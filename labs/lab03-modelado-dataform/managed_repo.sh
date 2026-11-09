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
# Si el secreto ya tiene una versión activa, no se vuelve a pedir el token (re-correr el script es seguro).
# Para rotarlo: ROTATE_TOKEN=1 labs/lab03-modelado-dataform/managed_repo.sh
if [ -n "${ROTATE_TOKEN:-}" ] || [ -z "$(gcloud secrets versions list dataform-github-token --filter='state=ENABLED' --limit=1 --format='value(name)')" ]; then
  read -r -s -p "Pega tu fine-grained PAT de GitHub (no se muestra): " PAT; echo
  printf '%s' "$PAT" | gcloud secrets versions add dataform-github-token --data-file=- >/dev/null; unset PAT
else
  echo "   (el secreto ya tiene una versión activa: no se pide el token)"
fi

echo "== 4/5 Agente de servicio de Dataform: leer el secreto y actuar como sa-dataform"
# El agente de servicio no existe hasta que algo lo crea. Se genera con la API de Service Usage
# (equivale a `gcloud beta services identity create`, sin depender del componente beta).
curl -sf -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "x-goog-user-project: $PROJECT_ID" \
  "https://serviceusage.googleapis.com/v1beta1/projects/$PROJECT_ID/services/dataform.googleapis.com:generateServiceIdentity" >/dev/null
sleep 10   # propagación del agente recién creado
gcloud secrets add-iam-policy-binding dataform-github-token \
  --member="serviceAccount:$AGENT" --role=roles/secretmanager.secretAccessor >/dev/null
# Strict act-as exige DOS roles del agente sobre sa-dataform: Token Creator (crear credenciales de corta
# duración) y Service Account User (actAs). El error de la invocación solo menciona el primero.
for ROLE in roles/iam.serviceAccountTokenCreator roles/iam.serviceAccountUser; do
  gcloud iam service-accounts add-iam-policy-binding "$SA_DATAFORM" \
    --member="serviceAccount:$AGENT" --role="$ROLE" >/dev/null
done

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
echo "Espera 2–3 minutos antes de invocarlo: los permisos de IAM recién dados tardan en propagarse."
echo "Si la invocación falla con 'does not have permission to generate tokens', solo espera y reintenta."
