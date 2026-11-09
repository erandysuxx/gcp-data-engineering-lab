# Pitch and STAR stories

> What to say about this lab in the interview: a 2-minute architecture pitch to say out loud, three STAR story templates with gaps for **your real numbers**, how to present it honestly as a personal project, and questions to ask the interviewer.

## How to use this document

1. Finish the labs first. Every `[gap]` below must be filled with something you actually did or measured; record the numbers as you go (bytes billed before and after, rows rejected, minutes per run).
2. Read the pitch out loud with a timer. Cut until it fits in 2 minutes without rushing.
3. Rehearse each STAR story in about 90 seconds. The interviewer will interrupt with "why?"; that's good, it means they're interested.
4. Never memorize word for word. Memorize the structure and the numbers.

## The 2-minute pitch

> Say it while drawing the batch architecture from `11-guia-de-decisiones.md`.

"To prepare for this role, I built an end-to-end data platform on GCP around a retail scenario close to yours: daily **sell-out** files from retailers, plus an e-commerce dataset.

The sell-out data comes from a generator I wrote that runs as a **Cloud Run job**. Every day it drops a JSONL file per retailer into a **Cloud Storage** landing bucket, partitioned by date, with deliberately injected errors, a manifest with row counts and a success marker. It also produces snapshots of the product and store master data with changes over time.

A **Dataflow** pipeline, packaged as a **Flex Template**, validates every row. Valid records are loaded into a partitioned raw table in **BigQuery**; invalid ones go to a dead-letter table with the reason. Then **Dataform** builds a star schema: staging models, an incremental daily sell-out fact, an accumulating snapshot for deliveries, and SCD type 2 dimensions for products and stores, all with assertions for grain, nulls and referential integrity.

An **Airflow** DAG on Composer orchestrates the day: a deferrable sensor waits for the file, then it launches Dataflow, runs Dataform, and finally reconciles **control totals**: the manifest count must equal valid plus rejected rows, or the run fails. Every step is idempotent by date, so I could backfill [N] days and re-run any date without duplicates.

Everything is in **Terraform**, and CI/CD runs on **GitHub Actions**: pull requests run linting, unit tests, a DAG integrity test, a Dataform dry-run and a Terraform plan; merges deploy using **Workload Identity Federation**, so there are no service account keys.

The part I learned the most from was cost: partitioning and clustering cut the bytes billed of the main query from [X] to [Y], and I measured it with `INFORMATION_SCHEMA.JOBS`, not with the dry-run estimate."

**Checklist after rehearsing:** Did you say *why* for at least three choices (Dataflow only for validation, Composer for dependencies and backfills, WIF instead of keys)? Did you give one real number? Did you stay under 2 minutes?

## STAR story 1: dead-letter and control totals

**Question it answers:** "Tell me about a time you dealt with bad data" or "How do you make sure your data is correct?"

- **Situation:** "In my pipeline, the daily retailer files had quality problems: malformed JSON, missing store IDs, invalid product codes and dates in the future, around [X %] of rows in my test feed."
- **Task:** "I needed to load the good data on time without losing track of the bad rows, and to be able to prove that nothing was silently dropped."
- **Action:**
  - "In the Beam pipeline I added a validation step with a tagged output: valid rows go to BigQuery, invalid rows go to a dead-letter table with the raw line and the reason."
  - "Each file comes with a manifest. After loading, the Airflow DAG checks that manifest rows equal loaded plus rejected rows and records the result in a control table; if it doesn't balance, the run fails."
  - "[Optional, if it happened: the reconciliation caught a real bug: [describe it, for example empty lines skipped without being counted].]"
- **Result:** "On [N] days of data, [R] rows were rejected with a reason and every run balanced. Bad rows no longer block a file, and a silent loss now fails the pipeline instead of reaching a dashboard. In a real setting, I'd send each retailer its rejection report automatically."

## STAR story 2: BigQuery cost with partitioning and clustering

**Question it answers:** "Tell me about a time you optimized performance or cost."

- **Situation:** "My main analytical query over the sell-out history, [describe it, for example weekly units by retailer and product for one region], was scanning the whole table on every run: [X GB] billed."
- **Task:** "Reduce the cost without changing the results, and measure the improvement with real billing data rather than estimates."
- **Action:**
  - "I partitioned the fact table by sale date and clustered it by [retailer, store, product], the columns the queries filter on."
  - "I fixed an incremental filter that used `SELECT MAX(date)`, which prevented partition pruning, and replaced it with a constant date window plus an idempotent `MERGE`."
  - "I compared `total_bytes_billed` in `INFORMATION_SCHEMA.JOBS` before and after, using labels to find exactly those jobs. I checked partition pruning with the dry run, but measured clustering only after execution, because the dry run can't estimate it."
- **Result:** "Bytes billed went from [X] to [Y] ([Z %] less) for the same result. I also learned that the dry run is not reliable for DML costs, so I measure those after running."

## STAR story 3: CI/CD with Workload Identity Federation

**Question it answers:** "Tell me about a time you improved security or automation" or "How do you deploy data pipelines?"

- **Situation:** "At first, I deployed everything from my laptop with my own credentials: Terraform, the container images and the DAGs. It wasn't reproducible, and the usual next step, a service account key stored as a CI secret, is a long-lived credential that can leak."
- **Task:** "Make every change go through a pull request with automated checks, and deploy from CI without any stored key."
- **Action:**
  - "I wrote a CI workflow that runs ruff, pytest, a DAG integrity test, `dataform compile` and dry-run, `terraform plan` and actionlint on every pull request."
  - "For deployment, I configured Workload Identity Federation: a pool and an OIDC provider for GitHub, with an attribute condition on the numeric repository and owner IDs, so a re-registered name can't impersonate the repo. The workflow exchanges its OIDC token for short-lived credentials of a deployer service account."
  - "I adopted the resources I had created by hand in earlier labs with Terraform `import` blocks, until the plan showed no changes."
- **Result:** "A merge to main now deploys infrastructure, images and DAGs in [N] minutes, with no keys stored anywhere. [Mention one thing CI caught, if it happened, for example a DAG with an import error that would have disappeared from the scheduler.] In a company setting, I'd add a protected production environment with required reviewers, which the free plan of my private repo doesn't support."

## Presenting it honestly as a personal project

This is a strength if you present it well, and a risk if you oversell it.

**Do:**
- Say it plainly: "This is a personal project I built to go deep on the GCP data stack."
- Explain the data: "The e-commerce data is a public dataset; the sell-out feed is synthetic, generated deterministically with errors I injected on purpose, so I could test validation and reprocessing."
- Be precise about scale: "The volumes are small, so I focused on correctness, idempotency, cost measurement and automation; those patterns don't change with scale. What does change at scale is…" (hot keys, slot contention, Composer sizing, many sources).
- Separate what you ran from what you only studied: "I ran Composer 3 for a short session and used the local development environment otherwise, because of cost." "Streaming I've designed but not run."
- Use your real numbers, even if they're small. A small real number beats a large invented one.

**Don't:**
- Present the lab as a production system or as work done for a company.
- Claim experience with tools you only read about. Say "I haven't used it in production; my understanding is… and I'd validate it with a small test".
- Get defensive about it being a lab. Turn it into curiosity: "What would you do differently at your scale?"

A good closing line: "I built it to understand the trade-offs, not only the tools: why Dataflow only for validation, why Composer and not a cron, and how much each choice costs."

## Questions to ask the interviewer

Pick three or four, depending on who is interviewing you (engineer, manager, business).

1. "What does a typical data source look like for the team: how many retailers or sources, and how standardized are their files?"
2. "How is the work split between data engineering, analytics engineering and the business teams? Who owns the data models?"
3. "What's the current orchestration setup, and what would you change if you could?"
4. "How do you handle data quality today? Is there a process when a retailer sends bad or late data?"
5. "How do you deploy changes to pipelines and infrastructure: is everything through CI/CD and Terraform?"
6. "How do you track and manage cloud cost? Do engineers see the cost of their pipelines?"
7. "What does success look like in the first three to six months for this role?"
8. "What is the biggest technical challenge the team is facing this year?"
9. "How do Commerce and Supply Chain use the data day to day? Which decision depends most on it?"
10. "How does the team share knowledge and review work: pairing, design reviews, documentation?"
