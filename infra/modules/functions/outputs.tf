output "functions" { value = { for k, v in aws_lambda_function.this : k => { function_name = v.function_name } } }
output "query" { value = { function_name = aws_lambda_function.this["query"].function_name, alias_name = aws_lambda_alias.live["query"].name, invoke_arn = aws_lambda_alias.live["query"].invoke_arn } }
