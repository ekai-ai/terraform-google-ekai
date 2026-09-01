# ──────────────────────────────────────────────────────────────────────────────
# Root module — composes 3 of the 4 submodules (bootstrap, cluster, platform)
# that used to be 3 separate root modules chained via `terraform_remote_state`
# (plus a 4th, cicd), each with its own GCS backend/state. Now: one apply, one
# state for these 3; module outputs wire submodule-to-submodule directly
# instead of remote-state reads.
#
# The 4th submodule (cicd) is deliberately NOT included here — it stays a
# separate apply/state at ./cicd/, reading THIS config's outputs via
# `data "terraform_remote_state"` (see ./cicd/main.tf). Why: this root's
# provider "kubernetes"/"helm"/"kubectl" blocks below can safely be configured
# from module.cluster's own same-apply outputs (cluster_endpoint/
# cluster_ca_certificate) because GCP's token-based auth (a short-lived OIDC
# token fetched at plan/apply time via `data.google_client_config`) doesn't
# need those values to be known any more eagerly than that — the same trick
# the source codebase's own cluster layer already relied on. The ArgoCD
# Terraform provider (argoproj-labs/argocd) has no equivalent mechanism: its
# `password` field is read eagerly, so it can only be set from a value
# Terraform already knows before apply — i.e. a remote_state read against an
# already-completed apply, never a same-apply managed-resource attribute
# (module.platform's freshly-generated argocd_admin_password_plaintext).
# That's the one boundary where the "single combined apply" simplification
# genuinely does not work, so it stays split here, mirroring the original
# 4-layer design for exactly this one seam.
#
# Apply order matches the original layer order (bootstrap → cluster →
# platform); depends_on on each module block enforces it explicitly since
# Terraform can't always infer full ordering from the module.X.Y references
# alone (some resources inside a submodule, e.g. the kubernetes/helm/kubectl-
# backed ones, don't reference upstream outputs directly — they rely on the
# *provider* configuration at root already pointing at a live cluster).
# ──────────────────────────────────────────────────────────────────────────────

module "bootstrap" {
  source = "./modules/bootstrap"

  project_id        = var.project_id
  region            = var.region
  env               = var.env
  vpc_name          = var.vpc_name
  subnet_cidr       = var.subnet_cidr
  pods_cidr         = var.pods_cidr
  services_cidr     = var.services_cidr
  dns_zone          = var.dns_zone
  manage_dns_zone   = var.manage_dns_zone
  state_bucket_name = var.state_bucket_name
}

module "cluster" {
  source     = "./modules/cluster"
  depends_on = [module.bootstrap]

  project_id             = var.project_id
  region                 = var.region
  env                    = var.env
  cluster_name           = var.cluster_name
  node_machine_type      = var.node_machine_type
  min_nodes              = var.min_nodes
  max_nodes              = var.max_nodes
  k8s_version            = var.k8s_version
  secrets_name           = var.secrets_name
  cicd_provider          = var.cicd_provider
  db_instance_tier       = var.db_instance_tier
  db_version             = var.db_version
  pipelines              = var.pipelines
  cloudbuild_sa_email    = var.cloudbuild_sa_email
  master_ipv4_cidr_block = var.master_ipv4_cidr_block

  # formerly `data "terraform_remote_state" "bootstrap"` in the cluster layer's main.tf
  vpc_name             = module.bootstrap.vpc_name
  subnet_name          = module.bootstrap.subnet_name
  pods_range_name      = module.bootstrap.pods_range_name
  services_range_name  = module.bootstrap.services_range_name
}

module "platform" {
  source     = "./modules/platform"
  depends_on = [module.cluster]

  project_id                  = var.project_id
  region                      = var.region
  env                         = var.env
  dns_zone                    = var.dns_zone
  argocd_namespace            = var.argocd_namespace
  argocd_admin_password_hashed = var.argocd_admin_password_hashed
  cicd_provider               = var.cicd_provider
  argocd_ingress_host         = var.argocd_ingress_host
  tls_secret_name             = var.tls_secret_name
  nginx_ingress_chart_version = var.nginx_ingress_chart_version
  eso_chart_version           = var.eso_chart_version
  argocd_chart_version        = var.argocd_chart_version
  keda_chart_version          = var.keda_chart_version
  reloader_chart_version      = var.reloader_chart_version
  cert_manager_chart_version  = var.cert_manager_chart_version
  enable_cert_manager         = var.enable_cert_manager
  cert_manager_sa_id          = var.cert_manager_sa_id
  enable_minio                = var.enable_minio
  minio_namespace             = var.minio_namespace
  minio_host                  = var.minio_host
  minio_default_buckets       = var.minio_default_buckets
  minio_persistence_size      = var.minio_persistence_size
  minio_storage_class         = var.minio_storage_class
  minio_replicas              = var.minio_replicas
  enable_ecr_pull_auth        = var.enable_ecr_pull_auth
  ecr_credentials_secret_name = var.ecr_credentials_secret_name
  aws_account_id              = var.aws_account_id
  aws_ecr_region              = var.aws_ecr_region
  ecr_namespace               = var.ecr_namespace
  acme_email                  = var.acme_email
  aws_ecr_access_key_id       = var.aws_ecr_access_key_id
  aws_ecr_secret_access_key   = var.aws_ecr_secret_access_key
  enable_neo4j                = var.enable_neo4j
  secrets_name                = var.secrets_name
  enable_redis_stack          = var.enable_redis_stack
  redis_namespace             = var.redis_namespace
  redis_password              = var.redis_password
  redis_storage_size          = var.redis_storage_size
  redis_storage_class         = var.redis_storage_class
  neo4j_namespace             = var.neo4j_namespace
  neo4j_storage_size          = var.neo4j_storage_size
  neo4j_storage_class         = var.neo4j_storage_class
  neo4j_memory_request        = var.neo4j_memory_request
  neo4j_memory_limit          = var.neo4j_memory_limit

  # formerly `data "terraform_remote_state" "cluster"` in the platform layer's main.tf
  cluster_name = module.cluster.cluster_name
}
