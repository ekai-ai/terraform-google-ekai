output "minio_endpoint" {
  value = "http://minio.${var.minio_namespace}.svc.cluster.local:9000"
}

output "minio_host" {
  value = var.minio_host
}

output "minio_console_host" {
  value = local.console_host
}

output "minio_root_user" {
  value     = random_password.root_user.result
  sensitive = true
}

output "minio_root_password" {
  value     = random_password.root_password.result
  sensitive = true
}

output "default_buckets" {
  value = var.default_buckets
}
