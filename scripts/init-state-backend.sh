#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# init-state-backend.sh  —  GCP Terraform state bootstrap
#
# Usage:  ./scripts/init-state-backend.sh <ENV> [PROJECT_ID]
#   ENV        — environment name — must have a matching env/<ENV>.tfvars
#   PROJECT_ID — optional override; if omitted, read from env/<ENV>.tfvars
#
# What it does:
#   1. Reads project_id and region from env/<ENV>.tfvars
#   2. Creates (or verifies) a GCS bucket: ekai-terraform-state-<ENV>
#      with versioning + uniform bucket-level access
#   3. Writes TWO backend config files, one per state-holding root config
#      (down from the original 4 layers, but not all the way to 1 — see
#      cicd/main.tf's file header for why the cicd apply has to stay
#      separate). The repo root and cicd/ are Terraform modules (no backend
#      block of their own); examples/self-deploy/{root,cicd} are the actual
#      root configs that use these files:
#        env/backend-<ENV>.tfbackend       — examples/self-deploy/root (bootstrap+cluster+platform)
#        env/backend-<ENV>-cicd.tfbackend  — examples/self-deploy/cicd
#
# Idempotent — safe to run multiple times; existing resources are not modified.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Args ──────────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ENV> [PROJECT_ID]"
  echo "  ENV        — environment name (dev, demo, prod, …)"
  echo "  PROJECT_ID — optional override; if omitted, read from env/<ENV>.tfvars"
  exit 1
fi
ENV="$1"
PROJECT_ID_OVERRIDE="${2:-}"

TFVARS="${REPO_ROOT}/env/${ENV}.tfvars"
if [[ ! -f "${TFVARS}" ]]; then
  echo "ERROR: ${TFVARS} not found."
  exit 1
fi

# ── Extract project_id — prefer explicit override over tfvars ────────────────
if [[ -n "${PROJECT_ID_OVERRIDE}" ]]; then
  PROJECT_ID="${PROJECT_ID_OVERRIDE}"
  echo "==> project_id from argument: ${PROJECT_ID}"
else
  PROJECT_ID=$(grep -E '^project_id\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/')
  echo "==> project_id from tfvars: ${PROJECT_ID}"
fi

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "REPLACE_ME" ]]; then
  echo "ERROR: project_id is empty or still a placeholder in ${TFVARS}"
  echo "       Pass the real project ID as a second argument: $0 ${ENV} <project-id>"
  exit 1
fi

REGION=$(grep -E '^region\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/')
if [[ -z "${REGION}" ]]; then
  echo "ERROR: could not extract 'region' from ${TFVARS}"
  exit 1
fi

# Use state_bucket_name from tfvars if set, otherwise default to a name that
# embeds project_id -- project_id is already globally unique in GCP, so this
# default never collides with anyone else's bucket without you having to
# pick a name yourself.
BUCKET_FROM_TFVARS=$(grep -E '^state_bucket_name\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/')
if [[ -n "${BUCKET_FROM_TFVARS}" ]]; then
  BUCKET="${BUCKET_FROM_TFVARS}"
  echo "==> State bucket from tfvars: ${BUCKET}"
else
  BUCKET="ekai-terraform-state-${ENV}-${PROJECT_ID}"
  echo "==> State bucket (default):   ${BUCKET}"
fi
echo "==> Project      : ${PROJECT_ID}"
echo "==> Region       : ${REGION}"

# ── Create or verify GCS bucket ──────────────────────────────────────────────
if gcloud storage buckets describe "gs://${BUCKET}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "==> Bucket already exists — skipping creation."
else
  echo "==> Creating bucket..."
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --no-public-access-prevention
fi

# ── Versioning ────────────────────────────────────────────────────────────────
echo "==> Enabling versioning..."
gcloud storage buckets update "gs://${BUCKET}" \
  --versioning \
  --project="${PROJECT_ID}"

# ── Uniform bucket-level access (idempotent) ──────────────────────────────────
echo "==> Enforcing uniform bucket-level access..."
gcloud storage buckets update "gs://${BUCKET}" \
  --uniform-bucket-level-access \
  --project="${PROJECT_ID}"

# ── Write backend config files ────────────────────────────────────────────────
ENV_DIR="${REPO_ROOT}/env"

# Use env value from tfvars as state prefix (may differ from the ENV argument)
ENV_PREFIX=$(grep -E '^env\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/')
if [[ -z "${ENV_PREFIX}" ]]; then
  ENV_PREFIX="${ENV}"
fi
echo "==> State prefix  : ${ENV_PREFIX}"

ROOT_BACKEND_FILE="${ENV_DIR}/backend-${ENV}.tfbackend"
echo "==> Writing ${ROOT_BACKEND_FILE}..."
cat > "${ROOT_BACKEND_FILE}" <<EOF
bucket = "${BUCKET}"
prefix = "${ENV_PREFIX}/combined.tfstate"
EOF

CICD_BACKEND_FILE="${ENV_DIR}/backend-${ENV}-cicd.tfbackend"
echo "==> Writing ${CICD_BACKEND_FILE}..."
cat > "${CICD_BACKEND_FILE}" <<EOF
bucket = "${BUCKET}"
prefix = "${ENV_PREFIX}/cicd.tfstate"
EOF

echo ""
echo "Done. Backend files written to ${ROOT_BACKEND_FILE} and ${CICD_BACKEND_FILE}"
echo ""
echo "Apply, in order (the repo root and cicd/ are Terraform modules, not"
echo "applyable directly — examples/self-deploy/{root,cicd} are the actual"
echo "state-holding root configs that wrap them):"
echo "  cd examples/self-deploy/root"
echo "  terraform init -backend-config=../../../env/backend-${ENV}.tfbackend"
echo "  terraform apply -var-file=../../../env/${ENV}.tfvars"
echo "  cd ../cicd"
echo "  terraform init -backend-config=../../../env/backend-${ENV}-cicd.tfbackend"
echo "  terraform apply -var-file=../../../env/${ENV}.tfvars"
