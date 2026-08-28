# Provider requirements are in versions.tf
# Variables are in variables.tf — outputs are in outputs.tf

# ─── Data sources ─────────────────────────────────────────────────────────────

data "google_project" "current" {
  project_id = var.project_id
}

# ─── Secrets ──────────────────────────────────────────────────────────────────
# Read the shared secret (JSON blob) to extract the GitHub token.
data "google_secret_manager_secret_version" "secrets" {
  project = var.project_id
  secret  = var.secrets_name
}

locals {
  _secret      = jsondecode(data.google_secret_manager_secret_version.secrets.secret_data)
  github_token = local._secret["github_token"]

  # User-managed Cloud Build service account email.
  # GCP requires a user-managed SA when using available_secrets (Secret Manager).
  # The default SA (<number>@cloudbuild.gserviceaccount.com) cannot be explicitly
  # set in the trigger's service_account field.
  cloudbuild_sa = "${var.env}-cloudbuild-sa@${var.project_id}.iam.gserviceaccount.com"

  # Deployment-files repo URL — same convention as AWS module.
  deploy_repo_url = "https://github.com/${var.github_owner}/deployment-files.git"
}

# ─── User-managed Cloud Build Service Account ─────────────────────────────────
# GCP requires a user-managed SA when triggers use available_secrets.

resource "google_service_account" "cloudbuild" {
  project      = var.project_id
  account_id   = "${var.env}-cloudbuild-sa"
  display_name = "Cloud Build SA — ${var.env}"
}

resource "google_project_iam_member" "cloudbuild_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# ─── Cloud Build Triggers ─────────────────────────────────────────────────────
# One trigger per entry in var.pipelines.
# To add a new pipeline: add one entry to var.pipelines in your .tfvars file.
# No Terraform source files need to change.

resource "google_cloudbuild_trigger" "service" {
  for_each = var.pipelines

  project     = var.project_id
  name        = "${var.env}-${each.key}-cicd"
  description = "Build, push Artifact Registry image, update deployment manifest — ${each.key}"

  # ── GitHub source ────────────────────────────────────────────────────────────
  github {
    owner = var.github_owner
    name  = each.value.github_repo

    push {
      branch = "^${each.value.branch}$"
    }
  }

  # ── Inline build config ──────────────────────────────────────────────────────
  # Steps mirror the AWS buildspec phases: build → push → manifest update.
  build {
    # Step 1: authenticate with Artifact Registry and build the Docker image.
    step {
      id   = "docker-build"
      name = "gcr.io/cloud-builders/docker"
      env  = ["DOCKER_BUILDKIT=1"]
      args = [
        "build",
        "--platform", "linux/amd64",
        "--build-arg", "TARGETARCH=amd64",
        "-f", each.value.dockerfile,
        "-t", "${var.registry_url}/${each.key}:$SHORT_SHA",
        each.value.build_context,
      ]
    }

    # Step 2: push the tagged image to Artifact Registry.
    step {
      id   = "docker-push"
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.registry_url}/${each.key}:$SHORT_SHA",
      ]
    }

    # Step 3: clone deployment-files, patch the manifest image tag, commit and push.
    # GITHUB_TOKEN → Secret Manager (sensitive, never in logs)
    # _GH_USER / _GH_EMAIL → substitutions (non-sensitive, avoids bash var validation error)
    step {
      id         = "update-manifest"
      name       = "gcr.io/cloud-builders/git"
      entrypoint = "bash"
      args = [
        "-c",
        <<-BASH
          set -euo pipefail

          # Extract token from master secret JSON (token is sensitive → via secret_env)
          TOKEN=$(echo "$$MASTER_SECRET" | python3 -c "import json,sys; print(json.load(sys.stdin)['github_token'])")

          git clone -b ${var.cd_branch} \
            "https://$_GH_USER:$$TOKEN@github.com/${var.github_owner}/deployment-files.git" \
            /workspace/deployment-files

          cd /workspace/deployment-files/${each.value.manifest_folder}

          sed -i "s|image: .*|image: $_REGISTRY/$_SERVICE:$SHORT_SHA|" ${each.value.manifest_file}

          git config user.email "$_GH_EMAIL"
          git config user.name  "$_GH_USER"
          git add ${each.value.manifest_file}
          git diff --cached --quiet && echo "nothing to commit" && exit 0

          git commit -m "chore: update ${each.key} to $SHORT_SHA"
          git push "https://$_GH_USER:$$TOKEN@github.com/${var.github_owner}/deployment-files.git" \
            HEAD:${var.cd_branch}
        BASH
      ]
      secret_env = ["MASTER_SECRET"]
    }

    # ── Available secrets ──────────────────────────────────────────────────────
    # Master secret JSON injected as MASTER_SECRET; bash extracts token inline.
    # Username/email are non-sensitive → substitutions (_GH_USER, _GH_EMAIL).
    available_secrets {
      secret_manager {
        version_name = "projects/${var.project_id}/secrets/${var.secrets_name}/versions/latest"
        env          = "MASTER_SECRET"
      }
    }

    # ── Substitutions ─────────────────────────────────────────────────────────
    substitutions = {
      _REGISTRY = var.registry_url
      _SERVICE  = each.key
      _ENV      = var.env
      _GH_USER  = local._secret["github_username"]
      _GH_EMAIL = local._secret["github_email"]
    }

    options {
      logging = "CLOUD_LOGGING_ONLY"
    }

    tags = [var.env, each.key, "cicd"]
  }

  # User-managed SA required when using available_secrets (Secret Manager).
  service_account = google_service_account.cloudbuild.id

  depends_on = [
    google_service_account.cloudbuild,
    google_project_iam_member.cloudbuild_artifact_writer,
    google_project_iam_member.cloudbuild_secret_accessor,
    google_project_iam_member.cloudbuild_log_writer,
    google_project_iam_member.cloudbuild_builder,
  ]
}

# Variables are in variables.tf — outputs are in outputs.tf
