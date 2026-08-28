output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.main.name
}

output "cluster_endpoint" {
  description = "The IP address of the cluster master endpoint."
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public certificate of the cluster CA."
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_id" {
  description = "Fully-qualified cluster ID (projects/PROJECT/locations/REGION/clusters/NAME)."
  value       = google_container_cluster.main.id
}
