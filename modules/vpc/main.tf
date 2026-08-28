# create vpc (custom mode — no auto-created subnets)
resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "${var.env}-${var.vpc_name}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  description = "Managed by Terraform — ${var.env} VPC"
}

# create private subnet with secondary ranges for GKE pods and services
resource "google_compute_subnetwork" "private" {
  project                  = var.project_id
  name                     = "${var.env}-private-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.env}-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.env}-services"
    ip_cidr_range = var.services_cidr
  }

  # GKE requires this label to discover the subnet
  # google_compute_subnetwork does not support freeform labels on secondary
  # ranges; the cluster name label is applied at the GKE cluster resource.

  description = "Managed by Terraform — ${var.env} private subnet"
}

# cloud router required by Cloud NAT
resource "google_compute_router" "router" {
  project     = var.project_id
  name        = "${var.env}-router"
  region      = var.region
  network     = google_compute_network.vpc.id
  description = "Managed by Terraform — ${var.env} Cloud Router"
}

# Cloud NAT — allows private nodes to reach the internet (image pulls, updates)
resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "${var.env}-cloud-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
