variable "redis_namespace" {
  description = "Kubernetes namespace where Redis is installed."
  type        = string
  default     = "redis"
}

variable "chart_version" {
  description = "Bitnami Redis Helm chart version. Pin in prod to avoid surprises."
  type        = string
  default     = "20.6.2"
}

# ── Redis Stack image override ────────────────────────────────────────────────
# Bitnami chart scaffolding + redis/redis-stack-server image for AI/RAG modules
# (RediSearch, RedisJSON, RedisTimeSeries, RedisBloom).

variable "image_registry" {
  description = "Container registry for the Redis Stack server image."
  type        = string
  default     = "docker.io"
}

variable "image_repository" {
  description = "Image repository."
  type        = string
  default     = "redis/redis-stack-server"
}

variable "image_tag" {
  description = "Redis Stack server image tag. Pin to a specific version in prod."
  type        = string
  default     = "7.4.0-v3"
}

variable "replica_count" {
  description = "Number of read-replica pods (excluding master). 0 for dev, 3 for prod."
  type        = number
  default     = 1
}

variable "persistence_size" {
  description = "PVC size for each Redis pod (master and each replica)."
  type        = string
  default     = "8Gi"
}

variable "storage_class" {
  description = "StorageClass for Redis PVCs. Empty string uses the GKE cluster default (standard-rwo). Use premium-rwo for SSD-backed volumes in prod."
  type        = string
  default     = ""
}

variable "resources_master" {
  description = "Kubernetes resource requests/limits for the master pod."
  type        = any
  default = {
    requests = { cpu = "200m", memory = "512Mi" }
    limits   = { cpu = "1", memory = "1Gi" }
  }
}

variable "resources_replica" {
  description = "Kubernetes resource requests/limits for each replica pod."
  type        = any
  default = {
    requests = { cpu = "200m", memory = "512Mi" }
    limits   = { cpu = "1", memory = "1Gi" }
  }
}

variable "metrics_enabled" {
  description = "Deploy the redis-exporter sidecar for Prometheus scraping."
  type        = bool
  default     = true
}

variable "network_policy_enabled" {
  description = "Apply a NetworkPolicy restricting traffic to pods within the cluster."
  type        = bool
  default     = true
}
