###############################################################################
# cert-manager Module
# Provider requirements are in versions.tf
# Variables are in variables.tf — outputs are in outputs.tf
###############################################################################
# Install flow:
#   kubernetes_namespace  →  helm_release (cert-manager + CRDs)
#   →  time_sleep (30s CRD propagation)
#   →  kubectl_manifest (ClusterIssuer staging + prod)
###############################################################################

# ── Namespace ─────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

# ── Helm release ──────────────────────────────────────────────────────────────
# installCRDs=true bootstraps all cert-manager CRDs inside the same Helm
# release so no separate CRD apply step is required.
# global.leaderElection.namespace pins leader-election ConfigMaps/Leases to the
# cert-manager namespace, preventing cross-namespace permission errors.
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version

  values = [yamlencode({
    installCRDs = true
    global = {
      leaderElection = {
        namespace = "cert-manager"
      }
    }
  })]

  depends_on = [kubernetes_namespace.cert_manager]
}

# ── CRD propagation delay ─────────────────────────────────────────────────────
# The ClusterIssuer CRD is registered by the Helm post-install hooks. Kubernetes
# API server discovery caches take ~10-30 s to reflect new CRDs, so kubectl_manifest
# calls below would get "no kind is registered" without this guard.
resource "time_sleep" "wait_for_crds" {
  create_duration = "30s"

  depends_on = [helm_release.cert_manager]
}

# ── ClusterIssuer — Let's Encrypt staging ────────────────────────────────────
# Use staging for testing to avoid hitting production rate limits.
# Staging certificates are signed by a fake CA and will trigger browser warnings.
resource "kubectl_manifest" "cluster_issuer_staging" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-staging-account-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [time_sleep.wait_for_crds]
}

# ── ClusterIssuer — Let's Encrypt production ─────────────────────────────────
# Switch Ingress annotations to this issuer only after staging validation passes.
# Production is rate-limited (5 duplicate certs/week per registered domain).
resource "kubectl_manifest" "cluster_issuer_prod" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [time_sleep.wait_for_crds]
}

# Variables are in variables.tf — outputs are in outputs.tf
