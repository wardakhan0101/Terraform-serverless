resource "aws_dynamodb_table" "books" {
  name                        = "${var.name}-books"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "PK"
  range_key                   = "SK"
  deletion_protection_enabled = true
  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  attribute {
    name = "CatalogPK"
    type = "S"
  }
  attribute {
    name = "CatalogSK"
    type = "S"
  }
  global_secondary_index {
    name = "catalog"
    key_schema {
      attribute_name = "CatalogPK"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "CatalogSK"
      key_type       = "RANGE"
    }
    projection_type = "ALL"
  }
  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
}
resource "aws_dynamodb_table" "reviews" {
  name                        = "${var.name}-reviews"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "PK"
  range_key                   = "SK"
  deletion_protection_enabled = true
  stream_enabled              = true
  stream_view_type            = "NEW_IMAGE"
  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
}
resource "aws_dynamodb_table" "stats" {
  name                        = "${var.name}-stats"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "BookID"
  range_key                   = "SK"
  deletion_protection_enabled = true
  attribute {
    name = "BookID"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  attribute {
    name = "TopPK"
    type = "S"
  }
  attribute {
    name = "averageRating"
    type = "N"
  }
  global_secondary_index {
    name = "top-rated"
    key_schema {
      attribute_name = "TopPK"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "averageRating"
      key_type       = "RANGE"
    }
    projection_type = "ALL"
  }
  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
  # Event markers deliberately have no TTL: replay remains idempotent indefinitely.
}
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-reviews-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue" "events" {
  name                        = "${var.name}-reviews.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"
  visibility_timeout_seconds  = 180
  message_retention_seconds   = 1209600
  receive_wait_time_seconds   = 20
  sqs_managed_sse_enabled     = true
  redrive_policy              = jsonencode({ deadLetterTargetArn = aws_sqs_queue.dlq.arn, maxReceiveCount = 5 })
}
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url            = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({ redrivePermission = "byQueue", sourceQueueArns = [aws_sqs_queue.events.arn] })
}
resource "aws_sqs_queue_policy" "tls" {
  for_each  = { events = aws_sqs_queue.events, dlq = aws_sqs_queue.dlq }
  queue_url = each.value.id
  policy    = jsonencode({ Version = "2012-10-17", Statement = [{ Sid = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "sqs:*", Resource = each.value.arn, Condition = { Bool = { "aws:SecureTransport" = "false" } } }] })
}
resource "aws_s3_bucket" "this" {
  for_each      = toset(["frontend", "failed-records", "artifacts"])
  bucket        = "${var.name}-${var.account_id}-${each.key}"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "tls" {
  for_each = { for k, b in aws_s3_bucket.this : k => b if k != "frontend" }
  bucket   = each.value.id
  policy   = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [each.value.arn, "${each.value.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }] })
}
resource "aws_s3_bucket_lifecycle_configuration" "retention" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    id     = "old-versions-and-multipart"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = each.key == "failed-records" ? 365 : 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
  depends_on = [aws_s3_bucket_versioning.this]
}
resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}
resource "aws_elasticache_user" "default" {
  user_id       = "${var.name}-disabled-default"
  user_name     = "default"
  engine        = "valkey"
  access_string = "off ~* -@all"
  authentication_mode { type = "no-password-required" }
}
resource "aws_elasticache_user" "service" {
  for_each      = { books = "book:*", reviews = "reviews:*" }
  user_id       = "${var.name}-${each.key}"
  user_name     = "${var.name}-${each.key}"
  engine        = "valkey"
  access_string = "on ~${each.value} -@all +get +setex +ping"
  authentication_mode { type = "iam" }
}
resource "aws_elasticache_user_group" "this" {
  user_group_id = var.name
  engine        = "valkey"
  user_ids      = concat([aws_elasticache_user.default.user_id], [for user in aws_elasticache_user.service : user.user_id])
}
resource "aws_elasticache_replication_group" "this" {
  replication_group_id        = var.name
  description                 = "Small two-AZ Valkey cache; non-authoritative data"
  engine                      = "valkey"
  engine_version              = "8.0"
  node_type                   = "cache.t4g.micro"
  num_cache_clusters          = 2
  automatic_failover_enabled  = true
  multi_az_enabled            = true
  preferred_cache_cluster_azs = ["us-west-2a", "us-west-2b"]
  port                        = 6379
  subnet_group_name           = aws_elasticache_subnet_group.this.name
  security_group_ids          = [var.cache_security_group]
  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = true
  transit_encryption_mode     = "required"
  user_group_ids              = [aws_elasticache_user_group.this.id]
  snapshot_retention_limit    = 1
  auto_minor_version_upgrade  = true
}
