output "service_name" {
  description = "Name of the Kubernetes Service created for this app."
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "namespace" {
  description = "Namespace the app was deployed into."
  value       = var.namespace
}

output "deployment_name" {
  description = "Name of the Kubernetes Deployment created for this app."
  value       = kubernetes_deployment_v1.this.metadata[0].name
}

output "cluster_internal_endpoint" {
  description = "In-cluster DNS endpoint for the Service (reachable from other pods)."
  value       = "http://${kubernetes_service_v1.this.metadata[0].name}.${var.namespace}.svc.cluster.local:${var.service_port}"
}

output "ingress_endpoint" {
  description = "External endpoint via Ingress, if ingress_enabled is true; otherwise null."
  value       = var.ingress_enabled ? "${var.ingress_tls_enabled ? "https" : "http"}://${var.ingress_host}" : null
}
