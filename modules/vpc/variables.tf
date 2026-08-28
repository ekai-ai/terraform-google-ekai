# variables.tf

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "env" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "GCP region (e.g. us-central1)"
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
