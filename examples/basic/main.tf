terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2.1, < 4.0.0"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

module "hello_service" {
  source = "../../modules/platform-app"

  name             = "hello-service"
  namespace        = "hello-demo"
  create_namespace = true

  image_repository = var.image_repository
  image_tag        = var.image_tag
  replicas         = 2

  container_port = 8000
  service_port   = 80
  run_as_user    = 1000

  env = {
    APP_NAME    = "hello-service"
    APP_VERSION = var.image_tag
  }

  labels = {
    "team" = "platform"
  }

  # Optional add-ons are off by default; flip these on to see them in action.
  # pdb_enabled             = true
  # hpa_enabled              = true
  # network_policy_enabled  = true
  # ingress_enabled          = true
  # ingress_host             = "hello.example.com"
}
