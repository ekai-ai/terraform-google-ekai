# terraform-google-ekai

Deploy Ekai into **your own GCP project**. One script provisions the VPC, a
GKE cluster, Cloud SQL (PostgreSQL), in-cluster Redis/Neo4j/MinIO, ArgoCD,
and the `ekai-saas` Helm chart — everything needed for a working Ekai install.

For how this repo is structured internally (why there are 2 Terraform
applies, the module layout, the Terraform Registry option), see
[ARCHITECTURE.md](ARCHITECTURE.md). This doc only covers deploying it.

## Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install), authenticated
  (`gcloud auth login`) — see [PERMISSIONS.md](PERMISSIONS.md) for exactly
  what this identity needs
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- `kubectl`, `jq`, `curl`
- A domain you can either delegate a subdomain of to Cloud DNS, or that
  already has a Cloud DNS managed zone

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

Full reference (every variable, every default): [ARCHITECTURE.md](ARCHITECTURE.md),
`variables.tf` and `cicd/variables.tf` — or the Terraform Registry's
auto-generated Inputs page once this is published there.

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

The app secret (`ekai-<env>` in Secret Manager, e.g. `ekai-customer`) ships
with a `REPLACE_ME` placeholder for the one thing the app needs a real value
for out of the box: AWS SES credentials for signup invite emails (used
regardless of which cloud hosts the cluster). Fill them in with one command
— replace the `...` values below with real ones (an AWS IAM user with SES
send access is enough — self-service uses in-cluster MinIO for file storage,
so no S3 access is needed on that IAM user):

```bash
gcloud secrets versions access latest --secret=ekai-customer --project=<your-project> | jq '
    .AWS_ACCESS_KEY_ID = "..." |
    .AWS_SECRET_ACCESS_KEY = "..." |
    .SES_AWS_REGION = "..." |
    .AWS_SES_FROM_EMAIL = "..."
  ' | gcloud secrets versions add ekai-customer --project=<your-project> --data-file=-
```

LLM keys (`ANTHROPIC_API_KEY`/`OPENAI_API_KEY`), Cognito, and Document AI
(`SEMANTICS__*`) ship blank — out of scope for this pass, same as GitHub sync
and Langfuse tracing. Set them the same way, via `gcloud secrets versions
add`, if/when you need those features. The app picks up any secret update
automatically within about a minute (ESO syncs it into the cluster, Reloader
restarts the affected pods) — no `terraform apply` needed for this step.

Optional — check the ArgoCD URL/password, Cloud DNS nameservers, portal URL,
and app secret's name:

```bash
terraform output -C examples/self-deploy/root
terraform output -C examples/self-deploy/cicd
```

## Tearing down

```bash
./scripts/self-deploy-destroy.sh <name>
```

Destroys everything this created, with confirmation prompts at each
destructive stage. Safe to re-run if it fails partway.

**Lost `env/<name>.tfvars`?** As long as
`gs://ekai-terraform-state-<name>-<project_id>` still exists, run
`./scripts/recover-tfvars.sh <name> <project_id>` first — it rebuilds both
`env/<name>.tfvars` and its backend config files straight from state, then
prints the `terraform plan` command to verify the result before you trust
it with a destroy.

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
