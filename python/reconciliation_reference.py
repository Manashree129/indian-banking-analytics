#!/usr/bin/env python3
"""
reconciliation_reference.py - Independent Python reference values for the PostgreSQL reconciliation

PURPOSE
    sql/02_data_quality_checks.sql returns one row per check with a python_value (typed
    into the SQL from the Day 1/Day 2 profiling) and a postgres_value (computed in the
    database). This script recomputes the Python side FRESH from the CSV so the result
    does not depend on numbers typed into the SQL, and can compare them with an export
    of the PostgreSQL result.

MODES
    1) Print the reference values:
         python python/reconciliation_reference.py --input data/raw/indian_banking_transactions.csv
    2) Compare with the result exported from pgAdmin (CSV with columns check_id, postgres_value):
         python python/reconciliation_reference.py --input data/raw/indian_banking_transactions.csv ^
                --compare path\\to\\02_results.csv
    3) Print expected results for the exploratory queries in sql/03_exploratory_analysis.sql:
         python python/reconciliation_reference.py --input data/raw/indian_banking_transactions.csv --exploratory

    Add --output FILE to save what is printed. Accepts the CSV or the original ZIP.
    Money checksums use exact decimal arithmetic on the raw text (no floating-point error).
"""
import argparse
import io
import sys
import zipfile
from decimal import Decimal
from pathlib import Path

import pandas as pd

TOLERANCE = Decimal("0.005")


def load_frames(path: Path):
    """raw = every column as text exactly as in the file; df = the same data with numeric types."""
    kw = dict(dtype=str, keep_default_na=False)
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as z:
            name = [n for n in z.namelist() if n.lower().endswith(".csv")][0]
            with z.open(name) as f:
                raw = pd.read_csv(io.TextIOWrapper(f, encoding="utf-8"), **kw)
    else:
        raw = pd.read_csv(path, **kw)
    df = raw.copy()
    for c in ["transaction_amount", "account_balance", "emi_amount"]:
        df[c] = df[c].astype(float)
    for c in ["credit_score", "has_loan", "is_fraud", "transaction_hour"]:
        df[c] = df[c].astype(int)
    return raw, df


# (check_id, area, description, function) - the same ids appear in sql/02_data_quality_checks.sql
CHECKS = [
    ("R01", "1 Raw load", "Rows in raw_data.transactions_raw", lambda raw, df: len(raw)),
    ("R02", "1 Raw load", "Distinct transaction_id in raw table", lambda raw, df: raw['transaction_id'].nunique()),
    ("R03", "1 Raw load", "Raw rows with any NULL or empty cell", lambda raw, df: int((raw == '').any(axis=1).sum())),
    ("R04", "1 Raw load", "Raw rows with leading/trailing spaces in any column", lambda raw, df: int(pd.concat([raw[c] != raw[c].str.strip() for c in raw.columns], axis=1).any(axis=1).sum())),
    ("R05", "1 Raw load", "Raw transaction_id not TXN + 9 digits", lambda raw, df: int((~raw['transaction_id'].str.match(r'^TXN[0-9]{9}$')).sum())),
    ("R06", "1 Raw load", "Raw customer_id not CUST + 6 digits", lambda raw, df: int((~raw['customer_id'].str.match(r'^CUST[0-9]{6}$')).sum())),
    ("R07", "1 Raw load", "Raw loan_type equal to the literal text None", lambda raw, df: int((raw['loan_type'] == 'None').sum())),
    ("T01", "2 Typed table", "Rows in banking.transactions", lambda raw, df: len(df)),
    ("T02", "2 Typed table", "Rows lost between raw and typed table", lambda raw, df: len(raw) - len(df)),
    ("T03", "2 Typed table", "Distinct transaction_id", lambda raw, df: df['transaction_id'].nunique()),
    ("T04", "2 Typed table", "Distinct customer_id", lambda raw, df: df['customer_id'].nunique()),
    ("T05", "2 Typed table", "Exact duplicate rows", lambda raw, df: int(df.duplicated().sum())),
    ("T06", "2 Typed table", "Duplicate rows ignoring transaction_id", lambda raw, df: int(df.drop(columns='transaction_id').duplicated().sum())),
    ("T07", "2 Typed table", "loan_type values that are NULL (should be 0)", lambda raw, df: int(df['loan_type'].isna().sum())),
    ("T08", "2 Typed table", "loan_type equal to the literal text None", lambda raw, df: int((df['loan_type'] == 'None').sum())),
    ("T09", "2 Typed table", "Checksum: SUM(transaction_amount)", lambda raw, df: sum(Decimal(x) for x in raw['transaction_amount'])),
    ("T10", "2 Typed table", "Checksum: SUM(account_balance)", lambda raw, df: sum(Decimal(x) for x in raw['account_balance'])),
    ("T11", "2 Typed table", "Checksum: SUM(emi_amount)", lambda raw, df: sum(Decimal(x) for x in raw['emi_amount'])),
    ("T12", "2 Typed table", "Checksum: SUM(credit_score)", lambda raw, df: int(df['credit_score'].sum())),
    ("D01", "3 Dates", "Distinct transaction_date values", lambda raw, df: df['transaction_date'].nunique()),
    ("D02", "3 Dates", "Rows dated before 2019-01-01", lambda raw, df: int((df['transaction_date'] < '2019-01-01').sum())),
    ("D03", "3 Dates", "Rows dated after 2024-01-01", lambda raw, df: int((df['transaction_date'] > '2024-01-01').sum())),
    ("D04", "3 Dates", "Rows in 2019", lambda raw, df: int(df['transaction_date'].str[:4].eq('2019').sum())),
    ("D05", "3 Dates", "Rows in 2020", lambda raw, df: int(df['transaction_date'].str[:4].eq('2020').sum())),
    ("D06", "3 Dates", "Rows in 2021", lambda raw, df: int(df['transaction_date'].str[:4].eq('2021').sum())),
    ("D07", "3 Dates", "Rows in 2022", lambda raw, df: int(df['transaction_date'].str[:4].eq('2022').sum())),
    ("D08", "3 Dates", "Rows in 2023", lambda raw, df: int(df['transaction_date'].str[:4].eq('2023').sum())),
    ("D09", "3 Dates", "Rows in 2024", lambda raw, df: int(df['transaction_date'].str[:4].eq('2024').sum())),
    ("D10", "3 Dates", "Rows where transaction_hour differs from hour of transaction_time", lambda raw, df: int((df['transaction_time'].str[:2].astype(int) != df['transaction_hour']).sum())),
    ("C01", "4 Categories", "Distinct values of account_type", lambda raw, df: df['account_type'].nunique()),
    ("C02", "4 Categories", "Distinct values of transaction_type", lambda raw, df: df['transaction_type'].nunique()),
    ("C03", "4 Categories", "Distinct values of transaction_direction", lambda raw, df: df['transaction_direction'].nunique()),
    ("C04", "4 Categories", "Distinct values of merchant_category", lambda raw, df: df['merchant_category'].nunique()),
    ("C05", "4 Categories", "Distinct values of state", lambda raw, df: df['state'].nunique()),
    ("C06", "4 Categories", "Distinct values of loan_type", lambda raw, df: df['loan_type'].nunique()),
    ("C07", "4 Categories", "Distinct values of transaction_status", lambda raw, df: df['transaction_status'].nunique()),
    ("C08", "4 Categories", "Distinct values of channel", lambda raw, df: df['channel'].nunique()),
    ("C09", "4 Categories", "Distinct values of kyc_status", lambda raw, df: df['kyc_status'].nunique()),
    ("C10", "4 Categories", "transaction_status = Success", lambda raw, df: int((df['transaction_status'] == 'Success').sum())),
    ("C11", "4 Categories", "transaction_status = Failed", lambda raw, df: int((df['transaction_status'] == 'Failed').sum())),
    ("C12", "4 Categories", "transaction_status = Reversed", lambda raw, df: int((df['transaction_status'] == 'Reversed').sum())),
    ("C13", "4 Categories", "transaction_status = Pending", lambda raw, df: int((df['transaction_status'] == 'Pending').sum())),
    ("C14", "4 Categories", "is_fraud = 1 (fraud-labelled rows)", lambda raw, df: int((df['is_fraud'] == 1).sum())),
    ("C15", "4 Categories", "has_loan = 1", lambda raw, df: int((df['has_loan'] == 1).sum())),
    ("C16", "4 Categories", "transaction_direction = Debit", lambda raw, df: int((df['transaction_direction'] == 'Debit').sum())),
    ("N01", "5 Numeric ranges", "Minimum transaction_amount", lambda raw, df: df['transaction_amount'].min()),
    ("N02", "5 Numeric ranges", "Maximum transaction_amount", lambda raw, df: df['transaction_amount'].max()),
    ("N03", "5 Numeric ranges", "Rows with transaction_amount <= 0", lambda raw, df: int((df['transaction_amount'] <= 0).sum())),
    ("N04", "5 Numeric ranges", "Rows with transaction_amount = 10,000,000.00", lambda raw, df: int((df['transaction_amount'] == 10000000).sum())),
    ("N05", "5 Numeric ranges", "Minimum account_balance", lambda raw, df: df['account_balance'].min()),
    ("N06", "5 Numeric ranges", "Maximum account_balance", lambda raw, df: df['account_balance'].max()),
    ("N07", "5 Numeric ranges", "Rows with account_balance = 500.00", lambda raw, df: int((df['account_balance'] == 500).sum())),
    ("N08", "5 Numeric ranges", "Rows with account_balance = 5,000,000.00", lambda raw, df: int((df['account_balance'] == 5000000).sum())),
    ("N09", "5 Numeric ranges", "Minimum credit_score", lambda raw, df: df['credit_score'].min()),
    ("N10", "5 Numeric ranges", "Maximum credit_score", lambda raw, df: df['credit_score'].max()),
    ("N11", "5 Numeric ranges", "Maximum emi_amount", lambda raw, df: df['emi_amount'].max()),
    ("N12", "5 Numeric ranges", "Distinct transaction_hour values", lambda raw, df: df['transaction_hour'].nunique()),
    ("Q01", "6 Consistency / DQ", "DQ-01 has_loan=1 and loan_type=None", lambda raw, df: int(((df['has_loan'] == 1) & (df['loan_type'] == 'None')).sum())),
    ("Q02", "6 Consistency / DQ", "DQ-01 of those, emi_amount > 0", lambda raw, df: int(((df['has_loan'] == 1) & (df['loan_type'] == 'None') & (df['emi_amount'] > 0)).sum())),
    ("Q03", "6 Consistency / DQ", "has_loan=0 but loan_type is not None", lambda raw, df: int(((df['has_loan'] == 0) & (df['loan_type'] != 'None')).sum())),
    ("Q04", "6 Consistency / DQ", "has_loan=0 but emi_amount > 0", lambda raw, df: int(((df['has_loan'] == 0) & (df['emi_amount'] > 0)).sum())),
    ("Q05", "6 Consistency / DQ", "has_loan=1 but emi_amount = 0", lambda raw, df: int(((df['has_loan'] == 1) & (df['emi_amount'] == 0)).sum())),
    ("Q06", "6 Consistency / DQ", "UQ-01 transaction_amount > account_balance", lambda raw, df: int((df['transaction_amount'] > df['account_balance']).sum())),
    ("Q07", "6 Consistency / DQ", "merchant_category = Salary (all rows)", lambda raw, df: int((df['merchant_category'] == 'Salary').sum())),
    ("Q08", "6 Consistency / DQ", "UQ-02 Salary rows that are Debits", lambda raw, df: int(((df['merchant_category'] == 'Salary') & (df['transaction_direction'] == 'Debit')).sum())),
    ("Q09", "6 Consistency / DQ", "DQ-02 customer_ids with more than one state", lambda raw, df: int((df.groupby('customer_id')['state'].nunique() > 1).sum())),
    ("Q10", "6 Consistency / DQ", "DQ-02 customer_ids with more than one account_type", lambda raw, df: int((df.groupby('customer_id')['account_type'].nunique() > 1).sum())),
    ("Q11", "6 Consistency / DQ", "DQ-02 customer_ids with more than one credit_score", lambda raw, df: int((df.groupby('customer_id')['credit_score'].nunique() > 1).sum())),
    ("Q12", "6 Consistency / DQ", "DQ-02 customer_ids with more than one kyc_status", lambda raw, df: int((df.groupby('customer_id')['kyc_status'].nunique() > 1).sum())),
    ("Q13", "6 Consistency / DQ", "DQ-02 customer_ids with more than one has_loan value", lambda raw, df: int((df.groupby('customer_id')['has_loan'].nunique() > 1).sum())),
    ("Q14", "6 Consistency / DQ", "customer_ids with exactly one transaction", lambda raw, df: int((df.groupby('customer_id').size() == 1).sum())),
    ("Q15", "6 Consistency / DQ", "Maximum transactions for one customer_id", lambda raw, df: int(df.groupby('customer_id').size().max())),
]


def to_decimal(v) -> Decimal:
    if isinstance(v, Decimal):
        return v.quantize(Decimal("0.01"))
    if isinstance(v, float):
        return Decimal(str(round(v, 2))).quantize(Decimal("0.01"))
    return Decimal(int(v)).quantize(Decimal("0.01"))


def compute(raw, df):
    return {cid: (area, desc, to_decimal(fn(raw, df))) for cid, area, desc, fn in CHECKS}


def fmt(d: Decimal) -> str:
    return f"{d:,.2f}".rstrip("0").rstrip(".") if d != d.to_integral_value() else f"{int(d):,}"


def reference_report(values) -> str:
    out = ["PYTHON REFERENCE VALUES", "-" * 78, f"{'check_id':<9}{'python_value':>20}  description"]
    for cid, (area, desc, v) in values.items():
        out.append(f"{cid:<9}{fmt(v):>20}  {desc}")
    out.append("-" * 78)
    out.append(f"{len(values)} reference values computed from the file")
    return "\n".join(out)


def compare_report(values, export_path: Path):
    ex = pd.read_csv(export_path, dtype=str, keep_default_na=False)
    ex.columns = [c.strip().lower() for c in ex.columns]
    if not {"check_id", "postgres_value"} <= set(ex.columns):
        sys.exit("The export must contain the columns check_id and postgres_value.")
    pg = {r["check_id"].strip(): Decimal(r["postgres_value"].replace(",", "").strip()) for _, r in ex.iterrows()}
    out = ["COMPARISON: PostgreSQL export vs fresh Python values", "-" * 78,
           f"{'check_id':<9}{'python':>20}{'postgres':>20}  result"]
    bad = 0
    for cid, (_, desc, v) in values.items():
        if cid not in pg:
            out.append(f"{cid:<9}{fmt(v):>20}{'(missing)':>20}  MISSING")
            bad += 1
            continue
        ok = abs(v - pg[cid]) < TOLERANCE
        bad += 0 if ok else 1
        out.append(f"{cid:<9}{fmt(v):>20}{fmt(pg[cid]):>20}  {'MATCH' if ok else 'MISMATCH  <-- ' + desc}")
    extra = sorted(set(pg) - set(values))
    if extra:
        out.append(f"Ids in export but not in this script: {extra}")
    out.append("-" * 78)
    out.append(f"SUMMARY: {len(values) - bad} of {len(values)} match" + ("" if bad == 0 else f"; {bad} need investigation"))
    return "\n".join(out), bad


def exploratory(df) -> str:
    """Expected results for sql/03_exploratory_analysis.sql (key columns only)."""
    out = []

    def block(title, frame):
        out.append("")
        out.append("=" * 78)
        out.append(title)
        out.append("=" * 78)
        out.append(frame.to_string())

    d = df.copy()
    d["year"] = d["transaction_date"].str[:4]
    g = d.groupby("year").agg(transactions=("transaction_id", "count"), total_amount=("transaction_amount", "sum"),
                              fraud_labelled=("is_fraud", "sum"), days_covered=("transaction_date", "nunique"))
    g["fraud_rate_pct"] = (100 * g["fraud_labelled"] / g["transactions"]).round(3)
    g["total_amount"] = g["total_amount"].round(2)
    block("E02 - rows, amount and fraud-label rate by year", g)

    s = d["transaction_status"].value_counts()
    block("E03 - transaction_status (rows, pct)", pd.DataFrame({"transactions": s, "pct": (100 * s / len(d)).round(2)}))

    for col, title in [("channel", "E04 - channel"), ("transaction_type", "E05 - transaction_type")]:
        t = d.groupby(col).agg(transactions=("transaction_id", "count"), total_amount=("transaction_amount", "sum"),
                               fraud_labelled=("is_fraud", "sum"))
        t["pct"] = (100 * t["transactions"] / len(d)).round(2)
        t["fraud_rate_pct"] = (100 * t["fraud_labelled"] / t["transactions"]).round(3)
        t["failed_pct"] = (100 * d[d["transaction_status"] == "Failed"].groupby(col).size() / t["transactions"]).round(2)
        t["total_amount"] = t["total_amount"].round(2)
        block(f"{title} (rows, amount, label rate, failed %)", t.sort_values("transactions", ascending=False))

    t = d.groupby("state").agg(transactions=("transaction_id", "count"), fraud_labelled=("is_fraud", "sum"))
    t["fraud_rate_pct"] = (100 * t["fraud_labelled"] / t["transactions"]).round(3)
    block("E07 - state (rows, label rate)", t.sort_values("transactions", ascending=False))

    bins = [0, 500, 1000, 5000, 25000, 100000, 1000000, float("inf")]
    labels = ["1 under 500", "2 500-999.99", "3 1,000-4,999.99", "4 5,000-24,999.99",
              "5 25,000-99,999.99", "6 100,000-999,999.99", "7 1,000,000 and over"]
    d["band"] = pd.cut(d["transaction_amount"], bins=bins, labels=labels, right=False)
    b = d.groupby("band", observed=True).agg(transactions=("transaction_id", "count"), fraud_labelled=("is_fraud", "sum"))
    b["pct"] = (100 * b["transactions"] / len(d)).round(2)
    b["fraud_rate_pct"] = (100 * b["fraud_labelled"] / b["transactions"]).round(3)
    block("E09 - provisional amount bands", b)

    qs = [0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99]
    p = d["transaction_amount"].quantile(qs).round(2)
    p.index = [f"p{int(q * 100):02d}" for q in qs]
    block("E10 - transaction_amount percentiles (linear interpolation = PERCENTILE_CONT)", p.to_frame("amount"))
    m = d.groupby("is_fraud")["transaction_amount"].agg(["count", "mean", "median"]).round(2)
    block("E11 - amount by is_fraud label (rows, mean, median)", m)

    borrower = d[d["has_loan"] == 1]
    la = borrower.groupby("year").agg(borrower_rows=("transaction_id", "count"),
                                      type_not_recorded=("loan_type", lambda s: int((s == "None").sum())))
    la["pct"] = (100 * la["type_not_recorded"] / la["borrower_rows"]).round(2)
    block("E15 - has_loan=1 rows with loan_type None, by year", la)

    k = d.groupby("customer_id").size().value_counts().sort_index()
    block("E18 - customer_ids by number of transactions", k.to_frame("customer_ids"))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True, help="Path to the CSV or the ZIP containing it")
    ap.add_argument("--compare", help="CSV exported from pgAdmin (columns check_id, postgres_value)")
    ap.add_argument("--exploratory", action="store_true", help="Print expected results for the 03 queries")
    ap.add_argument("--output", help="Save the printed report to this file")
    a = ap.parse_args()
    p = Path(a.input)
    if not p.exists():
        sys.exit(f"Input not found: {p}")
    raw, df = load_frames(p)
    if a.exploratory:
        text = exploratory(df)
        code = 0
    else:
        vals = compute(raw, df)
        if a.compare:
            text, bad = compare_report(vals, Path(a.compare))
            code = 1 if bad else 0
        else:
            text, code = reference_report(vals), 0
    print(text)
    if a.output:
        Path(a.output).parent.mkdir(parents=True, exist_ok=True)
        Path(a.output).write_text(text + "\n", encoding="utf-8")
        print(f"\n[saved] {a.output}")
    sys.exit(code)


if __name__ == "__main__":
    main()
