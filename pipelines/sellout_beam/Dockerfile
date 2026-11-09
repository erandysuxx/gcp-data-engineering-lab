# Flex Template con imagen propia: la MISMA imagen lanza el job y corre en los workers
# (patrón recomendado: https://docs.cloud.google.com/dataflow/docs/guides/templates/configuring-flex-templates).
# Ambas bases van fijadas: nunca `latest`.
FROM gcr.io/dataflow-templates-base/python311-template-launcher-base:20261026-rc00 AS template_launcher

FROM apache/beam_python3.11_sdk:2.77.0
COPY --from=template_launcher /opt/google/dataflow/python_template_launcher /opt/google/dataflow/python_template_launcher

WORKDIR /template
COPY pyproject.toml setup.py main.py ./
COPY sellout_beam ./sellout_beam
RUN pip install --no-cache-dir .

ENV FLEX_TEMPLATE_PYTHON_PY_FILE="/template/main.py"
# SETUP_FILE: al lanzar, Beam empaqueta `sellout_beam` y los workers (imagen estándar de Beam 2.77 / Py3.11)
# lo instalan al arrancar. Es un paquete chico y sin dependencias extra, así que el costo es mínimo.
# Alternativa para pipelines con muchas dependencias: usar ESTA imagen también en los workers
# (opción sdk_container_image) y no instalar nada en runtime.
ENV FLEX_TEMPLATE_PYTHON_SETUP_FILE="/template/setup.py"
