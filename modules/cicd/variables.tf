variable "project_id" {
  description = "GCP project ID that owns all resources."
  type        = string
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
  description = "K8s TLS Secret name the ekai-saas chart's Ingress references (cicd_provider = \"none\" only) — matches the platform submodule's tls_secret_name (cert-manager wildcard cert, reflected into ekai_namespace)."
  type        = string
  default     = "wildcard-tls"
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
  description = "ArgoCD server hostname — used by the ArgoCD Terraform provider to connect (e.g. argocd.client1.ekai.ai)."
  type        = string
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

# ── Formerly read via `data "terraform_remote_state" "cluster"` ──────────────
# Wired automatically from the combined root state by ../../cicd/main.tf —
# nothing to set in tfvars for these.

variable "artifact_registry_url" {
  description = "Artifact Registry base URL: REGION-docker.pkg.dev/PROJECT (sourced from the cluster submodule's output)."
  type        = string
}

variable "backend_db_username" {
  description = "Backend Cloud SQL DB username (sourced from the cluster submodule's output, self-service only)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "backend_db_password" {
  description = "Backend Cloud SQL DB password (sourced from the cluster submodule's output, self-service only)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "backend_db_name" {
  description = "Backend Cloud SQL DB name (sourced from the cluster submodule's output, self-service only)."
  type        = string
  default     = ""
}

variable "semantics_db_username" {
  description = "Semantics Cloud SQL DB username (sourced from the cluster submodule's output, self-service only)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "semantics_db_password" {
  description = "Semantics Cloud SQL DB password (sourced from the cluster submodule's output, self-service only)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "semantics_db_name" {
  description = "Semantics Cloud SQL DB name (sourced from the cluster submodule's output, self-service only)."
  type        = string
  default     = ""
}

variable "cloud_sql_ip" {
  description = "Private IP address of the Cloud SQL instance (sourced from the cluster submodule's output)."
  type        = string
  sensitive   = true
  default     = ""
}

# ── Formerly read via `data "terraform_remote_state" "platform"` ─────────────
# Wired automatically from the combined root state by ../../cicd/main.tf —
# nothing to set in tfvars for these.

variable "nginx_ingress_ip" {
  description = "External IP of the nginx ingress LoadBalancer (sourced from the platform submodule's output)."
  type        = string
  default     = ""
}

variable "argocd_admin_password_plaintext" {
  description = "Plaintext ArgoCD admin password (sourced from the platform submodule's output, self-service only)."
  type        = string
  sensitive   = true
  default     = null
}

variable "redis_credentials" {
  description = "Redis connection details (sourced from the platform submodule's output). Empty map when enable_redis_stack = false."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "neo4j_credentials" {
  description = "Neo4j connection details (sourced from the platform submodule's output). Empty map when enable_neo4j = false."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "minio_endpoint" {
  description = "MinIO internal endpoint (sourced from the platform submodule's output). Empty when enable_minio = false."
  type        = string
  default     = ""
}

variable "minio_root_user" {
  description = "MinIO root user (sourced from the platform submodule's output). Empty when enable_minio = false."
  type        = string
  sensitive   = true
  default     = ""
}

variable "minio_root_password" {
  description = "MinIO root password (sourced from the platform submodule's output). Empty when enable_minio = false."
  type        = string
  sensitive   = true
  default     = ""
}

variable "minio_default_buckets" {
  description = "MinIO default bucket names (sourced from the platform submodule's output). Empty list when enable_minio = false."
  type        = list(string)
  default     = []
}

variable "cluster_secret_store_name" {
  description = "ClusterSecretStore name used by ExternalSecret resources (sourced from the platform submodule's output)."
  type        = string
}
