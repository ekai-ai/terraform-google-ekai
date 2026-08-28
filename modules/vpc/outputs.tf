# outputs.tf

output "vpc_id" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Name of the private subnet"
  value       = google_compute_subnetwork.private.name
}

output "subnet_self_link" {
  description = "Self-link of the private subnet"
  value       = google_compute_subnetwork.private.self_link
}

output "pods_range_name" {
  description = "Name of the secondary IP range for GKE pods"
  value       = "${var.env}-pods"
}

output "services_range_name" {
  description = "Name of the secondary IP range for GKE services"
  value       = "${var.env}-services"
}
