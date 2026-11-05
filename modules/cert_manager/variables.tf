variable "acme_email" {
  description = "Email address registered with Let's Encrypt for certificate expiry notifications."
  type        = string

  validation {
    condition     = var.acme_email != "" && var.acme_email != "REPLACE_ME" && can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.acme_email))
    error_message = "acme_email must be a real email address -- got empty, the literal placeholder \"REPLACE_ME\", or something that doesn't look like an email."
  }
}

variable "chart_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "1.15.0"
}

variable "env" {
  description = "Environment name (e.g. dev, staging, prod). Used to label resources."
  type        = string
}
