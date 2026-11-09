# Lab 05 · Dataflow + Apache Beam: validar el feed y separar lo malo (dead-letter)

**Objetivo:** procesar el feed JSONL de cada día con un pipeline de Beam:
- parsear y validar contra el maestro de tiendas (*side input*);
- mandar las filas válidas a `raw_sellout.sellout_lines` y las malas, con la razón, a `raw_sellout.sellout_rejects`;
- correrlo primero en local, después en Dataflow y al final como **Flex Template**.

**Tiempo:** ~4 h · **Costo:** ~$0.10–0.30 (cada job chico tarda ~5 min, casi todo de arranque) · **Docs:** [`06-dataflow-beam`](../../docs/06-dataflow-beam.md)

## Conceptos en 1 minuto
- **Beam** es el modelo de programación (Pipeline, PCollection, PTransform). **Dataflow** es el servicio que lo ejecuta (runner).
- **El mismo código** corre con DirectRunner (tu laptop) o DataflowRunner (la nube).
- `ParseAndValidate` es un `DoFn` con dos salidas: la **principal** (válidas) y la **tagged output** `rejected`. Nada se pierde en silencio.
- **Idempotencia:** cada corrida escribe con `WRITE_TRUNCATE` sobre la partición `tabla$YYYYMMDD`. Re-correr un día **reemplaza** ese día; no duplica.

Código: [`pipelines/sellout_beam/`](../../pipelines/sellout_beam).

## Pasos
```bash
source .env.lab && scripts/preflight.sh
cd pipelines/sellout_beam && uv sync && cd ../..
```

### 1. Tests unitarios (sin nube)
```bash
(cd pipelines/sellout_beam && uv run pytest -q)
```
Lee `tests/test_transforms.py`: cada tipo de error tiene su `error_code`.

### 2. DirectRunner + archivos locales
```bash
(cd generator && uv run python -m sellout_gen.main --date 2026-11-01 \
   --products-csv ../data/olist/olist_products_dataset.csv --out ../out)
(cd pipelines/sellout_beam && uv run python -m sellout_beam.pipeline --run_date 2026-11-01 \
   --input_root ../../out --sink local --local_output_dir ../../out-beam)
cat out-beam/valid*.jsonl | wc -l; cat out-beam/rejected*.jsonl | wc -l
cat out/sellout/date=2026-11-01/_manifest.json     # ¿cuadran expected_valid_lines y expected_rejected_lines?
```

### 3. Permisos de los workers
```bash
labs/lab05-dataflow-beam/iam.sh
```

### 4. DataflowRunner (lanzado desde tu laptop)
```bash
(cd pipelines/sellout_beam && uv run python -m sellout_beam.pipeline --run_date 2026-11-01 \
  --input_root "gs://$LANDING_BUCKET" --sink bigquery --output_project "$PROJECT_ID" \
  --runner DataflowRunner --project "$PROJECT_ID" --region "$REGION" \
  --temp_location "gs://$TEMP_BUCKET/dataflow/tmp" --staging_location "gs://$TEMP_BUCKET/dataflow/staging" \
  --service_account_email "$SA_DATAFLOW" --max_num_workers 2 --machine_type e2-standard-2 \
  --setup_file ./setup.py --labels pipeline=sellout_daily)
```
- `--max_num_workers 2 --machine_type e2-standard-2`: dentro del límite de vCPU del free trial.
- `--setup_file`: empaqueta `sellout_beam` para que los workers lo instalen.

Mientras corre, abre **Dataflow → Jobs** en la consola. Mira el grafo (cada `>>` del código es un paso), los workers que se crean y el costo estimado.

### 5. Verifica con SQL (cifras de control a mano)
```bash
bq query --nouse_legacy_sql "
SELECT (SELECT COUNT(*) FROM raw_sellout.sellout_lines   WHERE sale_date = '2026-11-01') AS valid_rows,
       (SELECT COUNT(*) FROM raw_sellout.sellout_rejects WHERE feed_date = '2026-11-01') AS rejected_rows"
gcloud storage cat "gs://$LANDING_BUCKET/sellout/date=2026-11-01/_manifest.json" | grep -E 'total|expected'
bq query --nouse_legacy_sql "SELECT error_code, COUNT(*) FROM raw_sellout.sellout_rejects
  WHERE feed_date = '2026-11-01' GROUP BY 1 ORDER BY 2 DESC"
```

### 6. Flex Template: el pipeline como "producto" que cualquiera lanza con parámetros
Una **imagen** (launcher + tu código) y un **spec JSON** en GCS. Quien lo lanza (Airflow, tú, CI) no necesita tu código ni tu entorno de Python.
```bash
gcloud builds submit pipelines/sellout_beam --config pipelines/sellout_beam/cloudbuild.yaml \
  --substitutions _IMAGE="$IMAGE_PREFIX/sellout-beam:v1" --region "$REGION"   # construye en la nube (amd64), ~10 min
gcloud dataflow flex-template build "gs://$TEMP_BUCKET/templates/sellout_ingest.json" \
  --image "$IMAGE_PREFIX/sellout-beam:v1" --sdk-language PYTHON \
  --metadata-file pipelines/sellout_beam/metadata.json
for D in 2026-11-02 2026-11-03; do
  gcloud dataflow flex-template run "sellout-ingest-${D//-/}" --region "$REGION" \
    --template-file-gcs-location "gs://$TEMP_BUCKET/templates/sellout_ingest.json" \
    --parameters "run_date=$D,input_root=gs://$LANDING_BUCKET,output_project=$PROJECT_ID" \
    --service-account-email "$SA_DATAFLOW" --max-workers 2 --worker-machine-type e2-standard-2 \
    --temp-location "gs://$TEMP_BUCKET/dataflow/tmp" --staging-location "gs://$TEMP_BUCKET/dataflow/staging" \
    --additional-user-labels pipeline=sellout_daily
done
gcloud dataflow jobs list --region "$REGION" --limit 5
```
- Se usa `--config cloudbuild.yaml` y no `--tag`: el builder que usa `--tag` falla con `invalid tar header` al leer la imagen base del launcher.
- La imagen pesa ~2 GB (es la imagen del SDK de Beam). Construirla en tu laptop y subirla es lento: deja que la construya Cloud Build.

### 7. Idempotencia
Lanza otra vez el Flex Template para `2026-11-02` y repite el conteo del paso 5 para ese día: **mismos números**.

## Checkpoint
Para cada día, `valid_rows + rejected_rows = total_lines` del manifiesto, y los `error_code` coinciden con `rejects_by_kind`. `missing_product` aparece como `missing_field`.

## Limpieza
Los jobs batch se apagan solos al terminar. Comprueba que no quede nada corriendo:
```bash
gcloud dataflow jobs list --region "$REGION" --status active
```

## Preguntas
1. ¿Por qué validar en Dataflow y deduplicar en SQL (Dataform), en lugar de hacer todo en un solo lugar?
2. ¿Qué es un side input y por qué sirve para el maestro de tiendas pero no para una tabla de 500 millones de filas?
3. Este pipeline, ¿podría ser un `INSERT ... SELECT` en BigQuery? ¿Cuándo SÍ conviene Dataflow? (Ver `docs/11-guia-de-decisiones.md`.)
4. ¿Qué pasaría con `WRITE_APPEND` en vez de `WRITE_TRUNCATE` si Airflow reintenta la tarea?
5. (EN) *What is a dead-letter queue and why is it better than dropping bad records?*
