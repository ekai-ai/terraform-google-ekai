###############################################################################
# GKE Standard Cluster Module
# Provider requirements are in versions.tf
# Variables are in variables.tf — outputs are in outputs.tf
###############################################################################

###############################################################################
# Data sources
###############################################################################

data "google_compute_network" "vpc" {
  project = var.project_id
  name    = var.vpc_name
}

data "google_compute_subnetwork" "subnet" {
  project = var.project_id
  region  = var.region
  name    = var.subnet_name
}

###############################################################################
# GKE Cluster
###############################################################################

resource "google_container_cluster" "main" {
  project            = var.project_id
  name               = var.cluster_name
  location           = var.region # regional (not zonal)
  deletion_protection = var.env == "prod" ? true : false # protect prod cluster

  # Kubernetes version — empty string = GKE picks latest stable from REGULAR channel
  min_master_version = var.k8s_version != "" ? var.k8s_version : null

  # Networking
  network    = data.google_compute_network.vpc.self_link
  subnetwork = data.google_compute_subnetwork.subnet.self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Private cluster — nodes have no public IPs; master is publicly reachable
  # so kubectl works without a bastion (private_endpoint = false).
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    # Required when enable_private_nodes = true. Must not overlap with
    # the VPC CIDR or any subnet CIDR. /28 is the minimum GKE allows.
    master_ipv4_cidr_block = var.master_ipv4_cidr_block
  }

  # Remove the default node pool immediately; the custom pool below is used.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network policy (Calico)
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Required for network policy / Calico
  addons_config {
    network_policy_config {
      disabled = false
    }
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Logging & monitoring (managed, GKE defaults)
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Maintenance window — Sunday 04:00 UTC; adjust per environment as needed.
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T04:00:00Z"
      end_time   = "2024-01-01T08:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  resource_labels = {
    env     = var.env
    cluster = var.cluster_name
    managed = "terraform"
  }

  lifecycle {
    ignore_changes = [
      # Prevents drift when GKE auto-upgrades the master version.
      min_master_version,
      # node_version is managed by the node pool resource below.
    ]
  }
}

###############################################################################
# Custom Node Pool
###############################################################################

resource "google_container_node_pool" "main" {
  project  = var.project_id
  name     = "${var.cluster_name}-pool"
  location = var.region
  cluster  = google_container_cluster.main.name

  version = var.k8s_version != "" ? var.k8s_version : null

  # Autoscaling — one replica of min/max per zone in the region.
  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  # Roll nodes one at a time; keeps the cluster available during upgrades.
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.node_machine_type

    # Use a dedicated SA per cluster rather than the Compute default SA.
    # The SA must be created outside this module and passed in via var.node_service_account.
    service_account = var.node_service_account

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Workload Identity on nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Shielded nodes — recommended for all production workloads.
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    disk_type    = "pd-ssd"
    disk_size_gb = 100
    # Ubuntu required for Landlock LSM (CONFIG_SECURITY_LANDLOCK) — used by
    # ekai-erd sandbox isolation. COS disables Landlock by default.
    image_type   = "UBUNTU_CONTAINERD"

    labels = {
      env     = var.env
      cluster = var.cluster_name
      managed = "terraform"
    }

    tags = [
      "gke-node",
      "${var.cluster_name}-node",
    ]

    metadata = {
      # Disable legacy IMDS endpoint on nodes.
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [
      # GKE auto-upgrade bumps version; Terraform should not revert it.
      version,
    ]
  }
}

# Variables are in variables.tf — outputs are in outputs.tf
