variable "project_id" {
  description = "GCP project ID that owns all resources."
  type        = string
}

variable "region" {
  description = "GCP region (e.g. us-central1)."
  type        = string
}

variable "env" {
  description = "Environment name (e.g. dev, staging, prod)."
  type        = string
}

variable "pipelines" {
  description = <<-EOT
    Map of CI/CD pipeline definitions.
    To add a new pipeline, add one entry here and set its value in your .tfvars.
    No other file needs to change.
  EOT
  type = map(object({
    branch          = string                             # source branch to trigger on (e.g. "main")
    github_repo     = string                             # repository name only (e.g. "my-app"), NOT "org/repo"
    dockerfile      = optional(string, "Dockerfile")     # path to Dockerfile relative to repo root
    build_context   = optional(string, ".")               # Docker build context (default: repo root)
    manifest_folder = optional(string, "manifest-files") # folder inside deployment-files repo
    manifest_file   = string                             # filename of the K8s manifest to patch (e.g. "deployment.yaml")
  }))
}

variable "secrets_name" {
  description = "Secret Manager secret name that holds a JSON blob with github_token, github_username, and github_email keys."
  type        = string
}

variable "github_owner" {
  description = "GitHub organisation or user name (owner of all repos)."
  type        = string
}

variable "cd_branch" {
  description = "Git branch in deployment-files used for CD manifest updates (e.g. main)."
  type        = string
}

variable "manifest_folder" {
  description = "Default folder inside deployment-files where manifests live. Can be overridden per pipeline via pipelines[*].manifest_folder."
  type        = string
  default     = "manifest-files"
}

variable "registry_url" {
  description = "Artifact Registry base URL for image tags (e.g. us-central1-docker.pkg.dev/my-project/my-repo)."
  type        = string
}
