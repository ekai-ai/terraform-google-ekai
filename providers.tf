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
# google's version constraint: every module in this tree declares the same
# "~> 8.11". Terraform intersects the constraints of every module it loads,
# so they must agree (an earlier ">= 5.0, < 6.0" vs "~> 6.0" split had an
# empty intersection and could not install at all).
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
      version = "~> 8.11"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
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
  kubernetes = {
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
  # The endpoint and CA come from module.cluster, which this same apply
  # creates, so they are unknown on a new env's first plan. alekc/kubectl
  # checks its connection when it is configured and fails ("kubectl
  # provider: configure failed"); lazy_load waits until a kubectl_manifest
  # needs the connection, as gavinbunney/kubectl always did.
  lazy_load = true
}
