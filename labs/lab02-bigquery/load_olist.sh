#!/usr/bin/env bash
# Carga los CSV de Olist (ya en GCS) a raw_olist con ESQUEMA EXPLÍCITO. Idempotente: --replace.
set -euo pipefail
: "${LANDING_BUCKET:?source .env.lab}"
SCHEMAS="sql/lab02/schemas"
# Pares "tabla:archivo" (sin arrays asociativos: el bash de macOS es 3.2 y no los soporta)
PAIRS="orders:olist_orders_dataset.csv
order_items:olist_order_items_dataset.csv
products:olist_products_dataset.csv
sellers:olist_sellers_dataset.csv
customers:olist_customers_dataset.csv
order_payments:olist_order_payments_dataset.csv
order_reviews:olist_order_reviews_dataset.csv
category_translation:product_category_name_translation.csv"
echo "$PAIRS" | while IFS=: read -r T F; do
  echo "→ raw_olist.$T"
  bq load --location="$REGION" --source_format=CSV --skip_leading_rows=1 --allow_quoted_newlines \
    --replace "raw_olist.$T" "gs://${LANDING_BUCKET}/olist/${F}" "$SCHEMAS/$T.json"
done
bq query --nouse_legacy_sql --location="$REGION" \
  "SELECT table_id, row_count FROM raw_olist.__TABLES__ ORDER BY table_id"
