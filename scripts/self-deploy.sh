#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# self-deploy.sh  —  GCP self-deployment, made easy
#
# Usage:  ./scripts/self-deploy.sh <ENV>
#   ENV   environment name — must have a matching env/<ENV>.tfvars
#         (e.g. customer)
#
# What it does, in plain terms:
#   1. Enables the GCP APIs Terraform needs (under YOUR already-authenticated
#      gcloud identity — this script needs project-admin rights to run)
#   2. Creates a scoped deployer Service Account (not your own admin identity)
#      with just the roles Terraform needs, and a JSON key for it
#   3. Initializes the Terraform state bucket
#   4. Optionally runs the actual Terraform deploy — 2 applies (repo root,
#      then cicd/; down from the original 4 separate layers, but not all the
#      way to 1 — see cicd/main.tf's file header for why), after one clear
#      confirmation, since that step creates real cloud resources and costs
#      money
#
# cicd_provider = "none" (self-service, e.g. env/customer.tfvars) generates
# its own DB/Redis/Neo4j/ArgoCD credentials and the app's shared secret
# directly in Terraform — no master secret, no password prompts here.
#
# Requires: gcloud (authenticated with a project-admin identity), kubectl,
#           jq, curl, dig, terraform.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Every gcloud call in this script must be non-interactive. Set via env vars,
# not `gcloud config set` -- that itself runs gcloud, which would hit the
# exact same hang this is meant to prevent. CLOUDSDK_CORE_DISABLE_PROMPTS
# covers the survey/usage-reporting prompt too (a subset of "interactive
# prompts"), and the update-check var below skips gcloud's periodic
# component-update network call -- both can otherwise silently hang the
# very first gcloud call (e.g. `gcloud config get-value account` right
# below) for minutes on a slow/blocked network, with zero output to explain
# why.
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
export CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SKIP_DNS_WAIT=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --skip-dns-wait) SKIP_DNS_WAIT=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]}"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 [--skip-dns-wait] <ENV>"
  echo "  ENV              must have a matching env/<ENV>.tfvars (e.g. customer)"
  echo "  --skip-dns-wait  don't poll for DNS propagation -- print the nameservers"
  echo "                   and continue straight to the cicd apply"
  exit 1
fi
ENV="$1"
TFVARS="${REPO_ROOT}/env/${ENV}.tfvars"

if [[ ! -f "${TFVARS}" ]]; then
  echo "ERROR: ${TFVARS} not found."
  exit 1
fi

for bin in gcloud kubectl jq curl dig terraform; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' is required but not installed."; exit 1; }
done

echo "════════════════════════════════════════════════════════════════"
echo " Ekai GCP self-deploy — environment: ${ENV}"
echo "════════════════════════════════════════════════════════════════"
echo

PROJECT_ID=$(grep -E '^project_id[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/')
[[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "REPLACE_ME" ]] && { echo "ERROR: set a real project_id in ${TFVARS} first."; exit 1; }
REGION=$(grep -E '^region[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/')
[[ -z "${REGION}" ]] && { echo "ERROR: could not read 'region' from ${TFVARS}"; exit 1; }
ACME_EMAIL=$(grep -E '^acme_email[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/')
[[ -z "${ACME_EMAIL}" || "${ACME_EMAIL}" == "REPLACE_ME" ]] && { echo "ERROR: set a real acme_email in ${TFVARS} first -- cert-manager's Let's Encrypt ACME account registration fails without one."; exit 1; }
# CLUSTER_NAME is read from `terraform output` after the apply below, not
# grepped from tfvars here -- cluster_name is optional (defaults to
# "ekai-<env>-gke" in Terraform when left unset), and grepping a tfvars key
# that isn't present would return empty under set -e/pipefail's error
# checking anyway. See the "cicd" section below for where it's actually set.

# Captured before anything switches it -- gcloud auth activate-service-account
# below persists across separate script invocations (unlike AWS's env-var
# credentials, which reset per shell), so without saving and restoring this,
# a second run of this script starts already authenticated as the narrowly-
# scoped deployer SA from the previous run instead of your own admin identity.
ORIGINAL_ACCOUNT=$(gcloud config get-value account 2>/dev/null)

echo "==> Project: ${PROJECT_ID}"
echo "==> Region:  ${REGION}"
echo "==> Currently authenticated as: ${ORIGINAL_ACCOUNT}"
echo "    (this identity needs project-admin rights to run this script —"
echo "     it is NOT the identity Terraform will use)"
echo

CICD_PROVIDER=$(grep -E '^cicd_provider[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/' || true)
[[ -z "${CICD_PROVIDER}" ]] && CICD_PROVIDER="none"
if [[ "${CICD_PROVIDER}" == "none" ]]; then
  echo "==> cicd_provider = \"none\" (self-service) — the cluster/platform"
  echo "    submodules generate DB/Redis/Neo4j/ArgoCD credentials directly, no master secret needed."
fi

OUT_DIR="${REPO_ROOT}/.self-deploy"
mkdir -p "${OUT_DIR}"
SECRETS_FILE="${OUT_DIR}/${ENV}-generated-secrets.txt"
: > "${SECRETS_FILE}"
chmod 600 "${SECRETS_FILE}"
echo "# Generated by self-deploy.sh for env=${ENV} — copy into your password manager, then delete this file" >> "${SECRETS_FILE}"

# ── Step 1 — Enable required GCP APIs ─────────────────────────────────────────
echo "──── Step 1/4: Enable GCP APIs ─────────────────────────────────────"
REQUIRED_APIS=(
  compute.googleapis.com
  container.googleapis.com
  sqladmin.googleapis.com
  dns.googleapis.com
  secretmanager.googleapis.com
  servicenetworking.googleapis.com
  artifactregistry.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  cloudresourcemanager.googleapis.com
)
echo "==> Enabling: ${REQUIRED_APIS[*]}"
gcloud services enable "${REQUIRED_APIS[@]}" --project="${PROJECT_ID}"
echo "✓ APIs enabled."
echo

# ── Step 2 — Deployer Service Account + roles ─────────────────────────────────
echo "──── Step 2/4: Deployer Service Account ────────────────────────────"
SA_NAME="ekai-terraform-${ENV}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "==> Service account ${SA_EMAIL} already exists — reusing."
else
  echo "==> Creating service account ${SA_EMAIL}..."
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Ekai Terraform deployer (${ENV})"

  # A freshly created SA isn't always immediately visible to the Resource
  # Manager IAM policy-binding API -- add-iam-policy-binding right after
  # create can fail with "Service account ... does not exist" even though
  # it was just created. Poll until it resolves instead of racing it.
  echo "==> Waiting for the new service account to propagate..."
  for i in $(seq 1 20); do
    if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
      echo "✓ Service account is visible."
      break
    fi
    sleep 3
  done
fi

# Predefined roles cover almost everything a single-purpose deployer identity
# needs — no custom role JSON to author/maintain, unlike AWS (no equivalently
# complete predefined-policy catalog there). resourcemanager.projectIamAdmin
# is the broadest of these: needed so Terraform can grant project-level roles
# (logging.logWriter, secretmanager.secretAccessor, artifactregistry.reader,
# ...) to the GSAs it creates for GKE nodes / ESO / cert-manager / the shared
# app Workload Identity SA.
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
  # Needed for platform's google_storage_bucket.erd_workspace (+ its bucket
  # IAM binding) -- the state-bucket-scoped roles/storage.admin grant below
  # only covers that one bucket, not project-wide bucket creation.
  roles/storage.admin
)
for ROLE in "${PROJECT_ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet >/dev/null
done
echo "✓ Project-level roles granted to ${SA_EMAIL}."

# Fresh key every run, same reasoning as AWS's script: a previously created
# key's secret is unrecoverable by the time this runs a second time (GCP
# never returns it again either), and this script always truncates
# SECRETS_FILE. Old keys are deleted outright (GCP has no "deactivate", and
# no 2-key limit like AWS to work around).
# Portable read-into-array (not `mapfile` -- that's Bash 4+ only, and macOS's
# system /bin/bash is still 3.2, so `mapfile` fails there with "command not
# found" if it's what `env bash` resolves to).
OLD_KEYS=()
while IFS= read -r KEY_LINE; do
  [[ -n "${KEY_LINE}" ]] && OLD_KEYS+=("${KEY_LINE}")
done < <(gcloud iam service-accounts keys list \
  --iam-account="${SA_EMAIL}" --managed-by=user --format='value(name)')
# ${OLD_KEYS[@]} on a *declared-but-empty* array throws "unbound variable"
# under `set -u` on Bash 3.2 (macOS's system bash) -- fixed in Bash 4.4+, but
# not there yet. The common case (a fresh SA with no existing keys) is
# exactly when OLD_KEYS is empty, so guard the expansion.
for KEY in "${OLD_KEYS[@]+"${OLD_KEYS[@]}"}"; do
  echo "==> Deleting previous key ${KEY##*/}..."
  gcloud iam service-accounts keys delete "${KEY##*/}" --iam-account="${SA_EMAIL}" --quiet
done

KEY_FILE="${OUT_DIR}/${ENV}-deployer-key.json"
echo "==> Creating a fresh key for ${SA_EMAIL}..."
gcloud iam service-accounts keys create "${KEY_FILE}" --iam-account="${SA_EMAIL}"
chmod 600 "${KEY_FILE}"
echo "GOOGLE_APPLICATION_CREDENTIALS=${KEY_FILE}" >> "${SECRETS_FILE}"
echo "✓ Key created: ${KEY_FILE}"
echo
echo "NOTE: if your GCP organization enforces the"
echo "  iam.disableServiceAccountKeyCreation constraint, the command above"
echo "  fails — that org has opted out of downloadable SA keys entirely, and"
echo "  this script's auth approach won't work there (Workload Identity"
echo "  Federation would be needed instead, out of scope for this script)."
echo

# ── Step 3 — State backend ────────────────────────────────────────────────────
echo "──── Step 3/4: State backend ───────────────────────────────────────"
"${SCRIPT_DIR}/init-state-backend.sh" "${ENV}" "${PROJECT_ID}"

# `|| true` -- grep exits 1 (not an error, just "no match") when
# state_bucket_name is commented out entirely, which under `set -euo
# pipefail` would otherwise kill the script right here with no error message.
# Fallback must match init-state-backend.sh's own default exactly, or this
# step grants IAM on a bucket name that doesn't match what actually got
# created -- including using tfvars' own env= value (ENV_PREFIX), not this
# script's ENV argument, since the two can differ (see init-state-backend.sh).
ENV_PREFIX=$(grep -E '^env[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/')
if [[ -z "${ENV_PREFIX}" ]]; then
  ENV_PREFIX="${ENV}"
fi
BUCKET_FROM_TFVARS=$(grep -E '^state_bucket_name[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/' || true)
BUCKET="${BUCKET_FROM_TFVARS:-ekai-terraform-state-${ENV}-${PROJECT_ID}}"
# storage.admin, not just objectAdmin -- self-deploy-destroy.sh's optional
# cleanup deletes the bucket itself (storage.buckets.delete), which
# objectAdmin doesn't grant (object-level permissions only).
echo "==> Granting ${SA_EMAIL} bucket admin on gs://${BUCKET}..."
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.admin" \
  --quiet >/dev/null
echo "✓ State bucket access granted."
echo

if [[ "${CICD_PROVIDER}" == "none" ]]; then
  echo "==> cicd_provider = \"none\" (self-service) — no password prompts, no"
  echo "    master secret. The platform submodule generates its own ArgoCD admin"
  echo "    password, the cluster submodule its own Cloud SQL credentials. Retrieve"
  echo "    the ArgoCD password after apply from the app secret's ARGOCD_PASSWORD"
  echo "    key, or run (from examples/self-deploy/root):"
  echo "    terraform output -raw argocd_admin_password_plaintext"
  echo
fi

# ── Step 4 — Deploy (optional) ────────────────────────────────────────────────
echo "──── Step 4/4: Deploy infrastructure ───────────────────────────────"
echo "Everything above is prep — no cluster infrastructure has been created yet."
echo "This next step creates real GCP resources (VPC, GKE, Cloud SQL, ...) and costs money."
echo
read -rp "Run the Terraform deploy now (2 applies — bootstrap+cluster+platform, then cicd)? [y/N] " CONFIRM </dev/tty
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo
  echo "Skipped. When you're ready, deploy locally:"
  echo "  export GOOGLE_APPLICATION_CREDENTIALS=${KEY_FILE}"
  echo "  cd ${REPO_ROOT}/examples/self-deploy/root"
  echo "  terraform init -backend-config=../../../env/backend-${ENV}.tfbackend"
  echo "  terraform apply -var-file=../../../env/${ENV}.tfvars"
  echo "  cd ../cicd"
  echo "  (needs 'kubectl port-forward svc/argocd-server -n argocd 8080:80' running first — see cicd/providers.tf's comments for why)"
  echo "  terraform init -backend-config=../../../env/backend-${ENV}-cicd.tfbackend"
  echo "  terraform apply -var-file=../../../env/${ENV}.tfvars"
  echo
  echo "Generated key/secrets saved at: ${SECRETS_FILE} / ${KEY_FILE}"
  echo "Copy them into your password manager, then delete these files."
  exit 0
fi

export GOOGLE_APPLICATION_CREDENTIALS="${KEY_FILE}"
echo "==> Activating deployer identity for gcloud/kubectl calls..."
gcloud auth activate-service-account "${SA_EMAIL}" --key-file="${KEY_FILE}"
gcloud config set project "${PROJECT_ID}" >/dev/null

# Restore whatever identity was active before the line above, no matter how
# this script exits (success, error, Ctrl-C) -- gcloud auth
# activate-service-account persists across separate invocations (unlike AWS's
# env-var credentials, which reset per shell), so without this, a script that
# dies partway (e.g. a failed terraform apply) leaves gcloud silently stuck
# on the narrowly-scoped deployer SA for every future gcloud command,
# including the next run of this same script.
if [[ -n "${ORIGINAL_ACCOUNT}" ]]; then
  trap 'gcloud config set account "${ORIGINAL_ACCOUNT}" >/dev/null 2>&1 || true' EXIT
fi

echo "==> Waiting for the new key to propagate..."
for i in $(seq 1 20); do
  if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
    echo "✓ Key is active."
    break
  fi
  sleep 5
done

# 2 applies, in order: bootstrap+cluster+platform first (its state feeds
# cicd's terraform_remote_state read — see cicd/main.tf's file header for why
# cicd can't be folded into this same apply), then cicd. Both run from
# examples/self-deploy/{root,cicd} — the repo root and cicd/ directories are
# pure Terraform modules now (no backend block of their own; see
# providers.tf / cicd/providers.tf), so they can't be applied directly.
# examples/self-deploy/{root,cicd} are the actual state-holding root configs
# that wrap them — see examples/self-deploy/root/main.tf's header comment.
echo
echo "════════ terraform apply (bootstrap + cluster + platform) ════════"
cd "${REPO_ROOT}/examples/self-deploy/root"
terraform init -upgrade -reconfigure -backend-config="../../../env/backend-${ENV}.tfbackend"
terraform apply -auto-approve -compact-warnings -var-file="../../../env/${ENV}.tfvars"

# ── DNS delegation — only when Terraform just created a NEW Cloud DNS zone.
# Delegating dns_zone to Google's nameservers at your registrar/parent zone
# is out-of-band and human-timed -- Terraform has no access to do it for you.
# Until it's done, cert-manager's ACME DNS-01 challenge for the wildcard TLS
# cert can never succeed (Let's Encrypt can't find the zone via public DNS to
# verify the challenge record), even though the apply above still succeeds --
# the Certificate resource just sits at READY=False indefinitely. Confirmed
# live: this exact scenario left ArgoCD reachable but serving an invalid
# cert (browser "connection is not private").
MANAGE_DNS_ZONE=$(grep -E '^manage_dns_zone[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*\(true\|false\).*/\1/')
if [[ "${MANAGE_DNS_ZONE}" == "true" ]]; then
  DNS_ZONE=$(grep -E '^dns_zone[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/')
  # Strip trailing dots -- GCP's API returns FQDNs with them
  # (ns-cloud-d1.googledomains.com.), so without this every comparison
  # against dig's own trailing-dot-stripped output below would falsely
  # report "not propagated" even once delegation is already correct.
  ZONE_NS=$(terraform output -json name_servers 2>/dev/null | jq -r '.[]' | sed 's/\.$//' | sort)
  if [[ -n "${ZONE_NS}" ]]; then
    echo
    echo "════════ DNS delegation required ════════"
    echo "Terraform just created a Cloud DNS zone for ${DNS_ZONE}. Add an NS"
    echo "record for ${DNS_ZONE} at your domain registrar (or your parent DNS"
    echo "zone) pointing at each of these nameservers:"
    echo "${ZONE_NS}" | sed 's/^/  /'
    echo
    if [[ "${SKIP_DNS_WAIT}" -eq 1 ]]; then
      echo "==> DNS wait skipped."
    else
      read -rp "Press Enter once you've added it (Ctrl-C to do this later and re-run) " _ </dev/tty
      echo "==> Checking DNS delegation (this can take several minutes to propagate)..."
      for i in $(seq 1 40); do
        RESOLVED=$(dig +short NS "${DNS_ZONE}" @8.8.8.8 2>/dev/null | sed 's/\.$//' | sort)
        if [[ -n "${RESOLVED}" && "${RESOLVED}" == "${ZONE_NS}" ]]; then
          echo "✓ DNS delegation confirmed."
          break
        fi
        echo "  Not propagated yet (attempt ${i}/40) — waiting 15s..."
        sleep 15
      done
      if [[ "${RESOLVED}" != "${ZONE_NS}" ]]; then
        echo "⚠ Still not resolving after 10 minutes — the ArgoCD/app TLS cert"
        echo "  will keep failing until this delegation is correct. cert-manager"
        echo "  retries automatically in the background once it is; no need to"
        echo "  re-run this script for that."
      fi
    fi
  fi
fi

# ── cicd — needs a port-forward to ArgoCD's Service (see cicd/providers.tf:
# server_addr = "localhost:8080"). Kept this way deliberately for self-deploy
# instead of the real ingress hostname AWS uses — a fresh client domain's
# wildcard cert depends on Cloud DNS being delegated at the registrar first
# (an out-of-band, human-timed step Terraform can't wait for), which would
# otherwise block ArgoCD auth before the cluster even has its first
# Application. Port-forwarding straight to the Service's ClusterIP sidesteps
# DNS delegation and cert issuance entirely for this step.
echo
echo "════════ terraform apply (cicd) ════════"
echo "==> Fetching cluster credentials for port-forward..."
# Read the actual cluster name Terraform just created/used -- not grepped
# from tfvars, since cluster_name is optional there and this is the one
# place that already knows the real value regardless of whether it was
# explicitly set or defaulted.
CLUSTER_NAME=$(terraform output -raw cluster_name)
gcloud container clusters get-credentials "${CLUSTER_NAME}" --region "${REGION}" --project "${PROJECT_ID}"

kubectl port-forward svc/argocd-server -n argocd 8080:80 >/dev/null 2>&1 &
PF_PID=$!
# One combined trap -- a second `trap ... EXIT` replaces the first rather
# than stacking, so the account-restore trap set right after activating the
# deployer SA would otherwise silently stop firing once this trap is set.
cleanup_pf() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
  if [[ -n "${ORIGINAL_ACCOUNT}" ]]; then
    gcloud config set account "${ORIGINAL_ACCOUNT}" >/dev/null 2>&1 || true
  fi
}
trap cleanup_pf EXIT

echo "==> Waiting for ArgoCD port-forward to be ready..."
for i in $(seq 1 20); do
  if curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
    echo "✓ ArgoCD reachable on localhost:8080."
    break
  fi
  sleep 3
done

cd "${REPO_ROOT}/examples/self-deploy/cicd"
terraform init -upgrade -reconfigure -backend-config="../../../env/backend-${ENV}-cicd.tfbackend"
terraform apply -auto-approve -compact-warnings -var-file="../../../env/${ENV}.tfvars"

# The Certificate object's name is always "${ENV}-wildcard-tls" regardless of
# what tls_secret_name is set to (that only names the Secret it produces) --
# see modules/platform/main.tf's kubectl_manifest.wildcard_cert.
CERT_NAME="${ENV}-wildcard-tls"
echo
echo "==> Waiting for the wildcard TLS certificate to be issued..."
CERT_READY=false
for i in $(seq 1 20); do
  if [[ "$(kubectl get certificate "${CERT_NAME}" -n cert-manager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == "True" ]]; then
    CERT_READY=true
    break
  fi
  sleep 30
done

if [[ "${CERT_READY}" != "true" ]]; then
  # cert-manager's DNS-01 propagation self-check can get stuck reporting
  # "not yet propagated" indefinitely even once DNS is genuinely fine --
  # confirmed live: a stale internal cache in the controller, not a real DNS
  # problem. Deleting the Order and restarting the controller pod clears it.
  # Only one Certificate exists per self-service cluster, so clearing every
  # Order in the namespace is equivalent to clearing this one, without
  # needing to match its randomly-suffixed name.
  echo "⚠ Not ready after 10 minutes -- forcing a fresh cert-manager attempt..."
  kubectl delete order -n cert-manager --all --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl delete pod -n cert-manager -l app.kubernetes.io/component=controller --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl wait --for=condition=Ready pod -n cert-manager -l app.kubernetes.io/component=controller --timeout=90s >/dev/null 2>&1 || true

  for i in $(seq 1 20); do
    if [[ "$(kubectl get certificate "${CERT_NAME}" -n cert-manager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == "True" ]]; then
      CERT_READY=true
      break
    fi
    sleep 30
  done
fi

if [[ "${CERT_READY}" == "true" ]]; then
  echo "✓ TLS certificate issued."
else
  echo "⚠ TLS certificate still not ready -- ArgoCD/app URLs will show cert errors"
  echo "  until it resolves on its own. Check: kubectl get certificate ${CERT_NAME} -n cert-manager"
fi

cleanup_pf
trap - EXIT
echo "==> Restored your original gcloud identity (${ORIGINAL_ACCOUNT})."

echo
echo "✓ Deploy complete for env=${ENV}."
echo "Generated key/secrets saved at: ${SECRETS_FILE} / ${KEY_FILE} — copy into your password manager, then delete these files."
