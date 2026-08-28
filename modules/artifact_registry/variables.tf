variable "project_id" {
  description = "GCP project ID that owns the repositories."
  type        = string
}

variable "region" {
  description = "GCP region where repositories are created (e.g. us-central1)."
  type        = string
}

variable "env" {
  description = "Deployment environment name used as a repository-ID prefix (e.g. dev, staging, prod)."
  type        = string
}

variable "services" {
  description = "Map of logical service names. Keys become the repository-ID suffix: <env>-<service>."
  type        = map(any)
  # example:
  # services = {
  #   api     = {}
  #   worker  = {}
  #   frontend = {}
  # }
}

variable "gke_node_sa_email" {
  description = "Email of the GKE node service account that needs pull (reader) access."
  type        = string
}

variable "cloudbuild_sa_email" {
  description = "Email of the Cloud Build service account that needs push (writer) access."
  type        = string
}
