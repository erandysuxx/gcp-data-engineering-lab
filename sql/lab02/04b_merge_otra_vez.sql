/* Lab02 · 4b. El MISMO MERGE otra vez. Si es idempotente, no cambia nada: compara los conteos con 04. */
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
