terraform {
  required_providers {
    helm       = { source = "hashicorp/helm", version = "~> 2.16" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
