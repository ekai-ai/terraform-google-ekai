# ── nginx ingress LB IP data source ──────────────────────────────────────────
# Helm naming: release=ingress-nginx, chart=ingress-nginx
# → controller Service is named `ingress-nginx-controller` in namespace `ingress-nginx`.
data "kubernetes_service" "nginx_ingress" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.nginx_ingress]
}

output "cluster_secret_store_name" {
  description = "ClusterSecretStore name used by ExternalSecret resources in the cicd module."
  value       = module.eso.cluster_secret_store_name
}

output "nginx_ingress_ip" {
  description = "External IP of the nginx ingress LoadBalancer. Used for Cloud DNS A-record registration in the cicd module."
  value       = data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].ip
}

output "argocd_ingress_host" {
  description = "ArgoCD ingress hostname (consumed by the argocd provider in ../../cicd/)."
  value       = local.argocd_host
}

output "redis_credentials" {
  description = "Redis connection details merged into app secrets by the cicd module. Empty map when enable_redis_stack = false."
  sensitive   = true
  value = var.enable_redis_stack ? {
    REDIS_HOST     = module.redis[0].redis_host
    REDIS_PORT     = tostring(module.redis[0].redis_port)
    REDIS_USERNAME = module.redis[0].redis_username
    REDIS_PASSWORD = module.redis[0].redis_password
    REDIS_URI      = "${module.redis[0].redis_host}:${module.redis[0].redis_port}"
  } : {}
}

output "redis_enabled" {
  description = "Whether Redis was deployed in this platform layer."
  value       = var.enable_redis_stack
}

output "neo4j_credentials" {
  description = "Neo4j connection details merged into app secrets by the cicd module. Empty map when enable_neo4j = false."
  sensitive   = true
  value = var.enable_neo4j ? {
    NEO4J_URI      = module.neo4j[0].bolt_uri
    NEO4J_USERNAME = "neo4j"
    NEO4J_PASSWORD = module.neo4j[0].neo4j_password
  } : {}
}

output "neo4j_enabled" {
  description = "Whether Neo4j was deployed in this platform layer."
  value       = var.enable_neo4j
}

output "argocd_admin_password_plaintext" {
  description = "Plaintext ArgoCD admin password, self_service only (the cicd module's argocd provider needs it to authenticate). Null otherwise."
  sensitive   = true
  value       = local.self_service ? random_password.argocd_admin[0].result : null
}


output "erd_filestore_storage_class" {
  description = "Filestore StorageClass for ERD's workspace (empty when enable_erd_filestore = false). The cicd module mounts the workspace as a ReadWriteMany PVC of this class when it is set."
  value       = var.enable_erd_filestore ? kubernetes_storage_class_v1.erd_filestore[0].metadata[0].name : ""
}
