# Hello-Service

![CI](https://github.com/Psalmzee/hello-service-terraform-k8s/actions/workflows/ci.yml/badge.svg)

A minimal Python API (FastAPI) with a reusable Terraform module to deploy it to Kubernetes.

```
app/                    Application code, tests, dependencies
Dockerfile               Multi-stage, non-root container build
modules/platform-app/    Reusable Terraform module (not hardcoded to this app)
examples/basic/          Example usage of the module for this app
.github/workflows/ci.yml CI: tests, docker build, terraform fmt/validate, tflint
```

## Endpoints

| Method | Path      | Purpose                                    |
|--------|-----------|---------------------------------------------|
| GET    | `/`       | Hello message                              |
| GET    | `/health` | Liveness - process is up                   |
| GET    | `/ready`  | Readiness - pod should receive traffic     |

`/health` and `/ready` are intentionally separate. `/health` has no dependencies so a
slow downstream never causes Kubernetes to kill a healthy pod; `/ready` is the hook
point for dependency checks (DB, cache) in a real service - this demo has none, so
it always reports ready.

---

## Run locally

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r app/requirements-dev.txt
uvicorn app.main:app --reload --port 8000

curl localhost:8000/
curl localhost:8000/health
curl localhost:8000/ready
```

Or with `make run` (after installing deps).

## Run the tests

```bash
pip install -r app/requirements-dev.txt
pytest -v
```

## Build the Docker image

```bash
docker build -t hello-service:0.1.0 .
docker run --rm -p 8000:8000 hello-service:0.1.0
curl localhost:8000/health
```

The image is a two-stage build: dependencies are resolved in a `builder` stage,
then copied into a slim runtime stage that never sees pip or build tools. The
container runs as a non-root user (`appuser`), drops all Linux capabilities,
disallows privilege escalation, and mounts the root filesystem read-only.

If your cluster can't pull from your local Docker daemon (e.g. minikube, kind),
push the image somewhere reachable first, e.g.:

```bash
# kind
kind load docker-image hello-service:0.1.0

# minikube
minikube image load hello-service:0.1.0

# or push to a registry
docker tag hello-service:0.1.0 <your-registry>/hello-service:0.1.0
docker push <your-registry>/hello-service:0.1.0
```

## Deploy with Terraform

The example lives in `examples/basic` and calls the reusable module in
`modules/platform-app`. It requires a working `kubectl` context - Terraform
uses your existing kubeconfig, it doesn't provision a cluster.

```bash
cd examples/basic
cp terraform.tfvars.example terraform.tfvars   # adjust image_repository/image_tag
terraform init
terraform plan
terraform apply
```

This creates a `hello-demo` namespace, a Deployment (2 replicas), and a
ClusterIP Service. Ingress and the optional add-ons (PDB, HPA, NetworkPolicy)
are off by default - see the commented block in `examples/basic/main.tf`.

## Test the deployed app

```bash
kubectl -n hello-demo get pods
kubectl -n hello-demo port-forward svc/hello-service 8080:80

curl localhost:8080/
curl localhost:8080/health
curl localhost:8080/ready
```

Or check the Terraform outputs for the in-cluster DNS endpoint:

```bash
terraform output
```

## Destroy it

```bash
cd examples/basic
terraform destroy
```

Because `create_namespace = true` in the example, this also deletes the
`hello-demo` namespace and everything in it.

---

## Using the module for a different app

`modules/platform-app` isn't specific to this service - it takes an image,
not source code. Minimal usage:

```hcl
module "my_other_app" {
  source = "path/to/modules/platform-app"

  name              = "my-other-app"
  namespace         = "my-team"
  image_repository  = "ghcr.io/org/my-other-app"
  image_tag         = "1.4.2"
}
```

See `modules/platform-app/variables.tf` for the full configurable surface:
replicas, ports, service type, labels/annotations, env vars, resource
requests/limits, probe paths, Ingress (with optional TLS), and opt-in
PodDisruptionBudget / HorizontalPodAutoscaler / NetworkPolicy.

---

## Assumptions

- A Kubernetes cluster and valid kubeconfig already exist; this module deploys
  *into* a cluster, it doesn't create one (out of scope for "small and focused").
- The image is already built and pushed somewhere the cluster can pull from,
  or loaded into a local cluster (kind/minikube). Terraform doesn't build images.
- No ingress controller or cert-manager is assumed to be installed; Ingress and
  TLS are opt-in and documented, not defaulted on, since a bare cluster won't
  have either.
- `metrics-server` is required only if `hpa_enabled = true`. Most managed
  clusters (EKS, AKS, GKE) ship it or make it a one-line addon; kind/minikube
  usually need it installed manually.
- Secrets are referenced by name (`env_from_secret`), not created by this
  module - see below.

## Secret / config handling approach

Plain, non-sensitive config goes through `env` (a Terraform map rendered as
`env:` entries). Deliberately **not** used for secrets, since Terraform state
stores variable values in plaintext by default.

For secrets, the module accepts `env_from_secret`, the *name* of an existing
Kubernetes Secret, and wires it in via `envFrom`. The module never creates or
reads the Secret's contents. In practice that Secret would be populated by:

- **External Secrets Operator** or **Sealed Secrets**, syncing from
  AWS Secrets Manager / Vault / Azure Key Vault - preferred for anything
  beyond a demo, and what I'd reach for on a FinTech-style workload, and
- as a fallback, `kubectl create secret` run out-of-band / via a separate,
  access-restricted Terraform state.

This keeps the reusable module's blast radius small: it never touches
credentials, and rotating a secret doesn't require a `terraform apply`.

## Trade-offs / decisions worth flagging

- **FastAPI over Flask**: comparable size for a service this small, but
  built-in request validation and OpenAPI docs are close to free and useful
  once the API grows past three routes.
- **Kubernetes provider pinned to `>= 3.2.1, < 4.0.0`**: earlier 2.x/early-3.x
  releases have a confirmed bug ("Unexpected Identity Change") triggered when
  a resource takes unusually long to become Ready - which is exactly what
  happens if a Deployment gets stuck (e.g. on a probe or image pull issue)
  before you can fix it. v3.2.1 fixed this upstream. All resources also use
  their explicit `_v1`/`_v2` type names (`kubernetes_deployment_v1`, etc.)
  rather than the unversioned aliases, which v3.x deprecates.
- **Numeric UID required for `runAsNonRoot`**: the Dockerfile's `USER` directive
  is set to a numeric UID (`1000`), not a username. Kubernetes can only verify
  `runAsNonRoot` against a numeric UID at admission time - a named `USER` in
  the image (e.g. `USER appuser`) causes `CreateContainerConfigError` even
  though the container genuinely doesn't run as root. The module also exposes
  `run_as_user` so this can be pinned explicitly for any image, not just this
  one.
- **`read_only_root_filesystem = true` by default**: good default for a
  stateless API; exposed as a variable because some apps genuinely need
  scratch space (e.g. `/tmp`), which is better solved with an `emptyDir`
  mount than by loosening this for everyone.
- **HPA vs static `replicas`**: when `hpa_enabled = true`, Terraform still
  "owns" `spec.replicas` in the resource definition, so a later `apply` can
  fight the HPA's chosen count. I left this as a documented limitation rather
  than adding a conditional `lifecycle.ignore_changes` (Terraform can't make
  that conditional cleanly, and hardcoding `ignore_changes` unconditionally
  would fight *manual* replica changes on the more common non-HPA path).
  In production I'd split static and autoscaled deployments into distinct
  code paths rather than one flag doing both.
- **NetworkPolicy default is intentionally permissive** (same-namespace
  ingress on the app port) - it demonstrates the shape without assuming a
  specific CNI or a project's namespace-isolation model. Tightening it needs
  cluster-specific knowledge (which namespaces host the ingress controller,
  service mesh, etc.) that doesn't belong in a generic module default.
- **No StatefulSet/PVC support**: out of scope by design - this module is for
  stateless HTTP services, which is what "reusable but not over-engineered"
  points to for this exercise.

## What I'd improve for production

- **Image provenance**: build in CI, push by digest (not just tag), and pass
  the digest into Terraform - removes any "what's actually running" ambiguity.
- **Namespace-per-environment convention** and a remote Terraform backend
  with state locking (S3+DynamoDB, or Terraform Cloud) - local state is fine
  for this exercise, not for a team.
- **OpenTelemetry tracing/metrics** and structured JSON logging - currently
  there's nothing but uvicorn's default access log.
- **Tighter NetworkPolicy** scoped to the actual ingress controller/mesh
  namespace instead of "same namespace."
- **Pod-level `seccompProfile: RuntimeDefault`** and an explicit
  `automountServiceAccountToken = false` when the app doesn't call the
  Kubernetes API.
- **Canary/blue-green rollout** (Argo Rollouts or a simple `maxSurge`/
  `maxUnavailable` tune) once this sees real traffic, instead of the default
  rolling update.
- **Contract/integration tests** hitting a real deployed instance in CI
  (currently only unit tests against the FastAPI app in-process).



## Clean run-through, More Detailed.

Assumes Docker Desktop, kubectl, kind, terraform, and Python are already
installed (they are, on your machine). This is the sequence to run live.

### 1. Clone Repository

```bash
cd ~/projects
git clone https://github.com/Psalmzee/hello-service-terraform-k8s.git hello-service-demo
cd hello-service-demo
```

### 2. Run the tests

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r app/requirements-dev.txt
pytest -v
```

Expect: `4 passed`.

### 3. Build the Docker image

```bash
docker build -t hello-service:0.1.0 .
```

Optional — prove it runs standalone before involving Kubernetes:
```bash
docker run --rm -p 8000:8000 hello-service:0.1.0
```
New terminal: `curl localhost:8000/health`, then `Ctrl+C` the container.

### 4. Create a kind cluster

```bash
kind create cluster --name hello-service-test
kubectl cluster-info --context kind-hello-service-test
```

### 5. Load the image into the cluster

```bash
kind load docker-image hello-service:0.1.0 --name hello-service-test
```

### 6. Deploy with Terraform

```bash
cd examples/basic
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Type `yes`. Should complete in 15-20 seconds.

### 7. Verify

```bash
kubectl -n hello-demo get pods
kubectl -n hello-demo port-forward svc/hello-service 8080:80
```

New terminal:
```bash
curl localhost:8080/
curl localhost:8080/health
curl localhost:8080/ready
```

`Ctrl+C` the port-forward when done.

```bash
terraform output
```

### 8. CI checks

```bash
cd ~/projects/hello-service
terraform fmt -check -recursive
terraform -chdir=modules/platform-app init -backend=false
terraform -chdir=modules/platform-app validate
terraform -chdir=examples/basic init -backend=false
terraform -chdir=examples/basic validate
```

### 9. Tear down

```bash
cd examples/basic
terraform destroy
```
Type `yes`.

```bash
kind delete cluster --name hello-service-test
```

---
