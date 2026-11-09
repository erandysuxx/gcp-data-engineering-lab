#!/usr/bin/env bash
# Service account de los workers de Composer: orquesta, así que necesita LANZAR cosas, no procesar datos.
set -euo pipefail
: "${PROJECT_ID:?source .env.lab}"
if ! gcloud iam service-accounts describe "$SA_COMPOSER" >/dev/null 2>&1; then
  gcloud iam service-accounts create sa-composer --display-name="Workers de Airflow (Composer)"
  echo "   (esperando 30 s a que la SA nueva se propague en IAM; si no, los bindings fallan con 'does not exist')"
  sleep 30
fi
for ROLE in roles/composer.worker roles/dataflow.developer roles/run.developer roles/dataform.editor roles/bigquery.jobUser; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$SA_COMPOSER" \
    --role="$ROLE" --condition=None --quiet >/dev/null
done
bq query --nouse_legacy_sql --location="$REGION" "
GRANT \`roles/bigquery.dataEditor\` ON SCHEMA raw_sellout TO 'serviceAccount:$SA_COMPOSER';
GRANT \`roles/bigquery.dataEditor\` ON SCHEMA ops         TO 'serviceAccount:$SA_COMPOSER';"
gcloud storage buckets add-iam-policy-binding "gs://$LANDING_BUCKET" --member="serviceAccount:$SA_COMPOSER" --role=roles/storage.objectViewer >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://$ARCHIVE_BUCKET" --member="serviceAccount:$SA_COMPOSER" --role=roles/storage.objectAdmin >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://$TEMP_BUCKET"    --member="serviceAccount:$SA_COMPOSER" --role=roles/storage.objectViewer >/dev/null
# actAs: Composer lanza jobs que corren COMO estas SAs
for SA in "$SA_DATAFLOW" "$SA_DATAFORM" "$SA_GENERATOR"; do
  gcloud iam service-accounts add-iam-policy-binding "$SA" --member="serviceAccount:$SA_COMPOSER" \
    --role=roles/iam.serviceAccountUser >/dev/null
done
echo "sa-composer lista"
