#!/usr/bin/env bash
# Verifica que estás apuntando a TU proyecto de laboratorio antes de crear o borrar nada.
# Uso: source .env.lab && scripts/preflight.sh
set -uo pipefail
fail() { echo "  ✗ $1"; FAILED=1; }
ok()   { echo "  ✓ $1"; }
FAILED=0

echo "Preflight del laboratorio"
[ -n "${PROJECT_ID:-}" ] && [ "$PROJECT_ID" != "de-lab-CAMBIAME" ] || { echo "  ✗ Falta 'source .env.lab' (PROJECT_ID vacío)"; exit 1; }

ACTIVE=$(gcloud config get-value account 2>/dev/null)
if [ -n "${LAB_ACCOUNT:-}" ] && [ "$ACTIVE" != "$LAB_ACCOUNT" ]; then
  fail "gcloud usa '$ACTIVE' y el lab espera '$LAB_ACCOUNT'  →  gcloud config set account $LAB_ACCOUNT"
else ok "cuenta gcloud: $ACTIVE"; fi

CURP=$(gcloud config get-value project 2>/dev/null)
[ "$CURP" = "$PROJECT_ID" ] && ok "proyecto activo: $PROJECT_ID" || fail "proyecto activo '$CURP' != '$PROJECT_ID'  →  source .env.lab (exporta CLOUDSDK_CORE_PROJECT)"

if gcloud projects describe "$PROJECT_ID" --format="value(projectId)" >/dev/null 2>&1; then ok "el proyecto existe y tienes acceso"
else fail "no se puede leer el proyecto $PROJECT_ID"; fi

BILL=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null)
[ "$BILL" = "True" ] && ok "billing habilitado" || fail "billing NO habilitado en $PROJECT_ID (lab00, paso 3)"

ADC="${GOOGLE_APPLICATION_CREDENTIALS:-${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}/application_default_credentials.json}"
if [ -f "$ADC" ]; then
  QP=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('quota_project_id',''))" "$ADC" 2>/dev/null)
  ok "ADC presente ($ADC) quota_project='${QP}'"
  [ -n "$QP" ] && [ "$QP" != "$PROJECT_ID" ] && fail "el quota project del ADC es '$QP'  →  gcloud auth application-default set-quota-project $PROJECT_ID"
else fail "no hay ADC  →  gcloud auth application-default login"; fi

[ "${REGION:-}" = "us-central1" ] && ok "región: $REGION" || fail "REGION debe ser us-central1"

if [ $FAILED -eq 0 ]; then echo "Listo: puedes continuar."; else echo "Corrige lo marcado con ✗ antes de seguir."; exit 1; fi
