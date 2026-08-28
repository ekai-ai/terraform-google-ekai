output "image_map" {
  description = "Map of service name to its full Artifact Registry repository URL (without tag). GCP equivalent of the AWS ecr image_map output."
  value       = local.image_map
}

output "service_account_emails" {
  description = "Map of bare repo name to the GitHub Actions service account email that GitHub Actions workflows impersonate via WIF."
  value = {
    for repo, sa in google_service_account.github_actions :
    repo => sa.email
  }
}

output "wif_provider_name" {
  description = "Full resource name of the Workload Identity Federation OIDC provider. Written into the GCP_WORKLOAD_IDENTITY_PROVIDER secret on each app repo."
  value       = google_iam_workload_identity_pool_provider.github_oidc.name
}

output "wif_pool_name" {
  description = "Full resource name of the Workload Identity Federation pool."
  value       = local.wif_pool_name
}
