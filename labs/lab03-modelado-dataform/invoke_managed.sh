#!/usr/bin/env bash
# Compila la rama main en el repositorio gestionado y ejecuta los modelos con un tag. Es lo mismo
# que hará Airflow (operators Dataform*), pero con la API REST para que veas cada paso.
# Uso: labs/lab03-modelado-dataform/invoke_managed.sh olist 2026-11-03
set -euo pipefail
TAG="${1:-olist}"; RUN_DATE="${2:-2026-11-03}"
API="https://dataform.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION/repositories/sellout-dataform"
AUTH="Authorization: Bearer $(gcloud auth print-access-token)"
COMP=$(curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" "$API/compilationResults" \
  -d "{\"gitCommitish\": \"main\", \"codeCompilationConfig\": {\"vars\": {\"run_date\": \"$RUN_DATE\"}}}")
NAME=$(echo "$COMP" | python3 -c "import json,sys;d=json.load(sys.stdin);e=d.get('compilationErrors');print(d['name']);sys.exit(1 if e else 0)") \
  || { echo "Errores de compilación:"; echo "$COMP"; exit 1; }
echo "compilación: $NAME"
INV=$(curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" "$API/workflowInvocations" \
  -d "{\"compilationResult\": \"$NAME\", \"invocationConfig\": {\"includedTags\": [\"$TAG\"], \"serviceAccount\": \"$SA_DATAFORM\"}}")
INV_NAME=$(echo "$INV" | python3 -c "import json,sys;print(json.load(sys.stdin)['name'])")
echo "invocación: $INV_NAME"
for _ in $(seq 1 60); do
  STATE=$(curl -sf -H "$AUTH" "https://dataform.googleapis.com/v1/$INV_NAME" | python3 -c "import json,sys;print(json.load(sys.stdin)['state'])")
  echo "  estado: $STATE"
  case "$STATE" in SUCCEEDED) exit 0;; FAILED|CANCELLED) exit 1;; esac
  sleep 10
done
