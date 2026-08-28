output "instance_name" {
  description = "The name of the Cloud SQL instance."
  value       = google_sql_database_instance.postgres.name
}

output "private_ip_address" {
  description = "The private IP address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "connection_name" {
  description = "The connection name of the Cloud SQL instance (project:region:instance)."
  value       = google_sql_database_instance.postgres.connection_name
}

# self_service = true only — 04-cicd needs these to build DATABASE_URL/
# VECTOR_DATABASE_URL without reading a master Secret Manager secret.
output "backend_db_username" {
  value     = local.backend_user
  sensitive = true
}

output "backend_db_password" {
  value     = local.backend_password
  sensitive = true
}

output "backend_db_name" {
  value = local.backend_db_name
}

output "semantics_db_username" {
  value     = local.semantics_user
  sensitive = true
}

output "semantics_db_password" {
  value     = local.semantics_password
  sensitive = true
}

output "semantics_db_name" {
  value = local.semantics_db_name
}
