locals {
  selector_labels = {
    "app.kubernetes.io/name"     = var.name
    "app.kubernetes.io/instance" = var.name
  }

  common_labels = merge(
    local.selector_labels,
    { "app.kubernetes.io/managed-by" = "terraform" },
    var.labels
  )
}

resource "kubernetes_namespace_v1" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.common_labels
  }
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = var.annotations
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.selector_labels
    }

    template {
      metadata {
        labels      = local.common_labels
        annotations = var.annotations
      }

      spec {
        service_account_name = var.service_account_name != "" ? var.service_account_name : null

        security_context {
          run_as_non_root = true
          run_as_user     = var.run_as_user
        }

        container {
          name  = var.name
          image = "${var.image_repository}:${var.image_tag}"

          port {
            name           = "http"
            container_port = var.container_port
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env_from" {
            for_each = var.env_from_secret != "" ? [var.env_from_secret] : []
            content {
              secret_ref {
                name = env_from.value
              }
            }
          }

          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }

          liveness_probe {
            http_get {
              path = var.liveness_path
              port = var.container_port
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 2
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = var.readiness_path
              port = var.container_port
            }
            initial_delay_seconds = 3
            period_seconds        = 5
            timeout_seconds       = 2
            failure_threshold     = 3
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = var.run_as_user
            read_only_root_filesystem  = var.read_only_root_filesystem
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = var.annotations
  }

  spec {
    type     = var.service_type
    selector = local.selector_labels

    port {
      name        = "http"
      port        = var.service_port
      target_port = var.container_port
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

resource "kubernetes_ingress_v1" "this" {
  count = var.ingress_enabled ? 1 : 0

  metadata {
    name        = var.name
    namespace   = var.namespace
    labels      = local.common_labels
    annotations = merge(var.annotations, var.ingress_annotations)
  }

  spec {
    ingress_class_name = var.ingress_class_name

    rule {
      host = var.ingress_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.this.metadata[0].name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }

    dynamic "tls" {
      for_each = var.ingress_tls_enabled ? [1] : []
      content {
        hosts       = [var.ingress_host]
        secret_name = var.ingress_tls_secret_name
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "this" {
  count = var.pdb_enabled ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    min_available = var.pdb_min_available

    selector {
      match_labels = local.selector_labels
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  count = var.hpa_enabled ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.common_labels
  }

  spec {
    min_replicas = var.hpa_min_replicas
    max_replicas = var.hpa_max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.this.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_target_cpu_utilization
        }
      }
    }
  }
}

# Permissive-by-default: allows ingress to the app's port from any pod in the
# same namespace. This demonstrates the pattern; production use should scope
# the `from` block to specific namespaces/pods (e.g. an ingress controller
# namespace) rather than the whole namespace.
resource "kubernetes_network_policy_v1" "this" {
  count = var.network_policy_enabled ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = local.selector_labels
    }

    ingress {
      from {
        namespace_selector {}
      }

      ports {
        port     = var.container_port
        protocol = "TCP"
      }
    }

    policy_types = ["Ingress"]
  }
}
