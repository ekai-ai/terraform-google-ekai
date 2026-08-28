# ── Artifact Registry image map ───────────────────────────────────────────────
# GCP equivalent of the AWS ecr_image_map output.
# Returns a map of service name → full Artifact Registry repository URL.
# Callers can use this to construct image tags:
#   "${output.artifact_image_map["api"]}:${git_sha}"
output "artifact_image_map" {
  description = "Map of service name to its full Artifact Registry repository URL (REGION-docker.pkg.dev/PROJECT/ENV-SERVICE)."
  value = {
    for k in keys(var.pipelines) :
    k => "${local.registry_url}/${var.env}-${k}"
  }
}

output "argocd_app_name" {
  description = "Name of the ArgoCD Application managing ekai services."
  value       = module.ekai_CD.argocd_app_name
}

output "ekai_namespace" {
  description = "Kubernetes namespace where ekai services are deployed."
  value       = data.kubernetes_namespace.ekai_saas.metadata[0].name
}

output "app_secret_name" {
  description = "Name of the app secret Terraform created (cicd_provider = \"none\" only)."
  value       = local.self_service ? google_secret_manager_secret.app_secret[0].secret_id : null
}
