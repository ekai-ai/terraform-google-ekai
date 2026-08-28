# ──────────────────────────────────────────────────────────────────────────────
# examples/self-deploy/root — the actual state-holding root config for the
# "infra" module (../../.. = the repo root — bootstrap+cluster+platform,
# combined into one apply). This is what scripts/self-deploy.sh runs
# `terraform init`/`apply` against; the repo root itself is a pure module now
# (no backend block — see ../../../providers.tf) and cannot be applied
# directly.
#
# required_providers here matches ../../../providers.tf's exactly — the repo
# root module already declares (and configures) these providers internally,
# but re-declaring the same versions at the true root pins them at the entry
# point too, which is what actually determines what `terraform init`
# installs and locks in .terraform.lock.hcl.
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6"

  # Partial backend config — provide per-environment via -backend-config flag.
  # Example:
  #   terraform init -backend-config=../../../env/backend-<env>.tfbackend
  #
  # The GCS state bucket MUST exist before terraform init can succeed.
  # Create it first with: scripts/init-state-backend.sh <env> (from the repo
  # root — it writes backend files into env/, not here).
  #
  # This is one of TWO separate states in this repo — this one holds
  # bootstrap+cluster+platform ("combined"); examples/self-deploy/cicd/ holds
  # its own, reading this state's outputs via `data "terraform_remote_state"`
  # (inside the cicd module itself). See scripts/init-state-backend.sh for
  # the exact prefix each gets.
  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

module "infra" {
  source = "../../.."

  project_id                    = var.project_id
  region                        = var.region
  env                           = var.env
  secrets_name                  = var.secrets_name
  cicd_provider                 = var.cicd_provider
  vpc_name                      = var.vpc_name
  subnet_cidr                   = var.subnet_cidr
  pods_cidr                     = var.pods_cidr
  services_cidr                 = var.services_cidr
  dns_zone                      = var.dns_zone
  manage_dns_zone               = var.manage_dns_zone
  state_bucket_name             = var.state_bucket_name
  cluster_name                  = var.cluster_name
  node_machine_type             = var.node_machine_type
  min_nodes                     = var.min_nodes
  max_nodes                     = var.max_nodes
  k8s_version                   = var.k8s_version
  db_instance_tier              = var.db_instance_tier
  db_version                    = var.db_version
  pipelines                     = var.pipelines
  cloudbuild_sa_email           = var.cloudbuild_sa_email
  master_ipv4_cidr_block        = var.master_ipv4_cidr_block
  argocd_namespace              = var.argocd_namespace
  argocd_admin_password_hashed  = var.argocd_admin_password_hashed
  argocd_ingress_host           = var.argocd_ingress_host
  tls_secret_name               = var.tls_secret_name
  nginx_ingress_chart_version   = var.nginx_ingress_chart_version
  eso_chart_version             = var.eso_chart_version
  argocd_chart_version          = var.argocd_chart_version
  keda_chart_version            = var.keda_chart_version
  reloader_chart_version        = var.reloader_chart_version
  cert_manager_chart_version    = var.cert_manager_chart_version
  enable_cert_manager           = var.enable_cert_manager
  cert_manager_sa_id            = var.cert_manager_sa_id
  enable_minio                  = var.enable_minio
  minio_namespace               = var.minio_namespace
  minio_host                    = var.minio_host
  minio_default_buckets         = var.minio_default_buckets
  minio_persistence_size        = var.minio_persistence_size
  minio_storage_class           = var.minio_storage_class
  minio_replicas                = var.minio_replicas
  enable_ecr_pull_auth          = var.enable_ecr_pull_auth
  ecr_credentials_secret_name   = var.ecr_credentials_secret_name
  aws_account_id                = var.aws_account_id
  aws_ecr_region                = var.aws_ecr_region
  ecr_namespace                 = var.ecr_namespace
  acme_email                    = var.acme_email
  aws_ecr_access_key_id         = var.aws_ecr_access_key_id
  aws_ecr_secret_access_key     = var.aws_ecr_secret_access_key
  enable_neo4j                  = var.enable_neo4j
  enable_redis_stack            = var.enable_redis_stack
  redis_namespace               = var.redis_namespace
  redis_password                = var.redis_password
  redis_storage_size            = var.redis_storage_size
  redis_storage_class           = var.redis_storage_class
  neo4j_namespace               = var.neo4j_namespace
  neo4j_storage_size            = var.neo4j_storage_size
  neo4j_storage_class           = var.neo4j_storage_class
  neo4j_memory_request          = var.neo4j_memory_request
  neo4j_memory_limit            = var.neo4j_memory_limit
}
