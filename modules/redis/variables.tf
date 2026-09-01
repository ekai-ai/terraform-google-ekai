variable "redis_namespace" {
  description = "Kubernetes namespace where Redis is installed."
  type        = string
  default     = "redis"
}

variable "chart_version" {
  # 24.1.0 matches GCP Knowledge's actual live redis-stack release (verified
  # via `helm get values`/`MODULE LIST` against a real working environment)
  # -- this version's Bitnami redis image bundles RediSearch/RedisJSON/
  # vectorset natively (/opt/bitnami/redis/lib/redis/modules/*.so, auto-loaded
  # by Bitnami's own entrypoint). See modules/redis/main.tf for why this
  # replaced the redis/redis-stack-server image-swap approach entirely.
  description = "Bitnami Redis Helm chart version. Pin in prod to avoid surprises."
  type        = string
  default     = "24.1.0"
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
