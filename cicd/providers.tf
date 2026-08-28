# ──────────────────────────────────────────────────────────────────────────────
# cicd providers — required_providers matches the union of what THIS config's
# own resources + module.cicd's tree actually use (mirrors the original
# 04-cicd/providers.tf exactly): google, kubernetes, helm, kubectl, argocd,
# github, time, random.
#
# provider "argocd" is THE reason this is a separate apply/state from
# ../ (bootstrap+cluster+platform) — see ../main.tf's file header. Its
# `password` is resolved below (local.argocd_admin_password) from a value
# Terraform already knows before this apply even starts — either the
# combined root's already-completed state (self-service), or an
# already-existing master Secret Manager secret (cloud_build/github_actions)
# — never a same-apply managed resource's computed attribute.
#
# local.argocd_admin_password duplicates a couple of lines of logic that also
# exist inside ../modules/cicd/main.tf (its own `self_service`/`_secret`
# locals, used there to populate the generated app secret) — that's
# unavoidable once main.tf's per-service logic lives one level down in a
# submodule: a submodule's `local` values aren't visible to this directory's
# own provider configuration. Both reads are plain, side-effect-free data
# source lookups (Secret Manager / remote state), so reading them twice is
# harmless — this is the same duplication AWS's cicd/providers.tf accepts for
# its own (simpler, self-service-only) equivalent.
#
# Cluster credentials are queried directly from the GKE API
# (`data.google_container_cluster`) rather than via remote state — this is
# UNCHANGED from the original 04-cicd/providers.tf (a deliberate GCP-specific
# choice already made by the source codebase, more reliable than a remote
# state read that could point at a stale/mismatched prefix).
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
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

provider "google" {
  project = var.project_id
  region  = var.region
}

# Query GKE cluster directly from GCP API — more reliable than reading from
# remote state (avoids empty-string from try() if state prefix mismatches).
# Mirrors how Azure reads AKS credentials from the cluster resource directly.
data "google_client_config" "default" {}

data "google_container_cluster" "gke" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region
}

locals {
  cluster_endpoint = data.google_container_cluster.gke.endpoint
  cluster_ca       = data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate
}

provider "kubernetes" {
  host                   = "https://${local.cluster_endpoint}"
  cluster_ca_certificate = base64decode(local.cluster_ca)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${local.cluster_endpoint}"
    cluster_ca_certificate = base64decode(local.cluster_ca)
    token                  = data.google_client_config.default.access_token
  }
}

provider "kubectl" {
  host                   = "https://${local.cluster_endpoint}"
  cluster_ca_certificate = base64decode(local.cluster_ca)
  token                  = data.google_client_config.default.access_token
  load_config_file       = false
}

# ── ArgoCD admin password — resolved here (not inside modules/cicd) because
# the provider block below needs it, and provider configuration can only ever
# live in this top-level config, never in a submodule. ──────────────────────
data "google_secret_manager_secret_version" "master" {
  count   = var.cicd_provider == "none" ? 0 : 1
  project = var.project_id
  secret  = var.secrets_name
}

locals {
  argocd_admin_password = (
    var.cicd_provider == "none"
    ? data.terraform_remote_state.combined.outputs.argocd_admin_password_plaintext
    : jsondecode(data.google_secret_manager_secret_version.master[0].secret_data)["argocd_admin_password_plain"]
  )
}

# ArgoCD provider — grpc_web=true because plain gRPC (HTTP/2) does not traverse
# HTTP/1.1 nginx proxies cleanly. gRPC-Web is HTTP/1.1 compatible and works
# through the nginx ingress at port 443.
provider "argocd" {
  # The workflow step "Get GKE credentials" starts kubectl port-forward to
  # svc/argocd-server:80 → localhost:8080 before Terraform runs.
  # Using server_addr instead of port_forward_with_namespace because GCP
  # token-based k8s auth doesn't support in-provider port-forwarding.
  #
  # DELIBERATE — do NOT change this to a real ingress hostname (unlike AWS's
  # equivalent cicd/providers.tf, which connects to a real ALB DNS name): a
  # fresh client domain's wildcard cert depends on Cloud DNS being delegated
  # at the registrar first (an out-of-band, human-timed step Terraform can't
  # wait for), which would otherwise block ArgoCD auth before the cluster
  # even has its first Application. Port-forwarding straight to the
  # Service's ClusterIP sidesteps DNS delegation and cert issuance entirely
  # for this step. scripts/self-deploy.sh and self-deploy-destroy.sh start
  # this port-forward before running terraform against ./ (this directory).
  server_addr = "localhost:8080"
  username    = "admin"
  password    = local.argocd_admin_password
  insecure    = true
  plain_text  = true
}

provider "github" {
  owner = var.github_org
  token = local.github_token
}

locals {
  # local.github_token mirrors modules/cicd/main.tf's own resolution of the
  # same value (self_service never uses it; non-self-service reads it from
  # the master Secret Manager secret) — needed here too because provider
  # "github" can only be configured at this level.
  github_token = var.cicd_provider == "none" ? "" : jsondecode(data.google_secret_manager_secret_version.master[0].secret_data)["github_token"]
}
