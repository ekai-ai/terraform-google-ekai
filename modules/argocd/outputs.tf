output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = var.argocd_namespace
}

output "argocd_ingress_host" {
  description = "ArgoCD ingress hostname"
  value       = var.argocd_ingress_host
}
