resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}
resource "aws_default_security_group" "this" { vpc_id = aws_vpc.this.id }
resource "aws_subnet" "private" {
  for_each          = { a = "10.0.10.0/24", b = "10.0.20.0/24" }
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = "${var.region}${each.key}"
  tags              = { Name = "${var.name}-private-${each.key}" }
}
resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.this.id
}
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
resource "aws_security_group" "this" {
  for_each    = toset(["vpclink", "alb", "books", "reviews", "cache", "endpoints"])
  name        = "${var.name}-${each.key}"
  description = "Isolated ${each.key} boundary; explicit rules only"
  vpc_id      = aws_vpc.this.id
}
locals {
  paths = {
    link_alb      = { source = "vpclink", destination = "alb", port = 80 }
    alb_books     = { source = "alb", destination = "books", port = 8080 }
    alb_reviews   = { source = "alb", destination = "reviews", port = 8080 }
    books_cache   = { source = "books", destination = "cache", port = 6379 }
    reviews_cache = { source = "reviews", destination = "cache", port = 6379 }
    books_https   = { source = "books", destination = "endpoints", port = 443 }
    reviews_https = { source = "reviews", destination = "endpoints", port = 443 }
  }
}
resource "aws_vpc_security_group_ingress_rule" "path" {
  for_each                     = local.paths
  security_group_id            = aws_security_group.this[each.value.destination].id
  referenced_security_group_id = aws_security_group.this[each.value.source].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
}
resource "aws_vpc_security_group_egress_rule" "path" {
  for_each                     = local.paths
  security_group_id            = aws_security_group.this[each.value.source].id
  referenced_security_group_id = aws_security_group.this[each.value.destination].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
}
resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(["ecr.api", "ecr.dkr", "logs"])
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
  security_group_ids  = [aws_security_group.this["endpoints"].id]
  private_dns_enabled = true
  policy              = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = "*", Action = "*", Resource = "*", Condition = { StringEquals = { "aws:PrincipalAccount" = var.account_id } } }] })
}
resource "aws_vpc_endpoint" "gateway" {
  for_each          = toset(["s3", "dynamodb"])
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
  # ECR layer downloads use an AWS-owned S3 bucket, so do not restrict it to our account.
  policy = each.key == "s3" ? jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = "*", Action = "s3:GetObject", Resource = "arn:aws:s3:::prod-${var.region}-starport-layer-bucket/*" }] }) : jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = "*", Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:TransactWriteItems"], Resource = "arn:aws:dynamodb:${var.region}:${var.account_id}:table/${var.name}-*" }] })
}
resource "aws_vpc_security_group_egress_rule" "gateway" {
  for_each          = { for pair in setproduct(["books", "reviews"], ["s3", "dynamodb"]) : join("-", pair) => pair }
  security_group_id = aws_security_group.this[each.value[0]].id
  prefix_list_id    = aws_vpc_endpoint.gateway[each.value[1]].prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
