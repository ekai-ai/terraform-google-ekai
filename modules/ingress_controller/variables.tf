variable "namespace" {
  description = "Kubernetes namespace in which the ingress-nginx controller is deployed."
  type        = string
  default     = "ingress-nginx"
}

variable "chart_version" {
  description = "Version of the ingress-nginx Helm chart."
  type        = string
  default     = "4.11.0"
}

variable "static_ip" {
  description = "Pre-allocated GCP static external IP address to assign to the LoadBalancer service. Leave null to let GCP assign one automatically."
  type        = string
  default     = null
}
