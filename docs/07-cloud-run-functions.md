# Cloud Run: services, jobs y functions

> Cloud Run ejecuta contenedores sin administrar servidores. Tiene tres formas: services (HTTP), jobs (tareas batch que terminan) y functions (código que reacciona a eventos). Aquí ves cuándo usar cada una, cómo se programan con Cloud Scheduler o Workflows y cómo el lab despliega el generador del feed como Cloud Run Job que dispara Airflow. **Lab relacionado:** `labs/lab04-cloud-run-job`

## Qué es

| Forma | Qué hace | Cómo se invoca | Termina sola |
|---|---|---|---|
| **Cloud Run service** | Contenedor que escucha HTTP y **escala a cero** sin tráfico | Request HTTP(S) | No: atiende requests |
| **Cloud Run job** | Contenedor que corre una tarea y **termina** | `gcloud run jobs execute`, API, Scheduler, Workflows, Airflow | Sí |
| **Cloud Run function** (antes Cloud Functions) | Una función: tú escribes el código y Google arma el contenedor | HTTP o **eventos** vía Eventarc (GCS, Pub/Sub, auditoría) | Sí, por invocación |

Piezas que las acompañan:

- **Artifact Registry**: el registro de imágenes de contenedor (y de paquetes).
- **Secret Manager**: guarda credenciales y las inyecta en runtime.
- **Cloud Scheduler**: cron gestionado que llama a un endpoint HTTP, publica en Pub/Sub o ejecuta un Cloud Run job.
- **Workflows**: orquestación serverless liviana en YAML: pasos, condiciones, reintentos y llamadas a APIs de Google.

Un **job** tiene tres niveles: **job** (la definición: imagen, CPU, memoria, variables, tareas, reintentos) → **execution** (una corrida) → **task** (cada contenedor de esa corrida). Una ejecución puede tener hasta 10 000 tareas; `--parallelism` limita cuántas corren a la vez.

## Para qué sirve

- **Jobs**: ingesta batch por lotes. Traer archivos de una API o de un SFTP a GCS, descomprimir, renombrar y mover, generar datos sintéticos (el generador del lab), migraciones de esquema en CI.
- **Services**: APIs internas, webhooks que reciben notificaciones de terceros, endpoints que Workflows o Scheduler llaman.
- **Functions**: reacciones pequeñas a un evento: "llegó un archivo a `landing`", "llegó un mensaje a un topic".

## Cuándo sí / cuándo no

| Necesidad | Opción | Por qué no las otras |
|---|---|---|
| Descargar archivos de una API o SFTP cada día | **Cloud Run job** | Un service esperaría HTTP sin necesidad; Dataflow es excesivo para mover archivos |
| Reaccionar a cada archivo que llega a un bucket | **Cloud Run function** con trigger de GCS | Un DAG con sensor por archivo es más caro y más lento |
| Webhook que recibe notificaciones | **Cloud Run service** | Debe estar disponible para requests |
| Validar y transformar millones de filas por elemento | **Dataflow** | Un job de Cloud Run no reparte el trabajo solo ni hace shuffle |
| Cadena de 5–10 pasos con dependencias, reintentos, backfill y vista histórica | **Composer** (Managed Airflow) | Scheduler no maneja dependencias; Workflows no tiene backfill ni historial por fecha lógica |
| Un solo paso diario sin dependencias | **Scheduler + Cloud Run job** | Composer tiene costo fijo 24/7 |
| 3–4 llamadas encadenadas a APIs de Google, sin backfill | **Workflows** | Más liviano que Composer y sin costo fijo |

Límites a recordar: por defecto cada tarea tiene un timeout de 10 minutos, configurable hasta 168 horas (7 días). `--max-retries` va de 0 a 10 y por defecto es 3.

## Cómo se usa

### 1. Imagen fijada en Artifact Registry

Una imagen se identifica por **tag** (`:2026.11.09`, mutable salvo que el repositorio imponga tags inmutables) o por **digest** (`@sha256:...`, inmutable). `latest` es un antipatrón: no sabes qué código corrió ni puedes reproducir una corrida.

```bash
gcloud artifacts repositories create ${AR_REPO} --repository-format=docker --location=us-central1
docker build -t us-central1-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/sellout-generator:2026.11.09 .
docker push us-central1-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/sellout-generator:2026.11.09

# Obtener el digest para desplegar por digest
gcloud artifacts docker images describe \
  us-central1-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/sellout-generator:2026.11.09 \
  --format 'value(image_summary.digest)'
```

### 2. Crear el job del generador

```bash
gcloud run jobs deploy sellout-generator \
  --image us-central1-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/sellout-generator@sha256:<digest> \
  --region us-central1 \
  --service-account sa-generator@${PROJECT_ID}.iam.gserviceaccount.com \
  --tasks 1 --max-retries 1 --task-timeout 15m \
  --cpu 1 --memory 1Gi \
  --set-env-vars LANDING_BUCKET=${PROJECT_ID}-landing
```

- `--service-account`: la **service account de runtime**. El código usa sus credenciales con Application Default Credentials (ADC), sin llaves JSON. `sa-generator` solo necesita escribir en `${PROJECT_ID}-landing`.
- `--tasks 1`: el generador escribe un `_SUCCESS` al final. Con varias tareas, ninguna sabe cuándo terminaron las demás (ver sección 4).
- `--max-retries 1`: un reintento por tarea. Si el código no es idempotente, un reintento duplica datos.

### 3. Ejecutar con overrides

Los **overrides** cambian argumentos, variables, número de tareas o timeout **solo para esa ejecución**; la definición del job no cambia.

```bash
gcloud run jobs execute sellout-generator --region us-central1 --wait \
  --args="--date=2026-11-09"
```

El generador es **determinista**: la semilla es la fecha. Re-ejecutar el 9 de noviembre produce exactamente los mismos archivos en `gs://${PROJECT_ID}-landing/sellout/date=2026-11-09/`, con los mismos errores inyectados. El orden de escritura importa: primero los JSONL, después `_manifest.json` con los conteos y al final `_SUCCESS`. El sensor de Airflow espera `_SUCCESS`; si existiera antes que los datos, el pipeline leería archivos incompletos.

Desde Airflow (detalle en `08-orquestacion-airflow.md`):

```python
CloudRunExecuteJobOperator(
    task_id="generate_feed",
    project_id=PROJECT_ID, region="us-central1", job_name="sellout-generator",
    overrides={"container_overrides": [{"args": ["--date={{ ds }}"]}]},
    deferrable=True,
)
```

### 4. Paralelismo con tareas

Cada tarea recibe `CLOUD_RUN_TASK_INDEX` (0 a N−1), `CLOUD_RUN_TASK_COUNT` (N) y `CLOUD_RUN_TASK_ATTEMPT` (número de reintento). Tu código decide qué parte del trabajo le toca a cada una:

```python
import os

index = int(os.environ.get("CLOUD_RUN_TASK_INDEX", 0))
count = int(os.environ.get("CLOUD_RUN_TASK_COUNT", 1))

retailers = sorted(load_retailer_list())      # orden estable: misma asignación en cada corrida
for retailer in retailers[index::count]:      # reparto round-robin
    fetch_and_upload(retailer)                # debe ser idempotente: sobrescribe el mismo objeto
```

Con `--tasks 4`, cada tarea procesa una cuarta parte. Ninguna tarea sabe cuándo terminaron las otras, así que el `_SUCCESS` lo escribe el orquestador cuando la ejecución completa termina bien, o un paso posterior.

### 5. Service account y secretos

Credenciales de una API o un SFTP externo: **nunca** en la imagen ni en variables de entorno en texto plano. Van en Secret Manager:

```bash
printf '%s' "$SFTP_PASSWORD" | gcloud secrets create sftp-password --data-file=-
gcloud secrets add-iam-policy-binding sftp-password \
  --member=serviceAccount:sa-generator@${PROJECT_ID}.iam.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor
gcloud run jobs update sellout-generator --region us-central1 \
  --set-secrets SFTP_PASSWORD=sftp-password:1
```

- Como **variable de entorno**, el secreto se resuelve al arrancar la instancia. Fija una versión (`:1`), no `latest`.
- Como **volumen** (`--set-secrets=/secrets/sftp/password=sftp-password:latest`), se lee al abrir el archivo. Funciona mejor con la rotación.
- La service account de runtime recibe solo `secretAccessor` sobre **ese** secreto, no sobre el proyecto.

### 6. Cloud Scheduler

```bash
gcloud scheduler jobs create http sellout-generator-daily \
  --location us-central1 --schedule "0 5 * * *" --time-zone "America/Mexico_City" \
  --uri "https://run.googleapis.com/v2/projects/${PROJECT_ID}/locations/us-central1/jobs/sellout-generator:run" \
  --http-method POST \
  --oauth-service-account-email ${SA_GENERATOR}
```

Scheduler llama a la API de Cloud Run con un token OAuth de esa service account, que necesita `roles/run.invoker` sobre el job. El lab04 lo prueba (paso 7, opcional) y lo borra enseguida, porque en el lab06 quien dispara el job es Airflow. Sirve si **un solo paso** corre a una hora fija. No sabe de dependencias ni de fechas lógicas: si quieres re-procesar el día 3, lo ejecutas a mano con overrides.

### 7. Workflows

```yaml
main:
  params: [args]
  steps:
    - run_generator:
        call: googleapis.run.v1.namespaces.jobs.run
        args:
          name: ${"namespaces/" + sys.get_env("GOOGLE_CLOUD_PROJECT_ID") + "/jobs/sellout-generator"}
          location: us-central1
          body:
            overrides:
              containerOverrides:
                args: [${"--date=" + args.date}]
        result: execution
    - done:
        return: ${execution}
```

Los conectores de Workflows esperan a que termine la operación de larga duración. Workflows se cobra por paso ejecutado y no tiene costo fijo. No tiene backfill, ni catchup, ni vista de corridas por fecha lógica.

### 8. Cloud Run functions

```python
import functions_framework

@functions_framework.cloud_event
def on_landing_file(cloud_event):
    data = cloud_event.data
    print(f"Nuevo objeto: gs://{data['bucket']}/{data['name']}")
```

```bash
gcloud run deploy on-landing-file --source . --function on_landing_file \
  --base-image python314 --region us-central1 --no-allow-unauthenticated
gcloud eventarc triggers create landing-finalized --location us-central1 \
  --destination-run-service on-landing-file --destination-run-region us-central1 \
  --event-filters "type=google.cloud.storage.object.v1.finalized" \
  --event-filters "bucket=${PROJECT_ID}-landing" \
  --service-account ${EVENTARC_SA}   # una SA con roles/run.invoker sobre el servicio
```

Los eventos llegan **al menos una vez**: la función debe tolerar duplicados. Una función sirve para trabajo corto. Si el procesamiento crece, la función solo registra el evento y lanza un job o un DAG.

### 9. Patrones de ingesta típicos

- **API → GCS**: un job pagina la API, escribe un archivo por página o por día en `landing/<fuente>/date=YYYY-MM-DD/` y al final un manifiesto con los conteos. Reintentos con backoff y respeto del rate limit de la fuente.
- **SFTP → GCS**: un job lista los archivos remotos nuevos, los descarga a `/tmp` (memoria del contenedor: dimensiona `--memory`), los sube a GCS y registra qué ya se trajo. No borres en el origen hasta validar.
- **Descomprimir y mover**: un `.zip` no se lee en paralelo. Un job lo expande a JSONL o CSV en GCS antes de cargar a BigQuery. Mover dentro de GCS es una copia del lado del servidor (rewrite): no hace falta descargar.
- **Archivar**: después de cargar y validar, mover de `landing` a `${PROJECT_ID}-archive` con la misma ruta de partición. El reprocesamiento lee de `archive`.

## En la práctica

- **Cloud Run jobs efímeros lanzados desde un DAG** para traer archivos de fuentes externas: el DAG pasa la fecha por override, el job descarga a GCS y termina. Airflow solo espera el resultado. No hay VMs prendidas ni código de descarga dentro de los workers de Airflow.
- **Imagen `latest` sin fijar**: un push nuevo cambia el comportamiento de la corrida de mañana sin que nadie lo apruebe. Se despliega por digest desde CI y el tag lleva versión o commit.
- **Manifiesto y cifras de control**: el job escribe cuántas filas y archivos generó. El DAG lo compara después contra lo cargado en raw más los rechazos.
- **Costo**: los jobs cobran solo mientras corren las tareas (CPU y memoria por segundo). Composer, en cambio, cuesta 24/7. Si el flujo es "un paso a una hora", Scheduler + job es mucho más barato.

## Errores comunes

- Usar un service para trabajo batch y dejar requests HTTP abiertos 30 minutos.
- Escribir `_SUCCESS` antes que los datos, o desde varias tareas en paralelo.
- Generar nombres de archivo con timestamp de ejecución: cada reintento crea archivos nuevos y el día queda duplicado. El nombre se deriva de la fecha lógica.
- Dar `roles/editor` a la service account de runtime. Cada job tiene su propia service account con lo mínimo.
- Pasar contraseñas como `--set-env-vars` o horneadas en la imagen.
- Creer que el timeout de un job es por ejecución: es **por tarea**.
- Desplegar con `latest` y sorprenderse de que "ayer funcionaba".

## Autoevaluación

1. ¿Qué diferencia hay entre job, execution y task en Cloud Run?

<details><summary>Respuesta</summary>

El **job** es la definición (imagen, recursos, número de tareas, reintentos, timeout). Una **execution** es una corrida de ese job. Cada execution tiene una o más **tasks**, cada una en su propio contenedor, con `CLOUD_RUN_TASK_INDEX` para repartirse el trabajo.

</details>

2. ¿Por qué el generador del lab corre con `--tasks 1`?

<details><summary>Respuesta</summary>

Porque escribe `_SUCCESS` al final, después de los datos y del manifiesto. Con varias tareas, ninguna sabe cuándo terminaron las demás y alguna podría marcar éxito antes de tiempo. Si se paraleliza, el marcador lo escribe el orquestador o un paso posterior.

</details>

3. ¿Qué gana el lab al ser el generador determinista con semilla = fecha?

<details><summary>Respuesta</summary>

Idempotencia y reproducibilidad. Re-ejecutar un día produce los mismos archivos en la misma ruta, así que un reintento o un backfill no cambia los resultados ni duplica datos. Los errores inyectados también se repiten y las pruebas son estables.

</details>

4. ¿Cuándo eliges Cloud Scheduler + Cloud Run job en lugar de Composer?

<details><summary>Respuesta</summary>

Cuando hay un solo paso (o pocos, sin dependencias) que corre a una hora fija y no necesitas backfill por fecha lógica ni vista de corridas. Composer se justifica con varias tareas dependientes, sensores, reintentos por tarea y re-procesos por fecha. Su costo es fijo 24/7.

</details>

5. ¿Por qué se recomienda fijar la versión del secreto cuando se expone como variable de entorno?

<details><summary>Respuesta</summary>

Porque la variable se resuelve al arrancar la instancia. Con `latest`, dos tareas de la misma ejecución podrían usar versiones distintas durante una rotación. Fijar la versión hace explícito qué credencial se usa; el montaje como volumen es mejor si quieres seguir la rotación.

</details>

6. Una function se dispara por cada archivo que llega a `landing`. ¿Qué debes asumir sobre los eventos?

<details><summary>Respuesta</summary>

Que pueden llegar más de una vez (at-least-once) y no necesariamente en orden. La función debe ser idempotente: por ejemplo, derivar el destino del nombre del objeto y sobrescribir, no anexar.

</details>

## Para profundizar

- [Crear Cloud Run jobs (tareas, reintentos, timeout)](https://docs.cloud.google.com/run/docs/create-jobs)
- [Ejecutar jobs y overrides](https://docs.cloud.google.com/run/docs/execute/jobs)
- [Ejecutar jobs con Cloud Scheduler](https://docs.cloud.google.com/run/docs/execute/jobs-on-schedule)
- [Secretos en Cloud Run jobs](https://docs.cloud.google.com/run/docs/configuring/jobs/secrets)
- [Service account de runtime en jobs](https://docs.cloud.google.com/run/docs/configuring/jobs/service-identity)
- [Triggers de Cloud Run functions](https://docs.cloud.google.com/run/docs/function-triggers)
- [Ejecutar un Cloud Run job desde Workflows](https://docs.cloud.google.com/workflows/docs/tutorials/execute-cloud-run-jobs)
- [Artifact Registry: tags y digests](https://docs.cloud.google.com/artifact-registry/docs/docker/names)
