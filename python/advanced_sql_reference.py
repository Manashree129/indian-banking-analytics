#!/usr/bin/env python3
"""
advanced_sql_reference.py - Independent pandas reference results for sql/04_advanced_analytical_queries.sql

PURPOSE
    Recomputes the key results of the A01-A22 queries directly from the CSV with pandas (no SQL
    involved) so the PostgreSQL output can be compared against an independent calculation.
    Column names match the SQL output columns, so the grids can be compared side by side.

USAGE
    python python/advanced_sql_reference.py --input data/raw/indian_banking_transactions.csv
    python python/advanced_sql_reference.py --input <csv or zip> --queries A09 A10 A22
    python python/advanced_sql_reference.py --input <csv or zip> --output documentation/evidence/day3_python_reference.txt

NOTES
    * Percentiles use linear interpolation, which is what PERCENTILE_CONT does.
    * Wilson intervals use z = 1.96, as in the SQL.
    * Values are printed rounded the same way as the SQL (2-4 decimals); tiny rounding differences
      in the last printed digit are not a mismatch.
"""
import argparse
import io
import math
import sys
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

Z, Z2 = 1.96, 3.8416


def load(path: Path) -> pd.DataFrame:
    kw = dict(keep_default_na=False, na_values=[""])
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as zf:
            name = [n for n in zf.namelist() if n.lower().endswith(".csv")][0]
            with zf.open(name) as f:
                return pd.read_csv(io.TextIOWrapper(f, encoding="utf-8"), **kw)
    return pd.read_csv(path, **kw)


def wilson(x, n):
    p = x / n
    centre = p + Z2 / (2 * n)
    half = Z * np.sqrt(p * (1 - p) / n + Z2 / (4 * n * n))
    denom = 1 + Z2 / n
    return (centre - half) / denom, (centre + half) / denom


def pct(a, b):
    return 100.0 * a / b


# ---------------------------------------------------------------------------------------------
def a01(df):
    d = df[df.transaction_date < "2024-01-01"].copy()
    d["month_start"] = d.transaction_date.str[:7] + "-01"
    m = d.groupby("month_start").agg(transactions=("transaction_id", "count"), total_amount=("transaction_amount", "sum")).reset_index()
    m["yr"] = m.month_start.str[:4].astype(int)
    m["mo"] = m.month_start.str[5:7].astype(int)
    m["mom_transactions_pct"] = (100 * m.transactions.pct_change()).round(2)
    py = m.set_index(["yr", "mo"])
    prev = m.apply(lambda r: py.transactions.get((r.yr - 1, r.mo), np.nan), axis=1)
    m["yoy_transactions_pct"] = (100 * (m.transactions - prev) / prev).round(2)
    return m[["month_start", "transactions", "mom_transactions_pct", "yoy_transactions_pct"]]


def a02(df):
    s = df.groupby("transaction_date").size()
    s.index = pd.to_datetime(s.index)
    s = s.reindex(pd.date_range(s.index.min(), s.index.max()), fill_value=0)
    base = s.shift(1).rolling(7).mean()
    dev = 100 * (s - base) / base
    t = pd.DataFrame({"day": s.index.strftime("%Y-%m-%d"), "transactions": s.values, "baseline_7d_avg": base.round(1).values,
                      "deviation_pct": dev.round(1).values, "abs": dev.abs().values}).dropna()
    t = t.sort_values(["abs", "day"], ascending=[False, True]).head(15).reset_index(drop=True)
    t.insert(0, "rank_by_abs_deviation", range(1, 16))
    return t.drop(columns="abs")


def a04(df):
    d = df[df.transaction_date < "2024-01-01"].copy()
    d["calendar_year"] = d.transaction_date.str[:4].astype(int)
    y = d.groupby(["transaction_type", "calendar_year"]).agg(transactions=("transaction_id", "count"), total_amount=("transaction_amount", "sum")).reset_index()
    y = y.sort_values(["transaction_type", "calendar_year"])
    y["yoy_transactions_pct"] = (100 * y.groupby("transaction_type").transactions.pct_change()).round(2)
    y["yoy_amount_pct"] = (100 * y.groupby("transaction_type").total_amount.pct_change()).round(2)
    y["amount_rank_in_year"] = y.groupby("calendar_year").total_amount.rank(method="dense", ascending=False).astype(int)
    return y[["transaction_type", "calendar_year", "transactions", "yoy_transactions_pct", "yoy_amount_pct", "amount_rank_in_year"]]


def a05(df):
    c = df.groupby("customer_id").agg(transactions=("transaction_id", "count"), distinct_states=("state", "nunique")).reset_index()
    c = c.sort_values(["transactions", "customer_id"], ascending=[False, True]).reset_index(drop=True)
    c["row_number_rank"] = range(1, len(c) + 1)
    c["rank_with_gaps"] = c.transactions.rank(method="min", ascending=False).astype(int)
    c["dense_rank"] = c.transactions.rank(method="dense", ascending=False).astype(int)
    return c.head(15)


def a08(df):
    overall = df.transaction_status.isin(["Failed", "Reversed"]).mean()
    g = df.assign(bad=df.transaction_status.isin(["Failed", "Reversed"])).groupby(["transaction_type", "channel"]).agg(n=("bad", "size"), bad=("bad", "sum")).reset_index()
    g = g[g.n >= 500].copy()
    g["failed_or_reversed_pct"] = (100 * g.bad / g.n).round(2)
    lo, hi = wilson(g.bad, g.n)
    g["ci_low_pct"], g["ci_high_pct"] = (100 * lo).round(2), (100 * hi).round(2)
    g = g.sort_values(["failed_or_reversed_pct", "transaction_type", "channel"], ascending=[False, True, True]).head(15)
    g["overall_pct"] = round(100 * overall, 2)
    return g.rename(columns={"n": "transactions"})[["transaction_type", "channel", "transactions", "failed_or_reversed_pct", "ci_low_pct", "ci_high_pct"]]


def a09(df):
    bins = [0, 25000, 100000, 1000000, np.inf]
    labels = ["1 under 25,000", "2 25,000-99,999.99", "3 100,000-999,999.99", "4 1,000,000 and over"]
    d = df.assign(amount_band=pd.cut(df.transaction_amount, bins=bins, labels=labels, right=False))
    band = d.groupby("amount_band", observed=True).is_fraud.mean()
    c = d.groupby(["amount_band", "transaction_type"], observed=True).is_fraud.agg(transactions="size", fraud_labelled="sum").reset_index()
    c = c[c.transactions >= 200].copy()
    c["label_rate_pct"] = (100 * c.fraud_labelled / c.transactions).round(3)
    c["band_rate_pct"] = c.amount_band.map(lambda b: round(100 * band[b], 3))
    lo, hi = wilson(c.fraud_labelled, c.transactions)
    c["ci_low_pct"], c["ci_high_pct"] = (100 * lo).round(3), (100 * hi).round(3)
    c["amount_band"] = c.amount_band.astype(str)
    return c


def a10(df):
    s = df.sort_values(["transaction_amount", "transaction_id"], ascending=[False, True]).reset_index(drop=True)
    s["amount_decile"] = np.repeat(np.arange(1, 11), len(s) // 10)
    g = s.groupby("amount_decile").agg(transactions=("is_fraud", "size"), min_amount=("transaction_amount", "min"),
                                       max_amount=("transaction_amount", "max"), fraud_labelled=("is_fraud", "sum")).reset_index()
    g["label_rate_pct"] = (100 * g.fraud_labelled / g.transactions).round(3)
    g["cumulative_labelled"] = g.fraud_labelled.cumsum()
    g["cumulative_share_of_labelled_pct"] = (100 * g.cumulative_labelled / g.fraud_labelled.sum()).round(2)
    return g


def a11(df):
    g = df.groupby("transaction_type").transaction_amount
    t = pd.DataFrame({"transactions": g.size(), "p25": g.quantile(.25).round(2), "median": g.quantile(.5).round(2),
                      "p75": g.quantile(.75).round(2), "p95": g.quantile(.95).round(2), "p99": g.quantile(.99).round(2),
                      "mean": g.mean().round(2)})
    t["mean_to_median"] = (t["mean"] / t["median"]).round(2)
    return t.sort_values(["median"], ascending=False).reset_index()


def a12(df):
    rows = []
    for ch, d in df.groupby("channel"):
        lab, oth = d[d.is_fraud == 1].transaction_amount, d[d.is_fraud == 0].transaction_amount
        rows.append((ch, len(lab), len(oth), round(lab.median(), 2), round(oth.median(), 2), round(lab.median() / oth.median(), 2)))
    return pd.DataFrame(rows, columns=["channel", "labelled_transactions", "other_transactions", "median_labelled", "median_other", "median_ratio"])


def a13(df):
    d = df.assign(month=df.transaction_date.str[:7], bad=df.transaction_status.isin(["Failed", "Reversed"]).astype(int))
    m = d.groupby("month").agg(transactions=("bad", "size"), bad=("bad", "sum"))
    m["window_transactions"] = m.transactions.rolling(3).sum()
    m["window_bad"] = m.bad.rolling(3).sum()
    m["rolling_3m_rate_pct"] = (100 * m.window_bad / m.window_transactions).round(2)
    m = m.dropna().reset_index()
    return m[m.month < "2024-01"][["month", "transactions", "rolling_3m_rate_pct"]]


def a14(df):
    c = df.groupby("customer_id").size().rename("transactions").reset_index().sort_values(["transactions", "customer_id"], ascending=[False, True])
    n = len(c)
    sizes = [n // 10 + (1 if i < n % 10 else 0) for i in range(10)]
    c["activity_group"] = np.repeat(np.arange(1, 11), sizes)
    g = c.groupby("activity_group").agg(customer_ids=("transactions", "size"), min_transactions_per_id=("transactions", "min"),
                                        max_transactions_per_id=("transactions", "max"), transactions=("transactions", "sum")).reset_index()
    g["pct_of_transactions"] = (100 * g.transactions / g.transactions.sum()).round(2)
    g["cumulative_pct"] = (100 * g.transactions.cumsum() / g.transactions.sum()).round(2)
    return g


def a15(df):
    g = df.groupby("customer_id").agg(t=("state", "size"), s=("state", "nunique"), a=("account_type", "nunique"),
                                      c=("credit_score", "nunique"), k=("kyc_status", "nunique"), h=("has_loan", "nunique"))
    g = g[g.t >= 2]
    return pd.DataFrame([{"customer_ids_with_2plus_rows": len(g), "state_varies": int((g.s > 1).sum()), "account_type_varies": int((g.a > 1).sum()),
                          "credit_score_varies": int((g.c > 1).sum()), "kyc_status_varies": int((g.k > 1).sum()),
                          "has_loan_varies": int((g.h > 1).sum()),
                          "all_five_constant": int(((g.s == 1) & (g.a == 1) & (g.c == 1) & (g.k == 1) & (g.h == 1)).sum())}])


def a16(df):
    grp = np.where(df.has_loan == 0, "1 No loan (has_loan = 0)",
                   np.where(df.loan_type == "None", "3 Loan flag set, loan_type None (DQ-01)", "2 Loan flag set, named loan type"))
    d = df.assign(loan_group=grp)
    rows = []
    for k, g in d.groupby("loan_group"):
        rows.append((k, len(g), round(100 * len(g) / len(d), 2), round(g.emi_amount.median(), 2), round(g.emi_amount.mean(), 2),
                     round(g.credit_score.median(), 1), round(100 * g.transaction_status.isin(["Failed", "Reversed"]).mean(), 2),
                     int(g.is_fraud.sum()), round(100 * g.is_fraud.mean(), 3)))
    return pd.DataFrame(rows, columns=["loan_group", "transactions", "pct_of_all_rows", "median_emi", "mean_emi", "median_credit_score",
                                       "failed_or_reversed_pct", "fraud_labelled", "fraud_label_rate_pct"])


def a17(df):
    flagged = set(df[(df.has_loan == 1) & (df.loan_type == "None")].customer_id)
    d = df[df.customer_id.isin(flagged)]
    named = set(d[d.loan_type != "None"].customer_id)
    noloan = set(d[d.has_loan == 0].customer_id)
    only = flagged - set(d[~((d.has_loan == 1) & (d.loan_type == "None"))].customer_id)
    return pd.DataFrame([{"customer_ids_with_dq01_rows": len(flagged), "also_have_named_loan_rows": len(named),
                          "also_have_no_loan_rows": len(noloan), "only_dq01_rows": len(only)}])


def a18(df):
    r = df.transaction_amount / df.account_balance
    band = pd.cut(r, bins=[-np.inf, .1, .5, 1, 2, 10, np.inf], labels=["1 under 0.1", "2 0.1 to under 0.5", "3 0.5 to under 1",
                                                                      "4 1 to under 2", "5 2 to under 10", "6 10 and over"], right=False)
    g = df.assign(ratio_band=band.astype(str)).groupby(["transaction_direction", "ratio_band"]).is_fraud.agg(transactions="size", fraud_labelled="sum").reset_index()
    g["pct_of_direction"] = (100 * g.transactions / g.groupby("transaction_direction").transactions.transform("sum")).round(2)
    g["fraud_label_rate_pct"] = (100 * g.fraud_labelled / g.transactions).round(3)
    return g


def a19(df):
    rows = []
    for k, g in df.groupby("transaction_direction"):
        r = g.transaction_amount / g.account_balance
        rows.append((k, len(g), round(g.transaction_amount.corr(g.account_balance), 4), round(r.quantile(.5), 4),
                     round(r.quantile(.95), 4), round(r.quantile(.99), 4)))
    return pd.DataFrame(rows, columns=["transaction_direction", "transactions", "corr_amount_balance", "median_ratio", "p95_ratio", "p99_ratio"])


def a20(df):
    n = df.transaction_id.str[3:].astype(int)
    d = pd.to_datetime(df.transaction_date)
    return pd.DataFrame([{"rows_checked": len(df), "id_gaps": int((n.diff().dropna() != 1).sum()),
                          "date_regressions": int((d.diff().dropna() < pd.Timedelta(0)).sum()),
                          "next_before_current": int((d.shift(-1).dropna() < d[:-1]).sum()),
                          "max_day_jump": int(d.diff().dropna().dt.days.max())}])


def a21(df):
    s = df.assign(d=pd.to_datetime(df.transaction_date)).sort_values(["customer_id", "transaction_date", "transaction_time", "transaction_id"])
    gap = s.groupby("customer_id").d.diff().dropna().dt.days
    b = pd.cut(gap, bins=[-1, 0, 7, 30, 90, 365, np.inf], labels=["1 same day", "2 1-7 days", "3 8-30 days", "4 31-90 days",
                                                                  "5 91-365 days", "6 more than 365 days"])
    t = b.value_counts().sort_index().rename("transaction_pairs").reset_index()
    t.columns = ["gap_bucket", "transaction_pairs"]
    t["gap_bucket"] = t.gap_bucket.astype(str)
    t["pct_of_pairs"] = (100 * t.transaction_pairs / t.transaction_pairs.sum()).round(2)
    return t


def a22(df):
    p0 = df.is_fraud.mean()
    g = df.groupby("state").is_fraud.agg(transactions="size", fraud_labelled="sum").reset_index()
    g = g[g.transactions >= 1000].copy()
    p = g.fraud_labelled / g.transactions
    lo, hi = wilson(g.fraud_labelled, g.transactions)
    g["label_rate_pct"] = (100 * p).round(3)
    g["ci_low_pct"], g["ci_high_pct"] = (100 * lo).round(3), (100 * hi).round(3)
    g["z_score"] = ((p - p0) / np.sqrt(p0 * (1 - p0) / g.transactions)).round(2)
    return g.sort_values(["label_rate_pct", "state"], ascending=[False, True]).reset_index(drop=True)


QUERIES = {"A01": a01, "A02": a02, "A04": a04, "A05": a05, "A08": a08, "A09": a09, "A10": a10, "A11": a11, "A12": a12,
           "A13": a13, "A14": a14, "A15": a15, "A16": a16, "A17": a17, "A18": a18, "A19": a19, "A20": a20, "A21": a21, "A22": a22}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True)
    ap.add_argument("--queries", nargs="*", help="Subset, for example A09 A10 (default: all)")
    ap.add_argument("--output")
    a = ap.parse_args()
    p = Path(a.input)
    if not p.exists():
        sys.exit(f"Input not found: {p}")
    df = load(p)
    pd.set_option("display.width", 230)
    pd.set_option("display.max_columns", 30)
    pd.set_option("display.max_rows", 80)
    out = ["PYTHON (pandas) REFERENCE RESULTS FOR sql/04_advanced_analytical_queries.sql",
           "Queries without a reference here (A03, A06, A07) are checked structurally; see the catalogue."]
    for q in (a.queries or QUERIES):
        t = QUERIES[q](df)
        out += ["", "=" * 78, f"{q}  ({len(t)} rows)", "=" * 78, t.to_string(index=False, max_rows=70)]
    text = "\n".join(out)
    print(text)
    if a.output:
        Path(a.output).parent.mkdir(parents=True, exist_ok=True)
        Path(a.output).write_text(text + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
