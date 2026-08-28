variable "project_id" {
  description = "GCP project ID that owns the cluster."
  type        = string
}

variable "region" {
  description = "GCP region for the regional cluster (e.g. us-central1)."
  type        = string
}

variable "env" {
  description = "Environment label applied to all resources (e.g. dev, staging, prod)."
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
}

variable "vpc_name" {
  description = "Name of the VPC network the cluster will be attached to."
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnetwork (within vpc_name) for cluster nodes."
  type        = string
}

variable "pods_range_name" {
  description = "Name of the secondary IP range on the subnet used for Pods."
  type        = string
}

variable "services_range_name" {
  description = "Name of the secondary IP range on the subnet used for Services."
  type        = string
}

variable "node_machine_type" {
  description = "Compute Engine machine type for cluster nodes (e.g. e2-standard-4)."
  type        = string
  default     = "e2-standard-4"
}

variable "min_nodes" {
  description = "Minimum number of nodes per zone in the node pool."
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum number of nodes per zone in the node pool."
  type        = number
  default     = 5
}

variable "k8s_version" {
  description = "Kubernetes version prefix (e.g. 1.35). Empty string = GKE picks latest stable."
  type        = string
  default     = ""
}

variable "node_service_account" {
  description = "Email of the GCP service account to attach to cluster nodes."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE control plane private endpoint. Required when enable_private_nodes = true. Must be /28 and must not overlap with VPC or subnet CIDRs."
  type        = string
  default     = "172.16.0.0/28"
}
