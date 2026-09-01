#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# self-deploy-destroy.sh  —  tear down what self-deploy.sh created
#
# Usage:  ./scripts/self-deploy-destroy.sh <ENV>
#
# The repo root and cicd/ are reusable Terraform modules (no backend block
# of their own — see providers.tf / cicd/providers.tf); the actual
# state-holding root configs that apply/destroy them live at
# examples/self-deploy/{root,cicd} (down from the original 4 layers, but not
# all the way to 1 — see cicd/main.tf's file header for why the cicd apply
# has to stay separate from root's). Destroy runs in reverse dependency order:
#   1. terraform destroy in examples/self-deploy/cicd FIRST — it depends on
#      the root config's cluster/ArgoCD still being live (its kubernetes/
#      kubectl/argocd providers need a real API server + running ArgoCD to
#      clean up ExternalSecrets/the ArgoCD Application against), same as the
#      original script destroyed 04-cicd before 03-platform/02-cluster.
#   2. terraform destroy in examples/self-deploy/root (bootstrap+cluster+
#      platform, combined) — Terraform sequences this internally in reverse
#      dependency order (platform, then cluster, then bootstrap — see
#      main.tf's module depends_on chain), with one defensive retry (Cloud
#      SQL + VPC peering teardown timing isn't fully guaranteed even with the
#      service networking connection's deletion_policy = "ABANDON") — the
#      same retry structure the original script applied to its final
#      01-bootstrap destroy.
#   3. optional: delete the GCS state bucket + DNS records (cleanup-gcp-env.sh)
#   4. optional: delete the deployer Service Account + its key
#
# Each destructive stage has its own confirmation — say no to any of them and
# the rest still runs. Safe to re-run if it fails partway.
#
# Requires: gcloud, kubectl, terraform, jq, curl.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ENV>"
  exit 1
fi
ENV="$1"
TFVARS="${REPO_ROOT}/env/${ENV}.tfvars"

if [[ ! -f "${TFVARS}" ]]; then
  echo "ERROR: ${TFVARS} not found."
  exit 1
fi

for bin in gcloud kubectl terraform jq curl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' is required but not installed."; exit 1; }
done

PROJECT_ID=$(grep -E '^project_id\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/')
REGION=$(grep -E '^region\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/')
CLUSTER_NAME=$(grep -E '^cluster_name\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/')
[[ -z "${PROJECT_ID}" || -z "${REGION}" ]] && { echo "ERROR: could not read project_id/region from ${TFVARS}"; exit 1; }

echo "════════════════════════════════════════════════════════════════"
echo " Ekai GCP self-deploy DESTROY — environment: ${ENV} (project: ${PROJECT_ID})"
echo "════════════════════════════════════════════════════════════════"
echo
echo "This will permanently destroy the VPC, GKE cluster, Cloud SQL database,"
echo "ArgoCD, and DNS zone for '${ENV}'. This cannot be undone."
echo
read -rp "Type the environment name (${ENV}) to confirm: " CONFIRM_ENV
if [[ "${CONFIRM_ENV}" != "${ENV}" ]]; then
  echo "Did not match — aborted. Nothing was touched."
  exit 1
fi

# ── Deployer identity — reuse self-deploy.sh's key if present, else mint one.
# Unlike AWS's EKS (authentication_mode = CONFIG_MAP grants cluster access
# ONLY to the creating identity), GKE grants kubectl access to ANY principal
# holding roles/container.admin on the project — so reusing the existing key
# is safe as long as the deployer SA itself still exists with its roles
# intact (self-deploy.sh granted them).
SA_NAME="ekai-terraform-${ENV}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
OUT_DIR="${REPO_ROOT}/.self-deploy"
KEY_FILE="${OUT_DIR}/${ENV}-deployer-key.json"

if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "ERROR: deployer service account ${SA_EMAIL} not found — was self-deploy.sh run for this env?"
  exit 1
fi

if [[ ! -f "${KEY_FILE}" ]]; then
  echo "==> No local key file at ${KEY_FILE} — creating a fresh one."
  mkdir -p "${OUT_DIR}"
  gcloud iam service-accounts keys create "${KEY_FILE}" --iam-account="${SA_EMAIL}"
  chmod 600 "${KEY_FILE}"
fi

# Captured before anything switches it -- see the cleanup_all trap below for why.
ORIGINAL_ACCOUNT=$(gcloud config get-value account 2>/dev/null)

export GOOGLE_APPLICATION_CREDENTIALS="${KEY_FILE}"
echo "==> Activating deployer identity..."
gcloud auth activate-service-account "${SA_EMAIL}" --key-file="${KEY_FILE}"
gcloud config set project "${PROJECT_ID}" >/dev/null

# One combined trap, armed for the rest of the script (never cleared early) --
# gcloud auth activate-service-account persists across separate invocations
# (unlike AWS's env-var credentials, which reset per shell), so without
# this, a script that dies partway (e.g. a failed terraform destroy) leaves
# gcloud silently stuck on the narrowly-scoped deployer SA for every future
# gcloud command, including the next run of this same script. Killing an
# already-exited PF_PID is harmless, so this stays safe to leave armed even
# once the port-forward is no longer needed.
PF_PID=""
cleanup_all() {
  [[ -n "${PF_PID}" ]] && kill "${PF_PID}" >/dev/null 2>&1
  if [[ -n "${ORIGINAL_ACCOUNT}" ]]; then
    gcloud config set account "${ORIGINAL_ACCOUNT}" >/dev/null 2>&1
  fi
  true
}
trap cleanup_all EXIT

# ── 1. Terraform destroy — examples/self-deploy/cicd FIRST ───────────────────
# Must run while the root config's cluster/ArgoCD are still live — cicd's
# kubernetes/kubectl/argocd providers (port-forwarded to ArgoCD's Service,
# and the GKE cluster queried live — see cicd/providers.tf) need a real API
# server and a running ArgoCD to clean up ExternalSecrets/the ArgoCD
# Application against.
echo
echo "════════ terraform destroy (cicd) ════════"
echo "==> Fetching cluster credentials for port-forward..."
if gcloud container clusters get-credentials "${CLUSTER_NAME}" --region "${REGION}" --project "${PROJECT_ID}" 2>/dev/null; then
  kubectl port-forward svc/argocd-server -n argocd 8080:80 >/dev/null 2>&1 &
  PF_PID=$!

  echo "==> Waiting for ArgoCD port-forward to be ready..."
  for i in $(seq 1 20); do
    curl -sf http://localhost:8080/healthz >/dev/null 2>&1 && { echo "✓ ArgoCD reachable."; break; }
    sleep 3
  done
else
  echo "==> Cluster not reachable (already gone?) — proceeding without port-forward."
fi

cd "${REPO_ROOT}/examples/self-deploy/cicd"
terraform init -upgrade -reconfigure -backend-config="../../../env/backend-${ENV}-cicd.tfbackend" 1>/dev/null
terraform destroy -auto-approve -compact-warnings -var-file="../../../env/${ENV}.tfvars"

if [[ -n "${PF_PID}" ]]; then
  kill "${PF_PID}" >/dev/null 2>&1 || true
  PF_PID=""
fi

echo
echo "✓ cicd destroyed for env=${ENV}."

# ── 2. Terraform destroy — examples/self-deploy/root (bootstrap+cluster+platform)
# Terraform sequences this internally in reverse dependency order — platform,
# then cluster, then bootstrap (see main.tf's module depends_on chain) — the
# same order the original 4-separate-states script used to drive by hand
# across 03-platform/02-cluster/01-bootstrap (now that cicd is already gone
# above). One defensive retry, same as the original script's final
# 01-bootstrap destroy — Cloud SQL + VPC peering teardown timing isn't fully
# guaranteed even with deletion_policy = "ABANDON".
echo
echo "════════ terraform destroy (bootstrap + cluster + platform) ════════"
cd "${REPO_ROOT}/examples/self-deploy/root"
terraform init -upgrade -reconfigure -backend-config="../../../env/backend-${ENV}.tfbackend" 1>/dev/null
if ! terraform destroy -auto-approve -compact-warnings -var-file="../../../env/${ENV}.tfvars"; then
  echo "First destroy attempt failed — waiting 60s then retrying once..."
  sleep 60
  terraform refresh -compact-warnings -var-file="../../../env/${ENV}.tfvars" 2>/dev/null || true
  terraform destroy -auto-approve -compact-warnings -var-file="../../../env/${ENV}.tfvars"
fi

echo
echo "✓ Terraform infrastructure destroyed for env=${ENV}."

# ── Optional: GCS state bucket + DNS records ─────────────────────────────────
echo
read -rp "Also delete the GCS state bucket and DNS records? [y/N] " CLEAN_GCP
if [[ "${CLEAN_GCP}" =~ ^[Yy]$ ]]; then
  "${SCRIPT_DIR}/cleanup-gcp-env.sh" "${ENV}" "${PROJECT_ID}"
else
  echo "Skipped — the env name (${ENV}) is not reusable until this is run, since the state bucket still exists."
fi

# ── Optional: the deployer Service Account + key ─────────────────────────────
# Unlike AWS (where the policy documents are separate, reusable objects and
# only the user + its attachments are removed), GCP granted these 10 roles
# directly on the PROJECT's IAM policy -- deleting the SA alone leaves all 10
# as dangling bindings in that policy forever (GCP does not auto-clean them).
# Remove each binding explicitly first, same role list self-deploy.sh grants.
echo
read -rp "Also delete the deployer service account ${SA_EMAIL} and its key? [y/N] " CLEAN_SA
if [[ "${CLEAN_SA}" =~ ^[Yy]$ ]]; then
  PROJECT_ROLES=(
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
  )
  for ROLE in "${PROJECT_ROLES[@]}"; do
    gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="${ROLE}" \
      --condition=None \
      --quiet >/dev/null 2>&1 || true
  done
  gcloud iam service-accounts delete "${SA_EMAIL}" --project="${PROJECT_ID}" --quiet
  rm -f "${KEY_FILE}"
  echo "  Removed ${SA_EMAIL}'s project IAM roles, deleted the service account, and removed the local key file."
else
  echo "Skipped."
fi

echo
echo "✓ Done."
