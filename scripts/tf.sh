#!/usr/bin/env bash
# Terraform por Docker (no hace falta instalarlo). Monta el repo y tus credenciales de gcloud en solo lectura.
# Uso:  scripts/tf.sh init -backend-config="bucket=${TFSTATE_BUCKET}"
#       scripts/tf.sh plan -var-file=lab.tfvars
set -euo pipefail
TF_VERSION=1.17.1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GCLOUD_DIR="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"
ADC="${GOOGLE_APPLICATION_CREDENTIALS:-$GCLOUD_DIR/application_default_credentials.json}"
DOCKER_ARGS=(--rm -i -v "$ROOT:/repo" -w /repo/infra/terraform -e TF_IN_AUTOMATION=1)
if [ -f "$ADC" ]; then
  DOCKER_ARGS+=(-v "$ADC:/adc.json:ro" -e GOOGLE_APPLICATION_CREDENTIALS=/adc.json)
fi
[ -t 0 ] && DOCKER_ARGS+=(-t)
exec docker run "${DOCKER_ARGS[@]}" "hashicorp/terraform:${TF_VERSION}" "$@"
