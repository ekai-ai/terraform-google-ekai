# ──────────────────────────────────────────────────────────────────────────────
# Root outputs — two audiences:
#
#   1. End-state values a client actually wants to see after `terraform apply`
#      (argocd_url/admin creds, DNS zone info, cluster_name, region).
#
#   2. Values ./cicd/'s `data "terraform_remote_state" "combined"` block reads
#      (artifact_registry_url, backend/semantics db creds, cloud_sql_ip,
#      nginx_ingress_ip, argocd_admin_password_plaintext, redis_credentials,
#      neo4j_credentials, minio_*, cluster_secret_store_name) — these exist
#      here ONLY because ./cicd/ needs them; a human applying this config
#      alone wouldn't otherwise care. Named to match exactly what the original
#      cluster/platform layers' outputs were called, so the remote_state read
#      in ./cicd/main.tf is a direct, traceable rename of
#      `data.terraform_remote_state.cluster.outputs.X` /
#      `data.terraform_remote_state.platform.outputs.X` →
#      `data.terraform_remote_state.combined.outputs.X`.
#
# portal_url / argocd_app_name / ekai_namespace moved to ./cicd/outputs.tf —
# they don't exist until the cicd apply runs (this root doesn't deploy the app).
# ──────────────────────────────────────────────────────────────────────────────

output "argocd_url" {
  description = "ArgoCD's public URL."
  value       = "https://${module.platform.argocd_ingress_host}"
}

output "argocd_admin_username" {
  description = "ArgoCD admin username — always literally \"admin\"."
  value       = "admin"
}

output "argocd_admin_password" {
  description = "ArgoCD admin plaintext password (cicd_provider = \"none\" only — self-service generates this directly; non-self-service envs get it from their master Secret Manager secret instead, not exposed here)."
  value       = module.platform.argocd_admin_password_plaintext
  sensitive   = true
}

output "dns_zone_name" {
  description = "Cloud DNS managed zone resource name actually in use (whichever the bootstrap submodule created or was pointed at)."
  value       = module.bootstrap.dns_zone_name
}

output "dns_zone_dns_name" {
  description = "DNS name of the managed zone (e.g. dev.example.com.)."
  value       = module.bootstrap.dns_zone_dns_name
}

output "name_servers" {
  description = "Cloud DNS nameservers for this zone -- delegate dns_zone to these at your domain registrar."
  value       = module.bootstrap.name_servers
}

output "vpc_name" {
  description = "Name of the VPC network."
  value       = module.bootstrap.vpc_name
}

output "vpc_id" {
  description = "Self-link of the VPC network."
  value       = module.bootstrap.vpc_id
}

output "cluster_name" {
  description = "Name of the GKE cluster — use with: gcloud container clusters get-credentials <this> --region <region> --project <project_id>"
  value       = module.cluster.cluster_name
}

output "nginx_ingress_ip" {
  description = "External IP of the nginx ingress LoadBalancer. Delegate DNS for dns_zone to this zone's name servers, and point any externally-managed records (e.g. a parent-zone NS delegation) at it before relying on cert-manager's DNS-01 challenge to succeed."
  value       = module.platform.nginx_ingress_ip
}

output "region" {
  description = "GCP region this was deployed into."
  value       = var.region
}

# ═══════════════════════════════════════════════════════════════════════════
# Consumed by ./cicd/'s data "terraform_remote_state" "combined" block only
# ═══════════════════════════════════════════════════════════════════════════

output "artifact_registry_url" {
  description = "Artifact Registry base URL: REGION-docker.pkg.dev/PROJECT. Read by ./cicd/'s Cloud Build/GitHub Actions module inputs and its Artifact Registry image map output."
  value       = module.cluster.artifact_registry_url
}

output "backend_db_username" {
  description = "Backend Cloud SQL DB username (cicd_provider = \"none\" only). Read by ./cicd/ to build DATABASE_URL."
  value       = module.cluster.backend_db_username
  sensitive   = true
}

output "backend_db_password" {
  description = "Backend Cloud SQL DB password (cicd_provider = \"none\" only). Read by ./cicd/ to build DATABASE_URL."
  value       = module.cluster.backend_db_password
  sensitive   = true
}

output "backend_db_name" {
  description = "Backend Cloud SQL DB name (cicd_provider = \"none\" only). Read by ./cicd/ to build DATABASE_URL."
  value       = module.cluster.backend_db_name
}

output "semantics_db_username" {
  description = "Semantics Cloud SQL DB username (cicd_provider = \"none\" only). Read by ./cicd/ to build VECTOR_DATABASE_URL."
  value       = module.cluster.semantics_db_username
  sensitive   = true
}

output "semantics_db_password" {
  description = "Semantics Cloud SQL DB password (cicd_provider = \"none\" only). Read by ./cicd/ to build VECTOR_DATABASE_URL."
  value       = module.cluster.semantics_db_password
  sensitive   = true
}

output "semantics_db_name" {
  description = "Semantics Cloud SQL DB name (cicd_provider = \"none\" only). Read by ./cicd/ to build VECTOR_DATABASE_URL."
  value       = module.cluster.semantics_db_name
}

output "cloud_sql_ip" {
  description = "Private IP address of the Cloud SQL instance. Read by ./cicd/ to build DATABASE_URL/VECTOR_DATABASE_URL."
  value       = module.cluster.cloud_sql_ip
  sensitive   = true
}

output "argocd_admin_password_plaintext" {
  description = "Plaintext ArgoCD admin password (self-service only). Read by ./cicd/main.tf (app secret's ARGOCD_PASSWORD key) AND by ./cicd/providers.tf's argocd provider config — this is the value that made a same-apply provider \"argocd\" configuration unsafe, which is exactly why cicd is a separate apply reading it via remote_state instead."
  value       = module.platform.argocd_admin_password_plaintext
  sensitive   = true
}

output "redis_credentials" {
  description = "Redis connection details (empty map when enable_redis_stack = false). Read by ./cicd/ to merge REDIS_* into the app secret."
  value       = module.platform.redis_credentials
  sensitive   = true
}

output "neo4j_credentials" {
  description = "Neo4j connection details (empty map when enable_neo4j = false). Read by ./cicd/ to merge NEO4J_* into the app secret."
  value       = module.platform.neo4j_credentials
  sensitive   = true
}

output "minio_endpoint" {
  description = "MinIO internal endpoint (empty when enable_minio = false). Read by ./cicd/ to merge MINIO_* into the app secret."
  value       = module.platform.minio_endpoint
}

output "minio_root_user" {
  description = "MinIO root user (empty when enable_minio = false). Read by ./cicd/ to merge MINIO_ACCESS_KEY into the app secret."
  value       = module.platform.minio_root_user
  sensitive   = true
}

output "minio_root_password" {
  description = "MinIO root password (empty when enable_minio = false). Read by ./cicd/ to merge MINIO_SECRET_ACCESS_KEY into the app secret."
  value       = module.platform.minio_root_password
  sensitive   = true
}

output "minio_default_buckets" {
  description = "MinIO default bucket names (empty list when enable_minio = false). Read by ./cicd/ to set EKAI_BUCKET in the app secret."
  value       = module.platform.minio_default_buckets
}

output "cluster_secret_store_name" {
  description = "ClusterSecretStore name. Read by ./cicd/'s ExternalSecret resource."
  value       = module.platform.cluster_secret_store_name
}
