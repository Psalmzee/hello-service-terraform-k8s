output "service_name" {
  value = module.hello_service.service_name
}

output "namespace" {
  value = module.hello_service.namespace
}

output "cluster_internal_endpoint" {
  value = module.hello_service.cluster_internal_endpoint
}

output "ingress_endpoint" {
  value = module.hello_service.ingress_endpoint
}
