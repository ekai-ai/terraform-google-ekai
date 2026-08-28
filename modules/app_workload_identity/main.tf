###############################################################################
# GCP App Workload Identity Module
# Provider requirements are in versions.tf of the calling layer.
# Variables are in variables.tf — outputs are in outputs.tf
###############################################################################
# Auth flow (per service):
#   <service> pod  →  GKE Workload Identity  →  GSA ({env}-{service}-sa)
#                       ↓
#   GSA has roles/secretmanager.secretAccessor scoped to projects/.../secrets/{env}-{service}*
#   GSA has roles/storage.objectAdmin project-wide (GCS ≈ S3 equivalent)
#                       ↓
#   kubernetes_service_account is annotated with the GSA email so the GKE
#   metadata server exchanges the projected token automatically — no long-lived key.
###############################################################################

# ── One GSA per service ───────────────────────────────────────────────────────
resource "google_service_account" "service" {
  for_each = var.pipelines

  project      = var.project_id
  account_id   = "${var.env}-${each.key}-sa"
  display_name = "${each.key} workload identity SA"
  description  = "Workload Identity GSA for the ${each.key} service in ${var.env}."
}

# ── Secret Manager — scoped IAM condition per service ────────────────────────
# Each GSA can only read secrets whose name begins with "{env}-{service}".
# The condition uses the resource.name attribute which takes the form:
#   projects/PROJECT_NUMBER/secrets/SECRET_ID
# We match on the secret ID prefix so the condition works regardless of
# whether the caller uses the project number or the project ID in the path.
resource "google_project_iam_member" "secretmanager" {
  for_each = var.pipelines

  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.service[each.key].email}"

  condition {
    title       = "${var.env}-${each.key}-secrets-only"
    description = "Limit secret access to ${var.env}-${each.key}* secrets."
    expression  = "resource.name.startsWith(\"projects/${var.project_id}/secrets/${var.env}-${each.key}\")"
  }
}

# ── Cloud Storage — object-level access (GCS ≈ S3 equivalent) ────────────────
resource "google_project_iam_member" "storage" {
  for_each = var.pipelines

  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.service[each.key].email}"
}

# ── Workload Identity binding — K8s SA → GSA ─────────────────────────────────
# Allows the in-cluster ServiceAccount <ekai_namespace>/<service>-sa to
# impersonate the GSA via GKE Workload Identity Federation.
resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.pipelines

  service_account_id = google_service_account.service[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.ekai_namespace}/${each.key}-sa]"
}

# ── Kubernetes ServiceAccount — one per service, annotated with GSA email ─────
# The annotation is read by the GKE metadata server to exchange the projected
# OIDC token for a Google-scoped credential; no secret or key mount is needed.
resource "kubernetes_service_account" "service" {
  for_each = var.pipelines

  metadata {
    name      = "${each.key}-sa"
    namespace = var.ekai_namespace

    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.service[each.key].email
    }
  }

  depends_on = [google_service_account_iam_member.workload_identity]
}

# Variables are in variables.tf — outputs are in outputs.tf
