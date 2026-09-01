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
```

**Required:** edit `env/customer.tfvars` and set at minimum `project_id`,
`region`, `env`, `dns_zone` before continuing — `self-deploy.sh` will not
work with the template's placeholder values. Every variable has a full
explanation as an inline comment in that file; the ones most worth a second
look before your first deploy:

| Variable | What it controls |
|---|---|
| `project_id` | GCP project everything is created in |
| `region` | GCP region everything is created in |
| `env` | Unique name embedded in every resource this creates — must be unique per deployment |
| `dns_zone` | Domain this deploys under (`portal.<dns_zone>`, `argocd.<dns_zone>`, ...) |

Full reference (every variable, every default): [ARCHITECTURE.md](ARCHITECTURE.md),
`variables.tf` and `cicd/variables.tf` — or the Terraform Registry's
auto-generated Inputs page once this is published there.

```bash
./scripts/self-deploy.sh customer
```

The argument to `self-deploy.sh` must match the tfvars filename in `env/`
(without `.tfvars`). Use a real, unique `env` value (not `customer`) if
you're deploying more than once — every GCP resource this creates embeds
`env` in its name, so re-running with the same value modifies the *same*
infrastructure rather than creating a second one.

`self-deploy.sh` enables the required GCP APIs, creates the scoped deployer
Service Account Terraform needs, then runs both `terraform apply`s for you
after one confirmation (it creates real, billable GCP resources).

## After a successful deploy

The app secret (`ekai-<env>` in Secret Manager, e.g. `ekai-customer`) ships
with several `REPLACE_ME` placeholders the app needs real values for. Fill
them in with one command — replace the `...` values below with real ones (an
AWS IAM user with SES send access is enough — self-service uses in-cluster
MinIO for file storage, so no S3 access is needed on that IAM user):

```bash
gcloud secrets versions access latest --secret=ekai-customer --project=<your-project> | jq '
    .ANTHROPIC_API_KEY = "sk-ant-..." |
    .OPENAI_API_KEY = "sk-..." |
    .COGNITO_REGION = "..." |
    .COGNITO_USER_POOL_ID = "..." |
    .COGNITO_CLIENT_ID = "..." |
    .AWS_ACCESS_KEY_ID = "..." |
    .AWS_SECRET_ACCESS_KEY = "..." |
    .SES_AWS_REGION = "..." |
    .AWS_SES_FROM_EMAIL = "..." |
    .SEMANTICS__GOOGLE_CLOUD_PROJECT = "..." |
    .SEMANTICS__GCS_DOCAI_PROCESSOR_ID = "..." |
    .SEMANTICS__GCS_INPUT_BUCKET = "..." |
    .SEMANTICS__GCS_OUTPUT_BUCKET = "..."
  ' | gcloud secrets versions add ekai-customer --project=<your-project> --data-file=-
```

Only `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`SES_AWS_REGION`/
`AWS_SES_FROM_EMAIL` are needed to unblock the invite-email flow (the app
sends signup invites via AWS SES regardless of which cloud hosts the
cluster); the rest can stay `REPLACE_ME` until you need those specific
features. The app picks up the new secret automatically within about a
minute (ESO syncs it into the cluster, Reloader restarts the affected pods)
— no `terraform apply` needed for this step.

Optional — check the ArgoCD URL/password, Cloud DNS nameservers, portal URL,
and app secret's name:

```bash
terraform output -C examples/self-deploy/root
terraform output -C examples/self-deploy/cicd
```

## Tearing down

```bash
./scripts/self-deploy-destroy.sh customer
```

Destroys everything this created, with confirmation prompts at each
destructive stage. Safe to re-run if it fails partway.

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
