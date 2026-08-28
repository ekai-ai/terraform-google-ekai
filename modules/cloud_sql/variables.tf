variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region where the Cloud SQL instance is created."
  type        = string
}

variable "env" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
}

variable "vpc_name" {
  description = "Name of the existing VPC network to peer with Cloud SQL."
  type        = string
}

variable "secrets_name" {
  description = "Name of the Secret Manager secret that holds DB credentials JSON. Ignored when self_service = true."
  type        = string
  default     = ""
}

variable "self_service" {
  description = "true for cicd_provider = \"none\" — generates backend/semantics DB credentials directly instead of requiring a pre-existing Secret Manager secret."
  type        = bool
  default     = false
}

variable "instance_tier" {
  description = "Cloud SQL machine type (e.g. db-custom-2-7680, db-g1-small)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "db_version" {
  description = "PostgreSQL major version number used in the instance name and database_version (e.g. 15)."
  type        = string
  default     = "15"
}
