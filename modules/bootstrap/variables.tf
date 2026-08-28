# variables.tf

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (e.g. us-central1)"
  type        = string
}

variable "env" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "vpc_name" {
  description = "Base name for the VPC (prefixed with env)"
  type        = string
  default     = "vpc"
}

variable "subnet_cidr" {
  description = "Primary CIDR for the private subnet"
  type        = string
}

variable "pods_cidr" {
  description = "Secondary CIDR for GKE pods"
  type        = string
}

variable "services_cidr" {
  description = "Secondary CIDR for GKE services"
  type        = string
}

variable "dns_zone" {
  description = "DNS zone domain name (e.g. dev.example.com)"
  type        = string
}

variable "manage_dns_zone" {
  description = "When true, create the Cloud DNS managed zone; when false, look up an existing zone"
  type        = bool
  default     = true
}

variable "state_bucket_name" {
  description = "Globally unique name for the GCS bucket that stores Terraform state"
  type        = string
}
