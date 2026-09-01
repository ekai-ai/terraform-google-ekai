# Permissions the bootstrapping identity actually needs

`scripts/self-deploy.sh` and `scripts/self-deploy-destroy.sh` run as **two
different GCP identities**, not one:

1. **The bootstrapping identity** — whoever's authenticated in `gcloud`
   when you run the script (`gcloud auth login`, a service account, ...).
   Its job is enabling APIs, creating one deployer Service Account, granting
   it project-level roles, and setting up the Terraform state bucket. It
   never runs `terraform apply` itself.
2. **The scoped deployer** (`ekai-terraform-<env>@<project>.iam.gserviceaccount.com`)
   — a Service Account the bootstrapping identity creates. Terraform runs as
   *this* identity for everything else (VPC, GKE, Cloud SQL, DNS, Secret
   Manager, ...), via the predefined project roles `self-deploy.sh` grants it
   (see `PROJECT_ROLES` in that script — no custom role JSON to author, GCP's
   predefined-role catalog already covers this).

This file is about identity 1 only, traced against every `gcloud` call both
scripts actually make (not identity 2's, which is self-contained in the
roles above).

## Why this is less narrowly scopable than AWS

AWS's equivalent doc ([the AWS distribution's PERMISSIONS.md](https://github.com/ekai-ai/terraform-aws-ekai/blob/main/PERMISSIONS.md))
scopes the bootstrapping identity down to managing two specific,
pre-authored IAM policy documents by name. GCP's model doesn't have a direct
equivalent: granting a project-level predefined role to a Service Account
(`gcloud projects add-iam-policy-binding --role=roles/X`) is a single
action requiring the single project-wide permission
`resourcemanager.projects.setIamPolicy` — GCP has no built-in way to scope
that permission down to "only these specific roles." So while the
bootstrapping identity is nowhere near full Owner/Editor, it does need
`resourcemanager.projectIamAdmin`, which — inherently, not through any
choice made here — could also be used to grant broader roles to other
principals. Predefined roles below; if your org uses custom roles instead,
match these permissions.

```
roles/serviceusage.serviceUsageAdmin      # enable the required GCP APIs
roles/iam.serviceAccountAdmin             # create/delete the deployer SA itself
roles/iam.serviceAccountKeyAdmin          # create/list/delete its keys -- a separate role, serviceAccountAdmin doesn't include key permissions
roles/resourcemanager.projectIamAdmin     # grant the deployer SA its project-level roles
roles/storage.admin                       # create + manage the Terraform state bucket
```

That's the entire bootstrapping identity's footprint. It never directly
creates a VPC, GKE cluster, Cloud SQL instance, or DNS zone — those all
happen under the deployer SA's own roles, granted (not held) by this
identity.

## Where each permission is used

| Permission (role) | Where | Why |
|---|---|---|
| `roles/serviceusage.serviceUsageAdmin` | `self-deploy.sh` Step 1 | `gcloud services enable` for compute/container/sqladmin/dns/secretmanager/servicenetworking/artifactregistry/iam/iamcredentials/cloudresourcemanager |
| `roles/iam.serviceAccountAdmin` | `self-deploy.sh` Step 2, `self-deploy-destroy.sh` | create/describe the deployer SA; delete it during teardown |
| `roles/iam.serviceAccountKeyAdmin` | `self-deploy.sh` Step 2, `self-deploy-destroy.sh` | list/create/delete the deployer SA's keys |
| `roles/resourcemanager.projectIamAdmin` | `self-deploy.sh` Step 2 | `gcloud projects add-iam-policy-binding`, once per role in `PROJECT_ROLES` |
| `roles/storage.admin` | `init-state-backend.sh`, `self-deploy.sh` Step 3, `cleanup-gcp-env.sh` (optional) | create/describe/update the state bucket; grant the deployer SA `roles/storage.admin` scoped to just that bucket (needs bucket-lifecycle permissions, not just object read/write — the optional teardown deletes the bucket itself) |

`self-deploy-destroy.sh` reuses the deployer SA's own key throughout,
including to delete the SA itself at the end (`iam.serviceAccounts.delete`,
which cascades to its keys) — unlike AWS, where the scoped deployer
explicitly cannot manage IAM users (not even itself) and the script has to
switch back to the bootstrapping identity for that step. GCP's deployer SA
holds `roles/iam.serviceAccountAdmin` project-wide (it needs this to create
GSAs for GKE nodes / ESO / cert-manager / the shared app Workload Identity
SA), which also happens to cover deleting itself — no credential-switch-back
needed here.

## Why this had to be a separate identity in the first place

Unlike AWS's EKS (`authentication_mode = CONFIG_MAP`, which grants
Kubernetes RBAC only to the exact IAM identity that created the cluster),
GKE grants `kubectl` access to any principal holding `roles/container.admin`
on the project — so this split isn't strictly required for the same reason
AWS's is. It exists anyway for the same practical benefit: anyone who can
run this script can also destroy what it created, without needing your
original `gcloud auth login` session, and Terraform's blast radius stays
visibly scoped to one named, revocable Service Account instead of your own
identity.
