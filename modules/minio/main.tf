resource "random_password" "root_user" {
  length  = 16
  upper   = true
  lower   = true
  numeric = true
  special = false
  keepers = { namespace = var.minio_namespace }
}

resource "random_password" "root_password" {
  length  = 32
  upper   = true
  lower   = true
  numeric = true
  special = false
  keepers = { namespace = var.minio_namespace }
}

resource "kubernetes_namespace" "minio" {
  metadata {
    name = var.minio_namespace
  }
}

resource "helm_release" "minio" {
  name       = "minio"
  namespace  = kubernetes_namespace.minio.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "minio"
  version    = var.chart_version

  values = [yamlencode({
    global = {
      security = { allowInsecureImages = true }
    }

    image = {
      registry   = "docker.io"
      repository = "bitnamilegacy/minio"
      tag        = var.image_tag
    }

    clientImage = {
      registry   = "docker.io"
      repository = "bitnamilegacy/minio-client"
      tag        = var.client_image_tag
    }

    auth = {
      rootUser     = random_password.root_user.result
      rootPassword = random_password.root_password.result
    }

    mode        = var.mode
    statefulset = { replicaCount = var.replicas }

    persistence = {
      enabled      = true
      size         = var.persistence_size
      storageClass = var.storage_class
    }

    defaultBuckets = join(",", var.default_buckets)

    ingress = {
      enabled          = true
      ingressClassName = "nginx"
      hostname         = var.minio_host
      servicePort      = "minio-api"
      tls              = true
      extraTls = [{
        hosts      = [var.minio_host]
        secretName = var.tls_secret_name
      }]
      annotations = {
        # No cert-manager annotation — wildcard cert is managed centrally by
        # cert-manager and reflected into this namespace by Reflector.
        "nginx.ingress.kubernetes.io/proxy-body-size"    = "0"
        "nginx.ingress.kubernetes.io/proxy-read-timeout" = "600"
        "nginx.ingress.kubernetes.io/proxy-send-timeout" = "600"
      }
    }

    consoleIngress = {
      enabled          = true
      ingressClassName = "nginx"
      hostname         = local.console_host
      tls              = true
      extraTls = [{
        hosts      = [local.console_host]
        secretName = var.tls_secret_name
      }]
      annotations = {
        # No cert-manager annotation — wildcard cert reflected by Reflector.
      }
    }

    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { cpu = "500m", memory = "1Gi" }
    }
  })]
}

locals {
  console_host = var.minio_console_host != "" ? var.minio_console_host : "console.${var.minio_host}"
}
