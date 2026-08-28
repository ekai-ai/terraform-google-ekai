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

variable "github_org" {
  description = "GitHub organisation name (e.g. ekai-ai). Used to scope the OIDC trust condition and repo URLs."
  type        = string
}

variable "github_username" {
  description = "Git author name for manifest commits."
  type        = string
}

variable "github_email" {
  description = "Git author email for manifest commits."
  type        = string
}

variable "github_token" {
  description = "GitHub PAT for cloning and pushing the deployment-files repo. Written as ORG_TOKEN_GITHUB secret to each app repo."
  type        = string
  sensitive   = true
}

variable "cd_branch" {
  description = "Branch in deployment-files repo used for CD manifest updates (e.g. main)."
  type        = string
}

variable "registry_url" {
  description = "Artifact Registry base URL for image tags (e.g. us-central1-docker.pkg.dev/my-project). Provided by the artifact_registry module's registry_url output."
  type        = string
}

variable "create_wif_pool" {
  description = "Create the Workload Identity Federation pool. Set false if another stack already created it in this project."
  type        = bool
  default     = true
}

variable "pipelines" {
  description = <<-EOT
    Map of CI/CD pipeline definitions. Add entries in your .tfvars — no source changes needed.
    Each key is the logical service name; it becomes the Artifact Registry repository suffix (<env>-<service>).
  EOT
  type = map(object({
    branch          = string                             # source branch to trigger on (e.g. "main")
    github_repo     = string                             # "org/repo" format (e.g. "ekai-ai/my-app")
    build_cmd       = string                             # docker build command; $IMAGE is available
    manifest_folder = optional(string, "manifest-files") # folder inside deployment-files repo
    manifest_file   = string                             # filename of the K8s manifest to patch
    ingresshost     = optional(string, "")               # public hostname for DNS record (informational)
    pre_build_cmds  = optional(list(string), [])         # shell lines to run before build_cmd
  }))
}
