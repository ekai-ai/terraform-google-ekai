# Permissions

`self-deploy.sh` / `self-deploy-destroy.sh` run as two identities.

## 1. Bootstrapping identity (you — `gcloud auth login`, or a service account)

Enables APIs, creates the deployer SA, grants it project roles, sets up the
Terraform state bucket. Never runs `terraform apply`. Grant it:

```
roles/serviceusage.serviceUsageAdmin      # enable required APIs
roles/iam.serviceAccountAdmin             # create/delete the deployer SA
roles/iam.serviceAccountKeyAdmin          # create/delete its keys (serviceAccountAdmin doesn't cover keys)
roles/resourcemanager.projectIamAdmin     # grant the deployer SA its project roles
roles/storage.admin                       # create/manage the state bucket
```

`resourcemanager.projectIamAdmin` is unavoidably project-wide — GCP has no
way to scope "can grant only these roles."

Live-tested 2026-09-09 in `ekai-dev`: a service account holding only these 5
roles ran every `gcloud` call both scripts make as this identity (enable
APIs, create + key the deployer SA, grant it all 10 roles below, create the
state bucket, grant it bucket-scoped `storage.admin`). No failures, nothing
missing.

## 2. Deployer SA (`ekai-terraform-<env>@<project>.iam.gserviceaccount.com`)

Created by the bootstrapping identity; runs Terraform for everything else.
Auto-granted by `self-deploy.sh` (`PROJECT_ROLES`) — nothing to configure,
reference only:

```
roles/compute.networkAdmin
roles/servicenetworking.networksAdmin
roles/container.admin
roles/cloudsql.admin
roles/dns.admin
roles/secretmanager.admin
roles/artifactregistry.admin
roles/iam.serviceAccountAdmin
roles/iam.serviceAccountUser
roles/resourcemanager.projectIamAdmin
```
