"""
Mini "EL" tool: lands CSV files into the `raw` schema of the warehouse.

In real life Fivetran (or Airbyte, etc.) does this step. Each run:
  * creates raw.<table> if it doesn't exist (every column TEXT, exactly as landed)
  * deletes any rows from the same batch (so re-running a batch is idempotent)
  * appends the batch with two metadata columns: _batch_id and _loaded_at

Usage:
    python scripts/load_raw.py --batch 1
    python scripts/load_raw.py --batch 2
    python scripts/load_raw.py --reset          # drop the raw schema and start over

Connection settings come from the same env vars the dbt profile uses.
"""
import argparse
import csv
import os
from pathlib import Path

import psycopg2

DATA_DIR = Path(__file__).resolve().parent.parent / "data"


def connect():
    return psycopg2.connect(
        host=os.getenv("DBT_HOST", "localhost"),
        port=int(os.getenv("DBT_PORT", "5432")),
        user=os.getenv("DBT_USER", "dbt"),
        password=os.getenv("DBT_PASSWORD", "dbt"),
        dbname=os.getenv("DBT_DATABASE", "warehouse"),
    )


def load_batch(conn, batch: int) -> None:
    batch_dir = DATA_DIR / f"batch_{batch}"
    if not batch_dir.exists():
        raise SystemExit(f"No data folder found at {batch_dir}")

    with conn.cursor() as cur:
        cur.execute("create schema if not exists raw")
        for csv_path in sorted(batch_dir.glob("*.csv")):
            table = csv_path.stem
            with csv_path.open(newline="") as f:
                header = next(csv.reader(f))
            cols_ddl = ", ".join(f'"{c}" text' for c in header)
            cols = ", ".join(f'"{c}"' for c in header)

            cur.execute(
                f"create table if not exists raw.{table} "
                f"({cols_ddl}, _batch_id int, _loaded_at timestamptz)"
            )
            cur.execute(f"delete from raw.{table} where _batch_id = %s", (batch,))

            # COPY into a temp table, then stamp the metadata columns on the way in
            cur.execute(f"create temp table _stage ({cols_ddl}) on commit drop")
            with csv_path.open() as f:
                cur.copy_expert(f"copy _stage ({cols}) from stdin with (format csv, header true)", f)
            cur.execute(
                f"insert into raw.{table} ({cols}, _batch_id, _loaded_at) "
                f"select {cols}, %s, now() from _stage",
                (batch,),
            )
            inserted = cur.rowcount
            cur.execute("drop table _stage")
            print(f"  raw.{table:<12} +{inserted} rows (batch {batch})")
    conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--batch", type=int, help="batch number to load (1 or 2)")
    group.add_argument("--reset", action="store_true", help="drop the raw schema")
    args = parser.parse_args()

    conn = connect()
    try:
        if args.reset:
            with conn.cursor() as cur:
                cur.execute("drop schema if exists raw cascade")
            conn.commit()
            print("Dropped schema raw")
        else:
            print(f"Loading batch {args.batch} into schema raw ...")
            load_batch(conn, args.batch)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
