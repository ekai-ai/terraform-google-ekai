# ──────────────────────────────────────────────────────────────────────────────
# examples/self-deploy/cicd — the actual state-holding root config for the
# "cicd" module (../../../cicd = the repo's cicd/ directory). This is what
# scripts/self-deploy.sh runs `terraform init`/`apply` against, AFTER
# examples/self-deploy/root has already applied — cicd/'s own
# `data "terraform_remote_state" "combined"` block (inside ../../../cicd/
# main.tf) reads that apply's state directly, so this config doesn't need to
# pass any remote-state values itself; the module block below only carries
# genuine tfvars-driven inputs.
#
# required_providers here matches ../../../cicd/providers.tf's exactly — see
# examples/self-deploy/root/main.tf's header comment for why re-declaring
# matters even though the cicd module already configures these providers
# internally.
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"

  # Partial backend config — provide per-environment via -backend-config flag.
  # Example:
  #   terraform init -backend-config=../../../env/backend-<env>-cicd.tfbackend
  #
  # Second of the 2 states in this repo — see scripts/init-state-backend.sh
  # (run from the repo root — it writes backend files into env/, not here).
  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.11"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

module "cicd" {
  source = "../../../cicd"

  project_id                        = var.project_id
  region                            = var.region
  env                               = var.env
  state_bucket_name                 = var.state_bucket_name
  secrets_name                      = var.secrets_name
  dns_zone                          = var.dns_zone
  existing_image_registry_base_url  = var.existing_image_registry_base_url
  helm_chart_repo_url               = var.helm_chart_repo_url
  helm_chart_version                = var.helm_chart_version
  image_tag                         = var.image_tag
  erd_storage_class                 = var.erd_storage_class
  ingress_class_name                = var.ingress_class_name
  tls_secret_name                   = var.tls_secret_name
  secret_value_overrides            = var.secret_value_overrides
  pipelines                         = var.pipelines
  cd_branch                         = var.cd_branch
  manifest_folder                   = var.manifest_folder
  argocd_ingress_host               = var.argocd_ingress_host
  github_org                        = var.github_org
  ekai_namespace                    = var.ekai_namespace
  dns_zone_name                     = var.dns_zone_name
  cicd_provider                     = var.cicd_provider
  cluster_name                      = var.cluster_name
}
