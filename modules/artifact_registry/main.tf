# Provider requirements are in versions.tf

# ---------------------------------------------------------------------------
# Single shared Artifact Registry repository for all services in an env.
# Image path: REGION-docker.pkg.dev/PROJECT/ENV/SERVICE:TAG
# e.g.       us-central1-docker.pkg.dev/ekai-dev/demo/ekai-backend:abc1234
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "shared" {
  project       = var.project_id
  location      = var.region
  repository_id = "ekai${var.env}"
  description   = "Shared Docker registry for ${var.env} — all services"
  format        = "DOCKER"

  labels = {
    env     = var.env
    managed = "terraform"
  }
}

# ---------------------------------------------------------------------------
# IAM — GKE node SA: reader on the shared repository
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository_iam_member" "gke_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.shared.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.gke_node_sa_email}"
}

# ---------------------------------------------------------------------------
# IAM — Cloud Build SA: writer on the shared repository
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository_iam_member" "cloudbuild_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.shared.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.cloudbuild_sa_email}"
}
