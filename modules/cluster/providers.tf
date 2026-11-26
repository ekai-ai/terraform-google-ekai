###############################################################################
# cluster submodule — Provider requirements
###############################################################################
# Submodule note: provider "google" {}, "kubernetes" {}, "helm" {}, and
# "kubectl" {} configuration blocks now live only in the root module's
# providers.tf (a submodule cannot declare a provider configuration block of
# its own) — see ../../providers.tf. Those blocks used to be configured here
# directly (this submodule's own module.gke output, same-apply); root now
# gets the same values from module.cluster's outputs one level up.
#
# required_providers is kept here too — harmless, and documents this
# submodule's own provider requirements independent of root.
#
# google-beta was declared in the original 02-cluster/providers.tf but never
# actually used by any resource in this module tree (verified by grep — no
# `provider = google-beta` anywhere) — dropped here as genuinely dead.
#
# google's version constraint: every module in this tree declares the same
# "~> 8.11". Terraform intersects the constraints of every module it loads,
# so they must agree (an earlier ">= 5.0, < 6.0" vs "~> 6.0" split had an
# empty intersection and could not install at all).
terraform {
  required_version = ">= 1.6"

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
      version = "~> 0.12"
    }
  }
}
