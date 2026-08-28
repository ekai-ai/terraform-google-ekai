variable "project_id" {
  description = "GCP project ID that owns the cluster and Secret Manager secrets."
  type        = string
}

variable "region" {
  description = "GCP region of the GKE cluster (e.g. us-central1). Used in the ClusterSecretStore workloadIdentity spec."
  type        = string
}

variable "env" {
  description = "Environment name (e.g. dev, staging, prod). Used to name the GSA: eso-{env}."
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Required by the ClusterSecretStore workloadIdentity auth block."
  type        = string
}

variable "chart_version" {
  description = "ESO Helm chart version."
  type        = string
  default     = "0.10.3"
}
