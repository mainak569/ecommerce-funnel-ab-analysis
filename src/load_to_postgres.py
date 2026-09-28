"""Clean the raw CSVs and load them into PostgreSQL, then create the analysis views."""
import csv
import io
from pathlib import Path

import pandas as pd
from sqlalchemy import text

from db import PROJECT_ROOT, get_engine

RAW_DIR = PROJECT_ROOT / "data" / "raw"
SQL_DIR = PROJECT_ROOT / "sql"

# parents before children so foreign keys are satisfied
LOAD_ORDER = [
    "products",
    "website_sessions",
    "website_pageviews",
    "orders",
    "order_items",
    "order_item_refunds",
]
CHUNK_SIZE = 100_000


def copy_insert(table, conn, keys, data_iter):
    """pandas to_sql method that uses Postgres COPY instead of row-by-row INSERTs."""
    buf = io.StringIO()
    csv.writer(buf).writerows(data_iter)
    buf.seek(0)
    columns = ", ".join(keys)
    with conn.connection.cursor() as cur:
        cur.copy_expert(f"COPY {table.name} ({columns}) FROM STDIN WITH (FORMAT csv)", buf)


def clean(df):
    df["created_at"] = pd.to_datetime(df["created_at"])
    for col in df.select_dtypes(include=["object", "string"]).columns:
        df[col] = df[col].str.strip().replace("", None)
    return df


def run_sql_file(engine, path):
    with engine.begin() as conn:
        conn.execute(text(Path(path).read_text()))


def load_table(engine, name):
    total = 0
    for chunk in pd.read_csv(RAW_DIR / f"{name}.csv", chunksize=CHUNK_SIZE):
        chunk = clean(chunk)
        chunk.to_sql(name, engine, if_exists="append", index=False, method=copy_insert)
        total += len(chunk)
    print(f"{name}: {total:,} rows loaded")


def main():
    engine = get_engine()
    run_sql_file(engine, SQL_DIR / "01_schema.sql")
    for name in LOAD_ORDER:
        load_table(engine, name)
    run_sql_file(engine, SQL_DIR / "views.sql")
    with engine.begin() as conn:
        conn.execute(text("ANALYZE"))
    print("views created")


if __name__ == "__main__":
    main()
