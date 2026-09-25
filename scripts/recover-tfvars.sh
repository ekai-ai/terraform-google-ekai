#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# recover-tfvars.sh  —  rebuild a lost env/<ENV>.tfvars + backend files from state
#
# Usage:  ./scripts/recover-tfvars.sh <ENV> <PROJECT_ID>
#   ENV         — environment name whose env/<ENV>.tfvars was lost
#   PROJECT_ID  — GCP project it was deployed into (you already know this)
#
# What it does:
#   1. Reads the env's combined.tfstate directly from its GCS state bucket
#      (gs://ekai-terraform-state-<ENV>-<PROJECT_ID>) -- if that bucket is
#      gone too, there's nothing left to recover from and this can't help.
#   2. Pulls the handful of values that can't just come from
#      env/customer.tfvars's own defaults: region, dns_zone, acme_email,
#      tls_secret_name -- everything else in the template is already a
#      sensible default (node size, redis/neo4j/minio toggles, etc.).
#   3. Writes env/<ENV>.tfvars (starting from customer.tfvars, the values
#      above substituted in) and both backend config files.
#
# You still need to verify the result before trusting it with a destroy --
# see README.md's Troubleshooting entry for the terraform plan check
# (expect no replacements, no large add/destroy counts).
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ENV="${1:?Usage: $0 <ENV> <PROJECT_ID>}"
PROJECT_ID="${2:?Usage: $0 <ENV> <PROJECT_ID>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUCKET="ekai-terraform-state-${ENV}-${PROJECT_ID}"
STATE_FILE="/tmp/${ENV}-combined.tfstate"

echo "==> Fetching gs://${BUCKET}/${ENV}/combined.tfstate/default.tfstate ..."
gsutil cat "gs://${BUCKET}/${ENV}/combined.tfstate/default.tfstate" > "${STATE_FILE}"

echo "==> Extracting values from state..."
VALUES=$(python3 << PYEOF
import json, re

with open("${STATE_FILE}") as f:
    state = json.load(f)

def find(mod, typ, name):
    for r in state["resources"]:
        if r.get("module", "") == mod and r["type"] == typ and r["name"] == name and r.get("instances"):
            return r["instances"][0]["attributes"]
    return None

subnet = find("module.infra.module.bootstrap.module.vpc", "google_compute_subnetwork", "private")
dnszone = find("module.infra.module.bootstrap", "google_dns_managed_zone", "env")
clusterissuer = find("module.infra.module.platform", "kubectl_manifest", "cluster_issuer")

region = subnet["region"] if subnet else ""
dns_zone = dnszone["dns_name"].rstrip(".") if dnszone else ""

acme_email = ""
if clusterissuer:
    m = re.search(r'"email":\s*"([^"]+)"', clusterissuer.get("yaml_body", ""))
    acme_email = m.group(1) if m else ""

print(f"{region}|{dns_zone}|{acme_email}")
PYEOF
)

IFS='|' read -r REGION DNS_ZONE ACME_EMAIL <<< "${VALUES}"

if [[ -z "${REGION}" || -z "${DNS_ZONE}" ]]; then
  echo "ERROR: couldn't find region/dns_zone in state -- state file may be from"
  echo "an older layout. Recover manually (see README.md Troubleshooting)."
  exit 1
fi

echo "  region:     ${REGION}"
echo "  dns_zone:   ${DNS_ZONE}"
echo "  acme_email: ${ACME_EMAIL:-<not found, left as REPLACE_ME>}"

# The Certificate object's name (and so its identity, for Terraform's
# purposes) is always "${ENV}-wildcard-tls" regardless of what
# tls_secret_name is actually set to -- see modules/platform/main.tf's
# kubectl_manifest.wildcard_cert. No need to pull the real historical value
# out of state; this is safe to just compute.
TLS_SECRET_NAME="${ENV}-wildcard-tls"

TFVARS_OUT="${REPO_ROOT}/env/${ENV}.tfvars"
if [[ -f "${TFVARS_OUT}" ]]; then
  echo "ERROR: ${TFVARS_OUT} already exists -- not overwriting. Delete it first if you want to regenerate."
  exit 1
fi

echo "==> Writing ${TFVARS_OUT}..."
sed \
  -e "s|^project_id[[:space:]]*=.*|project_id = \"${PROJECT_ID}\"|" \
  -e "s|^region[[:space:]]*=.*|region = \"${REGION}\"|" \
  -e "s|^env[[:space:]]*=.*|env = \"${ENV}\"|" \
  -e "s|^dns_zone[[:space:]]*=.*|dns_zone = \"${DNS_ZONE}\"|" \
  -e "s|^acme_email[[:space:]]*=.*|acme_email = \"${ACME_EMAIL:-REPLACE_ME}\"|" \
  -e "s|^tls_secret_name[[:space:]]*=.*|tls_secret_name = \"${TLS_SECRET_NAME}\"|" \
  "${REPO_ROOT}/env/customer.tfvars" > "${TFVARS_OUT}"
echo "# Reconstructed from live Terraform state by recover-tfvars.sh -- verify" \
  "with a terraform plan before trusting it with a destroy." \
  | cat - "${TFVARS_OUT}" > "${TFVARS_OUT}.tmp" && mv "${TFVARS_OUT}.tmp" "${TFVARS_OUT}"

echo "==> Writing backend config files..."
cat > "${REPO_ROOT}/env/backend-${ENV}.tfbackend" << EOF
bucket = "${BUCKET}"
prefix = "${ENV}/combined.tfstate"
EOF
cat > "${REPO_ROOT}/env/backend-${ENV}-cicd.tfbackend" << EOF
bucket = "${BUCKET}"
prefix = "${ENV}/cicd.tfstate"
EOF

rm -f "${STATE_FILE}"

echo
echo "✓ Recovered env/${ENV}.tfvars + backend files."
echo "  Now verify before trusting it with a destroy:"
echo "    cd examples/self-deploy/root"
echo "    terraform init -reconfigure -backend-config=../../../env/backend-${ENV}.tfbackend"
echo "    terraform plan -var-file=../../../env/${ENV}.tfvars"
echo "  Expect no '# forces replacement' and no large add/destroy counts."
