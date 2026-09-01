# ──────────────────────────────────────────────────────────────────────────────
# examples/self-deploy/cicd/variables.tf — mirrors ../../../cicd/variables.tf
# 1:1, same names/types/defaults/descriptions. This is the file that actually
# receives `-var-file=env/<env>.tfvars`; main.tf here just passes every one
# of these straight through to `module "cicd" { source = "../../../cicd" }`
# as X = var.X. See ../../../cicd/variables.tf for the full original
# commentary this mirrors — not repeated here to avoid the two copies
# drifting out of sync in wording while still needing to stay in sync in
# substance.
# ──────────────────────────────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID that owns all resources."
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the GCS bucket holding the combined root's Terraform state. Optional -- leave unset and this defaults to ekai-terraform-state-<env>-<project_id>, matching scripts/init-state-backend.sh's own default. Must match whatever state_bucket_name (or its default) the combined root actually used."
  type        = string
  default     = ""
}

variable "region" {
  description = "GCP region (e.g. us-central1)."
  type        = string
}

variable "env" {
  description = "Environment name (e.g. dev, staging, prod)."
  type        = string
}

variable "secrets_name" {
  description = "Secret Manager secret name containing a JSON blob with github_token, github_username, github_email, and argocd_admin_password keys. Ignored when cicd_provider = \"none\"."
  type        = string
  default     = ""
}

variable "dns_zone" {
  description = "Base DNS zone for this environment (e.g. customer.ekai.ai) (cicd_provider = \"none\" only) — used to derive service hostnames and FRONTEND_URL."
  type        = string
  default     = ""
}

variable "existing_image_registry_base_url" {
  description = "Container registry base URL the ekai-saas chart pulls app images from (cicd_provider = \"none\" only), e.g. \"public.ecr.aws/s7m9t1b0\"."
  type        = string
  default     = ""
}

variable "helm_chart_repo_url" {
  description = "OCI registry Ekai publishes the ekai-saas chart to (cicd_provider = \"none\" only), e.g. \"public.ecr.aws/s7m9t1b0/ekai-helm\" -- bare host+path, no \"oci://\" prefix and no chart name suffix. Expected public — no client credentials needed."
  type        = string
  default     = ""
}

variable "helm_chart_version" {
  description = "Chart version to deploy (cicd_provider = \"none\" only). Defaults to \"*\" — ArgoCD always tracks and auto-syncs whatever version is latest in the Helm repo, no terraform apply needed per release. Set an exact version (e.g. \"0.1.2\") to pin instead."
  type        = string
  default     = "*"
}

variable "image_tag" {
  description = "Application image tag to deploy (cicd_provider = \"none\" only) — passed through as the ekai-saas chart's imageTag."
  type        = string
  default     = ""
}

variable "erd_storage_class" {
  description = "StorageClass for ERD's workspace PVC (cicd_provider = \"none\" only) — passed through as the ekai-saas chart's erd.workspace.storageClassName."
  type        = string
  default     = "standard-rwo"
}

variable "ingress_class_name" {
  description = "Ingress controller class for the ekai-saas chart (cicd_provider = \"none\" only)."
  type        = string
  default     = "nginx"
}

variable "tls_secret_name" {
  description = "K8s TLS Secret name the ekai-saas chart's Ingress references (cicd_provider = \"none\" only) — matches the combined root's tls_secret_name (cert-manager wildcard cert, reflected into ekai_namespace)."
  type        = string
  default     = "wildcard-tls"
}

variable "claude_model" {
  description = "Claude model the app's semantics service uses (cicd_provider = \"none\" only)."
  type        = string
  default     = "claude-haiku-4-5-20251001"
}

variable "vector_embedding_model" {
  description = "OpenAI embedding model for semantics' vector search (cicd_provider = \"none\" only)."
  type        = string
  default     = "text-embedding-3-small"
}

variable "vector_embedding_batch_size" {
  description = "Batch size for embedding generation (cicd_provider = \"none\" only)."
  type        = number
  default     = 100
}

variable "secret_value_overrides" {
  description = "Escape hatch for any key in the app secret (cicd_provider = \"none\" only) that doesn't have its own dedicated variable — merged on top of every computed/default value, so it wins on conflicts."
  type        = map(string)
  default     = {}
}

variable "pipelines" {
  description = "Map of service CI/CD pipeline definitions. Add entries in .tfvars — no source changes needed."
  type = map(object({
    branch          = string                              # source branch to trigger on (e.g. "main")
    github_repo     = string                               # repository name only (e.g. "my-app"), NOT "org/repo"
    dockerfile      = optional(string, "Dockerfile")       # path to Dockerfile relative to repo root
    build_context   = optional(string, ".")                # Docker build context directory (default: repo root)
    manifest_folder = optional(string, "manifest-files")   # folder inside deployment-files repo
    manifest_file   = string                               # filename of the K8s manifest to patch (e.g. "deployment.yaml")
    ingresshost     = optional(string, "")                 # public hostname for Cloud DNS record (empty = skip)
  }))
  default = {}
}

variable "cd_branch" {
  description = "Branch in deployment-files repo used for CD manifest updates (e.g. main). Only read when cicd_provider != \"none\" — a self-service client has no default, doesn't need to set this."
  type        = string
  default     = ""
}

variable "manifest_folder" {
  description = "Folder inside deployment-files repo where ArgoCD reads K8s manifests (e.g. gcp-manifests, manifest-files)."
  type        = string
  default     = "manifest-files"
}

variable "argocd_ingress_host" {
  description = "ArgoCD server hostname. Optional -- defaults to \"argocd.<dns_zone>\" when unset."
  type        = string
  default     = null
}

variable "github_org" {
  description = "GitHub organisation name (owner of all repos). Only read when cicd_provider != \"none\" — a self-service client has no default, doesn't need to set this."
  type        = string
  default     = ""
}

variable "ekai_namespace" {
  description = "Kubernetes namespace for ekai application services."
  type        = string
}

variable "dns_zone_name" {
  description = "Cloud DNS managed zone name (not the DNS name itself) used for service A records."
  type        = string
}

variable "cicd_provider" {
  description = "CI/CD backend to provision. 'cloud_build' creates Cloud Build triggers; 'github_actions' creates a Workload Identity Federation pool, per-repo service accounts, and pushes workflow YAML to each app repo; 'none' is self-service — no CI/CD, no master secret, ArgoCD pulls the ekai-saas Helm chart directly and Terraform generates the app's shared secret."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["cloud_build", "github_actions", "none"], var.cicd_provider)
    error_message = "cicd_provider must be one of: cloud_build, github_actions, none."
  }
}

variable "cluster_name" {
  description = "GKE cluster name — used to query cluster endpoint directly from the GKE API in providers.tf."
  type        = string
  default     = "ekai-gke"
}
