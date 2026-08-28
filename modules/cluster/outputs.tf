###############################################################################
# cluster submodule — Outputs
# Consumed by the platform submodule (via direct module.cluster.X references
# at root — see ../../main.tf) and by ../../cicd/ (via
# `data.terraform_remote_state.combined.outputs.X` — see ../../cicd/main.tf).
###############################################################################

# ---------------------------------------------------------------------------
# GKE cluster
# ---------------------------------------------------------------------------

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "The IP address of the GKE master endpoint."
  value       = module.gke.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public certificate of the cluster CA."
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "cluster_id" {
  description = "Fully-qualified GKE cluster ID (projects/PROJECT/locations/REGION/clusters/NAME)."
  value       = module.gke.cluster_id
}

# ---------------------------------------------------------------------------
# Cloud SQL
# ---------------------------------------------------------------------------

output "cloud_sql_instance_name" {
  description = "The name of the Cloud SQL instance."
  value       = module.cloud_sql.instance_name
}

output "cloud_sql_ip" {
  description = "The private IP address of the Cloud SQL instance."
  value       = module.cloud_sql.private_ip_address
  sensitive   = true
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name (project:region:instance) for use with the Cloud SQL Auth Proxy."
  value       = module.cloud_sql.connection_name
}

# cicd_provider = "none" only — the cicd module builds DATABASE_URL/VECTOR_DATABASE_URL
# from these instead of reading a master Secret Manager secret.
output "backend_db_username" {
  value     = module.cloud_sql.backend_db_username
  sensitive = true
}

output "backend_db_password" {
  value     = module.cloud_sql.backend_db_password
  sensitive = true
}

output "backend_db_name" {
  value = module.cloud_sql.backend_db_name
}

output "semantics_db_username" {
  value     = module.cloud_sql.semantics_db_username
  sensitive = true
}

output "semantics_db_password" {
  value     = module.cloud_sql.semantics_db_password
  sensitive = true
}

output "semantics_db_name" {
  value = module.cloud_sql.semantics_db_name
}

# ---------------------------------------------------------------------------
# Artifact Registry
# ---------------------------------------------------------------------------

output "artifact_registry_url" {
  description = "Artifact Registry base URL: REGION-docker.pkg.dev/PROJECT (no trailing slash)."
  value       = module.artifact_registry.registry_url
}

output "artifact_registry_image_map" {
  description = "Map of service name to its full Artifact Registry repository URL."
  value       = module.artifact_registry.image_map
}

# ---------------------------------------------------------------------------
# GKE node service account
# ---------------------------------------------------------------------------

output "gke_node_sa_email" {
  description = "Email of the GKE node service account."
  value       = google_service_account.gke_node.email
}

output "gke_node_sa_id" {
  description = "Full resource ID of the GKE node service account."
  value       = google_service_account.gke_node.id
}
