variable "argocd_namespace" {
  description = "Kubernetes namespace to deploy ArgoCD into (e.g. argocd)."
  type        = string
  default     = "argocd"
}

variable "argocd_admin_password_hashed" {
  description = "Bcrypt-hashed ArgoCD admin password (use: htpasswd -nbBC 10 '' PASSWORD | tr -d ':' | sed 's/$2y/$2a/')."
  type        = string
  sensitive   = true
}

variable "argocd_ingress_host" {
  description = "Hostname for the ArgoCD Ingress (e.g. argocd.client1.example.com)."
  type        = string
}

variable "tls_secret_name" {
  description = "Name of the Kubernetes TLS secret containing the wildcard certificate."
  type        = string
  default     = "wildcard-tls"
}
