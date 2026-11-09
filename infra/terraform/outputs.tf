output "buckets" {
  value = {
    landing = google_storage_bucket.landing.url
    archive = google_storage_bucket.archive.url
    temp    = google_storage_bucket.temp.url
  }
}

output "service_accounts" {
  value = { for k, v in google_service_account.sa : k => v.email }
}

output "dataform_repository" {
  value = google_dataform_repository.sellout.id
}

output "composer_dag_bucket" {
  description = "Prefijo gs:// donde se suben los DAGs (vacío si Composer está apagado)"
  value       = var.enable_composer ? google_composer_environment.lab[0].config[0].dag_gcs_prefix : ""
}

output "composer_airflow_uri" {
  value = var.enable_composer ? google_composer_environment.lab[0].config[0].airflow_uri : ""
}
