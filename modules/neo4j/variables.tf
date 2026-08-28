variable "namespace" {
  type    = string
  default = "neo4j"
}

variable "chart_version" {
  type    = string
  default = "5.26.0"
}

variable "neo4j_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "storage_size" {
  type    = string
  default = "20Gi"
}

variable "storage_class" {
  type    = string
  default = "standard-rwo"
}

variable "memory_request" {
  type    = string
  default = "2Gi"
}

variable "memory_limit" {
  type    = string
  default = "4Gi"
}

variable "cpu_request" {
  type    = string
  default = "500m"
}

variable "cpu_limit" {
  type    = string
  default = "2"
}
