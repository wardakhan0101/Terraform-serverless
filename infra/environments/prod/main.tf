module "network" {
  source     = "../../modules/network"
  name       = local.name
  region     = local.region
  account_id = local.account
}
module "data" {
  source               = "../../modules/data"
  name                 = local.name
  account_id           = local.account
  subnet_ids           = module.network.subnet_ids
  cache_security_group = module.network.security_groups["cache"]
}
module "identity" {
  source = "../../modules/identity"
  name   = local.name
}
module "alerts" {
  source         = "../../modules/alerts"
  name           = local.name
  region         = local.region
  account_id     = local.account
  operator_email = var.operator_email
}
module "compute" {
  source        = "../../modules/compute"
  name          = local.name
  environment   = local.environment
  region        = local.region
  network       = module.network
  data          = module.data
  pools         = module.identity.pools
  alerts_arn    = module.alerts.topic_arn
  image_digests = var.image_digests
}
module "functions" {
  source        = "../../modules/functions"
  name          = local.name
  account_id    = local.account
  data          = module.data
  artifacts_dir = "${path.root}/../../../.local/artifacts"
}
module "api" {
  source  = "../../modules/api"
  name    = local.name
  network = module.network
  pools   = module.identity.pools
  alb     = module.compute.alb
  query   = module.functions.query
}
module "edge" {
  source        = "../../modules/edge"
  name          = local.name
  region        = local.region
  buckets       = module.data.buckets
  api           = module.api.api
  pools         = module.identity.pools
  frontend_dist = "${path.root}/../../../frontend/dist"
}
module "monitoring" {
  source       = "../../modules/monitoring"
  name         = local.name
  region       = local.region
  functions    = module.functions.functions
  data         = module.data
  api          = module.api.api
  alb          = module.compute.alb
  services     = module.compute.services
  cluster_name = module.compute.cluster_name
  alerts_arn   = module.alerts.topic_arn
}
