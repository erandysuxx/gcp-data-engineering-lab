variable "project_id" {
  description = "Proyecto de GCP del laboratorio"
  type        = string
}

variable "region" {
  description = "Región única para todos los recursos"
  type        = string
  default     = "us-central1"
}

variable "github_repo" {
  description = "Tu copia del repo, formato owner/nombre (Dataform clona de aquí)"
  type        = string
}

variable "enable_composer" {
  description = "Crea el entorno de Composer (cobra 24/7 mientras exista). Déjalo en false salvo en la sesión del lab06."
  type        = bool
  default     = false
}

variable "composer_image_version" {
  description = "Imagen de Composer 3 (ver VERSIONS.md)"
  type        = string
  default     = "composer-3-airflow-3.3.1-build.5"
}
