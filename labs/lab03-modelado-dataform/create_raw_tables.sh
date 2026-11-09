#!/usr/bin/env bash
# Crea los datasets y las tablas "contrato" que NO crea Dataform (raw_sellout.*, ops.control_figures).
# Mismo esquema, partición y clustering que infra/terraform: en el lab07 Terraform las ADOPTA con import.
# Idempotente: si ya existen, no hace nada.
set -euo pipefail
: "${PROJECT_ID:?source .env.lab}"
mkds() {  # dataset, descripción
  bq show "${PROJECT_ID}:$1" >/dev/null 2>&1 || bq mk --location="$REGION" --dataset --description "$2" "${PROJECT_ID}:$1"
}
mkds raw_sellout "Feed de sell-out validado por Dataflow + dead-letter + snapshots de maestros"
mkds staging "Modelos de staging de Dataform (limpieza, tipos, dedup)"
mkds marts "Modelo dimensional (estrella) para consumo"
mkds ops "Operación: cifras de control de los pipelines"
mkds dataform_assertions "Vistas de las assertions de Dataform"

mktable() {  # dataset tabla campo_particion clustering
  bq show "${PROJECT_ID}:$1.$2" >/dev/null 2>&1 && { echo "  = $1.$2 ya existe"; return; }
  bq mk --table --schema "infra/schemas/$2.json" \
    --time_partitioning_type DAY --time_partitioning_field "$3" --clustering_fields "$4" "${PROJECT_ID}:$1.$2"
}
mktable raw_sellout sellout_lines    sale_date     retailer_id,product_id
mktable raw_sellout sellout_rejects  feed_date     error_code
mktable raw_sellout product_snapshot snapshot_date product_id
mktable raw_sellout store_snapshot   snapshot_date store_id
mktable ops         control_figures  run_date      pipeline
bq ls "${PROJECT_ID}:raw_sellout"
