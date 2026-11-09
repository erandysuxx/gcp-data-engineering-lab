"""CLI del generador.

Ejemplos:
    # local, sin nube
    python -m sellout_gen.main --date 2026-11-01 \
        --products-csv ../data/olist/olist_products_dataset.csv --out ../out

    # contra Cloud Storage (lo que hace el Cloud Run Job)
    python -m sellout_gen.main --date 2026-11-01 \
        --products-csv gs://$LANDING_BUCKET/olist/olist_products_dataset.csv --out gs://$LANDING_BUCKET
"""

from __future__ import annotations

import argparse
import json
import logging
import os
from datetime import UTC, date, datetime, timedelta

from . import feed, masters
from .io import Writer, read_text

log = logging.getLogger("sellout_gen")


def jsonl(rows: list[dict]) -> str:
    return "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)


def run(run_date: date, products_csv: str, out: str) -> dict:
    catalog = masters.load_catalog(read_text(products_csv))
    products = masters.products_snapshot(catalog, run_date)
    stores = masters.stores_snapshot(run_date)
    files, manifest = feed.generate(run_date, products, stores)

    w = Writer(out)
    part = f"date={run_date.isoformat()}"
    # 1) Maestros del día (snapshots completos)
    w.write(f"masters/{part}/products.jsonl", jsonl(masters.to_dicts(products)))
    w.write(f"masters/{part}/stores.jsonl", jsonl(masters.to_dicts(stores)))
    # 2) Feed de sell-out, un archivo por retailer
    for rid, lines in sorted(files.items()):
        w.write(f"sellout/{part}/sellout_{rid}.jsonl", "\n".join(lines) + "\n")
    # 3) Manifiesto y, AL FINAL, la bandera _SUCCESS: quien la ve sabe que todo lo demás ya está escrito
    w.write(f"sellout/{part}/_manifest.json", json.dumps(manifest, indent=2) + "\n", "application/json")
    w.write(f"sellout/{part}/_SUCCESS", "", "text/plain")
    log.info(
        "feed %s: %s líneas (%s rechazos esperados)",
        run_date,
        manifest["total_lines"],
        manifest["expected_rejected_lines"],
    )
    return manifest


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    yesterday = (datetime.now(UTC).date() - timedelta(days=1)).isoformat()
    p.add_argument(
        "--date",
        default=os.environ.get("RUN_DATE") or yesterday,
        help="YYYY-MM-DD (o env RUN_DATE). Por defecto: ayer en UTC (útil si lo dispara Cloud Scheduler)",
    )
    p.add_argument("--products-csv", default=os.environ.get("PRODUCTS_CSV"), help="CSV de productos de Olist")
    p.add_argument("--out", default=os.environ.get("OUT_ROOT"), help="carpeta local o gs://bucket[/prefijo]")
    a = p.parse_args()
    if not (a.products_csv and a.out):
        p.error("--products-csv y --out son obligatorios (o PRODUCTS_CSV y OUT_ROOT)")
    manifest = run(date.fromisoformat(a.date), a.products_csv, a.out)
    print(json.dumps({k: manifest[k] for k in ("feed_date", "total_lines", "expected_rejected_lines")}))


if __name__ == "__main__":
    main()
