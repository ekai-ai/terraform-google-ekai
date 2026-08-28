# ──────────────────────────────────────────────────────────────────────────────
# cicd submodule — Provider requirements
# Submodule note: provider "google" {}, "kubernetes" {}, "helm" {},
# "kubectl" {}, "argocd" {}, and "github" {} configuration blocks now live
# only in ../../cicd/providers.tf (one level up — a submodule cannot declare
# a provider configuration block of its own). Those blocks used to be
# configured here directly (cluster credentials queried straight from the
# GKE API via `data.google_container_cluster`, the ArgoCD provider from a
# `data "terraform_remote_state" "platform"` read); the top-level cicd/
# config now does both, unchanged in mechanism — see that file for why.
#
# required_providers is kept here too — harmless, and documents this
# submodule's own provider requirements independent of the top-level config.
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
