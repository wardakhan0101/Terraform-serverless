terraform {
  required_version = "~> 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.70.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
  backend "local" {
    path = "../../../.local/prod.tfstate"
  }
}

provider "aws" {
  # Intentionally fixed: never fall back to another profile/account.
  profile             = "poc-personal"
  region              = "us-west-2"
  allowed_account_ids = ["495278513214"]
  default_tags {
    tags = {
      Project     = "book-review"
      Environment = "prod"
      Owner       = "portfolio-owner"
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name        = "book-review-prod"
  environment = "prod"
  region      = "us-west-2"
  account     = "495278513214"
}
