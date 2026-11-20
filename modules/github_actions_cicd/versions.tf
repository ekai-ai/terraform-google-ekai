terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.11"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.3"
    }
  }
}
