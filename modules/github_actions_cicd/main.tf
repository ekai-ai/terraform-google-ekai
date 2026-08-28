# ─── Data sources ─────────────────────────────────────────────────────────────

data "google_project" "current" {
  project_id = var.project_id
}

# ─── Locals ───────────────────────────────────────────────────────────────────

locals {
  # Unique set of bare repo names (strip "org/" prefix, deduplicate).
  # Used to create GitHub Actions secrets once per repo, not once per pipeline.
  unique_app_repos = toset([
    for svc, cfg in var.pipelines : split("/", cfg.github_repo)[1]
  ])

  # Map of service name → fully-qualified Artifact Registry repository URL
  # (without tag). Format: REGION-docker.pkg.dev/PROJECT/ENV-SERVICE
  image_map = {
    for svc, cfg in var.pipelines :
    svc => "${var.registry_url}/${svc}"
  }

  # Deployment-files repo URL used by the manifest-update steps.
  deploy_repo_url = "https://github.com/${var.github_org}/deployment-files.git"
  deploy_repo_dir = "${path.module}/_deploy_repo"

  # Artifact Registry Docker hostname — used for `gcloud auth configure-docker`.
  # Format: REGION-docker.pkg.dev
  ar_hostname = "${var.region}-docker.pkg.dev"

  # WIF pool and provider IDs — stable, deterministic names.
  wif_pool_id     = "github-actions-pool"
  wif_provider_id = "github-oidc"

  # Resolved pool name (create or look up).
  wif_pool_name = var.create_wif_pool ? (
    google_iam_workload_identity_pool.github[0].name
    ) : (
    data.google_iam_workload_identity_pool.github[0].name
  )
}

# ─── Workload Identity Federation pool (one per project) ──────────────────────
# create_wif_pool = false when another module already created it.

resource "google_iam_workload_identity_pool" "github" {
  count = var.create_wif_pool ? 1 : 0

  project                   = var.project_id
  workload_identity_pool_id = local.wif_pool_id
  display_name              = "GitHub Actions WIF Pool"
  description               = "Allows GitHub Actions OIDC tokens to authenticate to GCP."
}

data "google_iam_workload_identity_pool" "github" {
  count = var.create_wif_pool ? 0 : 1

  project                   = var.project_id
  workload_identity_pool_id = local.wif_pool_id
}

# ─── WIF OIDC provider (one per pool) ─────────────────────────────────────────
# Maps GitHub's OIDC token claims to GCP attributes used in SA bindings.

resource "google_iam_workload_identity_pool_provider" "github_oidc" {
  project                            = var.project_id
  workload_identity_pool_id          = local.wif_pool_id
  workload_identity_pool_provider_id = local.wif_provider_id
  display_name                       = "GitHub OIDC"
  description                        = "OIDC identity provider for github.com"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Only tokens issued by github.com are trusted.
  attribute_condition = "assertion.repository_owner == \"${var.github_org}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  depends_on = [
    google_iam_workload_identity_pool.github,
    data.google_iam_workload_identity_pool.github,
  ]
}

# ─── Service accounts — one per unique app repo ───────────────────────────────
# Each SA is impersonated by any workflow running in the corresponding repo.
# Using repo-scoped SAs (rather than one shared SA) limits blast radius.

resource "google_service_account" "github_actions" {
  for_each = local.unique_app_repos

  project      = var.project_id
  account_id   = "${var.env}-gh-${substr(each.key, 0, min(length(each.key), 18))}"
  display_name = "GitHub Actions — ${each.key} (${var.env})"
  description  = "Impersonated by GitHub Actions OIDC for repo ${var.github_org}/${each.key}"
}

# ── Artifact Registry writer ───────────────────────────────────────────────────

resource "google_project_iam_member" "ar_writer" {
  for_each = local.unique_app_repos

  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions[each.key].email}"
}

# ── Secret Manager accessor ────────────────────────────────────────────────────
# Allows the workflow SA to read env-scoped secrets from Secret Manager if needed.

resource "google_project_iam_member" "secret_accessor" {
  for_each = local.unique_app_repos

  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.github_actions[each.key].email}"
}

# ── WIF binding — allow GitHub repo's OIDC token to impersonate the SA ─────────
# The principalSet condition scopes impersonation to the specific repository.

resource "google_service_account_iam_binding" "wif_user" {
  for_each = local.unique_app_repos

  service_account_id = google_service_account.github_actions[each.key].name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${local.wif_pool_name}/attribute.repository/${var.github_org}/${each.key}",
  ]

  depends_on = [google_iam_workload_identity_pool_provider.github_oidc]
}

# ─── GitHub Actions secrets — pushed to each app repo ─────────────────────────
# The workflow YAML references these via secrets.<NAME>.
# ORG_TOKEN_GITHUB allows the manifest-update step to push to deployment-files.

resource "github_actions_secret" "wif_provider" {
  for_each = local.unique_app_repos

  repository      = each.key
  secret_name     = "GCP_WORKLOAD_IDENTITY_PROVIDER"
  value          = google_iam_workload_identity_pool_provider.github_oidc.name

  depends_on = [google_iam_workload_identity_pool_provider.github_oidc]
}

resource "github_actions_secret" "service_account" {
  for_each = local.unique_app_repos

  repository      = each.key
  secret_name     = "GCP_SERVICE_ACCOUNT"
  value          = google_service_account.github_actions[each.key].email

  depends_on = [google_service_account.github_actions]
}

resource "github_actions_secret" "gcp_region" {
  for_each = local.unique_app_repos

  repository      = each.key
  secret_name     = "GCP_REGION"
  value          = var.region
}

resource "github_actions_secret" "gcp_project_id" {
  for_each = local.unique_app_repos

  repository      = each.key
  secret_name     = "GCP_PROJECT_ID"
  value          = var.project_id
}

resource "github_actions_secret" "org_token_github" {
  for_each = local.unique_app_repos

  repository      = each.key
  secret_name     = "ORG_TOKEN_GITHUB"
  value          = var.github_token
}

# ─── GitHub Actions workflow YAML — one per pipeline ──────────────────────────
# Creates .github/workflows/gcp-ci.yml in each app repo.
# Mirrors the AWS ekai-ci.yml structure:
#   checkout → gcp-auth (OIDC) → setup-gcloud → configure-docker
#   → build & push → update manifest in deployment-files

resource "github_repository_file" "workflow" {
  for_each = var.pipelines

  repository          = split("/", each.value.github_repo)[1]
  branch              = each.value.branch
  file                = ".github/workflows/gcp-ci.yml"
  overwrite_on_create = true

  content = yamlencode({
    name = "Build & Push to Artifact Registry"

    on = {
      push = {
        branches = [each.value.branch]
      }
    }

    permissions = {
      "id-token" = "write"
      contents   = "read"
    }

    jobs = {
      build-push-deploy = {
        name      = "build-push-deploy"
        "runs-on" = "ubuntu-latest"

        steps = concat(
          [
            # Step 1: Checkout the application source.
            {
              name = "Checkout"
              uses = "actions/checkout@v4"
            },

            # Step 2: Authenticate to GCP via Workload Identity Federation (OIDC).
            # No static service account keys are stored anywhere.
            {
              name = "Authenticate to GCP (OIDC)"
              id   = "auth"
              uses = "google-github-actions/auth@v2"
              with = {
                workload_identity_provider = "$${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}"
                service_account            = "$${{ secrets.GCP_SERVICE_ACCOUNT }}"
              }
            },

            # Step 3: Install gcloud SDK so subsequent steps can call gcloud commands.
            {
              name = "Set up gcloud SDK"
              uses = "google-github-actions/setup-gcloud@v2"
            },

            # Step 4: Configure Docker to authenticate against Artifact Registry.
            {
              name = "Configure Docker for Artifact Registry"
              run  = "gcloud auth configure-docker ${local.ar_hostname} --quiet"
            },

            # Step 5: Build the Docker image and push it to Artifact Registry.
            # IMAGE env var is constructed here and exported to GITHUB_ENV so the
            # manifest-update step can reference it.
            {
              name = "Build & push image"
              env = {
                AR_REGISTRY = local.ar_hostname
                AR_REPO     = "${var.env}-${each.key}"
                GCP_PROJECT = "$${{ secrets.GCP_PROJECT_ID }}"
                IMAGE_TAG   = "$${{ github.sha }}"
              }
              run = join("\n", concat(
                each.value.pre_build_cmds,
                [
                  "IMAGE=${local.ar_hostname}/$$GCP_PROJECT/${var.env}-${each.key}:$$IMAGE_TAG",
                  each.value.build_cmd,
                  "docker push $$IMAGE",
                  "echo \"IMAGE=$$IMAGE\" >> $$GITHUB_ENV",
                ]
              ))
            },

            # Step 6: Clone deployment-files, patch the image tag in the manifest,
            # commit and push. Exits cleanly when there is nothing to commit.
            {
              name = "Update manifest in deployment-files"
              env = {
                GITHUB_TOKEN    = "$${{ secrets.ORG_TOKEN_GITHUB }}"
                CD_BRANCH       = var.cd_branch
                MANIFEST_FOLDER = each.value.manifest_folder
                MANIFEST_FILE   = each.value.manifest_file
                SERVICE         = each.key
              }
              run = <<-BASH
                git clone -b $CD_BRANCH https://x-access-token:$GITHUB_TOKEN@github.com/${var.github_org}/deployment-files.git
                cd deployment-files/$MANIFEST_FOLDER
                sed -i "s|${local.ar_hostname}/[^/]\\+/${var.env}-${each.key}:[^[:space:]]*|$IMAGE|g" $MANIFEST_FILE
                git config user.email "${var.github_email}"
                git config user.name  "${var.github_username}"
                git add .
                git diff --quiet && echo "No changes" && exit 0
                git commit -m "chore: update $SERVICE to $IMAGE_TAG"
                git push
              BASH
            },
          ]
        )
      }
    }
  })

  depends_on = [
    github_actions_secret.wif_provider,
    github_actions_secret.service_account,
    github_actions_secret.gcp_region,
    github_actions_secret.gcp_project_id,
    github_actions_secret.org_token_github,
  ]
}

# ─── Initial manifest image-tag seeding ───────────────────────────────────────
# Writes the initial Artifact Registry image references into the deployment repo.
# After first apply, GitHub Actions takes over on every push.
# Mirrors the AWS null_resource.update_manifests pattern exactly.

resource "null_resource" "seed_manifests" {
  triggers = {
    images = jsonencode(local.image_map)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      set -e
      REPO_URL="https://${var.github_token}@${replace(local.deploy_repo_url, "https://", "")}"
      rm -rf ${local.deploy_repo_dir}
      if ! git clone -b ${var.cd_branch} "$REPO_URL" ${local.deploy_repo_dir} 2>/dev/null; then
        git clone "$REPO_URL" ${local.deploy_repo_dir}
        git -C ${local.deploy_repo_dir} checkout -b ${var.cd_branch}
        git -C ${local.deploy_repo_dir} push origin ${var.cd_branch}
      fi

      cd "${local.deploy_repo_dir}/${try(values(var.pipelines)[0].manifest_folder, "manifest-files")}"

      %{for svc, uri in local.image_map}
      find . \( -name "*.yaml" -o -name "*.yml" \) | while read f; do
        sed -Ei "s|(image:[[:space:]]*)(.*/)?(${svc}:)|\1${replace(uri, "/", "\\/")}:|g" "$f"
      done
      %{endfor}

      if git diff --quiet; then
        echo "No changes to seed"
        cd /
        rm -rf ${local.deploy_repo_dir}
        exit 0
      fi

      git config user.email "${var.github_email}"
      git config user.name  "${var.github_username}"
      git add .
      git commit -m "chore: seed Artifact Registry image references"
      git push origin ${var.cd_branch}

      cd /
      rm -rf ${local.deploy_repo_dir}
    EOF
  }
}
