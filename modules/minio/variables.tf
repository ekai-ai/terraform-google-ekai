variable "minio_namespace" {
  type    = string
  default = "minio"
}

variable "chart_version" {
  type    = string
  default = "14.8.5"
}

variable "image_tag" {
  type    = string
  default = "2024.11.7-debian-12-r0"
}

variable "client_image_tag" {
  type    = string
  default = "2024.11.13-debian-12-r1"
}

variable "mode" {
  description = "distributed or standalone"
  type        = string
  default     = "standalone"
}

variable "replicas" {
  type    = number
  default = 1
}

variable "persistence_size" {
  type    = string
  default = "20Gi"
}

variable "storage_class" {
  description = "GKE storage class (standard, premium-rwo, etc.)"
  type        = string
  default     = "standard-rwo"
}

variable "default_buckets" {
  type    = list(string)
  default = ["ekai-files"]
}

variable "minio_host" {
  description = "MinIO API hostname e.g. minio.demo.ekai.ai"
  type        = string
}

variable "minio_console_host" {
  description = "MinIO console hostname. Defaults to console.<minio_host> if empty."
  type        = string
  default     = ""
}

variable "tls_secret_name" {
  description = "K8s TLS Secret name (created by cert-manager)"
  type        = string
  default     = "wildcard-tls"
}
