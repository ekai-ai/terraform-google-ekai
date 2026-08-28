# ──────────────────────────────────────────────────────────────────────────────
# cicd outputs — re-exports module.cicd's own outputs. These aren't real
# until THIS apply has run — the combined root doesn't deploy the
# application, only the platform it runs on.
# ──────────────────────────────────────────────────────────────────────────────

output "artifact_image_map" {
  description = "Map of service name to its full Artifact Registry repository URL."
  value       = module.cicd.artifact_image_map
}

output "argocd_app_name" {
  description = "Name of the ArgoCD Application managing ekai services."
  value       = module.cicd.argocd_app_name
}

output "ekai_namespace" {
  description = "Kubernetes namespace where ekai services are deployed."
  value       = module.cicd.ekai_namespace
}

output "app_secret_name" {
  description = "Name of the app secret Terraform created (cicd_provider = \"none\" only)."
  value       = module.cicd.app_secret_name
}

output "portal_url" {
  description = "The application's public URL (cicd_provider = \"none\" only)."
  value       = var.cicd_provider == "none" ? "https://portal.${var.dns_zone}" : null
}
