"""Pruebas que corren en CI sin GCP: ¿el DAG importa, tiene la forma esperada y respeta las reglas del equipo?"""

import os
import time
from pathlib import Path

import pytest

os.environ.setdefault("AIRFLOW__CORE__LOAD_EXAMPLES", "False")
DAGS = Path(__file__).resolve().parents[1] / "dags"


@pytest.fixture(scope="session")
def dagbag():
    from airflow.models.dagbag import DagBag

    return DagBag(dag_folder=str(DAGS))  # Airflow 3: include_examples ya no existe


def test_no_import_errors(dagbag):
    assert dagbag.import_errors == {}, dagbag.import_errors


def test_parse_is_fast():
    """Un DAG que hace I/O al parsearse (leer GCS, llamar APIs) frena al scheduler para TODOS los DAGs."""
    from airflow.models.dagbag import DagBag

    t0 = time.perf_counter()
    DagBag(dag_folder=str(DAGS))  # Airflow 3: include_examples ya no existe
    assert time.perf_counter() - t0 < 5


def test_sellout_daily_shape(dagbag):
    # Nota: en Airflow 3 dagbag.get_dag() consulta la base de datos; en CI usamos el dict dagbag.dags.
    dag = dagbag.dags["sellout_daily"]
    assert dag is not None
    assert dag.catchup is False
    assert dag.max_active_runs == 1
    ids = set(dag.task_ids)
    expected = {
        "generate_feed",
        "wait_for_feed",
        "load_product_snapshot",
        "load_store_snapshot",
        "run_dataflow",
        "control_figures",
        "dataform_compile",
        "dataform_invoke",
        "wait_dataform",
        "archive_files",
    }
    assert expected <= ids
    # El gate de cifras de control va ANTES de transformar
    assert "control_figures" in dag.get_task("dataform_compile").upstream_task_ids
    assert "run_dataflow" in dag.get_task("control_figures").upstream_task_ids


def test_every_task_retries(dagbag):
    for t in dagbag.dags["sellout_daily"].tasks:
        assert t.retries >= 1, f"{t.task_id} sin retries"


def test_templates_use_logical_date(dagbag):
    """Idempotencia: los pasos que leen/escriben datos deben depender de {{ ds }}, no de 'hoy'."""
    dag = dagbag.dags["sellout_daily"]
    assert "{{ ds }}" in dag.get_task("wait_for_feed").object
    assert "{{ ds }}" in str(dag.get_task("run_dataflow").body)
    assert "{{ ds }}" in str(dag.get_task("dataform_compile").compilation_result)
