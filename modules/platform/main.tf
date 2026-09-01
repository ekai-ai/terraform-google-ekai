# ──────────────────────────────────────────────────────────────────────────────
# platform submodule (Helm releases + cluster-level infrastructure)
# Depends on the cluster submodule. Provisions everything that runs INSIDE GKE.
# Reads the cluster name from the cluster submodule (wired by the root module
# — see ../../main.tf — instead of a `data "terraform_remote_state" "cluster"`
# read against cluster's own state, since this is now one apply/one state).
#
# The original 03-platform/main.tf also declared a
# `data "terraform_remote_state" "bootstrap"` block here, but never actually
# referenced any of its outputs anywhere in this layer (verified by grep) —
# a genuinely dead read, dropped entirely rather than replaced with a
# passthrough variable nobody would ever wire.
# ──────────────────────────────────────────────────────────────────────────────

check "argocd_password_provided_when_not_self_service" {
  assert {
    condition     = var.cicd_provider == "none" || var.argocd_admin_password_hashed != ""
    error_message = "argocd_admin_password_hashed must be set when cicd_provider != \"none\" (self-service generates it directly instead)."
  }
}

locals {
  self_service = var.cicd_provider == "none"

  # self_service only — no master secret to read a hashed admin password
  # from, generate it directly instead. Read from terraform_data below, not
  # bcrypt() directly -- bcrypt() generates a fresh random salt on every
  # single call, so a plain local would produce a DIFFERENT hash on every
  # plan/apply even though the underlying password never changes, making
  # ArgoCD's admin secret look "modified" forever.
  argocd_admin_password_hashed = local.self_service ? terraform_data.argocd_admin_password_hashed[0].output : var.argocd_admin_password_hashed

  argocd_host = coalesce(var.argocd_ingress_host, "argocd.${var.dns_zone}")
  minio_host  = coalesce(var.minio_host, "minio.${var.dns_zone}")
}

resource "random_password" "argocd_admin" {
  count   = local.self_service ? 1 : 0
  length  = 24
  special = false
}

resource "terraform_data" "argocd_admin_password_hashed" {
  count = local.self_service ? 1 : 0
  input = bcrypt(random_password.argocd_admin[0].result, 10)

  lifecycle {
    ignore_changes = [input]
  }
}

# ── nginx Ingress Controller (public LoadBalancer) ────────────────────────────
# Creates a GCP L4 Network Load Balancer. Its external IP is the single entry
# point for all Ingress resources (ArgoCD, app services, etc.).
resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.nginx_ingress_chart_version
  namespace        = "ingress-nginx"
  create_namespace = true
  timeout          = 600
  cleanup_on_fail  = true

  values = [yamlencode({
    controller = {
      service = {
        type = "LoadBalancer"
        annotations = {
          # GCP: use a global external IP rather than an ephemeral one in prod.
          # Remove or change to "Regional" for dev environments.
          "cloud.google.com/load-balancer-type" = "External"
        }
      }
      # Publish the LB IP as .status.loadBalancer.ingress on each Ingress object
      # so kubectl and Terraform data sources can resolve it.
      publishService = {
        enabled = true
      }
    }
  })]
}

# ── Destroy-time guard — mirrors the AWS/Azure pattern ────────────────────────
# On destroy: all platform modules depend on this time_sleep, so Helm releases
# are removed first. time_sleep then waits 2 minutes (destroy_duration) giving
# the nginx LB time to drain and the GCP load balancer to be deleted before
# any cluster-level IAM resources are torn down.
# On apply: create_duration = 0s so there is no delay.
resource "time_sleep" "wait_for_alb_cleanup" {
  create_duration  = "0s"
  destroy_duration = "2m"
  depends_on       = [helm_release.nginx_ingress]
}

# ── App namespace — created early so ECR pull auth and ESO ExternalSecrets
# can reference it during this layer's apply.
resource "kubernetes_namespace" "ekai_saas" {
  metadata {
    name = "ekai-saas"
    labels = {
      name = "ekai-saas"
    }
  }
  depends_on = [time_sleep.wait_for_alb_cleanup]
}

# ── Shared app ServiceAccount — used by all ekai-saas pods ──────────────────
# All deployments reference ekai-app-sa. Creating it here ensures it exists
# before ArgoCD syncs the deployment manifests. Annotated for Workload
# Identity (GSA below) so pods can read the app secret without a key file.
resource "kubernetes_service_account" "ekai_app" {
  metadata {
    name      = "ekai-app-sa"
    namespace = kubernetes_namespace.ekai_saas.metadata[0].name
    labels = {
      app     = "ekai"
      managed = "terraform"
    }
    annotations = {
      "iam.gke.io/gcp-service-account" = "${var.env}-ekai-app-sa@${var.project_id}.iam.gserviceaccount.com"
    }
  }
  depends_on = [kubernetes_namespace.ekai_saas]
}

# ── Shared app GSA + Workload Identity ───────────────────────────────────────
# Every ekai-saas pod runs as ekai-app-sa (above) -- one shared GSA covers all
# of them, scoped to only the app's own secret (ekai-${env}), same
# conditional-IAM pattern as modules/app_workload_identity.
resource "google_service_account" "ekai_app" {
  project      = var.project_id
  account_id   = "${var.env}-ekai-app-sa"
  display_name = "ekai-saas app Workload Identity SA (${var.env})"
}

resource "google_project_iam_member" "ekai_app_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.ekai_app.email}"

  condition {
    title       = "${var.env}-ekai-app-secret-only"
    description = "Limit secret access to the ekai-${var.env} app secret."
    expression  = "resource.name.startsWith(\"projects/${var.project_id}/secrets/ekai-${var.env}\")"
  }
}

resource "google_project_iam_member" "ekai_app_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.ekai_app.email}"
}

resource "google_service_account_iam_member" "ekai_app_workload_identity" {
  service_account_id = google_service_account.ekai_app.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "serviceAccount:${var.project_id}.svc.id.goog[ekai-saas/ekai-app-sa]"
}

# ── External Secrets Operator (Workload Identity + Helm + ClusterSecretStore) ─
# GSA is bound to the ESO K8s SA via Workload Identity Federation.
# No service-account key is stored in the cluster.
module "eso" {
  source        = "../eso"
  project_id    = var.project_id
  region        = var.region
  env           = var.env
  cluster_name  = var.cluster_name
  chart_version = var.eso_chart_version

  depends_on = [time_sleep.wait_for_alb_cleanup]
}

# ── ArgoCD (Helm + nginx Ingress) ─────────────────────────────────────────────
# ArgoCD server runs in insecure mode; TLS is terminated at nginx using the
# wildcard cert provisioned by cert-manager (or a pre-existing K8s Secret).
module "argocd" {
  source = "../argocd"

  argocd_namespace             = var.argocd_namespace
  argocd_admin_password_hashed = local.argocd_admin_password_hashed
  argocd_ingress_host          = local.argocd_host
  tls_secret_name              = var.tls_secret_name

  depends_on = [time_sleep.wait_for_alb_cleanup, module.eso]
}

# ── KEDA (event-driven autoscaler) ────────────────────────────────────────────
# Always deployed — used to scale worker pods based on queue length.
# ScaledObjects in deployment-files are simply inactive until a scaler target
# (Redis, Pub/Sub, etc.) is available.
resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
  }
  depends_on = [time_sleep.wait_for_alb_cleanup]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.keda_chart_version
  namespace        = kubernetes_namespace.keda.metadata[0].name
  create_namespace = false
  timeout          = 600
  cleanup_on_fail  = true

  depends_on = [kubernetes_namespace.keda]
}

# ── Reloader — auto-restart pods when K8s Secrets change ─────────────────────
# Watches K8s Secrets/ConfigMaps and triggers rolling restarts on any pod that
# has the annotation: reloader.stakater.com/auto: "true"
# Required so ESO-synced Secret updates propagate to running pods automatically.
resource "helm_release" "reloader" {
  name             = "reloader"
  repository       = "https://stakater.github.io/stakater-charts"
  chart            = "reloader"
  version          = var.reloader_chart_version
  namespace        = "kube-system"
  create_namespace = false
  timeout          = 300
  cleanup_on_fail  = true

  values = [yamlencode({ reloader = { watchGlobally = true } })]

  depends_on = [time_sleep.wait_for_alb_cleanup]
}

# ── Reflector — copy TLS secrets across namespaces ───────────────────────────
# Copies cert-manager wildcard TLS secret to argocd, ekai-saas, minio, etc.
# Annotations on the source secret control which namespaces receive the copy.
resource "helm_release" "reflector" {
  name             = "reflector"
  repository       = "https://emberstack.github.io/helm-charts"
  chart            = "reflector"
  namespace        = "kube-system"
  create_namespace = false
  timeout          = 300
  cleanup_on_fail  = true

  depends_on = [time_sleep.wait_for_alb_cleanup]
}

# ── cert-manager (optional — GKE TLS certificate management) ─────────────────
# Manages TLS certificates via Let's Encrypt / GCP Certificate Authority Service.
# Disabled when TLS is handled externally (enable_cert_manager = false).
# When enabled, configure a ClusterIssuer (DNS01/HTTP01) in the cicd module or
# as a kubectl_manifest in this layer after cert-manager CRDs are installed.
resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  namespace        = "cert-manager"
  create_namespace = true
  timeout          = 600
  cleanup_on_fail  = true

  values = [yamlencode({
    installCRDs = true

    # Workload Identity annotation on the cert-manager controller SA so it can
    # use GCP DNS01 challenges without a key file. Annotate with the GSA email
    # of a SA that has roles/dns.admin on the Cloud DNS zone.
    serviceAccount = {
      annotations = {
        "iam.gke.io/gcp-service-account" = "${local.cert_manager_sa_id}@${var.project_id}.iam.gserviceaccount.com"
      }
    }
  })]

  depends_on = [time_sleep.wait_for_alb_cleanup]
}

# ── cert-manager GSA + Workload Identity (Bug 3 fix) ─────────────────────────
# The cert-manager pod needs DNS01 access to issue wildcard certs.
# This GSA is annotated on the cert-manager controller SA via the Helm values above.
locals {
  cert_manager_sa_id = var.cert_manager_sa_id != "" ? var.cert_manager_sa_id : "cert-manager-${var.env}"
}

resource "google_service_account" "cert_manager" {
  count        = var.enable_cert_manager ? 1 : 0
  project      = var.project_id
  account_id   = local.cert_manager_sa_id
  display_name = "cert-manager Workload Identity SA (${var.env})"
}

resource "google_project_iam_member" "cert_manager_dns_admin" {
  count   = var.enable_cert_manager ? 1 : 0
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager[0].email}"
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  count              = var.enable_cert_manager ? 1 : 0
  service_account_id = google_service_account.cert_manager[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
}

# ── ClusterIssuer (Let's Encrypt DNS-01 via Cloud DNS) ───────────────────────
resource "kubectl_manifest" "cluster_issuer" {
  count = var.enable_cert_manager ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-key"
        }
        solvers = [{
          dns01 = {
            cloudDNS = {
              project = var.project_id
              # hostedZoneName tells cert-manager exactly which Cloud DNS zone to use.
              # Without this, cert-manager walks up the domain hierarchy and looks for
              # the parent zone (ekai.ai) which is not in GCP, causing DNS-01 to fail.
              hostedZoneName = "${var.env}-zone"
            }
          }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# ── Wildcard Certificate for *.{env}.ekai.ai ─────────────────────────────────
# One certificate covers all subdomains. Namespaces that need it reference
# this secret name in their Ingress tls.secretName.
resource "kubectl_manifest" "wildcard_cert" {
  count = var.enable_cert_manager ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "${var.env}-wildcard-tls"
      namespace = "cert-manager"
      annotations = {
        # Reflector copies this secret to all listed namespaces automatically.
        "reflector.v1.k8s.emberstack.com/reflection-allowed"            = "true"
        "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "argocd,ekai-saas,minio,ingress-nginx"
        "reflector.v1.k8s.emberstack.com/reflection-auto-enabled"       = "true"
        "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces"    = "argocd,ekai-saas,minio,ingress-nginx"
      }
    }
    spec = {
      secretName = var.tls_secret_name
      # secretTemplate copies annotations to the Secret cert-manager creates.
      # Reflector watches the Secret (not the Certificate) for reflection annotations.
      # This eliminates the need for a separate kubernetes_annotations resource
      # that fails when the Secret doesn't exist yet.
      secretTemplate = {
        annotations = {
          "reflector.v1.k8s.emberstack.com/reflection-allowed"            = "true"
          "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = "argocd,ekai-saas,minio,ingress-nginx"
          "reflector.v1.k8s.emberstack.com/reflection-auto-enabled"       = "true"
          "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces"    = "argocd,ekai-saas,minio,ingress-nginx"
        }
      }
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [
        "*.${var.dns_zone}",
        var.dns_zone,
      ]
    }
  })

  depends_on = [kubectl_manifest.cluster_issuer, helm_release.reflector]
}

# ── ArgoCD DNS record (Bug 4 fix) ─────────────────────────────────────────────
# nginx_ingress data source is declared in outputs.tf (shared)
resource "google_dns_record_set" "argocd" {
  project      = var.project_id
  managed_zone = "${var.env}-zone"
  name         = "${local.argocd_host}."
  type         = "A"
  ttl          = 300
  rrdatas      = [data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].ip]
}

# ── MinIO DNS records (Bug 5 fix) ─────────────────────────────────────────────
resource "google_dns_record_set" "minio" {
  count        = var.enable_minio ? 1 : 0
  project      = var.project_id
  managed_zone = "${var.env}-zone"
  name         = "${local.minio_host}."
  type         = "A"
  ttl          = 300
  rrdatas      = [data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].ip]
}

# ── MinIO (optional in-cluster object storage) ───────────────────────────────
# Set enable_minio = true in tfvars to deploy. Outputs MINIO_* values that
# the cicd module merges into per-service infra secrets via ESO.
module "minio" {
  count  = var.enable_minio ? 1 : 0
  source = "../minio"

  minio_namespace  = var.minio_namespace
  minio_host       = local.minio_host
  tls_secret_name  = var.tls_secret_name
  default_buckets  = var.minio_default_buckets
  persistence_size = var.minio_persistence_size
  storage_class    = var.minio_storage_class
  mode             = var.minio_replicas >= 4 ? "distributed" : "standalone"
  replicas         = var.minio_replicas

  depends_on = [time_sleep.wait_for_alb_cleanup, module.eso]
}

# ── ECR pull auth (optional — GKE pulling from AWS ECR) ──────────────────────
# Enable with enable_ecr_pull_auth = true in tfvars.
# Creates:
#   1. K8s Opaque secret with long-lived AWS IAM credentials (from Secret Manager)
#   2. CronJob that runs every 6h: fetches fresh ECR token → creates/patches
#      docker-registry K8s secret "aws-ecr-pull-secret" in ecr_namespace
#   3. ServiceAccount + Role + RoleBinding for the CronJob
#
# Use case: demo or client envs where images live in AWS ECR (pre-built) instead
# of (or alongside) Artifact Registry. Reference in pod specs:
#   imagePullSecrets:
#     - name: aws-ecr-pull-secret
module "ecr_pull_auth" {
  count  = var.enable_ecr_pull_auth ? 1 : 0
  source = "../ecr_pull_auth"

  project_id                  = var.project_id
  namespace                   = var.ecr_namespace
  ecr_credentials_secret_name = var.ecr_credentials_secret_name
  aws_account_id              = var.aws_account_id
  aws_region                  = var.aws_ecr_region

  depends_on = [module.eso, kubernetes_namespace.ekai_saas]
}

# ── Redis (optional — Bitnami Redis Stack, self-contained module) ────────────
# Generates its own password (random_password inside the module) -- no master
# secret dependency, works identically for self_service and non-self_service.
module "redis" {
  count  = var.enable_redis_stack ? 1 : 0
  source = "../redis"

  redis_namespace  = var.redis_namespace
  persistence_size = var.redis_storage_size
  storage_class    = var.redis_storage_class

  depends_on = [time_sleep.wait_for_alb_cleanup]
}

# ── Neo4j (optional — community edition, single-node with PDB) ───────────────
module "neo4j" {
  count  = var.enable_neo4j ? 1 : 0
  source = "../neo4j"

  namespace      = var.neo4j_namespace
  storage_size   = var.neo4j_storage_size
  storage_class  = var.neo4j_storage_class
  memory_request = var.neo4j_memory_request
  memory_limit   = var.neo4j_memory_limit

  depends_on = [time_sleep.wait_for_alb_cleanup]
}
