#!/usr/bin/env bash
# Descarga el dataset Olist de Kaggle a data/olist/ (no se versiona).
# Requiere la Kaggle CLI con tu token: https://www.kaggle.com/docs/api  (pip install kaggle)
set -euo pipefail
DEST="${1:-data/olist}"
mkdir -p "$DEST"
kaggle datasets download -d olistbr/brazilian-ecommerce -p "$DEST" --unzip
ls -lh "$DEST"
