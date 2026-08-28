# bootstrap submodule only manages Cloud DNS and the VPC.
# No GKE / Kubernetes providers needed — the cluster does not exist yet.
#
# Submodule note: provider "google" {} configuration now lives only in the
# root module's providers.tf (a submodule cannot declare a provider
# configuration block of its own — see ../../providers.tf). required_providers
# is kept here too — harmless, and documents this submodule's own provider
# requirements independent of root.

terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
