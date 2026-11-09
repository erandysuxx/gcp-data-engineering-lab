# Lab 01 · Cloud Storage: la zona de aterrizaje (landing)

**Objetivo:** crear los 3 buckets del lab, cada uno con una política distinta según su propósito, y subir el dataset de Olist.

**Tiempo:** ~1 h · **Costo:** centavos (unos 125 MB) · **Docs:** [`03-cloud-storage`](../../docs/03-cloud-storage.md)

## Conceptos en 1 minuto
- Un **bucket** es un contenedor de **objetos** (archivos). Las "carpetas" son prefijos del nombre (`sellout/date=2026-11-01/...`).
- Bucket distinto = **política** distinta (clase de almacenamiento, lifecycle, soft delete, permisos):

  | Bucket | Para qué | Política |
  |---|---|---|
  | `${PROJECT_ID}-landing` | Donde "aterrizan" los archivos de las fuentes | El feed se borra a los 14 días; Olist (`olist/`) se conserva |
  | `${PROJECT_ID}-archive` | Copia histórica de lo procesado | A Nearline a los 30 días; se borra al año |
  | `${PROJECT_ID}-temp` | Temporales de Dataflow (`dataflow/`) y specs de templates (`templates/`) | `dataflow/` se borra a los 3 días; **sin soft delete** |

## Pasos
```bash
source .env.lab && scripts/preflight.sh
```

### 1. Crear los buckets
```bash
for B in "$LANDING_BUCKET" "$ARCHIVE_BUCKET" "$TEMP_BUCKET"; do
  gcloud storage buckets create "gs://$B" --location="$REGION" --default-storage-class=STANDARD \
    --uniform-bucket-level-access --public-access-prevention
done
```
- `--uniform-bucket-level-access`: los permisos se dan solo con IAM a nivel bucket (sin ACLs por objeto, que son difíciles de auditar).
- `--public-access-prevention`: aunque alguien se equivoque, el bucket no puede volverse público.

### 2. Políticas de ciclo de vida (lifecycle) y soft delete
```bash
gcloud storage buckets update "gs://$LANDING_BUCKET" --lifecycle-file=labs/lab01-cloud-storage/lifecycle-landing.json
gcloud storage buckets update "gs://$ARCHIVE_BUCKET" --lifecycle-file=labs/lab01-cloud-storage/lifecycle-archive.json
gcloud storage buckets update "gs://$TEMP_BUCKET"    --lifecycle-file=labs/lab01-cloud-storage/lifecycle-temp.json
gcloud storage buckets update "gs://$TEMP_BUCKET"    --clear-soft-delete
gcloud storage buckets describe "gs://$TEMP_BUCKET" --format="yaml(lifecycle_config,soft_delete_policy)"
```
**Por qué soft delete apagado en temp:** con soft delete, cada objeto borrado o sobrescrito se sigue cobrando durante la retención (7 días por defecto). En un bucket donde todo se escribe y se borra a cada rato, pagas basura.

### 3. Descargar Olist y subirlo
```bash
scripts/download_olist.sh                  # deja los CSV en data/olist/ (no se versiona)
gcloud storage cp data/olist/*.csv "gs://$LANDING_BUCKET/olist/"
gcloud storage ls -l "gs://$LANDING_BUCKET/olist/"
gcloud storage du -s -r "gs://$LANDING_BUCKET"   # tamaño total
```

### 4. El layout de un feed (vista previa del lab04)
Genera un día del feed de sell-out **en local** y súbelo para ver cómo luce una entrega:
```bash
cd generator && uv sync && uv run python -m sellout_gen.main --date 2026-10-31 \
  --products-csv ../data/olist/olist_products_dataset.csv --out ../out && cd ..
gcloud storage cp -r out/sellout out/masters "gs://$LANDING_BUCKET/"
gcloud storage ls -r "gs://$LANDING_BUCKET/sellout/"
gcloud storage cat "gs://$LANDING_BUCKET/sellout/date=2026-10-31/_manifest.json"
```
Observa:
- **Partición en la ruta** (`date=YYYY-MM-DD`): cada día es un prefijo. Reprocesar un día = leer un prefijo.
- **`_manifest.json`**: cuántas líneas trae cada archivo. Es la base de las **cifras de control** del lab06.
- **`_SUCCESS`** se escribe **al final**. Quien procesa espera esta bandera para no leer una entrega a medias.

## Checkpoint
- `gcloud storage ls` muestra los 3 buckets.
- `gcloud storage buckets describe gs://$TEMP_BUCKET` muestra `retentionDurationSeconds: '0'` en soft delete.
- Hay 9 CSV en `gs://$LANDING_BUCKET/olist/`.

## Limpieza
Nada: los buckets se usan en los labs siguientes. El feed de prueba se borra solo a los 14 días.

## Preguntas
1. ¿Por qué tres buckets y no uno con tres carpetas?
2. ¿Qué pasa si mandas archivos temporales a la clase Archive?
3. Un retailer sube 5 archivos y el último tarda 20 minutos. ¿Cómo evitas procesar una entrega incompleta?
4. (EN) *Explain uniform bucket-level access in one sentence.*
