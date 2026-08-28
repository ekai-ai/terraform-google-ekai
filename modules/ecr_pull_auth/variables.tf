variable "namespace" {
  description = "Kubernetes namespace where all resources (secret, service account, role, cron job) are created."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID that owns the ECR registry (e.g. 123456789012). Used to construct the ECR registry URL."
  type        = string
}

variable "aws_region" {
  description = "AWS region where the ECR registry lives (e.g. us-east-1). Used to construct the ECR registry URL and the aws ecr get-login-password --region flag."
  type        = string
}

variable "ecr_credentials_secret_name" {
  description = "Name of the GCP Secret Manager secret that holds the AWS IAM credentials JSON. The secret value must be a JSON object with keys AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
  type        = string
}

variable "secret_name" {
  description = "Name of the kubernetes docker-registry secret that the cron job creates/refreshes in var.namespace. Referenced as imagePullSecrets in pod specs."
  type        = string
  default     = "aws-ecr-pull-secret"
}

variable "refresh_schedule" {
  description = "Cron expression controlling how often the ECR token is refreshed. ECR tokens expire after 12 h; default refreshes every 6 h."
  type        = string
  default     = "0 */6 * * *"
}

variable "project_id" {
  description = "GCP project ID — used to scope the Secret Manager secret read."
  type        = string
}
