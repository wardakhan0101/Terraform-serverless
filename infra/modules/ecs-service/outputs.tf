output "repository_url" { value = aws_ecr_repository.this.repository_url }

output "service_name" { value = aws_ecs_service.this.name }

output "target_groups" { value = { for key, tg in aws_lb_target_group.this : key => tg.arn_suffix } }
