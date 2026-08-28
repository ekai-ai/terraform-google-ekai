# ──────────────────────────────────────────────────────────────────────────────
# cicd submodule
# Depends on the cluster and platform submodules (wired by ../../cicd/main.tf
# — via `data "terraform_remote_state" "combined"` against the combined
# bootstrap+cluster+platform state one level up — instead of the original
# THREE separate `data "terraform_remote_state"` reads against bootstrap's,
# cluster's, and platform's own states).
# Provisions Cloud Build triggers, Artifact Registry image URLs, ArgoCD
# Application, ExternalSecret CRDs, and Cloud DNS service records.
#
# Per-service Secret Manager secrets ({env}-<service>) are created and owned
# by the client — same pattern as AWS/Azure. Ekai provides DATABASE_URL and
# REDIS_* values after the cluster + platform submodules apply; client adds
# them to their Secret Manager secret before first build.
#
# cicd_provider = "none" (self-service): none of the above applies. Terraform
# generates the entire ekai-${env} secret directly (DB/Redis/Neo4j/MinIO/
# ArgoCD credentials, service URLs, crypto keys) and ArgoCD pulls the
# ekai-saas Helm chart directly from a public OCI registry — no CI/CD, no
# git access, no pre-existing master secret. See local.self_service below.
#
# The original 04-cicd/main.tf also declared a
# `data "terraform_remote_state" "bootstrap"` block here, but never actually
# referenced any of its outputs anywhere in this layer (verified by grep) —
# a genuinely dead read, dropped entirely (same treatment as the equivalent
# dead read in the platform submodule).
# ──────────────────────────────────────────────────────────────────────────────

locals {
  # One source of truth for "is this a self-service deploy" — every
  # cicd_provider == "none" check below reads this instead, so there's one
  # place to fix if the provider values or self-service condition ever change.
  self_service = var.cicd_provider == "none"

  # formerly `data.terraform_remote_state.cluster.outputs.artifact_registry_url`
  # / `data.terraform_remote_state.platform.outputs.nginx_ingress_ip` — now
  # plain input variables wired from ../../cicd/main.tf's combined-state read.
  registry_url     = var.artifact_registry_url
  nginx_ingress_ip = var.nginx_ingress_ip
}

# ── Master credentials from Secret Manager — self_service skips this
# entirely: no pre-existing secret required, the cluster/platform submodules
# generate DB/Redis/Neo4j creds and the ArgoCD password directly instead. ───
data "google_secret_manager_secret_version" "master" {
  count   = local.self_service ? 0 : 1
  project = var.project_id
  secret  = var.secrets_name
}

locals {
  _secret               = local.self_service ? {} : jsondecode(data.google_secret_manager_secret_version.master[0].secret_data)
  github_token          = local.self_service ? "" : local._secret["github_token"]
  github_username       = local.self_service ? "" : local._secret["github_username"]
  github_email          = local.self_service ? "" : local._secret["github_email"]
  # formerly `data.terraform_remote_state.platform.outputs.argocd_admin_password_plaintext`
  argocd_admin_password = local.self_service ? var.argocd_admin_password_plaintext : local._secret["argocd_admin_password_plain"]

  # Transform var.pipelines (cloud_build schema: dockerfile) into the
  # github_actions_cicd schema (build_cmd + pre_build_cmds) for the
  # github_actions module. The module receives the full "org/repo" format.
  gha_pipelines = {
    for svc, cfg in var.pipelines : svc => {
      branch          = cfg.branch
      github_repo     = "${var.github_org}/${cfg.github_repo}"
      build_cmd       = "docker build -f ${cfg.dockerfile} . -t $IMAGE"
      manifest_folder = cfg.manifest_folder
      manifest_file   = cfg.manifest_file
      ingresshost     = cfg.ingresshost
      pre_build_cmds  = []
    }
  }
}

# ── Cloud Build triggers — one per pipeline ───────────────────────────────────
# Disabled when cicd_provider != "cloud_build".
module "cloud_build" {
  count  = var.cicd_provider == "cloud_build" ? 1 : 0
  source = "../cloud_build"

  project_id      = var.project_id
  region          = var.region
  env             = var.env
  pipelines       = var.pipelines
  secrets_name    = var.secrets_name
  github_owner    = var.github_org
  cd_branch       = var.cd_branch
  manifest_folder = var.manifest_folder
  registry_url    = local.registry_url
}

# ── GitHub Actions CI/CD — WIF + per-repo SAs + workflow YAML ────────────────
# Enabled when cicd_provider = "github_actions".
module "github_actions_cicd" {
  count  = var.cicd_provider == "github_actions" ? 1 : 0
  source = "../github_actions_cicd"

  project_id      = var.project_id
  region          = var.region
  env             = var.env
  pipelines       = local.gha_pipelines
  github_org      = var.github_org
  github_token    = local.github_token
  github_username = local.github_username
  github_email    = local.github_email
  cd_branch       = var.cd_branch
  registry_url    = local.registry_url
}

# ekai-saas namespace is created in the platform submodule
# (kubernetes_namespace.ekai_saas). Read it here so ArgoCD Application and
# ExternalSecrets can reference it.
data "kubernetes_namespace" "ekai_saas" {
  metadata {
    name = var.ekai_namespace
  }
}

# ── cicd_provider = "none" only: Terraform CREATES the app's shared secret
# directly — no more requiring the client to pre-create it with a placeholder
# JSON before terraform apply. Every value Terraform can know for certain
# (Cloud SQL/Redis/Neo4j/MinIO creds, service URLs derived from dns_zone,
# freshly generated crypto keys, safe non-secret defaults) is filled in for
# real. Only values that genuinely require the client's own external
# accounts (LLM API keys, Cognito, GitHub App, Document AI) are left as
# "REPLACE_ME". Update those after apply with:
#   gcloud secrets versions access latest --secret=ekai-<env> --project=<project> \
#     | jq '.ANTHROPIC_API_KEY = "sk-ant-..." | .OPENAI_API_KEY = "sk-..." |
#           .COGNITO_REGION = "..." | .COGNITO_USER_POOL_ID = "..." | .COGNITO_CLIENT_ID = "..." |
#           .SEMANTICS__GOOGLE_CLOUD_PROJECT = "..." | .SEMANTICS__GCS_DOCAI_PROCESSOR_ID = "..." |
#           .SEMANTICS__GCS_INPUT_BUCKET = "..." | .SEMANTICS__GCS_OUTPUT_BUCKET = "..."' \
#     | gcloud secrets versions add ekai-<env> --project=<project> --data-file=-
# lifecycle.ignore_changes means Terraform only sets this content once, at
# creation — it never overwrites whatever the client puts there afterward.
resource "random_id" "encryption_key" {
  count       = local.self_service ? 1 : 0
  byte_length = 32
}

resource "random_id" "jwt_secret" {
  count       = local.self_service ? 1 : 0
  byte_length = 32
}

resource "random_id" "fernet_key" {
  count       = local.self_service ? 1 : 0
  byte_length = 32
}

locals {
  # Matches the real, verified secret shape — DATABASE_URL for backend's own
  # database, VECTOR_DATABASE_URL for semantics' (same Cloud SQL instance,
  # separate database + user). self_service: the cluster submodule generates
  # these directly (module.cloud_sql's self_service branch) and exports them
  # via the combined root state — no master secret involved at all.
  generated_db_urls = local.self_service ? {
    DATABASE_URL        = "postgresql://${var.backend_db_username}:${var.backend_db_password}@${var.cloud_sql_ip}:5432/${var.backend_db_name}"
    VECTOR_DATABASE_URL = "postgresql://${var.semantics_db_username}:${var.semantics_db_password}@${var.cloud_sql_ip}:5432/${var.semantics_db_name}"
  } : {}

  generated_redis_creds = local.self_service ? var.redis_credentials : {}
  generated_neo4j_creds = local.self_service ? var.neo4j_credentials : {}

  # GCP-specific — no native GCS storage code path in the app (only
  # USE_MINIO/MINIO_* or AWS_ACCESS_KEY_ID+EKAI_BUCKET exist), so self-service
  # always uses the in-cluster MinIO the platform submodule already deploys.
  generated_minio_creds = local.self_service ? {
    USE_MINIO               = "true"
    MINIO_ENDPOINT_URL      = var.minio_endpoint
    MINIO_ACCESS_KEY        = var.minio_root_user
    MINIO_SECRET_ACCESS_KEY = var.minio_root_password
    EKAI_BUCKET             = var.minio_default_buckets[0]
  } : {}

  # Not one of the app's documented keys — the client's own convenience, so
  # they can find their generated ArgoCD login the same place as everything
  # else instead of running a separate `terraform output` on the platform
  # submodule. ArgoCD's admin username is always literally "admin".
  generated_argocd_creds = local.self_service ? {
    ARGOCD_USERNAME = "admin"
    ARGOCD_PASSWORD = local.argocd_admin_password
  } : {}

  # AI_CORE_*/SEMANTICS_API_BASE are called by the BACKEND pod itself,
  # server-to-server -- pointing these at the public Ingress hostname sends
  # the backend's own traffic out through the internet-facing LB and back in
  # (LB hairpin routing), same class of bug as the FRONTEND__ URLs below.
  # These are the in-cluster Service DNS names instead. Ports match the
  # chart's values.yaml containerPort defaults (backend:3000, semantics:8000,
  # profile:9002, erd.api:9002).
  #
  # FRONTEND_URL stays the real public URL (used for outbound things like
  # email links, not API calls).
  #
  # FRONTEND__*_URL (except GITHUB_SYNC_APP_URL, see client_provided_
  # placeholders below) are read by the *browser-side* JS bundle, and the
  # frontend's nginx image bakes in a strict `connect-src 'self'` CSP plus
  # its own internal reverse-proxy (/api/, /api/ai_core_ms/, etc. -> the same
  # backend/erd/semantics/profile K8s Services). Absolute cross-subdomain
  # URLs here get silently blocked client-side by CSP -- must be relative
  # paths so the browser stays same-origin and nginx does the actual
  # cross-service hop.
  generated_service_urls = local.self_service ? {
    FRONTEND_URL                        = "https://portal.${var.dns_zone}"
    AI_CORE_ENDPOINT                    = "http://ekai-erd:9002"
    AI_CORE_PROFILER_ENDPOINT           = "http://ekai-profile:9002"
    AI_CORE_SEMANTICS_ENDPOINT          = "http://ekai-semantics:8000"
    SEMANTICS_API_BASE                  = "http://ekai-semantics:8000"
    FRONTEND__BACKEND_URL               = "/api/"
    FRONTEND__AI_CORE_URL               = "/api/ai_core_ms/"
    FRONTEND__AI_CORE_SEMANTICS_URL     = "/api/ai_core_semantics/"
    FRONTEND__AI_CORE_PROFILER_ENDPOINT = "/api/ai_core_profiler/"
  } : {}

  # Freshly generated per-install, independent values — never reused across
  # environments. ENCRYPTION_KEY/PLATFORM__FERNET_KEY get a "=" appended:
  # random_id's b64_url for byte_length=32 is unpadded base64 (43 chars) --
  # both Python's cryptography and the Fernet spec itself require the padded
  # 44-char form ("Fernet key must be 32 url-safe base64-encoded bytes"), and
  # both keys are fed straight into Fernet (ai-core's crypto.py, backend's
  # encryption-fernet.ts). 32 bytes always needs exactly one padding
  # character. PLATFORM__JWT_SECRET has no such format requirement.
  generated_crypto_keys = local.self_service ? {
    ENCRYPTION_KEY       = "${random_id.encryption_key[0].b64_url}="
    PLATFORM__JWT_SECRET = random_id.jwt_secret[0].b64_url
    PLATFORM__FERNET_KEY = "${random_id.fernet_key[0].b64_url}="
  } : {}

  # Safe, non-secret, working defaults — same for every install. The client
  # never needs to touch these.
  safe_defaults = local.self_service ? {
    DECRYPTED_EKAI_TOKEN        = "EKAI@8008"
    VECTOR_EMBEDDING_MODEL      = var.vector_embedding_model
    VECTOR_EMBEDDING_BATCH_SIZE = tostring(var.vector_embedding_batch_size)
    CLAUDE_MODEL                = var.claude_model
    NODE_ENV                    = "production"
    ENVIRONMENT                 = "production"
    PORT                        = "3000"
    PLATFORM__PORT              = "3000"
    CONFIG_ROOT                 = "/app/config"
    PLATFORM__APPLICATION_NAME  = "ekai"
    PLATFORM__DISABLE_SAME_SITE = "false"
    AI_CORE__BASE_PATH          = "/app/workspaces"
    AI_CORE__REDIS_DB           = "0"
    AI_CORE__REDIS_BUFFER_TIME  = "60"
    LOGS_GROUP_NAME             = "ekai/${var.env}"

    SEMANTICS__LOGS_GROUP_NAME              = "ekai/${var.env}/semantics"
    SEMANTICS__API_KEY_ENABLED              = "false"
    SEMANTICS__API_V1_PREFIX                = "/api/v1"
    SEMANTICS__BASE_PATH                    = "/app/workspaces"
    SEMANTICS__DEPLOYMENT_TYPE              = "EKAI"
    SEMANTICS__CLAUDE_MAX_TOKENS            = "32000"
    SEMANTICS__CLAUDE_TEMPERATURE           = "0.0"
    SEMANTICS__VERTEX_SONNET_MODEL          = "claude-sonnet-4-6@default"
    SEMANTICS__CONFIDENCE_THRESHOLD         = "0.6"
    SEMANTICS__DB_POOL_SIZE                 = "5"
    SEMANTICS__DB_MAX_OVERFLOW              = "10"
    SEMANTICS__REDIS_DB                     = "0"
    SEMANTICS__REDIS_MAX_CONNECTIONS        = "100"
    SEMANTICS__REDIS_RETRY_ON_TIMEOUT       = "true"
    SEMANTICS__REDIS_SOCKET_CONNECT_TIMEOUT = "5"
    SEMANTICS__REDIS_SOCKET_KEEPALIVE       = "true"
    SEMANTICS__PAGINATION_DEFAULT_LIMIT     = "20"
    SEMANTICS__PAGINATION_MAX_LIMIT         = "100"
    SEMANTICS__MAX_FILE_SIZE_MB             = "50"
    SEMANTICS__DOCUMENT_CHUNK_SIZE          = "15000"
    SEMANTICS__EXTRACTION_MAX_RETRIES       = "2"
    SEMANTICS__UPLOAD_DIR                   = "/app/uploads"
    SEMANTICS__GCS_DOCAI_LOCATION           = "us"
  } : {}

  # Only the client can provide these — real external accounts/keys Terraform
  # has no way to know. Blank string for genuinely optional features
  # (GitHub sync, Langfuse tracing); "REPLACE_ME" for ones the app needs to
  # actually function.
  client_provided_placeholders = local.self_service ? {
    ANTHROPIC_API_KEY    = "REPLACE_ME"
    OPENAI_API_KEY       = "REPLACE_ME"
    COGNITO_REGION       = "REPLACE_ME"
    COGNITO_USER_POOL_ID = "REPLACE_ME"
    COGNITO_CLIENT_ID    = "REPLACE_ME"

    PLATFORM__EKAI_GITHUB_APP_ID          = ""
    PLATFORM__EKAI_GITHUB_APP_PRIVATE_KEY = ""
    # Not a backend call -- the public github.com/apps/.../installations/new
    # install link, only needed if testing the GitHub sync flow.
    FRONTEND__GITHUB_SYNC_APP_URL = ""

    LANGFUSE_HOST       = ""
    LANGFUSE_PUBLIC_KEY = ""
    LANGFUSE_SECRET_KEY = ""

    # Signup invite emails go through AWS SES regardless of which cloud
    # hosts the cluster (no GCP-native equivalent in the app) -- same
    # category as SEMANTICS__GCS_* below being hardcoded to GCP Document AI
    # regardless of cluster cloud. Since self-service always uses in-cluster
    # MinIO for file storage (not S3), this AWS IAM user only needs SES send
    # access, not S3 -- a smaller ask than AWS's own self-service, which
    # reuses the same credential for both.
    AWS_ACCESS_KEY_ID     = "REPLACE_ME"
    AWS_SECRET_ACCESS_KEY = "REPLACE_ME"
    SES_AWS_REGION        = "REPLACE_ME"
    AWS_SES_FROM_EMAIL    = "REPLACE_ME"

    SEMANTICS__API_KEY                = ""
    SEMANTICS__GOOGLE_CLOUD_PROJECT   = "REPLACE_ME"
    SEMANTICS__GCS_DOCAI_PROCESSOR_ID = "REPLACE_ME"
    SEMANTICS__GCS_INPUT_BUCKET       = "REPLACE_ME"
    SEMANTICS__GCS_OUTPUT_BUCKET      = "REPLACE_ME"
  } : {}
}

resource "google_secret_manager_secret" "app_secret" {
  count     = local.self_service ? 1 : 0
  project   = var.project_id
  secret_id = "ekai-${var.env}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "app_secret" {
  count  = local.self_service ? 1 : 0
  secret = google_secret_manager_secret.app_secret[0].id

  # secret_value_overrides is merged LAST, so it wins on any key conflict —
  # the one place left to override a value with no dedicated variable
  # without editing this file.
  secret_data = jsonencode(merge(
    local.client_provided_placeholders,
    local.safe_defaults,
    local.generated_service_urls,
    local.generated_crypto_keys,
    local.generated_db_urls,
    local.generated_redis_creds,
    local.generated_neo4j_creds,
    local.generated_minio_creds,
    local.generated_argocd_creds,
    var.secret_value_overrides,
  ))

  lifecycle {
    ignore_changes = [secret_data]
    precondition {
      # The platform submodule's enable_redis_stack/enable_neo4j/enable_minio
      # default to false and aren't forced true for cicd_provider = "none" —
      # a self-service tfvars that forgets any of them would otherwise ship an
      # app secret silently missing REDIS_*/NEO4J_*/MINIO_* keys entirely,
      # only surfacing as a pod crash much later.
      condition     = length(local.generated_redis_creds) > 0 && length(local.generated_neo4j_creds) > 0 && length(local.generated_minio_creds) > 0
      error_message = "cicd_provider = \"none\" requires the platform submodule's enable_redis_stack = true, enable_neo4j = true, and enable_minio = true — the ekai-saas chart's ERD/KEDA/file-storage needs all three, and this secret would otherwise be missing REDIS_*/NEO4J_*/MINIO_* keys entirely."
    }
    precondition {
      # Both flow into self_service_helm_values (imageRegistry/the chart
      # repo ArgoCD pulls from) — blank here means a chart the client can
      # never actually pull, failing confusingly inside ArgoCD instead of
      # at plan time.
      condition     = var.existing_image_registry_base_url != "" && var.helm_chart_repo_url != ""
      error_message = "cicd_provider = \"none\" requires existing_image_registry_base_url and helm_chart_repo_url to both be set."
    }
  }
}

# Every field from the ekai-saas chart's example-values.yaml, sourced from
# what this Terraform layer already knows — nothing left for the chart's own
# (non-functional) blank defaults to fill in.
locals {
  self_service_helm_values = local.self_service ? yamlencode({
    namespace          = var.ekai_namespace
    dnsZone            = var.dns_zone
    imageRegistry      = var.existing_image_registry_base_url
    imageTag           = var.image_tag
    secretName         = "ekai-${var.env}"
    serviceAccountName = "ekai-app-sa"
    erd = {
      workspace = {
        storageClassName = var.erd_storage_class
      }
    }
    ingress = {
      className = var.ingress_class_name
      annotations = {
        "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      }
      tls = {
        enabled    = true
        secretName = var.tls_secret_name
      }
    }
  }) : ""
}

# ── ArgoCD application — git (Ekai-internal envs) or Helm chart (self-service)
module "ekai_CD" {
  source = "../ekai_CD"

  env             = var.env
  ekai_namespace  = var.ekai_namespace
  source_type     = local.self_service ? "helm" : "git"
  CD_branch       = var.cd_branch
  manifest_folder = var.manifest_folder
  github_org      = var.github_org
  github_username = local.github_username
  github_token    = local.github_token

  # source_type = "helm" only
  helm_repo_url      = var.helm_chart_repo_url
  helm_chart_version = var.helm_chart_version
  helm_values        = local.self_service_helm_values

  depends_on = [
    module.cloud_build,
    module.github_actions_cicd,
    data.kubernetes_namespace.ekai_saas,
    kubectl_manifest.external_secret,
    google_secret_manager_secret_version.app_secret,
  ]
}

# ── ExternalSecret CRD — ONE shared secret ekai-{env} for all services ────────
# All pods reference the same K8s Secret (ekai-{env}) via envFrom. Same
# secret name and shape for every cicd_provider value — self_service just
# changes who/what populates the underlying Secret Manager secret (Terraform
# above, vs. the client manually for cloud_build/github_actions).
resource "kubectl_manifest" "external_secret" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "ekai-${var.env}"
      namespace = var.ekai_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        # formerly `data.terraform_remote_state.platform.outputs.cluster_secret_store_name`
        name = var.cluster_secret_store_name
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "ekai-${var.env}"
        creationPolicy = "Owner"
      }
      dataFrom = [{
        extract = {
          key = "ekai-${var.env}"
        }
      }]
    }
  })

  depends_on = [module.cloud_build, module.github_actions_cicd, data.kubernetes_namespace.ekai_saas]
}

# ── Cloud DNS A records — one per pipeline that has an ingresshost ────────────
# for_each is based on var.pipelines (static variable) — always known at plan
# time, no "Invalid count/for_each argument" errors regardless of cluster state.
# nginx_ingress_ip comes from the combined root state (see ../../cicd/main.tf)
# and is stable once the nginx LoadBalancer Service has its external IP assigned.
resource "google_dns_record_set" "services" {
  for_each = {
    for k, v in var.pipelines : k => v.ingresshost
    if v.ingresshost != ""
  }

  project      = var.project_id
  managed_zone = var.dns_zone_name
  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  rrdatas      = [local.nginx_ingress_ip]

  depends_on = [module.ekai_CD]
}

# cicd_provider = "none" only — the block above is driven by var.pipelines,
# which self-service never populates (there's no CI pipeline to describe),
# so without this, every hostname generated_service_urls/self_service_helm_values
# already bakes into the app secret and chart Ingress (portal/backend/erd/
# semantics/profile.<dns_zone>) would be NXDOMAIN after a successful apply —
# nothing else in this stack creates these records.
resource "google_dns_record_set" "self_service_services" {
  for_each = local.self_service ? toset(["portal", "backend", "erd", "semantics", "profile"]) : toset([])

  project      = var.project_id
  managed_zone = var.dns_zone_name
  name         = "${each.value}.${var.dns_zone}."
  type         = "A"
  ttl          = 300
  rrdatas      = [local.nginx_ingress_ip]

  depends_on = [module.ekai_CD]
}
