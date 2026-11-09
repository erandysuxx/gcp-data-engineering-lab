"""Maestros sintéticos de producto y tienda, deterministas y con cambios en el tiempo (para SCD2).

Todo se deriva de hashes: la misma fecha produce siempre el mismo resultado, sin estado guardado.
"""

from __future__ import annotations

import csv
import hashlib
import io
from dataclasses import asdict, dataclass
from datetime import date, timedelta

EPOCH = date(2026, 1, 5)  # lunes: inicio de la "historia" de los maestros
CATALOG_SIZE = 300  # productos de Olist que se venden en tiendas físicas

BRANDS = ["Aurea", "Lumen", "Verdant", "Nordica", "Solenne", "Brisa", "Kora", "Mirelle"]
RETAILERS = {
    "R01": "Retailer Alfa",
    "R02": "Retailer Beta",
    "R03": "Retailer Gama",
    "R04": "Retailer Delta",
    "R05": "Retailer Epsilon",
}
CITIES = [
    ("sao paulo", "SP"),
    ("rio de janeiro", "RJ"),
    ("belo horizonte", "MG"),
    ("curitiba", "PR"),
    ("porto alegre", "RS"),
    ("salvador", "BA"),
    ("recife", "PE"),
    ("fortaleza", "CE"),
]
FORMATS = ["hiper", "super", "farmacia", "conveniencia"]


def h(*parts: object) -> int:
    """Hash estable (no usa hash() de Python, que cambia entre procesos)."""
    raw = "|".join(str(p) for p in parts).encode()
    return int.from_bytes(hashlib.sha256(raw).digest()[:8], "big")


def weeks_between(start: date, end: date) -> list[date]:
    """Lunes de cada semana desde start hasta end (inclusive)."""
    out, d = [], start - timedelta(days=start.weekday())
    while d <= end:
        out.append(d)
        d += timedelta(days=7)
    return out


@dataclass(frozen=True)
class Product:
    product_id: str
    category: str
    brand: str
    list_price: float
    snapshot_date: str


@dataclass(frozen=True)
class Store:
    store_id: str
    retailer_id: str
    retailer_name: str
    city: str
    state: str
    store_format: str
    snapshot_date: str


def load_catalog(products_csv_text: str) -> list[tuple[str, str]]:
    """Elige CATALOG_SIZE productos de Olist (determinista) → [(product_id, category)]."""
    rows = list(csv.DictReader(io.StringIO(products_csv_text)))
    rows = [r for r in rows if r.get("product_category_name")]
    rows.sort(key=lambda r: h("catalog", r["product_id"]))
    return [(r["product_id"], r["product_category_name"]) for r in rows[:CATALOG_SIZE]]


def products_snapshot(catalog: list[tuple[str, str]], d: date) -> list[Product]:
    """Estado del maestro de productos en la fecha d.

    - Precio: sube 5 % cada semana "de cambio" (≈1 de cada 15 semanas por producto).
    - Marca: se reasigna en semanas raras (≈1 de cada 60), para ver SCD2 en atributos no numéricos.
    """
    snap = []
    for pid, category in catalog:
        base = 5 + (h("price", pid) % 14500) / 100  # 5.00 – 150.00
        brand_idx = h("brand", pid) % len(BRANDS)
        price_changes = 0
        for monday in weeks_between(EPOCH, d):
            if h("pchg", pid, monday) % 15 == 0:
                price_changes += 1
            if h("bchg", pid, monday) % 60 == 0:
                brand_idx = (brand_idx + 1) % len(BRANDS)
        price = round(base * (1.05**price_changes), 2)
        snap.append(Product(pid, category, BRANDS[brand_idx], price, d.isoformat()))
    return snap


def stores_snapshot(d: date) -> list[Store]:
    """Estado del maestro de tiendas en d. El formato de tienda cambia en semanas raras (SCD)."""
    snap = []
    for rid, rname in RETAILERS.items():
        n_stores = 4 + h("nstores", rid) % 5  # 4–8 tiendas por retailer
        for i in range(1, n_stores + 1):
            sid = f"{rid}-S{i:03d}"
            city, state = CITIES[h("city", sid) % len(CITIES)]
            fmt_idx = h("fmt", sid) % len(FORMATS)
            for monday in weeks_between(EPOCH, d):
                if h("fchg", sid, monday) % 40 == 0:
                    fmt_idx = (fmt_idx + 1) % len(FORMATS)
            snap.append(Store(sid, rid, rname, city, state, FORMATS[fmt_idx], d.isoformat()))
    return snap


def to_dicts(items) -> list[dict]:
    return [asdict(x) for x in items]
