import json

import apache_beam as beam
from apache_beam.testing.test_pipeline import TestPipeline
from apache_beam.testing.util import assert_that, equal_to

from sellout_beam.transforms import REJECTED, ParseAndValidate

RUN_DATE = "2026-11-01"
GOOD = {
    "line_id": "L1",
    "retailer_id": "R01",
    "store_id": "R01-S001",
    "product_id": "p1",
    "sale_date": RUN_DATE,
    "units": 3,
    "net_sales": 30.5,
    "currency": "BRL",
}


def test_valid_line_passes():
    with TestPipeline() as p:
        stores = p | "Stores" >> beam.Create(["R01-S001"])
        res = (
            p
            | beam.Create([("f.jsonl", json.dumps(GOOD))])
            | beam.ParDo(ParseAndValidate(RUN_DATE), valid_stores=beam.pvalue.AsList(stores)).with_outputs(
                REJECTED, main="valid"
            )
        )
        assert_that(res.valid | beam.Map(lambda r: (r["line_id"], r["units"])), equal_to([("L1", 3)]), label="v")
        assert_that(res[REJECTED], equal_to([]), label="r")


def test_each_error_goes_to_dead_letter_with_its_code():
    bad = [
        ("{not json", "malformed_json"),
        (json.dumps({**GOOD, "units": -2}), "non_positive_units"),
        (json.dumps({**GOOD, "store_id": "R01-S999"}), "unknown_store"),
        (json.dumps({**GOOD, "sale_date": "01/11/2026"}), "bad_date"),
        (json.dumps({**GOOD, "sale_date": "2026-10-31"}), "date_mismatch"),
        (json.dumps({**GOOD, "product_id": None}), "missing_field"),
        (json.dumps({**GOOD, "units": "tres"}), "bad_number"),
    ]
    with TestPipeline() as p:
        stores = p | "Stores" >> beam.Create(["R01-S001"])
        res = (
            p
            | beam.Create([("f.jsonl", line) for line, _ in bad])
            | beam.ParDo(ParseAndValidate(RUN_DATE), valid_stores=beam.pvalue.AsList(stores)).with_outputs(
                REJECTED, main="valid"
            )
        )
        assert_that(res.valid, equal_to([]), label="v")
        assert_that(res[REJECTED] | beam.Map(lambda r: r["error_code"]), equal_to([c for _, c in bad]), label="r")
