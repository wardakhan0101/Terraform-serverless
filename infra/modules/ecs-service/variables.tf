variable "name" { type = string }

variable "service" { type = string }

variable "cluster_id" { type = string }

variable "cluster_name" { type = string }

variable "vpc_id" { type = string }

variable "subnet_ids" { type = list(string) }

variable "security_group_id" { type = string }

variable "listener_arn" { type = string }

variable "load_balancer_suffix" { type = string }

variable "priority" { type = number }

variable "region" { type = string }

variable "environment" { type = map(string) }

variable "data_policy" { type = string }

variable "alerts_arn" { type = string }

variable "image_digest" {
  type     = string
  default  = null
  nullable = true
  validation {
    condition     = var.image_digest == null ? true : can(regex("^sha256:[a-f0-9]{64}$", var.image_digest))
    error_message = "Image digest must be an actual SHA256 image manifest digest, or null for undeployed plan-only reference."
  }
}

variable "deployment_environment" { type = string }
