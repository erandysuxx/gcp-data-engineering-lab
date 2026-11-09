# Nombres de 2026: el viejo y el nuevo

> En abril de 2026 Google renombró varios productos de datos. El job description y muchos entrevistadores siguen usando los nombres viejos; la consola y la documentación ya usan los nuevos. Conviene saber los dos y decirlos juntos. **Lab relacionado:** `labs/lab06-airflow-composer` (Composer) y, en general, todos.

## Por qué importa

- El JD pide "Composer", "Dataproc", "Looker Studio" o "Dataplex". Si buscas esos nombres en la doc actual, vas a caer en páginas que dicen "Managed Airflow", "Managed Service for Apache Spark", "Data Studio" o "Knowledge Catalog".
- Lo que **casi nunca cambió** es lo técnico: los comandos `gcloud`, las APIs, las librerías y los roles de IAM conservan el nombre viejo. Tu código y tu Terraform siguen funcionando igual.
- En la entrevista, menciona los dos nombres una vez y sigue con el que use tu interlocutor. Muestra que estás al día sin corregir a nadie.

## Tabla de renombres (verificada en la doc oficial, nov-2026)

| Nombre viejo (el del JD) | Nombre nuevo | Desde | Qué **no** cambió | Fuente |
|---|---|---|---|---|
| Cloud Composer | **Managed Service for Apache Airflow** ("Managed Airflow"). Generaciones: Composer 1 → *Managed Airflow (Legacy Gen 1)*, Composer 2 → *Managed Airflow (Gen 2)*, Composer 3 → *Managed Airflow (Gen 3)* | 15-abr-2026 | `gcloud composer …`, roles `roles/composer.*`, nombres de imagen `composer-3-airflow-X.Y.Z-build.N` (la del lab: `composer-3-airflow-3.3.1-build.5`), la URL `/composer/docs` | [Release notes](https://docs.cloud.google.com/composer/docs/release-notes) · [Versiones](https://docs.cloud.google.com/composer/docs/composer-versioning-overview) |
| Dataproc (y Dataproc Serverless / Serverless for Apache Spark) | **Managed Service for Apache Spark** | 3-abr-2026 | La API de Dataproc, las librerías cliente, `gcloud dataproc …` y los nombres de roles y permisos de IAM | [Release notes](https://docs.cloud.google.com/managed-spark/docs/release-notes) |
| Dataplex / Dataplex Universal Catalog | **Knowledge Catalog** | 10-abr-2026 | `dataplex.googleapis.com`, `google-cloud-dataplex`, `gcloud dataplex …`, roles `roles/dataplex.*`. Los metadatos existentes migran solos | [Transición](https://docs.cloud.google.com/knowledge-catalog/docs/transition-dataplex-universal-catalog) · [Release notes](https://docs.cloud.google.com/knowledge-catalog/docs/release-notes) |
| Looker Studio | **Data Studio** (vuelve a su nombre original) | 16-abr-2026 | Los reportes no hay que tocarlos; `lookerstudio.google.com` redirige a `datastudio.google.com` | [Welcome](https://docs.cloud.google.com/data-studio/welcome) · [Release notes](https://docs.cloud.google.com/data-studio/release-notes) |
| Data Catalog | **En apagado gradual desde el 1-jun-2026.** Migrar a Knowledge Catalog | 1-jun-2026 | **Excepción:** el Policy Tag Manager (taxonomías y *policy tags*), sus métodos de `datacatalog.googleapis.com` y los roles `roles/datacatalog.*` **no** están deprecados. Son la base de la seguridad por columna y del *data masking* de BigQuery | [Release notes de Knowledge Catalog](https://docs.cloud.google.com/knowledge-catalog/docs/release-notes) · [Column-level security](https://docs.cloud.google.com/bigquery/docs/column-level-security-intro) |

Cuidado con dos confusiones frecuentes:

- **Looker no es Data Studio.** Looker (la plataforma con LookML y capa semántica, la del JD para la fase 2) **conserva su nombre**. Lo que cambió fue Looker Studio, el producto gratuito de reportes, que volvió a llamarse Data Studio. La página de Looker lo lista como "Data Studio (formerly Looker Studio)" ([fuente](https://cloud.google.com/looker-modeling)).
- **Knowledge Catalog tuvo varios nombres en poco tiempo.** En abril de 2025 "Dataplex Catalog" pasó a llamarse "BigQuery universal catalog"; después la doc usó "Dataplex Universal Catalog"; desde abril de 2026 es Knowledge Catalog. Si un entrevistador dice "Dataplex", habla de lo mismo.

## Otros cambios de nombre que vas a ver en la doc

No son de abril de 2026 (o la doc no da la fecha), pero aparecen en las páginas que vas a leer:

| Antes | Ahora | Nota | Fuente |
|---|---|---|---|
| *Streaming inserts* (`tabledata.insertAll`) | **Storage Write API (REST)** | La Storage Write API de siempre ahora se llama **Storage Write API (gRPC)** y es la recomendada para proyectos nuevos | [Storage Write API (REST)](https://docs.cloud.google.com/bigquery/docs/write-api-rest) |
| Roles básicos Owner / Editor / Viewer | **Roles básicos legacy** | Los básicos nuevos son Admin (`roles/admin`), Writer (`roles/writer`) y Reader (`roles/reader`). En producción no se usa ninguno de los dos juegos | [Roles de IAM](https://docs.cloud.google.com/iam/docs/roles-overview) |
| Analytics Hub | **BigQuery sharing** | Intercambio de datasets entre organizaciones | [Authorized views](https://docs.cloud.google.com/bigquery/docs/authorized-views) |
| Multi-región `US` / `EU` de BigQuery | Anunciado: dejarán de llamarse "multi-región" y aparecerán como regiones únicas, colocalizadas con `us-central1` y `europe-west4` | La doc lo anuncia "más adelante este año". Confirma el estado antes de citarlo | [Ubicaciones de BigQuery](https://docs.cloud.google.com/bigquery/docs/locations) |

Los servicios centrales de este lab (BigQuery, Cloud Storage, Dataflow, Dataform, Cloud Run, Cloud Scheduler) siguen con su nombre en la documentación consultada en noviembre de 2026.

## Cómo decirlo en la entrevista

Frases en inglés, listas para usar:

- "We'd orchestrate the daily load with **Composer, now Managed Service for Apache Airflow**, on Gen 3 with Airflow 3."
- "For data quality scans and lineage I'd use **Dataplex, which Google renamed Knowledge Catalog this year**; the API and IAM roles still say `dataplex`."
- "If the team needs Spark, **Dataproc, now Managed Service for Apache Spark**, but for this volume BigQuery SQL is enough."
- "The free dashboards were built in **Looker Studio, now Data Studio**; governed metrics would live in Looker with LookML."
- "Column-level security still uses **policy tags**; those weren't affected by the Data Catalog shutdown."

## Cómo buscar en la doc

- Busca con el nombre nuevo **y** el viejo. Muchas páginas de referencia (`gcloud`, REST, IAM) solo usan el viejo.
- En Terraform, los recursos tampoco cambiaron de nombre: `google_composer_environment`, `google_dataproc_cluster`, `google_dataplex_*`.
- Si un tutorial dice "Cloud Composer 3", es exactamente lo que el lab06 llama "Managed Airflow (Gen 3)".

## Autoevaluación

1. Un entrevistador te pregunta por "Cloud Composer 2". ¿Cómo se llama hoy y qué cambió en tus DAGs por el renombre?
<details><summary>Respuesta</summary>

Managed Airflow (Gen 2), dentro de Managed Service for Apache Airflow. El renombre no cambia nada técnico: siguen `gcloud composer`, los roles `roles/composer.*` y los nombres de imagen. Los DAGs no se tocan.
</details>

2. ¿Looker y Data Studio son el mismo producto?
<details><summary>Respuesta</summary>

No. Data Studio es el antiguo Looker Studio (reportes gratuitos). Looker es la plataforma de BI con LookML y capa semántica, y conserva su nombre.
</details>

3. Data Catalog está en apagado. ¿Se rompe el *data masking* de BigQuery que usa policy tags?
<details><summary>Respuesta</summary>

No. El Policy Tag Manager (taxonomías y policy tags), sus métodos de `datacatalog.googleapis.com` y los roles `roles/datacatalog.*` no están deprecados. La API `datacatalog.googleapis.com` debe seguir habilitada para administrarlos.
</details>

4. ¿Con qué comando `gcloud` administras hoy un data quality scan de Knowledge Catalog?
<details><summary>Respuesta</summary>

Con `gcloud dataplex …`. El CLI, la API (`dataplex.googleapis.com`) y los roles conservan el nombre Dataplex.
</details>

## Para profundizar

- [Managed Service for Apache Airflow: documentación](https://docs.cloud.google.com/composer/docs)
- [Managed Airflow: comparación de generaciones](https://docs.cloud.google.com/composer/docs/composer-versioning-overview)
- [Managed Service for Apache Spark: release notes](https://docs.cloud.google.com/managed-spark/docs/release-notes)
- [Knowledge Catalog: transición desde Dataplex Universal Catalog](https://docs.cloud.google.com/knowledge-catalog/docs/transition-dataplex-universal-catalog)
- [Data Studio: welcome](https://docs.cloud.google.com/data-studio/welcome)
- [Transición de Data Catalog a Knowledge Catalog](https://docs.cloud.google.com/knowledge-catalog/docs/transition-to-dataplex-catalog)
