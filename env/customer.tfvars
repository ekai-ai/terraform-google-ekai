# Self-service client template — "customer" stands in for a real customer
# name. Unlike an Ekai-internal environment, a self-service deployment isn't
# a tier — it's one client's own GCP project. Copy this file, rename it to
# the client's actual name, fill in the values below.
#
# The repo root and cicd/ are reusable Terraform modules (no backend block of
# their own) — this ONE tfvars file feeds the two ACTUAL state-holding root
# configs that wrap them, examples/self-deploy/root and
# examples/self-deploy/cicd (exactly like the original 4-layer design, where
# one tfvars file already served all 4 layers; each config simply ignores
# the tfvars keys it doesn't declare a variable for):
#   examples/self-deploy/root  — wraps the repo root (bootstrap + cluster +
#      platform, combined into one apply/state, down from 3 separate ones in
#      the original design)
#   examples/self-deploy/cicd  — wraps cicd/, kept as its own separate
#      apply/state, same as the original 04-cicd layer, because the ArgoCD
#      Terraform provider can only be configured from a value read from an
#      ALREADY-COMPLETED apply's state (a remote_state read), never from a
#      resource this SAME apply also creates — see cicd/main.tf's file
#      header for the full reasoning.
#
# So: 2 backend config files, 2 inits, 2 applies (in order — cicd depends on
# the root's state). Run scripts/init-state-backend.sh <name> to generate
# both, then:
#   cd examples/self-deploy/root
#   terraform init -backend-config=../../../env/backend-<name>.tfbackend
#   terraform apply -var-file=../../../env/<name>.tfvars
#   cd ../cicd
#   terraform init -backend-config=../../../env/backend-<name>-cicd.tfbackend
#   terraform apply -var-file=../../../env/<name>.tfvars
# (scripts/self-deploy.sh does all of this for you, in order — including the
# ArgoCD port-forward the cicd apply needs, see cicd/providers.tf.)
#
# dns_zone_name mirrors an existing quirk of the source codebase, not
# something this port introduced: it is NOT derived automatically from the
# bootstrap submodule's output even though bootstrap creates the zone as
# "${env}-zone" — it's set here independently, by the same convention. If you
# ever change env such that the zone name would differ, update this too.

# ─── GCP Identity ─────────────────────────────────────────────────────────────
project_id = "REPLACE_ME" # a real GCP project the deployer identity has access to
region     = "us-east1"
env        = "customer"

# ─── bootstrap submodule (Cloud DNS zone + VPC) ───────────────────────────────
dns_zone        = "customer.ekai.ai" # stand-in — a real client uses their own domain
manage_dns_zone = true

vpc_name      = "ekai-vpc"
subnet_cidr   = "10.20.0.0/20" # primary subnet
pods_cidr     = "10.28.0.0/16" # secondary range for GKE pods
services_cidr = "10.29.0.0/20" # secondary range for GKE services (ClusterIP)

# state_bucket_name intentionally left unset -- scripts/init-state-backend.sh
# defaults to ekai-terraform-state-<env>-<project_id>, which is globally
# unique on its own (project_id already is) without you needing to pick a
# name yourself. Only set state_bucket_name below if you want a different one.

# ─── cluster submodule (GKE + Cloud SQL) ──────────────────────────────────────
cluster_name = "ekai-customer-gke"

# GKE has native node-pool autoscaling (unlike EKS) -- no separate Cluster
# Autoscaler to install. min_nodes is the floor, max_nodes the ceiling; GKE
# scales between them on its own based on pending pod resource requests.
node_machine_type = "e2-standard-4"
min_nodes         = 3
max_nodes         = 5

# secrets_name intentionally omitted -- cicd_provider = "none" generates
# backend/semantics DB credentials directly instead of requiring a
# pre-existing Secret Manager secret.

# ─── In-cluster Redis + Neo4j + MinIO -- the ekai-saas chart's ERD/KEDA needs
# Redis+Neo4j, and self-service always uses in-cluster MinIO for file storage
# (the app has no native GCS storage code path) ───────────────────────────────
enable_redis_stack = true
enable_neo4j       = true
enable_minio       = true
# minio_host intentionally left unset -- defaults to "minio.<dns_zone>"

# ─── platform submodule ────────────────────────────────────────────────────────
argocd_namespace = "argocd"
# argocd_ingress_host intentionally left unset -- defaults to "argocd.<dns_zone>"
# argocd_admin_password_hashed intentionally omitted -- cicd_provider = "none"
# generates its own ArgoCD admin password + hash directly (platform submodule).
acme_email      = "REPLACE_ME"
tls_secret_name = "customer-wildcard-tls"

# ─── cicd/ (separate apply) — self-service mode ────────────────────────────────
# cicd_provider = "none" is the entire point of this file: no Cloud Build, no
# GitHub Actions -- ArgoCD pulls the ekai-saas Helm chart directly. None of
# pipelines/cd_branch/github_org apply here.
cicd_provider = "none"

ekai_namespace = "ekai-saas"

# Real, public, no-login images -- a real client would point this at
# wherever Ekai publishes release images.
existing_image_registry_base_url = "public.ecr.aws/s7m9t1b0"
image_tag                        = "latest"

# Chart Terraform installs via ArgoCD -- "*" tracks latest automatically.
# OCI registry, not the deployment-files repo's GitHub Pages: that repo is
# private, unreachable by ArgoCD running with no GitHub credentials in a
# customer's own cluster.
helm_chart_repo_url = "public.ecr.aws/s7m9t1b0/ekai-helm"
helm_chart_version  = "*"

# Cloud DNS zone resource name (created by the bootstrap submodule as "${env}-zone")
dns_zone_name = "customer-zone"
