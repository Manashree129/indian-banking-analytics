#!/usr/bin/env python3
"""
data_profiling.py - Reproducible profiling of indian_banking_transactions.csv

PURPOSE
    Describe the dataset exactly as it exists in the file: shape, data types,
    missing values, duplicates, ranges, category distributions, fraud-label
    distribution and date coverage. It changes nothing; the raw file is only read.

USAGE
    python python/data_profiling.py --input data/raw/indian_banking_transactions.csv
    python python/data_profiling.py --input path/to/archive.zip
    python python/data_profiling.py --input <file> --output documentation/evidence/day1_profiling_output.txt

IMPORTANT NOTE ABOUT THE LITERAL TEXT "None"
    The column loan_type contains the literal text "None" (meaning "no loan type
    recorded"). Pandas treats "None" as a missing value by default, which would
    silently turn 377,134 text values into NaN. This script therefore reads the
    file with keep_default_na=False and only treats an EMPTY string as missing.
"""
import argparse
import hashlib
import io
import sys
import zipfile
from pathlib import Path

import pandas as pd

CATEGORICAL_COLUMNS = [
    "account_type", "transaction_type", "transaction_direction", "merchant_category",
    "state", "has_loan", "loan_type", "transaction_status", "channel",
    "kyc_status", "is_fraud",
]
NUMERIC_COLUMNS = ["transaction_amount", "account_balance", "credit_score",
                   "emi_amount", "transaction_hour"]


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load(input_path: Path):
    """Return (dataframe, description_of_source). Accepts a .csv or a .zip holding one CSV."""
    kwargs = dict(keep_default_na=False, na_values=[""])
    if input_path.suffix.lower() == ".zip":
        with zipfile.ZipFile(input_path) as z:
            names = [n for n in z.namelist() if n.lower().endswith(".csv")]
            if len(names) != 1:
                sys.exit(f"Expected exactly one CSV in the ZIP, found: {names}")
            with z.open(names[0]) as f:
                df = pd.read_csv(io.TextIOWrapper(f, encoding="utf-8"), **kwargs)
            return df, f"{input_path.name} -> {names[0]}"
    return pd.read_csv(input_path, **kwargs), input_path.name


def section(out, title):
    out.append("")
    out.append("=" * 78)
    out.append(title)
    out.append("=" * 78)


def profile(df: pd.DataFrame, source_desc: str, input_path: Path) -> str:
    out = []
    section(out, "1. FILE AND SHAPE")
    out.append(f"Source          : {source_desc}")
    out.append(f"SHA-256 (input) : {sha256_of(input_path)}")
    out.append(f"Rows            : {len(df):,}")
    out.append(f"Columns         : {df.shape[1]}")
    out.append(f"Column names    : {', '.join(df.columns)}")

    section(out, "2. DATA TYPES, MISSING VALUES, DISTINCT COUNTS")
    t = pd.DataFrame({
        "pandas_dtype": df.dtypes.astype(str),
        "missing": df.isna().sum(),
        "distinct": df.nunique(),
    })
    out.append(t.to_string())

    section(out, "3. DUPLICATES")
    out.append(f"Exact duplicate rows                     : {df.duplicated().sum():,}")
    out.append(f"Duplicate transaction_id values          : {df['transaction_id'].duplicated().sum():,}")
    out.append(f"Duplicates ignoring transaction_id       : {df.drop(columns='transaction_id').duplicated().sum():,}")
    out.append(f"Distinct customer_id values              : {df['customer_id'].nunique():,}")
    per_cust = df.groupby("customer_id").size()
    out.append(f"Transactions per customer_id (min/median/max): "
               f"{per_cust.min()} / {per_cust.median():.0f} / {per_cust.max()}")

    section(out, "4. DATE COVERAGE")
    d = pd.to_datetime(df["transaction_date"], errors="coerce", format="%Y-%m-%d")
    out.append(f"Unparseable dates : {d.isna().sum():,}")
    out.append(f"Minimum date      : {d.min().date()}")
    out.append(f"Maximum date      : {d.max().date()}")
    out.append(f"Distinct dates    : {d.nunique():,}")
    out.append("Rows per year:")
    out.append(d.dt.year.value_counts().sort_index().to_string())
    last = d.max()
    out.append(f"Rows on the last date ({last.date()}): {(d == last).sum():,}")

    section(out, "5. NUMERIC COLUMNS")
    out.append(df[NUMERIC_COLUMNS].describe(percentiles=[.01, .05, .25, .5, .75, .95, .99])
               .T.round(2).to_string())
    out.append("")
    out.append(f"transaction_amount <= 0 : {(df['transaction_amount'] <= 0).sum():,}")
    out.append(f"transaction_amount == max ({df['transaction_amount'].max():,.2f}) : "
               f"{(df['transaction_amount'] == df['transaction_amount'].max()).sum():,}")
    out.append(f"account_balance == min ({df['account_balance'].min():,.2f}) : "
               f"{(df['account_balance'] == df['account_balance'].min()).sum():,}")
    out.append(f"account_balance == max ({df['account_balance'].max():,.2f}) : "
               f"{(df['account_balance'] == df['account_balance'].max()).sum():,}")
    out.append("Most frequent transaction_amount values (round-number clustering):")
    out.append(df["transaction_amount"].value_counts().head(5).to_string())

    section(out, "6. CATEGORY DISTRIBUTIONS")
    for c in CATEGORICAL_COLUMNS:
        vc = df[c].value_counts(dropna=False)
        pct = (vc / len(df) * 100).round(2)
        out.append(f"\n-- {c} ({len(vc)} values)")
        out.append(pd.DataFrame({"rows": vc, "pct": pct}).to_string())

    section(out, "7. FRAUD LABEL (is_fraud is a SUPPLIED LABEL, not confirmed fraud)")
    n1 = int(df["is_fraud"].sum())
    out.append(f"is_fraud = 1 : {n1:,}   rate = {n1 / len(df):.4%}")
    out.append("transaction_amount summary by label:")
    out.append(df.groupby("is_fraud")["transaction_amount"]
               .describe().round(2).to_string())
    for c in ["channel", "transaction_type"]:
        g = df.groupby(c)["is_fraud"].agg(rows="count", labelled="sum", rate="mean")
        g["rate_pct"] = (g.pop("rate") * 100).round(3)
        out.append(f"\n-- label rate by {c}")
        out.append(g.sort_values("rate_pct", ascending=False).to_string())

    section(out, "8. HAS_LOAN vs LOAN_TYPE vs EMI_AMOUNT")
    out.append("has_loan x (loan_type == 'None'):")
    out.append(pd.crosstab(df["has_loan"], df["loan_type"].eq("None"),
                           rownames=["has_loan"], colnames=["loan_type is 'None'"],
                           margins=True).to_string())
    anomaly = df[(df["has_loan"] == 1) & (df["loan_type"] == "None")]
    out.append(f"\nRows with has_loan=1 AND loan_type='None' : {len(anomaly):,} "
               f"({len(anomaly) / len(df):.2%} of all rows; "
               f"{len(anomaly) / (df['has_loan'] == 1).sum():.2%} of has_loan=1 rows)")
    out.append(f"  ...of which emi_amount > 0 : {(anomaly['emi_amount'] > 0).sum():,}")
    out.append(f"Rows with has_loan=0 AND loan_type<>'None' : "
               f"{((df['has_loan'] == 0) & (df['loan_type'] != 'None')).sum():,}")
    out.append(f"Rows with has_loan=0 AND emi_amount>0      : "
               f"{((df['has_loan'] == 0) & (df['emi_amount'] > 0)).sum():,}")
    out.append(f"Rows with has_loan=1 AND emi_amount=0      : "
               f"{((df['has_loan'] == 1) & (df['emi_amount'] == 0)).sum():,}")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True, help="Path to the CSV or to the ZIP containing it")
    ap.add_argument("--output", help="Optional path to also save the report as a text file")
    args = ap.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        sys.exit(f"Input not found: {input_path}")
    df, desc = load(input_path)
    report = profile(df, desc, input_path)
    print(report)
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(report + "\n", encoding="utf-8")
        print(f"\n[saved] {args.output}")


if __name__ == "__main__":
    main()
