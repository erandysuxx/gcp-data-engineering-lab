/* Lab02 · 3f. MITOS. Corre ambas con --dry_run:
   - SELECT * lee TODAS las columnas (incluido el payload).
   - LIMIT NO reduce los bytes facturados: BigQuery ya leyó las columnas antes de limitar. */
SELECT * FROM sandbox.sales_big_part WHERE sale_date = '2026-10-05' LIMIT 10;
