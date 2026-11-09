/* SCD2 INCREMENTAL CON MERGE (patrón alternativo, de referencia)
   ==============================================================
   El lab usó esta versión al principio y funciona (validada procesando 2026-11-01, -02 y -03 EN ORDEN).
   La cambiamos por la reconstrucción desde el historial (definitions/marts/dim_product.sqlx) por esto:

   - El MERGE compara "lo que llega hoy" contra "lo vigente". Si procesas una fecha VIEJA después de
     una nueva (backfill, re-proceso, restatement), cierra versiones que no debía y la historia se corrompe.
   - En Airflow 3 un backfill y las corridas programadas tienen límites de concurrencia SEPARADOS:
     el orden no está garantizado salvo que lo fuerces (depends_on_past, --max-active-runs 1, pausar).

   ¿Cuándo SÍ conviene el MERGE? Dimensiones enormes (cientos de millones de filas) donde reconstruir
   todo cada día es caro, y el orden de carga está garantizado.

   Era un `config { type: "operations", hasOutput: true }` de Dataform.
*/
-- 1) La tabla se crea una sola vez (las operations no la crean solas).
CREATE TABLE IF NOT EXISTS ${self()} (
  product_sk INT64, product_id STRING, category STRING, category_en STRING, weight_g INT64,
  brand STRING, list_price NUMERIC, row_hash INT64,
  valid_from DATE, valid_to DATE, is_current BOOL
)
CLUSTER BY product_id;

-- 2) Estado "hoy" (run_date) de cada producto: catálogo de Olist + maestro de retail vigente.
CREATE TEMP TABLE src AS
SELECT
  p.product_id, p.category, p.category_en, p.weight_g, s.brand, CAST(s.list_price AS NUMERIC) AS list_price,
  FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(p.category_en, s.brand, s.list_price))) AS row_hash,
  COALESCE(s.snapshot_date, DATE '${constants.RUN_DATE}') AS effective_date
FROM ${ref("stg_products")} AS p
LEFT JOIN ${ref("stg_product_snapshot")} AS s USING (product_id);

-- 3) MERGE SCD2 en una sola sentencia (atómica e idempotente: re-correr el mismo día no cambia nada).
--    Rama A (merge_key = product_id): cierra la versión vigente si el hash cambió; inserta productos nuevos.
--    Rama B (merge_key = NULL): las filas que cambiaron; como no hacen match, se insertan como versión nueva.
MERGE ${self()} AS t
USING (
  SELECT src.product_id AS merge_key, src.*, FALSE AS is_change FROM src
  UNION ALL
  SELECT CAST(NULL AS STRING), src.*, TRUE
  FROM src JOIN ${self()} AS cur
    ON cur.product_id = src.product_id AND cur.is_current AND cur.row_hash != src.row_hash
) AS s
ON t.product_id = s.merge_key AND t.is_current
WHEN MATCHED AND t.row_hash != s.row_hash THEN
  UPDATE SET is_current = FALSE, valid_to = DATE_SUB(s.effective_date, INTERVAL 1 DAY)
WHEN NOT MATCHED BY TARGET THEN
  INSERT (product_sk, product_id, category, category_en, weight_g, brand, list_price, row_hash,
          valid_from, valid_to, is_current)
  VALUES (
    FARM_FINGERPRINT(CONCAT(s.product_id, "|",
      CAST(IF(s.is_change, s.effective_date, DATE '${constants.SCD_OPEN_FROM}') AS STRING))),
    s.product_id, s.category, s.category_en, s.weight_g, s.brand, s.list_price, s.row_hash,
    IF(s.is_change, s.effective_date, DATE '${constants.SCD_OPEN_FROM}'), DATE '${constants.SCD_OPEN_TO}', TRUE);

-- 4) Miembro desconocido: los hechos con un producto que no conocemos apuntan aquí en vez de quedar NULL.
INSERT INTO ${self()} (product_sk, product_id, category, category_en, row_hash, valid_from, valid_to, is_current)
SELECT ${constants.UNKNOWN_SK}, "unknown", "unknown", "unknown", 0,
       DATE '${constants.SCD_OPEN_FROM}', DATE '${constants.SCD_OPEN_TO}', TRUE
FROM UNNEST([1])
WHERE NOT EXISTS (SELECT 1 FROM ${self()} WHERE product_sk = ${constants.UNKNOWN_SK});
