# 1. Namespace for ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"

  values = [yamlencode({
    configs = {
      params = {
        "server.insecure" = "true"
      }
      secret = {
        argocdServerAdminPassword = var.argocd_admin_password_hashed
      }
    }
    server = {
      ingress = {
        enabled           = true
        ingressClassName  = "nginx"
        hostname          = var.argocd_ingress_host
        hosts             = [var.argocd_ingress_host]
        annotations = {
          "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
          "nginx.ingress.kubernetes.io/rewrite-target"     = "/"
        }
        # tls: false — do NOT let the chart add argocd-server-tls entry.
        # That non-existent secret causes nginx to serve the fake cert.
        # We use extraTls only, pointing to our wildcard secret.
        tls = false
        extraTls = [{
          hosts      = [var.argocd_ingress_host]
          secretName = var.tls_secret_name
        }]
      }
    }
  })]

  depends_on = [kubernetes_namespace.argocd]
}

# AppProject/default is auto-created by ArgoCD with a finalizer.
# Managing it here (force_conflicts = true) ensures Terraform destroys it
# before Helm uninstall, so the finalizer is gone before controllers are killed
# and the argocd namespace terminates cleanly.
resource "kubectl_manifest" "argocd_default_project" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name       = "default"
      namespace  = var.argocd_namespace
      finalizers = []
    }
    spec = {
      sourceRepos              = ["*"]
      destinations             = [{ namespace = "*", server = "https://kubernetes.default.svc" }]
      clusterResourceWhitelist = [{ group = "*", kind = "*" }]
    }
  })
  force_conflicts = true
  depends_on      = [helm_release.argocd]
}

# DNS / Route53 records are NOT created here. The wildcard A record in
# Layer 04 (modules/microservices_CD) reads the nginx-ingress LB Service IP
# directly and covers `argocd.<env>.<domain>` automatically.
# Per-Ingress LB-IP lookups would race against Ingress status propagation
# and fail with "empty list of object" during apply.
