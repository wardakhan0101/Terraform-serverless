output "alb" { value = { arn = aws_lb.this.arn, dns_name = aws_lb.this.dns_name, arn_suffix = aws_lb.this.arn_suffix } }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "services" { value = { for k, v in module.services : k => { service_name = v.service_name, repository_url = v.repository_url } } }
