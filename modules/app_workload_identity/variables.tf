variable "project_id" {
  description = "GCP project ID that owns all resources. Used in GSA emails, IAM bindings, and Workload Identity pool names."
  type        = string
}

variable "env" {
  description = "Environment name (e.g. dev, staging, prod). Prefixes GSA account IDs and secret name conditions."
  type        = string
}

variable "ekai_namespace" {
  description = "Kubernetes namespace where service pods run (e.g. ekai-saas). Used in the Workload Identity member string and kubernetes_service_account namespace."
  type        = string
}

variable "pipelines" {
  description = <<-EOT
    Map of service pipeline definitions — the same map passed to modules/cloud_build.
    Only the map keys (service names) are consumed by this module; the object
    attributes are carried along so callers can share one variable across modules.
  EOT
  type = map(object({
    branch          = string
    github_repo     = string
    dockerfile      = optional(string, "Dockerfile")
    manifest_folder = optional(string, "manifest-files")
    manifest_file   = string
    ingresshost     = optional(string, "")
  }))
  default = {}
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Reserved for future use (e.g. data sources, cluster-scoped conditions). Not consumed directly by current resources."
  type        = string
}
