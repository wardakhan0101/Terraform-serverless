locals {
  alarms = merge(
    { for name, fn in var.functions : "${name}-errors" => { namespace = "AWS/Lambda", metric = "Errors", statistic = "Sum", threshold = 1, dimensions = { FunctionName = var.functions[name].function_name } } },
    { for name, fn in var.functions : "${name}-throttles" => { namespace = "AWS/Lambda", metric = "Throttles", statistic = "Sum", threshold = 1, dimensions = { FunctionName = var.functions[name].function_name } } },
    {
      stream-age                 = { namespace = "AWS/Lambda", metric = "IteratorAge", statistic = "Maximum", threshold = 600000, dimensions = { FunctionName = var.functions["publisher"].function_name } }
      stream-destination-failure = { namespace = "AWS/Lambda", metric = "DestinationDeliveryFailures", statistic = "Sum", threshold = 1, dimensions = { FunctionName = var.functions["publisher"].function_name } }
      queue-age                  = { namespace = "AWS/SQS", metric = "ApproximateAgeOfOldestMessage", statistic = "Maximum", threshold = 300, dimensions = { QueueName = var.data.queues.events.name } }
      queue-depth                = { namespace = "AWS/SQS", metric = "ApproximateNumberOfMessagesVisible", statistic = "Maximum", threshold = 1000, dimensions = { QueueName = var.data.queues.events.name } }
      dlq-depth                  = { namespace = "AWS/SQS", metric = "ApproximateNumberOfMessagesVisible", statistic = "Maximum", threshold = 1, dimensions = { QueueName = var.data.queues.dlq.name } }
      api-errors                 = { namespace = "AWS/ApiGateway", metric = "5XXError", statistic = "Sum", threshold = 5, dimensions = { ApiName = var.api.name, Stage = var.api.stage_name } }
      api-latency                = { namespace = "AWS/ApiGateway", metric = "Latency", statistic = "Average", threshold = 2000, dimensions = { ApiName = var.api.name, Stage = var.api.stage_name } }
      alb-errors                 = { namespace = "AWS/ApplicationELB", metric = "HTTPCode_ELB_5XX_Count", statistic = "Sum", threshold = 5, dimensions = { LoadBalancer = var.alb.arn_suffix } }
    },
    { for key, table in var.data.tables : "${key}-throttles" => { namespace = "AWS/DynamoDB", metric = "ThrottledRequests", statistic = "Sum", threshold = 1, dimensions = { TableName = table.name, Operation = "PutItem" } } },
    { for key, service in var.services : "${key}-cpu" => { namespace = "AWS/ECS", metric = "CPUUtilization", statistic = "Average", threshold = 85, dimensions = { ClusterName = var.cluster_name, ServiceName = service.service_name } } }
  )
}
resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = local.alarms
  alarm_name          = "${var.name}-${each.key}"
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = each.value.statistic
  dimensions          = each.value.dimensions
  period              = 60
  evaluation_periods  = 2
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alerts_arn]
  ok_actions          = [var.alerts_arn]
}
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = [for index, name in sort(keys(local.alarms)) : {
    type = "metric", x = (index % 3) * 8, y = floor(index / 3) * 6, width = 8, height = 6,
    properties = { title = name, region = var.region, stat = local.alarms[name].statistic, period = 60,
    metrics = [concat([local.alarms[name].namespace, local.alarms[name].metric], flatten([for key, value in local.alarms[name].dimensions : [key, value]]))] }
  }] })
}
