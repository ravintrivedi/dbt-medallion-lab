# dbt Medallion Lab: Postgres + dbt Core + GitHub Actions

A hands-on exercise that builds a **bronze → silver → gold** pipeline with **dbt Core (open source)** on a local **PostgreSQL 16** warehouse in Docker, with **Git-based CI/CD in GitHub Actions**.

Everything here is open source and free: dbt Core (Apache 2.0), dbt-postgres, PostgreSQL, SQLFluff, pre-commit and GitHub Actions (free for public repos).

**Time:** about 60–90 minutes. If you're short on time, do steps 1–8 and 10 (the core of the exercise).

---

## What you'll build

```
 CSV files ──► load_raw.py ──► raw.*            (stands in for Fivetran: lands data as-is)
                                  │
                       BRONZE     ▼  views, 1:1 with raw, no transformation
                        brz_customers · brz_products · brz_orders · brz_order_items · brz_payments
                                  │
                       SILVER     ▼  tables: typed, cleaned, de-duplicated, conformed
                        slv_customers · slv_products · slv_orders (incremental/merge)
                        slv_order_items · slv_payments · int_order_totals (ephemeral)
                        snp_customers (snapshot, SCD Type 2) · country_codes (seed)
                                  │
                       GOLD       ▼  tables: business-ready star schema + KPIs (contracts enforced)
                        fct_orders · dim_customers · dim_products · agg_daily_revenue
                                  │
                                  ▼
                        exposure: exec_revenue_dashboard
```

The raw data is deliberately messy, so the silver layer has real work to do:

| Problem in the raw data | Where it gets fixed |
|---|---|
| Everything lands as `text` | Silver casts to `date`, `timestamp`, `integer`, `numeric` |
| Status variants: `PLACED `, `complete`, `canceled` | `slv_orders` conforms them to 5 values |
| Countries: `uk`, `UK`, `United Kingdom`, `GB`, `USA`… | `country_codes` seed maps them to ISO codes |
| Exact duplicate order rows re-sent by the source | `row_number()` de-duplication |
| Same order re-sent each time its status changes | Incremental `merge` on `order_id` |
| Customers who move or change their email | `snp_customers` snapshot keeps SCD2 history |
| Blank emails, orders with no customer | Warn-level tests flag them without blocking the pipeline |
| Money in pence as text | `cents_to_currency()` macro |

### How the medallion layers map to dbt conventions

| Medallion | dbt-style name | In this repo | Materialization |
|---|---|---|---|
| Raw / landing | sources | `raw.*` (declared in `_bronze__sources.yml`) | loaded by EL tool |
| Bronze | base / staging | `models/bronze/brz_*` | `view` |
| Silver | staging + intermediate | `models/silver/slv_*`, `int_*` | `table`, `incremental`, `ephemeral` |
| Gold | marts | `models/gold/fct_*`, `dim_*`, `agg_*` | `table` + contracts |

### Repo layout

```
.
├── .github/
│   ├── workflows/ci.yml            # PR: lint + build/test on a throw-away Postgres
│   ├── workflows/cd.yml            # merge to main: prod build, manifest, docs to GitHub Pages
│   ├── workflows/deploy-local.yml  # optional: self-hosted runner deploys to your laptop
│   └── dependabot.yml
├── data/batch_1, data/batch_2      # two days of raw CSV extracts
├── scripts/load_raw.py             # mini EL tool
├── models/bronze | silver | gold   # the medallion layers (+ YAML docs & tests)
├── snapshots/snp_customers.yml     # SCD2
├── seeds/country_codes.csv         # reference data
├── macros/                         # generate_schema_name, cents_to_currency
├── tests/                          # singular test + custom generic test
├── analyses/                       # compiled-only SQL
├── docker-compose.yml              # Postgres 16
├── profiles.yml                    # dev / ci / prod targets, all secrets from env vars
├── dbt_project.yml, packages.yml
├── .sqlfluff, .pre-commit-config.yaml, Makefile, requirements.txt
```

---

## Step 0: Prerequisites

| Tool | Notes |
|---|---|
| **Docker** | Docker Desktop, or a fully open-source option: Colima or Rancher Desktop (macOS) or Docker Engine/Podman (Linux) |
| **Python 3.10–3.13** | `python3 --version` |
| **Git** + a **GitHub account** | The repo should be **public** if you want free GitHub Pages for the docs |
| Optional | A SQL client (DBeaver Community, or `psql`) and VS Code with the *dbt Power User* extension |

> **Windows:** everything works. Activate the venv with `.venv\Scripts\activate` and run the commands directly instead of using `make`.

---

## Step 1: Start the warehouse

```bash
unzip dbt-medallion-lab.zip && cd dbt-medallion-lab
docker compose up -d --wait
docker ps          # dbt-warehouse should show (healthy)
```

This gives you Postgres 16 on `localhost:5432`, with database `warehouse` and user/password `dbt` / `dbt`.

> Port 5432 already in use? Change it to `"5433:5432"` in `docker-compose.yml` and `export DBT_PORT=5433`.

---

## Step 2: Install dbt and connect

```bash
python3 -m venv .venv
source .venv/bin/activate              # Windows: .venv\Scripts\activate
pip install -r requirements.txt        # dbt-core 1.12, dbt-postgres, sqlfluff, pre-commit
dbt --version
dbt deps                               # installs dbt_utils into dbt_packages/
dbt debug                              # should end with "All checks passed!"
```

`profiles.yml` sits in the repo root and dbt finds it automatically. It defines three **targets**, all reading credentials from env vars (with local defaults):

| Target | Used by | Schemas created |
|---|---|---|
| `dev` (default) | you, locally | `dev_bronze`, `dev_silver`, `dev_gold`, `dev_snapshots` |
| `ci` | pull-request workflow | `ci_pr_<n>_bronze`, … |
| `prod` | CD / deploy | `bronze`, `silver`, `gold`, `snapshots` |

Naming is controlled by `macros/generate_schema_name.sql`. Read it, because it's a classic interview question (*"How do you isolate dev/CI from prod in dbt?"*).

`dbt deps` also creates `package-lock.yml`. Commit it so CI installs the same package versions.

---

## Step 3: Land the raw data (the "EL" in ELT)

```bash
python scripts/load_raw.py --batch 1
```

This creates schema `raw` with 5 tables. Every column is `text`, plus `_batch_id` and `_loaded_at`. Have a look:

```bash
docker exec -it dbt-warehouse psql -U dbt -d warehouse
```
```sql
select status, count(*) from raw.orders group by 1 order by 1;    -- see the messy variants
select distinct country from raw.customers;
\q
```

> In production this is Fivetran's job. dbt only does the **T**.

---

## Step 4: Build it one layer at a time

```bash
dbt seed                            # loads country_codes reference data
dbt run  --select tag:bronze        # 5 views
dbt run  --select tag:silver        # cleaned tables (+ incremental slv_orders)
dbt run  --select tag:gold          # star schema
dbt snapshot                        # SCD2 baseline
```

Then do it the way you would in production, with one command that runs **seeds, models, snapshots and tests in DAG order** and skips anything downstream of a failure:

```bash
dbt build
```

Expected result: `PASS=57 WARN=2 ERROR=0`. The two warnings are planted data-quality issues (a blank email, and order lines whose order had no customer), set to `severity: warn` so they get reported without blocking the run.

Useful selectors to practise:

```bash
dbt ls --select +fct_orders           # everything upstream of fct_orders
dbt ls --select slv_orders+           # everything downstream of slv_orders
dbt build --select slv_customers+     # rebuild a model and all its children
dbt compile --select fct_orders       # see the rendered SQL in target/compiled/
```

Query the gold layer:

```sql
select * from dev_gold.agg_daily_revenue order by order_date;
select customer_segment, count(*), sum(lifetime_revenue) from dev_gold.dim_customers group by 1;
```

---

## Step 5: Understand the tests (dbt's quality layer)

| Type | Example in this repo | File |
|---|---|---|
| Built-in generic tests | `unique`, `not_null`, `accepted_values`, `relationships` | `_silver__models.yml` |
| Package tests | `dbt_utils.accepted_range`, `dbt_utils.equality` | silver/gold YAML |
| **Custom generic test** | `non_negative` | `tests/generic/test_non_negative.sql` |
| **Singular test** | every revenue order fully paid | `tests/assert_orders_fully_paid.sql` |
| **Unit tests** (dbt 1.8+) | status normalisation + dedup; customer segmentation | `unit_tests:` in silver/gold YAML |
| **Source freshness** | warn after 24h, error after 72h | `_bronze__sources.yml` |
| **Model contracts** | column names/types + PK enforced on `fct_orders`, `dim_customers` | `_gold__models.yml` |

```bash
dbt test --select test_type:unit       # unit tests only: mocked inputs, no real data
dbt test --select test_type:data       # data tests
dbt source freshness
```

**Data tests vs unit tests:** data tests check the *data* after a build. Unit tests check the *logic* against hand-written inputs before the model is built, which makes them a natural fit for CI.

---

## Step 6: Incremental models and snapshots (day 2)

Simulate the next day's load. It contains 50 new orders, status updates for 25 existing orders, 8 new customers and 3 customers who moved or changed email.

```bash
python scripts/load_raw.py --batch 2
dbt build
```

Look for `MERGE 75` on `slv_orders` (only the new rows were processed) and `INSERT 0 11` on the snapshot.

```sql
-- still one row per order, statuses updated in place
select count(*), count(distinct order_id) from dev_silver.slv_orders;      -- 198 | 198

-- SCD2 history: old row closed, new row current
select customer_id, city, email, dbt_valid_from, dbt_valid_to
from dev_snapshots.snp_customers
where customer_id in ('C003','C008','C015')
order by customer_id, dbt_valid_from;
```

Open `models/silver/slv_orders.sql` and find:
* `is_incremental()`: the watermark filter on `_loaded_at` only runs on incremental runs
* `unique_key='order_id'` + `incremental_strategy='merge'`
* `dbt build --full-refresh --select slv_orders` rebuilds it from scratch

---

## Step 7: Docs and lineage

```bash
dbt docs generate
dbt docs serve --port 8080       # open http://localhost:8080, then the lineage graph icon (bottom right)
```

Because of `persist_docs`, the descriptions are also written into Postgres as table and column comments.

---

## Step 8: Put it in Git and on GitHub

```bash
git init -b main
pre-commit install                 # runs SQLFluff + YAML checks on every commit
git add -A
git commit -m "Initial medallion pipeline"
```

Create an **empty** repo on GitHub (no README), then:

```bash
git remote add origin https://github.com/<you>/dbt-medallion-lab.git
git push -u origin main
```

Pushing to `main` triggers the **CD** workflow (Actions tab). The `release` job builds the whole prod target on a fresh Postgres and saves `manifest.json`.

### Protect `main` (this turns CI into a gate)

Settings → Branches → **Add branch ruleset** (or *Add classic branch protection rule*) for `main`:
* ✅ Require a pull request before merging
* ✅ Require status checks to pass → add **`Lint SQL`** and **`dbt build (ephemeral Postgres)`** (they show up after CI has run once)

---

## Step 9: CI, the pull-request workflow

`ci.yml` runs on every PR into `main`:

1. **Lint SQL**: SQLFluff, with no database needed. Failures show as inline annotations on the PR.
2. **dbt build**: starts a Postgres *service container*, lands batch 1, runs `dbt build`, lands batch 2, runs `dbt build` again (so incremental and snapshot logic are tested on every PR), then checks freshness, generates docs and uploads artifacts.

### Exercise A: a good change

```bash
git checkout -b feature/items-sold
```
In `models/gold/agg_daily_revenue.sql`, add `sum(item_count) as items_sold,` under `net_revenue`, then:
```bash
dbt build --select agg_daily_revenue+
git commit -am "Add items_sold to daily revenue"
git push -u origin feature/items-sold
```
Open the PR on GitHub, watch both checks go green, then **merge**. CD runs automatically.

### Exercise B: break it on purpose (so you see CI catch it)

```bash
git checkout main && git pull && git checkout -b feature/oops
```
In `models/silver/slv_orders.sql`, delete the line `when 'complete' then 'completed'`. Push and open a PR.
→ The **unit test** `test_slv_orders_dedupes_and_normalises_status` fails before the model is even built, and everything downstream of `slv_orders` is skipped. The merge button stays blocked. Revert the change and push again to watch it go green.

Other things worth breaking:
* Change a column type in `fct_orders.sql` (e.g. `cast(item_count as int)`). The **contract** fails the build.
* Write `SELECT` in capitals. **SQLFluff** fails in the lint job, and locally `pre-commit` blocks the commit first.

---

## Step 10: CD, deploying on merge

`cd.yml` runs on every push to `main`:
* **release**: `dbt build --target prod` on a clean database, `dbt docs generate`, then the prod `manifest.json` gets uploaded as an artifact
* **publish-docs** (opt-in): publishes the dbt docs site to GitHub Pages
  1. Settings → Pages → Source: **GitHub Actions**
  2. Settings → Secrets and variables → Actions → **Variables** tab → `PUBLISH_DOCS` = `true`
  3. Re-run CD. The docs URL appears on the job summary.

### Optional (advanced): real deployment to your laptop with a self-hosted runner

GitHub's cloud runners can't reach `localhost` on your machine. So to deploy into the Postgres you keep, install a **self-hosted runner**. This is the same pattern used to deploy into a warehouse inside a private network.

1. Settings → Actions → Runners → **New self-hosted runner**. Follow the commands GitHub shows (download, `./config.sh`, `./run.sh`). Keep it running in a terminal.
2. Add the repo variable `LOCAL_DEPLOY` = `true`.
3. Merge any PR. `deploy-local.yml` runs on your machine:
   * first run: full `dbt build --target prod`
   * later runs: **Slim CD**, which runs `dbt build --select state:modified+ --state <previous manifest>`, so only changed models and their children are rebuilt
   * manual "Run workflow" with `full_refresh` ticked rebuilds everything

Check it: `select * from gold.agg_daily_revenue;` on your local database.

---

## Step 11: Slim CI with `state:modified` + `--defer`

On a big project you don't rebuild 2,000 models on every PR. You build **only what changed** and *defer* unchanged parents to prod. Try it locally:

```bash
# 1. build "prod" locally and keep its manifest as the comparison state
dbt build --target prod
mkdir -p prod-artifacts && cp target/manifest.json prod-artifacts/

# 2. change a model (e.g. add a column to agg_daily_revenue.sql), then:
dbt ls    --select state:modified+ --state prod-artifacts       # what changed?
dbt build --select state:modified+ --defer --state prod-artifacts
```

Only `agg_daily_revenue` gets built in `dev_gold`. Check `target/run/.../agg_daily_revenue.sql` and you'll see it reads `"gold"."fct_orders"` (prod) instead of rebuilding fct_orders in dev. That's `--defer`.

> In CI on GitHub-hosted runners the database is empty, so there's no prod to defer to. That's why `ci.yml` does a full build (fine at this size). With a persistent warehouse such as Snowflake, you'd download the `prod-manifest` artifact from the last CD run and run the same command. dbt platform (Cloud) does this for you in its CI jobs.

---

## Step 12: Challenges (do these without looking anything up)

1. **New gold model**: `fct_order_items` (grain = order line) with `line_amount`, plus `unique` + `relationships` tests.
2. **Customer history in gold**: build `dim_customers_history` from `snp_customers`, with `is_current` and the validity dates.
3. **Quarantine pattern**: instead of silently dropping orphan orders in `slv_orders`, route them into `slv_orders_quarantine` and add a test that warns when it isn't empty.
4. **Late-arriving data guard**: change the `slv_orders` merge so an older `updated_at` can never overwrite a newer one.
5. **Macro**: write `normalize_status(column)` and use it in `slv_orders`. Make sure the unit test still passes.
6. **Microbatch**: convert `slv_orders` to `incremental_strategy='microbatch'` with `event_time='updated_at'` (dbt 1.9+), and explain when you'd choose it over `merge`.
7. **Semantic layer prep**: add a `semantic_models:` + `metrics:` block for net revenue on `fct_orders`.
8. **CI improvement**: add a step that posts `dbt build` results as a PR comment, or fails the PR if any model lacks a description.

---

## Interview talking points this lab gives you

* **Medallion ↔ dbt**: bronze = sources + base views, silver = staging/intermediate, gold = marts. dbt adds lineage, tests, docs and environments on top of a layering pattern that is otherwise just a convention.
* **Environments**: one codebase, many targets. `generate_schema_name` isolates dev, CI and prod. In Snowflake you'd typically use zero-copy clones or separate databases.
* **Quality layers**: unit tests (logic, pre-build) → data tests (post-build) → contracts (shape guarantees for downstream consumers) → source freshness (pipeline SLAs). Severity `warn` vs `error` is a business decision.
* **Incremental strategies**: `append`, `merge`, `delete+insert`, `insert_overwrite`, `microbatch`. Choose based on update patterns, warehouse and cost. Watermarks and late-arriving data are the usual pitfalls.
* **SCD2** via snapshots, versus building history from CDC (Fivetran history mode).
* **CI/CD**: PR gate (lint + build + test in an isolated schema) → merge → deploy, plus Slim CI (`state:modified+`, `--defer`) to keep CI cheap at scale. On the dbt platform this is built in: CI jobs, deferral, and docs via dbt Explorer.
* **The ELT story**: Fivetran lands raw data (here, `load_raw.py`) → dbt transforms it in the warehouse → BI reads gold (here, the exposure).
* **dbt Core v2**: v2 is now in alpha, built on the Fusion engine foundations and Apache 2.0 licensed. You can check whether a project is ready with `dbt parse --use-v2-parser`. When I ran that on this project it parsed cleanly, but Postgres isn't a supported v2 adapter yet (Snowflake, BigQuery, Databricks, Redshift and DuckDB are), so it needs `DBT_ALLOW_EXPERIMENTAL_ADAPTERS=true`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `dbt debug` connection refused | `docker compose up -d --wait`. Check the port isn't taken by a local Postgres |
| `dbt_utils` not found | `dbt deps` |
| `relation raw.orders does not exist` | Run `python scripts/load_raw.py --batch 1` first |
| Contract error `numeric` vs `bigint` etc. | The SQL's output type changed: fix the SQL or the YAML `data_type` |
| Want a clean slate | `make reset` (drops all lab schemas), or `docker compose down -v` (drops the volume) |
| CI can't find status checks for branch protection | They appear only after the workflow has run once on a PR |
| `deploy-local` job stuck "Queued" | The self-hosted runner isn't running (`./run.sh`), or `LOCAL_DEPLOY` is set without a runner |

## Command cheat sheet

```bash
dbt deps | debug | seed | run | test | build | snapshot | compile | docs generate | docs serve
dbt build --select tag:silver           # by tag
dbt build --select +model+              # model with parents and children
dbt build --full-refresh -s slv_orders  # rebuild incremental from scratch
dbt test  --select test_type:unit
dbt source freshness
dbt ls --select state:modified+ --state prod-artifacts
python scripts/load_raw.py --batch 1|2  |  --reset
sqlfluff lint models  |  sqlfluff fix models
```
