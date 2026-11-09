#!/usr/bin/env bash
# Limpieza del laboratorio.
#   scripts/teardown.sh composer   → borra SOLO el entorno de Composer y su bucket (lo que más cobra)
#   scripts/teardown.sh project    → borra el PROYECTO completo (todo deja de cobrar; recuperable 30 días)
set -euo pipefail
: "${PROJECT_ID:?source .env.lab}" "${REGION:?}"
case "${1:-}" in
  composer)
    for ENV in $(gcloud composer environments list --locations "$REGION" --format="value(name.basename())"); do
      BUCKET=$(gcloud composer environments describe "$ENV" --location "$REGION" --format="value(config.dagGcsPrefix)" | cut -d/ -f3)
      echo "Borrando Composer $ENV y gs://$BUCKET"
      gcloud composer environments delete "$ENV" --location "$REGION" --quiet
      [ -n "$BUCKET" ] && gcloud storage rm -r "gs://$BUCKET" || true
    done
    ;;
  project)
    echo "Vas a BORRAR el proyecto $PROJECT_ID y todo lo que contiene."
    read -r -p "Escribe el ID del proyecto para confirmar: " CONFIRM
    [ "$CONFIRM" = "$PROJECT_ID" ] || { echo "No coincide. Nada se borró."; exit 1; }
    gcloud projects delete "$PROJECT_ID" --quiet
    echo "Listo. Pendientes fuera de GCP: borra tu PAT de GitHub y las variables del repo (gh variable list)."
    ;;
  *)
    echo "Uso: scripts/teardown.sh composer|project"; exit 1;;
esac
