# Composer cobra 24/7 mientras existe, corra o no. Por eso va detrás de un flag que por defecto está apagado.
#   terraform apply -var enable_composer=true    → lo crea (~25 min)
#   terraform apply -var enable_composer=false   → lo borra
resource "google_composer_environment" "lab" {
  count  = var.enable_composer ? 1 : 0
  name   = "lab-composer"
  region = var.region

  config {
    environment_size = "ENVIRONMENT_SIZE_SMALL"

    software_config {
      image_version = var.composer_image_version
      env_variables = {
        LAB_PROJECT_ID     = var.project_id
        LAB_REGION         = var.region
        LAB_LANDING_BUCKET = local.landing_bucket
        LAB_ARCHIVE_BUCKET = local.archive_bucket
        LAB_TEMP_BUCKET    = local.temp_bucket
      }
    }

    node_config {
      service_account = google_service_account.sa["sa-composer"].email
    }

    workloads_config { # lo mínimo: dimensiona por tareas concurrentes, no "por si acaso"
      scheduler {
        cpu        = 0.5
        memory_gb  = 2
        storage_gb = 1
        count      = 1
      }
      triggerer {
        cpu       = 0.5
        memory_gb = 1
        count     = 1
      }
      dag_processor {
        cpu        = 0.5
        memory_gb  = 2
        storage_gb = 1
        count      = 1
      }
      web_server {
        cpu        = 0.5
        memory_gb  = 2
        storage_gb = 1
      }
      worker {
        cpu        = 0.5
        memory_gb  = 2
        storage_gb = 1
        min_count  = 1
        max_count  = 2
      }
    }
  }
  depends_on = [google_project_iam_member.project]
}
