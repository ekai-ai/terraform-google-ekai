# ── Auth ──────────────────────────────────────────────────────────────────────
resource "random_password" "redis" {
  length  = 32
  upper   = true
  lower   = true
  numeric = true
  special = false # avoid url-encoding ambiguities in REDIS_URL

  keepers = {
    namespace = var.redis_namespace
  }
}

# ── Namespace ─────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "redis" {
  metadata {
    name = var.redis_namespace
  }
}

# ── Helm release — Bitnami Redis chart with Redis Stack image ─────────────────
# Uses Bitnami's HA scaffolding (master + replicas, persistence, NetworkPolicy,
# metrics exporter) but swaps the image for `redis/redis-stack-server` which
# ships RediSearch + RedisJSON + RedisTimeSeries + RedisBloom pre-loaded —
# needed for AI/RAG workloads (vector similarity, JSON docs, embeddings).
resource "helm_release" "redis" {
  name       = "redis"
  namespace  = kubernetes_namespace.redis.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  version    = var.chart_version

  values = [yamlencode({
    # Bitnami chart v21+ refuses non-Bitnami images by default — opt out so we
    # can use the official `redis/redis-stack-server` image.
    # NOT a security override: disables only the chart-internal image whitelist.
    global = {
      security = {
        allowInsecureImages = true
      }
    }

    architecture = "replication"

    image = {
      registry   = var.image_registry
      repository = var.image_repository
      tag        = var.image_tag
      pullPolicy = "IfNotPresent"
    }

    # Bitnami's own image bundles these module .so files (confirmed present
    # under /opt/bitnami/redis/lib/redis/modules/ on the running container)
    # but its current entrypoint/config generation doesn't emit `loadmodule`
    # directives for any of them -- MODULE LIST came back with only
    # "vectorset" (natively built into redis-server itself, not one of
    # these loadable modules) until this was added explicitly.
    commonConfiguration = <<-EOT
      appendonly yes
      loadmodule /opt/bitnami/redis/lib/redis/modules/redisearch.so
      loadmodule /opt/bitnami/redis/lib/redis/modules/rejson.so
      loadmodule /opt/bitnami/redis/lib/redis/modules/redisbloom.so
      loadmodule /opt/bitnami/redis/lib/redis/modules/redistimeseries.so
    EOT

    auth = {
      enabled  = true
      password = random_password.redis.result
      sentinel = false
    }

    master = {
      persistence = {
        enabled      = true
        size         = var.persistence_size
        storageClass = var.storage_class
      }
      resources = var.resources_master
      podSecurityContext = {
        enabled = true
        fsGroup = 1000
      }
      containerSecurityContext = {
        enabled      = true
        runAsUser    = 1000
        runAsNonRoot = true
      }
    }

    replica = {
      replicaCount = var.replica_count
      persistence = {
        enabled      = true
        size         = var.persistence_size
        storageClass = var.storage_class
      }
      resources = var.resources_replica
      podSecurityContext = {
        enabled = true
        fsGroup = 1000
      }
      containerSecurityContext = {
        enabled      = true
        runAsUser    = 1000
        runAsNonRoot = true
      }
    }

    metrics = {
      enabled = var.metrics_enabled
    }

    networkPolicy = {
      enabled = var.network_policy_enabled
    }
  })]

  depends_on = [kubernetes_namespace.redis]
}

# Redis is cluster-internal — pods reach it via in-cluster DNS.
# Connection details flow to platform outputs and are merged into per-service
# Secret Manager secrets by the cicd layer.
locals {
  redis_host = "redis-master.${var.redis_namespace}.svc.cluster.local"
  redis_port = 6379
  redis_url  = "redis://default:${random_password.redis.result}@${local.redis_host}:${local.redis_port}"
}
