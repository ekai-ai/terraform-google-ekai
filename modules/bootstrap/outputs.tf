# outputs.tf
# All values consumed by the cluster/platform submodules via direct
# module.bootstrap.X references at root (see ../../main.tf) instead of the
# original `data "terraform_remote_state" "bootstrap" { ... }` reads.

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
output "vpc_name" {
  description = "Name of the VPC network"
  value       = module.vpc.vpc_name
}

output "vpc_id" {
  description = "Self-link of the VPC network"
  value       = module.vpc.vpc_id
}

output "subnet_name" {
  description = "Name of the private subnet"
  value       = module.vpc.subnet_name
}

output "subnet_self_link" {
  description = "Self-link of the private subnet"
  value       = module.vpc.subnet_self_link
}

output "pods_range_name" {
  description = "Secondary IP range name for GKE pods"
  value       = module.vpc.pods_range_name
}

output "services_range_name" {
  description = "Secondary IP range name for GKE services"
  value       = module.vpc.services_range_name
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------
output "dns_zone_name" {
  description = "Cloud DNS managed zone resource name"
  value = (
    var.manage_dns_zone
    ? google_dns_managed_zone.env[0].name
    : data.google_dns_managed_zone.env[0].name
  )
}

output "dns_zone_dns_name" {
  description = "DNS name of the managed zone (e.g. dev.example.com.)"
  value = (
    var.manage_dns_zone
    ? google_dns_managed_zone.env[0].dns_name
    : data.google_dns_managed_zone.env[0].dns_name
  )
}

output "name_servers" {
  description = "Cloud DNS nameservers for this zone -- delegate dns_zone to these at your domain registrar (matches AWS's route53_name_servers output)."
  value = (
    var.manage_dns_zone
    ? google_dns_managed_zone.env[0].name_servers
    : data.google_dns_managed_zone.env[0].name_servers
  )
}

# ---------------------------------------------------------------------------
# NOTE: SSL certificate outputs removed — wildcard TLS is handled by cert-manager
# in the platform submodule (Let's Encrypt DNS-01). GCP managed SSL certs don't support wildcards.

# ---------------------------------------------------------------------------
# State bucket
# ---------------------------------------------------------------------------
output "state_bucket_name" {
  description = "Name of the GCS bucket used for Terraform state (created by scripts/init-state-backend.sh)"
  value       = var.state_bucket_name
}
