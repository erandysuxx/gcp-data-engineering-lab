"""Feed diario de sell-out: lo que cada retailer reporta que vendió al consumidor final.

Inyecta errores realistas a propósito para practicar validación, dead-letter y cifras de control.
"""

from __future__ import annotations

import json
import random
from collections import Counter
from datetime import date

from .masters import Product, Store, h

ERROR_RATE = 0.03  # ~3 % de líneas con algún problema
DUPLICATE_RATE = 0.01  # ~1 % de líneas válidas reenviadas (duplicado exacto)
ERROR_KINDS = ["malformed_json", "negative_units", "unknown_store", "bad_date", "missing_product"]


def _line(store: Store, p: Product, d: date, rng: random.Random, n: int) -> dict:
    units = rng.randint(1, 12)
    discount = rng.choice([0, 0, 0, 0.05, 0.10, 0.20])
    return {
        "line_id": f"{d:%Y%m%d}-{store.store_id}-{n:04d}",
        "retailer_id": store.retailer_id,
        "store_id": store.store_id,
        "product_id": p.product_id,
        "sale_date": d.isoformat(),
        "units": units,
        "net_sales": round(units * p.list_price * (1 - discount), 2),
        "currency": "BRL",
    }


def _corrupt(rec: dict, kind: str, d: date) -> str:
    bad = dict(rec)
    if kind == "malformed_json":
        return json.dumps(bad)[:-7]  # JSON truncado: no parsea
    if kind == "negative_units":
        bad["units"] = -abs(bad["units"])
    elif kind == "unknown_store":
        bad["store_id"] = f"{bad['retailer_id']}-S999"
    elif kind == "bad_date":
        bad["sale_date"] = f"{d:%d/%m/%Y}"  # formato no ISO
    elif kind == "missing_product":
        bad["product_id"] = None
    return json.dumps(bad, ensure_ascii=False)


def generate(d: date, products: list[Product], stores: list[Store]) -> tuple[dict[str, list[str]], dict]:
    """Devuelve ({retailer_id: [líneas JSONL]}, manifiesto). Determinista para cada fecha."""
    files: dict[str, list[str]] = {}
    kinds: Counter[str] = Counter()
    duplicates = 0
    for store in stores:
        rng = random.Random(h("feed", d, store.store_id))
        n_lines = rng.randint(25, 60)
        chosen = rng.sample(products, k=min(n_lines, len(products)))
        out = files.setdefault(store.retailer_id, [])
        for n, p in enumerate(chosen, start=1):
            rec = _line(store, p, d, rng, n)
            if rng.random() < ERROR_RATE:
                kind = rng.choice(ERROR_KINDS)
                kinds[kind] += 1
                out.append(_corrupt(rec, kind, d))
                continue
            out.append(json.dumps(rec, ensure_ascii=False))
            if rng.random() < DUPLICATE_RATE:
                duplicates += 1
                out.append(json.dumps(rec, ensure_ascii=False))

    total = sum(len(v) for v in files.values())
    rejects = sum(kinds.values())
    manifest = {
        "feed_date": d.isoformat(),
        "generator_version": "1.0.0",
        "files": [{"name": f"sellout_{rid}.jsonl", "lines": len(lines)} for rid, lines in sorted(files.items())],
        "total_lines": total,
        "expected_valid_lines": total - rejects,
        "expected_rejected_lines": rejects,
        "rejects_by_kind": dict(sorted(kinds.items())),
        "duplicate_lines": duplicates,
        "distinct_valid_lines": total - rejects - duplicates,
    }
    return files, manifest
