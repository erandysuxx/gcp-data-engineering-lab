resource "google_bigquery_dataset" "ds" {
  for_each    = local.datasets
  dataset_id  = each.key
  location    = var.region
  description = each.value

  # Lab: permite destruir el dataset aunque tenga tablas. En producción: false.
  delete_contents_on_destroy = true

  # sandbox: las tablas desaparecen solas a los 7 días (no te olvides de borrarlas = no pagas)
  default_table_expiration_ms = each.key == "sandbox" ? 7 * 24 * 3600 * 1000 : null

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_table" "raw" {
  for_each   = local.raw_tables
  dataset_id = google_bigquery_dataset.ds[each.value.dataset].dataset_id
  table_id   = each.key
  schema     = file("${path.module}/../schemas/${each.key}.json")

  time_partitioning {
    type  = "DAY"
    field = each.value.partition
  }
  clustering          = each.value.cluster
  deletion_protection = false # lab. En producción: true (un cambio de partición REEMPLAZA la tabla = borra datos)
}
