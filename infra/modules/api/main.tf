resource "aws_apigatewayv2_vpc_link" "this" {
  name               = var.name
  subnet_ids         = var.network.subnet_ids
  security_group_ids = [var.network.security_groups["vpclink"]]
}
resource "aws_api_gateway_rest_api" "this" {
  name = var.name
  endpoint_configuration { types = ["REGIONAL"] }
  minimum_compression_size = 1024
}
resource "aws_api_gateway_authorizer" "this" {
  for_each                       = var.pools
  name                           = "${each.key}-pool"
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  type                           = "COGNITO_USER_POOLS"
  provider_arns                  = [each.value.arn]
  identity_source                = "method.request.header.Authorization"
  identity_validation_expression = "^${var.pools[each.key].client_id}$"
}
resource "aws_api_gateway_resource" "root" {
  for_each    = toset(["books", "reviews", "discover"])
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = each.key
}
resource "aws_api_gateway_resource" "book_id" {
  for_each    = toset(["books", "reviews"])
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.root[each.key].id
  path_part   = "{bookId}"
}
locals {
  routes = {
    books_list     = { resource = aws_api_gateway_resource.root["books"].id, method = "GET", path = "/books", role = null, parameter = false }
    books_create   = { resource = aws_api_gateway_resource.root["books"].id, method = "POST", path = "/books", role = "author", parameter = false }
    books_get      = { resource = aws_api_gateway_resource.book_id["books"].id, method = "GET", path = "/books/{bookId}", role = null, parameter = true }
    reviews_list   = { resource = aws_api_gateway_resource.book_id["reviews"].id, method = "GET", path = "/reviews/{bookId}", role = null, parameter = true }
    reviews_create = { resource = aws_api_gateway_resource.book_id["reviews"].id, method = "POST", path = "/reviews/{bookId}", role = "reader", parameter = true }
  }
}
resource "aws_api_gateway_method" "service" {
  for_each           = local.routes
  rest_api_id        = aws_api_gateway_rest_api.this.id
  resource_id        = each.value.resource
  http_method        = each.value.method
  authorization      = each.value.role == null ? "NONE" : "COGNITO_USER_POOLS"
  authorizer_id      = each.value.role == null ? null : aws_api_gateway_authorizer.this[each.value.role].id
  request_parameters = each.value.parameter ? { "method.request.path.bookId" = true } : {}
}
resource "aws_api_gateway_integration" "service" {
  for_each                = local.routes
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = each.value.resource
  http_method             = aws_api_gateway_method.service[each.key].http_method
  integration_http_method = each.value.method
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = aws_apigatewayv2_vpc_link.this.id
  integration_target      = var.alb.arn
  uri                     = "http://${var.alb.dns_name}${each.value.path}"
  timeout_milliseconds    = 25000
  request_parameters = merge(
    each.value.parameter ? { "integration.request.path.bookId" = "method.request.path.bookId" } : {},
    each.value.role == null ? {} : {
      "integration.request.header.X-Identity-Sub"      = "context.authorizer.claims.sub"
      "integration.request.header.X-Identity-Issuer"   = "context.authorizer.claims.iss"
      "integration.request.header.X-Identity-Audience" = "context.authorizer.claims.aud"
    }
  )
}
resource "aws_api_gateway_method" "discover" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.root["discover"].id
  http_method   = "GET"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "discover" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.root["discover"].id
  http_method             = aws_api_gateway_method.discover.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.query.invoke_arn
}
resource "aws_lambda_permission" "api" {
  statement_id  = "DiscoverFromApi"
  action        = "lambda:InvokeFunction"
  function_name = var.query.function_name
  qualifier     = var.query.alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/GET/discover"
}
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  triggers = {
    redeployment = sha1(jsonencode({
      methods      = aws_api_gateway_method.service
      integrations = aws_api_gateway_integration.service
      discover     = aws_api_gateway_integration.discover
      authorizers  = aws_api_gateway_authorizer.this
    }))
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_cloudwatch_log_group" "api" {
  name              = "/apigateway/${var.name}"
  retention_in_days = 30
}
resource "aws_api_gateway_stage" "this" {
  rest_api_id           = aws_api_gateway_rest_api.this.id
  deployment_id         = aws_api_gateway_deployment.this.id
  stage_name            = "portfolio"
  cache_cluster_enabled = false
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format          = jsonencode({ requestId = "$context.requestId", method = "$context.httpMethod", resource = "$context.resourcePath", status = "$context.status", latency = "$context.responseLatency", integrationStatus = "$context.integration.status" })
  }
}
resource "aws_api_gateway_method_settings" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"
  settings {
    metrics_enabled        = true
    data_trace_enabled     = false
    throttling_burst_limit = 50
    throttling_rate_limit  = 25
    caching_enabled        = false
  }
}
