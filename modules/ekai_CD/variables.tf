variable "ekai_namespace" {
  description = "Kubernetes namespace for ekai services (created by the caller — see main.tf's header comment)."
  type        = string
}

variable "source_type" {
  description = <<-EOT
    ArgoCD Application source:
      "git"  — default, Ekai-internal envs. Deploys from the deployment-files
               git repo (path = manifest_folder, target_revision = CD_branch).
      "helm" — self-service clients. No git/CI access needed at all — deploys a
               versioned Helm chart Ekai publishes (see helm_repo_url/
               helm_chart_name/helm_chart_version).
  EOT
  type        = string
  default     = "git"
  validation {
    condition     = contains(["git", "helm"], var.source_type)
    error_message = "source_type must be 'git' or 'helm'."
  }
}

variable "CD_branch" {
  description = "Git branch used for CD deployment manifests (source_type = \"git\" only)"
  type        = string
  default     = ""
}

variable "manifest_folder" {
  description = "Folder inside deployment-files repo where K8s manifests live (e.g. gcp-manifests) (source_type = \"git\" only)"
  type        = string
  default     = "manifest-files"
}

variable "github_org" {
  description = "GitHub organisation name (source_type = \"git\" only)"
  type        = string
  default     = ""
}

variable "github_username" {
  description = "GitHub username used for ArgoCD repository credentials (source_type = \"git\" only)"
  type        = string
  default     = ""
}

variable "github_token" {
  description = "GitHub Personal Access Token for ArgoCD repository access (source_type = \"git\" only)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "helm_repo_url" {
  description = "Helm chart repository URL (source_type = \"helm\" only). Expected to be a public repo — no client credentials needed."
  type        = string
  default     = ""
}

variable "helm_chart_name" {
  description = "Chart name to deploy from helm_repo_url (source_type = \"helm\" only)"
  type        = string
  default     = "ekai-saas"
}

variable "helm_chart_version" {
  description = "Chart version to deploy (source_type = \"helm\" only). Bump to upgrade."
  type        = string
  default     = ""
}

variable "helm_values" {
  description = "Raw YAML values passed to the chart (source_type = \"helm\" only)."
  type        = string
  default     = ""
}

variable "env" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}
