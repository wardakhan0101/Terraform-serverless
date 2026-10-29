resource "aws_ecs_cluster" "this" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
resource "aws_lb" "this" {
  name                       = var.name
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = var.network.subnet_ids
  security_groups            = [var.network.security_groups["alb"]]
  drop_invalid_header_fields = true
  enable_deletion_protection = true
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"detail\":\"Not found\"}"
      status_code  = "404"
    }
  }
}
locals {
  data_policies = {
    books = jsonencode({ Version = "2012-10-17", Statement = [
      { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:PutItem"], Resource = var.data.tables.books.arn },
      { Effect = "Allow", Action = "dynamodb:Query", Resource = "${var.data.tables.books.arn}/index/catalog" },
      { Effect = "Allow", Action = "elasticache:Connect", Resource = [var.data.cache_arn, var.data.cache_users.books.arn] }
    ] })
    reviews = jsonencode({ Version = "2012-10-17", Statement = [
      { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"], Resource = var.data.tables.reviews.arn },
      # Narrow read-only exception: verify immutable book existence, never write Books data.
      { Effect = "Allow", Action = "dynamodb:GetItem", Resource = var.data.tables.books.arn },
      { Effect = "Allow", Action = "elasticache:Connect", Resource = [var.data.cache_arn, var.data.cache_users.reviews.arn] }
    ] })
  }
}
module "services" {
  for_each               = { books = 10, reviews = 20 }
  source                 = "../ecs-service"
  name                   = var.name
  deployment_environment = var.environment
  service                = each.key
  region                 = var.region
  cluster_id             = aws_ecs_cluster.this.id
  cluster_name           = aws_ecs_cluster.this.name
  vpc_id                 = var.network.vpc_id
  subnet_ids             = var.network.subnet_ids
  security_group_id      = var.network.security_groups[each.key]
  listener_arn           = aws_lb_listener.http.arn
  load_balancer_suffix   = aws_lb.this.arn_suffix
  priority               = each.value
  image_digest           = lookup(var.image_digests, each.key, null)
  alerts_arn             = var.alerts_arn
  data_policy            = local.data_policies[each.key]
  environment = merge({
    BOOKS_TABLE = var.data.tables.books.name
    CACHE_HOST  = var.data.cache_host
    CACHE_GROUP = var.data.cache_group
    CACHE_USER  = var.data.cache_users[each.key].name
    }, each.key == "books" ? {
    AUTHOR_ISSUER    = "https://cognito-idp.${var.region}.amazonaws.com/${var.pools["author"].id}"
    AUTHOR_CLIENT_ID = var.pools["author"].client_id
    } : {
    REVIEWS_TABLE    = var.data.tables.reviews.name
    READER_ISSUER    = "https://cognito-idp.${var.region}.amazonaws.com/${var.pools["reader"].id}"
    READER_CLIENT_ID = var.pools["reader"].client_id
  })
}
