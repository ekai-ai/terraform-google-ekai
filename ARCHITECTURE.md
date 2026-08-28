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
