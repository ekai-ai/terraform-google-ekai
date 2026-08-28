output "redis_host" {
  description = "In-cluster DNS name for the Redis master service."
  value       = local.redis_host
}

output "redis_port" {
  description = "Redis port (6379)."
  value       = local.redis_port
}

output "redis_username" {
  description = "Redis ACL user (always 'default' for Bitnami chart with sentinel disabled)."
  value       = "default"
}

output "redis_password" {
  description = "Redis password for the default user."
  value       = random_password.redis.result
  sensitive   = true
}

output "redis_url" {
  description = "Full Redis connection URL (redis://default:<password>@<host>:<port>)."
  value       = local.redis_url
  sensitive   = true
}
