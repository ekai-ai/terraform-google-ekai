variable "acme_email" {
  description = "Email address registered with Let's Encrypt for certificate expiry notifications."
  type        = string
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
