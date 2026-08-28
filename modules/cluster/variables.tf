###############################################################################
# cluster submodule — Variables
###############################################################################

# ---------------------------------------------------------------------------
# Core identity
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID that owns all resources in this layer."
  type        = string
}

variable "region" {
  description = "GCP region for the cluster and related resources (e.g. us-central1)."
  type        = string
}

variable "env" {
  description = "Deployment environment label applied to all resources (e.g. dev, staging, prod)."
  type        = string
}

# ---------------------------------------------------------------------------
# Formerly read via `data "terraform_remote_state" "bootstrap"` ─────────────
# Wired automatically from module.bootstrap's outputs by the root module
# (see ../../main.tf) — nothing to set in tfvars for these.
# ---------------------------------------------------------------------------

variable "vpc_name" {
  description = "VPC name (sourced from the bootstrap submodule's output)."
  type        = string
}

variable "subnet_name" {
  description = "Private subnet name (sourced from the bootstrap submodule's output)."
  type        = string
}

variable "pods_range_name" {
  description = "Secondary IP range name for GKE pods (sourced from the bootstrap submodule's output)."
  type        = string
}

variable "services_range_name" {
  description = "Secondary IP range name for GKE services (sourced from the bootstrap submodule's output)."
  type        = string
}

# ---------------------------------------------------------------------------
# GKE cluster
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
}

variable "node_machine_type" {
  description = "Compute Engine machine type for cluster nodes (e.g. e2-standard-4)."
  type        = string
  default     = "e2-standard-4"
}

variable "min_nodes" {
  description = "Minimum number of nodes per zone in the node pool."
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum number of nodes per zone in the node pool."
  type        = number
  default     = 5
}

variable "k8s_version" {
  description = "Kubernetes version prefix for the cluster (e.g. 1.35). Leave empty to let GKE pick the latest stable version."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Secrets / credentials
# ---------------------------------------------------------------------------

variable "secrets_name" {
  description = "Name of the Secret Manager secret containing DB credentials JSON. Ignored when cicd_provider = \"none\" (self-service generates its own DB credentials instead)."
  type        = string
  default     = ""
}

variable "cicd_provider" {
  description = "CI/CD provider: \"cloud_build\", \"github_actions\", or \"none\" (self-service — no CI/CD, no master secret, Terraform generates DB/Redis/Neo4j/ArgoCD credentials directly)."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["cloud_build", "github_actions", "none"], var.cicd_provider)
    error_message = "cicd_provider must be one of: cloud_build, github_actions, none."
  }
}

# ---------------------------------------------------------------------------
# Cloud SQL
# ---------------------------------------------------------------------------

variable "db_instance_tier" {
  description = "Cloud SQL machine type (e.g. db-custom-2-7680)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "db_version" {
  description = "PostgreSQL major version used in the instance name and database_version (e.g. 15)."
  type        = string
  default     = "15"
}

# ---------------------------------------------------------------------------
# CI/CD pipelines — Artifact Registry
# ---------------------------------------------------------------------------

variable "pipelines" {
  description = <<-EOT
    Map of logical service names to pipeline metadata.
    Keys are used as Artifact Registry repository-ID suffixes (<env>-<key>).
    Values are arbitrary metadata objects (may be empty maps {}).
    Example:
      pipelines = {
        api      = {}
        worker   = {}
        frontend = {}
      }
  EOT
  type        = map(any)
  default     = {}
}

# ---------------------------------------------------------------------------
# Cloud Build service account (for Artifact Registry writer IAM)
# ---------------------------------------------------------------------------

variable "cloudbuild_sa_email" {
  description = "Cloud Build SA email for Artifact Registry writer access. Leave empty to auto-compute from project number: <number>@cloudbuild.gserviceaccount.com."
  type        = string
  default     = ""
}

variable "master_ipv4_cidr_block" {
  description = "CIDR for the GKE control plane private endpoint (/28). Must not overlap with VPC or subnet CIDRs. Default: 172.16.0.0/28."
  type        = string
  default     = "172.16.0.0/28"
}
