# ──────────────────────────────────────────────────────────────────────────────
# examples/self-deploy/root/variables.tf — mirrors ../../../variables.tf
# (the "infra" module's own variables.tf — bootstrap+cluster+platform) 1:1,
# same names/types/defaults/descriptions. This is the file that actually
# receives `-var-file=env/<env>.tfvars`; main.tf here just passes every one
# of these straight through to `module "infra" { source = "../../.." }` as
# X = var.X. See ../../../variables.tf for the full original commentary this
# mirrors (dedup notes, why each variable exists, etc.) — not repeated here
# to avoid the two copies drifting out of sync in wording while still needing
# to stay in sync in substance.
# ──────────────────────────────────────────────────────────────────────────────

# ═══════════════════════════════════════════════════════════════════════════
# Shared across layers (also redeclared in ./cicd/variables.tf where cicd
# needs its own copy — see note above)
# ═══════════════════════════════════════════════════════════════════════════

variable "project_id" {
  description = "GCP project ID that owns all resources."
  type        = string
}

variable "region" {
  description = "GCP region (e.g. us-central1). Must match the state bucket location."
  type        = string
}

variable "env" {
  description = "Environment name (e.g. client1, dev, prod). Used in resource naming and state prefixes."
  type        = string
}

variable "secrets_name" {
  description = "Name of the Secret Manager secret containing DB credentials JSON. Ignored when cicd_provider = \"none\" (self-service generates its own DB credentials instead)."
  type        = string
  default     = ""
}

# ── CI/CD provider ─────────────────────────────────────────────────────────────
variable "cicd_provider" {
  description = <<-EOT
    CI/CD provider for building and pushing container images.
      cloud_build    — GCP Cloud Build triggers with GitHub webhooks.
      github_actions — GitHub Actions workflows with Workload Identity Federation.
      none           — self-service client mode: no CI at all. ArgoCD deploys the
                       ekai-saas Helm chart Ekai maintains instead of a git-based
                       manifest patch. This is the mode env/customer.tfvars uses.
  EOT
  type        = string
  default     = "none"
  validation {
    condition     = contains(["cloud_build", "github_actions", "none"], var.cicd_provider)
    error_message = "cicd_provider must be one of: cloud_build, github_actions, none."
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# bootstrap submodule (Cloud DNS zone + VPC)
# ═══════════════════════════════════════════════════════════════════════════

variable "vpc_name" {
  description = "Base name for the VPC (prefixed with env)."
  type        = string
  default     = "vpc"
}

variable "subnet_cidr" {
  description = "Primary CIDR for the private subnet."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary CIDR for GKE pods."
  type        = string
}

variable "services_cidr" {
  description = "Secondary CIDR for GKE services."
  type        = string
}

variable "dns_zone" {
  description = "DNS zone domain name (e.g. dev.example.com). Created by the bootstrap submodule when manage_dns_zone = true."
  type        = string
}

variable "manage_dns_zone" {
  description = "When true, create the Cloud DNS managed zone; when false, look up an existing zone."
  type        = bool
  default     = true
}

variable "state_bucket_name" {
  description = "Name of the GCS bucket that stores Terraform state (created by scripts/init-state-backend.sh, outside Terraform). Optional -- leave unset and the scripts default to ekai-terraform-state-<env>-<project_id>, which is globally unique on its own since project_id already is. Only set this to use a different bucket name."
  type        = string
  default     = ""
}

# ═══════════════════════════════════════════════════════════════════════════
# cluster submodule (GKE, Cloud SQL, Artifact Registry, node service account)
# ═══════════════════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════════════════
# platform submodule (nginx ingress, ESO, ArgoCD, KEDA, reloader, cert-manager,
# MinIO, ECR pull auth, Redis, Neo4j)
# ═══════════════════════════════════════════════════════════════════════════

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

variable "argocd_ingress_host" {
  description = "Hostname for the ArgoCD Ingress. Optional -- defaults to \"argocd.<dns_zone>\" when unset."
  type        = string
  default     = null
}

variable "tls_secret_name" {
  description = "Name of the K8s TLS Secret used by ArgoCD and other Ingresses (created by cert-manager or pre-provisioned)."
  type        = string
  default     = "wildcard-tls"
}

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
  description = "MinIO API hostname e.g. minio.demo.ekai.ai. Optional -- defaults to \"minio.<dns_zone>\" when unset."
  type        = string
  default     = null
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
  description = "AWS account ID owning the ECR registry (e.g. 123456789012). Required when enable_ecr_pull_auth = true."
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
  description = "AWS Access Key ID for ECR pull. Sensitive — never commit to tfvars."
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_ecr_secret_access_key" {
  description = "AWS Secret Access Key for ECR pull. Sensitive — never commit to tfvars."
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
