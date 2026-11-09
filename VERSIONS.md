# Versiones fijadas

Una sola fuente de verdad. Si cambias una versión, cámbiala aquí **y** en el archivo que la usa (columna derecha).

| Componente | Versión | Dónde se usa |
|---|---|---|
| Python | 3.11 | `.python-version`, `pyproject.toml` de cada componente, imágenes Docker |
| Composer image (Managed Service for Apache Airflow, Gen 3) | `composer-3-airflow-3.3.1-build.5` | `infra/terraform/composer.tf`, `labs/lab06-airflow-composer` (`composer-dev`) |
| Apache Airflow (CI) | 3.3.1 + constraints `constraints-3.3.1/constraints-3.11.txt` | `.github/workflows/ci.yml`, `orchestration/pyproject.toml` |
| apache-airflow-providers-google | CI: 22.3.0 (constraints 3.3.1) · imagen de Composer: 22.6.0 (verificado con `composer-dev`) | `orchestration/setup_venv.sh` |
| Apache Beam | `apache-beam[gcp]==2.77.0` | `pipelines/sellout_beam/pyproject.toml`, `Dockerfile` |
| Imagen base Flex Template | `gcr.io/dataflow-templates-base/python311-template-launcher-base:20261026-rc00` + `apache/beam_python3.11_sdk:2.77.0` | `pipelines/sellout_beam/Dockerfile` |
| Dataform CLI / core | `@dataform/cli@3.1.4`, `dataformCoreVersion: 3.1.4` | `workflow_settings.yaml`, CI |
| Terraform | 1.17.1 (`hashicorp/terraform:1.17.1` en local, `setup-terraform` en CI) | `infra/terraform/versions.tf`, `scripts/tf.sh`, CI |
| Provider google (Terraform) | `~> 8.10` | `infra/terraform/versions.tf` |
| Región | `us-central1` (una sola región para todo) | `.env.lab` |

## Cómo comprobar que siguen vigentes

```bash
# Imágenes de Composer disponibles (requiere el lab00 hecho)
gcloud composer environments list-image-versions --location "$REGION" --project "$PROJECT_ID" \
  --format="value(imageVersionId)" | grep 'composer-3-airflow-3' | head
# Soporte de versiones del SDK de Beam en Dataflow
#   https://docs.cloud.google.com/dataflow/docs/support/sdk-version-support-status
```
