// Último snapshot CONOCIDO del maestro de tiendas (sin filtrar por run_date).
// Así dim_store (SCD1 = "el estado más reciente") da lo mismo aunque re-proceses un día viejo.
// (dim_product no usa esto: reconstruye su historia completa desde raw_sellout.product_snapshot.)
publish("stg_store_snapshot", {
  type: "view",
  tags: ["daily"],
  description: "Maestro de tiendas: último snapshot disponible de cada tienda.",
}).query((ctx) => `
  SELECT * EXCEPT (rn) FROM (
    SELECT s.*, ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY snapshot_date DESC) AS rn
    FROM ${ctx.ref("raw_sellout", "store_snapshot")} AS s
  ) WHERE rn = 1
`);
