# ──────────────────────────────────────────────────────────────────────────────
# platform submodule providers
# Submodule note: provider "google" {}, "kubernetes" {}, "helm" {}, and
# "kubectl" {} configuration blocks now live only in the root module's
# providers.tf (a submodule cannot declare a provider configuration block of
# its own) — see ../../providers.tf. Those blocks used to be configured here
# from a `data "terraform_remote_state" "cluster"` read (cluster_endpoint/
# cluster_ca_certificate/cluster_name); root now gets the same values
# directly from module.cluster's outputs.
#
# required_providers is kept here too — harmless, and documents this
# submodule's own provider requirements independent of root.
# ──────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
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
      version = "~> 3.6"
    }
  }
}
