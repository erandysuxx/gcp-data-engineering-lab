resource "google_artifact_registry_repository" "images" {
  repository_id = "lab-images"
  location      = var.region
  format        = "DOCKER"
  description   = "Imágenes del generador y del Flex Template"

  cleanup_policies { # no acumular imágenes viejas (el storage de AR se cobra)
    id     = "keep-last-5"
    action = "KEEP"
    most_recent_versions { keep_count = 5 }
  }
  depends_on = [google_project_service.apis]
}
