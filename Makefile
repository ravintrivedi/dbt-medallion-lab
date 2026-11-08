# Shortcuts (macOS/Linux). Run `make help`.
.PHONY: help up down setup load1 load2 build lint docs reset

help:   ## list commands
	@grep -E '^[a-z0-9]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-8s %s\n", $$1, $$2}'
up:     ## start the Postgres warehouse
	docker compose up -d --wait
down:   ## stop the warehouse
	docker compose down
setup:  ## create venv and install everything
	python3 -m venv .venv && .venv/bin/pip install -r requirements.txt && .venv/bin/dbt deps && .venv/bin/pre-commit install
load1:  ## land raw batch 1
	.venv/bin/python scripts/load_raw.py --batch 1
load2:  ## land raw batch 2
	.venv/bin/python scripts/load_raw.py --batch 2
build:  ## dbt build (dev)
	.venv/bin/dbt build
lint:   ## sqlfluff lint
	.venv/bin/sqlfluff lint models tests analyses
docs:   ## generate and serve dbt docs on :8080
	.venv/bin/dbt docs generate && .venv/bin/dbt docs serve --port 8080
reset:  ## wipe raw + all dbt schemas (keeps the container)
	docker exec dbt-warehouse psql -U dbt -d warehouse -c "drop schema if exists raw, dev_bronze, dev_silver, dev_gold, dev_snapshots, bronze, silver, gold, snapshots cascade;"
