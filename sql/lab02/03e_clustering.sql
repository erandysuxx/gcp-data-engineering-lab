/* Lab02 · 3e. CLUSTERING. El dry-run da el MISMO estimado para las dos (es una cota superior),
   pero al EJECUTARLAS la tabla clustered factura menos. Ejecútalas (sin --dry_run) y mira
   total_bytes_billed con 06_costo_jobs.sql. */
SELECT SUM(units) FROM sandbox.sales_big_part      WHERE sale_date = '2026-10-05' AND store_id = 'S007';
SELECT SUM(units) FROM sandbox.sales_big_part_clus WHERE sale_date = '2026-10-05' AND store_id = 'S007';
