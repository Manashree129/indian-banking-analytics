#!/usr/bin/env python3
"""
data_validation.py - Rule-based validation of indian_banking_transactions.csv

PURPOSE
    data_profiling.py DESCRIBES the data. This script TESTS it against explicit rules
    and reports each rule as one of:

      PASS    the rule holds for every row
      FAIL    a structural rule is broken (the file is not safe to load as-is)
      REVIEW  the rule is broken or the pattern is unusual, but whether it is an
              error depends on a field definition the publisher has not documented.
              These are NOT cleaned or removed automatically.

    The script never modifies the data. Exit code: 0 if no FAIL, 1 if any FAIL.

USAGE
    python python/data_validation.py --input data/raw/indian_banking_transactions.csv
    python python/data_validation.py --input path/to/archive.zip \
        --output documentation/evidence/day1_validation_output.txt

NOTE ON EXPECTED VALUE LISTS
    The allowed-value lists below are the values OBSERVED in the supplied file on
    2026-10-28. They are not taken from publisher documentation (none was found).
    A new value appearing in a future copy of the file will therefore FAIL, which
    is intentional: it forces a human to look at it.
"""
import argparse
import sys
from pathlib import Path

import pandas as pd

# Reuse the loader so both scripts read the file identically
sys.path.insert(0, str(Path(__file__).resolve().parent))
from data_profiling import load  # noqa: E402

EXPECTED_COLUMNS = [
    "transaction_id", "customer_id", "transaction_date", "transaction_time",
    "account_type", "transaction_type", "transaction_amount", "transaction_direction",
    "account_balance", "merchant_category", "state", "credit_score", "has_loan",
    "loan_type", "emi_amount", "transaction_status", "channel", "kyc_status",
    "is_fraud", "transaction_hour",
]

ALLOWED = {
    "account_type": {"Savings", "Current", "Salary", "NRI", "Fixed Deposit"},
    "transaction_type": {"UPI", "IMPS", "NEFT", "POS", "ATM_Withdrawal", "Net_Banking",
                         "RTGS", "Auto_Debit", "Cheque", "Credit_Card"},
    "transaction_direction": {"Debit", "Credit"},
    "transaction_status": {"Success", "Failed", "Reversed", "Pending"},
    "channel": {"Mobile_App", "Web", "ATM", "POS_Terminal", "Branch", "API"},
    "kyc_status": {"Verified", "Pending", "Expired"},
    "loan_type": {"None", "Personal", "Home", "Auto", "Business", "Education", "Gold"},
    "has_loan": {0, 1},
    "is_fraud": {0, 1},
}

RESULTS = []


def record(rule_id, status, description, detail=""):
    RESULTS.append((rule_id, status, description, detail))


def validate(df: pd.DataFrame, expected_rows=None):
    n = len(df)

    # ---------- STRUCTURE ----------
    cols_ok = list(df.columns) == EXPECTED_COLUMNS
    record("S01", "PASS" if cols_ok else "FAIL", "Columns match the 20 expected names in order",
           "" if cols_ok else f"found: {list(df.columns)}")
    if expected_rows is not None:
        record("S02", "PASS" if n == expected_rows else "FAIL",
               f"Row count equals expected value ({expected_rows:,})", f"found {n:,}")
    record("S03", "PASS", f"Row count recorded", f"{n:,} rows")

    missing = int(df.isna().sum().sum())
    record("S04", "PASS" if missing == 0 else "FAIL",
           "No empty (missing) cells in any column", f"{missing:,} empty cells")

    # ---------- KEYS AND FORMATS ----------
    dup_id = int(df["transaction_id"].duplicated().sum())
    record("K01", "PASS" if dup_id == 0 else "FAIL", "transaction_id is unique", f"{dup_id:,} duplicates")
    bad_tid = int((~df["transaction_id"].str.match(r"^TXN\d{9}$")).sum())
    record("K02", "PASS" if bad_tid == 0 else "FAIL", "transaction_id format TXN + 9 digits", f"{bad_tid:,} bad")
    bad_cid = int((~df["customer_id"].str.match(r"^CUST\d{6}$")).sum())
    record("K03", "PASS" if bad_cid == 0 else "FAIL", "customer_id format CUST + 6 digits", f"{bad_cid:,} bad")
    dup_rows = int(df.duplicated().sum())
    record("K04", "PASS" if dup_rows == 0 else "FAIL", "No exact duplicate rows", f"{dup_rows:,} duplicates")
    dup_ex_id = int(df.drop(columns="transaction_id").duplicated().sum())
    record("K05", "PASS" if dup_ex_id == 0 else "REVIEW",
           "No duplicate rows when transaction_id is ignored (hidden duplicates)", f"{dup_ex_id:,}")

    # ---------- DATES AND TIMES ----------
    d = pd.to_datetime(df["transaction_date"], errors="coerce", format="%Y-%m-%d")
    bad_d = int(d.isna().sum())
    record("D01", "PASS" if bad_d == 0 else "FAIL", "transaction_date parses as YYYY-MM-DD", f"{bad_d:,} bad")
    record("D02", "PASS", "Date range recorded", f"{d.min().date()} to {d.max().date()}")
    bad_t = int((~df["transaction_time"].str.match(r"^([01]\d|2[0-3]):[0-5]\d$")).sum())
    record("D03", "PASS" if bad_t == 0 else "FAIL", "transaction_time is a valid HH:MM", f"{bad_t:,} bad")
    hour_mm = int((df["transaction_time"].str[:2].astype(int) != df["transaction_hour"]).sum())
    record("D04", "PASS" if hour_mm == 0 else "FAIL",
           "transaction_hour equals the hour part of transaction_time", f"{hour_mm:,} mismatches")
    # Calendar continuity: every day between min and max should appear at least once
    full_days = (d.max() - d.min()).days + 1
    missing_days = full_days - d.nunique()
    record("D07", "PASS" if missing_days == 0 else "REVIEW",
           "Every calendar day between min and max date has at least one transaction",
           f"{d.nunique():,} distinct dates of {full_days:,} calendar days ({missing_days:,} missing)")
    # Final year coverage: a trailing partial year distorts year-over-year comparisons
    last_year = d.dt.year.max()
    days_last_year = d[d.dt.year == last_year].nunique()
    rows_last_year = int((d.dt.year == last_year).sum())
    record("D05", "PASS" if days_last_year >= 365 else "REVIEW",
           "Final calendar year is complete (otherwise exclude from year-over-year comparisons)",
           f"{last_year} has {days_last_year} distinct date(s) and {rows_last_year:,} rows")
    record("D06", "PASS" if bool(d.is_monotonic_increasing) else "REVIEW",
           "File is sorted by transaction_date", "")

    # ---------- DOMAINS ----------
    for col, allowed in ALLOWED.items():
        found = set(df[col].unique())
        extra = found - allowed
        record(f"V-{col}", "PASS" if not extra else "FAIL",
               f"{col} contains only the {len(allowed)} observed/allowed values",
               "" if not extra else f"unexpected: {sorted(map(str, extra))}")
    bad_cs = int(((df["credit_score"] < 300) | (df["credit_score"] > 900)).sum())
    record("V-credit_score", "PASS" if bad_cs == 0 else "FAIL",
           "credit_score within 300-900 (typical Indian bureau scale; assumption)",
           f"{bad_cs:,} outside; observed {df['credit_score'].min()}-{df['credit_score'].max()}")
    nonpos = int((df["transaction_amount"] <= 0).sum())
    record("V-amount_positive", "PASS" if nonpos == 0 else "FAIL", "transaction_amount > 0", f"{nonpos:,}")
    negbal = int((df["account_balance"] < 0).sum())
    record("V-balance_nonneg", "PASS" if negbal == 0 else "REVIEW", "account_balance >= 0", f"{negbal:,}")
    negemi = int((df["emi_amount"] < 0).sum())
    record("V-emi_nonneg", "PASS" if negemi == 0 else "FAIL", "emi_amount >= 0", f"{negemi:,}")

    # ---------- CROSS-FIELD CONSISTENCY ----------
    a = int(((df["has_loan"] == 0) & (df["loan_type"] != "None")).sum())
    record("X01", "PASS" if a == 0 else "FAIL", "has_loan=0 implies loan_type='None'", f"{a:,} violations")
    b = int(((df["has_loan"] == 0) & (df["emi_amount"] > 0)).sum())
    record("X02", "PASS" if b == 0 else "FAIL", "has_loan=0 implies emi_amount=0", f"{b:,} violations")
    c = int(((df["has_loan"] == 1) & (df["loan_type"] == "None")).sum())
    record("X03", "PASS" if c == 0 else "REVIEW",
           "has_loan=1 implies a named loan_type",
           f"{c:,} rows ({c / n:.2%}) have has_loan=1 and loan_type='None'; all have emi_amount>0. "
           f"Meaning of 'None' for a borrower is undocumented (unspecified type? data defect?)")
    e = int(((df["has_loan"] == 1) & (df["emi_amount"] == 0)).sum())
    record("X04", "PASS" if e == 0 else "REVIEW", "has_loan=1 implies emi_amount>0", f"{e:,}")

    # ---------- PLAUSIBILITY / DEFINITION QUESTIONS (REVIEW, never auto-cleaned) ----------
    cap_amt = int((df["transaction_amount"] == df["transaction_amount"].max()).sum())
    record("P01", "REVIEW" if cap_amt > 1 else "PASS",
           "Maximum transaction_amount is not repeated (possible clipping / ceiling)",
           f"max {df['transaction_amount'].max():,.2f} appears {cap_amt:,} times")
    cap_bal_max = int((df["account_balance"] == df["account_balance"].max()).sum())
    cap_bal_min = int((df["account_balance"] == df["account_balance"].min()).sum())
    record("P02", "REVIEW" if (cap_bal_max > 1 or cap_bal_min > 1) else "PASS",
           "account_balance min/max are not repeated (possible floor/ceiling)",
           f"min {df['account_balance'].min():,.2f} x{cap_bal_min:,}; "
           f"max {df['account_balance'].max():,.2f} x{cap_bal_max:,}")
    gt = int((df["transaction_amount"] > df["account_balance"]).sum())
    record("P03", "REVIEW" if gt else "PASS",
           "transaction_amount does not exceed account_balance",
           f"{gt:,} rows ({gt / n:.1%}); balance timing (before/after) is undocumented")
    sal_debit = int(((df["merchant_category"] == "Salary") & (df["transaction_direction"] == "Debit")).sum())
    sal_total = int((df["merchant_category"] == "Salary").sum())
    record("P04", "REVIEW" if sal_debit else "PASS",
           "merchant_category='Salary' rows are credits",
           f"{sal_debit:,} of {sal_total:,} Salary rows ({sal_debit / sal_total:.1%}) are Debits")
    top_round = df["transaction_amount"].value_counts().head(5)
    record("P05", "REVIEW",
           "Round-number amounts are not heavily over-represented",
           "top amounts: " + ", ".join(f"{k:,.0f} x{v:,}" for k, v in top_round.items()))

    # customer-level attribute stability
    g = df.groupby("customer_id")
    n_cust = df["customer_id"].nunique()
    unstable = {}
    for col in ["state", "account_type", "credit_score", "kyc_status", "has_loan"]:
        unstable[col] = int((g[col].nunique() > 1).sum())
    record("P06", "REVIEW" if any(unstable.values()) else "PASS",
           "Customer-level attributes are constant within a customer_id",
           f"customers (of {n_cust:,}) with >1 value: " +
           ", ".join(f"{k}={v:,}" for k, v in unstable.items()) +
           ". customer_id behaves like a row-level label, not a stable customer profile")
    one_txn = int((g.size() == 1).sum())
    record("P07", "PASS", "Customers with exactly one transaction (information only)", f"{one_txn:,}")

    # fraud label is binary and has plausible prevalence (information)
    fr = df["is_fraud"].mean()
    record("P08", "PASS", "is_fraud prevalence recorded (supplied label, not confirmed fraud)",
           f"{int(df['is_fraud'].sum()):,} labelled = {fr:.3%}")


def render() -> str:
    lines = ["DATA VALIDATION REPORT", "-" * 78]
    for rid, st, desc, det in RESULTS:
        lines.append(f"[{st:<6}] {rid:<18} {desc}")
        if det:
            lines.append(f"{'':<27}-> {det}")
    counts = {s: sum(1 for r in RESULTS if r[1] == s) for s in ("PASS", "FAIL", "REVIEW")}
    lines += ["-" * 78,
              f"SUMMARY: {counts['PASS']} PASS, {counts['REVIEW']} REVIEW, {counts['FAIL']} FAIL",
              "REVIEW items are data-definition questions; no rows were changed or removed."]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True, help="Path to the CSV or to the ZIP containing it")
    ap.add_argument("--expected-rows", type=int, default=550000,
                    help="Row count verified on first inspection (default 550000)")
    ap.add_argument("--output", help="Optional path to save the report as a text file")
    args = ap.parse_args()

    p = Path(args.input)
    if not p.exists():
        sys.exit(f"Input not found: {p}")
    df, _ = load(p)
    validate(df, expected_rows=args.expected_rows)
    report = render()
    print(report)
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(report + "\n", encoding="utf-8")
        print(f"\n[saved] {args.output}")
    sys.exit(1 if any(r[1] == "FAIL" for r in RESULTS) else 0)


if __name__ == "__main__":
    main()
