#!/usr/bin/env bash
# Capa de BOOTSTRAP del lab07: lo que Terraform necesita ANTES de poder correr desde GitHub Actions.
#   1. Bucket del state de Terraform (versionado).
#   2. Service account `sa-deployer` (la identidad con la que despliega CI).
#   3. Workload Identity Federation: GitHub Actions obtiene credenciales de corta duración SIN llaves JSON.
# Se corre UNA vez, a mano, con tu usuario. Uso:  source .env.lab && infra/bootstrap/bootstrap.sh
set -euo pipefail
: "${PROJECT_ID:?source .env.lab}" "${REGION:?}" "${TFSTATE_BUCKET:?}" "${GITHUB_REPO:?}"

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
POOL=github
PROVIDER=github-oidc
SA="sa-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

echo "== 1/4 Bucket del state: gs://${TFSTATE_BUCKET}"
gcloud storage buckets describe "gs://${TFSTATE_BUCKET}" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://${TFSTATE_BUCKET}" --location="$REGION" \
    --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://${TFSTATE_BUCKET}" --versioning   # recuperar un state corrupto

echo "== 2/4 Service account del deploy"
if ! gcloud iam service-accounts describe "$SA" >/dev/null 2>&1; then
  gcloud iam service-accounts create sa-deployer --display-name="GitHub Actions deployer"
  echo "   (esperando 30 s a que la SA nueva se propague en IAM; si no, los bindings fallan con 'does not exist')"
  sleep 30
fi
# Roles amplios porque Terraform crea SAs, IAM, buckets, datasets y Composer. En una empresa se separa:
# una SA de solo lectura para `plan` en los PR y otra con permisos de escritura solo para `main`.
for ROLE in roles/editor roles/resourcemanager.projectIamAdmin roles/iam.serviceAccountAdmin \
            roles/storage.admin roles/bigquery.admin roles/secretmanager.admin roles/artifactregistry.admin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:${SA}" --role="$ROLE" \
    --condition=None --quiet >/dev/null
done
gcloud storage buckets add-iam-policy-binding "gs://${TFSTATE_BUCKET}" \
  --member="serviceAccount:${SA}" --role=roles/storage.objectAdmin >/dev/null

echo "== 3/4 Workload Identity Federation (pool + provider OIDC de GitHub)"
# IDs NUMÉRICOS del repo y del dueño: un nombre (owner/repo) se puede liberar y reutilizar; un ID no.
REPO_ID=$(gh api "repos/${GITHUB_REPO}" --jq .id)
OWNER_ID=$(gh api "repos/${GITHUB_REPO}" --jq .owner.id)
gcloud iam workload-identity-pools describe "$POOL" --location=global >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools create "$POOL" --location=global --display-name="GitHub Actions"
gcloud iam workload-identity-pools providers describe "$PROVIDER" --location=global \
    --workload-identity-pool="$POOL" >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" --location=global \
    --workload-identity-pool="$POOL" --display-name="GitHub OIDC" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.repository_owner_id=assertion.repository_owner_id,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository_owner_id == '${OWNER_ID}' && assertion.repository_id == '${REPO_ID}'"
gcloud iam service-accounts add-iam-policy-binding "$SA" --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository_id/${REPO_ID}" \
  >/dev/null

WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"
echo "== 4/4 Variables del repo en GitHub (no son secretos: no dan acceso por sí solas)"
gh variable set GCP_PROJECT_ID  --repo "$GITHUB_REPO" --body "$PROJECT_ID"
gh variable set GCP_REGION      --repo "$GITHUB_REPO" --body "$REGION"
gh variable set TFSTATE_BUCKET  --repo "$GITHUB_REPO" --body "$TFSTATE_BUCKET"
gh variable set WIF_PROVIDER    --repo "$GITHUB_REPO" --body "$WIF_PROVIDER"
gh variable set DEPLOYER_SA     --repo "$GITHUB_REPO" --body "$SA"
gh variable set ENABLE_COMPOSER --repo "$GITHUB_REPO" --body "false"
echo "Listo. WIF_PROVIDER=${WIF_PROVIDER}"
