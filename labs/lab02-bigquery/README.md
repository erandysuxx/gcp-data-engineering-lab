# Lab 02 · BigQuery: cargar, consultar, medir y no pagar de más

**Objetivo:** cargar Olist a BigQuery con esquemas explícitos, **medir** el efecto de la partición y el clustering, hacer un `MERGE` idempotente, compartir datos con una vista autorizada y calcular cuánto costó cada consulta.

**Tiempo:** ~3 h · **Costo:** $0 (dentro del free tier: 1 TiB de consultas y 10 GiB de storage al mes) · **Docs:** [`04-bigquery`](../../docs/04-bigquery.md)

## Conceptos en 1 minuto
- **On-demand:** pagas por **bytes leídos** (`total_bytes_billed`), no por filas devueltas ni por tiempo.
- **Cargar** desde GCS (`bq load`, un *load job*) es **gratis**. Lo que se cobra es el storage y las consultas.
- `--dry_run` estima los bytes **sin ejecutar ni cobrar**. Úsalo antes de toda consulta grande.

## Pasos
```bash
source .env.lab && scripts/preflight.sh
```

### 1. Datasets
```bash
bq mk --location="$REGION" --dataset --description "Copia cruda del dataset Olist (canal e-commerce)" "${PROJECT_ID}:raw_olist"
bq mk --location="$REGION" --dataset --default_table_expiration 604800 \
  --description "Experimentos del lab02 (las tablas expiran solas)" "${PROJECT_ID}:sandbox"
```

### 2. La trampa del autodetect
```bash
bq load --location="$REGION" --autodetect --source_format=CSV \
  sandbox.customers_autodetect "gs://$LANDING_BUCKET/olist/olist_customers_dataset.csv"
bq show --schema --format=prettyjson sandbox.customers_autodetect | grep -A1 zip
bq query --nouse_legacy_sql "SELECT customer_zip_code_prefix FROM sandbox.customers_autodetect
  WHERE customer_state = 'SP' LIMIT 5"
```
El código postal (`01151`) se detectó como **INTEGER** y perdió el cero (`1151`). Para producción, el esquema es un **contrato** explícito: mira `sql/lab02/schemas/customers.json`.

### 3. Carga con esquema explícito
```bash
labs/lab02-bigquery/load_olist.sh
```
`--allow_quoted_newlines` es necesario porque los comentarios de las reviews traen saltos de línea dentro de comillas. Sin ese flag, la carga falla.

### 4. Explorar con dry-run primero
```bash
scripts/bq.sh sql/lab02/01_explorar.sql --dry_run   # "will process N bytes"
scripts/bq.sh sql/lab02/01_explorar.sql
```

### 5. Tabla externa
```bash
scripts/bq.sh sql/lab02/02_tabla_externa.sql
```
BigQuery lee el CSV directo de GCS. No se cobra storage de BigQuery, pero cada consulta relee el archivo, sin caché ni partición.

### 6. Partición y clustering: medir, no creer
```bash
scripts/bq.sh sql/lab02/03a_crear_tablas_grandes.sql     # 3 copias de una tabla de ~3 GB (tarda 1–2 min)
scripts/bq.sh sql/lab02/03b_particion.sql --dry_run       # tabla SIN partición: lee todo
scripts/bq.sh sql/lab02/03c_particion_ok.sql --dry_run    # particionada: ~1/10
scripts/bq.sh sql/lab02/03d_subconsulta_no_poda.sql --dry_run   # ANTIPATRÓN: subconsulta → lee todo
scripts/bq.sh sql/lab02/03f_select_star_limit.sql --dry_run     # SELECT * con LIMIT: no ahorra
scripts/bq.sh sql/lab02/03e_clustering.sql                # EJECUTAR (el dry-run no ve el clustering)
scripts/bq.sh sql/lab02/06_costo_jobs.sql                 # compara gib_billed de las dos consultas de 03e
```
Anota en tu `PROGRESO.md` la tabla de bytes de cada consulta. **Esa tabla es una historia de entrevista** (ver `docs/interview/pitch-and-star.md`).

### 7. MERGE idempotente (upsert)
```bash
scripts/bq.sh sql/lab02/04_merge.sql
```
```bash
scripts/bq.sh sql/lab02/04b_merge_otra_vez.sql      # el mismo MERGE, otra vez
```
La segunda vez `filas_afectadas_por_el_merge` debe ser **0** y los conteos no cambian: eso es idempotencia.

### 8. Vista autorizada
```bash
scripts/bq.sh sql/lab02/05_authorized_view.sql
labs/lab02-bigquery/authorize_view.sh
```
Ahora puedes dar `roles/bigquery.dataViewer` sobre el dataset `reporting` a un analista. Va a ver la vista agregada, **pero no las tablas de `raw_olist`** (ni los datos de clientes).

### 9. ¿Cuánto costó todo?
```bash
scripts/bq.sh sql/lab02/06_costo_jobs.sql
```

## Checkpoint
- `raw_olist` tiene 8 tablas. `orders` ronda las 99 mil filas.
- Tu tabla de bytes muestra:
  - la partición reduce ~10x en el dry-run;
  - la subconsulta no poda;
  - `LIMIT` no ahorra;
  - el clustering reduce `gib_billed` al ejecutar.
- Re-correr el `MERGE` afecta 0 filas.

## Limpieza (importante: ~10 GB de storage)
```bash
scripts/bq.sh sql/lab02/07_limpieza.sql
```

## Preguntas
1. ¿Por qué el dry-run no muestra el ahorro del clustering?
2. Tu consulta usa `WHERE fecha >= (SELECT MAX(fecha) FROM t)`. ¿Qué cambias y por qué?
3. ¿Cuándo usarías una tabla externa en vez de cargar los datos?
4. (EN) *How would you reduce the cost of a dashboard query that scans a 5 TB table every hour?*
