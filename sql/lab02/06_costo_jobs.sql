/* Lab02 · 6. ¿Cuánto me costaron mis consultas? INFORMATION_SCHEMA.JOBS guarda cada job 180 días.
   On-demand: se factura por bytes (total_bytes_billed), con mínimo de 10 MB por tabla leída. */
SELECT
  creation_time,
  job_type,
  statement_type,
  ROUND(total_bytes_processed / POW(1024, 3), 3) AS gib_processed,
  ROUND(total_bytes_billed / POW(1024, 3), 3)    AS gib_billed,
  ROUND(total_bytes_billed / POW(1024, 4) * 6.25, 4) AS usd_on_demand_aprox,  -- lista; el 1er TiB del mes es gratis
  total_slot_ms,
  (SELECT value FROM UNNEST(labels) WHERE key = 'lab') AS lab,
  LEFT(REGEXP_REPLACE(query, r'\s+', ' '), 90) AS query_head
FROM `region-${REGION}`.INFORMATION_SCHEMA.JOBS
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND statement_type != 'SCRIPT'          -- los scripts duplican los bytes de sus hijos
ORDER BY creation_time DESC
LIMIT 30;
