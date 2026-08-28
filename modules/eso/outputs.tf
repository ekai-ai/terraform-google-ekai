output "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore CRD (referenced by ExternalSecret resources)."
  value       = "gcp-secrets-manager"
}

output "eso_sa_email" {
  description = "Email of the GCP service account attached to the ESO pod via Workload Identity."
  value       = google_service_account.eso.email
}
