"""Pipeline: feed JSONL del día → validación → BigQuery (válidas) + dead-letter (rechazos).

Local (sin GCP, escribe JSONL en ./out-beam):
    python -m sellout_beam.pipeline --run_date 2026-11-01 \
        --input_root ../../out --sink local --local_output_dir ../../out-beam

Dataflow (desde tu máquina):
    python -m sellout_beam.pipeline --run_date 2026-11-01 \
        --input_root gs://$LANDING_BUCKET --sink bigquery --output_project $PROJECT_ID \
        --runner DataflowRunner --project $PROJECT_ID --region $REGION \
        --temp_location gs://$TEMP_BUCKET/dataflow/tmp --staging_location gs://$TEMP_BUCKET/dataflow/staging \
        --service_account_email $SA_DATAFLOW --max_num_workers 2 --machine_type e2-standard-2 \
        --setup_file ./setup.py
"""

from __future__ import annotations

import json
import logging

import apache_beam as beam
from apache_beam.io.textio import ReadFromText, ReadFromTextWithFilename, WriteToText
from apache_beam.options.pipeline_options import PipelineOptions, SetupOptions

from .transforms import REJECTED, ParseAndValidate, store_ids

VALID_SCHEMA = {
    "fields": [
        {"name": "line_id", "type": "STRING", "mode": "REQUIRED"},
        {"name": "retailer_id", "type": "STRING", "mode": "REQUIRED"},
        {"name": "store_id", "type": "STRING", "mode": "REQUIRED"},
        {"name": "product_id", "type": "STRING", "mode": "REQUIRED"},
        {"name": "sale_date", "type": "DATE", "mode": "REQUIRED"},
        {"name": "units", "type": "INT64", "mode": "REQUIRED"},
        {"name": "net_sales", "type": "NUMERIC", "mode": "REQUIRED"},
        {"name": "currency", "type": "STRING", "mode": "REQUIRED"},
        {"name": "source_file", "type": "STRING", "mode": "REQUIRED"},
    ]
}
REJECT_SCHEMA = {
    "fields": [
        {"name": "feed_date", "type": "DATE", "mode": "REQUIRED"},
        {"name": "source_file", "type": "STRING", "mode": "REQUIRED"},
        {"name": "raw_line", "type": "STRING", "mode": "NULLABLE"},
        {"name": "error_code", "type": "STRING", "mode": "REQUIRED"},
        {"name": "error_detail", "type": "STRING", "mode": "NULLABLE"},
    ]
}


class SelloutOptions(PipelineOptions):
    @classmethod
    def _add_argparse_args(cls, parser):
        parser.add_argument("--run_date", required=True, help="YYYY-MM-DD: la partición que se procesa")
        parser.add_argument("--input_root", required=True, help="raíz local o gs://bucket del feed")
        parser.add_argument("--sink", default="bigquery", choices=["bigquery", "local"])
        parser.add_argument("--output_project", default=None, help="proyecto de BigQuery (sink=bigquery)")
        parser.add_argument("--output_dataset", default="raw_sellout")
        parser.add_argument("--local_output_dir", default="out-beam")


def run(argv: list[str] | None = None) -> None:
    opts = PipelineOptions(argv)
    o = opts.view_as(SelloutOptions)
    opts.view_as(SetupOptions).save_main_session = False
    part = f"date={o.run_date}"
    feed_glob = f"{o.input_root.rstrip('/')}/sellout/{part}/sellout_*.jsonl"
    stores_path = f"{o.input_root.rstrip('/')}/masters/{part}/stores.jsonl"

    with beam.Pipeline(options=opts) as p:
        stores = store_ids(p | "ReadStores" >> ReadFromText(stores_path))
        results = (
            p
            | "ReadFeed" >> ReadFromTextWithFilename(feed_glob)
            | "Validate"
            >> beam.ParDo(ParseAndValidate(o.run_date), valid_stores=beam.pvalue.AsList(stores)).with_outputs(
                REJECTED, main="valid"
            )
        )
        valid, rejected = results.valid, results[REJECTED]

        if o.sink == "local":
            out = o.local_output_dir.rstrip("/")
            valid | "ValidJson" >> beam.Map(json.dumps) | "WriteValid" >> WriteToText(f"{out}/valid", ".jsonl")
            rejected | "RejJson" >> beam.Map(json.dumps) | "WriteRej" >> WriteToText(f"{out}/rejected", ".jsonl")
            return

        # Idempotencia: cada corrida REEMPLAZA solo la partición de su día (decorador $YYYYMMDD + WRITE_TRUNCATE).
        decorator = o.run_date.replace("-", "")
        common = dict(
            method=beam.io.WriteToBigQuery.Method.FILE_LOADS,  # load jobs: gratis y atómicos por partición
            create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,  # las tablas las crea el lab05 / Terraform
            write_disposition=beam.io.BigQueryDisposition.WRITE_TRUNCATE,
        )
        valid | "WriteValidBQ" >> beam.io.WriteToBigQuery(
            table=f"{o.output_project}:{o.output_dataset}.sellout_lines${decorator}", schema=VALID_SCHEMA, **common
        )
        rejected | "WriteRejectsBQ" >> beam.io.WriteToBigQuery(
            table=f"{o.output_project}:{o.output_dataset}.sellout_rejects${decorator}", schema=REJECT_SCHEMA, **common
        )


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    run()
