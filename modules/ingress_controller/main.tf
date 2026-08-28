# Deploy NGINX Ingress Controller on GKE using Helm
#
# Lifecycle:
#   1. kubernetes_namespace.ingress          — creates the target namespace
#   2. helm_release.nginx_ingress            — installs the chart into that namespace
#   3. time_sleep.wait_for_lb               — allows GKE 30 s to provision the
#                                             external IP on the LoadBalancer Service
#   4. data.kubernetes_service.nginx_lb     — reads the assigned IP for use by callers

resource "kubernetes_namespace" "ingress" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  namespace  = kubernetes_namespace.ingress.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.chart_version
  timeout    = 600

  # Two replicas for availability across GKE node pools
  set {
    name  = "controller.replicaCount"
    value = "2"
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  # Only set loadBalancerIP when a static IP was provided; an empty string
  # would cause GKE to reject the Service spec.
  dynamic "set" {
    for_each = var.static_ip != null ? [var.static_ip] : []
    content {
      name  = "controller.service.loadBalancerIP"
      value = set.value
    }
  }
}

# GKE's external load-balancer provisioner runs asynchronously after the
# Service object is created by Helm. Wait 30 s before reading the Service
# so the ingress[0].ip field is populated.
resource "time_sleep" "wait_for_lb" {
  create_duration = "30s"

  depends_on = [helm_release.nginx_ingress]
}

data "kubernetes_service" "nginx_lb" {
  metadata {
    # The ingress-nginx chart names the controller Service <release>-ingress-nginx-controller
    name      = "nginx-ingress-ingress-nginx-controller"
    namespace = kubernetes_namespace.ingress.metadata[0].name
  }

  depends_on = [time_sleep.wait_for_lb]
}
