import json
from datetime import date

import pytest

from sellout_gen import feed, masters
from sellout_gen.main import run

CSV = "product_id,product_category_name\n" + "".join(f"p{i:04d},cat_{i % 7}\n" for i in range(500))


@pytest.fixture
def catalog():
    return masters.load_catalog(CSV)


def test_catalog_is_deterministic_and_sized(catalog):
    assert len(catalog) == masters.CATALOG_SIZE
    assert catalog == masters.load_catalog(CSV)


def test_same_date_same_output(catalog):
    d = date(2026, 11, 1)
    p, s = masters.products_snapshot(catalog, d), masters.stores_snapshot(d)
    assert feed.generate(d, p, s) == feed.generate(d, p, s)


def test_manifest_adds_up(catalog):
    d = date(2026, 11, 1)
    files, m = feed.generate(d, masters.products_snapshot(catalog, d), masters.stores_snapshot(d))
    total = sum(len(v) for v in files.values())
    assert m["total_lines"] == total
    assert m["expected_valid_lines"] + m["expected_rejected_lines"] == total
    assert m["expected_rejected_lines"] == sum(m["rejects_by_kind"].values())
    assert m["expected_rejected_lines"] > 0, "el feed debe traer errores para practicar"


def test_masters_change_over_time(catalog):
    early = {p.product_id: p for p in masters.products_snapshot(catalog, date(2026, 2, 1))}
    late = {p.product_id: p for p in masters.products_snapshot(catalog, date(2026, 11, 1))}
    changed = [pid for pid in early if early[pid].list_price != late[pid].list_price]
    assert 0 < len(changed) < len(early), "algunos precios cambian, no todos"


def test_valid_lines_have_expected_schema(catalog):
    d = date(2026, 11, 1)
    files, _ = feed.generate(d, masters.products_snapshot(catalog, d), masters.stores_snapshot(d))
    keys = {"line_id", "retailer_id", "store_id", "product_id", "sale_date", "units", "net_sales", "currency"}
    parsed = 0
    for lines in files.values():
        for line in lines:
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            assert set(rec) == keys
            parsed += 1
    assert parsed > 0


def test_run_writes_layout_with_success_last(tmp_path):
    csv_path = tmp_path / "products.csv"
    csv_path.write_text(CSV)
    run(date(2026, 11, 1), str(csv_path), str(tmp_path / "out"))
    base = tmp_path / "out"
    assert (base / "sellout/date=2026-11-01/_SUCCESS").exists()
    assert (base / "masters/date=2026-11-01/products.jsonl").exists()
    assert json.loads((base / "sellout/date=2026-11-01/_manifest.json").read_text())["total_lines"] > 0
