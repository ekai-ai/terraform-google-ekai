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
roles/storage.admin                       # create the ERD workspace GCS bucket (enable_erd_gcs_fuse)
```
