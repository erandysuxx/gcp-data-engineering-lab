data "google_project" "this" {}

resource "google_service_account" "sa" {
  for_each     = local.service_accounts
  account_id   = each.key
  display_name = each.value
}

locals {
  sa = { for k, v in google_service_account.sa : k => "serviceAccount:${v.email}" }

  # Roles a nivel PROYECTO (lo mínimo; lo demás va por recurso, más abajo)
  project_roles = {
    "sa-dataflow-worker"    = { member = local.sa["sa-dataflow"], role = "roles/dataflow.worker" }
    "sa-dataflow-jobuser"   = { member = local.sa["sa-dataflow"], role = "roles/bigquery.jobUser" }
    "sa-dataform-jobuser"   = { member = local.sa["sa-dataform"], role = "roles/bigquery.jobUser" }
    "sa-composer-worker"    = { member = local.sa["sa-composer"], role = "roles/composer.worker" }
    "sa-composer-dataflow"  = { member = local.sa["sa-composer"], role = "roles/dataflow.developer" }
    "sa-composer-run"       = { member = local.sa["sa-composer"], role = "roles/run.developer" }
    "sa-composer-dataform"  = { member = local.sa["sa-composer"], role = "roles/dataform.editor" }
    "sa-composer-jobuser"   = { member = local.sa["sa-composer"], role = "roles/bigquery.jobUser" }
    "sa-generator-logwrite" = { member = local.sa["sa-generator"], role = "roles/logging.logWriter" }
  }

  # Roles por DATASET
  dataset_roles = {
    "dataflow-raw_sellout" = { ds = "raw_sellout", member = local.sa["sa-dataflow"], role = "roles/bigquery.dataEditor" }
    "dataform-raw_olist"   = { ds = "raw_olist", member = local.sa["sa-dataform"], role = "roles/bigquery.dataViewer" }
    "dataform-raw_sellout" = { ds = "raw_sellout", member = local.sa["sa-dataform"], role = "roles/bigquery.dataViewer" }
    "dataform-staging"     = { ds = "staging", member = local.sa["sa-dataform"], role = "roles/bigquery.dataEditor" }
    "dataform-marts"       = { ds = "marts", member = local.sa["sa-dataform"], role = "roles/bigquery.dataEditor" }
    "dataform-assertions"  = { ds = "dataform_assertions", member = local.sa["sa-dataform"], role = "roles/bigquery.dataEditor" }
    "composer-raw_sellout" = { ds = "raw_sellout", member = local.sa["sa-composer"], role = "roles/bigquery.dataEditor" }
    "composer-ops"         = { ds = "ops", member = local.sa["sa-composer"], role = "roles/bigquery.dataEditor" }
  }

  # Roles por BUCKET
  bucket_roles = {
    "generator-landing" = { bucket = local.landing_bucket, member = local.sa["sa-generator"], role = "roles/storage.objectAdmin" }
    "dataflow-landing"  = { bucket = local.landing_bucket, member = local.sa["sa-dataflow"], role = "roles/storage.objectViewer" }
    "dataflow-temp"     = { bucket = local.temp_bucket, member = local.sa["sa-dataflow"], role = "roles/storage.objectAdmin" }
    "composer-landing"  = { bucket = local.landing_bucket, member = local.sa["sa-composer"], role = "roles/storage.objectViewer" }
    "composer-archive"  = { bucket = local.archive_bucket, member = local.sa["sa-composer"], role = "roles/storage.objectAdmin" }
    "composer-temp"     = { bucket = local.temp_bucket, member = local.sa["sa-composer"], role = "roles/storage.objectViewer" }
  }

  # actAs: Composer lanza jobs que corren COMO otras SAs → necesita serviceAccountUser sobre ellas
  act_as = ["sa-dataflow", "sa-dataform", "sa-generator"]
}

resource "google_project_iam_member" "project" {
  for_each = local.project_roles
  project  = var.project_id
  role     = each.value.role
  member   = each.value.member
}

resource "google_bigquery_dataset_iam_member" "ds" {
  for_each   = local.dataset_roles
  dataset_id = google_bigquery_dataset.ds[each.value.ds].dataset_id
  role       = each.value.role
  member     = each.value.member
}

resource "google_storage_bucket_iam_member" "bucket" {
  for_each   = local.bucket_roles
  bucket     = each.value.bucket
  role       = each.value.role
  member     = each.value.member
  depends_on = [google_storage_bucket.landing, google_storage_bucket.archive, google_storage_bucket.temp]
}

resource "google_service_account_iam_member" "composer_act_as" {
  for_each           = toset(local.act_as)
  service_account_id = google_service_account.sa[each.value].name
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa["sa-composer"]
}

resource "google_artifact_registry_repository_iam_member" "dataflow_pull" {
  location   = var.region
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = local.sa["sa-dataflow"]
}
