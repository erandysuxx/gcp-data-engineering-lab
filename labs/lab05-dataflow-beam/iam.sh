#!/usr/bin/env bash
# Service account de los WORKERS de Dataflow con lo mínimo para este pipeline.
set -euo pipefail
: "${PROJECT_ID:?source .env.lab}"
if ! gcloud iam service-accounts describe "$SA_DATAFLOW" >/dev/null 2>&1; then
  gcloud iam service-accounts create sa-dataflow --display-name="Workers de Dataflow"
  echo "   (esperando 30 s a que la SA nueva se propague en IAM; si no, los bindings fallan con 'does not exist')"
  sleep 30
fi
for ROLE in roles/dataflow.worker roles/bigquery.jobUser; do   # a nivel proyecto (no hay forma más fina)
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$SA_DATAFLOW" \
    --role="$ROLE" --condition=None --quiet >/dev/null
done
gcloud storage buckets add-iam-policy-binding "gs://$LANDING_BUCKET" \
  --member="serviceAccount:$SA_DATAFLOW" --role=roles/storage.objectViewer >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://$TEMP_BUCKET" \
  --member="serviceAccount:$SA_DATAFLOW" --role=roles/storage.objectAdmin >/dev/null
gcloud artifacts repositories add-iam-policy-binding "$AR_REPO" --location="$REGION" \
  --member="serviceAccount:$SA_DATAFLOW" --role=roles/artifactregistry.reader >/dev/null
bq query --nouse_legacy_sql --location="$REGION" \
  "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA raw_sellout TO 'serviceAccount:$SA_DATAFLOW'"
# Tú (quien lanza el job) necesitas "actuar como" esa SA:
gcloud iam service-accounts add-iam-policy-binding "$SA_DATAFLOW" \
  --member="user:$LAB_ACCOUNT" --role=roles/iam.serviceAccountUser >/dev/null
echo "sa-dataflow lista"
