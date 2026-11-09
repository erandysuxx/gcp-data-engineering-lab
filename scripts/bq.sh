#!/usr/bin/env bash
# Corre un archivo .sql reemplazando ${VARIABLES} de tu entorno (source .env.lab primero).
# Uso:  scripts/bq.sh sql/lab02/01_explorar.sql            # ejecuta
#       scripts/bq.sh sql/lab02/01_explorar.sql --dry_run  # solo estima bytes (gratis)
# Cada job lleva la etiqueta lab=<carpeta> para poder medir su costo después en INFORMATION_SCHEMA.JOBS.
set -euo pipefail
FILE="$1"; shift
LAB=$(basename "$(dirname "$FILE")")
SQL=$(python3 -c 'import os,sys;print(os.path.expandvars(open(sys.argv[1]).read()))' "$FILE")
bq query --nouse_legacy_sql --location="${REGION:-us-central1}" --label="lab:${LAB}" --max_rows=50 "$@" "$SQL"
