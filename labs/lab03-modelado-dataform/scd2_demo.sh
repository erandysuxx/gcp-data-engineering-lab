#!/usr/bin/env bash
# Simula 3 días de maestros y corre el SCD2 de dim_product para cada día, EN ORDEN.
# Uso: labs/lab03-modelado-dataform/scd2_demo.sh 2026-11-01 2026-11-02 2026-11-03
set -euo pipefail
: "${PROJECT_ID:?source .env.lab}"
DF="npx --yes @dataform/cli@3.1.4"
for D in "$@"; do
  echo "== $D: generar maestros (local) y cargarlos a raw_sellout"
  (cd generator && uv run python -m sellout_gen.main --date "$D" \
     --products-csv ../data/olist/olist_products_dataset.csv --out ../out >/dev/null)
  P=${D//-/}
  bq load --location="$REGION" --source_format=NEWLINE_DELIMITED_JSON --replace \
    "raw_sellout.product_snapshot\$$P" "out/masters/date=$D/products.jsonl"
  bq load --location="$REGION" --source_format=NEWLINE_DELIMITED_JSON --replace \
    "raw_sellout.store_snapshot\$$P" "out/masters/date=$D/stores.jsonl"
  echo "== $D: SCD2 (staging de maestros + dim_product)"
  $DF run --actions dim_product --include-deps --vars "run_date=$D"   # --include-deps: también sus vistas de staging
done
bq query --nouse_legacy_sql --location="$REGION" "
SELECT valid_from, COUNT(*) AS versiones, COUNTIF(is_current) AS vigentes
FROM marts.dim_product GROUP BY valid_from ORDER BY valid_from"
