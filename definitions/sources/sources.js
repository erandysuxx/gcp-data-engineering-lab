// Declaraciones: tablas que Dataform NO crea pero que los modelos leen con ref().
// Así el grafo de dependencias (y el linaje) arranca en las tablas raw.

const olist = [
  "orders", "order_items", "products", "sellers", "customers",
  "order_payments", "order_reviews", "category_translation",
];
olist.forEach((name) => declare({ schema: "raw_olist", name }));

["sellout_lines", "sellout_rejects", "product_snapshot", "store_snapshot"].forEach((name) =>
  declare({ schema: "raw_sellout", name })
);
