output "pull_secret_name" {
  description = "Name of the kubernetes docker-registry secret created by the refresh cron job. Add this to imagePullSecrets in pod specs that pull from ECR."
  value       = var.secret_name
}
