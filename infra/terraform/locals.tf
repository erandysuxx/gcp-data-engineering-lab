locals {
  landing_bucket = "${var.project_id}-landing"
  archive_bucket = "${var.project_id}-archive"
  temp_bucket    = "${var.project_id}-temp"

  datasets = {
    raw_olist           = "Copia cruda del dataset Olist (canal e-commerce)"
    raw_sellout         = "Feed de sell-out validado por Dataflow + dead-letter + snapshots de maestros"
    staging             = "Modelos de staging de Dataform (limpieza, tipos, dedup)"
    marts               = "Modelo dimensional (estrella) para consumo"
    ops                 = "Operación: cifras de control de los pipelines"
    dataform_assertions = "Vistas de las assertions de Dataform"
    sandbox             = "Experimentos del lab02 (las tablas expiran solas)"
    reporting           = "Vistas autorizadas para compartir sin exponer las tablas base"
  }

  # Tablas que NO crea Dataform ni un load: el esquema es un contrato y vive en infra/schemas/.
  raw_tables = {
    sellout_lines    = { dataset = "raw_sellout", partition = "sale_date", cluster = ["retailer_id", "product_id"] }
    sellout_rejects  = { dataset = "raw_sellout", partition = "feed_date", cluster = ["error_code"] }
    product_snapshot = { dataset = "raw_sellout", partition = "snapshot_date", cluster = ["product_id"] }
    store_snapshot   = { dataset = "raw_sellout", partition = "snapshot_date", cluster = ["store_id"] }
    control_figures  = { dataset = "ops", partition = "run_date", cluster = ["pipeline"] }
  }

  service_accounts = {
    sa-generator = "Cloud Run Job que genera el feed"
    sa-dataflow  = "Workers de Dataflow"
    sa-dataform  = "Ejecuta los workflows de Dataform (strict act-as)"
    sa-composer  = "Workers de Airflow (Composer)"
  }
}
