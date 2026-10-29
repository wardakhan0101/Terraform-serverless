variable "name" { type = string }

variable "account_id" { type = string }

variable "subnet_ids" { type = list(string) }

variable "cache_security_group" { type = string }
