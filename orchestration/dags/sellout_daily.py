"""DAG `sellout_daily`: ingesta diaria del feed de sell-out de retailers, de punta a punta.

    generate_feed ─► wait_for_feed ─┬─► load_masters ──┐
      (Cloud Run Job)  (sensor GCS)  └─► run_dataflow ──┴─► control_figures ─► dataform_compile
                                         (Flex Template)     (gate de conteos)      │
                                                                                     ▼
                                     archive_files ◄─ wait_dataform ◄─ dataform_invoke

Principios que ilustra:
- Airflow ORQUESTA, no procesa: cada paso pesado corre en un servicio (Cloud Run, Dataflow, BigQuery, Dataform).
- Idempotencia: cada corrida procesa SOLO su fecha lógica ({{ ds }}) y reemplaza su partición. Re-correr no duplica.
- Nada de I/O al parsear: la configuración sale de variables de entorno, que leer es gratis.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timedelta

from airflow.providers.google.cloud.hooks.bigquery import BigQueryHook
from airflow.providers.google.cloud.hooks.gcs import GCSHook
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.providers.google.cloud.operators.cloud_run import CloudRunExecuteJobOperator
from airflow.providers.google.cloud.operators.dataflow import DataflowStartFlexTemplateOperator
from airflow.providers.google.cloud.operators.dataform import (
    DataformCreateCompilationResultOperator,
    DataformCreateWorkflowInvocationOperator,
)
from airflow.providers.google.cloud.sensors.dataform import DataformWorkflowInvocationStateSensor
from airflow.providers.google.cloud.sensors.gcs import GCSObjectExistenceSensor
from airflow.sdk import DAG, task
from google.cloud.dataform_v1beta1 import WorkflowInvocation

log = logging.getLogger(__name__)

# ── Configuración (variables de entorno del Composer / de composer-dev) ─────────────────────────────
PROJECT_ID = os.environ.get("LAB_PROJECT_ID", "de-lab-CAMBIAME")
REGION = os.environ.get("LAB_REGION", "us-central1")
LANDING = os.environ.get("LAB_LANDING_BUCKET", f"{PROJECT_ID}-landing")
ARCHIVE = os.environ.get("LAB_ARCHIVE_BUCKET", f"{PROJECT_ID}-archive")
TEMP = os.environ.get("LAB_TEMP_BUCKET", f"{PROJECT_ID}-temp")
DATAFORM_REPO = os.environ.get("LAB_DATAFORM_REPO", "sellout-dataform")
DATAFORM_BRANCH = os.environ.get("LAB_DATAFORM_BRANCH", "main")
FLEX_SPEC = os.environ.get("LAB_FLEX_SPEC", f"gs://{TEMP}/templates/sellout_ingest.json")
SA_DATAFLOW = os.environ.get("LAB_SA_DATAFLOW", f"sa-dataflow@{PROJECT_ID}.iam.gserviceaccount.com")
SA_DATAFORM = os.environ.get("LAB_SA_DATAFORM", f"sa-dataform@{PROJECT_ID}.iam.gserviceaccount.com")
GENERATOR_JOB = os.environ.get("LAB_GENERATOR_JOB", "sellout-generator")

LABELS = {"pipeline": "sellout_daily"}  # llegan al billing export: costo por pipeline


def _on_failure(context) -> None:
    """Punto único para alertar. En el lab solo deja un log claro; en producción, Slack/PagerDuty/email."""
    ti = context["task_instance"]
    log.error("FALLÓ %s.%s (run %s, intento %s)", ti.dag_id, ti.task_id, context["run_id"], ti.try_number)


with DAG(
    dag_id="sellout_daily",
    description="Feed diario de sell-out: GCS → Dataflow → BigQuery raw → Dataform → marts",
    schedule="0 6 * * *",  # 06:00 UTC. En Airflow 3 la fecha lógica ({{ ds }}) es la del disparo
    start_date=datetime(2026, 11, 1),
    catchup=False,  # default en Airflow 3; los históricos se cargan con `airflow backfill create`
    max_active_runs=1,  # una corrida a la vez: dos invocaciones de Dataform no escriben las mismas tablas
    dagrun_timeout=timedelta(hours=2),
    default_args={
        "owner": "data-eng",
        "retries": 2,
        "retry_delay": timedelta(minutes=2),
        "retry_exponential_backoff": True,
        "on_failure_callback": _on_failure,
    },
    tags=["lab", "sellout"],
    doc_md=__doc__,
) as dag:
    # 1) En la vida real el retailer deja el archivo; aquí lo "fabrica" el generador (Cloud Run Job).
    generate_feed = CloudRunExecuteJobOperator(
        task_id="generate_feed",
        project_id=PROJECT_ID,
        region=REGION,
        job_name=GENERATOR_JOB,
        overrides={"container_overrides": [{"env": [{"name": "RUN_DATE", "value": "{{ ds }}"}]}]},
        deferrable=True,
    )

    # 2) Esperar la bandera _SUCCESS (se escribe al final): así nunca leemos un feed a medio escribir.
    wait_for_feed = GCSObjectExistenceSensor(
        task_id="wait_for_feed",
        bucket=LANDING,
        object="sellout/date={{ ds }}/_SUCCESS",
        deferrable=True,  # no ocupa un worker mientras espera
        timeout=60 * 60,
    )

    # 3) Maestros: un load job por tabla. Cargar a BigQuery desde GCS es gratis y atómico.
    load_masters = [
        BigQueryInsertJobOperator(
            task_id=f"load_{name}_snapshot",
            project_id=PROJECT_ID,
            location=REGION,
            configuration={
                "labels": {**LABELS, "step": "load_masters"},
                "load": {
                    "sourceUris": [f"gs://{LANDING}/masters/date={{{{ ds }}}}/{name}s.jsonl"],
                    "sourceFormat": "NEWLINE_DELIMITED_JSON",
                    # decorador $YYYYMMDD + WRITE_TRUNCATE: reemplaza SOLO la partición del día (idempotente)
                    "destinationTable": {
                        "projectId": PROJECT_ID,
                        "datasetId": "raw_sellout",
                        "tableId": f"{name}_snapshot${{{{ ds_nodash }}}}",
                    },
                    "writeDisposition": "WRITE_TRUNCATE",
                    "createDisposition": "CREATE_NEVER",
                },
            },
        )
        for name in ("product", "store")
    ]

    # 4) Validación + carga del feed con Dataflow (Flex Template). Las filas malas van a la dead-letter.
    run_dataflow = DataflowStartFlexTemplateOperator(
        task_id="run_dataflow",
        project_id=PROJECT_ID,
        location=REGION,
        body={
            "launchParameter": {
                "jobName": "sellout-ingest-{{ ds_nodash }}",
                "containerSpecGcsPath": FLEX_SPEC,
                "parameters": {
                    "run_date": "{{ ds }}",
                    "input_root": f"gs://{LANDING}",
                    "output_project": PROJECT_ID,
                    "output_dataset": "raw_sellout",
                },
                "environment": {
                    "serviceAccountEmail": SA_DATAFLOW,
                    "tempLocation": f"gs://{TEMP}/dataflow/tmp",
                    "stagingLocation": f"gs://{TEMP}/dataflow/staging",
                    "machineType": "e2-standard-2",
                    "maxWorkers": 2,  # dentro del límite de vCPU del free trial
                    "additionalUserLabels": LABELS,
                },
            }
        },
        deferrable=True,  # espera a que el job termine desde el triggerer, sin ocupar un worker
    )

    # 5) Cifras de control: líneas del manifiesto = válidas + rechazadas en BigQuery. Si no cuadra, se detiene.
    @task
    def control_figures(ds=None, run_id=None) -> dict:
        manifest = json.loads(
            GCSHook().download(bucket_name=LANDING, object_name=f"sellout/date={ds}/_manifest.json").decode()
        )
        client = BigQueryHook(use_legacy_sql=False, location=REGION).get_client(project_id=PROJECT_ID)
        sql = """
            SELECT
              (SELECT COUNT(*) FROM raw_sellout.sellout_lines   WHERE sale_date = @d) AS valid_rows,
              (SELECT COUNT(*) FROM raw_sellout.sellout_rejects WHERE feed_date = @d) AS rejected_rows
        """
        from google.cloud import bigquery  # import local: no pesa al parsear el DAG

        params = [bigquery.ScalarQueryParameter("d", "DATE", ds)]
        row = list(client.query(sql, job_config=bigquery.QueryJobConfig(query_parameters=params, labels=LABELS)))[0]
        expected = manifest["total_lines"]
        got = row.valid_rows + row.rejected_rows
        status = "OK" if got == expected else "MISMATCH"
        insert = """
            INSERT INTO ops.control_figures
              (run_date, pipeline, source_lines, valid_rows, rejected_rows, status, dag_run_id, checked_at)
            VALUES (@d, 'sellout_daily', @src, @ok, @rej, @status, @run, CURRENT_TIMESTAMP())
        """
        params += [
            bigquery.ScalarQueryParameter("src", "INT64", expected),
            bigquery.ScalarQueryParameter("ok", "INT64", row.valid_rows),
            bigquery.ScalarQueryParameter("rej", "INT64", row.rejected_rows),
            bigquery.ScalarQueryParameter("status", "STRING", status),
            bigquery.ScalarQueryParameter("run", "STRING", run_id),
        ]
        client.query(insert, job_config=bigquery.QueryJobConfig(query_parameters=params, labels=LABELS)).result()
        result = {"expected": expected, "valid": row.valid_rows, "rejected": row.rejected_rows, "status": status}
        log.info("cifras de control %s: %s", ds, result)
        if status != "OK":
            raise ValueError(f"Las cifras no cuadran para {ds}: {result}")
        return result

    # 6) Dataform: compilar el código de la rama main con run_date = {{ ds }} y ejecutar los modelos "daily".
    dataform_compile = DataformCreateCompilationResultOperator(
        task_id="dataform_compile",
        project_id=PROJECT_ID,
        region=REGION,
        repository_id=DATAFORM_REPO,
        compilation_result={
            "git_commitish": DATAFORM_BRANCH,
            "code_compilation_config": {"vars": {"run_date": "{{ ds }}"}},
        },
    )
    dataform_invoke = DataformCreateWorkflowInvocationOperator(
        task_id="dataform_invoke",
        project_id=PROJECT_ID,
        region=REGION,
        repository_id=DATAFORM_REPO,
        asynchronous=True,  # no bloquea un worker: lo espera el sensor de abajo
        workflow_invocation={
            "compilation_result": "{{ task_instance.xcom_pull('dataform_compile')['name'] }}",
            "invocation_config": {"included_tags": ["daily"], "service_account": SA_DATAFORM},
        },
    )
    wait_dataform = DataformWorkflowInvocationStateSensor(
        task_id="wait_dataform",
        project_id=PROJECT_ID,
        region=REGION,
        repository_id=DATAFORM_REPO,
        workflow_invocation_id="{{ task_instance.xcom_pull('dataform_invoke')['name'].split('/')[-1] }}",
        expected_statuses={WorkflowInvocation.State.SUCCEEDED},
        failure_statuses={WorkflowInvocation.State.FAILED, WorkflowInvocation.State.CANCELLED},
        mode="reschedule",  # libera el worker entre chequeos
        poke_interval=30,
        timeout=60 * 30,
    )

    # 7) Archivar: copia (no mueve) a archive. Copiar es idempotente; landing se limpia por lifecycle.
    @task
    def archive_files(ds=None) -> int:
        gcs = GCSHook()
        copied = 0
        for prefix in (f"sellout/date={ds}/", f"masters/date={ds}/"):
            for obj in gcs.list(bucket_name=LANDING, prefix=prefix):
                gcs.copy(LANDING, obj, ARCHIVE, obj)  # copia del lado del servidor: no pasa por el worker
                copied += 1
        return copied

    cf = control_figures()
    generate_feed >> wait_for_feed >> [*load_masters, run_dataflow]
    run_dataflow >> cf
    [*load_masters, cf] >> dataform_compile >> dataform_invoke >> wait_dataform >> archive_files()
