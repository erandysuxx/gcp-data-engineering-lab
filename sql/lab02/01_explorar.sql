/* Lab02 · 1. Explorar raw_olist. Corre primero con --dry_run y mira "bytes processed". */

-- ¿Cuántas órdenes hay por estado? (lee solo la columna order_status)
SELECT order_status, COUNT(*) AS orders
FROM raw_olist.orders
GROUP BY order_status
ORDER BY orders DESC;
