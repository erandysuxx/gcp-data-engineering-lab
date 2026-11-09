# Lab 00 · Setup: cuenta, proyecto, presupuesto y tu Claude

**Objetivo:** dejar listo un proyecto de GCP propio, con una alerta de presupuesto y las herramientas instaladas, y tu Claude conectado a la documentación oficial de Google.

**Tiempo:** ~2 h · **Costo:** $0 · **Docs:** [`02-fundamentos-gcp`](../../docs/02-fundamentos-gcp.md)

## Conceptos en 1 minuto
- **Billing account** (cuenta de facturación) ≠ **proyecto**. El proyecto agrupa recursos y la billing account los paga. Un proyecto sin billing no puede crear casi nada.
- **Free trial:** US$300 durante 90 días, con límites (8 vCPU de Compute Engine a la vez, sin aumentos de cuota). Al terminar no te cobran salvo que actives el pago.
- **Dos logins distintos:**
  - `gcloud auth login` es para la CLI (`gcloud`, `bq`).
  - `gcloud auth application-default login` (**ADC**) es para el código: Python, Terraform, Beam, Airflow local.
  - **Nunca** descargues llaves JSON de service accounts.

## Pasos

### 1. Cuenta y free trial
Activa el free trial en <https://console.cloud.google.com/freetrial> con tu cuenta personal de Google.

### 2. Herramientas locales
| Herramienta | Para qué | Instalación |
|---|---|---|
| Google Cloud CLI (`gcloud`, `bq`) | Todo el lab | <https://docs.cloud.google.com/sdk/docs/install> |
| `uv` | Python 3.11 y entornos aislados | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| Docker Desktop | Imágenes, Airflow local y Terraform | <https://www.docker.com/products/docker-desktop/>. En Mac con Apple Silicon, activa *Use Rosetta for x86_64/amd64 emulation* |
| Node.js 22 | CLI de Dataform | <https://nodejs.org> |
| Kaggle CLI | Descargar el dataset | `uv tool install kaggle` y tu token en `~/.kaggle/kaggle.json` (<https://www.kaggle.com/docs/api>) |
| `gh` (GitHub CLI) | Lab07 | <https://cli.github.com> |
| Claude Code | Tu tutor | <https://docs.claude.com/en/docs/claude-code> |

### 3. Proyecto y billing
```bash
cp scripts/env.example.sh .env.lab        # edita PROJECT_ID (único en GCP, p. ej. de-lab-tunombre-123), LAB_ACCOUNT y GITHUB_REPO
source .env.lab

gcloud auth login "$LAB_ACCOUNT"
gcloud projects create "$PROJECT_ID" --name="DE Lab"
gcloud billing accounts list                         # copia el ACCOUNT_ID (formato XXXXXX-XXXXXX-XXXXXX)
export BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
```

### 4. ADC (credenciales para el código)
```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project "$PROJECT_ID"
```

### 5. Habilitar las APIs del lab
Cada servicio de GCP es una API que hay que encender en el proyecto. Habilitarla no cuesta nada; lo que se cobra es usarla.
```bash
gcloud services enable \
  bigquery.googleapis.com storage.googleapis.com dataflow.googleapis.com dataform.googleapis.com \
  run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com \
  composer.googleapis.com cloudscheduler.googleapis.com iam.googleapis.com iamcredentials.googleapis.com \
  sts.googleapis.com billingbudgets.googleapis.com cloudresourcemanager.googleapis.com \
  logging.googleapis.com monitoring.googleapis.com --project "$PROJECT_ID"
```

### 6. Alerta de presupuesto (hazlo YA)
Una alerta **avisa**, no corta el gasto. Lo que corta el gasto es borrar recursos (`scripts/teardown.sh`).

El monto tiene que ir en la **moneda de tu billing account**. Un free trial abierto desde México puede quedar en MXN; si no coincide, la API responde `INVALID_ARGUMENT` sin más detalle.
```bash
CUR=$(gcloud billing accounts describe "$BILLING_ACCOUNT" --format="value(currencyCode)")
echo "Moneda: $CUR"              # USD → usa 20 ; MXN → usa ~400
AMOUNT=20; [ "$CUR" = "MXN" ] && AMOUNT=400
gcloud billing budgets create --billing-account="$BILLING_ACCOUNT" \
  --display-name="de-lab" --budget-amount="${AMOUNT}${CUR}" \
  --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0 \
  --filter-projects="projects/$PROJECT_ID" --billing-project="$PROJECT_ID"
gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --billing-project="$PROJECT_ID"
```
`--billing-project` le dice a la API de presupuestos a qué proyecto cargar la llamada (*quota project*). Sin él, la API puede responder que no tienes permiso.

### 7. Preflight
Al iniciar **cada** sesión:
```bash
source .env.lab && scripts/preflight.sh
```

### 8. Conecta tu Claude a la documentación oficial
**a) MCP de Google Developer Knowledge.** Busca en la documentación oficial de Google Cloud.
```bash
gcloud services enable developerknowledge.googleapis.com --project "$PROJECT_ID"
gcloud services api-keys create --display-name=claude-dk \
  --api-target=service=developerknowledge.googleapis.com --project "$PROJECT_ID"
KEY_NAME=$(gcloud services api-keys list --project "$PROJECT_ID" --filter="displayName=claude-dk" --format="value(name)")
DK_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --format="value(keyString)")
claude mcp add --transport http --scope user google-developer-knowledge \
  https://developerknowledge.googleapis.com/mcp --header "X-Goog-Api-Key: $DK_KEY"
unset DK_KEY
```
La key está **restringida** a esa sola API: si se filtra, no sirve para nada más. Aun así, no la pegues en ningún archivo del repo.

**b) Skills oficiales de Google para agentes** (`github.com/google/skills`, Apache-2.0):
```bash
npx skills add google/skills   # elige: bigquery-basics, bigquery-optimization, gcloud, google-cloud-storage-basics
```

### Nota si usas zsh (la shell por defecto de macOS)
En zsh, `$VAR:algo` puede romperse: `:r`, `:t`, `:h`… son *modificadores* de zsh (`"$PROJECT_ID:raw_olist"` se convierte en otra cosa). Por eso el lab siempre escribe `${PROJECT_ID}:raw_olist`, con llaves. Hazlo igual en tus comandos.

## Checkpoint
- `scripts/preflight.sh` termina en "Listo".
- En Claude, `/mcp` muestra `google-developer-knowledge` conectado.
- Pregúntale: *"Usa el MCP de Google: ¿qué es un slot en BigQuery?"*. Debe citar `docs.cloud.google.com`.

## Limpieza
Nada que limpiar: aún no creaste recursos que cobren.

## Preguntas
1. ¿Qué diferencia hay entre `gcloud auth login` y `gcloud auth application-default login`?
2. ¿Por qué una alerta de presupuesto no basta para no gastar?
3. ¿Qué pasa con tus recursos cuando termina el free trial?
