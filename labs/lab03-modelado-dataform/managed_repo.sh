#!/usr/bin/env bash
# Repositorio de Dataform GESTIONADO, conectado a tu GitHub. Lo usará Airflow en el lab06.
# Requiere: tu copia del repo en GitHub con este código en main, y un fine-grained PAT (ver README).
set -euo pipefail
: "${PROJECT_ID:?source .env.lab}" "${GITHUB_REPO:?}" "${SA_DATAFORM:?}"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
AGENT="service-${PROJECT_NUMBER}@gcp-sa-dataform.iam.gserviceaccount.com"

echo "== 1/5 Service account sa-dataform (strict act-as: Dataform ya no ejecuta con su agente por defecto)"
if ! gcloud iam service-accounts describe "$SA_DATAFORM" >/dev/null 2>&1; then
  gcloud iam service-accounts create sa-dataform --display-name="Ejecuta los workflows de Dataform (strict act-as)"
  echo "   (esperando 30 s a que la SA nueva se propague en IAM; si no, los bindings fallan con 'does not exist')"
  sleep 30
fi
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$SA_DATAFORM" \
  --role=roles/bigquery.jobUser --condition=None --quiet >/dev/null

echo "== 2/5 Permisos por dataset con SQL (DCL): leer raw, escribir staging/marts/assertions"
bq query --nouse_legacy_sql --location="$REGION" "
GRANT \`roles/bigquery.dataViewer\` ON SCHEMA raw_olist   TO 'serviceAccount:$SA_DATAFORM';
GRANT \`roles/bigquery.dataViewer\` ON SCHEMA raw_sellout TO 'serviceAccount:$SA_DATAFORM';
GRANT \`roles/bigquery.dataEditor\` ON SCHEMA staging     TO 'serviceAccount:$SA_DATAFORM';
GRANT \`roles/bigquery.dataEditor\` ON SCHEMA marts       TO 'serviceAccount:$SA_DATAFORM';
GRANT \`roles/bigquery.dataEditor\` ON SCHEMA dataform_assertions TO 'serviceAccount:$SA_DATAFORM';"

echo "== 3/5 Secreto con el token de GitHub (el valor NUNCA va a un archivo ni a Terraform)"
gcloud secrets describe dataform-github-token >/dev/null 2>&1 || \
  gcloud secrets create dataform-github-token --replication-policy=automatic
read -r -s -p "Pega tu fine-grained PAT de GitHub (no se muestra): " PAT; echo
printf '%s' "$PAT" | gcloud secrets versions add dataform-github-token --data-file=- >/dev/null; unset PAT

echo "== 4/5 Agente de servicio de Dataform: leer el secreto y actuar como sa-dataform"
gcloud beta services identity create --service=dataform.googleapis.com --project="$PROJECT_ID" >/dev/null 2>&1 || true
gcloud secrets add-iam-policy-binding dataform-github-token \
  --member="serviceAccount:$AGENT" --role=roles/secretmanager.secretAccessor >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$SA_DATAFORM" \
  --member="serviceAccount:$AGENT" --role=roles/iam.serviceAccountTokenCreator >/dev/null

echo "== 5/5 Crear el repositorio (API REST de Dataform)"
API="https://dataform.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION/repositories"
curl -sf -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "Content-Type: application/json" \
  "$API?repositoryId=sellout-dataform" -d @- <<JSON || echo "(si dice ALREADY_EXISTS, ya estaba creado)"
{
  "serviceAccount": "$SA_DATAFORM",
  "gitRemoteSettings": {
    "url": "https://github.com/$GITHUB_REPO.git",
    "defaultBranch": "main",
    "authenticationTokenSecretVersion": "projects/$PROJECT_ID/secrets/dataform-github-token/versions/latest"
  }
}
JSON
echo; echo "Repositorio: $API/sellout-dataform"
