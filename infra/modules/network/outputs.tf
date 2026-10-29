output "vpc_id" { value = aws_vpc.this.id }

output "subnet_ids" { value = [for subnet in aws_subnet.private : subnet.id] }

output "security_groups" { value = { for key, sg in aws_security_group.this : key => sg.id } }
