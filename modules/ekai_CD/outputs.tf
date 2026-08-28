output "argocd_app_name" {
  description = "Name of the ArgoCD application managing the ekai workload"
  value       = argocd_application.ekai-saas.metadata[0].name
}
