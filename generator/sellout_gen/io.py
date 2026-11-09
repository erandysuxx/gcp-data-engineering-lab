"""Lectura y escritura sobre disco local o Cloud Storage (gs://) con la misma interfaz."""

from __future__ import annotations

import os
from pathlib import Path


def _split_gs(uri: str) -> tuple[str, str]:
    bucket, _, blob = uri.removeprefix("gs://").partition("/")
    return bucket, blob


def read_text(path: str) -> str:
    if path.startswith("gs://"):
        from google.cloud import storage

        bucket, blob = _split_gs(path)
        return storage.Client().bucket(bucket).blob(blob).download_as_text()
    return Path(path).read_text(encoding="utf-8")


class Writer:
    """Escribe archivos bajo un prefijo raíz local o gs://bucket[/prefijo]."""

    def __init__(self, root: str):
        self.root = root.rstrip("/")
        self._bucket = None
        if self.root.startswith("gs://"):
            from google.cloud import storage

            bucket, self._prefix = _split_gs(self.root)
            self._bucket = storage.Client().bucket(bucket)

    def write(self, rel_path: str, content: str, content_type: str = "application/x-ndjson") -> str:
        if self._bucket is not None:
            name = f"{self._prefix}/{rel_path}" if self._prefix else rel_path
            self._bucket.blob(name).upload_from_string(content, content_type=content_type)
            return f"gs://{self._bucket.name}/{name}"
        full = Path(self.root) / rel_path
        os.makedirs(full.parent, exist_ok=True)
        full.write_text(content, encoding="utf-8")
        return str(full)
