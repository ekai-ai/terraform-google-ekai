# ──────────────────────────────────────────────────────────────────────────────
# examples/self-deploy/root/outputs.tf — re-exports every one of
# ../../../outputs.tf's outputs as module.infra.X. See that file for
# descriptions of what each value is and who consumes it.
# ──────────────────────────────────────────────────────────────────────────────

output "argocd_url" {
  description = "ArgoCD's public URL."
  value       = module.infra.argocd_url
}

output "argocd_admin_username" {
  description = "ArgoCD admin username — always literally \"admin\"."
  value       = module.infra.argocd_admin_username
}

output "argocd_admin_password" {
  description = "ArgoCD admin plaintext password (cicd_provider = \"none\" only — self-service generates this directly; non-self-service envs get it from their master Secret Manager secret instead, not exposed here)."
  value       = module.infra.argocd_admin_password
  sensitive   = true
}

output "dns_zone_name" {
  description = "Cloud DNS managed zone resource name actually in use (whichever the bootstrap submodule created or was pointed at)."
  value       = module.infra.dns_zone_name
}

output "dns_zone_dns_name" {
  description = "DNS name of the managed zone (e.g. dev.example.com.)."
  value       = module.infra.dns_zone_dns_name
}

output "name_servers" {
  description = "Cloud DNS nameservers for this zone -- delegate dns_zone to these at your domain registrar."
  value       = module.infra.name_servers
}

output "vpc_name" {
  description = "Name of the VPC network."
  value       = module.infra.vpc_name
}

output "vpc_id" {
  description = "Self-link of the VPC network."
  value       = module.infra.vpc_id
}

output "cluster_name" {
  description = "Name of the GKE cluster — use with: gcloud container clusters get-credentials <this> --region <region> --project <project_id>"
  value       = module.infra.cluster_name
}

output "nginx_ingress_ip" {
  description = "External IP of the nginx ingress LoadBalancer. Delegate DNS for dns_zone to this before relying on cert-manager's DNS-01 challenge to succeed."
  value       = module.infra.nginx_ingress_ip
}

output "region" {
  description = "GCP region this was deployed into."
  value       = module.infra.region
}

output "artifact_registry_url" {
  description = "Artifact Registry base URL: REGION-docker.pkg.dev/PROJECT. Read by examples/self-deploy/cicd's terraform_remote_state consumer (via the cicd module's own remote_state read)."
  value       = module.infra.artifact_registry_url
}

output "backend_db_username" {
  description = "Backend Cloud SQL DB username (cicd_provider = \"none\" only). Read by the cicd module to build DATABASE_URL."
  value       = module.infra.backend_db_username
  sensitive   = true
}

output "backend_db_password" {
  description = "Backend Cloud SQL DB password (cicd_provider = \"none\" only). Read by the cicd module to build DATABASE_URL."
  value       = module.infra.backend_db_password
  sensitive   = true
}

output "backend_db_name" {
  description = "Backend Cloud SQL DB name (cicd_provider = \"none\" only). Read by the cicd module to build DATABASE_URL."
  value       = module.infra.backend_db_name
}

output "semantics_db_username" {
  description = "Semantics Cloud SQL DB username (cicd_provider = \"none\" only). Read by the cicd module to build VECTOR_DATABASE_URL."
  value       = module.infra.semantics_db_username
  sensitive   = true
}

output "semantics_db_password" {
  description = "Semantics Cloud SQL DB password (cicd_provider = \"none\" only). Read by the cicd module to build VECTOR_DATABASE_URL."
  value       = module.infra.semantics_db_password
  sensitive   = true
}

output "semantics_db_name" {
  description = "Semantics Cloud SQL DB name (cicd_provider = \"none\" only). Read by the cicd module to build VECTOR_DATABASE_URL."
  value       = module.infra.semantics_db_name
}

output "cloud_sql_ip" {
  description = "Private IP address of the Cloud SQL instance. Read by the cicd module to build DATABASE_URL/VECTOR_DATABASE_URL."
  value       = module.infra.cloud_sql_ip
  sensitive   = true
}

output "argocd_admin_password_plaintext" {
  description = "Plaintext ArgoCD admin password (self-service only). Read by the cicd module (app secret's ARGOCD_PASSWORD key) AND by examples/self-deploy/cicd's argocd provider config — this is the value that makes a same-apply provider \"argocd\" configuration unsafe, which is exactly why cicd is applied separately, reading it back via remote_state instead."
  value       = module.infra.argocd_admin_password_plaintext
  sensitive   = true
}

output "redis_credentials" {
  description = "Redis connection details (empty map when enable_redis_stack = false). Read by the cicd module to merge REDIS_* into the app secret."
  value       = module.infra.redis_credentials
  sensitive   = true
}

output "neo4j_credentials" {
  description = "Neo4j connection details (empty map when enable_neo4j = false). Read by the cicd module to merge NEO4J_* into the app secret."
  value       = module.infra.neo4j_credentials
  sensitive   = true
}

output "minio_endpoint" {
  description = "MinIO internal endpoint (empty when enable_minio = false). Read by the cicd module to merge MINIO_* into the app secret."
  value       = module.infra.minio_endpoint
}

output "minio_root_user" {
  description = "MinIO root user (empty when enable_minio = false). Read by the cicd module to merge MINIO_ACCESS_KEY into the app secret."
  value       = module.infra.minio_root_user
  sensitive   = true
}

output "minio_root_password" {
  description = "MinIO root password (empty when enable_minio = false). Read by the cicd module to merge MINIO_SECRET_ACCESS_KEY into the app secret."
  value       = module.infra.minio_root_password
  sensitive   = true
}

output "minio_default_buckets" {
  description = "MinIO default bucket names (empty list when enable_minio = false). Read by the cicd module to set EKAI_BUCKET in the app secret."
  value       = module.infra.minio_default_buckets
}

output "cluster_secret_store_name" {
  description = "ClusterSecretStore name. Read by the cicd module's ExternalSecret resource."
  value       = module.infra.cluster_secret_store_name
}
