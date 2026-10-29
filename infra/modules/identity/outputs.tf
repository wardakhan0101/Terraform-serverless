output "pools" { value = { for k, p in aws_cognito_user_pool.this : k => { id = p.id, arn = p.arn, client_id = aws_cognito_user_pool_client.this[k].id } } }
