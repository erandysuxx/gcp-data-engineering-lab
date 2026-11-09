# Lab 04 · Cloud Run Job: el generador del feed como job batch

**Objetivo:** empaquetar el generador en una imagen Docker, publicarla en Artifact Registry y correrla como **Cloud Run Job** con una service account propia. Opcionalmente, programarla con Cloud Scheduler. Este job "fabrica" el feed que Dataflow procesará en el lab05.

**Tiempo:** ~2 h · **Costo:** ~$0 (Cloud Run cobra por segundo de CPU y memoria; un día de feed tarda segundos) · **Docs:** [`07-cloud-run-functions`](../../docs/07-cloud-run-functions.md)

## Conceptos en 1 minuto
- **Cloud Run service** responde HTTP y escala a cero. **Cloud Run job** corre hasta terminar y no escucha HTTP.
- Jerarquía: **job** (la definición) → **execution** (una corrida) → **task** (una instancia; puede haber N en paralelo).
- La imagen se fija por **tag inmutable** (`:v1`, `:<sha>`), nunca `latest`: así siempre sabes qué código corrió.

## Pasos
```bash
source .env.lab && scripts/preflight.sh
```

### 1. Artifact Registry (donde viven las imágenes)
```bash
gcloud artifacts repositories create "$AR_REPO" --repository-format=docker --location="$REGION" \
  --description="Imágenes del generador y del Flex Template"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
```

### 2. Service account del job (mínimo privilegio)
Solo necesita leer y escribir en el bucket de landing y escribir logs. **Nada** a nivel proyecto sobre datos.
```bash
gcloud iam service-accounts create sa-generator --display-name="Cloud Run Job que genera el feed"
gcloud storage buckets add-iam-policy-binding "gs://$LANDING_BUCKET" \
  --member="serviceAccount:$SA_GENERATOR" --role=roles/storage.objectAdmin
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_GENERATOR" --role=roles/logging.logWriter --condition=None
```
Si un binding falla con *"does not exist"* justo después de crear la SA, espera ~30 s y repítelo. IAM es *eventualmente consistente*: la SA tarda unos segundos en ser visible para todos los servicios.

### 3. Construir y publicar la imagen
Cloud Run corre en `linux/amd64`. En una Mac con Apple Silicon hay que pedírselo a Docker:
```bash
docker buildx build --platform linux/amd64 -t "$IMAGE_PREFIX/sellout-generator:v1" --push generator
```
*Alternativa sin Docker local:* `gcloud builds submit generator --tag "$IMAGE_PREFIX/sellout-generator:v1"` (construye con Cloud Build).

### 4. Crear el job
```bash
gcloud run jobs deploy sellout-generator --region "$REGION" \
  --image "$IMAGE_PREFIX/sellout-generator:v1" \
  --service-account "$SA_GENERATOR" \
  --set-env-vars "PRODUCTS_CSV=gs://$LANDING_BUCKET/olist/olist_products_dataset.csv,OUT_ROOT=gs://$LANDING_BUCKET" \
  --tasks 1 --max-retries 1 --task-timeout 10m --labels pipeline=sellout_daily
```

### 5. Ejecutarlo para 3 días
La fecha se pasa como variable de entorno, sobrescrita **solo en esa ejecución**:
```bash
for D in 2026-11-01 2026-11-02 2026-11-03; do
  gcloud run jobs execute sellout-generator --region "$REGION" --update-env-vars "RUN_DATE=$D" --wait
done
gcloud storage ls "gs://$LANDING_BUCKET/sellout/"
gcloud storage cat "gs://$LANDING_BUCKET/sellout/date=2026-11-02/_manifest.json"
```

### 6. Ver ejecuciones y logs
```bash
gcloud run jobs executions list --job sellout-generator --region "$REGION"
gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="sellout-generator"' \
  --limit 10 --freshness 1h --format="value(timestamp,textPayload)"
```

### 7. (Opcional) Programarlo con Cloud Scheduler
Sin `RUN_DATE`, el generador usa "ayer en UTC": justo lo que necesita un cron.
```bash
gcloud run jobs add-iam-policy-binding sellout-generator --region "$REGION" \
  --member="serviceAccount:$SA_GENERATOR" --role=roles/run.invoker
gcloud scheduler jobs create http sellout-generator-daily --location "$REGION" \
  --schedule "0 5 * * *" --time-zone "UTC" --http-method POST \
  --uri "https://run.googleapis.com/v2/projects/$PROJECT_ID/locations/$REGION/jobs/sellout-generator:run" \
  --oauth-service-account-email "$SA_GENERATOR"
gcloud scheduler jobs run sellout-generator-daily --location "$REGION"   # dispararlo ya, para probar
```
**Bórralo al terminar este paso:** en el lab06, quien dispara el generador es Airflow.
```bash
gcloud scheduler jobs delete sellout-generator-daily --location "$REGION" --quiet
```

## Checkpoint
- Existen `sellout/date=2026-11-0{1,2,3}/` con 5 archivos JSONL, `_manifest.json` y `_SUCCESS`.
- Re-ejecutar un día deja **exactamente** los mismos archivos: el generador es determinista. Compara el `md5` con `gcloud storage hash`.

## Limpieza
Nada: el job no cuesta mientras no corre. Las imágenes viejas se pueden borrar con `gcloud artifacts docker images delete`.

## Preguntas
1. ¿Por qué un job y no un service para esto? ¿Y por qué no una Cloud Run function?
2. ¿Qué cambiarías si el feed fuera de 50 retailers y tardara 40 minutos? Pista: `--tasks` y `CLOUD_RUN_TASK_INDEX`.
3. ¿Qué rol le falta a `sa-generator` para escribir en BigQuery, y por qué no se lo damos?
4. (EN) *Why should container images be pinned to an immutable tag?*
