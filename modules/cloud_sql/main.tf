# ---------------------------------------------------------------------------
# Module: cloud_sql
# Provisions a private Cloud SQL PostgreSQL instance with VPC peering,
# creates databases and users, and reads credentials from Secret Manager.
# ---------------------------------------------------------------------------

# Provider requirements are in versions.tf

# ---------------------------------------------------------------------------
# Local helpers
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.env}-cloudsql"
}

# ---------------------------------------------------------------------------
# Secret Manager – read the JSON blob that holds all DB passwords.
# Expected secret format (JSON):
#   {
#     "backend_db_password":   "...",
#     "semantics_db_password": "..."
#   }
# ---------------------------------------------------------------------------

# Skipped entirely for self_service, which generates its own credentials
# below instead of requiring a pre-existing secret.
data "google_secret_manager_secret_version" "db_credentials" {
  count   = var.self_service ? 0 : 1
  project = var.project_id
  secret  = var.secrets_name
}

# self_service only — no pre-existing secret to read DB credentials from.
resource "random_password" "backend_db" {
  count   = var.self_service ? 1 : 0
  length  = 24
  special = false
}

resource "random_password" "semantics_db" {
  count   = var.self_service ? 1 : 0
  length  = 24
  special = false
}

locals {
  credentials         = var.self_service ? {} : jsondecode(data.google_secret_manager_secret_version.db_credentials[0].secret_data)
  backend_user        = var.self_service ? "ekai_backend" : local.credentials["backend_db_username"]
  backend_password    = var.self_service ? random_password.backend_db[0].result : local.credentials["backend_db_password"]
  backend_db_name     = var.self_service ? "ekai_backend" : local.credentials["backend_db_name"]
  semantics_user      = var.self_service ? "ekai_semantics" : local.credentials["semantics_db_username"]
  semantics_password  = var.self_service ? random_password.semantics_db[0].result : local.credentials["semantics_db_password"]
  semantics_db_name   = var.self_service ? "ekai_semantics" : local.credentials["semantics_db_name"]
}

# ---------------------------------------------------------------------------
# VPC – look up the existing network
# ---------------------------------------------------------------------------

data "google_compute_network" "vpc" {
  project = var.project_id
  name    = var.vpc_name
}

# ---------------------------------------------------------------------------
# Private service connection – allocate a global address range for
# Google-managed services (Cloud SQL, Memorystore, etc.)
# ---------------------------------------------------------------------------

resource "google_compute_global_address" "private_service_range" {
  project       = var.project_id
  name          = "${local.name_prefix}-psc-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = data.google_compute_network.vpc.id
}

# ---------------------------------------------------------------------------
# VPC peering to Google's Service Networking API
# ---------------------------------------------------------------------------

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = data.google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
  # ABANDON: GCP holds the peering internally even after Cloud SQL is deleted.
  # Attempting DELETE causes "Producer services still using this connection".
  # ABANDON skips the API delete — GCP cleans it up asynchronously.
  deletion_policy = "ABANDON"
}

# ---------------------------------------------------------------------------
# Cloud SQL instance (PostgreSQL, private IP only)
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "postgres" {
  project             = var.project_id
  name                = "${local.name_prefix}-${var.db_version}"
  database_version    = "POSTGRES_${var.db_version}"
  region              = var.region
  deletion_protection = var.env == "prod" ? true : false

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier              = var.instance_tier
    availability_type = var.env == "prod" ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.env == "prod" ? true : false
      start_time                     = "03:00"
      transaction_log_retention_days = var.env == "prod" ? 7 : 1

      backup_retention_settings {
        retained_backups = var.env == "prod" ? 14 : 3
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 4
      update_track = "stable"
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }
  }

  # Cloud SQL deletion takes 5-15 minutes — wait long enough so the
  # service networking connection teardown doesn't race with it.
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ---------------------------------------------------------------------------
# Databases
# ---------------------------------------------------------------------------

resource "google_sql_database" "backend_db" {
  project   = var.project_id
  instance  = google_sql_database_instance.postgres.name
  name      = local.backend_db_name
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

resource "google_sql_database" "semantics_db" {
  project   = var.project_id
  instance  = google_sql_database_instance.postgres.name
  name      = local.semantics_db_name
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# ---------------------------------------------------------------------------
# Users — names and passwords read from Secret Manager
# ---------------------------------------------------------------------------

resource "google_sql_user" "backend_db_user" {
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = local.backend_user
  password = local.backend_password

  depends_on = [google_sql_database.backend_db]
}

resource "google_sql_user" "semantics_db_user" {
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = local.semantics_user
  password = local.semantics_password

  depends_on = [google_sql_database.semantics_db]
}
