output "tables" {
  value = {
    books   = { name = aws_dynamodb_table.books.name, arn = aws_dynamodb_table.books.arn }
    reviews = { name = aws_dynamodb_table.reviews.name, arn = aws_dynamodb_table.reviews.arn, stream_arn = aws_dynamodb_table.reviews.stream_arn }
    stats   = { name = aws_dynamodb_table.stats.name, arn = aws_dynamodb_table.stats.arn }
  }
}

output "queues" { value = { events = aws_sqs_queue.events, dlq = aws_sqs_queue.dlq } }

output "buckets" {
  value = { for key, bucket in aws_s3_bucket.this : key => {
    id                          = bucket.id
    arn                         = bucket.arn
    bucket_regional_domain_name = bucket.bucket_regional_domain_name
  } }
}

output "cache_host" { value = aws_elasticache_replication_group.this.primary_endpoint_address }

output "cache_arn" { value = aws_elasticache_replication_group.this.arn }

output "cache_group" { value = aws_elasticache_replication_group.this.replication_group_id }

output "cache_users" { value = { for key, user in aws_elasticache_user.service : key => { arn = user.arn, name = user.user_name } } }
