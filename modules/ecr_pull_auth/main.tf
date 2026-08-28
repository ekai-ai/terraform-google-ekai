###############################################################################
# ECR Pull Auth Module
# Provider requirements are in versions.tf
# Variables are in variables.tf — outputs are in outputs.tf
###############################################################################
# Auth flow:
#   GCP Secret Manager (ecr_credentials_secret_name)
#     → kubernetes_secret "aws-ecr-credentials"  (AWS_ACCESS_KEY_ID + SECRET)
#       → CronJob mounts the secret as env vars
#         → aws ecr get-login-password | kubectl create secret docker-registry
#           → var.secret_name (docker-registry type) — consumed as imagePullSecrets
###############################################################################

# ── Read AWS IAM credentials from GCP Secret Manager ─────────────────────────
# The secret value must be a JSON object:
#   { "AWS_ACCESS_KEY_ID": "AKIA...", "AWS_SECRET_ACCESS_KEY": "..." }
data "google_secret_manager_secret_version" "ecr_credentials" {
  project = var.project_id
  secret  = var.ecr_credentials_secret_name
}

locals {
  ecr_creds    = jsondecode(data.google_secret_manager_secret_version.ecr_credentials.secret_data)
  ecr_registry = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

# ── Opaque secret: long-lived AWS IAM key for the refresher job ───────────────
# Only the refresh cron job uses this; application pods use the docker-registry
# secret (var.secret_name) that the job creates.
resource "kubernetes_secret" "aws_ecr_credentials" {
  metadata {
    name      = "aws-ecr-credentials"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    AWS_ACCESS_KEY_ID     = local.ecr_creds["AWS_ACCESS_KEY_ID"]
    AWS_SECRET_ACCESS_KEY = local.ecr_creds["AWS_SECRET_ACCESS_KEY"]
  }
}

# ── ServiceAccount for the refresh cron job ───────────────────────────────────
resource "kubernetes_service_account" "ecr_pull_refresher" {
  metadata {
    name      = "ecr-pull-refresher"
    namespace = var.namespace
  }
}

# ── Role: only the permissions required to create/replace the pull secret ─────
resource "kubernetes_role" "ecr_pull_refresher" {
  metadata {
    name      = "ecr-pull-refresher"
    namespace = var.namespace
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "create", "patch", "update", "delete"]
  }
}

# ── RoleBinding: bind the role to the refresher service account ───────────────
resource "kubernetes_role_binding" "ecr_pull_refresher" {
  metadata {
    name      = "ecr-pull-refresher"
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ecr_pull_refresher.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.ecr_pull_refresher.metadata[0].name
    namespace = var.namespace
  }
}

# ── CronJob: refresh the docker-registry pull secret every 6 h ───────────────
# alpine/k8s ships both `aws` (via apk) and `kubectl`.
# The job:
#   1. Fetches a fresh ECR password via aws ecr get-login-password.
#   2. Passes it to kubectl create secret docker-registry --dry-run=client | apply
#      so the secret is created on first run and patched on subsequent runs.
resource "kubernetes_cron_job_v1" "refresh_ecr_pull_secret" {
  metadata {
    name      = "refresh-ecr-pull-secret"
    namespace = var.namespace
  }

  spec {
    schedule                      = var.refresh_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = {
          app = "refresh-ecr-pull-secret"
        }
      }

      spec {
        # Retry up to 2 times on transient AWS/ECR errors.
        backoff_limit = 2

        template {
          metadata {}

          spec {
            service_account_name = kubernetes_service_account.ecr_pull_refresher.metadata[0].name

            restart_policy = "OnFailure"

            container {
              name  = "refresh"
              image = "alpine/k8s:1.29.6"

              command = ["/bin/sh", "-c"]
              args = [<<-EOT
                set -euo pipefail
                aws ecr get-login-password --region "$AWS_REGION" \
                  | kubectl create secret docker-registry "$SECRET_NAME" \
                      --docker-server="$ECR_REGISTRY" \
                      --docker-username=AWS \
                      --docker-password="$(cat)" \
                      --namespace="$NAMESPACE" \
                      --dry-run=client -o yaml \
                  | kubectl apply -f -
              EOT
              ]

              env {
                name  = "AWS_REGION"
                value = var.aws_region
              }
              env {
                name  = "ECR_REGISTRY"
                value = local.ecr_registry
              }
              env {
                name  = "SECRET_NAME"
                value = var.secret_name
              }
              env {
                name  = "NAMESPACE"
                value = var.namespace
              }

              # Inject AWS credentials from the Opaque secret.
              env {
                name = "AWS_ACCESS_KEY_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.aws_ecr_credentials.metadata[0].name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }
              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.aws_ecr_credentials.metadata[0].name
                    key  = "AWS_SECRET_ACCESS_KEY"
                  }
                }
              }

              resources {
                requests = {
                  cpu    = "50m"
                  memory = "64Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "128Mi"
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret.aws_ecr_credentials,
    kubernetes_role_binding.ecr_pull_refresher,
  ]
}

# Variables are in variables.tf — outputs are in outputs.tf
