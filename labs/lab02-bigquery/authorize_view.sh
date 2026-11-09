#!/usr/bin/env bash
# Autoriza la vista reporting.v_sales_by_state a leer raw_olist (sin dar acceso a raw_olist a sus lectores).
set -euo pipefail
: "${PROJECT_ID:?source .env.lab}"
TMP=$(mktemp)
bq show --format=prettyjson "${PROJECT_ID}:raw_olist" > "$TMP"
python3 - "$TMP" "$PROJECT_ID" <<'PY'
import json, sys
path, project = sys.argv[1], sys.argv[2]
ds = json.load(open(path))
view = {"view": {"projectId": project, "datasetId": "reporting", "tableId": "v_sales_by_state"}}
if view not in ds.setdefault("access", []):
    ds["access"].append(view)
json.dump(ds, open(path, "w"))
PY
bq update --source "$TMP" "${PROJECT_ID}:raw_olist"
bq show --format=prettyjson "${PROJECT_ID}:raw_olist" | python3 -c "import json,sys;print([a for a in json.load(sys.stdin)['access'] if 'view' in a])"
rm -f "$TMP"
