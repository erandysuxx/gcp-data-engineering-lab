# Interview questions with model answers

> About 60 questions a GCP Data Engineer (mid-level) interview is likely to include, grouped by topic. Try to answer out loud first, then open the model answer. The answers are short on purpose: in an interview, say the core idea in 30–60 seconds and let the interviewer ask for more. Whenever you can, add "in my lab I…" with a real number you measured.

Topics: [BigQuery](#bigquery) · [Modeling](#data-modeling) · [Dataflow / Beam](#dataflow-and-apache-beam) · [Airflow / Composer](#airflow-and-composer) · [Storage](#cloud-storage) · [Cloud Run](#cloud-run-and-serverless) · [Data Quality & Observability](#data-quality-and-observability) · [CI/CD & Terraform](#cicd-and-terraform) · [Domain](#domain-sell-out-and-supply-chain) · [Behavioral / Agile](#behavioral-and-agile)

## BigQuery

**1. What is the difference between partitioning and clustering?**
<details><summary>Model answer</summary>

Partitioning splits a table into segments by one column (usually a date) or by ingestion time; a constant filter on that column lets BigQuery skip whole partitions, and the dry run can estimate the cost precisely. Clustering sorts data inside the storage blocks by up to four columns, so filters on those columns read fewer blocks, but the saving is only known after the query runs. I partition by the date most queries filter on and cluster by the high-cardinality columns used in filters and joins, such as retailer, store and product.
</details>

**2. How do you reduce BigQuery cost?**
<details><summary>Model answer</summary>

Read less: select only the needed columns (no `SELECT *`), filter on the partition column with constant expressions, cluster by common filters, and require partition filters on big tables. Write less: incremental models instead of full rebuilds, and the right storage billing model per dataset. Then measure: `total_bytes_billed` in `INFORMATION_SCHEMA.JOBS`, labels on jobs to attribute cost per pipeline, and audit logs to find tables nobody reads. On the capacity side, compare on-demand with editions once the workload is stable.
</details>

**3. On-demand vs editions: how do you choose?**
<details><summary>Model answer</summary>

On-demand charges per TiB processed: simple and good for spiky or small workloads, with a cap on concurrent slots per project. Editions charge for slot capacity over time through reservations, with a baseline that is always billed plus autoscaling. I start on-demand, look at slot usage and bytes billed in `INFORMATION_SCHEMA.JOBS` for a few weeks, and move to a reservation when the workload is predictable enough that paying for capacity is cheaper, or when I need workload isolation.
</details>

**4. What does a dry run tell you, and what doesn't it tell you?**
<details><summary>Model answer</summary>

It validates the query and estimates the bytes it will process, for free, which is great for checking partition pruning before running. It does not tell you the real cost of DML: an `UPDATE` or a `MERGE` with an update clause also bills the full size of the partitions it modifies, and which partitions get touched depends on the data. For those, I measure `total_bytes_billed` after the run.
</details>

**5. Why might a query with `WHERE date >= (SELECT MAX(date) FROM target)` scan the whole table?**
<details><summary>Model answer</summary>

Because partition pruning requires a constant expression on the partitioning column, and a subquery is dynamic: its value is only known at runtime. I replace it with a constant window like `DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)` plus an idempotent `MERGE`, or pass the date as a literal from the orchestrator, and I confirm the pruning with a dry run.
</details>

**6. Batch load vs Storage Write API vs streaming inserts: when do you use each?**
<details><summary>Model answer</summary>

Batch load jobs from Cloud Storage for files: they are free (shared slot pool) and atomic per job; that's what my daily pipeline uses. The Storage Write API (gRPC) for streaming or high-throughput writes: it is the recommended API, cheaper than the legacy method, with exactly-once semantics and a pending mode for atomic batch commits. Legacy streaming inserts (`tabledata.insertAll`, now documented as Storage Write API REST) only for existing code. If messages come from Pub/Sub and need no transformation, a BigQuery subscription writes them directly.
</details>

**7. How do you write an upsert in BigQuery?**
<details><summary>Model answer</summary>

With `MERGE`: match source and target on the business key, `WHEN MATCHED THEN UPDATE`, `WHEN NOT MATCHED THEN INSERT`. I deduplicate the source first (for example with `QUALIFY ROW_NUMBER() OVER (PARTITION BY key ORDER BY updated_at DESC) = 1`), otherwise the `MERGE` fails when two source rows match one target row. I also add a partition filter on the target in the `ON` condition so it doesn't touch the whole table.
</details>

**8. How do you control who sees what in BigQuery?**
<details><summary>Model answer</summary>

IAM at project and dataset level for the basics, following least privilege. Authorized views to expose a subset of data without granting access to the source tables. Row-level access policies to filter rows, for example by country or retailer. Policy tags on columns to restrict or mask sensitive fields. Service accounts per pipeline so each job only has the access it needs.
</details>

**9. What are time travel and fail-safe, and how do they affect cost?**
<details><summary>Model answer</summary>

Time travel lets you query or restore a table as it was within a window of 2 to 7 days; fail-safe keeps data another 7 days for emergency recovery through support. With logical storage billing they're included; with physical billing they're charged separately. So a table that is fully rewritten every day can be cheaper on logical billing. The model is set per dataset, so I decide based on the write pattern of each dataset.
</details>

**10. How would you find the most expensive queries in a project?**
<details><summary>Model answer</summary>

Query `region-xx.INFORMATION_SCHEMA.JOBS` for the last N days, excluding `statement_type = 'SCRIPT'` to avoid double counting parent jobs, and order by `total_bytes_billed` (on-demand) or `total_slot_ms` (capacity). Group by user, by label or by query hash to find patterns, then look at the worst ones: missing partition filters, `SELECT *`, repeated full rebuilds.
</details>

## Data modeling

**11. What is the grain of a fact table, and why define it first?**
<details><summary>Model answer</summary>

The grain is what exactly one row represents, for example "units sold per day, per store, per product, per retailer". You define it first because it decides which dimensions apply, which measures are additive and what the unique key is. In my lab, I enforce the grain with a `uniqueKey` assertion in Dataform; if it fails, something upstream is duplicating rows.
</details>

**12. Star vs snowflake schema?**
<details><summary>Model answer</summary>

Star: facts joined directly to denormalized dimensions. It's simpler to query and works well in BigQuery, where storage is cheap and fewer joins help. Snowflake normalizes dimensions into several tables; it saves space and avoids repeating attributes, but adds joins. For analytics on BigQuery I default to star, and I'd also consider nested fields for one-to-many attributes.
</details>

**13. How do you implement SCD type 2?**
<details><summary>Model answer</summary>

Each dimension row has a surrogate key, the business key, the attributes, `valid_from`, `valid_to` and an `is_current` flag. On each load, compare the incoming snapshot with the current rows (a hash of the tracked attributes helps). For changed keys, close the current row by setting `valid_to` and `is_current = false`, and insert a new current row; new keys are inserted directly. In my lab I do it with an explicit `MERGE` in Dataform, and facts join to the version that was valid on the transaction date.
</details>

**14. What is fan-out, and how do you avoid it?**
<details><summary>Model answer</summary>

Fan-out happens when you join a table to another with a one-to-many relationship and the rows multiply, so sums get inflated. A classic case: joining order payments (several per order) to order items and summing item prices. Avoid it by aggregating each side to the same grain before joining, and by testing totals before and after the join.
</details>

**15. What is an accumulating snapshot fact?**
<details><summary>Model answer</summary>

A fact table with one row per process instance, such as an order or a delivery, with a date column per milestone (ordered, approved, shipped, delivered) and duration measures between them. The row is updated as the process advances. It's ideal for lead time and OTIF analysis. In my lab, `fct_deliveries` is an accumulating snapshot.
</details>

**16. Why use surrogate keys and an unknown member?**
<details><summary>Model answer</summary>

Surrogate keys decouple the warehouse from source keys, which can change, collide across sources or be reused, and they are required for SCD2, where one business key has several versions. The unknown member (for example key -1) catches facts whose dimension reference is missing or late, so they still appear in totals instead of disappearing in an inner join, and you can monitor how many there are.
</details>

**17. Raw, staging, marts: why three layers?**
<details><summary>Model answer</summary>

Raw is a faithful copy of the source, so you can always reprocess. Staging cleans, types, renames and deduplicates, one model per source table. Marts contain the business models: facts and dimensions. Separating them makes each step testable, and when a business rule changes you rebuild from raw instead of asking the source to resend.
</details>

## Dataflow and Apache Beam

**18. When would you use Dataflow instead of BigQuery SQL?**
<details><summary>Model answer</summary>

When the logic doesn't fit well in SQL: parsing messy or non-tabular files, validating row by row and routing bad records to a dead-letter destination, calling external services, or streaming with windows and late data. If the data is already in BigQuery and the transformation is relational, SQL is simpler, cheaper to maintain and readable by analysts. In my lab, Dataflow only validates the incoming files; everything downstream is SQL in Dataform.
</details>

**19. How do you implement a dead-letter pattern in Beam?**
<details><summary>Model answer</summary>

In the validation `DoFn`, wrap the parsing and validation in a try/except. Valid records go to the main output, and invalid ones go to a tagged output with the raw line and the error reason. The rejected collection is written to its own table (or a bucket), and its count is reconciled with the source manifest. One bad record never fails the job, and every rejection is auditable.
</details>

**20. What is a side input?**
<details><summary>Model answer</summary>

A small dataset made available to every worker alongside the main collection, for example a mapping from EAN to SKU or the list of valid store IDs, used to enrich or validate each element. It must fit in worker memory; for large lookups, join with `CoGroupByKey` or do the join in BigQuery instead.
</details>

**21. GroupByKey vs CombinePerKey?**
<details><summary>Model answer</summary>

`GroupByKey` shuffles all values for a key to one worker, which is expensive and dangerous with hot keys. `CombinePerKey` (sum, count, mean) does partial aggregation on each worker before the shuffle, so much less data moves. If you only need an aggregate, use a combiner.
</details>

**22. What are watermarks and late data?**
<details><summary>Model answer</summary>

In streaming, events arrive out of order. The watermark is the system's estimate that all events up to a given event time have arrived; when it passes the end of a window, the window can emit results. Events that arrive after that are late data: you decide with allowed lateness and triggers whether to update the result or drop them. In batch, the equivalent problem is late-arriving files, which I handle with reprocessing windows.
</details>

**23. How do you test a Beam pipeline?**
<details><summary>Model answer</summary>

Unit tests with `TestPipeline` and `assert_that` on the DirectRunner: feed a few valid and invalid lines and assert what lands in the main and dead-letter outputs. Pure functions (validation rules) get plain pytest tests. Then a small integration run on Dataflow with a sample file before production. All of that runs in CI except the Dataflow run.
</details>

**24. What is a Flex Template, and why use it?**
<details><summary>Model answer</summary>

A Dataflow pipeline packaged as a container image in Artifact Registry plus a JSON spec in Cloud Storage that declares the parameters. The orchestrator launches it with parameters such as the date, without installing Beam or the pipeline code in Airflow. The image is versioned and built by CI, so you know exactly what runs.
</details>

## Airflow and Composer

**25. How do you make a pipeline idempotent?**
<details><summary>Model answer</summary>

Every run is tied to a logical date and only reads and writes that date's data: files under `date=YYYY-MM-DD/`, and outputs that replace the partition for that date (`WRITE_TRUNCATE` on the partition, or `DELETE` plus `INSERT` in a transaction, or a keyed `MERGE`) instead of appending. Re-running the same date then gives the same result. I verify it in the lab by running the same date twice and checking that counts don't change.
</details>

**26. A DAG run fails halfway. What happens and what do you do?**
<details><summary>Model answer</summary>

Tasks retry according to their retries and backoff; if they still fail, downstream tasks don't run and the DAG run is marked failed, which should trigger an alert. I look at the failed task's log, fix the cause, and clear the failed task so it and its downstream tasks re-run. That's only safe because each task is idempotent; otherwise, re-running a load could duplicate data.
</details>

**27. What is a backfill, and how do you do one safely?**
<details><summary>Model answer</summary>

Running a pipeline for past logical dates, for example after fixing a bug or onboarding a retailer with history. Safely means idempotent tasks, a limit on concurrent runs so you don't overload BigQuery or the sources, running a small range first and validating it, and checking control totals per date. In Airflow 3, backfills are managed by the scheduler, and I always trigger with an explicit logical date.
</details>

**28. What is the difference between catchup and backfill?**
<details><summary>Model answer</summary>

Catchup is a DAG setting: when enabled, the scheduler automatically creates runs for every interval missed since the start date. A backfill is an explicit, on-demand request to run a range of past dates. I usually set catchup to false and do backfills deliberately, so deploying a DAG with an old start date doesn't launch hundreds of runs.
</details>

**29. How do you test a DAG?**
<details><summary>Model answer</summary>

A DAG integrity test in CI: load every file with `DagBag` and fail on import errors or cycles. Unit tests for any Python callables. Checks on DAG structure (expected tasks and dependencies). Then a run in a local or dev environment with a fixed logical date. I also keep top-level code minimal, so parsing is fast and has no side effects.
</details>

**30. Why shouldn't Airflow workers process data?**
<details><summary>Model answer</summary>

Airflow is an orchestrator: its workers have limited resources shared by all DAGs, and heavy processing there slows everything down and doesn't scale. Tasks should delegate the work to services built for it, like BigQuery, Dataflow or Cloud Run jobs, and just launch, wait and check. XCom is for small values like IDs and counts, not datasets.
</details>

**31. What is a deferrable sensor, and why does it matter?**
<details><summary>Model answer</summary>

A classic sensor occupies a worker slot while it waits, for example for a file. A deferrable sensor hands the wait to the triggerer, an async process, and frees the worker until the condition is met. With many sensors waiting for files from many retailers, that's the difference between needing a large environment and a small one.
</details>

## Cloud Storage

**32. How would you lay out a landing bucket for daily files from many sources?**
<details><summary>Model answer</summary>

One prefix per source and per date, for example `sellout/retailer=X/date=YYYY-MM-DD/`, plus a `_SUCCESS` marker and a manifest with row counts. Files are never modified in landing; after successful processing they move to an archive bucket. Uniform bucket-level access, no public access, and lifecycle rules defined in Terraform.
</details>

**33. Which storage class would you use for each bucket?**
<details><summary>Model answer</summary>

Standard for landing and temp, which are read soon after writing. For archived originals that are rarely read, a colder class via a lifecycle rule (Nearline, Coldline or Archive), keeping in mind their minimum storage durations (30, 90 and 365 days) and retrieval fees. Temporary files should be deleted by lifecycle, not archived, because deleting from a cold class early still bills the minimum duration.
</details>

**34. What is soft delete, and when would you turn it off?**
<details><summary>Model answer</summary>

Soft delete keeps deleted or overwritten objects, recoverable and billed, for a retention period that defaults to 7 days. It's good protection for landing and archive. I turn it off on temporary or frequently rewritten buckets, such as Dataflow staging, because there it mainly adds storage cost for data nobody wants back.
</details>

**35. How do you trigger processing when a file lands?**
<details><summary>Model answer</summary>

Event-driven: a Cloud Storage notification triggers a Cloud Run function or Eventarc, which can start a workflow or a job. Schedule-driven: the orchestrator waits with a deferrable sensor on the `_SUCCESS` marker. For a daily batch with dependencies and control totals, I prefer the orchestrator, because a missing file then becomes a visible failure with a timeout, not just "nothing happened".
</details>

## Cloud Run and serverless

**36. Cloud Run jobs vs services vs functions?**
<details><summary>Model answer</summary>

Services listen for HTTP requests and scale with traffic: APIs and webhooks. Jobs run a container to completion and exit, optionally as many parallel tasks with retries: batch work like my data generator. Functions are small pieces of code triggered by events or HTTP, deployed from source. Same platform underneath; you pick by "does it serve requests, or does it run and finish?".
</details>

**37. Cloud Scheduler, Workflows or Composer?**
<details><summary>Model answer</summary>

Cloud Scheduler to trigger one thing at a fixed time. Workflows to chain a few HTTP or API calls with retries and conditions; serverless and billed per step. Composer (Airflow) for many pipelines with dependencies across systems, sensors, backfills and per-task re-runs; it is billed for provisioned capacity even when idle. I don't bring in Composer for a single cron.
</details>

**38. How do you run a Cloud Run job from Airflow and pass parameters?**
<details><summary>Model answer</summary>

Use the Google provider's Cloud Run execute-job operator with overrides, such as environment variables or arguments, carrying the logical date. The job writes its output under a date prefix, so it's idempotent, and the next task checks that the expected objects exist.
</details>

**39. What limits should you keep in mind for Cloud Run jobs?**
<details><summary>Model answer</summary>

Each task has a timeout (10 minutes by default, configurable up to 7 days) and its own retry count; long jobs should checkpoint progress. Parallel tasks get an index environment variable, and your code decides which slice of work each one handles. For distributed processing of large data, Dataflow or Spark is a better fit.
</details>

## Data quality and observability

**40. How do you detect a missing file?**
<details><summary>Model answer</summary>

Each source has an expected arrival time. The DAG waits with a deferrable sensor on the `_SUCCESS` marker for that date's prefix, with a timeout; if it expires, the task fails and alerts. A missing file must look like a failure, not like a day with zero sales. I also keep a file registry table, and a freshness check on the latest date in the mart.
</details>

**41. What are control totals, and why use them?**
<details><summary>Model answer</summary>

The source declares how many rows it sent (a manifest); after loading, you check that the manifest count equals loaded rows plus rejected rows. If it doesn't match, rows were lost or duplicated somewhere, even though every task succeeded. I record the result per run in `ops.control_figures` and fail the DAG if it doesn't balance.
</details>

**42. Where do you validate data quality in a pipeline?**
<details><summary>Model answer</summary>

Shape (schema and types) at ingestion, in Beam, with a dead-letter output. Meaning (uniqueness, not-null, accepted ranges, referential integrity) in Dataform assertions after modeling. Process (freshness, volume, control totals) in the orchestrator, which sees the whole run. Each check sits where it has the information to decide.
</details>

**43. What alerts would you set up for this pipeline?**
<details><summary>Model answer</summary>

Failed DAG run, failed Dataflow job, control totals not balanced, a file not arriving before its deadline, and an unusual volume compared with history. All through Cloud Monitoring notification channels to the team. Every alert has to be actionable: if nobody knows what to do when it fires, it's noise.
</details>

**44. How do you attribute cost to a specific pipeline?**
<details><summary>Model answer</summary>

Labels everywhere: on BigQuery jobs, on Dataflow jobs and on resources such as buckets and Cloud Run jobs, with standard keys like `pipeline`, `layer` and `env`. Labels reach the Cloud Billing export to BigQuery, where you group cost by label. For BigQuery alone, `INFORMATION_SCHEMA.JOBS` also exposes job labels.
</details>

**45. How do you know whether anyone uses a table?**
<details><summary>Model answer</summary>

BigQuery Data Access audit logs are on by default and record a `TableDataRead` event per read; I route them to BigQuery to look at months of history. I cross-check with `referenced_tables` in `INFORMATION_SCHEMA.JOBS`, because results served from cache don't produce a read event. If nobody reads it, I notify the owners and pause the pipeline before deleting anything.
</details>

## CI/CD and Terraform

**46. How do you secure CI access to GCP?**
<details><summary>Model answer</summary>

Workload Identity Federation instead of service account keys. GitHub Actions requests an OIDC token, and a workload identity provider in GCP trusts GitHub's issuer, validates an attribute condition and exchanges the token for short-lived credentials of a deployer service account. The condition uses the numeric repository and owner IDs, not names, because names can be re-registered. No secrets are stored or rotated.
</details>

**47. What does your CI validate in a data repo?**
<details><summary>Model answer</summary>

Lint with ruff, unit tests for Beam transforms and the generator, a DAG integrity test, `dataform compile` and `dataform run --dry-run`, `terraform fmt`, `validate` and `plan`, and actionlint for the workflows themselves. Deploys only happen after merge to main.
</details>

**48. What is Terraform state, and where do you keep it?**
<details><summary>Model answer</summary>

The state maps the configuration to the real resources and their attributes; Terraform uses it to compute the plan. It must be remote and shared: a Cloud Storage bucket with object versioning to recover old versions, and the GCS backend provides locking so two applies can't corrupt it. Access is limited to the pipeline and a few admins, because state can contain sensitive values.
</details>

**49. What is drift, and how do you handle it?**
<details><summary>Model answer</summary>

Drift is the difference between code and reality, usually from manual changes in the console. The next `apply` reverts it to what the code says, without asking. I prevent it by making every infra change go through a PR, and detect it with a scheduled `terraform plan -detailed-exitcode` that alerts when there are pending changes.
</details>

**50. How do you bring manually created resources under Terraform?**
<details><summary>Model answer</summary>

With `import` blocks: declare the resource address and the real ID, write the matching `resource` block (or let `plan -generate-config-out` propose one), and apply. The import happens during apply. Then the plan must show no changes; if it proposes changes, my resource block doesn't describe reality yet. In my lab I adopted the buckets, datasets and service accounts created in earlier labs this way.
</details>

**51. How do you handle dev, qa and prod environments?**
<details><summary>Model answer</summary>

One GCP project per environment for strong isolation of IAM, quotas and billing; the same Terraform code with per-environment variables; automatic deploys to dev and qa after merge; and production behind an approval by someone other than the author, for example GitHub Environments with required reviewers. People don't have write access to prod; only the deployer service account through the pipeline does.
</details>

## Domain: sell-out and supply chain

**52. What's the difference between sell-in, sell-out and sell-through?**
<details><summary>Model answer</summary>

Sell-in is what the manufacturer sells to retailers or distributors, recorded in the manufacturer's own systems. Sell-out is what retailers sell to consumers, reported by each retailer with its own formats and delays. Sell-through relates the two: the share of stock received by the retailer that was sold to consumers in a period. Sell-out is closer to real demand, but it's the messiest data to integrate.
</details>

**53. A retailer sends corrected data for the last four weeks. How do you handle the restatement?**
<details><summary>Model answer</summary>

Treat the new file as the source of truth for that retailer and those dates: register it as a new version, load it, and replace exactly that slice in the fact table (by retailer and date range, using `DELETE` plus `INSERT` in a transaction or a keyed `MERGE`) instead of appending. Because the load is idempotent and keyed by retailer and date, the rest of the data is untouched. I keep the previous version in the archive for audit, and notify downstream users that history changed.
</details>

**54. How would you map retailer product codes to your SKUs?**
<details><summary>Model answer</summary>

Retailers usually report EAN/GTIN or their own item codes. I keep a mapping table from EAN (or retailer code) to SKU, with validity dates because mappings change, and join through it in staging. Unmapped codes go to the unknown member with a count and an alert, so the business can fix the master data instead of the sales silently disappearing.
</details>

**55. How would you calculate OTIF?**
<details><summary>Model answer</summary>

At order-line level: on time if delivered within the agreed window of the committed date, in full if the delivered quantity covers the ordered quantity (with any agreed tolerance). OTIF is the share of lines, or orders, that meet both. The hard part is agreeing on the definitions: requested or confirmed date, tolerance, and whether partial deliveries count. I'd model it as an accumulating snapshot with one row per order line and a date per milestone.
</details>

**56. Why do retailers' calendars matter?**
<details><summary>Model answer</summary>

Retail usually reports in fiscal weeks and 4-4-5 or 4-5-4 months, so periods compare like for like, with the same number of each weekday. If you aggregate by calendar month, comparisons with last year are distorted. A date dimension with both calendars, plus flags for holidays and promotions, solves it.
</details>

## Behavioral and Agile

**57. Tell me about a time you found a data quality issue.**
<details><summary>Model answer</summary>

Use STAR (see `pitch-and-star.md`). Situation: the daily feed loaded green, but totals looked off. Task: find out where rows went. Action: compared the manifest count with loaded plus rejected rows, found the gap, fixed the cause and added the reconciliation as a permanent check. Result: [your number], and that class of error now fails the DAG instead of reaching the dashboard.
</details>

**58. How do you handle a stakeholder asking for "real time"?**
<details><summary>Model answer</summary>

Ask what decision they'll make with the data and how often. Then show the options with their cost and complexity: daily, hourly, near-real-time. Often hourly is enough. If real time is truly needed, scope it to the few metrics that need it rather than the whole model.
</details>

**59. How do you work in an Agile data team?**
<details><summary>Model answer</summary>

Small, vertical increments that deliver usable data (one source end to end before the next), clear acceptance criteria that include data checks, short-lived branches and PRs with review, and demos with real data. Data work has unknowns, such as source quality, so I raise risks early in refinement and timebox investigations.
</details>

**60. Tell me about a mistake you made and what you learned.**
<details><summary>Model answer</summary>

Pick a real, small one, and own it. For example: running a large `MERGE` without measuring its real bytes billed, or creating a resource by hand that Terraform later reverted. Explain the impact, how you fixed it and the guardrail you added (a dry run plus a `total_bytes_billed` check, everything through PRs). Interviewers look for ownership and learning, not perfection.
</details>

**61. Why this role, and why L'Oréal?**
<details><summary>Model answer</summary>

Connect your experience to their context: a large consumer-goods company where Commerce and Supply Chain decisions depend on integrating messy external data (retailer sell-out, e-commerce) with internal data, at scale, on GCP. Say what you want to learn (domain depth, scale) and what you bring (pipelines with quality controls, cost awareness, CI/CD). Be specific about something you learned about the team and its data platform while preparing.
</details>
