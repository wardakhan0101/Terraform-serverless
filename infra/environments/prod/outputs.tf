output "planning_identity" {
  value = { profile = "poc-personal", account = data.aws_caller_identity.current.account_id, region = local.region }
}
output "frontend_url" { value = module.edge.frontend_url }
output "api_url" { value = module.api.api.invoke_url }
output "image_repositories" { value = { for name, service in module.compute.services : name => service.repository_url } }
output "artifact_readiness" {
  value = { for name in ["books", "reviews"] : name => contains(keys(var.image_digests), name) ? "Digest supplied; registry presence not verified" : "UNPUBLISHED: local build must be published later; not deployment-ready" }
}
output "alert_readiness" { value = var.operator_email == null ? "No subscriber configured; notifications unverified" : "Subscriber planned; confirmation and delivery unverified" }
output "cognito" { value = { for role, pool in module.identity.pools : role => { pool_id = pool.id, client_id = pool.client_id } } }
