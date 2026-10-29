locals {
  functions = {
    publisher  = { timeout = 60, memory = 256, concurrency = 4 }
    aggregator = { timeout = 30, memory = 256, concurrency = 10 }
    query      = { timeout = 20, memory = 256, concurrency = 10 }
  }
  function_statements = {
    publisher = [
      { Effect = "Allow", Action = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"], Resource = var.data.tables.reviews.stream_arn },
      { Effect = "Allow", Action = "dynamodb:ListStreams", Resource = "*" },
      { Effect = "Allow", Action = "sqs:SendMessage", Resource = var.data.queues.events.arn },
      { Effect = "Allow", Action = "s3:PutObject", Resource = "${var.data.buckets["failed-records"].arn}/*", Condition = { StringEquals = { "s3:ResourceAccount" = var.account_id } } },
      { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = var.data.buckets["failed-records"].arn }
    ]
    aggregator = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = var.data.queues.events.arn },
      { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:PutItem"], Resource = var.data.tables.stats.arn }
    ]
    query = [
      { Effect = "Allow", Action = "dynamodb:Query", Resource = "${var.data.tables.stats.arn}/index/top-rated" }
    ]
  }
}
resource "aws_cloudwatch_log_group" "functions" {
  for_each          = local.functions
  name              = "/aws/lambda/${var.name}-${each.key}"
  retention_in_days = 30
}
resource "aws_iam_role" "functions" {
  for_each           = local.functions
  name               = "${var.name}-${each.key}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy" "functions" {
  for_each = local.functions
  role     = aws_iam_role.functions[each.key].id
  policy = jsonencode({ Version = "2012-10-17", Statement = concat(local.function_statements[each.key], [
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.functions[each.key].arn}:*" }
  ]) })
}
resource "aws_lambda_function" "this" {
  for_each                       = local.functions
  function_name                  = "${var.name}-${each.key}"
  role                           = aws_iam_role.functions[each.key].arn
  handler                        = "backend.functions.${each.key}.handler"
  runtime                        = "python3.12"
  architectures                  = ["x86_64"]
  filename                       = "${var.artifacts_dir}/${each.key}.zip"
  source_code_hash               = filebase64sha256("${var.artifacts_dir}/${each.key}.zip")
  timeout                        = each.value.timeout
  memory_size                    = each.value.memory
  reserved_concurrent_executions = each.value.concurrency
  publish                        = true
  environment {
    variables = each.key == "publisher" ? { QUEUE_URL = var.data.queues.events.id } : { STATS_TABLE = var.data.tables.stats.name }
  }
  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }
  depends_on = [aws_iam_role_policy.functions, aws_cloudwatch_log_group.functions]
}
resource "aws_lambda_alias" "live" {
  for_each         = aws_lambda_function.this
  name             = "live"
  function_name    = each.value.function_name
  function_version = each.value.version
}
resource "aws_lambda_event_source_mapping" "stream" {
  event_source_arn                   = var.data.tables.reviews.stream_arn
  function_name                      = aws_lambda_alias.live["publisher"].arn
  starting_position                  = "TRIM_HORIZON"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 300
  maximum_retry_attempts             = 5
  maximum_record_age_in_seconds      = 21600
  bisect_batch_on_function_error     = true
  parallelization_factor             = 1
  function_response_types            = ["ReportBatchItemFailures"]
  filter_criteria {
    filter { pattern = jsonencode({ eventName = ["INSERT"], dynamodb = { NewImage = { kind = { S = ["review"] } } } }) }
  }
  destination_config {
    on_failure { destination_arn = var.data.buckets["failed-records"].arn }
  }
  depends_on = [aws_iam_role_policy.functions]
}
resource "aws_lambda_event_source_mapping" "queue" {
  event_source_arn        = var.data.queues.events.arn
  function_name           = aws_lambda_alias.live["aggregator"].arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
  scaling_config { maximum_concurrency = 10 }
  depends_on = [aws_iam_role_policy.functions]
}
