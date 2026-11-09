# Copia este archivo a .env.lab (está en .gitignore), edita las 3 primeras variables y cárgalo
# en cada terminal nueva:   source .env.lab
#
# Todo el lab usa estas variables: nunca escribas el ID de tu proyecto a mano en un comando.

export PROJECT_ID="de-lab-CAMBIAME"            # ID de tu proyecto de GCP (único en todo GCP)
export LAB_ACCOUNT="tu-correo@gmail.com"        # cuenta con la que haces `gcloud auth login`
export GITHUB_REPO="tu-usuario/gcp-data-engineering-lab"   # tu copia del repo (lab07)

export REGION="us-central1"                     # una sola región para TODO el lab

# Nombres derivados (no los cambies)
export LANDING_BUCKET="${PROJECT_ID}-landing"
export ARCHIVE_BUCKET="${PROJECT_ID}-archive"
export TEMP_BUCKET="${PROJECT_ID}-temp"
export TFSTATE_BUCKET="${PROJECT_ID}-tfstate"
export AR_REPO="lab-images"                     # Artifact Registry (imágenes Docker)
export IMAGE_PREFIX="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}"

# Service accounts (una por componente: mínimo privilegio)
export SA_GENERATOR="sa-generator@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_DATAFLOW="sa-dataflow@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_DATAFORM="sa-dataform@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_COMPOSER="sa-composer@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_DEPLOYER="sa-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

# gcloud/bq usan este proyecto por defecto en ESTA terminal (no toca tu config global)
export CLOUDSDK_CORE_PROJECT="$PROJECT_ID"
