// Último snapshot de cada maestro con fecha <= run_date.
// Usar "el último disponible" (y no "el de hoy") evita que un día sin archivo deje la dimensión vacía.
// Trade-off: sin cota inferior se leen todas las particiones <= run_date. Los maestros son chicos;
// con maestros grandes pondrías una ventana constante (p. ej. 30 días) para podar.
const { RUN_DATE } = constants;

publish("stg_product_snapshot", {
  type: "view",
  tags: ["daily"],
  description: "Maestro de productos de retail vigente a run_date (último snapshot disponible).",
}).query((ctx) => `
  SELECT * EXCEPT (rn) FROM (
    SELECT s.*, ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY snapshot_date DESC) AS rn
    FROM ${ctx.ref("raw_sellout", "product_snapshot")} AS s
    WHERE snapshot_date <= DATE '${RUN_DATE}'
  ) WHERE rn = 1
`);

publish("stg_store_snapshot", {
  type: "view",
  tags: ["daily"],
  description: "Maestro de tiendas vigente a run_date (último snapshot disponible).",
}).query((ctx) => `
  SELECT * EXCEPT (rn) FROM (
    SELECT s.*, ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY snapshot_date DESC) AS rn
    FROM ${ctx.ref("raw_sellout", "store_snapshot")} AS s
    WHERE snapshot_date <= DATE '${RUN_DATE}'
  ) WHERE rn = 1
`);
