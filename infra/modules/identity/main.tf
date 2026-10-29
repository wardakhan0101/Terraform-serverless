resource "aws_cognito_user_pool" "this" {
  for_each                 = toset(["author", "reader"])
  name                     = "${var.name}-${each.key}s"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = "ACTIVE"
  mfa_configuration        = "OPTIONAL"
  software_token_mfa_configuration { enabled = true }
  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  username_configuration { case_sensitive = false }
  admin_create_user_config { allow_admin_create_user_only = false }
}
resource "aws_cognito_user_pool_client" "this" {
  for_each                      = aws_cognito_user_pool.this
  name                          = "${var.name}-${each.key}-web"
  user_pool_id                  = each.value.id
  generate_secret               = false
  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
  access_token_validity         = 60
  id_token_validity             = 60
  refresh_token_validity        = 1
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
  read_attributes  = ["email", "email_verified", "sub"]
  write_attributes = ["email"]
}
