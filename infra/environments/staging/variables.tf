variable "image_digests" {
  description = "Actual published digests if available. Empty map deliberately plans unpublished-local-build references; nothing is deployed."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for key, value in var.image_digests : contains(["books", "reviews"], key) && can(regex("^sha256:[a-f0-9]{64}$", value))])
    error_message = "Only books/reviews with actual sha256 manifest digests are supported."
  }
}

variable "operator_email" {
  description = "Optional future alert subscriber; planning never sends email."
  type        = string
  default     = null
}
