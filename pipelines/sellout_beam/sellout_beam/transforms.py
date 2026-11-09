"""Transformaciones puras del pipeline. No dependen de GCP: se prueban con TestPipeline."""

from __future__ import annotations

import json
from datetime import date

import apache_beam as beam
from apache_beam import pvalue

VALID, REJECTED = "valid", "rejected"
REQUIRED = ("line_id", "retailer_id", "store_id", "product_id", "sale_date", "units", "net_sales", "currency")


class ParseAndValidate(beam.DoFn):
    """Recibe (archivo, línea) y emite la fila tipada (salida principal) o un rechazo (salida 'rejected').

    El maestro de tiendas del día llega como *side input*: una lista chica que cada worker recibe completa.
    """

    def __init__(self, run_date: str):
        self.run_date = run_date

    def process(self, element, valid_stores):
        source_file, raw = element
        stores = valid_stores if isinstance(valid_stores, set) else set(valid_stores)

        def reject(code: str, detail: str = ""):
            return pvalue.TaggedOutput(
                REJECTED,
                {
                    "feed_date": self.run_date,
                    "source_file": source_file,
                    "raw_line": raw[:4000],
                    "error_code": code,
                    "error_detail": detail[:500],
                },
            )

        if not raw.strip():
            return  # líneas vacías: no son datos ni errores
        try:
            rec = json.loads(raw)
        except json.JSONDecodeError as e:
            yield reject("malformed_json", str(e))
            return
        if not isinstance(rec, dict):
            yield reject("malformed_json", "la línea no es un objeto JSON")
            return
        missing = [k for k in REQUIRED if rec.get(k) in (None, "")]
        if missing:
            yield reject("missing_field", ",".join(missing))
            return
        try:
            sale_date = date.fromisoformat(str(rec["sale_date"]))
        except ValueError:
            yield reject("bad_date", str(rec["sale_date"]))
            return
        if sale_date.isoformat() != self.run_date:
            yield reject("date_mismatch", f"{sale_date} != {self.run_date}")
            return
        try:
            units, net_sales = int(rec["units"]), float(rec["net_sales"])
        except (TypeError, ValueError):
            yield reject("bad_number", f"units={rec['units']} net_sales={rec['net_sales']}")
            return
        if units <= 0:
            yield reject("non_positive_units", str(units))
            return
        if net_sales < 0:
            yield reject("negative_sales", str(net_sales))
            return
        if rec["store_id"] not in stores:
            yield reject("unknown_store", str(rec["store_id"]))
            return
        yield {
            "line_id": str(rec["line_id"]),
            "retailer_id": str(rec["retailer_id"]),
            "store_id": str(rec["store_id"]),
            "product_id": str(rec["product_id"]),
            "sale_date": sale_date.isoformat(),
            "units": units,
            "net_sales": round(net_sales, 2),
            "currency": str(rec["currency"]),
            "source_file": source_file,
        }


def store_ids(lines: beam.PCollection) -> beam.PCollection:
    """Extrae store_id del maestro de tiendas (JSONL)."""
    return lines | "ParseStores" >> beam.Map(json.loads) | "StoreId" >> beam.Map(lambda r: r["store_id"])
