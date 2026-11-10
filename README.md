# Indian Banking Transactions Analytics & Risk Insights

**Project status: In Progress** (Days 1-2 complete and executed in PostgreSQL 18 by the project owner. Day 3 advanced SQL scripts, views and query catalogue are written and logic-checked, but their **PostgreSQL execution is pending**, see [Project Progress](#project-progress). Excel, Power Query, DAX and Power BI work is planned, not started.)

## Project Overview

An end-to-end analytics project on a 550,000-row banking transactions dataset. It covers data profiling and validation in Python, database design and advanced analytical SQL in PostgreSQL, independent validation in Excel, data preparation in Power Query, and an interactive four-page Power BI report with explicit DAX measures.

The emphasis is on reliable data handling: every figure is recalculated from the file, issues are investigated before any cleaning, and limitations are stated openly.

## Business Problem

A bank's operations and risk teams need to understand how transaction volume and value are distributed across channels, transaction types and categories, how often transactions fail or are reversed, and where the dataset's fraud label concentrates, while knowing how far the data can be trusted. This project answers those questions for the supplied dataset and documents what cannot be concluded from it.

## Project Objectives

1. Verify the dataset's size, structure, coverage and quality from the actual file.
2. Investigate data inconsistencies (for example `has_loan` versus `loan_type`) before making any cleaning decision.
3. Load the data into PostgreSQL and reconcile it with the Python profile.
4. Write at least 20 meaningful analytical SQL queries, at least 10 of them advanced.
5. Validate selected metrics independently in Excel.
6. Build a Power BI report with four pages and explicit DAX measures, reconciled to PostgreSQL.
7. Deliver evidence-backed findings, recommendations and a clear statement of limitations.

## Dataset Source and Initial Description

| Item | Verified from the file |
|---|---|
| File | `indian_banking_transactions.csv` (inside `archive.zip`) |
| Rows / columns | 550,000 / 20 |
| Date range | 2019-01-01 to 2024-01-01 (all 1,827 calendar days present; 2024 holds one day only) |
| Distinct `transaction_id` | 550,000 (no duplicates) |
| Distinct `customer_id` | 79,916 (see limitations) |
| Missing values | 0 empty cells |
| Fraud-labelled rows (`is_fraud = 1`) | 4,873 (0.886%) |
| Transaction status | Success 92.04%, Failed 3.98%, Reversed 2.00%, Pending 1.97% |
| Transaction amount | 2.40 to 10,000,000.00; mean 29,907.09; median 2,035.74 |

**Provenance and licence: not verified.** The original publisher, licence and generation method could not be confirmed, and several characteristics suggest the data may be simulated. Results describe patterns within this dataset only. See [source and provenance](documentation/source_and_provenance.md) and [data/README.md](data/README.md). The CSV is not included in this repository.

`is_fraud` is a supplied label. It is described as "fraud-labelled" throughout and is not treated as confirmed fraud or as a confirmed financial loss.

The data is historical (2019-2024) and must not be read as evidence of current banking activity.

## Technologies

| Technology | Planned use | Status |
|---|---|---|
| Python / Pandas | Reproducible profiling, validation and reconciliation reference values | Scripts created and run (Days 1-2) |
| PostgreSQL | Schema, loading, validation, exploratory and advanced SQL, views | Day 2 scripts executed in PostgreSQL 18 (reported by the project owner); Day 3 scripts written and logic-checked, **PostgreSQL execution pending** |
| Excel | Formulas and PivotTables for independent validation | Planned (Day 4) |
| Power Query | Repeatable data preparation | Planned (Day 4) |
| Power BI Desktop and DAX | Data model, four-page report, explicit measures | Planned (Day 4) |
| Git and GitHub | Version control and publication | Managed by the project owner |

## Data Quality (Day 1 findings)

Automated checks (Python): **33 PASS, 8 REVIEW, 0 FAIL** ([validation output](documentation/evidence/day1_validation_output.txt)). No data has been altered.

Confirmed findings:
- 19,422 rows (3.53%) have `has_loan = 1` but `loan_type = 'None'`, all with a positive EMI amount. Cause undocumented; rows are kept and will be labelled separately in analysis.
- `customer_id` is not a stable customer profile: state, credit score and other attributes change between rows of the same ID.
- Coverage ends one day into 2024; 2024 is excluded from year-over-year comparisons.
- Maximum amount (10,000,000.00) and balance limits (500.00 and 5,000,000.00) repeat, which suggests capping.

Unresolved questions (meaning of `account_balance`, `state`, the `is_fraud` label, currency, and Salary-category debits) are listed in the [data quality report](documentation/data_quality_report.md).

## Methodology: PostgreSQL Schema, Loading and Validation (Day 2)

Design in [`sql/01_schema_and_load.sql`](sql/01_schema_and_load.sql):

- **Two layers.** `raw_data.transactions_raw` holds all 20 columns as text, loaded unchanged from the CSV and never modified. `banking.transactions` is a typed copy built from it. The only transformation is type casting (`DATE`, `TIME`, `NUMERIC`, `SMALLINT`); no row is removed and no value is changed or imputed.
- **The literal text `None` is kept as text.** `loan_type = 'None'` (377,134 rows) is not converted to NULL, and the 19,422 `has_loan = 1` rows with no loan type are kept and flagged, not guessed.
- **Constraints.** A primary key plus CHECK constraints for rules that hold on every row (positive amounts, 300-900 credit score, valid flags and category lists, hour consistent with time, no-loan rows carry no loan type or EMI). A future file that breaks them fails to load.
- **Validation.** [`sql/02_data_quality_checks.sql`](sql/02_data_quality_checks.sql) creates one read-only view of 72 checks, each comparing a PostgreSQL value with a Python value (row counts, duplicates, `None` handling, money checksums, date range, categories, ranges, data-quality counts), plus metadata queries for types, constraints and indexes.
- **Reconciliation.** [`python/reconciliation_reference.py`](python/reconciliation_reference.py) recomputes every Python value fresh from the CSV and can compare it with an export of the PostgreSQL result.
- Step-by-step Windows/pgAdmin instructions: [database setup guide](documentation/database_setup.md).

### Day 2 validation status

| Item | Status |
|---|---|
| Python reference values for 72 checks | Verified from the file |
| SQL logic cross-check in SQLite (not PostgreSQL) | Done ([output](documentation/evidence/day2_sqlite_logic_check.txt)) |
| `01`, `02` and `03` executed in PostgreSQL 18 with pgAdmin 4 | **Done by the project owner.** Reported results: 550,000 raw rows and 550,000 typed rows, zero rows lost, all 72 reconciliation checks matched, all 21 queries E01-E21 executed successfully |
| Result grids from that run | Not reviewed by the assistant; the figures above are the project owner's report |

## SQL Analysis: Foundational Queries (Day 2)

[`sql/03_exploratory_analysis.sql`](sql/03_exploratory_analysis.sql) contains 21 foundational queries (E01-E21): table overview, volume and amount by year and month, status, channel, transaction type, category, state, account type and direction, amount bands and percentiles, fraud-label rates with denominators and a minimum sample size, hour and weekday patterns, loan investigation, KYC against status, customer ID activity, largest transactions and amount against balance. They use grouping, conditional aggregation, `CASE`, `HAVING`, a CTE, window denominators and `PERCENTILE_CONT`. The advanced SQL deliverable is in `sql/04` (below); these 21 queries are not counted toward it.

Descriptive observations so far (calculated in Python and SQLite; **to be confirmed in PostgreSQL**): the fraud-label rate is about 0.8% in every amount band below 100,000, 1.78% for 100,000-999,999.99 and 8.25% for amounts of 1,000,000 and over; it is otherwise flat across year, hour, channel and state. Details and denominators: [data quality report, section 9](documentation/data_quality_report.md).

## Advanced SQL Techniques (Day 3)

[`sql/04_advanced_analytical_queries.sql`](sql/04_advanced_analytical_queries.sql) holds **22 additional queries (A01-A22)**, none repeating E01-E21. By a strict definition (see the [query catalogue](documentation/sql_query_catalogue.md)):

| Level | Queries | Count |
|---|---|---:|
| Advanced: multi-step (two or more CTE steps or a correlated subquery, plus window, ranking, percentile or generated-calendar logic) | A01, A02, A04, A08, A09, A10, A13, A14, A17, A21, A22 | **11** |
| Advanced: single technique | A03, A05, A06, A07, A11, A12, A16, A19, A20 | 9 |
| Intermediate | A15, A18 | 2 |

Techniques implemented: single and multiple CTEs, `ROW_NUMBER`, `RANK`, `DENSE_RANK`, `LAG`, `LEAD`, `NTILE`, running totals and year-to-date, rolling windows on a generated calendar (previous 7 days, 3 months), month-over-month and year-over-year change, conditional aggregation, `CASE`, a correlated `EXISTS`, `HAVING` with minimum sample sizes, `PERCENTILE_CONT` (with `FILTER`), `CORR`, Wilson confidence intervals, and data-quality exception queries.

[`sql/05_views.sql`](sql/05_views.sql) creates **6 read-only views** for Excel and Power BI: `v_transactions_enriched` (transaction grain, 27 columns), `v_monthly_summary`, `v_status_summary`, `v_channel_type_summary`, `v_fraud_label_summary` and `v_data_quality_exceptions`. Grain, columns and limits of each are documented in the catalogue.

## Analytical Questions (Day 3)

Monthly growth and year-over-year change (A01, A04); unusual days against a rolling baseline (A02); cumulative volume (A03); customer ID ranking, concentration and repeat timing (A05, A14, A21); highest-value transactions per category (A06); channel mix by type (A07); failed and reversed patterns with intervals (A08, A13); fraud-label rate by type within amount band, by amount decile, by channel median and by state (A09, A10, A12, A22); amount distributions (A11); the loan-flag inconsistency (A16, A17); customer ID attribute stability (A15); amount against account balance (A18, A19); ID sequence integrity (A20).

## Key SQL Findings (Day 3)

**Evidence level:** every figure below was calculated outside PostgreSQL (SQLite logic check and an independent pandas calculation agree). **None has been confirmed in PostgreSQL yet.** They describe patterns in this dataset, not confirmed fraud or real banking behaviour.

- **The fraud label concentrates in very large amounts.** The top 10% of transactions by amount hold 18.61% of fraud-labelled rows (lift 1.86); the other nine deciles sit at 0.74%-0.86% (A10). Within amount bands, RTGS and Cheque are not clearly higher than other types, except a small RTGS excess in the 100,000-999,999.99 band (2.03% vs 1.78%) (A09).
- **Amount and `account_balance` are essentially uncorrelated** (correlation -0.0034 for credits, -0.0001 for debits), so balance-based metrics are not built (A19).
- **`customer_id` does not identify a stable customer.** Across IDs with two or more rows, credit score varies for 100.00%, state for 99.57% and account type for 98.24%; no ID keeps all five attributes constant (A15).
- **DQ-01 rows resemble ordinary borrower rows in EMI** (median 4,872.50 vs 4,907.09 for named loan types); 17,241 IDs have such rows and 15,302 of them also have a named loan type. The cause is still unknown (A16, A17).
- **Activity is flat over time.** Monthly counts and the rolling 3-month failed-or-reversed rate (5.70%-6.24%) show no drift; year-over-year transaction-count changes stay within 3.84% for every type (A01, A04, A13).
- **State label rates are close to the overall 0.886%.** Rajasthan (0.782%, z -2.17) is the only state flagged below overall in the displayed ranking; with 10 states one nominal outlier is expected by chance (A22).
- **Transaction IDs are gap-free and the file is date-ordered** (0 gaps, 0 regressions), consistent with generated or processed data but not proof (A20).

## SQL Documentation

- [Query catalogue](documentation/sql_query_catalogue.md): all 22 queries and 6 views with business question, concepts, metric, status and reference values
- [`sql/04_advanced_analytical_queries.sql`](sql/04_advanced_analytical_queries.sql) and [`sql/05_views.sql`](sql/05_views.sql)
- [SQLite logic-check output](documentation/evidence/day3_sqlite_logic_check.txt) and [pandas reference results](documentation/evidence/day3_python_reference.txt)

### Day 3 validation status

| Item | Status |
|---|---|
| 22 queries run in SQLite (logic check, not PostgreSQL) | 22 of 22 ran, 0 errors |
| 6 views created and queried in SQLite | 6 of 6, 0 errors |
| Independent pandas check | 19 of 22 queries compared automatically and matched; A03, A06, A07 verified by direct checks; views checked against pandas |
| Executed in PostgreSQL 18 | **Pending** (project owner to run and share the key grids listed in the catalogue) |

## Project Progress

| Area | Status |
|---|---|
| Day 1: inspection, provenance review, documentation, Python profiling and validation | Complete, approved |
| Day 2: schema and load script, quality checks, exploratory SQL, setup guide, Python reconciliation | Complete; executed in PostgreSQL 18 by the project owner |
| Day 3: 22 advanced queries, 6 views, query catalogue | Written; SQLite and pandas checks done; **PostgreSQL execution pending** |
| Day 4: Excel validation, Power Query, DAX, Power BI | Not started |
| Day 5: insights, limitations, final review | Not started |

## Planned Analysis

- Transaction volume and value over time, by channel, transaction type, category, state and account type.
- Transaction-status analysis (successful, failed, reversed, pending).
- Fraud-label rates by channel, transaction type, state, category and amount band, always shown with denominators and minimum sample sizes.
- Amount distribution using medians and percentiles, not only means.
- Advanced SQL: CTEs, window functions (`ROW_NUMBER`, `RANK`, `DENSE_RANK`, `LAG`, `LEAD`), running totals, conditional aggregation, `PERCENTILE_CONT`, correlated subqueries, exception-detection queries and reusable views.

## Planned Dashboard Pages

1. **Executive Overview**: transaction count, distinct customer IDs, total and average amount, fraud-label count and rate, status distribution, date coverage.
2. **Transaction Activity**: volume over time, amount distribution, transaction type and channel comparisons, direction analysis where valid.
3. **Fraud-Label Analysis**: label rate by channel, type, state, category and amount band, with counts and denominators.
4. **Transaction Status & Data Quality**: status distribution, data-quality exceptions, loan-type investigation, coverage and limitations.

## Initial Project Structure

```
indian-banking-analytics/
├── README.md
├── .gitignore
├── data/
│   └── README.md                     # source, access and licence notes
├── python/
│   ├── data_profiling.py             # profiling (Day 1, done)
│   ├── data_validation.py            # rule-based validation (Day 1, done)
│   ├── reconciliation_reference.py   # Python values and comparison for the SQL checks (Day 2)
│   ├── sqlite_logic_check.py         # optional logic check outside PostgreSQL (Days 2-3)
│   └── advanced_sql_reference.py     # independent pandas results for A01-A22 (Day 3)
├── sql/
│   ├── 01_schema_and_load.sql        # Day 2 (executed in PostgreSQL by the project owner)
│   ├── 02_data_quality_checks.sql    # Day 2 (executed in PostgreSQL by the project owner)
│   ├── 03_exploratory_analysis.sql   # Day 2 (executed in PostgreSQL by the project owner)
│   ├── 04_advanced_analytical_queries.sql  # Day 3 (22 queries, PostgreSQL execution pending)
│   └── 05_views.sql                  # Day 3 (6 views, PostgreSQL execution pending)
├── excel/                            # Day 4 (planned)
├── powerbi/                          # Day 4 (planned)
├── documentation/
│   ├── source_and_provenance.md      # done
│   ├── data_dictionary.md            # done
│   ├── data_quality_report.md        # Day 2 update (section 9)
│   ├── database_setup.md             # Windows/pgAdmin setup and loading guide (Day 2)
│   ├── sql_query_catalogue.md        # all queries and views documented (Day 3)
│   └── evidence/                     # saved script outputs
└── screenshots/                      # Day 4 (planned)
```

Files planned for later days (`metric_definitions.md`, `business_insights.md`, `limitations.md`, `validation_notes.md`, the Power BI file and screenshots) are not created yet. Additions to the agreed structure: `documentation/evidence/` for saved script outputs, `documentation/database_setup.md` for the setup guide, `documentation/sql_query_catalogue.md`, three extra Python scripts, and `.gitignore` to keep the raw dataset out of the repository.

## Reproduce the Checks

Python checks (Days 1-2):

```bash
pip install pandas
# place indian_banking_transactions.csv in data/raw/ (see data/README.md)
python python/data_profiling.py  --input data/raw/indian_banking_transactions.csv
python python/data_validation.py --input data/raw/indian_banking_transactions.csv
python python/reconciliation_reference.py --input data/raw/indian_banking_transactions.csv
```

PostgreSQL: follow the [database setup guide](documentation/database_setup.md), running `sql/01`, loading the CSV, then `sql/02` and `sql/03`. Day 3: run `sql/05_views.sql`, then the queries of `sql/04_advanced_analytical_queries.sql` one at a time (execution order and the grids to check are in the [query catalogue](documentation/sql_query_catalogue.md#5-execution-order-and-result-grids-to-send-postgresql-18-pgadmin-4)). Independent reference results: `python python/advanced_sql_reference.py --input data/raw/indian_banking_transactions.csv`.

## Documentation

- [Source and provenance](documentation/source_and_provenance.md)
- [Data dictionary](documentation/data_dictionary.md)
- [Data quality report](documentation/data_quality_report.md)
- [Day 1 profiling output](documentation/evidence/day1_profiling_output.txt)
- [Day 1 validation output](documentation/evidence/day1_validation_output.txt)
- [SQL query catalogue](documentation/sql_query_catalogue.md)
- [Database setup and loading guide](documentation/database_setup.md)
- [Day 2 Python reference values](documentation/evidence/day2_python_reference_values.txt)
- [Day 2 expected exploratory results](documentation/evidence/day2_python_reference_exploratory.txt)
- [Day 2 SQLite logic check output](documentation/evidence/day2_sqlite_logic_check.txt)

## Initial Limitations and Items Requiring Verification

- Dataset publisher, licence and generation method are unverified.
- Currency, the meaning of `account_balance`, `state` and the `is_fraud` label assignment are undocumented.
- `customer_id` cannot support customer-level conclusions.
- Data covers 2019-01-01 to 2024-01-01 only.
- The Day 3 SQL (`sql/04`, `sql/05`) has been checked in SQLite and against pandas but **not yet executed in PostgreSQL**; no PostgreSQL result is claimed for it.
- The 19,422 `has_loan = 1` rows with `loan_type = 'None'` remain unexplained; they are flagged, not corrected.
- `account_balance` has no usable definition: 14.45% of rows have an amount larger than the balance, in a pattern that fits neither "before" nor "after" the transaction.
- No Excel, Power Query, DAX or Power BI work has been completed yet; no result from those tools is claimed.
