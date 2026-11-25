# terraform-google-ekai

Deploy Ekai into **your own GCP project**. One script provisions the VPC, a
GKE cluster, Cloud SQL (PostgreSQL), in-cluster Redis/Neo4j, ArgoCD,
and the `ekai-saas` Helm chart — everything needed for a working Ekai install.

For how this repo is structured internally (why there are 2 Terraform
applies, the module layout), see [ARCHITECTURE.md](https://github.com/ekai-ai/terraform-google-ekai/blob/main/ARCHITECTURE.md). This
doc only covers deploying it. Prefer consuming it directly as a module
instead of `self-deploy.sh`? See
[Using this as a Terraform Registry module](#using-this-as-a-terraform-registry-module)
below.

## Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install), authenticated
  (`gcloud auth login`) — see [PERMISSIONS.md](https://github.com/ekai-ai/terraform-google-ekai/blob/main/PERMISSIONS.md) for exactly
  what this identity needs
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- `kubectl`, `jq`, `curl`
- A domain you can either delegate a subdomain of to Cloud DNS, or that
  already has a Cloud DNS managed zone

## Network Requirements

Only relevant if your GCP project sits behind a restrictive egress firewall (a
Shared VPC / hub-and-spoke setup, or an upstream corporate firewall). Give this
list to whoever manages that firewall before deploying — otherwise the GKE
nodes never finish joining, or Helm releases hang until Terraform times out.
Running `self-deploy.sh` from a VM *inside* that same restricted network? Then
both lists apply to that one firewall, not just the cluster's.

**Machine running `self-deploy.sh`:** `*.googleapis.com`, `github.com`,
`raw.githubusercontent.com`, `codeload.github.com`, `registry.terraform.io`,
`releases.hashicorp.com`, `licensing.ekai.ai`, plus the Helm chart repos:
`argoproj.github.io`, `charts.jetstack.io`, `charts.external-secrets.io`,
`kubernetes.github.io`, `kedacore.github.io`, `stakater.github.io`,
`emberstack.github.io`, `helm.neo4j.com`, `registry-1.docker.io`.

**The GKE cluster (nodes + pods):**

| Destination | Port | Why |
| --- | --- | --- |
| The GKE control plane endpoint (the IP printed after cluster creation) | HTTPS 443, TCP 8132 (Konnectivity proxy, if used) | Google's documented minimum for any GKE cluster ([source](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules)) |
| `*.googleapis.com` (or the `restricted.googleapis.com` VIP, `199.36.153.4/30`) | HTTPS 443 | Private Google Access — nodes have no external IP, so this is how they reach Secret Manager, Cloud DNS and Cloud Logging/Monitoring ([source](https://docs.cloud.google.com/vpc/docs/configure-private-google-access)) |
| `quay.io`, `ghcr.io`, `registry.k8s.io`, `docker.io` | HTTPS 443 | Container images for ArgoCD/cert-manager, External Secrets/Reloader/KEDA, nginx-ingress, and Redis/Neo4j/Reflector respectively |
| `public.ecr.aws` | HTTPS 443 | The `ekai-saas` Helm chart + every app image |
| `licensing.ekai.ai` | HTTPS 443 | Backend pod's own runtime license checks (not just the installer) |
| `acme-v02.api.letsencrypt.org` | HTTPS 443 | cert-manager's wildcard cert issuance |
| `api.github.com` | HTTPS 443 | GitHub code sync |

Only if you fill in the optional AWS-SES placeholders in the customer
secret: `email.<region>.amazonaws.com` (your own SES credentials) — skip
if you leave those `REPLACE_ME`.

## Deploy

```bash
git clone https://github.com/ekai-ai/terraform-google-ekai.git
cd terraform-google-ekai
cp env/customer.tfvars env/<name>.tfvars
```

`<name>` is your choice (e.g. client name) — it's both the filename and the
argument to `self-deploy.sh` below. Set `env` inside the file to the same
value. Don't edit `env/customer.tfvars` directly — it's the shared template.

**Required:** edit `env/<name>.tfvars` and set at minimum `project_id`,
`region`, `env`, `dns_zone`, `acme_email` — `self-deploy.sh` won't work with
placeholder values. Every variable has an inline comment; worth a second
look before your first deploy:

| Variable | What it controls |
|---|---|
| `project_id` | GCP project everything is created in |
| `region` | GCP region everything is created in |
| `env` | Unique name embedded in every resource this creates — must be unique per deployment |
| `dns_zone` | Domain this deploys under (`portal.<dns_zone>`, `argocd.<dns_zone>`, ...) |
| `acme_email` | Email for Let's Encrypt certificate notifications — cert-manager's ACME account registration fails without a real one |

Full reference (every variable, every default): [ARCHITECTURE.md](https://github.com/ekai-ai/terraform-google-ekai/blob/main/ARCHITECTURE.md),
`variables.tf` and `cicd/variables.tf` — or the Terraform Registry's
auto-generated Inputs page, once this is published there (see
[below](#using-this-as-a-terraform-registry-module) — not done yet).

```bash
./scripts/self-deploy.sh <name>
```

The argument to `self-deploy.sh` must match the tfvars filename in `env/`
(without `.tfvars`) — i.e. whatever you named the copy above. Use a real,
unique `env` value if you're deploying more than once — every GCP resource
this creates embeds `env` in its name, so re-running with the same value
modifies the *same* infrastructure rather than creating a second one.

`self-deploy.sh` enables the required GCP APIs, creates the scoped deployer
Service Account Terraform needs, then runs both `terraform apply`s for you
after one confirmation (it creates real, billable GCP resources).

## After a successful deploy

Check the ArgoCD URL/password, Cloud DNS nameservers, portal URL, and app
secret's name:

```bash
terraform output -C examples/self-deploy/root
terraform output -C examples/self-deploy/cicd
```

## Upgrading an install that still has MinIO

Earlier versions deployed MinIO for file storage; it's gone now. Re-running
`./scripts/self-deploy.sh <name>` on such an install **deletes the `minio`
namespace, its PVCs and their disks** — files stored in MinIO are lost, by
design. The same run also removes the leftover `USE_MINIO=true`, `MINIO_*` and
`EKAI_BUCKET` settings from the app's Secret Manager secret (it's created once
and never overwritten, so they'd otherwise keep pointing at the deleted
service).

Consuming this as a Terraform module instead of running `self-deploy.sh`? Do
that last part by hand: add a new version of the secret named by the
`app_secret_name` output, without `MINIO_ENDPOINT_URL`, `MINIO_ACCESS_KEY`,
`MINIO_SECRET_ACCESS_KEY` and `EKAI_BUCKET`, and with `USE_MINIO` set to
`"false"`.

## Tearing down

```bash
./scripts/self-deploy-destroy.sh <name>
```

Destroys everything this created, with confirmation prompts at each
destructive stage. Safe to re-run if it fails partway.

**Lost `env/<name>.tfvars`?** `self-deploy-destroy.sh` notices it's missing,
asks for the GCP project ID, and rebuilds it (and its backend config files)
straight from `gs://ekai-terraform-state-<name>-<project_id>` before
continuing — as long as that bucket still exists, nothing is actually lost.
Run `./scripts/recover-tfvars.sh <name> <project_id>` directly instead if
you want to check the recovered values (with a `terraform plan`) before
trusting them with a destroy.

## Troubleshooting

**`invalid_grant` / `reauth related error` from gcloud/Terraform** — your
*base* gcloud credentials need re-authentication, before the script even
gets to creating anything. Run `gcloud auth login` again (or
`gcloud auth application-default login` if the error is specifically about
Application Default Credentials), then re-run `self-deploy.sh`.

**`iam.disableServiceAccountKeyCreation` policy error when creating the
deployer key** — your GCP organization has an org policy blocking
downloadable Service Account keys entirely. This script's auth approach
needs that constraint disabled for the target project (or ask your GCP org
admin to grant an exception) — Workload Identity Federation would be the
alternative, but isn't supported by this script.

**ArgoCD `terraform apply` in `examples/self-deploy/cicd` can't connect**
— the ArgoCD Terraform provider connects via
`kubectl port-forward svc/argocd-server -n argocd 8080:80`, which
`self-deploy.sh` starts and tears down automatically. If you're running the
`cicd` apply manually (not via the script), start that port-forward
yourself first.

**`Error acquiring the state lock`** — a previous apply/destroy crashed or
got interrupted after taking the lock but before releasing it (the state
file itself may already be fully up to date). Confirm nothing is actually
still running, then `terraform force-unlock <lock ID>` (the ID is printed
in the error) from whichever directory the error came from.

**`deployer service account ... not found` from `self-deploy-destroy.sh`,
even though `self-deploy.sh` was run for that env** — your active `gcloud`
identity is probably stuck as the deployer SA itself, left over from an
interrupted prior run (it can't describe itself). Check with
`gcloud config get-value account`; if it shows
`ekai-terraform-<env>@...` instead of your own account, run
`gcloud config set account <your-account>` and retry.

**Lost `env/<name>.tfvars`** — see `./scripts/recover-tfvars.sh` under
[Tearing down](#tearing-down).

## Using this as a Terraform Registry module

**Not published yet** — connecting a repo to the Terraform Registry for
the first time is a one-time manual step (sign in to
[registry.terraform.io](https://registry.terraform.io) with the `ekai-ai`
org's GitHub account, then publish this repo through the UI) that hasn't
been done. Nothing below works until it has. Once it is, publishing a new
version just needs a semver tag pushed (`git tag vX.Y.Z && git push origin
vX.Y.Z`) — no further manual registry step after the first one.

```hcl
module "infra" {
  source  = "registry.terraform.io/ekai-ai/ekai/google"
  version = "~> 0.1"

  region = "us-east1"
  env    = "acme"
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

See [ARCHITECTURE.md](https://github.com/ekai-ai/terraform-google-ekai/blob/main/ARCHITECTURE.md) for why this is 2 separate applies
and the full module layout.
