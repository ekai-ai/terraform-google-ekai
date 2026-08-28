# ──────────────────────────────────────────────────────────────────────────────
# cicd — separate apply/state from the combined bootstrap+cluster+platform
# root one directory up (see ../main.tf's file header for the full reasoning).
# In short: the argocd Terraform provider's `password` field must be a value
# Terraform already knows before apply — it cannot be a same-apply managed
# resource attribute the way kubernetes/helm/kubectl's token-based auth can.
# module.platform's freshly-generated ArgoCD admin password is exactly such
# an attribute, so this apply has to run separately, AFTER the combined one
# has already finished and written that password to state.
#
# Reads the combined root's own state via terraform_remote_state — same
# mechanism the original 04-cicd/main.tf used to read the cluster/platform
# layers' (and bootstrap's) state, just pointed at the new combined state
# instead of 3 separate ones.
# ──────────────────────────────────────────────────────────────────────────────

data "terraform_remote_state" "combined" {
  backend = "gcs"
  config = {
    bucket = "ekai-terraform-state-${var.env}"
    prefix = "${var.env}/combined.tfstate"
  }
}

module "cicd" {
  source = "../modules/cicd"

  project_id                        = var.project_id
  region                            = var.region
  env                               = var.env
  secrets_name                      = var.secrets_name
  dns_zone                          = var.dns_zone
  existing_image_registry_base_url  = var.existing_image_registry_base_url
  helm_chart_repo_url               = var.helm_chart_repo_url
  helm_chart_version                = var.helm_chart_version
  image_tag                         = var.image_tag
  erd_storage_class                 = var.erd_storage_class
  ingress_class_name                = var.ingress_class_name
  tls_secret_name                   = var.tls_secret_name
  claude_model                      = var.claude_model
  vector_embedding_model            = var.vector_embedding_model
  vector_embedding_batch_size       = var.vector_embedding_batch_size
  secret_value_overrides            = var.secret_value_overrides
  pipelines                         = var.pipelines
  cd_branch                         = var.cd_branch
  manifest_folder                   = var.manifest_folder
  argocd_ingress_host               = var.argocd_ingress_host
  github_org                        = var.github_org
  ekai_namespace                    = var.ekai_namespace
  dns_zone_name                     = var.dns_zone_name
  cicd_provider                     = var.cicd_provider

  # formerly `data "terraform_remote_state" "cluster"` in the original
  # 04-cicd/main.tf — now reads the combined root's state instead
  artifact_registry_url = data.terraform_remote_state.combined.outputs.artifact_registry_url
  backend_db_username    = data.terraform_remote_state.combined.outputs.backend_db_username
  backend_db_password    = data.terraform_remote_state.combined.outputs.backend_db_password
  backend_db_name        = data.terraform_remote_state.combined.outputs.backend_db_name
  semantics_db_username  = data.terraform_remote_state.combined.outputs.semantics_db_username
  semantics_db_password  = data.terraform_remote_state.combined.outputs.semantics_db_password
  semantics_db_name      = data.terraform_remote_state.combined.outputs.semantics_db_name
  cloud_sql_ip           = data.terraform_remote_state.combined.outputs.cloud_sql_ip

  # formerly `data "terraform_remote_state" "platform"` in the original
  # 04-cicd/main.tf
  nginx_ingress_ip                = data.terraform_remote_state.combined.outputs.nginx_ingress_ip
  argocd_admin_password_plaintext = data.terraform_remote_state.combined.outputs.argocd_admin_password_plaintext
  redis_credentials                = data.terraform_remote_state.combined.outputs.redis_credentials
  neo4j_credentials                = data.terraform_remote_state.combined.outputs.neo4j_credentials
  minio_endpoint                   = data.terraform_remote_state.combined.outputs.minio_endpoint
  minio_root_user                  = data.terraform_remote_state.combined.outputs.minio_root_user
  minio_root_password              = data.terraform_remote_state.combined.outputs.minio_root_password
  minio_default_buckets            = data.terraform_remote_state.combined.outputs.minio_default_buckets
  cluster_secret_store_name        = data.terraform_remote_state.combined.outputs.cluster_secret_store_name
}
