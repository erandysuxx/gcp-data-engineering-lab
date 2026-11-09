/* Lab02 · 3d. ANTIPATRÓN: filtrar la partición con una SUBCONSULTA. El dry-run no puede saber
   qué particiones leerá: estima la tabla completa. Compáralo con 03c (ventana constante). */
SELECT SUM(units)
FROM sandbox.sales_big_part
WHERE sale_date >= (SELECT DATE_SUB(MAX(sale_date), INTERVAL 1 DAY) FROM sandbox.sales_big_part);
