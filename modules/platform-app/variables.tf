variable "name" {
  description = "Name applied to all resources created by this module (Deployment, Service, etc.). Must be a valid Kubernetes resource name (RFC 1123)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into."
  type        = string
  default     = "default"
}

variable "create_namespace" {
  description = "Whether this module should create the namespace. Set to false if the namespace already exists or is managed by a separate namespace-provisioning module."
  type        = bool
  default     = false
}

variable "image_repository" {
  description = "Container image repository, e.g. ghcr.io/org/app or 123456789.dkr.ecr.us-east-1.amazonaws.com/app."
  type        = string
}

variable "image_tag" {
  description = "Container image tag. Avoid 'latest' outside local development; pin to an immutable tag (or digest) so deployments are reproducible."
  type        = string
}

variable "replicas" {
  description = "Number of pod replicas. Only used as the initial/static count; if hpa_enabled is true, the HPA takes over scaling after the first apply."
  type        = number
  default     = 2
}

variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
  default     = 8000
}

variable "service_port" {
  description = "Port exposed by the Kubernetes Service."
  type        = number
  default     = 80
}

variable "service_type" {
  description = "Kubernetes Service type: ClusterIP, NodePort, or LoadBalancer."
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "service_type must be one of: ClusterIP, NodePort, LoadBalancer."
  }
}

variable "labels" {
  description = "Additional labels merged into the module's default label set on every resource."
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Additional annotations applied to the Deployment (pod template) and Service."
  type        = map(string)
  default     = {}
}

variable "env" {
  description = "Plain (non-secret) environment variables for the container, as name => value. For secrets, use env_from_secret instead of putting values here or in state."
  type        = map(string)
  default     = {}
}

variable "env_from_secret" {
  description = "Name of an existing Kubernetes Secret to load as environment variables via envFrom. This module does not create or manage the Secret's contents - see README for the recommended secret-handling approach."
  type        = string
  default     = ""
}

variable "resources" {
  description = "Container resource requests and limits. Sensible small-service defaults are provided; override per environment."
  type = object({
    requests = optional(object({
      cpu    = optional(string, "50m")
      memory = optional(string, "64Mi")
    }), {})
    limits = optional(object({
      cpu    = optional(string, "200m")
      memory = optional(string, "128Mi")
    }), {})
  })
  default = {}
}

variable "liveness_path" {
  description = "HTTP path used for the liveness probe."
  type        = string
  default     = "/health"
}

variable "readiness_path" {
  description = "HTTP path used for the readiness probe."
  type        = string
  default     = "/ready"
}

variable "service_account_name" {
  description = "Name of an existing ServiceAccount to use. Leave empty to use the namespace's default ServiceAccount."
  type        = string
  default     = ""
}

variable "run_as_user" {
  description = "Numeric UID to run the container as. Leave null to rely on the image's own USER directive. Kubernetes' runAsNonRoot check can only verify a numeric UID at admission time - if your image's USER is a name rather than a UID, container creation fails with CreateContainerConfigError unless this is set explicitly."
  type        = number
  default     = null
}

variable "read_only_root_filesystem" {
  description = "Whether to mount the container's root filesystem as read-only. True by default (security hardening). Set to false if the app writes to disk at runtime, or pair with an emptyDir volume for the specific writable path needed."
  type        = bool
  default     = true
}

# ---- Ingress (optional) ----

variable "ingress_enabled" {
  description = "Whether to create an Ingress resource for this app."
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Hostname for the Ingress. Required if ingress_enabled is true."
  type        = string
  default     = ""
}

variable "ingress_class_name" {
  description = "IngressClass to use (e.g. nginx, alb)."
  type        = string
  default     = "nginx"
}

variable "ingress_annotations" {
  description = "Extra annotations for the Ingress only (e.g. cert-manager issuer, ALB target-type). Merged with the module's default labels/annotations."
  type        = map(string)
  default     = {}
}

variable "ingress_tls_enabled" {
  description = "Whether to configure TLS on the Ingress. This module does not create certificates or the TLS secret - point ingress_tls_secret_name at a secret managed by cert-manager or provisioned out of band."
  type        = bool
  default     = false
}

variable "ingress_tls_secret_name" {
  description = "Name of the existing Kubernetes TLS secret used for Ingress TLS. Required if ingress_tls_enabled is true."
  type        = string
  default     = ""
}

# ---- Optional add-ons (off by default to keep the base deployment simple) ----

variable "pdb_enabled" {
  description = "Whether to create a PodDisruptionBudget."
  type        = bool
  default     = false
}

variable "pdb_min_available" {
  description = "Minimum number of available pods enforced by the PodDisruptionBudget."
  type        = number
  default     = 1
}

variable "hpa_enabled" {
  description = "Whether to create a HorizontalPodAutoscaler. Requires metrics-server to be installed in the cluster."
  type        = bool
  default     = false
}

variable "hpa_min_replicas" {
  description = "Minimum replicas when hpa_enabled is true."
  type        = number
  default     = 2
}

variable "hpa_max_replicas" {
  description = "Maximum replicas when hpa_enabled is true."
  type        = number
  default     = 5
}

variable "hpa_target_cpu_utilization" {
  description = "Target average CPU utilization percentage for the HPA."
  type        = number
  default     = 70
}

variable "network_policy_enabled" {
  description = "Whether to create a NetworkPolicy restricting ingress to the app's container_port from pods within the same namespace. This is a permissive starting point, not a zero-trust policy - tighten the pod/namespace selector per environment."
  type        = bool
  default     = false
}
