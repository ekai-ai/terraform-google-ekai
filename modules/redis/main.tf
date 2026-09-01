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

# ── Helm release — Bitnami Redis chart ────────────────────────────────────────
# No image override: Bitnami's own redis image (chart 24.1.0+) already
# bundles RediSearch/RedisJSON/vectorset modules natively -- needed for
# AI/RAG workloads (vector similarity, JSON docs, embeddings) -- and its
# entrypoint auto-loads whatever .so files it finds under its own modules
# directory. An earlier version of this swapped the image for
# `redis/redis-stack-server` instead, which technically has the same modules
# but Bitnami's entrypoint doesn't know how to load modules from a foreign
# image's filesystem layout -- MODULE LIST came back empty despite running
# that image, breaking every FT.SEARCH-dependent app feature. Confirmed
# against a real working environment (GCP Knowledge's live redis-stack
# release: plain bitnami/redis image, chart 24.1.0, MODULE LIST shows
# search/ReJSON/vectorset all loaded) before making this change.
resource "helm_release" "redis" {
  name = "redis"
  # Bitnami retired the classic index-based repo (charts.bitnami.com now
  # redirects to a broadcom.com index whose entries point at this OCI
  # registry) -- installing via the old "repository + chart" combo makes
  # Helm try to reinterpret an oci:// URL as a plain tarball URL, failing
  # with "invalid_reference: invalid tag". Pulling directly via OCI avoids
  # that translation entirely.
  namespace  = kubernetes_namespace.redis.metadata[0].name
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "redis"
  version    = var.chart_version

  values = [yamlencode({
    architecture = "replication"

    # Chart 24.1.0's own default image.tag pins a specific Bitnami build
    # (e.g. 7.4.2-debian-12-r0) that 404s -- same ongoing free-tier tag
    # pruning pattern hit earlier with redis-exporter. GCP Knowledge's real
    # working redis-stack release runs bitnami/redis:latest, not a pinned
    # version; matching that exactly here rather than a versioned tag that
    # may already be gone by the time this next applies.
    image = {
      tag = "latest"
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
