output "cluster_issuer_name" {
  description = "Name of the production ClusterIssuer (referenced by Ingress cert-manager.io/cluster-issuer annotation)."
  value       = "letsencrypt-prod"
}
