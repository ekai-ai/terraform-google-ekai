###############################################################################
# cluster submodule — Main
# Provisions the GKE cluster, Cloud SQL, Artifact Registry repositories,
# and the GKE node service account with its required IAM bindings.
# Reads VPC/subnet names from the bootstrap submodule (wired by the root
# module — see ../../main.tf — instead of a `data "terraform_remote_state"
# "bootstrap"` read against bootstrap's own state, since this is now one
# apply/one state).
###############################################################################

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  # Cloud Build default SA — <project-number>@cloudbuild.gserviceaccount.com
  _cloudbuild_sa = var.cloudbuild_sa_email != "" ? var.cloudbuild_sa_email : "${data.google_project.current.number}@cloudbuild.gserviceaccount.com"

  self_service = var.cicd_provider == "none"
}

###############################################################################
# GKE node service account
# A dedicated SA per cluster limits the blast radius if a node is compromised.
###############################################################################

resource "google_service_account" "gke_node" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE node SA — ${var.cluster_name}"
  description  = "Attached to all nodes in the ${var.cluster_name} cluster. Managed by Terraform."
}

###############################################################################
# IAM — node SA project-level roles
###############################################################################

resource "google_project_iam_member" "node_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "node_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

resource "google_project_iam_member" "node_monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

###############################################################################
# GKE cluster
###############################################################################

module "gke" {
  source = "../gke"

  project_id             = var.project_id
  region                 = var.region
  env                    = var.env
  cluster_name           = var.cluster_name
  vpc_name               = var.vpc_name
  subnet_name            = var.subnet_name
  pods_range_name        = var.pods_range_name
  services_range_name    = var.services_range_name
  node_machine_type      = var.node_machine_type
  min_nodes              = var.min_nodes
  max_nodes              = var.max_nodes
  k8s_version            = var.k8s_version
  node_service_account   = google_service_account.gke_node.email
  master_ipv4_cidr_block = var.master_ipv4_cidr_block

  depends_on = [
    google_project_iam_member.node_artifact_registry_reader,
    google_project_iam_member.node_logging_writer,
    google_project_iam_member.node_monitoring_metric_writer,
  ]
}

###############################################################################
# Cloud SQL (private PostgreSQL)
###############################################################################

module "cloud_sql" {
  source = "../cloud_sql"

  project_id    = var.project_id
  region        = var.region
  env           = var.env
  vpc_name      = var.vpc_name
  secrets_name  = var.secrets_name
  self_service  = local.self_service
  instance_tier = var.db_instance_tier
  db_version    = var.db_version
}

###############################################################################
# Update master secret with platform-derived DB URLs
# After Cloud SQL is created, write DATABASE_URL and VECTOR_DATABASE_URL into
# the master secret so ESO can sync them to pods at runtime.
# Mirrors the Azure pattern where the platform layer writes back to Key Vault.
# Skipped entirely for self_service, which has no master secret -- the cicd
# module builds these URLs directly from module.cloud_sql's own outputs instead.
###############################################################################
data "google_secret_manager_secret_version" "master" {
  count      = local.self_service ? 0 : 1
  project    = var.project_id
  secret     = var.secrets_name
  depends_on = [module.cloud_sql]
}

locals {
  _master       = local.self_service ? {} : jsondecode(data.google_secret_manager_secret_version.master[0].secret_data)
  _sql_ip       = module.cloud_sql.private_ip_address
  _backend_user = local.self_service ? "" : local._master["backend_db_username"]
  _backend_pass = local.self_service ? "" : local._master["backend_db_password"]
  _backend_db   = local.self_service ? "" : local._master["backend_db_name"]
  _sem_user     = local.self_service ? "" : local._master["semantics_db_username"]
  _sem_pass     = local.self_service ? "" : local._master["semantics_db_password"]
  _sem_db       = local.self_service ? "" : local._master["semantics_db_name"]

  _updated_master = local.self_service ? {} : merge(local._master, {
    DATABASE_URL        = "postgresql://${local._backend_user}:${local._backend_pass}@${local._sql_ip}:5432/${local._backend_db}"
    VECTOR_DATABASE_URL = "postgresql://${local._sem_user}:${local._sem_pass}@${local._sql_ip}:5432/${local._sem_db}"
  })
}

resource "google_secret_manager_secret_version" "master_with_db_urls" {
  count       = local.self_service ? 0 : 1
  secret      = "projects/${var.project_id}/secrets/${var.secrets_name}"
  secret_data = jsonencode(local._updated_master)

  lifecycle {
    # Only update when DB URLs actually change (new SQL IP or creds).
    ignore_changes = []
  }

  depends_on = [module.cloud_sql]
}

###############################################################################
# Artifact Registry — one repository per entry in var.pipelines
###############################################################################

module "artifact_registry" {
  source = "../artifact_registry"

  project_id          = var.project_id
  region              = var.region
  env                 = var.env
  services            = var.pipelines
  gke_node_sa_email   = google_service_account.gke_node.email
  cloudbuild_sa_email = local._cloudbuild_sa

  depends_on = [google_service_account.gke_node]
}
