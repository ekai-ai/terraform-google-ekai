output "service_account_emails" {
  description = "Map of service name → GSA email. Useful for referencing GSAs in other modules (e.g. granting additional roles)."
  value       = { for k, sa in google_service_account.service : k => sa.email }
}

output "service_account_names" {
  description = "Map of service name → GSA resource name (full projects/…/serviceAccounts/… form). Use with google_service_account_iam_member in other modules."
  value       = { for k, sa in google_service_account.service : k => sa.name }
}

output "kubernetes_service_account_names" {
  description = "Map of service name → Kubernetes ServiceAccount name (e.g. backend-sa). Matches the name field in kubernetes_service_account."
  value       = { for k, ksa in kubernetes_service_account.service : k => ksa.metadata[0].name }
}
