# main.tf
# NOTE: The GCS state bucket is created by scripts/init-state-backend.sh
# (outside Terraform) to avoid the chicken-and-egg problem where Terraform
# needs the bucket to store its own state. Do NOT add google_storage_bucket
# here — the init script owns the bucket lifecycle.

# ---------------------------------------------------------------------------
# Cloud DNS managed zone
# ---------------------------------------------------------------------------

# Created when manage_dns_zone = true
resource "google_dns_managed_zone" "env" {
  count         = var.manage_dns_zone ? 1 : 0
  project       = var.project_id
  name          = "${var.env}-zone"
  dns_name      = "${var.dns_zone}."
  description   = "Managed by Terraform — ${var.env} DNS zone"
  force_destroy = true # deletes all records before destroying the zone

  labels = {
    env     = var.env
    managed = "terraform"
  }
}

# Looked up when manage_dns_zone = false (zone was pre-created outside Terraform)
data "google_dns_managed_zone" "env" {
  count   = var.manage_dns_zone ? 0 : 1
  project = var.project_id
  name    = "${var.env}-zone"
}

# NOTE: No managed SSL certificate here. GCP's google_compute_managed_ssl_certificate
# does NOT support wildcard domains (*.example.com). Wildcard TLS is handled by
# cert-manager in the platform submodule using Let's Encrypt DNS-01 challenges via Cloud DNS.

# ---------------------------------------------------------------------------
# VPC, subnet, Cloud Router, and Cloud NAT
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../vpc"

  project_id    = var.project_id
  env           = var.env
  region        = var.region
  vpc_name      = var.vpc_name
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
}
