# El secreto se declara aquí, pero su VALOR (el PAT de GitHub) se agrega a mano con gcloud:
# un secreto escrito en Terraform quedaría en texto plano en el state.
resource "google_secret_manager_secret" "github_token" {
  secret_id = "dataform-github-token"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_dataform_repository" "sellout" {
  name            = "sellout-dataform"
  region          = var.region
  service_account = google_service_account.sa["sa-dataform"].email # strict act-as: SA propia obligatoria

  git_remote_settings {
    url                                 = "https://github.com/${var.github_repo}.git"
    default_branch                      = "main"
    authentication_token_secret_version = "${google_secret_manager_secret.github_token.id}/versions/latest"
  }
}

locals {
  dataform_agent = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

# El agente de servicio de Dataform lee el token y "se pone" la SA sa-dataform para ejecutar.
resource "google_secret_manager_secret_iam_member" "dataform_agent_token" {
  secret_id = google_secret_manager_secret.github_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.dataform_agent
}

resource "google_service_account_iam_member" "dataform_agent_token_creator" {
  service_account_id = google_service_account.sa["sa-dataform"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.dataform_agent
}
