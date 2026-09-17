locals {
  repo_url = var.source_type == "git" ? "https://github.com/${var.github_org}/deployment-files.git" : var.helm_repo_url

  # ArgoCD Image Updater annotations -- self-service (source_type == "helm")
  # only. Every tracked image uses a mutable "latest" tag, so ArgoCD's own
  # diffing never notices a new push (the manifest text never changes);
  # Image Updater polls each image's digest and patches this Application's
  # Helm parameters when it changes, giving ArgoCD a real diff to sync.
  # write-back-method "argocd" patches the Application directly (there's no
  # git repo to commit to for a Helm/OCI-sourced self-service install).
  # Aliases/value paths match the chart's existing per-service
  # <service>.image.{repository,tag} values exactly (see values.yaml) --
  # semantics/profile are skipped since they're disabled for self-service.
  image_updater_images = {
    backend         = "backend"
    frontend        = "frontend"
    erd             = "erd"
    document-worker = "erd.documentWorker"
    profile-worker  = "erd.profileWorker"
  }

  image_updater_annotations = var.source_type != "helm" ? {} : merge(
    {
      "argocd-image-updater.argoproj.io/image-list"        = join(",", [for alias, path in local.image_updater_images : "${alias}=public.ecr.aws/s7m9t1b0/ekai/ekai-${alias}"])
      "argocd-image-updater.argoproj.io/write-back-method" = "argocd"
    },
    merge([
      for alias, path in local.image_updater_images : {
        "argocd-image-updater.argoproj.io/${alias}.update-strategy" = "digest"
        "argocd-image-updater.argoproj.io/${alias}.helm.image-name" = "${path}.image.repository"
        "argocd-image-updater.argoproj.io/${alias}.helm.image-tag"  = "${path}.image.tag"
      }
    ]...)
  )
}

resource "argocd_repository_credentials" "manifests_repo_creds" {
  count    = var.source_type == "git" ? 1 : 0
  url      = local.repo_url
  username = var.github_username
  password = var.github_token
}

# ArgoCD requires Helm chart repos to be registered with type = "helm" before
# an Application can reference them via source.chart — unlike git repos,
# which ArgoCD can clone ad hoc. Without this, the repo-server tries to
# git-clone the plain HTTP Helm repo URL and the Application never syncs
# ("repository not found"/ComparisonError).
resource "argocd_repository" "helm_chart_repo" {
  count      = var.source_type == "helm" ? 1 : 0
  repo       = var.helm_repo_url
  type       = "helm"
  name       = var.helm_chart_name
  enable_oci = true

  lifecycle {
    precondition {
      condition     = var.helm_repo_url != ""
      error_message = "helm_repo_url must be set when source_type = \"helm\" (04-cicd's helm_chart_repo_url, cicd_provider = \"none\" only)."
    }
  }
}

resource "argocd_application" "ekai-saas" {
  metadata {
    name        = "ekai-saas-${var.env}"
    namespace   = "argocd"
    annotations = local.image_updater_annotations
  }

  spec {
    project = "default"

    source {
      repo_url        = local.repo_url
      path            = var.source_type == "git" ? var.manifest_folder : null
      chart           = var.source_type == "helm" ? var.helm_chart_name : null
      target_revision = var.source_type == "git" ? var.CD_branch : var.helm_chart_version

      dynamic "helm" {
        for_each = var.source_type == "helm" ? [1] : []
        content {
          values = var.helm_values
        }
      }
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = var.ekai_namespace
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
      sync_options = ["CreateNamespace=true"]
      retry {
        limit = "5"
        backoff {
          duration     = "30s"
          max_duration = "2m"
          factor       = "2"
        }
      }
    }
  }

  depends_on = [
    argocd_repository_credentials.manifests_repo_creds,
    argocd_repository.helm_chart_repo,
    time_sleep.wait_for_argocd_prune,
  ]
}

# The var.ekai_namespace Kubernetes namespace itself is created by the caller
# (04-cicd/main.tf, via 03-platform's kubernetes_namespace.ekai_saas) — not
# this module.
#
# On destroy: ArgoCD prunes all K8s resources including Ingresses. The GCP
# load balancer behind nginx-ingress is then cleaned up — typically 2-4 min.
# This sleep sits between argocd_application (destroyed first) and the
# caller's namespace (destroyed after), giving that cleanup time to finish
# before 03-platform/02-cluster destroy starts.
# On create: 0s, no impact.
resource "time_sleep" "wait_for_argocd_prune" {
  create_duration  = "0s"
  destroy_duration = "5m"
}
