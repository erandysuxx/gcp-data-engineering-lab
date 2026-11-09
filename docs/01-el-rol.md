# El rol: GCP Data Engineer mid-level en L'Oréal

> Qué hace un Data Engineer en el equipo Data & AI (Commerce, Supply Chain y datos de sell-out), qué puedes dejar fuera del estudio, cómo se mapea cada requisito del job description a esta guía y el vocabulario de negocio que te van a preguntar. **Lab relacionado:** todos; empieza por `labs/lab00-setup`.

## Qué hace un Data Engineer en este puesto

Construye y opera los caminos por los que los datos llegan de sus fuentes (e-commerce, ERP, feeds de retailers) a BigQuery, ya limpios, modelados y con su costo bajo control. En el día a día:

- **Ingesta**: archivos de retailers, extracciones de sistemas y APIs hacia Cloud Storage y BigQuery.
- **Transformación**: SQL (Dataform o dbt) para casi todo; Python o Beam cuando SQL no alcanza.
- **Modelado**: hechos y dimensiones con un grano declarado, listos para BI.
- **Orquestación**: DAGs de Airflow con reintentos, backfills e idempotencia.
- **Calidad y observabilidad**: assertions, cifras de control, linaje y alertas.
- **Operación**: permisos, costo, incidentes, CI/CD e infraestructura como código.
- **Conversación con negocio**: acordar qué significa "sell-through" o "a tiempo" antes de escribir una línea.

Lo anterior sale del job description. En la entrevista, pregunta cómo se reparte el trabajo con analytics engineering y con la plataforma.

## Qué no necesitas estudiar

| Tema | Por qué queda fuera | Lo mínimo que sí debes saber |
|---|---|---|
| Data science y modelos de ML | Lo hace el data scientist | Entregarle tablas con grano claro, histórico completo y fechas confiables |
| MLOps | Lo hace el ML engineer | Que sus pipelines consumen tus tablas y necesitan que no cambien sin aviso |
| Redes, VPC, *org policies* | Lo hace el equipo de plataforma | Que pueden bloquearte (IP privada, perímetros, prohibición de llaves) y a quién pedirle |
| Diseño de dashboards | Lo hace BI | Entregar marts con métricas definidas; Looker es la fase 2 de esta guía |
| Administración de bases de datos (DBA) | Lo hace el dueño del sistema fuente | Extraer sin tumbar la fuente (réplica, ventanas, CDC) y que BigQuery no es una base transaccional |

## Roles vecinos

| Rol | Qué entrega | Herramientas típicas | Dónde se cruza contigo |
|---|---|---|---|
| **Data Engineer** (tú) | Pipelines confiables de raw a marts, costo y calidad | BigQuery, Dataflow, Airflow, Dataform, Terraform | — |
| Analytics engineer | Modelos SQL de negocio, tests y documentación | dbt o Dataform, SQL | Comparten los marts: tú garantizas raw y staging, él define métricas |
| BI developer | Dashboards, capa semántica y reportes | Looker (LookML), Data Studio | Consume tus marts; te pide grano correcto y queries rápidas |
| Data scientist | Análisis y modelos predictivos | Python, notebooks, SQL | Consume tus tablas; te pide histórico y consistencia |
| ML engineer | Modelos en producción y su monitoreo | Plataformas de ML, pipelines | Mismo tipo de pipelines, otro producto final |
| Platform / SRE | Proyectos, red, seguridad, CI/CD compartido, confiabilidad | Terraform, IAM, VPC, monitoring | Te da proyectos y permisos; tú le pides accesos y le reportas incidentes |

## Mapa del job description a esta guía

| Requisito del JD | Docs | Labs |
|---|---|---|
| Pipelines de datos en GCP | [02](02-fundamentos-gcp.md), [07](07-cloud-run-functions.md), [08](08-orquestacion-airflow.md), [11](11-guia-de-decisiones.md) | `lab04-cloud-run-job`, `lab05-dataflow-beam`, `lab06-airflow-composer` |
| ETL/ELT batch y near-real-time | [06](06-dataflow-beam.md), [08](08-orquestacion-airflow.md), [11](11-guia-de-decisiones.md) | `lab05-dataflow-beam`, `lab06-airflow-composer` (near-real-time solo en teoría) |
| SQL y Python | [04](04-bigquery.md), [05](05-modelado-dimensional.md), [06](06-dataflow-beam.md) | `lab02-bigquery`, `lab03-modelado-dataform`, `lab04-cloud-run-job`, `lab05-dataflow-beam` |
| Modelos dimensionales (estrella y copo de nieve) | [05](05-modelado-dimensional.md) | `lab03-modelado-dataform` |
| BigQuery: performance, partitioning, clustering, control de acceso | [04](04-bigquery.md) | `lab02-bigquery` |
| Looker (fase 2) | [13](13-nombres-2026.md) para no confundirlo con Data Studio | `lab08-looker` (fase 2) |
| Calidad, linaje y observabilidad | [09](09-calidad-linaje-observabilidad.md) | `lab03-modelado-dataform`, `lab06-airflow-composer` |
| Agile | Este doc, sección [Agile](#agile-en-este-rol) | Todos: cada lab es una historia partida en tareas |
| CI/CD | [10](10-cicd-terraform.md) | `lab07-cicd-terraform` |
| Plus: Terraform, Docker, Cloud Run | [07](07-cloud-run-functions.md), [10](10-cicd-terraform.md) | `lab04-cloud-run-job`, `lab07-cicd-terraform` |

Para la entrevista en inglés, ve a `docs/interview/`. Los errores reales que más se repiten están en [12-lecciones-de-produccion](12-lecciones-de-produccion.md).

## Contexto de dominio

### Commerce vs Supply Chain

| | Commerce | Supply Chain |
|---|---|---|
| Pregunta central | ¿Cuánto vendemos, a quién, por qué canal, a qué precio? | ¿Está el producto correcto, en el lugar correcto, a tiempo y al menor costo? |
| Datos típicos | Pedidos de e-commerce, precios, promociones, sell-in, sell-out | Pedidos de reposición, inventario, envíos, entregas, forecast |
| Métricas | Ventas netas, unidades, ticket promedio, sell-through | OTIF, lead time, cobertura de inventario |
| En el lab | Olist (orders, order_items, payments) y el feed de sell-out | Fechas estimada y real de entrega de Olist |

### Sell-in, sell-out y sell-through

- **Sell-in**: lo que la marca le vende al retailer o distribuidor. Está en el ERP de la marca (sus facturas).
- **Sell-out**: lo que el retailer le vende al consumidor final (los tickets de caja). Lo tiene el retailer; la marca lo recibe en feeds.
- **Sell-through**: qué parte de lo disponible en el retailer llegó al consumidor en un periodo. La definición más común es `sell-out / (inventario inicial + sell-in del periodo)`; hay equipos que lo calculan solo sobre lo recibido. Acuerda una y documéntala.

Ejemplo de un mes retail de 4 semanas para un SKU en una cadena:

| Concepto | Unidades |
|---|---|
| Inventario del retailer al inicio | 200 |
| Sell-in del mes (marca → retailer) | 1,000 |
| Sell-out del mes (retailer → consumidor) | 700 |
| Inventario al cierre | 200 + 1,000 − 700 = **500** |
| Sell-through | 700 / (200 + 1,000) = **58.3 %** |
| Venta semanal promedio | 700 / 4 = 175 |
| Cobertura al cierre | 500 / 175 ≈ **2.9 semanas** |

Lectura: el reporte de la marca muestra un buen mes (1,000 unidades de sell-in), pero el retailer se quedó con casi tres semanas de inventario. Si el sell-out no sube, el próximo pedido baja. Por eso Commerce y Supply Chain miran el sell-out: es la demanda real, y la base del forecast y de la reposición.

### Por qué el sell-out llega con calidad variable

El sell-out no lo produce la marca: lo manda cada retailer, a su manera.

- **Formato y canal propios**: CSV o Excel por SFTP o correo, EDI, portales, APIs.
- **Códigos propios**: EAN, UPC o el código interno del retailer; a veces solo una descripción.
- **Calendario propio**: semanas de domingo a sábado o de lunes a domingo, y sus propios códigos de tienda.
- **Correcciones tardías**: reenvían semanas pasadas (*restatements*), mandan duplicados o se saltan días y tiendas.
- **Valores raros**: cantidades negativas (devoluciones), montos con o sin impuestos, monedas distintas.
- **Cambios de esquema sin aviso**: una columna nueva o renombrada.

Cómo lo maneja el lab: el generador inyecta errores a propósito. El crudo aterriza tal cual en `gs://${PROJECT_ID}-landing/sellout/date=YYYY-MM-DD/`. Dataflow valida y manda lo inválido a `raw_sellout.sellout_rejects` (*dead-letter*) con el motivo. Las cifras de control (recibidas, cargadas, rechazadas) quedan en `ops.control_figures`. Reprocesar un día es idempotente.

### Calendario retail 4-4-5

Los meses calendario tienen distinto número de días y de fines de semana, así que comparar noviembre contra noviembre mezcla cuatro o cinco sábados. El retail usa semanas completas:

- Cada trimestre tiene 13 semanas: dos "meses" de 4 semanas y uno de 5 (4-4-5). Existen variantes 4-5-4 y 5-4-4.
- El año tiene 52 semanas (364 días). Cada pocos años se agrega una semana 53 para realinear con el calendario.
- "Semana 45 de este año contra semana 45 del año pasado" compara los mismos días de la semana.

En el modelo: una `dim_date` con `fiscal_year`, `fiscal_quarter`, `fiscal_period` y `fiscal_week`, contra la que se une cada hecho. Nunca calcules el mes retail con `EXTRACT(MONTH …)`. Si un retailer cierra semana en domingo y la marca en sábado, normaliza al calendario de la marca.

### Mapeo EAN/UPC → SKU

- **EAN-13** (13 dígitos) y **UPC-A** (12) son códigos de barras que identifican la unidad de venta en caja; ambos son GTIN. Un UPC-A se puede expresar como EAN-13 anteponiendo un cero.
- El **SKU** es el código interno de la marca. Cada retailer tiene, además, el suyo.
- La relación no es 1 a 1: un SKU puede tener varios EAN (cambio de empaque, país, kit promocional) y el mapeo cambia con el tiempo.

En el modelo: una tabla de mapeo con fechas de vigencia, códigos normalizados (sin espacios, con ceros a la izquierda) y guardados como `STRING`, nunca como número. Lo que no cruza no se descarta: va al **miembro desconocido** de la dimensión de producto (lab03) y su porcentaje es un indicador de calidad que se reporta.

### OTIF y lead time

- **OTIF** (*On Time In Full*): porcentaje de pedidos (o líneas) entregados **a tiempo y completos a la vez**. Ejemplo: de 100 pedidos, 90 llegaron a tiempo, 85 completos y 80 cumplieron ambas cosas: OTIF = **80 %**, no 90 × 85 %. Antes de calcular, acuerda la unidad (pedido, línea o unidades), contra qué fecha se mide "a tiempo" y qué tolerancia aplica a "completo".
- **Lead time**: tiempo entre el pedido y la entrega. Se puede partir en tramos (aprobación, despacho, transporte) y conviene reportar la distribución (mediana, p90), no solo el promedio.

En el lab, Olist trae `order_purchase_timestamp`, `order_approved_at`, `order_delivered_carrier_date`, `order_delivered_customer_date` y `order_estimated_delivery_date`. "A tiempo" es entregar en o antes de la fecha estimada; el lead time es la diferencia entre compra y entrega. "Completo" no viene directo: se aproxima con `order_status`. En el lab03 todo esto vive en `fct_deliveries`, una *accumulating snapshot* (una fila por pedido que se actualiza con cada hito).

## Agile en este rol

La mayoría de los equipos de datos trabaja con Scrum o Kanban. Las ceremonias son cinco. En el *refinement* se aclaran historias y criterios de aceptación. En la *planning* el equipo se compromete con lo que cabe en el sprint. La *daily* dura 15 minutos y sirve para avances y bloqueos. En la *review* se muestran datos funcionando a quien los pidió. En la *retro* se mejora el proceso. Para un Data Engineer, "terminado" (*Definition of Done*) no es "la query corre en mi laptop": es en producción, con tests, documentado, monitoreado y con el costo revisado (dry-run y bytes facturados).

Una user story describe valor para alguien, no tecnología. Tu trabajo es partirla en tareas técnicas chicas (uno o dos días), verificables y entregables por separado, siguiendo el flujo del dato: contrato y landing, carga a raw, validación, modelo, calidad, orquestación y despliegue. Si una tarea no se puede demostrar en la review, está mal partida. Ejemplo con este lab:

> **Historia:** "Como analista de Supply Chain quiero ver el sell-out semanal por retailer y producto para compararlo contra el sell-in."
> **Criterios de aceptación:** datos al día siguiente antes de las 8:00; semanas en calendario 4-4-5; cifras de control cuadradas; un retailer no ve los datos de otro.

| Tarea técnica | Lab |
|---|---|
| Acordar el contrato del feed y crear el landing con `date=`, `_manifest.json` y `_SUCCESS` | `lab01-cloud-storage` |
| Generar el feed diario como Cloud Run job | `lab04-cloud-run-job` |
| Validar y cargar a `raw_sellout.sellout_lines` con dead-letter | `lab05-dataflow-beam` |
| Tabla particionada y con clustering; vista autorizada por retailer | `lab02-bigquery` |
| Staging, `dim_date` retail, dimensiones y hecho de sell-out con assertions | `lab03-modelado-dataform` |
| DAG diario con sensor, cifras de control y backfill de 3 días | `lab06-airflow-composer` |
| CI en el PR y despliegue con Terraform y WIF | `lab07-cicd-terraform` |

## Preguntas para practicar

1. Explica sell-in, sell-out y sell-through en dos frases y di cuál usa Supply Chain para reponer.
<details><summary>Respuesta</summary>

Sell-in es lo que la marca vende al retailer; sell-out, lo que el retailer vende al consumidor; sell-through, la proporción de lo disponible que se vendió. Para reponer y pronosticar se usa el sell-out, porque es la demanda real.
</details>

2. Con inventario inicial de 300, sell-in de 600 y sell-out de 450 en un mes de 4 semanas, ¿cuál es el sell-through y la cobertura al cierre?
<details><summary>Respuesta</summary>

Inventario final: 300 + 600 − 450 = 450. Sell-through: 450 / 900 = 50 %. Venta semanal: 450 / 4 = 112.5. Cobertura: 450 / 112.5 = 4 semanas.
</details>

3. ¿Por qué un retail usa semanas 4-4-5 en lugar de meses calendario?
<details><summary>Respuesta</summary>

Porque cada periodo tiene semanas completas y el mismo número de días de cada tipo. La comparación contra el año anterior es justa: la semana 45 contra la semana 45, sin mezclar cuatro o cinco fines de semana.
</details>

4. 30 % de las unidades de un retailer no cruzan con el maestro de productos. ¿Qué haces con esas filas?
<details><summary>Respuesta</summary>

No las borras. Las asignas al miembro desconocido de la dimensión, reportas el porcentaje como indicador de calidad y corriges el mapeo EAN → SKU. Así los totales siguen cuadrando con lo recibido.
</details>

5. ¿Qué tareas de un DE quedan fuera de este puesto y cuál es el mínimo que debes saber de cada una?
<details><summary>Respuesta</summary>

Data science, MLOps, redes y org policies, diseño de dashboards y administración de bases de datos. Lo mínimo: entregar tablas confiables a quien modela, saber que la red y las políticas pueden bloquearte y a quién escalar, entregar marts con métricas definidas a BI y extraer sin dañar la fuente.
</details>

## Para profundizar

- [02-fundamentos-gcp](02-fundamentos-gcp.md): proyectos, IAM y qué es un job en cada servicio.
- [05-modelado-dimensional](05-modelado-dimensional.md): grano, hechos, dimensiones y SCD.
- [11-guia-de-decisiones](11-guia-de-decisiones.md): qué herramienta usar en cada caso.
- [13-nombres-2026](13-nombres-2026.md): los nombres nuevos de Composer, Dataproc, Dataplex y Looker Studio.
- `docs/interview/`: preguntas y pitch en inglés.
