# ──────────────────────────────────────────────────────────────────────────────
# Root providers (bootstrap + cluster + platform) — required_providers is the
# union of what THESE 3 submodules' trees actually use. Provider
# *configuration* blocks (provider "google" {}, "kubernetes" {}, "helm" {},
# "kubectl" {}) live here (this directory still configures its own providers,
# same as before — only the backend block moved out, see below) — the
# bootstrap/cluster/platform submodules cannot declare their own provider
# config, only require providers via their own required_providers block (kept
# in each modules/<name>/providers.tf for documentation).
#
# provider "argocd" is intentionally NOT declared here (moved to ./cicd/
# providers.tf instead): nothing under bootstrap/cluster/platform's module
# tree creates an argocd_* resource — only modules/ekai_CD does (verified by
# grep), and that module is only ever called by modules/cicd, which is not
# part of this root anymore. See main.tf's file header for the full reasoning
# (the argocd provider's `password` field can't safely be configured from a
# same-apply resource attribute the way kubernetes/helm/kubectl's token-based
# auth can — that's WHY cicd is split back out into its own apply).
#
# provider "github" is also NOT declared: nothing under bootstrap/cluster/
# platform's module tree creates a github_* resource — only
# modules/github_actions_cicd does, and that module is only ever called by
# modules/cicd.
#
# google's version constraint: bootstrap declared "~> 6.0" and the original
# cluster layer declared ">= 5.0, < 6.0" — two constraints with an EMPTY
# intersection. This conflict was invisible in the original 4-layer design
# (each layer ran its own separate `terraform init`); combining them into one
# module tree surfaces it. Resolved in modules/cluster/providers.tf by
# widening that submodule's own constraint to ">= 5.0, < 7.0" (matching what
# its own children already declared) — see that file's comment for the full
# reasoning. "~> 6.0" here reflects the version this repo is actually tested
# against (matches bootstrap's original constraint).
#
# required_version — the strictest of the 3 original layers' (bootstrap
# required ">= 1.6", the original cluster layer required ">= 1.6", platform
# required ">= 1.5"); Terraform checks each submodule's own required_version
# block too, so this mainly documents the real minimum up front.
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6"

  # No backend block here — this directory is a reusable Terraform module
  # (module "infra" { source = "registry.terraform.io/ekai-ai/ekai/google" }
  # for registry consumers, or a plain relative `source` for anyone using this
  # repo directly), not a state-holding root config. The actual root config
  # that DOES declare a backend and gets applied is
  # examples/self-deploy/root/ — see that directory's main.tf, and
  # scripts/init-state-backend.sh for how its backend config is generated.
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
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

provider "google" {
  project = var.project_id
  region  = var.region
}

# Kubernetes/Helm/kubectl providers — configured from the cluster submodule's
# own outputs. This is a same-apply "provider configured from a resource this
# apply also creates" pattern: Terraform defers actually connecting until the
# first kubernetes/helm/kubectl resource is planned/applied (all of which live
# inside the cluster/platform submodules), by which time the GKE cluster
# already exists. This works because the token below is fetched fresh at
# plan/apply time from the already-authenticated gcloud/Terraform Google
# provider identity (`data.google_client_config.default.access_token`), the
# same trick the source codebase's own cluster layer already relied on for
# its same-apply kubernetes/helm/kubectl providers. (The ArgoCD provider does
# NOT have this escape hatch, which is why it's configured in
# ./cicd/providers.tf from a remote_state read instead — see main.tf's file
# header.)
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.cluster.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.cluster.cluster_endpoint}"
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

provider "kubectl" {
  host                   = "https://${module.cluster.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
  load_config_file       = false
}
