#!/usr/bin/env python3
"""
sqlite_logic_check.py - Optional LOGIC cross-check of the SQL scripts outside PostgreSQL

WHAT THIS IS
    A second, independent engine (SQLite, bundled with Python) is used to confirm that the
    aggregation, window and ranking logic in the SQL scripts runs and gives sensible results.
    It loads the CSV into an in-memory SQLite database, applies MECHANICAL dialect rewrites to
    the SQL text, runs every statement and prints the results.

    Rewrites applied (PostgreSQL -> SQLite): schema-qualified names (banking.transactions ->
    banking_transactions), TO_CHAR / EXTRACT / DATE_TRUNC('month') -> strftime / date(),
    the !~ operator -> REGEXP, generate_series calendars -> recursive CTEs,
    PERCENTILE_CONT(q) WITHIN GROUP (ORDER BY x) -> a Python aggregate with the same linear
    interpolation, CORR -> a Python aggregate, date - date -> julianday difference.

WHAT THIS IS NOT
    It is NOT a PostgreSQL execution and does not prove the scripts run on PostgreSQL (syntax,
    types, planner behaviour and the rewritten constructs can differ). It cannot test
    01_schema_and_load.sql, information_schema / pg_catalog queries (tagged "-- [PG-ONLY]"),
    or the exact semantics of RANGE/INTERVAL frames. Only running the scripts in PostgreSQL verifies them.

USAGE
    python python/sqlite_logic_check.py --input data/raw/indian_banking_transactions.csv
    python python/sqlite_logic_check.py --input <csv or zip> --output documentation/evidence/sqlite_logic_check.txt
    python python/sqlite_logic_check.py --input <csv> --files 04_advanced_analytical_queries.sql
"""
import argparse
import io
import math
import re
import sqlite3
import sys
import zipfile
from pathlib import Path

import pandas as pd

SQL_DIR = Path(__file__).resolve().parent.parent / "sql"
DEFAULT_FILES = ["02_data_quality_checks.sql", "03_exploratory_analysis.sql",
                 "04_advanced_analytical_queries.sql", "05_views.sql"]


class PctCont:
    """PERCENTILE_CONT(q): linear interpolation between the two closest ranks (PostgreSQL semantics)."""
    def __init__(self):
        self.v, self.q = [], None

    def step(self, value, q):
        self.q = q
        if value is not None:
            self.v.append(float(value))

    def finalize(self):
        if not self.v:
            return None
        v = sorted(self.v)
        pos = self.q * (len(v) - 1)
        lo, hi = int(math.floor(pos)), int(math.ceil(pos))
        return v[lo] + (v[hi] - v[lo]) * (pos - lo)


class Corr:
    """CORR(y, x): Pearson correlation coefficient."""
    def __init__(self):
        self.n = self.sx = self.sy = self.sxx = self.syy = self.sxy = 0.0

    def step(self, y, x):
        if x is None or y is None:
            return
        self.n += 1; self.sx += x; self.sy += y
        self.sxx += x * x; self.syy += y * y; self.sxy += x * y

    def finalize(self):
        if self.n < 2:
            return None
        cov = self.sxy - self.sx * self.sy / self.n
        vx = self.sxx - self.sx ** 2 / self.n
        vy = self.syy - self.sy ** 2 / self.n
        return None if vx <= 0 or vy <= 0 else cov / math.sqrt(vx * vy)


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
    con.execute("CREATE INDEX idx_customer ON banking_transactions (customer_id)")
    con.create_function("REGEXP", 2, lambda p, s: 1 if re.search(p, s or "") else 0)
    con.create_aggregate("PCTCONT", 2, PctCont)
    con.create_aggregate("CORR", 2, Corr)
    return con


CAL_SQLITE = ("calendar AS (SELECT MIN(transaction_date) AS day FROM banking_transactions "
              "UNION ALL SELECT date(day, '+1 day') FROM calendar "
              "WHERE day < (SELECT MAX(transaction_date) FROM banking_transactions))")
MON_SQLITE = ("months AS (SELECT date(MIN(transaction_date), 'start of month') AS month_start FROM banking_transactions "
              "UNION ALL SELECT date(month_start, '+1 month') FROM months "
              "WHERE month_start < (SELECT date(MAX(transaction_date), 'start of month') FROM banking_transactions))")


def rewrite(sql: str) -> str:
    recursive = "generate_series" in sql
    sql = re.sub(r"calendar AS \(.*?AS g\s*\)", CAL_SQLITE, sql, flags=re.S)
    sql = re.sub(r"months AS \(.*?AS g\s*\)", MON_SQLITE, sql, flags=re.S)
    if recursive:
        sql = re.sub(r"^\s*WITH ", "WITH RECURSIVE ", sql, count=1)
    sql = re.sub(r"banking\.(v_\w+)", r"banking_\1", sql)
    sql = (sql.replace("banking.transactions", "banking_transactions")
              .replace("raw_data.transactions_raw", "raw_transactions_raw")
              .replace("CREATE OR REPLACE VIEW", "CREATE VIEW"))
    sql = re.sub(r"(\w+) !~ ('[^']*')", r"NOT (\1 REGEXP \2)", sql)
    sql = re.sub(r"EXTRACT\(DAY FROM \((\w+\.)?month_start \+ INTERVAL '1 month' - INTERVAL '1 day'\)\)",
                 lambda m: "CAST(strftime('%d', date(" + (m.group(1) or '') + "month_start, '+1 month', '-1 day')) AS INTEGER)", sql)
    sql = re.sub(r"CAST\(DATE_TRUNC\('month', (\w+(?:\.\w+)?)\) AS DATE\)", r"date(\1, 'start of month')", sql)
    fmt = {"HOUR": "%H", "DOW": "%w", "YEAR": "%Y", "MONTH": "%m", "DAY": "%d"}
    sql = re.sub(r"EXTRACT\((HOUR|DOW|YEAR|MONTH|DAY)\s+FROM\s+([\w.]+)\)",
                 lambda m: f"CAST(strftime('{fmt[m.group(1)]}', {m.group(2)}) AS INTEGER)", sql)
    tc = {"YYYY-MM-DD": "%Y-%m-%d", "YYYY-MM": "%Y-%m", "YYYY": "%Y"}
    sql = re.sub(r"TO_CHAR\(([^,()]+(?:\([^()]*\))?),\s*'(YYYY-MM-DD|YYYY-MM|YYYY)'\)",
                 lambda m: f"strftime('{tc[m.group(2)]}', {m.group(1)})", sql)
    sql = re.sub(r"PERCENTILE_CONT\(([\d.]+)\) WITHIN GROUP \(ORDER BY ([^()]*(?:\([^()]*\))?[^()]*)\)",
                 r"PCTCONT(\2, \1)", sql)
    sql = sql.replace("(txn_date - prev_txn_date)", "CAST(julianday(txn_date) - julianday(prev_txn_date) AS INTEGER)")
    sql = sql.replace("(t.transaction_date + t.transaction_time)", "(t.transaction_date || ' ' || t.transaction_time)")
    return sql


def statements(path: Path):
    t = path.read_text(encoding="utf-8")
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    t = t.replace("-- [PG-ONLY]", "PGONLYMARK")
    t = re.sub(r"--[^\n]*", "", t)
    return [s.strip() for s in t.split(";") if s.strip()]


def run_file(con, path: Path, out: list, max_rows=30):
    errors = ok = skipped = 0
    for i, s in enumerate(statements(path), 1):
        label = f"{path.name} statement {i}"
        if "PGONLYMARK" in s:
            out.append(f"{label}: SKIPPED (PG-only)")
            skipped += 1
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
            ok += 1
        except Exception as e:  # report and carry on
            errors += 1
            out.append(f"{label}: ERROR {e}")
    out.append(f"-- {path.name}: {ok} ran, {skipped} skipped (PG-only), {errors} error(s)")
    return errors


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True)
    ap.add_argument("--output")
    ap.add_argument("--files", nargs="*", default=DEFAULT_FILES, help="SQL file names inside sql/")
    a = ap.parse_args()
    pd.set_option("display.width", 220)
    pd.set_option("display.max_columns", 40)
    con = build_db(load_raw(Path(a.input)))
    out = ["SQLITE LOGIC CROSS-CHECK (not a PostgreSQL execution)", "=" * 78]
    errs = 0
    for name in a.files:
        p = SQL_DIR / name
        if not p.exists():
            out.append(f"{name}: not found, skipped")
            continue
        errs += run_file(con, p, out)
        if name.startswith("02_"):
            res = pd.read_sql("SELECT result, COUNT(*) AS checks FROM banking_v_reconciliation_checks GROUP BY result", con)
            out.append("RECONCILIATION SUMMARY: " + ", ".join(f"{r.result}={r.checks}" for r in res.itertuples()))
        if name.startswith("05_"):
            views = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='view' AND name LIKE 'banking_v_%' "
                                               "AND name <> 'banking_v_reconciliation_checks' ORDER BY name")]
            for v in views:
                try:
                    n = con.execute(f"SELECT COUNT(*) FROM {v}").fetchone()[0]
                    out.append(f"view {v}: {n} row(s)")
                except Exception as e:
                    errs += 1
                    out.append(f"view {v}: ERROR {e}")
        out.append("=" * 78)
    text = "\n".join(out)
    print(text)
    if a.output:
        Path(a.output).parent.mkdir(parents=True, exist_ok=True)
        Path(a.output).write_text(text + "\n", encoding="utf-8")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
