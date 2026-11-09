/* Lab02 · 3b. PODA DE PARTICIONES. Corre con --dry_run las dos consultas y compara "bytes processed".
   La de la tabla particionada debe leer ~1/10 (filtra 1 de 10 días). */
SELECT SUM(units) FROM sandbox.sales_big_plain WHERE sale_date = '2026-10-05';
