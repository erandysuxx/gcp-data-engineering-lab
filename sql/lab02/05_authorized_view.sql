/* Lab02 · 5. AUTHORIZED VIEW: compartir un resultado sin dar acceso a la tabla base.
   La vista vive en otro dataset (reporting) y expone solo agregados, sin datos de clientes. */
CREATE SCHEMA IF NOT EXISTS reporting OPTIONS (location = '${REGION}');

CREATE OR REPLACE VIEW reporting.v_sales_by_state AS
SELECT c.customer_state AS state, DATE_TRUNC(DATE(o.order_purchase_timestamp), MONTH) AS month,
       COUNT(DISTINCT o.order_id) AS orders, SUM(i.price) AS revenue
FROM raw_olist.orders AS o
JOIN raw_olist.order_items AS i USING (order_id)
JOIN raw_olist.customers AS c USING (customer_id)
GROUP BY state, month;
-- Paso siguiente (en el README): autorizar la vista sobre raw_olist con `bq update --view`.
