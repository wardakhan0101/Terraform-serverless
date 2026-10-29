locals { prefix = "${var.name}-${var.service}" }
resource "aws_ecr_repository" "this" {
  name                 = local.prefix
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  encryption_configuration { encryption_type = "AES256" }
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "Expire untagged build leftovers", selection = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 14 }, action = { type = "expire" } }] })
}
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.prefix}"
  retention_in_days = 30
}
resource "aws_iam_role" "task" {
  name               = "${local.prefix}-task"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy" "task" {
  role   = aws_iam_role.task.id
  policy = var.data_policy
}
resource "aws_iam_role" "execution" {
  name               = "${local.prefix}-execution"
  assume_role_policy = aws_iam_role.task.assume_role_policy
}
resource "aws_iam_role_policy" "execution" {
  role = aws_iam_role.execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = aws_ecr_repository.this.arn },
    { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.this.arn}:*" }
  ] })
}
resource "aws_ecs_task_definition" "this" {
  family                   = local.prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.execution.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name = var.service
    # Explicitly unresolved deployment prerequisite, NOT a fabricated digest.
    image                  = var.image_digest == null ? "${aws_ecr_repository.this.repository_url}:unpublished-local-build" : "${aws_ecr_repository.this.repository_url}@${var.image_digest}"
    essential              = true
    user                   = "10001"
    readonlyRootFilesystem = true
    linuxParameters        = { initProcessEnabled = true, capabilities = { drop = ["ALL"] } }
    portMappings           = [{ containerPort = 8080, protocol = "tcp" }]
    environment            = [for key, value in merge(var.environment, { SERVICE = var.service, AWS_REGION = var.region }) : { name = key, value = value }]
    logConfiguration       = { logDriver = "awslogs", options = { awslogs-group = aws_cloudwatch_log_group.this.name, awslogs-region = var.region, awslogs-stream-prefix = "app" } }
    healthCheck            = { command = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=2)\""], interval = 30, timeout = 5, retries = 3, startPeriod = 30 }
    stopTimeout            = 30
  }])
}
resource "aws_lb_target_group" "this" {
  for_each             = toset(["stable", "canary"])
  name                 = "br-${var.deployment_environment}-${var.service}-${each.key}"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}
resource "aws_lb_listener_rule" "this" {
  listener_arn = var.listener_arn
  priority     = var.priority
  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.this["stable"].arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.this["canary"].arn
        weight = 0
      }
    }
  }
  condition {
    path_pattern { values = ["/${var.service}", "/${var.service}/*", "/portfolio/${var.service}", "/portfolio/${var.service}/*"] }
  }
  # Native ECS controls weights during and after deployments, not Terraform.
  lifecycle { ignore_changes = [action] }
}
resource "aws_iam_role" "traffic" {
  name               = "${local.prefix}-traffic"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy" "traffic" {
  role = aws_iam_role.traffic.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["elasticloadbalancing:DescribeRules", "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetHealth"], Resource = "*" },
    { Effect = "Allow", Action = "elasticloadbalancing:ModifyRule", Resource = aws_lb_listener_rule.this.arn }
  ] })
}
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.prefix}-target-errors"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { TargetGroup = aws_lb_target_group.this["canary"].arn_suffix, LoadBalancer = var.load_balancer_suffix }
  alarm_actions       = [var.alerts_arn]
}
resource "aws_ecs_service" "this" {
  name                              = local.prefix
  cluster                           = var.cluster_id
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = 2
  launch_type                       = "FARGATE"
  platform_version                  = "1.4.0"
  availability_zone_rebalancing     = "ENABLED"
  health_check_grace_period_seconds = 60
  enable_execute_command            = false
  deployment_controller { type = "ECS" }
  deployment_configuration {
    strategy             = "CANARY"
    bake_time_in_minutes = 5
    canary_configuration {
      canary_percent              = 10
      canary_bake_time_in_minutes = 5
    }
  }
  alarms {
    enable      = true
    rollback    = true
    alarm_names = [aws_cloudwatch_metric_alarm.errors.alarm_name]
  }
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.this["stable"].arn
    container_name   = var.service
    container_port   = 8080
    advanced_configuration {
      alternate_target_group_arn = aws_lb_target_group.this["canary"].arn
      production_listener_rule   = aws_lb_listener_rule.this.arn
      role_arn                   = aws_iam_role.traffic.arn
    }
  }
  # Application Auto Scaling owns desired count; native ECS owns active target group.
  # Provider represents load_balancer as a set: individual members cannot be ignored.
  # The complete set is deployment-owned; inspect it in the documented drift review.
  lifecycle { ignore_changes = [desired_count, load_balancer] }
  depends_on = [aws_iam_role_policy.traffic, aws_iam_role_policy.task, aws_iam_role_policy.execution]
}
resource "aws_appautoscaling_target" "this" {
  min_capacity       = 2
  max_capacity       = 4
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.prefix}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = "ecs"
  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
    predefined_metric_specification { predefined_metric_type = "ECSServiceAverageCPUUtilization" }
  }
}
