# Lab 06 · Airflow: orquestar todo, primero en local y después en Composer

**Objetivo:** correr el DAG `sellout_daily`, que une todo lo anterior:

```
generate_feed (Cloud Run Job) → wait_for_feed (sensor GCS, deferrable)
   → load_*_snapshot (BigQuery load) + run_dataflow (Flex Template)
   → control_figures (gate de conteos) → dataform_compile → dataform_invoke → wait_dataform → archive_files
```

Primero lo corres en **tu laptop**, con la misma imagen que usa Composer (`composer-dev`, $0). Después, en una **sesión corta** de Composer 3 real, que **se borra** al terminar.

**Tiempo:** ~4 h + ~2 h · **Costo:** ~$0.20 local (los Dataflow que dispara) + Composer 3 Small, unos dólares por hora: confírmalo en la [calculadora](https://cloud.google.com/products/calculator) antes de crearlo · **Docs:** [`08-orquestacion-airflow`](../../docs/08-orquestacion-airflow.md)

## Antes de empezar
Necesitas tener hecho:
- **lab04:** el job `sellout-generator`;
- **lab05:** el spec `gs://$TEMP_BUCKET/templates/sellout_ingest.json`;
- **lab03, paso 7:** el repositorio de Dataform `sellout-dataform`, con tu código en `main` de GitHub.

## Parte A · Airflow local con `composer-dev`
```bash
source .env.lab && scripts/preflight.sh
```

### A1. Instalar la herramienta (versión fija)
```bash
uv tool install --python 3.11 "git+https://github.com/GoogleCloudPlatform/composer-local-dev.git@0.12.0"
composer-dev --help
```

### A2. Crear el entorno local con la imagen exacta de Composer
```bash
composer-dev create lab-local --from-image-version composer-3-airflow-3.3.1-build.5 \
  --project "$PROJECT_ID" --port 8081 --dags-path orchestration/dags
python3 -c 'import os;print(os.path.expandvars(open("labs/lab06-airflow-composer/variables.env.example").read()))' \
  > composer/lab-local/variables.env
```
- La imagen es `linux/amd64`. En Apple Silicon corre emulada: activa Rosetta en Docker Desktop.
- Si arranca lento, sube `memory_limit` (p. ej. `"8g"`) y `cpu_count` (p. ej. `4`) en `composer/lab-local/config.json`.

### A3. Arrancar
```bash
composer-dev start lab-local          # la primera vez descarga la imagen (varios GB)
```
Abre <http://localhost:8081>. El DAG `sellout_daily` debe aparecer sin errores de import.

### A4. Una corrida
En Airflow 3, una corrida manual **sin** fecha lógica deja `{{ ds }}` vacío. Pasa siempre la fecha:
```bash
composer-dev run-airflow-cmd lab-local dags trigger sellout_daily --logical-date 2026-11-04T06:00:00+00:00
```
Mírala en la UI (Grid → la corrida → cada tarea → Logs). Cuando termine:
```bash
bq query --nouse_legacy_sql "SELECT * FROM ops.control_figures ORDER BY checked_at DESC LIMIT 5"
bq query --nouse_legacy_sql "SELECT sale_date, SUM(units) units, SUM(net_sales) sales
  FROM marts.fct_sellout_daily GROUP BY 1 ORDER BY 1"
gcloud storage ls "gs://$ARCHIVE_BUCKET/sellout/"
```

### A5. Backfill de 3 días
En Airflow 3 el backfill lo ejecuta el scheduler. Con `max_active_runs=1`, las fechas corren **en orden**: el SCD2 lo necesita.
```bash
composer-dev run-airflow-cmd lab-local backfill create --dag-id sellout_daily \
  --from-date 2026-11-05 --to-date 2026-11-07
```

### A6. Idempotencia: re-correr no duplica
Anota primero las unidades del 2026-11-05 en `fct_sellout_daily` y la fila de `ops.control_figures`.
```bash
composer-dev run-airflow-cmd lab-local tasks clear sellout_daily --start-date 2026-11-05 --end-date 2026-11-05 --yes
```
Cuando termine, compara: las unidades son **las mismas**, y `control_figures` tiene una fila nueva con los **mismos** conteos.

### A7. Apagar
```bash
composer-dev stop lab-local
```

## Parte B · Composer 3 real (una sola sesión, ≤ 2 h, y se borra)
> **Costo:** Composer cobra **mientras existe**, corra o no corra DAGs. No lo dejes prendido de un día para otro. Agenda el borrado antes de crearlo.

### B1. Service account de Composer
```bash
labs/lab06-airflow-composer/iam.sh
```

### B2. Crear el entorno (~25 min), dimensionado al mínimo
```bash
gcloud composer environments create lab-composer --location "$REGION" \
  --image-version composer-3-airflow-3.3.1-build.5 --environment-size small \
  --service-account "$SA_COMPOSER" \
  --env-variables "LAB_PROJECT_ID=$PROJECT_ID,LAB_REGION=$REGION,LAB_LANDING_BUCKET=$LANDING_BUCKET,LAB_ARCHIVE_BUCKET=$ARCHIVE_BUCKET,LAB_TEMP_BUCKET=$TEMP_BUCKET" \
  --scheduler-cpu 0.5 --scheduler-memory 2 --scheduler-storage 1 --scheduler-count 1 \
  --triggerer-cpu 0.5 --triggerer-memory 1 --triggerer-count 1 \
  --dag-processor-cpu 0.5 --dag-processor-memory 2 --dag-processor-storage 1 --dag-processor-count 1 \
  --web-server-cpu 0.5 --web-server-memory 2 --web-server-storage 1 \
  --worker-cpu 0.5 --worker-memory 2 --worker-storage 1 --min-workers 1 --max-workers 2
```

### B3. Desplegar el DAG y correrlo
```bash
gcloud composer environments storage dags import --environment lab-composer --location "$REGION" \
  --source orchestration/dags/sellout_daily.py
gcloud composer environments describe lab-composer --location "$REGION" --format="value(config.airflowUri)"
gcloud composer environments run lab-composer --location "$REGION" dags trigger -- \
  sellout_daily --logical-date 2026-11-08T06:00:00+00:00
```
Mira la corrida en la UI de Airflow (el link del `describe`). Fíjate en que las tareas ahora corren como `sa-composer`, no como tú.

### B4. Borrar el entorno **y su bucket** (Composer no borra el bucket)
```bash
BUCKET=$(gcloud composer environments describe lab-composer --location "$REGION" --format="value(config.dagGcsPrefix)" | cut -d/ -f3)
gcloud composer environments delete lab-composer --location "$REGION" --quiet
gcloud storage rm -r "gs://$BUCKET"
gcloud composer environments list --locations "$REGION"   # debe salir vacío
```

## Checkpoint
- En `ops.control_figures` hay una fila `OK` por cada fecha: 2026-11-04 a 2026-11-08.
- `fct_sellout_daily` tiene esas fechas, y re-correr una no cambia sus unidades.
- `assert_sellout_reconciles` pasó en cada corrida (míralo en el log de `wait_dataform` o en Dataform → Workflow execution logs).
- No queda ningún entorno de Composer.

## Preguntas
1. ¿Por qué `control_figures` va **antes** de Dataform y no al final?
2. ¿Qué diferencia hay entre un sensor `deferrable` y uno en `mode="reschedule"`? ¿Y cuál es el problema de `poke` normal?
3. Llegan los archivos de un retailer 3 horas tarde. ¿Qué pasa en el DAG y cómo lo harías más robusto?
4. Un analista te pide reprocesar octubre completo. ¿Qué comando usas y por qué importa `max_active_runs=1` aquí?
5. (EN) *Walk me through what happens when the Dataflow step fails on the second retry.*
