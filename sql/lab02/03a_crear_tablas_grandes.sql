/* Lab02 · 3a. Tabla sintética de ~3 GB para que partición y clustering se NOTEN en bytes.
   (Con tablas chicas no se ve nada: BigQuery cobra mínimo 10 MB por tabla leída.)
   Generar datos con GENERATE_ARRAY no escanea nada: el costo es solo el storage, y la borramos al final. */
CREATE OR REPLACE TABLE sandbox.sales_big_plain AS
SELECT
  DATE_ADD(DATE '2026-10-01', INTERVAL MOD(n, 10) DAY)      AS sale_date,
  FORMAT('S%03d', MOD(DIV(n, 7), 50))                         AS store_id,
  FORMAT('P%05d', MOD(n * 7919, 5000))                        AS product_id,
  1 + MOD(n, 12)                                              AS units,
  CAST(ROUND(10 + MOD(n * 31, 9000) / 100, 2) AS NUMERIC)     AS net_sales,
  REPEAT('x', 60)                                             AS payload   -- relleno para que la tabla pese
FROM UNNEST(GENERATE_ARRAY(0, 29999)) AS a,
     UNNEST(GENERATE_ARRAY(0, 999)) AS b,          -- 30 000 x 1 000 = 30 M filas
     UNNEST([a * 1000 + b]) AS n;                  -- (un solo array de 30 M excede el límite de tamaño)

/* Misma data, particionada por día. */
CREATE OR REPLACE TABLE sandbox.sales_big_part
PARTITION BY sale_date
AS SELECT * FROM sandbox.sales_big_plain;

/* Misma data, particionada por día Y agrupada (clustered) por tienda. */
CREATE OR REPLACE TABLE sandbox.sales_big_part_clus
PARTITION BY sale_date
CLUSTER BY store_id
AS SELECT * FROM sandbox.sales_big_plain;
