/* Lab02 · 4. MERGE (upsert) idempotente.
   Escenario: el sistema fuente reenvía órdenes con estado corregido. Queremos actualizar las que existen,
   insertar las nuevas, y que correr esto dos veces deje el MISMO resultado. */
CREATE OR REPLACE TABLE sandbox.orders_current AS
SELECT order_id, order_status, order_purchase_timestamp
FROM raw_olist.orders
WHERE order_purchase_timestamp < '2018-01-01';

-- "Novedades": 100 órdenes existentes con otro estado + las órdenes de enero 2018 (nuevas)
CREATE OR REPLACE TABLE sandbox.orders_updates AS
SELECT order_id, 'canceled' AS order_status, order_purchase_timestamp
FROM sandbox.orders_current
WHERE order_status = 'delivered'
QUALIFY ROW_NUMBER() OVER (ORDER BY order_id) <= 100
UNION ALL
SELECT order_id, order_status, order_purchase_timestamp
FROM raw_olist.orders
WHERE order_purchase_timestamp >= '2018-01-01' AND order_purchase_timestamp < '2018-02-01';

MERGE sandbox.orders_current AS t
USING sandbox.orders_updates AS s
ON t.order_id = s.order_id
WHEN MATCHED AND t.order_status != s.order_status THEN
  UPDATE SET order_status = s.order_status
WHEN NOT MATCHED BY TARGET THEN
  INSERT (order_id, order_status, order_purchase_timestamp)
  VALUES (s.order_id, s.order_status, s.order_purchase_timestamp);

SELECT @@row_count AS filas_afectadas_por_el_merge;
SELECT COUNT(*) AS total, COUNTIF(order_status = 'canceled') AS canceled FROM sandbox.orders_current;
-- Siguiente: corre 04b_merge_otra_vez.sql (solo el MERGE). Debe afectar 0 filas.
