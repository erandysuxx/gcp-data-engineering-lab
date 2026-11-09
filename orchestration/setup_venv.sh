#!/usr/bin/env bash
# Crea .venv con la MISMA versión de Airflow que la imagen de Composer (ver VERSIONS.md).
# Airflow se instala SIEMPRE con su archivo de constraints: fija cientos de dependencias compatibles.
set -euo pipefail
cd "$(dirname "$0")"
AIRFLOW_VERSION=3.3.1
PY=3.11
CONSTRAINTS="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PY}.txt"
uv venv --python "$PY" .venv
uv pip install --python .venv/bin/python \
  "apache-airflow==${AIRFLOW_VERSION}" apache-airflow-providers-google apache-airflow-providers-apache-beam pytest ruff \
  --constraint "$CONSTRAINTS"
