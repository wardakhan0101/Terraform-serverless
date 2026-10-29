variable "name" { type = string }
variable "account_id" { type = string }
variable "region" { type = string }
variable "operator_email" {
  description = "Optional future alert subscriber; planning never sends email."
  type        = string
  default     = null
}
