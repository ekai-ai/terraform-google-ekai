terraform {
  required_version = ">= 1.5"

  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.18"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 3.0"
    }
  }
}
