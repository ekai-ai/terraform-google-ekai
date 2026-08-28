###############################################################################
# GCP External Secrets Operator Module — Workload Identity
# Provider requirements are in versions.tf
# Variables are in variables.tf — outputs are in outputs.tf
###############################################################################
# Auth flow:
#   ESO pod  →  GKE Workload Identity  →  GSA (eso-{env})
#              ↓
#   GSA has roles/secretmanager.secretAccessor on this project
#              ↓
#   ClusterSecretStore uses workloadIdentity auth → no long-lived key needed
###############################################################################

# ── Google Service Account for ESO ────────────────────────────────────────────
resource "google_service_account" "eso" {
  project      = var.project_id
  account_id   = "eso-${var.env}"
  display_name = "External Secrets Operator — ${var.env}"
  description  = "Workload Identity SA used by ESO to read Secret Manager secrets in ${var.env}."
}

# ── IAM: allow ESO GSA to read secrets project-wide ──────────────────────────
# Scoped to the project — ExternalSecret resources filter by name at read time.
resource "google_project_iam_member" "eso_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso.email}"
}

# ── Workload Identity binding ─────────────────────────────────────────────────
# Allows the K8s SA external-secrets/external-secrets (created by the Helm chart)
# to impersonate the GSA via GKE Workload Identity Federation.
resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}

# ── ESO namespace ─────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "eso" {
  metadata {
    name = "external-secrets"
  }
}

# ── ESO Helm release ──────────────────────────────────────────────────────────
# The ServiceAccount is annotated with the GSA email so the GKE metadata server
# exchanges the projected token for a Google-scoped credential automatically.
resource "helm_release" "eso" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace.eso.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version

  values = [yamlencode({
    installCRDs = true

    serviceAccount = {
      create = true
      name   = "external-secrets"
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.eso.email
      }
    }
  })]

  depends_on = [
    kubernetes_namespace.eso,
    google_service_account_iam_member.eso_workload_identity,
  ]
}

# ── ClusterSecretStore — points at GCP Secret Manager ────────────────────────
# Cluster-scoped so any namespace can reference it via ExternalSecret without
# per-namespace wiring — mirrors the AWS ClusterSecretStore pattern.
# workloadIdentity auth delegates credential acquisition to the annotated K8s SA;
# no service account key JSON is stored in the cluster.
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "gcp-secrets-manager"
    }
    spec = {
      provider = {
        gcpsm = {
          projectID = var.project_id
          auth = {
            workloadIdentity = {
              clusterLocation = var.region
              clusterName     = var.cluster_name
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.eso]
}

# Variables are in variables.tf — outputs are in outputs.tf
