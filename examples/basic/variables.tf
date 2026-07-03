variable "kubeconfig_path" {
  description = "Path to kubeconfig file used by the Kubernetes provider."
  type        = string
  default     = "~/.kube/config"
}

variable "image_repository" {
  description = "Image repository for the hello-service app (e.g. a local registry, ghcr.io/you/hello-service, or an ECR repo URL)."
  type        = string
  default     = "hello-service"
}

variable "image_tag" {
  description = "Image tag to deploy."
  type        = string
  default     = "0.1.0"
}
