output "neo4j_password" {
  value     = local.password
  sensitive = true
}

output "bolt_uri" {
  value = "bolt://neo4j.${var.namespace}.svc.cluster.local:7687"
}

output "neo4j_uri" {
  value = "neo4j://neo4j.${var.namespace}.svc.cluster.local:7687"
}
