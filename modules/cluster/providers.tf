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
# google's version constraint was originally ">= 5.0, < 6.0" here, which
# directly CONFLICTS with the bootstrap submodule's "~> 6.0" (empty
# intersection: nothing satisfies both >= 6.0 and < 6.0). That conflict was
# invisible in the original 4-layer design because 01-bootstrap and
# 02-cluster were separate `terraform init`s with independent provider
# installs. Now that bootstrap+cluster+platform share one combined module
# tree, Terraform aggregates required_providers constraints across every
# module actually instantiated in the graph, so the two constraints must be
# simultaneously satisfiable. Widened to ">= 5.0, < 7.0" here to match what
# this submodule's own children (modules/gke, modules/cloud_sql,
# modules/artifact_registry) already declare — this is the smaller, more
# conservative edit (relaxing the accidentally-narrow constraint) rather than
# tightening bootstrap's.
terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}
