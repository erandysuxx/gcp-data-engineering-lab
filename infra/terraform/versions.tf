terraform {
  required_version = "~> 1.17.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
  }
  # Estado remoto en GCS (versionado y con lock). El bucket lo crea infra/bootstrap/bootstrap.sh,
  # FUERA de este state: el state no puede guardarse en un bucket que él mismo administra.
  # Se configura al hacer init:  terraform init -backend-config="bucket=${TFSTATE_BUCKET}"
  backend "gcs" {
    prefix = "lab/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  default_labels = {
    managed-by = "terraform"
    lab        = "gcp-data-engineering"
  }
}
