# Lecciones de producción

> Dieciocho situaciones que se repiten en plataformas de datos reales, contadas en abstracto y sin cifras. Cada una sigue el mismo formato: **Situación → Qué pasó → Por qué → Qué hacer**. Sirven para dos cosas: no repetirlas y tener historias concretas para la entrevista ("¿qué harías si…?").
> **Lab relacionado:** varias se pueden reproducir en `labs/lab02-bigquery`, `labs/lab05-dataflow-beam` y `labs/lab07-cicd-terraform`.

| Tema | Lecciones |
|---|---|
| BigQuery: poda, clustering, almacenamiento y DML | 1–6 |
| Orquestación y cómputo | 7, 8, 17 |
| Datos que nadie usa | 9, 13, 14 |
| Almacenamiento y mensajería | 10, 11, 12 |
| Seguridad y operación | 15, 16, 18 |

## Las lecciones

### 1. Un filtro incremental con `MAX()` no poda particiones

- **Situación:** una tabla incremental lee de una fuente particionada por fecha con `WHERE fecha >= (SELECT MAX(fecha) FROM destino)`.
- **Qué pasó:** el costo de la carga diaria crecía con el tamaño total de la fuente, no con el volumen del día.
- **Por qué:** BigQuery poda particiones solo cuando el filtro sobre la columna de partición es una **expresión constante**. Una subconsulta es dinámica: su valor se conoce al ejecutar, así que se escanean todas las particiones ([Query partitioned tables](https://docs.cloud.google.com/bigquery/docs/querying-partitioned-tables)).
- **Qué hacer:** usar una ventana constante, como `WHERE fecha >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)`, combinada con un `MERGE` idempotente que absorba la superposición de días; o pasar la fecha como literal desde el orquestador (`'{{ ds }}'`). Comprueba la poda con un dry-run antes y después.

### 2. Una carga incremental sobre una fuente sin partición lee la tabla entera

- **Situación:** el modelo destino es incremental "para ahorrar", pero la fuente no está particionada ni clusterizada.
- **Qué pasó:** cada ejecución diaria escaneaba la fuente completa. El modelo incremental ahorraba en escritura, pero no en lectura.
- **Por qué:** un filtro de fecha solo reduce bytes si la tabla que se lee está particionada (o clusterizada) por esa columna. En una tabla sin partición, `WHERE fecha = ...` igual lee todas las columnas referenciadas de todas las filas.
- **Qué hacer:** particionar las tablas raw y staging por la fecha que usan los incrementales (de llegada o de negocio) y exigir filtro de partición (`require_partition_filter`) en las tablas grandes.

### 3. Deduplicar con una ventana sobre una columna que no es la de partición no poda

- **Situación:** para quedarse con la última versión de cada registro se usa `QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1`, filtrando por `updated_at`, pero la tabla está particionada por `ingestion_date`.
- **Qué pasó:** la deduplicación escaneaba toda la historia en cada corrida.
- **Por qué:** el filtro no toca la columna de partición, así que no hay poda. Además, la ventana necesita ver todas las filas del mismo `id` para decidir cuál es la última.
- **Qué hacer:** filtrar también por la columna de partición con una ventana acotada (por ejemplo, los últimos N días de `ingestion_date`) y deduplicar solo ese tramo contra el destino con `MERGE`. Si la consulta natural filtra por `updated_at`, considera particionar por esa columna.

### 4. El clustering agregado tarde solo ordena los datos nuevos

- **Situación:** una tabla grande y sin clustering se vuelve cara; alguien le agrega clustering con `bq update --clustering_fields`.
- **Qué pasó:** las consultas sobre la historia siguieron costando lo mismo.
- **Por qué:** al convertir una tabla existente en clusterizada, los datos existentes **no** se reorganizan; solo los datos nuevos entran al reclustering automático ([Clustered tables](https://docs.cloud.google.com/bigquery/docs/clustered-tables)).
- **Qué hacer:** reescribir la historia: crear una tabla nueva con `CREATE TABLE ... PARTITION BY ... CLUSTER BY ... AS SELECT` y hacer el cambio, o correr un `UPDATE ... SET col = col WHERE true` ([Modify clustering](https://docs.cloud.google.com/bigquery/docs/manage-clustered-tables)). Ambos procesan la tabla completa: estima el costo antes. Mejor aún, define partición y clustering desde el diseño.

### 5. LOGICAL vs PHYSICAL depende de cómo escribes

- **Situación:** se cambió un dataset al modelo de facturación PHYSICAL (bytes comprimidos) porque "comprime mucho y sale más barato".
- **Qué pasó:** en algunos datasets el costo de almacenamiento subió.
- **Por qué:** con PHYSICAL se paga aparte el *time travel* y el *fail-safe*; con LOGICAL están incluidos en la tarifa ([Time travel y fail-safe](https://docs.cloud.google.com/bigquery/docs/time-travel)). Las tablas que se reescriben completas cada día (`CREATE OR REPLACE`, `WRITE_TRUNCATE`) dejan en time travel y fail-safe una copia de lo reemplazado, día tras día.
- **Qué hacer:** decidir **por dataset**, que es donde se configura, mirando el patrón de escritura y los bytes de `TIME_TRAVEL_PHYSICAL_BYTES` y `FAIL_SAFE_PHYSICAL_BYTES` en `INFORMATION_SCHEMA.TABLE_STORAGE`. Separa las tablas que se recargan completas de las que solo crecen. Ten en cuenta que, después de cambiar de modelo, hay que esperar 14 días para volver a cambiar ([Datasets](https://docs.cloud.google.com/bigquery/docs/datasets-intro)). En PHYSICAL, acortar la ventana de time travel (mínimo 2 días) también reduce costo.

### 6. El dry-run no te dice cuánto cobra un DML

- **Situación:** un `MERGE` diario sobre una tabla de hechos particionada se validó con dry-run y parecía barato.
- **Qué pasó:** la factura real del job fue mucho mayor que la estimación.
- **Por qué:** en on-demand, un `UPDATE`, `DELETE` o `MERGE` con cláusula de actualización cobra lo que lee **más el tamaño total, con todas sus columnas, de las particiones que modifica** ([DML: on-demand query size](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax)). Qué particiones toca un `MERGE` depende de los datos que llegan, y eso se sabe al ejecutar.
- **Qué hacer:** medir con `total_bytes_billed` en `INFORMATION_SCHEMA.JOBS`, no con el dry-run. Acotar el destino con un filtro de partición en la condición del `MERGE`. Cuando se reemplaza un día completo, usar un `DELETE` de la partición entera (BigQuery puede borrar particiones completas sin escanear) seguido de un `INSERT`, dentro de una transacción ([DML en tablas particionadas](https://docs.cloud.google.com/bigquery/docs/using-dml-with-partitioned-tables)).

### 7. Composer cobra las 24 horas

- **Situación:** cada ambiente (dev, qa y prod) tenía su entorno de Composer del mismo tamaño que prod, encendido todo el tiempo.
- **Qué pasó:** los entornos de dev y qa costaban casi lo mismo que prod, aunque corrían una fracción de los DAGs y solo en horario laboral.
- **Por qué:** Composer se cobra por la capacidad aprovisionada del entorno, se use o no ([Workflows vs Managed Airflow](https://docs.cloud.google.com/workflows/docs/choose-orchestration)).
- **Qué hacer:** dimensionar por **tareas concurrentes** reales, no por número de DAGs: los presets de Composer 3 se eligen por DAGs totales, DAG runs concurrentes y tareas concurrentes ([Optimize environments](https://docs.cloud.google.com/composer/docs/composer-3/optimize-environments)). En dev, usar el entorno local (`composer-dev`) o crear el entorno con Terraform al empezar el día y destruirlo al terminar. Revisar los mínimos de workers.

### 8. Dataflow streaming que loguea cada mensaje

- **Situación:** un pipeline streaming escribía un log `INFO` por cada mensaje procesado "para depurar".
- **Qué pasó:** la factura de Cloud Logging superó a la del propio Dataflow.
- **Por qué:** Cloud Logging cobra por volumen ingerido, y un streaming procesa mensajes sin parar. La documentación de Dataflow desaconseja loguear métricas por elemento en pipelines de alto volumen ([Optimize costs](https://docs.cloud.google.com/dataflow/docs/optimize-costs)).
- **Qué hacer:** loguear hitos y errores, no elementos. Usar **métricas de Beam** (contadores) para contar procesados y rechazados. Agregar un filtro de exclusión para severidades bajas, con una vía de escape para depurar, como un sufijo `debug` en el nombre del job ([Filter Dataflow logs](https://docs.cloud.google.com/dataflow/docs/guides/filter-logs)).

### 9. Antes de mantener un pipeline caro, confirma que alguien lo lee

- **Situación:** un pipeline costoso alimentaba cada día una tabla "crítica" que nadie recordaba haber pedido.
- **Qué pasó:** al revisar quién la leía, resultó que solo la leía el propio pipeline.
- **Por qué:** los pipelines se crean por un pedido puntual y nunca se apagan; nadie revisa el uso.
- **Qué hacer:** consultar los **audit logs de Data Access** de BigQuery (eventos `TableDataRead`), que vienen activos por defecto ([BigQuery audit logs](https://docs.cloud.google.com/bigquery/docs/reference/auditlogs)), y cruzarlos con `referenced_tables` en `INFORMATION_SCHEMA.JOBS`, porque las lecturas desde caché no generan `TableDataRead`. Si nadie la lee en un periodo razonable, avisar a los posibles dueños, pausar y, después de un tiempo prudente, borrar. Primero se pausa; se borra al final.

### 10. Una suscripción de Pub/Sub atrasada descarta mensajes en silencio

- **Situación:** el consumidor de una suscripción estuvo caído varios días y nadie lo notó.
- **Qué pasó:** al levantarlo, faltaban los mensajes más viejos. No hubo error: simplemente no estaban.
- **Por qué:** una suscripción retiene los mensajes sin confirmar durante su *message retention duration* (por defecto 7 días; máximo 31). Pasado ese tiempo, Pub/Sub puede descartarlos sin importar si se confirmaron ([Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)). Además, una suscripción sin actividad expira (por defecto, a los 31 días).
- **Qué hacer:** alertar sobre la antigüedad del mensaje más viejo sin confirmar (`subscription/oldest_unacked_message_age_by_region`) con un umbral muy por debajo de la retención ([Monitor Pub/Sub](https://docs.cloud.google.com/pubsub/docs/monitoring)); configurar dead-letter topic; activar retención en el topic si necesitas reprocesar. Ten presente que retener mensajes sin confirmar más de un día tiene costo de almacenamiento.

### 11. Soft delete en buckets temporales cobra lo que ya borraste

- **Situación:** el bucket de staging de Dataflow y el de archivos temporales se reescribían constantemente.
- **Qué pasó:** el almacenamiento facturado era muy superior a lo que se veía en el bucket.
- **Por qué:** el soft delete viene activo por defecto con 7 días de retención; los objetos borrados o sobrescritos siguen cobrando almacenamiento hasta que vence ([Soft delete](https://docs.cloud.google.com/storage/docs/soft-delete)). La propia documentación advierte que en buckets de datos temporales puede aumentar mucho los costos.
- **Qué hacer:** desactivar el soft delete (retención 0) en los buckets **temporales**, como `${PROJECT_ID}-temp`, y mantenerlo en landing y archive, donde protege contra borrados accidentales. Configurarlo en Terraform, no a mano.

### 12. El lifecycle hecho por scripts compite con Terraform; los temporales se borran, no se archivan

- **Situación:** las reglas de lifecycle se aplicaban con un script aparte, mientras los buckets estaban en Terraform. Además, una regla movía los temporales a Archive "para ahorrar".
- **Qué pasó:** cada `terraform apply` borraba las reglas del script, porque el código no las tenía. Y los temporales en Archive generaban cargos por borrado anticipado.
- **Por qué:** Terraform revierte cualquier configuración que no esté en el código (drift). Archive tiene una duración mínima de 365 días (Coldline 90, Nearline 30): borrar antes se cobra igual ([Storage classes](https://docs.cloud.google.com/storage/docs/storage-classes)).
- **Qué hacer:** el lifecycle vive en el recurso `google_storage_bucket` (bloque `lifecycle_rule`). Los temporales se **borran** con una regla `Delete` por edad; solo se cambia de clase lo que de verdad se guarda mucho tiempo y casi no se lee, como los originales en archive ([Object Lifecycle Management](https://docs.cloud.google.com/storage/docs/lifecycle)).

### 13. Scans de calidad que nadie lee

- **Situación:** se activaron scans de calidad y de perfilado en muchas tablas, con reglas genéricas por columna (no nulos y rangos en todo), muestreo al 100 % y frecuencia diaria.
- **Qué pasó:** el cargo de procesamiento premium se volvió una línea importante de la factura, y casi nadie abría los resultados.
- **Por qué:** cada scan procesa datos y se cobra por DCU ([Knowledge Catalog pricing](https://cloud.google.com/products/knowledge-catalog/pricing)). Muchas reglas, por muchas columnas, sobre muchas tablas, todos los días, se multiplican.
- **Qué hacer:** definir reglas solo donde una falla dispara una acción; usar alcance incremental, muestreo y filtros de filas ([Auto data quality](https://docs.cloud.google.com/knowledge-catalog/docs/auto-data-quality-overview)); bajar la frecuencia; atribuir el costo por scan con las etiquetas `goog-dataplex-datascan-*` del billing export ([Monitor DCU costs](https://docs.cloud.google.com/knowledge-catalog/docs/monitoring)); y preferir assertions de Dataform en las tablas que ya controlas.

### 14. El linaje cobra por cada job del proyecto

- **Situación:** la Data Lineage API se activó en todos los proyectos, incluidos los de desarrollo, "para tener visibilidad".
- **Qué pasó:** apareció un cargo diario de procesamiento premium. Alguien apagó la API de Dataplex y el cargo siguió.
- **Por qué:** el linaje se activa **por proyecto** y registra los jobs de todos los servicios compatibles; se cobra en el SKU premium y depende de su propia API ([About data lineage](https://docs.cloud.google.com/knowledge-catalog/docs/about-data-lineage)).
- **Qué hacer:** activarlo solo donde alguien lo consulta (normalmente prod) y deshabilitar la Data Lineage API en el resto. Identificar el cargo con la etiqueta `goog-dataplex-workload-type = LINEAGE` ([Troubleshoot lineage](https://docs.cloud.google.com/knowledge-catalog/docs/troubleshooting-lineage)).

### 15. Llaves JSON de service account en la CI

- **Situación:** la CI se autenticaba con una llave JSON guardada como secret desde hacía años.
- **Qué pasó:** nadie sabía quién la había creado ni dónde más estaba copiada, y rotarla implicaba romper pipelines.
- **Por qué:** las llaves de SA son credenciales de larga vida que no expiran por defecto, se filtran con facilidad y en los audit logs no permiten saber quién las usó ([Managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)).
- **Qué hacer:** reemplazarlas por Workload Identity Federation, con la condición de atributos por IDs numéricos de owner y repo ([WIF con pipelines](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)); borrar la llave vieja y bloquear la creación de llaves con la política de organización. Detalle en `10-cicd-terraform.md`.

### 16. Imagen `latest` sin fijar

- **Situación:** un Cloud Run job y un Flex Template referenciaban `imagen:latest`.
- **Qué pasó:** un día el job empezó a fallar sin que nadie hubiera tocado el código del pipeline; otra rama había publicado una imagen con el mismo tag.
- **Por qué:** un tag es una etiqueta móvil; `latest` apunta a lo último que se publicó, venga de donde venga. No hay forma de saber qué versión corría ayer.
- **Qué hacer:** etiquetar las imágenes con el SHA del commit, desplegar referenciando el tag o, mejor, el digest (`@sha256:...`), y fijar por digest las imágenes base del `Dockerfile`. Así, volver a la versión anterior es cambiar una referencia.

### 17. Un DAG que hace I/O al parsearse

- **Situación:** un DAG leía archivos SQL desde GCS y variables de Airflow en el nivel superior del archivo, y construía tareas con `eval()` sobre texto de configuración.
- **Qué pasó:** el scheduler tardaba cada vez más en parsear, las tareas se retrasaban y un cambio en la configuración rompió todos los DAGs de ese archivo.
- **Por qué:** Airflow vuelve a parsear los archivos de DAG continuamente; el código de nivel superior se ejecuta en cada parseo. Las lecturas de red y de variables ahí multiplican el tiempo de parseo y la carga de la base de datos ([Write DAGs](https://docs.cloud.google.com/composer/docs/composer-3/write-dags), [Debug scheduling issues](https://docs.cloud.google.com/composer/docs/composer-3/debug-task-scheduling-issues)). `eval()` sobre texto externo, además, ejecuta código arbitrario.
- **Qué hacer:** que el nivel superior solo **declare** el DAG. Leer valores en tiempo de ejecución con plantillas Jinja (`{{ var.value.x }}`, `{{ ds }}`); poner el SQL en archivos dentro del repo, junto a los DAGs; parsear configuración con `yaml.safe_load`, nunca con `eval()`. Vigilar el tiempo de parseo en el dashboard de monitoreo.

### 18. Sin labels no se puede atribuir costo

- **Situación:** la factura de BigQuery y Dataflow subió y nadie podía decir qué pipeline la subió.
- **Qué pasó:** se perdieron días cruzando nombres de jobs y horarios para adivinar.
- **Por qué:** sin etiquetas, el billing export solo sabe de proyecto, servicio y SKU.
- **Qué hacer:** poner `labels` estándar (`pipeline`, `layer`, `env`, `owner`) en los jobs de BigQuery ([Adding labels](https://docs.cloud.google.com/bigquery/docs/adding-labels)), en los jobs de Dataflow (la opción `labels` llega al billing export, [Pipeline options](https://docs.cloud.google.com/dataflow/docs/reference/pipeline-options)) y en los recursos de Terraform. Hacerlo obligatorio en la revisión de PRs.

## Patrones que se repiten

Si lees las 18 juntas, aparecen cuatro ideas:
1. **Medir antes de optimizar:** `total_bytes_billed`, billing export con labels y audit logs. El dry-run y la intuición no bastan.
2. **El costo escondido está en lo que corre siempre:** entornos encendidos, streaming, logs, scans, linaje, soft delete.
3. **Lo que no está en el código se pierde:** lifecycle por script, cambios en la consola, imágenes sin fijar.
4. **Apagar también es una decisión de ingeniería:** confirmar el uso, pausar, esperar y luego borrar.

## Autoevaluación

1. ¿Por qué `WHERE fecha >= (SELECT MAX(fecha) FROM t)` escanea toda la tabla y `WHERE fecha >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)` no?
<details><summary>Respuesta</summary>La poda necesita una expresión constante sobre la columna de partición. La subconsulta es dinámica y su valor se conoce al ejecutar; `CURRENT_DATE()` con aritmética constante sí se resuelve antes de leer.</details>

2. Agregaste clustering a una tabla de varios años y el costo de las consultas históricas no bajó. ¿Por qué y qué haces?
<details><summary>Respuesta</summary>Porque el clustering agregado tarde solo aplica a los datos nuevos. Hay que reescribir la historia (CTAS con `CLUSTER BY` e intercambio de tablas, o `UPDATE ... SET col = col WHERE true`), estimando antes el costo de esa reescritura.</details>

3. ¿Por qué un `MERGE` puede costar mucho más de lo que estimó el dry-run?
<details><summary>Respuesta</summary>Porque con una cláusula `UPDATE` o `DELETE` se cobra también el tamaño completo, con todas las columnas, de las particiones que se modifican, y qué particiones se tocan depende de los datos que llegan. Se mide con `total_bytes_billed` y se acota con filtros de partición en la condición del `MERGE`.</details>

4. ¿En qué buckets del lab desactivarías el soft delete y en cuáles no?
<details><summary>Respuesta</summary>Se desactiva en `-temp`, que se reescribe constantemente y cuyo contenido es desechable. Se mantiene en `-landing` y `-archive`, donde protege los originales contra borrados accidentales.</details>

5. Un consumidor de Pub/Sub estuvo caído 10 días con la retención por defecto. ¿Qué perdiste y qué alerta lo habría evitado?
<details><summary>Respuesta</summary>Los mensajes con más de 7 días sin confirmar pudieron descartarse. Una alerta sobre `oldest_unacked_message_age_by_region` con un umbral de horas, no de días, lo habría detectado a tiempo.</details>

6. ¿Qué tienen en común las lecciones 7, 8, 13 y 14?
<details><summary>Respuesta</summary>Son costos de cosas que corren todo el tiempo o en todo el proyecto aunque nadie las use: un entorno encendido, logs por mensaje, scans diarios y linaje en todos los proyectos. Se controlan con dimensionamiento, intención y medición en el billing export.</details>

7. *(English)* Tell, in four sentences, the story of lesson 9 as if it happened in a project you worked on.
<details><summary>Respuesta</summary>Ejemplo: "We had an expensive daily pipeline feeding a table that everybody assumed was critical. Before optimizing it, I checked the BigQuery Data Access audit logs and the referenced tables in INFORMATION_SCHEMA.JOBS. The only reader was the pipeline itself. We notified the possible owners, paused it for a few weeks with no complaints, and then removed it." Cuenta solo lo que de verdad hiciste; si es del lab, dilo.</details>

## Para profundizar

- BigQuery: [Query partitioned tables](https://docs.cloud.google.com/bigquery/docs/querying-partitioned-tables) · [Clustered tables](https://docs.cloud.google.com/bigquery/docs/clustered-tables) · [Time travel y fail-safe](https://docs.cloud.google.com/bigquery/docs/time-travel) · [DML syntax y costo](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax) · [INFORMATION_SCHEMA.JOBS](https://docs.cloud.google.com/bigquery/docs/information-schema-jobs)
- Composer: [Optimize environments](https://docs.cloud.google.com/composer/docs/composer-3/optimize-environments) · [Write DAGs](https://docs.cloud.google.com/composer/docs/composer-3/write-dags)
- Dataflow: [Optimize costs](https://docs.cloud.google.com/dataflow/docs/optimize-costs) · [Filter logs](https://docs.cloud.google.com/dataflow/docs/guides/filter-logs)
- Pub/Sub: [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring)
- Cloud Storage: [Soft delete](https://docs.cloud.google.com/storage/docs/soft-delete) · [Storage classes](https://docs.cloud.google.com/storage/docs/storage-classes) · [Lifecycle](https://docs.cloud.google.com/storage/docs/lifecycle)
- Knowledge Catalog: [About data lineage](https://docs.cloud.google.com/knowledge-catalog/docs/about-data-lineage) · [Monitor DCU costs](https://docs.cloud.google.com/knowledge-catalog/docs/monitoring)
- IAM: [WIF con pipelines](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
