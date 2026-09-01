# Architecture

For how to actually deploy this, see [README.md](README.md). This doc
covers how the repo is structured and why, for anyone modifying it or
consuming it a different way than `self-deploy.sh`.

## Why 2 Terraform applies, not 1

This repo has 2 layers:

- **The modules** — the repo root (this directory) and `cicd/` are plain,
  reusable Terraform modules: no `backend` block, nothing applied directly.
  The repo root wires up the `bootstrap`, `cluster`, and `platform`
  submodules into one apply's worth of resources; `cicd/` wires up
  `modules/cicd` (the app secret, ExternalSecret, Workload Identity, and the
  ArgoCD Application that actually deploys the app).
- **The root configs** — `examples/self-deploy/root/` and
  `examples/self-deploy/cicd/` are the actual state-holding configs that
  call those two modules and get applied. `examples/self-deploy/cicd/`
  reads `examples/self-deploy/root/`'s state via `terraform_remote_state`.

Why 2 applies and not 1: the ArgoCD Terraform provider's `password` field
has to be a value Terraform already knows *before* it starts applying — it
can't be a same-apply resource's computed attribute (unlike the
kubernetes/helm/kubectl providers, whose `exec`-based auth is specifically
designed to defer until first use). The root config generates that
password; `cicd/` has to run afterward, as its own apply, to read it back
safely. See `cicd/main.tf`'s header comment for the full explanation.

## ArgoCD auth: port-forward, not the public ingress hostname

`cicd/providers.tf`'s `provider "argocd"` block connects via
`server_addr = "localhost:8080"`, expecting a
`kubectl port-forward svc/argocd-server -n argocd 8080:80` already running
(`self-deploy.sh` starts and tears this down for you automatically). This is
deliberate, not a shortcut: a fresh client domain's wildcard TLS cert is
issued via cert-manager's Let's Encrypt DNS-01 challenge through Cloud DNS,
which requires the zone to actually be delegated at the domain registrar —
an out-of-band, human-timed step Terraform can't wait for. If the ArgoCD
provider depended on the real public hostname instead, a fresh deploy would
be blocked on DNS delegation before ArgoCD could even receive its first
Application. Port-forwarding straight to the Service's ClusterIP (ArgoCD
runs with `server.insecure=true`) sidesteps DNS delegation and cert
issuance entirely for Terraform's own control-plane calls — those can
proceed immediately after the cluster and ArgoCD exist, and DNS/cert
issuance can be fixed up on your own timeline afterward without blocking
the apply.

## Manual deploy (without self-deploy.sh)

```bash
./scripts/init-state-backend.sh <name>

cd examples/self-deploy/root
terraform init -backend-config=../../../env/backend-<name>.tfbackend
terraform apply -var-file=../../../env/<name>.tfvars

# start the ArgoCD port-forward before the cicd apply (see above)
gcloud container clusters get-credentials <cluster_name> --region <region> --project <project_id>
kubectl port-forward svc/argocd-server -n argocd 8080:80 &

cd ../cicd
terraform init -backend-config=../../../env/backend-<name>-cicd.tfbackend
terraform apply -var-file=../../../env/<name>.tfvars
```

To destroy manually: `terraform destroy` in `examples/self-deploy/cicd/`
first (it needs the cluster/ArgoCD from the root apply still live to clean
up against, and the same port-forward running), then in
`examples/self-deploy/root/`.

## Using this as a Terraform Registry module

The repo root and `cicd/` are structured as ordinary Terraform modules, so
once this repo is connected to the Terraform Registry (a one-time manual
step someone with access to the registry/repo settings has to do — publish
the repo, then push a semver tag; **this does not work until that's been
done**), you can consume them directly instead of using
`examples/self-deploy/`:

```hcl
module "infra" {
  source  = "registry.terraform.io/ekai-ai/ekai/google"
  version = "~> 0.1"

  region = "us-east1"
  env    = "<your-name>"
  # ...every variable in variables.tf
}

module "cicd" {
  source  = "registry.terraform.io/ekai-ai/ekai/google//cicd"
  version = "~> 0.1"
  # ...every variable in cicd/variables.tf, plus the values module.infra
  # exports that cicd needs (see examples/self-deploy/cicd/main.tf for
  # exactly which — with a registry module you'd normally wire these with
  # module.infra.X directly if both modules live in the same config, instead
  # of examples/self-deploy's terraform_remote_state indirection, which only
  # exists because self-deploy.sh's 2-apply split needs an actual state
  # boundary between them)
}
```

`examples/self-deploy/` is the reference implementation of exactly this
pattern (plus the backend/provider wiring a real deployment needs) — read it
before writing your own. Note that `provider "google"/"kubernetes"/etc.` are
configured *inside* root/cicd themselves (not left for the consumer to
supply) — that's what makes the kubernetes/helm/kubectl exec-auth pattern
above work at all, but it also means a registry consumer can't override
provider configuration via `providers = {}`.

## Layout

```
main.tf / variables.tf / outputs.tf / providers.tf   # "infra" module (bootstrap+cluster+platform) — no backend, not applied directly
cicd/
  main.tf / variables.tf / outputs.tf / providers.tf  # "cicd" module — no backend, not applied directly
examples/self-deploy/
  root/    # actual root config wrapping the "infra" module — backend + required_providers + module "infra" { source = "../../.." }
  cicd/    # actual root config wrapping the "cicd" module — backend + required_providers + module "cicd" { source = "../../../cicd" }
modules/
  bootstrap/   # Cloud DNS zone + VPC
  cluster/     # GKE cluster + node pool, Cloud SQL, Artifact Registry
  platform/    # nginx ingress, ESO, Redis, Neo4j, MinIO, ArgoCD, KEDA, reloader, cert-manager
  cicd/        # app secret, ExternalSecret, Workload Identity, ArgoCD Application, DNS records
  <shared low-level modules used by the above>
env/
  customer.tfvars   # template — copy and fill in; shared by both applies
scripts/
  self-deploy.sh            # deployer SA setup + both terraform applies, guided
  self-deploy-destroy.sh    # both terraform destroys + optional cleanup
  init-state-backend.sh     # creates the GCS state bucket + both backend configs
  cleanup-gcp-env.sh        # DNS records + state bucket cleanup, used by the above
```

## Scope

The self-service path (`cicd_provider = "none"`) is the supported,
documented flow in this distribution. Unlike the AWS equivalent of this
repo, the `cloud_build` and `github_actions` CI/CD modules are included
here and remain genuinely functional if you set `cicd_provider` to either
value — they're Ekai-internal deployment paths, not documented or supported
for client use, but weren't stripped out during the port. Don't rely on
them without reading `modules/cicd/main.tf` and the Ekai-internal
`gcp-terraform` source they were ported from.

## Variable reference

Every variable in `variables.tf` and `cicd/variables.tf` — the README's
table only covers the handful worth a second look. `project_id`/`region`/
`env`/`secrets_name`/`cicd_provider` are declared in both files identically
(see "Shared across layers" below); everything else lives in only one.

### Shared across layers (`variables.tf` and `cicd/variables.tf`)

| Variable | Default | What it controls |
|---|---|---|
| `project_id` | — (required) | GCP project ID that owns all resources |
| `region` | — (required) | GCP region — must match the state bucket location |
| `env` | — (required) | Environment name (e.g. `client1`, `dev`, `prod`) — used in resource naming and state prefixes |
| `secrets_name` | `""` | Legacy master-secret name; ignored when `cicd_provider = "none"` |
| `cicd_provider` | `"none"` | `"none"` (supported) / `"cloud_build"` / `"github_actions"` (included and functional, but not documented for client use — see Scope above) |

### Bootstrap submodule (Cloud DNS zone + VPC)

| Variable | Default | What it controls |
|---|---|---|
| `vpc_name` | `"vpc"` | Base VPC name (prefixed with `env`) |
| `subnet_cidr` | — (required) | Primary CIDR for the private subnet |
| `pods_cidr` | — (required) | Secondary CIDR for GKE pods |
| `services_cidr` | — (required) | Secondary CIDR for GKE services |
| `dns_zone` | — (required) | Domain this deploys under, e.g. `client1.ekai.ai` |
| `manage_dns_zone` | `true` | Terraform creates the Cloud DNS zone; `false` to look up an existing one |
| `state_bucket_name` | — (required) | Globally unique GCS bucket name for Terraform state — created by `scripts/init-state-backend.sh`, outside Terraform |

### Cluster submodule (GKE + Cloud SQL + Artifact Registry)

| Variable | Default | What it controls |
|---|---|---|
| `cluster_name` | — (required) | GKE cluster name |
| `node_machine_type` | `"e2-standard-4"` | Compute Engine machine type for cluster nodes |
| `min_nodes` / `max_nodes` | `1` / `5` | Node pool floor/ceiling per zone — GKE autoscales natively between them |
| `k8s_version` | `""` → GKE latest stable | Kubernetes version prefix (e.g. `1.35`) |
| `db_instance_tier` | `"db-custom-2-7680"` | Cloud SQL machine type |
| `db_version` | `"15"` | PostgreSQL major version |
| `master_ipv4_cidr_block` | `"172.16.0.0/28"` | CIDR for the GKE control plane private endpoint — must not overlap the VPC/subnet CIDRs |
| `cloudbuild_sa_email` | `""` → auto-computed | Cloud Build SA email for Artifact Registry writer access |
| `pipelines` | — (required) | Map of service CI/CD pipeline definitions |

### Platform submodule (ingress-nginx, ESO, ArgoCD, KEDA, Reloader, cert-manager, Redis, Neo4j, MinIO, ECR pull auth)

| Variable | Default | What it controls |
|---|---|---|
| `argocd_namespace` | `"argocd"` | ArgoCD's namespace |
| `argocd_admin_password_hashed` | `""` | Bcrypt hash; ignored for self-service (generated directly instead) |
| `argocd_ingress_host` | — (required) | ArgoCD's hostname, e.g. `argocd.client1.ekai.ai` |
| `tls_secret_name` | `"wildcard-tls"` | K8s TLS Secret used by ArgoCD and other Ingresses (cert-manager or pre-provisioned) |
| `nginx_ingress_chart_version` | `"4.10.1"` | ingress-nginx chart version |
| `eso_chart_version` | `"0.10.3"` | External Secrets Operator chart version |
| `argocd_chart_version` | `""` → latest | argo-cd chart version |
| `keda_chart_version` | `"2.16.0"` | KEDA chart version |
| `reloader_chart_version` | `"1.2.0"` | Stakater Reloader chart version — restarts pods when K8s Secrets change |
| `cert_manager_chart_version` | `"v1.14.5"` | cert-manager chart version |
| `enable_cert_manager` | `true` | Deploy cert-manager for GKE TLS — set `false` if TLS is handled externally |
| `cert_manager_sa_id` | `""` | Service account ID for cert-manager Workload Identity — override per-env in shared projects |
| `acme_email` | `"umar@ekai.ai"` | Email for Let's Encrypt certificate notifications — **override this** |
| `enable_redis_stack` | `false` | Deploy Redis Stack (Bitnami chart) in-cluster — the app's ERD/KEDA features need it |
| `redis_namespace` / `redis_storage_size` / `redis_storage_class` | `"redis"` / `"10Gi"` / `"standard-rwo"` | Redis namespace and PVC sizing |
| `redis_password` | `""` | Redis password override |
| `enable_neo4j` | `false` | Deploy Neo4j community edition in-cluster — the app's ERD features need it |
| `neo4j_namespace` / `neo4j_storage_size` / `neo4j_storage_class` | `"neo4j"` / `"20Gi"` / `"standard-rwo"` | Neo4j namespace and PVC sizing |
| `neo4j_memory_request` / `neo4j_memory_limit` | `"2Gi"` / `"4Gi"` | Neo4j pod memory sizing |
| `enable_minio` | `false` | Deploy in-cluster MinIO — self-service always needs this (no native GCS storage path in the app) |
| `minio_namespace` | `"minio"` | MinIO namespace |
| `minio_host` | `""` | MinIO API hostname, e.g. `minio.demo.ekai.ai` |
| `minio_default_buckets` | `["ekai-files"]` | Buckets MinIO creates on first boot |
| `minio_persistence_size` / `minio_storage_class` / `minio_replicas` | `"20Gi"` / `"standard-rwo"` / `1` | MinIO PVC sizing and replica count |
| `enable_ecr_pull_auth` | `false` | Deploy the CronJob that lets GKE pull images from AWS ECR — requires the 3 vars below |
| `ecr_credentials_secret_name` | — (required) | Secret name the CronJob writes ECR credentials into |
| `aws_account_id` / `aws_ecr_region` | `""` / `"us-east-1"` | AWS account + region owning the ECR registry — required when `enable_ecr_pull_auth = true` |
| `aws_ecr_access_key_id` / `aws_ecr_secret_access_key` | `""` / `""` | AWS credentials for ECR pull — sensitive, never commit to tfvars |
| `ecr_namespace` | `"ekai-saas"` | Namespace where the ECR pull secret and CronJob are created |

### `cicd/variables.tf` — self-service app config

| Variable | Default | What it controls |
|---|---|---|
| `dns_zone` | `""` | Base DNS zone (self-service only) — derives service hostnames and `FRONTEND_URL` |
| `existing_image_registry_base_url` | `""` | Where container images are pulled from (self-service only) |
| `helm_chart_repo_url` | `""` | OCI registry the `ekai-saas` chart is published to — bare host+path, no `oci://` prefix |
| `helm_chart_version` | `"*"` | Chart version — `"*"` auto-tracks latest via ArgoCD, no apply needed per release |
| `image_tag` | `""` | Image tag deployed — passed through as the chart's `imageTag` |
| `erd_storage_class` | `"standard-rwo"` | StorageClass for ERD's workspace PVC |
| `ingress_class_name` | `"nginx"` | Ingress controller class for the chart |
| `tls_secret_name` | `"wildcard-tls"` | TLS Secret the chart's Ingress references — matches the combined root's cert-manager wildcard cert |
| `claude_model` | `"claude-haiku-4-5-20251001"` | Claude model the semantics service uses |
| `vector_embedding_model` | `"text-embedding-3-small"` | OpenAI embedding model for vector search |
| `vector_embedding_batch_size` | `100` | Batch size for embedding generation |
| `secret_value_overrides` | `{}` | Escape hatch for any app-secret key with no dedicated variable — wins on conflicts |
| `manifest_folder` | `"manifest-files"` | Folder in the `deployment-files` repo where ArgoCD reads K8s manifests |
| `ekai_namespace` | — (required) | Kubernetes namespace for the app's services |
| `dns_zone_name` | — (required) | Cloud DNS managed zone *name* (not the DNS name itself) — used for service A records |
| `cluster_name` | `"ekai-gke"` | GKE cluster name — queries the cluster endpoint directly from the GKE API in `providers.tf` |

### `cicd/variables.tf` — not functional in this distribution

Read only when `cicd_provider != "none"` (self-service has no default and
doesn't need to set these): `cd_branch`, `github_org`. `pipelines` and
`argocd_ingress_host` are declared here too but are shared/required — see
above.
