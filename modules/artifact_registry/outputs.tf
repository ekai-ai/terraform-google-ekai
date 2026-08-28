# Shared registry base URL — images go under REGION-docker.pkg.dev/PROJECT/ekaiENV/SERVICE:TAG
output "registry_url" {
  description = "Shared Artifact Registry URL: REGION-docker.pkg.dev/PROJECT/ekaiENV"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.shared.repository_id}"
}

output "image_map" {
  description = "Map of service name to its full image URL in the shared registry."
  value = {
    for svc in keys(var.services) :
    svc => "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.shared.repository_id}/${svc}"
  }
}
