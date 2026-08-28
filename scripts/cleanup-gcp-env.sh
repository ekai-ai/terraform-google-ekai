#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# cleanup-gcp-env.sh — GCP environment post-destroy cleanup
#
# Usage:  ./scripts/cleanup-gcp-env.sh <ENV> <PROJECT_ID>
#
# What it does:
#   1. Clears all DNS records from the Cloud DNS zone (so zone can be deleted)
#   2. Deletes the GCS Terraform state bucket
#   3. Cleans local .terraform directories
#
# Run this BEFORE `terraform destroy` (for DNS) or AFTER (for bucket cleanup).
# Idempotent — safe to run multiple times.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Args ──────────────────────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <ENV> <PROJECT_ID>"
  echo "  ENV        — environment name (demo, dev, prod, …)"
  echo "  PROJECT_ID — GCP project ID (text, not numeric)"
  exit 1
fi

ENV="$1"
PROJECT_ID="$2"
ZONE_NAME="${ENV}-zone"
BUCKET="ekai-terraform-state-${ENV}"

echo "==> Environment : ${ENV}"
echo "==> Project     : ${PROJECT_ID}"
echo "==> DNS Zone    : ${ZONE_NAME}"
echo "==> State bucket: gs://${BUCKET}"
echo ""

# ── 1. Clear DNS records ──────────────────────────────────────────────────────
echo "==> Step 1: Clearing DNS records from zone '${ZONE_NAME}'..."
if gcloud dns managed-zones describe "${ZONE_NAME}" \
     --project="${PROJECT_ID}" &>/dev/null; then

  # Delete all records except SOA and NS (auto-removed with the zone)
  DELETED=0
  while IFS=',' read -r name rtype ttl; do
    [[ -z "$name" ]] && continue
    echo "    Deleting: ${name} ${rtype}"
    gcloud dns record-sets delete "${name}" \
      --type="${rtype}" \
      --zone="${ZONE_NAME}" \
      --project="${PROJECT_ID}" \
      --quiet 2>/dev/null && DELETED=$((DELETED+1)) || true
  done < <(gcloud dns record-sets list \
              --zone="${ZONE_NAME}" \
              --project="${PROJECT_ID}" \
              --format="csv[no-heading](name,type,ttl)" \
           | grep -v ",SOA," | grep -v ",NS,")

  echo "==> Cleared ${DELETED} DNS record(s). Zone is ready to delete."
else
  echo "==> Zone '${ZONE_NAME}' not found — skipping."
fi
echo ""

# ── 2. Delete GCS state bucket ────────────────────────────────────────────────
echo "==> Step 2: Deleting GCS state bucket gs://${BUCKET}..."
if gcloud storage buckets describe "gs://${BUCKET}" \
     --project="${PROJECT_ID}" &>/dev/null; then
  gcloud storage rm -r "gs://${BUCKET}/**" \
    --project="${PROJECT_ID}" 2>/dev/null || true
  gcloud storage buckets delete "gs://${BUCKET}" \
    --project="${PROJECT_ID}"
  echo "==> Bucket gs://${BUCKET} deleted."
else
  echo "==> Bucket gs://${BUCKET} not found — skipping."
fi
echo ""

# ── 3. Clean local Terraform state ───────────────────────────────────────────
echo "==> Step 3: Cleaning local .terraform directories..."
find "${REPO_ROOT}" -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
find "${REPO_ROOT}" -name "*.tfplan" -delete 2>/dev/null || true
echo "==> Local cleanup complete."
echo ""

echo "✅ GCP environment '${ENV}' fully cleaned."
echo "   Next apply: run init-state-backend.sh first to recreate the state bucket."
