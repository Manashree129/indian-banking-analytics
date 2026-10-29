#!/usr/bin/env python3
"""
sqlite_logic_check.py - Optional LOGIC cross-check of sql/02 and sql/03 outside PostgreSQL

WHAT THIS IS
    A second, independent engine (SQLite, bundled with Python) is used to confirm that the
    reconciliation expected-values and the aggregation logic in the SQL scripts are right.
    It loads the CSV into an in-memory SQLite database, applies a few MECHANICAL dialect
    rewrites to the SQL text (schema-qualified names, TO_CHAR, EXTRACT, the !~ operator),
    runs every statement, and prints the results.

WHAT THIS IS NOT
    It is NOT a PostgreSQL execution and does not prove the scripts run on PostgreSQL.
    It cannot test: 01_schema_and_load.sql, PERCENTILE_CONT queries and the
    information_schema / pg_catalog queries (statements tagged "-- [PG-ONLY]" are skipped).
    Only running the scripts in PostgreSQL verifies them.

USAGE
    python python/sqlite_logic_check.py --input data/raw/indian_banking_transactions.csv
    python python/sqlite_logic_check.py --input data/raw/indian_banking_transactions.csv ^
           --output documentation/evidence/day2_sqlite_logic_check.txt
"""
import argparse
import io
import re
import sqlite3
import sys
import zipfile
from pathlib import Path

import pandas as pd

SQL_DIR = Path(__file__).resolve().parent.parent / "sql"


def load_raw(path: Path) -> pd.DataFrame:
    kw = dict(dtype=str, keep_default_na=False)
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as z:
            name = [n for n in z.namelist() if n.lower().endswith(".csv")][0]
            with z.open(name) as f:
                return pd.read_csv(io.TextIOWrapper(f, encoding="utf-8"), **kw)
    return pd.read_csv(path, **kw)


def build_db(raw: pd.DataFrame) -> sqlite3.Connection:
    df = raw.copy()
    for c in ["transaction_amount", "account_balance", "emi_amount"]:
        df[c] = df[c].astype(float)
    for c in ["credit_score", "has_loan", "is_fraud", "transaction_hour"]:
        df[c] = df[c].astype(int)
    con = sqlite3.connect(":memory:")
    raw.to_sql("raw_transactions_raw", con, index=False)      # stands in for raw_data.transactions_raw
    df.to_sql("banking_transactions", con, index=False)       # stands in for banking.transactions
    con.create_function("REGEXP", 2, lambda p, s: 1 if re.search(p, s or "") else 0)
    return con


def rewrite(sql: str) -> str:
    sql = (sql.replace("banking.v_reconciliation_checks", "banking_v_reconciliation_checks")
              .replace("banking.transactions", "banking_transactions")
              .replace("raw_data.transactions_raw", "raw_transactions_raw")
              .replace("CREATE OR REPLACE VIEW", "CREATE VIEW"))
    sql = re.sub(r"(\w+) !~ ('[^']*')", r"NOT (\1 REGEXP \2)", sql)
    fmt = {"HOUR": "%H", "DOW": "%w", "YEAR": "%Y"}
    sql = re.sub(r"EXTRACT\((HOUR|DOW|YEAR) FROM (\w+)\)",
                 lambda m: f"CAST(strftime('{fmt[m.group(1)]}', {m.group(2)}) AS INTEGER)", sql)
    tc = {"YYYY-MM-DD": "%Y-%m-%d", "YYYY-MM": "%Y-%m", "YYYY": "%Y"}
    sql = re.sub(r"TO_CHAR\(([^,()]+(?:\([^()]*\))?),\s*'(YYYY-MM-DD|YYYY-MM|YYYY)'\)",
                 lambda m: f"strftime('{tc[m.group(2)]}', {m.group(1)})", sql)
    return sql


def statements(path: Path):
    t = path.read_text(encoding="utf-8")
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    t = t.replace("-- [PG-ONLY]", "PGONLYMARK")
    t = re.sub(r"--[^\n]*", "", t)
    return [s.strip() for s in t.split(";") if s.strip()]


def run_file(con, path: Path, out: list, max_rows=30):
    errors = 0
    for i, s in enumerate(statements(path), 1):
        label = f"{path.name} statement {i}"
        if "PGONLYMARK" in s:
            out.append(f"{label}: SKIPPED (PG-only)")
            continue
        try:
            cur = con.execute(rewrite(s))
            if cur.description:
                d = pd.DataFrame(cur.fetchall(), columns=[c[0] for c in cur.description])
                out.append(f"{label}: OK, {len(d)} row(s)")
                out.append(d.to_string(index=False) if len(d) <= max_rows
                           else d.head(8).to_string(index=False) + f"\n... {len(d)} rows")
            else:
                out.append(f"{label}: OK (no result set)")
        except Exception as e:  # report and carry on
            errors += 1
            out.append(f"{label}: ERROR {e}")
    return errors


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True)
    ap.add_argument("--output")
    a = ap.parse_args()
    pd.set_option("display.width", 220)
    pd.set_option("display.max_columns", 30)
    con = build_db(load_raw(Path(a.input)))
    out = ["SQLITE LOGIC CROSS-CHECK (not a PostgreSQL execution)", "=" * 78]
    errs = run_file(con, SQL_DIR / "02_data_quality_checks.sql", out)
    res = pd.read_sql("SELECT result, COUNT(*) AS checks FROM banking_v_reconciliation_checks GROUP BY result", con)
    out += ["", "RECONCILIATION SUMMARY: " + ", ".join(f"{r.result}={r.checks}" for r in res.itertuples()), "=" * 78]
    errs += run_file(con, SQL_DIR / "03_exploratory_analysis.sql", out)
    text = "\n".join(out)
    print(text)
    if a.output:
        Path(a.output).parent.mkdir(parents=True, exist_ok=True)
        Path(a.output).write_text(text + "\n", encoding="utf-8")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
