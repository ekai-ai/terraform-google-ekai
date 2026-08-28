variable "project_id" {
  description = "GCP project ID that owns the cluster and Secret Manager secrets."
  type        = string
}

variable "region" {
  description = "GCP region of the GKE cluster (e.g. us-central1)."
  type        = string
}

variable "env" {
  description = "Environment name (e.g. dev, staging, prod). Used for resource naming."
  type        = string
}

# ── Formerly read via `data "terraform_remote_state" "cluster"` ─────────────
# Wired automatically from module.cluster's output by the root module (see
# ../../main.tf) — nothing to set in tfvars for this. cluster_endpoint /
# cluster_ca_certificate (the other two values this layer used to read from
# cluster's remote state) are NOT re-declared here — they were only ever used
# to configure the kubernetes/helm/kubectl providers, which now live solely
# at root (see ../../providers.tf); this layer never referenced them directly.

variable "cluster_name" {
  description = "GKE cluster name (sourced from the cluster submodule's output) — used by module.eso for its Workload Identity binding."
  type        = string
}

# ── ArgoCD ────────────────────────────────────────────────────────────────────

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD."
  type        = string
  default     = "argocd"
}

variable "argocd_admin_password_hashed" {
  description = "Bcrypt-hashed ArgoCD admin password (use: htpasswd -nbBC 10 '' PASSWORD | tr -d ':' | sed 's/$2y/$2a/'). Leave empty when cicd_provider = \"none\" -- self-service generates its own."
  type        = string
  sensitive   = true
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

variable "argocd_ingress_host" {
  description = "Hostname for the ArgoCD Ingress (e.g. argocd.dev.example.com)."
  type        = string
}

variable "tls_secret_name" {
  description = "Name of the K8s TLS Secret used by ArgoCD and other Ingresses (created by cert-manager or pre-provisioned)."
  type        = string
  default     = "wildcard-tls"
}

# ── Chart versions ─────────────────────────────────────────────────────────────

variable "nginx_ingress_chart_version" {
  description = "ingress-nginx Helm chart version."
  type        = string
  default     = "4.10.1"
}

variable "eso_chart_version" {
  description = "External Secrets Operator Helm chart version."
  type        = string
  default     = "0.10.3"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version. Leave empty to use the latest available."
  type        = string
  default     = ""
}

variable "keda_chart_version" {
  description = "KEDA Helm chart version."
  type        = string
  default     = "2.16.0"
}

variable "reloader_chart_version" {
  description = "Stakater Reloader Helm chart version — auto-restarts pods when K8s Secrets change."
  type        = string
  default     = "1.2.0"
}

variable "cert_manager_chart_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "v1.14.5"
}

variable "enable_cert_manager" {
  description = "Deploy cert-manager for GKE TLS certificate management. Set false if TLS is handled externally."
  type        = bool
  default     = true
}

variable "cert_manager_sa_id" {
  description = "Service account ID for cert-manager Workload Identity. Override per-env to avoid conflicts in shared projects."
  type        = string
  default     = ""
}

# ── MinIO ─────────────────────────────────────────────────────────────────────
variable "enable_minio" {
  description = "Deploy in-cluster MinIO object storage."
  type        = bool
  default     = false
}

variable "minio_namespace" {
  type    = string
  default = "minio"
}

variable "minio_host" {
  description = "MinIO API hostname e.g. minio.demo.ekai.ai"
  type        = string
  default     = ""
}

variable "minio_default_buckets" {
  type    = list(string)
  default = ["ekai-files"]
}

variable "minio_persistence_size" {
  type    = string
  default = "20Gi"
}

variable "minio_storage_class" {
  description = "GKE storage class (standard-rwo, premium-rwo)"
  type        = string
  default     = "standard-rwo"
}

variable "minio_replicas" {
  type    = number
  default = 1
}

# ── ECR pull auth (optional — GKE pulling images from AWS ECR) ────────────────
# Enable when the cluster pulls images from AWS ECR instead of (or in addition
# to) Artifact Registry. Creates a CronJob that refreshes the ECR auth token
# every 6h (tokens expire after 12h) and writes a docker-registry K8s Secret
# that pods reference via imagePullSecrets.
variable "enable_ecr_pull_auth" {
  description = "Deploy the ECR pull auth CronJob so GKE can pull images from AWS ECR. Requires ecr_credentials_secret_name, aws_account_id, aws_ecr_region."
  type        = bool
  default     = false
}

variable "ecr_credentials_secret_name" {
  description = "GCP Secret Manager secret name holding AWS IAM creds JSON: {\"AWS_ACCESS_KEY_ID\":\"AKIA...\",\"AWS_SECRET_ACCESS_KEY\":\"...\"}. Required when enable_ecr_pull_auth = true."
  type        = string
  default     = ""
}

variable "aws_account_id" {
  description = "AWS account ID owning the ECR registry (e.g. 123456789012). Used to construct ACCOUNT.dkr.ecr.REGION.amazonaws.com. Required when enable_ecr_pull_auth = true."
  type        = string
  default     = ""
}

variable "aws_ecr_region" {
  description = "AWS region of the ECR registry (e.g. us-east-1). Required when enable_ecr_pull_auth = true."
  type        = string
  default     = "us-east-1"
}

variable "ecr_namespace" {
  description = "Kubernetes namespace where the ECR pull secret and CronJob are created."
  type        = string
  default     = "ekai-saas"
}

variable "acme_email" {
  description = "Email for Let's Encrypt certificate notifications."
  type        = string
  default     = "umar@ekai.ai"
}

variable "aws_ecr_access_key_id" {
  description = "AWS Access Key ID for ECR pull. Passed via TF_VAR_aws_ecr_access_key_id in the workflow. Sensitive — never commit to tfvars."
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_ecr_secret_access_key" {
  description = "AWS Secret Access Key for ECR pull. Passed via TF_VAR_aws_ecr_secret_access_key in the workflow. Sensitive — never commit to tfvars."
  type        = string
  default     = ""
  sensitive   = true
}

# ── Neo4j ─────────────────────────────────────────────────────────────────────
variable "enable_neo4j" {
  description = "Deploy Neo4j community edition in-cluster."
  type        = bool
  default     = false
}

variable "secrets_name" {
  description = "GCP Secret Manager secret name holding all credentials (read by Cloud SQL and Redis modules)."
  type        = string
  default     = ""
}

# ── Redis Stack ────────────────────────────────────────────────────────────────
variable "enable_redis_stack" {
  description = "Deploy Redis Stack (Bitnami redis chart) in-cluster."
  type        = bool
  default     = false
}

variable "redis_namespace" {
  type    = string
  default = "redis"
}

variable "redis_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "redis_storage_size" {
  type    = string
  default = "10Gi"
}

variable "redis_storage_class" {
  type    = string
  default = "standard-rwo"
}

variable "neo4j_namespace" {
  type    = string
  default = "neo4j"
}

variable "neo4j_storage_size" {
  type    = string
  default = "20Gi"
}

variable "neo4j_storage_class" {
  type    = string
  default = "standard-rwo"
}

variable "neo4j_memory_request" {
  type    = string
  default = "2Gi"
}

variable "neo4j_memory_limit" {
  type    = string
  default = "4Gi"
}
