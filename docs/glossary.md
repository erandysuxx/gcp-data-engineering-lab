# Glossary (EN–ES)

> Terms you will hear in a GCP Data Engineer interview, with the Spanish equivalent and a one-line definition. Learn to say the English term naturally: interviews at a global company happen in English even when the team speaks Spanish. Product names follow the 2026 naming (see `13-nombres-2026.md`).

## BigQuery and storage

| Term (EN) | Español | One-line definition |
|---|---|---|
| Partitioning | Particionamiento | Splitting a table into segments (usually by date) so queries that filter on that column read only the relevant segments. |
| Partition pruning | Poda de particiones | BigQuery skipping partitions that cannot match a constant filter on the partitioning column. |
| Clustering | Clusterizado / agrupamiento | Sorting data inside storage blocks by up to four columns so filters and aggregations on them read fewer blocks. |
| Slot | Slot | A virtual unit of compute that BigQuery uses to execute a query stage. |
| On-demand pricing | Precio bajo demanda | Paying for the bytes each query processes (per TiB), with no reserved capacity. |
| Editions (capacity pricing) | Ediciones (precio por capacidad) | Paying for slot capacity over time through reservations (Standard, Enterprise, Enterprise Plus), with baseline and autoscaling. |
| Reservation | Reserva | A pool of slots assigned to projects, folders or the organization. |
| Dry run | Ejecución en seco | Validating a query and estimating the bytes it would process without running it or paying for it. |
| Bytes processed / bytes billed | Bytes procesados / facturados | What a query reads vs. what you are charged for (`total_bytes_billed` in `INFORMATION_SCHEMA.JOBS`). |
| DML | DML (lenguaje de manipulación de datos) | `INSERT`, `UPDATE`, `DELETE` and `MERGE` statements that change table rows. |
| MERGE | MERGE | A single statement that inserts, updates or deletes target rows depending on whether they match a source. |
| Upsert | Upsert (insertar o actualizar) | Insert a row if its key is new, otherwise update it; usually implemented with `MERGE`. |
| Load job | Job de carga | A batch job that loads files (for example from Cloud Storage) into a table; it uses a shared, free slot pool. |
| Storage Write API (gRPC) | Storage Write API (gRPC) | The recommended API for streaming or batch-committing rows into BigQuery, with exactly-once semantics. |
| Storage Write API (REST) / streaming inserts | Inserciones en streaming (legacy) | The legacy `tabledata.insertAll` method; kept for existing code. |
| External table | Tabla externa | A table whose data stays in Cloud Storage (or another source) and is read at query time. |
| Authorized view | Vista autorizada | A view allowed to read a source dataset, so users can query the view without access to the underlying tables. |
| Row-level security | Seguridad a nivel de fila | Policies that filter which rows each principal can see. |
| Policy tag | Policy tag (etiqueta de política) | A tag on a column that restricts or masks access to that column. |
| Time travel | Viaje en el tiempo | Querying or restoring a table as it was at a point within the last 2–7 days. |
| Fail-safe | Fail-safe | A further 7-day retention period, after time travel, for emergency recovery through support. |
| Logical vs physical storage billing | Facturación lógica vs física | Paying for uncompressed bytes (time travel included) vs. compressed bytes (time travel billed separately); set per dataset. |
| Soft delete (Cloud Storage) | Borrado suave | Deleted or overwritten objects are kept, and billed, for a retention period (7 days by default). |
| Lifecycle rule | Regla de ciclo de vida | A bucket rule that deletes objects or changes their storage class based on conditions such as age. |
| Storage class | Clase de almacenamiento | Standard, Nearline, Coldline or Archive; colder classes are cheaper at rest but have minimum storage durations and retrieval fees. |

## Pipelines and processing

| Term (EN) | Español | One-line definition |
|---|---|---|
| ETL | ETL (extraer, transformar, cargar) | Transforming data before loading it into the warehouse. |
| ELT | ELT (extraer, cargar, transformar) | Loading raw data first and transforming it inside the warehouse; the usual pattern on BigQuery. |
| Landing zone | Zona de aterrizaje | The bucket or prefix where source files arrive untouched. |
| Raw / staging / marts | Capas raw / staging / marts | Layers: faithful copy of the source, cleaned and typed data, business-ready models. |
| Medallion architecture | Arquitectura medallón | The same layering idea named bronze, silver and gold. |
| Idempotent | Idempotente | Running the same job twice for the same input leaves the same result, with no duplicates. |
| Backfill | Backfill (reproceso histórico) | Running a pipeline for past dates, for example after a bug fix or a new source. |
| Restatement | Reexpresión / reenvío corregido | A source re-sending corrected data for periods already loaded. |
| Late-arriving data | Datos tardíos | Records that arrive after the period they belong to has already been processed. |
| Watermark | Marca de agua (watermark) | In streaming, the system's estimate of how complete the data is up to a given event time. |
| Windowing | Ventanas | Grouping streaming events into time buckets (fixed, sliding or session windows) to aggregate them. |
| Trigger (Beam) | Disparador | Rule that decides when a window emits results (at the watermark, early or late). |
| PCollection | PCollection | A distributed dataset in an Apache Beam pipeline. |
| ParDo / DoFn | ParDo / DoFn | Beam's element-wise transform and the function it applies to each element. |
| Side input | Entrada lateral | A small extra dataset (for example a lookup table) made available to every worker. |
| Tagged output | Salida etiquetada | A second output of a DoFn, typically used to send invalid records to a dead-letter destination. |
| Dead-letter queue (DLQ) | Cola de mensajes fallidos | Where records that cannot be processed go, with the reason, instead of failing the whole job or being dropped. |
| Hot key | Llave caliente | A key with far more records than the rest, which overloads a single worker. |
| Fusion / Reshuffle | Fusión / Reshuffle | Dataflow merging steps into one stage; a Reshuffle breaks fusion to restore parallelism. |
| Flex Template | Flex Template | A Dataflow pipeline packaged as a container image plus a spec file, launched with parameters. |
| Worker | Worker (trabajador) | A VM (Dataflow) or process (Airflow) that executes the actual work. |
| Autoscaling | Autoescalado | Adding or removing workers automatically based on load. |
| Fan-out | Fan-out (multiplicación de filas) | Rows multiplying after a join with a one-to-many relationship, which inflates sums. In messaging, one event delivered to many consumers. |
| Data contract | Contrato de datos | An agreed schema, semantics and SLA between a data producer and its consumers. |

## Orchestration

| Term (EN) | Español | One-line definition |
|---|---|---|
| DAG | DAG (grafo acíclico dirigido) | An Airflow workflow: tasks and their dependencies, with no cycles. |
| DAG run | Ejecución del DAG | One execution of a DAG for a given logical date. |
| Logical date | Fecha lógica | The data interval a DAG run represents, not the moment it actually runs (formerly *execution date*). |
| Operator | Operador | A template for a task, for example "run a BigQuery job" or "launch a Flex Template". |
| Sensor | Sensor | A task that waits for a condition, such as a file existing in a bucket. |
| Deferrable operator | Operador diferible | A task that releases its worker while waiting and is resumed by the triggerer when the condition is met. |
| XCom | XCom | Small messages tasks pass to each other (IDs, counts), not datasets. |
| Asset | Asset (antes Dataset) | In Airflow 3, a logical data object that can trigger DAGs when it is updated. |
| Catchup | Catchup | Whether the scheduler creates runs for every missed interval since the start date. |
| Retry with backoff | Reintento con espera exponencial | Re-running a failed task after increasing delays. |

## Data modeling

| Term (EN) | Español | One-line definition |
|---|---|---|
| Grain | Grano | What exactly one row of a fact table represents, for example "units sold per day, store and product". |
| Fact table | Tabla de hechos | Measurable events (sales, deliveries) at a defined grain, with keys to dimensions. |
| Dimension | Dimensión | Descriptive context for facts: product, store, date, customer. |
| Conformed dimension | Dimensión conformada | A dimension shared, with the same keys and meaning, across several fact tables. |
| Surrogate key | Llave subrogada | A warehouse-generated key, independent of the source's business key. |
| Natural / business key | Llave natural / de negocio | The identifier the source uses, such as a SKU code or a store number. |
| SCD type 1 | SCD tipo 1 | Overwrite the attribute; history is lost. |
| SCD type 2 | SCD tipo 2 | Insert a new row with validity dates for each change; history is preserved. |
| Unknown member | Miembro desconocido | A default dimension row (for example key `-1`) so facts with a missing reference are not lost in joins. |
| Transaction fact | Hecho transaccional | One row per event. |
| Periodic snapshot | Snapshot periódico | One row per entity per period, for example daily inventory per store and product. |
| Accumulating snapshot | Snapshot acumulativo | One row per process instance (an order) updated as it reaches milestones (shipped, delivered). |
| Star schema | Esquema en estrella | Facts joined directly to denormalized dimensions. |
| Snowflake schema | Esquema copo de nieve | Dimensions normalized into several related tables. |

## Quality, governance and operations

| Term (EN) | Español | One-line definition |
|---|---|---|
| Data quality dimensions | Dimensiones de calidad | Completeness, uniqueness, validity, consistency, freshness and volume. |
| Assertion | Aserción | A query that returns violating rows; the test fails if any row comes back (Dataform). |
| Control totals / control figures | Cifras de control | Reconciling source counts with loaded plus rejected counts to prove nothing was lost or duplicated. |
| Data quality scan | Scan de calidad | A Knowledge Catalog job that checks rules on a table on a schedule; billed per use. |
| Data profiling | Perfilado de datos | Computing column statistics (nulls, distinct values, ranges) to understand a dataset. |
| Lineage | Linaje | The record of which jobs read which sources to produce which tables. |
| Freshness | Frescura | How recent the latest available data is compared with what is expected. |
| SLA / SLO | SLA / SLO | The commitment to consumers (for example "marts ready by 08:00") and the internal target behind it. |
| Audit logs (Admin Activity / Data Access) | Logs de auditoría | Who changed configuration (always on) and who read or wrote data (on by default for BigQuery). |
| Label | Etiqueta (label) | A key-value pair on a job or resource that flows into the billing export for cost attribution. |
| Billing export | Exportación de facturación | Detailed Cloud Billing data exported to BigQuery for analysis. |

## Security, IaC and CI/CD

| Term (EN) | Español | One-line definition |
|---|---|---|
| Service account | Cuenta de servicio | A non-human identity that workloads use to call Google Cloud APIs. |
| Least privilege | Mínimo privilegio | Granting only the permissions a principal strictly needs. |
| Workload Identity Federation (WIF) | Federación de identidades de carga de trabajo | Exchanging an external token (for example GitHub's OIDC token) for short-lived Google credentials, with no stored keys. |
| Attribute condition | Condición de atributos | The CEL expression that decides which external tokens a WIF provider accepts. |
| Infrastructure as Code (IaC) | Infraestructura como código | Defining infrastructure in versioned files that are reviewed and applied automatically. |
| Terraform state | Estado de Terraform | The mapping between configuration and real resources; stored remotely with locking. |
| Drift | Desviación (drift) | Differences between the code and the real infrastructure, usually caused by manual changes. |
| Plan / apply | Plan / apply | Preview the changes / execute them. |
| CI / CD | Integración / despliegue continuo | Validating every change automatically / deploying merged changes automatically. |
| Separation of duties | Separación de funciones | The person who writes a change is not the one who approves its production deployment. |
| Image digest | Digest de imagen | The immutable `sha256` identifier of a container image, unlike a movable tag. |

## Retail and supply chain domain

| Term (EN) | Español | One-line definition |
|---|---|---|
| Sell-in | Sell-in (venta al canal) | Sales from the manufacturer to retailers or distributors. |
| Sell-out | Sell-out (venta al consumidor) | Sales from the retailer to the end consumer, reported by the retailer. |
| Sell-through rate | Tasa de sell-through | Share of the stock received by the retailer that was sold to consumers in a period. |
| SKU | SKU | The manufacturer's (or retailer's) internal code for a sellable item. |
| EAN / GTIN | EAN / GTIN | The standard barcode number on a product; retailers often report EAN and you map it to SKU. |
| Retail calendar (4-4-5 / 4-5-4) | Calendario retail | A fiscal calendar of weeks grouped into 4- and 5-week months, so periods compare like for like. |
| Same-store sales (like-for-like) | Ventas en tiendas comparables | Growth measured only on stores open in both periods. |
| OTIF | OTIF (a tiempo y completo) | On Time In Full: share of orders (or lines) delivered on the agreed date with the full quantity. |
| Fill rate | Tasa de surtido | Share of ordered quantity actually shipped. |
| Lead time | Tiempo de entrega | Time from placing an order to receiving it. |
| Stockout / out-of-stock (OOS) | Quiebre de stock | A product not available on the shelf or in stock when demand exists. |
| Weeks of cover / days of inventory | Semanas de cobertura | How long current stock lasts at the current sales rate. |
| Master data | Datos maestros | Reference data (products, stores, customers) that transactions point to. |

## Phrases for the interview

Use these to explain trade-offs. They sound natural and show you think in costs and risks, not only in tools.

- "It depends on the latency the business actually needs. If the decision is made once a day, a daily batch is simpler and much cheaper."
- "I'd start with the simplest option that meets the requirement and only add Dataflow when the logic doesn't fit in SQL."
- "The trade-off here is cost versus freshness."
- "I'd make the load idempotent: re-running the same date replaces that partition instead of appending duplicates."
- "I measured it with `total_bytes_billed` in `INFORMATION_SCHEMA.JOBS`, not with the dry-run estimate."
- "The first thing I'd check is whether anyone actually reads that table."
- "A green DAG doesn't mean the data is right, so I reconcile control totals against the source manifest."
- "Invalid rows go to a dead-letter table with the reason, so one bad record doesn't block the whole file."
- "I'd keep the raw files in Cloud Storage so we can reprocess when a rule changes."
- "We authenticate CI with Workload Identity Federation, so there are no service account keys to leak or rotate."
- "Infrastructure changes go through a pull request and Terraform; the console is read-only for us."
- "Before choosing, I'd ask about volume, latency, who consumes the data and who will operate it."
- "That's a good point; I haven't used it in production, but my understanding is… and I'd validate it with a small test first."
- "To put it in numbers: in my lab, partitioning and clustering reduced the bytes billed for that query from X to Y."
- "If I had to do it again, I'd define the grain and the data contract with the retailer before writing any code."
