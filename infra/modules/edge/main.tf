resource "aws_cloudfront_origin_access_control" "this" {
  name                              = var.name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
data "aws_cloudfront_cache_policy" "disabled" { name = "Managed-CachingDisabled" }
data "aws_cloudfront_cache_policy" "static" { name = "Managed-CachingOptimized" }
data "aws_cloudfront_origin_request_policy" "api" { name = "Managed-AllViewerExceptHostHeader" }
resource "aws_cloudfront_cache_policy" "discover" {
  name        = "${var.name}-discover"
  default_ttl = 600
  min_ttl     = 0
  max_ttl     = 600
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "all" }
  }
}
resource "aws_cloudfront_response_headers_policy" "security" {
  name = var.name
  security_headers_config {
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
    }
    content_security_policy {
      content_security_policy = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self' https://cognito-idp.us-west-2.amazonaws.com; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
      override                = true
    }
  }
}
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  comment             = "Portfolio frontend and same-origin API; Discover cached for 600 seconds"
  origin {
    origin_id                = "frontend"
    domain_name              = var.buckets.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }
  origin {
    origin_id   = "api"
    domain_name = "${var.api.id}.execute-api.${var.region}.amazonaws.com"
    origin_path = "/${var.api.stage_name}"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  default_cache_behavior {
    target_origin_id           = "frontend"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.static.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }
  ordered_cache_behavior {
    path_pattern               = "/config.json"
    target_origin_id           = "frontend"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    viewer_protocol_policy     = "https-only"
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }
  ordered_cache_behavior {
    path_pattern               = "/discover"
    target_origin_id           = "api"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    viewer_protocol_policy     = "https-only"
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.discover.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }
  dynamic "ordered_cache_behavior" {
    for_each = ["/books", "/books/*", "/reviews/*"]
    content {
      path_pattern               = ordered_cache_behavior.value
      target_origin_id           = "api"
      allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods             = ["GET", "HEAD"]
      viewer_protocol_policy     = "https-only"
      compress                   = true
      cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
      origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.api.id
      response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
}
resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.buckets.frontend.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Principal = { Service = "cloudfront.amazonaws.com" }, Action = "s3:GetObject", Resource = "${var.buckets.frontend.arn}/*", Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.this.arn } } },
    { Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [var.buckets.frontend.arn, "${var.buckets.frontend.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }
  ] })
}
locals {
  frontend_dist = var.frontend_dist
  content_types = { html = "text/html", js = "application/javascript", css = "text/css", svg = "image/svg+xml", json = "application/json", ico = "image/x-icon" }
}
resource "aws_s3_object" "frontend" {
  for_each      = fileset(local.frontend_dist, "**")
  bucket        = var.buckets.frontend.id
  key           = each.value
  source        = "${local.frontend_dist}/${each.value}"
  source_hash   = filemd5("${local.frontend_dist}/${each.value}")
  content_type  = lookup(local.content_types, reverse(split(".", each.value))[0], "application/octet-stream")
  cache_control = each.value == "index.html" ? "no-cache" : "public, max-age=31536000, immutable"
}
resource "aws_s3_object" "config" {
  bucket        = var.buckets.frontend.id
  key           = "config.json"
  content_type  = "application/json"
  cache_control = "no-store"
  content = jsonencode({
    region  = var.region
    apiBase = ""
    pools   = { for role, pool in var.pools : role => { poolId = pool.id, clientId = pool.client_id } }
  })
}
