/* Lab02 · 2. Tabla EXTERNA: BigQuery lee el CSV directo de GCS, sin cargarlo.
   Útil para explorar o para datos que no quieres duplicar. Lento y sin caché ni partición: no es para producción. */
CREATE OR REPLACE EXTERNAL TABLE sandbox.ext_sellers
OPTIONS (
  format = 'CSV',
  uris = ['gs://${LANDING_BUCKET}/olist/olist_sellers_dataset.csv'],
  skip_leading_rows = 1
);

SELECT seller_state, COUNT(*) AS sellers
FROM sandbox.ext_sellers
GROUP BY seller_state
ORDER BY sellers DESC
LIMIT 5;
