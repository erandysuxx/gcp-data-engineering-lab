# Tres buckets con propósitos distintos = políticas distintas.
resource "google_storage_bucket" "landing" {
  name                        = local.landing_bucket
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # SOLO en un lab: permite borrar el bucket con objetos

  lifecycle_rule { # el feed ya se archivó: a los 14 días se borra (los CSV de Olist en olist/ se conservan)
    condition {
      age            = 14
      matches_prefix = ["sellout/", "masters/"]
    }
    action { type = "Delete" }
  }
}

resource "google_storage_bucket" "archive" {
  name                        = local.archive_bucket
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  lifecycle_rule { # se lee poco: a Nearline a los 30 días (ojo: Nearline cobra mínimo 30 días y por lectura)
    condition { age = 30 }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  lifecycle_rule {
    condition { age = 365 }
    action { type = "Delete" }
  }
}

resource "google_storage_bucket" "temp" {
  name                        = local.temp_bucket
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  soft_delete_policy { # temporales: sin soft delete (si no, pagas los borrados durante la retención)
    retention_duration_seconds = 0
  }
  lifecycle_rule { # los temporales de Dataflow se borran a los 3 días; el spec del Flex Template (templates/) no
    condition {
      age            = 3
      matches_prefix = ["dataflow/"]
    }
    action { type = "Delete" }
  }
}
