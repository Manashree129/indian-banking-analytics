# SQL Query Catalogue

Scripts documented here:
- [`sql/04_advanced_analytical_queries.sql`](../sql/04_advanced_analytical_queries.sql): 22 additional analytical queries, A01-A22
- [`sql/05_views.sql`](../sql/05_views.sql): 6 reusable views, V1-V6

Not documented here: the 21 foundational queries E01-E21 in [`sql/03_exploratory_analysis.sql`](../sql/03_exploratory_analysis.sql) (Day 2, executed in PostgreSQL by the project owner) and the 72 reconciliation checks in `sql/02`. The E-queries are **not** counted toward the A-query totals below.

Last updated: Day 3.

## 1. Verification status (read this first)

Four different levels of evidence are used. They are never mixed.

| Level | Meaning | A01-A22 (`sql/04`) | Views (`sql/05`) |
|---|---|---|---|
| **Verified using SQLite** | The script was run in SQLite after mechanical dialect rewrites ([`python/sqlite_logic_check.py`](../python/sqlite_logic_check.py)). Shows the logic runs and returns sensible results. **Not PostgreSQL.** | 22 of 22 ran, 0 errors ([output](evidence/day3_sqlite_logic_check.txt)) | 6 of 6 created and queried, 0 errors |
| **Independently checked using pandas** | Results recomputed from the CSV with no SQL ([`python/advanced_sql_reference.py`](../python/advanced_sql_reference.py)) and compared with the SQLite results | 19 of 22 compared automatically and matched (A01, A02, A04, A05, A08-A22); A03, A06 and A07 verified by direct checks (see 2.1) | Row counts, per-group totals, status shares, flags and the 9 exception counts checked against pandas |
| **Executed successfully in PostgreSQL** | Run in PostgreSQL 18 with pgAdmin 4 and the output inspected | **None yet. Pending.** | **None yet. Pending.** |
| **Still pending** | Everything that needs a real PostgreSQL run | All 22 queries and all 6 views | |

The SQLite and pandas checks are logic evidence only. They do not prove PostgreSQL syntax or behaviour. In particular they cannot confirm `generate_series`, `FILTER` on `PERCENTILE_CONT`, `CORR`, `DATE_TRUNC`, `INTERVAL` arithmetic or `CREATE OR REPLACE VIEW` on a real PostgreSQL server. The scripts were also reviewed line by line in their original PostgreSQL form.

"Reference values" below were calculated outside PostgreSQL (SQLite and pandas agree). They are what your pgAdmin grids should show if everything is correct. A difference is a finding to investigate, not something to patch.

### 1.1 Advanced-query count (honest breakdown)

| Level | Queries | Count |
|---|---|---:|
| **Advanced: multi-step** (two or more CTE steps or a correlated subquery, combined with window, ranking, percentile or generated-calendar logic) | A01, A02, A04, A08, A09, A10, A13, A14, A17, A21, A22 | **11** |
| **Advanced: single technique** (one clearly advanced feature in a short query) | A03, A05, A06, A07, A11, A12, A16, A19, A20 | 9 |
| **Intermediate** (grouped or conditional aggregation with CTEs, no window or ordered-set logic) | A15, A18 | 2 |
| **Total additional queries** | | **22** |

Project target: at least 20 queries and at least 10 genuinely advanced queries. The 11 multi-step queries are counted as "genuinely advanced". The 9 single-technique queries do use advanced features but are shorter, so they are reported separately and not used to reach the target. Combined with E01-E21 the project has 43 analytical queries, but the Day 3 target is judged on the 22 A-queries alone.

### 1.2 SQL techniques demonstrated

| Required technique | Where |
|---|---|
| Single CTE / multiple CTEs | A03, A05, A06 (single); A01, A02, A04, A08, A09, A10, A13, A14, A21, A22 (multiple) |
| `ROW_NUMBER()` | A02, A05, A06 |
| `RANK()` | A05, A07, A08, A22 |
| `DENSE_RANK()` | A04, A05 |
| `LAG()` / `LEAD()` | A01, A04, A20 (LEAD in A20) , A21 |
| Running totals / cumulative aggregates | A03, A10, A14 |
| Rolling averages / rolling windows | A02 (previous 7 calendar days), A13 (3 calendar months) |
| Month-over-month | A01 |
| Year-over-year | A01 (by month), A04 (by type) |
| Conditional aggregation | A07, A08, A15, A16, A17, A18 |
| `CASE WHEN` | A01, A09, A16, A18, A21, A22 and others |
| Subqueries / correlated subqueries | A17 (correlated `EXISTS`), bounds subqueries in A02 and A13 |
| `HAVING` with minimum sample size | A08 (500), A09 (200), A11 (1,000), A12 (100 labelled), A22 (1,000) |
| `PERCENTILE_CONT()` | A11, A12, A16, A19 |
| `CORR()` | A19 |
| `NTILE()` | A10, A14 |
| Date-based analysis | A01-A04, A13, A20, A21 |
| Data-quality / exception detection | A15, A17, A20 (and the views V6) |
| Generated calendar (`generate_series`) | A02, A13 |
| Wilson confidence intervals | A08, A09, A22, V5 |

## 2. Conventions shared by all queries

- Table: `banking.transactions` (typed table from `01_schema_and_load.sql`). Schema-qualified names everywhere.
- Each query is self-contained, read-only, ends with a semicolon, and needs no temporary table and no other script. The views in `05` are independent of the queries.
- `fraud-labelled` = `is_fraud = 1`, a supplied label, not confirmed fraud. Amounts are never called losses.
- Currency is undocumented (not assumed to be INR). Amounts on Failed, Reversed and Pending rows are attempted amounts.
- `account_balance` has no reliable definition; no query claims an overdraft.
- `customer_id` is not a stable customer; customer-level queries describe ID values only.
- Complete years: 2019-2023. 2024 holds one day and is excluded where it would distort a trend.
- Rolling windows use calendar periods built from `generate_series`, so a missing day or month counts as zero instead of shortening the window (A02: previous 7 calendar days excluding the day itself; A13: current plus previous 2 calendar months). No day or month is missing in this dataset.
- Zero denominators use `NULLIF`; first-period lags are NULL; ranking ties use explicit tie-breakers.
- Confidence intervals: 95% Wilson (z = 1.96). With many groups compared, some differences appear by chance, and nothing here shows causes.

### 2.1 How the three queries without an automatic pandas comparison were checked

- **A03**: last cumulative value equals the 2019-2023 row count (549,705) and `cumulative_pct_of_total` ends at 100.00; December 2019 year-to-date equals the 2019 row count (110,083).
- **A06**: the 45 transaction IDs returned equal the top 3 per category computed in pandas, in the same order.
- **A07**: `pct_of_type` sums to 100 within each of the 10 transaction types (60 rows).

### 2.2 Relationship to the Day 2 queries (E01-E21)

No A-query repeats an E-query. These pairs touch the same tables, so the difference is stated:

| A-query | Related E-query | What A adds |
|---|---|---|
| A01 | E14 monthly volume | Month-over-month and year-over-year change with gap-safe logic |
| A04 | E02 by year | Year-over-year change and yearly rank by transaction type |
| A05, A14 | E18 transactions per customer_id | Ranking with three tie rules (A05) and concentration deciles (A14) |
| A07, A08 | E04, E05 channel and type summaries | Channel mix within type with ranks (A07); failed-or-reversed rate per combination with intervals (A08) |
| A09, A10 | E09 amount bands | Label rate by type inside each band (A09); decile gains table with cumulative capture (A10) |
| A11 | E10 overall percentiles | Percentiles per transaction type |
| A12 | E11 mean and median by label | Medians by channel, labelled vs other |
| A16 | E16 loan type cross-check | Three-group profile of the DQ-01 rows |
| A18, A19 | E20 amount vs balance | Ratio bands with label rate (A18); correlation and ratio percentiles (A19) |
| A22 | E07 state summary | Intervals, z-score and signal against the overall rate |

A02, A03, A06, A13, A15, A17, A20 and A21 have no counterpart in E01-E21.

## 3. Query catalogue (sql/04)

Each entry lists: business question, SQL concepts, metric and denominator, logic, output columns, execution status, reference values for validation, interpretation guidance and limitations. **PostgreSQL status for every query: pending.** Status line format: SQLite = logic run; pandas = independent check.

### A01 - Monthly volume with month-over-month and year-over-year change
*Advanced: multi-step.* **Question:** how do monthly transaction counts and attempted amounts change from the previous month and from the same month a year earlier? **Concepts:** CTE chain, `LAG`, self-join on (year, month), `NULLIF`. **Metric:** change % = (current - comparison) / comparison x 100. MoM is shown only when the previous row is exactly the previous calendar month; YoY joins on (year - 1, same month). Scope Jan 2019 - Dec 2023. **Logic:** aggregate by month, lag the previous month and a month index, join the prior-year month. **Output:** `month_start, transactions, mom_transactions_pct, same_month_prev_year_transactions, yoy_transactions_pct, total_amount, mom_amount_pct, yoy_amount_pct`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 60 rows. Jan 2019: 9,406 transactions, MoM and YoY NULL. Feb 2019 MoM -12.61%. Jan 2020: MoM +1.01%, YoY +0.36%. Across all months MoM ranges -12.61% to +13.02% and YoY -4.98% to +4.56%. **Interpretation:** monthly counts are broadly flat. Month length alone changes counts by several percent, so MoM swings are partly calendar effects. **Limitations:** 2019 has no YoY; amounts are attempted amounts in an unknown currency.

### A02 - Unusual days against the previous 7 calendar days
*Advanced: multi-step.* **Question:** which days deviate most from the recent norm? **Concepts:** `generate_series` calendar, `LEFT JOIN` + `COALESCE`, framed window `ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING`, `ROW_NUMBER`. **Metric:** baseline = average of the previous 7 calendar days (day excluded); deviation % = (transactions - baseline) / baseline x 100; first 7 days excluded. **Logic:** calendar -> daily counts -> zero-filled series -> baseline window -> keep days with a full window -> rank by absolute deviation. **Output:** `rank_by_abs_deviation, day, transactions, baseline_7d_avg, deviation_pct`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 15 rows. Rank 1: 2023-11-11, 373 transactions vs baseline 304.1 (+22.6%). Rank 2: 2022-06-26, 242 vs 305.0 (-20.7%). **Interpretation:** daily counts vary naturally by roughly this much, so the top days are a screen, not evidence of events. **Limitations:** descriptive only; no explanation for any day is available in the data.

### A03 - Running totals by month and year-to-date
*Advanced: single technique.* **Question:** how do volume and amount accumulate, and what share of the five-year total is reached each month? **Concepts:** `SUM() OVER` with `UNBOUNDED PRECEDING`, `PARTITION BY year` for YTD, whole-table window denominator. **Metric:** cumulative_pct = running total / total for 2019-2023 x 100. **Output:** `month_start, transactions, cumulative_transactions, cumulative_pct_of_total, year_to_date_transactions, total_amount, cumulative_amount`. **Status:** SQLite verified, direct checks (2.1), PostgreSQL pending. **Reference:** 60 rows. Jan 2019 cumulative 9,406 (1.71%). Final cumulative 549,705 (100.00%). Dec 2019 year-to-date 110,083. **Interpretation:** a steady, nearly linear rise (about 1.7% per month). **Limitations:** 2024 excluded; cumulative amount is attempted amount.

### A04 - Year-over-year change by transaction type, with yearly rank
*Advanced: multi-step.* **Question:** which transaction types grew or shrank between complete years, and how do they rank by amount each year? **Concepts:** CTE, `LAG` with `PARTITION BY`, `DENSE_RANK` with `PARTITION BY`. **Metric:** YoY % shown only when the previous row is the preceding year. **Output:** `transaction_type, calendar_year, transactions, yoy_transactions_pct, total_amount, yoy_amount_pct, amount_rank_in_year`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 50 rows (10 types x 5 years); 2019 YoY NULL. RTGS ranks 1 by amount in every year; ATM_Withdrawal 2020 YoY +2.07% (transactions). **Interpretation:** transaction-count changes never exceed 3.84% in absolute value for any type; amount changes are larger (up to 10.92%). **Limitations:** ranking ties are broken by type name, so the rank is unique in practice; amounts include non-successful rows.

### A05 - Customer ID activity ranking: ROW_NUMBER vs RANK vs DENSE_RANK
*Advanced: single technique.* **Question:** which customer_id values are most active and how do the three ranking functions treat ties? **Concepts:** CTE, `ROW_NUMBER`, `RANK`, `DENSE_RANK`, `COUNT(DISTINCT)`. **Metric:** rank by transactions per customer_id (tie-break customer_id for ROW_NUMBER only). **Output:** `customer_id, transactions, total_amount, distinct_states, row_number_rank, rank_with_gaps, dense_rank`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 15 rows. CUST003688 and CUST054493 both have 20 transactions (row numbers 1 and 2; rank 1 and 1; dense rank 1 and 1). The next four IDs have 19 (rank 3, dense rank 2). The 15 rows show 6-10 distinct states per ID. **Interpretation:** illustrates tie handling; the distinct-state count shows one ID appearing in many states. **Limitations:** customer_id is not a stable customer (DQ-02).

### A06 - Three largest transactions in each merchant category
*Advanced: single technique.* **Question:** what are the highest-value transactions per category, through which channel, with what status and label? **Concepts:** `ROW_NUMBER` with `PARTITION BY`, deterministic tie-break, top-N per group. **Metric:** rank by amount within category, ties by transaction_id. **Output:** `merchant_category, rank_in_category, transaction_id, transaction_date, transaction_type, channel, transaction_direction, transaction_amount, transaction_status, is_fraud`. **Status:** SQLite verified, direct check (2.1), PostgreSQL pending. **Reference:** 45 rows (15 categories x 3). E-Commerce rank 1: TXN000347558, 6,151,663.89, RTGS, Mobile_App. Education rank 1: TXN000423543, 7,923,295.55, Cheque. **Interpretation:** across the 45 rows, 27 are Debits, 38 have Success status and 3 are fraud-labelled; 7 were not completed (4 Pending, 2 Failed, 1 Reversed), so the largest amounts are not always completed money movements. **Limitations:** a probable 10,000,000.00 ceiling (DQ-04) means amounts at the top may be capped.

### A07 - Channel mix within each transaction type
*Advanced: single technique.* **Question:** through which channels does each type flow, and which channel carries the most completed amount? **Concepts:** conditional aggregation, window `SUM` with `PARTITION BY`, `RANK` with `PARTITION BY`. **Metric:** pct_of_type = channel rows / type rows; success amount sums Success rows only. **Output:** `transaction_type, channel, transactions, pct_of_type, channel_rank_in_type, success_amount, pct_of_type_success_amount`. **Status:** SQLite verified, direct check (2.1), PostgreSQL pending. **Reference:** 60 rows. ATM_Withdrawal via Mobile_App: 20,774 transactions = 37.70% of the type. **Interpretation:** every type appears in every channel in similar proportions (Mobile_App carries 37.6%-38.5% of each type), including pairings that are unnatural, such as ATM_Withdrawal through Web. **Limitations:** the pairing logic of the source is undocumented; this describes the file, not real payment behaviour.

### A08 - Failed-or-reversed rate by transaction type and channel
*Advanced: multi-step.* **Question:** is any type/channel combination meaningfully worse than the overall failed-or-reversed rate? **Concepts:** four CTE steps, scalar overall rate via `CROSS JOIN`, `HAVING COUNT(*) >= 500`, Wilson interval, `RANK`, `CASE` signal. **Metric:** (Failed + Reversed) / rows in the combination; overall = same ratio over 550,000 rows. **Output:** `rank_by_rate, transaction_type, channel, transactions, failed, reversed, failed_or_reversed_pct, overall_pct, ci_low_pct, ci_high_pct, ratio_to_overall, signal`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 15 rows (top 15 of 60). Overall 5.99%. Rank 1: Cheque via Branch, 2,167 transactions, 105 failed, 51 reversed, 7.20% (interval 6.18-8.36), signal "above overall". **Interpretation:** the highest combinations are about 1.05-1.20 times the overall rate; with 60 combinations compared, a few "above overall" signals are expected by chance. **Limitations:** the reason for a failure or reversal is not in the data.

### A09 - Fraud-label rate by transaction type within amount band
*Advanced: multi-step.* **Question:** RTGS and Cheque have higher overall label rates but larger amounts; do they stand out once amount size is held roughly constant? **Concepts:** five CTE steps, `CASE` banding, stratified comparison, `HAVING COUNT(*) >= 200`, Wilson interval, ratio to the band's own rate. **Metric:** rate = labelled / rows in the (band, type) cell; band rate = labelled / rows in the whole band. **Output:** `amount_band, transaction_type, transactions, fraud_labelled, label_rate_pct, band_rate_pct, ratio_to_band, ci_low_pct, ci_high_pct, signal`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 24 rows. Band 3 (100,000-999,999.99): RTGS 434 of 21,414 = 2.027% vs band 1.783%, signal "above band rate"; Cheque and NEFT "below band rate". Band 4 (1,000,000 and over): RTGS 93 of 1,180 = 7.881% and Cheque 34 of 419 = 8.115% vs band 8.247%, both "consistent with band rate". Bands 1-2: all cells between 0.68% and 0.99%. **Interpretation:** most of the higher RTGS/Cheque rate is explained by their larger amounts; a small excess remains for RTGS in band 3. This is an association in a supplied label, not a cause. **Limitations:** label assignment is undocumented; cells under 200 rows are not shown.

### A10 - Fraud-label concentration by amount decile (gains table)
*Advanced: multi-step.* **Question:** what share of fraud-labelled rows sits in the largest transactions? **Concepts:** `NTILE(10)`, CTE, cumulative `SUM() OVER`, whole-table denominators, lift. **Metric:** decile 1 = largest 10% of rows by amount (ties by transaction_id); cumulative share = labelled in deciles 1..k / all labelled; lift = decile rate / overall rate. **Output:** `amount_decile, transactions, min_amount, max_amount, fraud_labelled, label_rate_pct, cumulative_labelled, cumulative_share_of_labelled_pct, lift_vs_overall`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 10 rows of 55,000. Decile 1: amounts 51,277.67-10,000,000.00, 907 labelled (1.649%), cumulative share 18.61%, lift 1.86. Deciles 2-10: rates 0.736%-0.855%. **Interpretation:** the label is concentrated in the very top of the amount range (see A09 and E09), not spread across the top decile. **Limitations:** equal amounts can straddle decile boundaries; not confirmed fraud and not losses.

### A11 - Amount distribution by transaction type (percentiles)
*Advanced: single technique.* **Question:** how skewed are amounts within each type? **Concepts:** `PERCENTILE_CONT`, mean-to-median ratio, `HAVING COUNT(*) >= 1000`. **Metric:** continuous percentiles per type; mean_to_median = mean / median. **Output:** `transaction_type, transactions, p25, median, p75, p95, p99, mean, mean_to_median`. **Status:** SQLite verified (percentile via equivalent function), pandas matched, PostgreSQL pending. **Reference:** 10 rows. RTGS median 161,495.24, mean 269,254.41 (ratio 1.67). UPI median 657.65. Cheque mean-to-median 3.58. ATM_Withdrawal p95 and p99 both 10,000.00. **Interpretation:** medians differ by more than two orders of magnitude across types; use the median for typical size. **Limitations:** amounts include non-successful rows; the 10,000,000.00 ceiling caps the tail.

### A12 - Median amount of fraud-labelled vs other transactions, by channel
*Advanced: single technique.* **Question:** is the labelled-versus-other amount gap consistent across channels? **Concepts:** `PERCENTILE_CONT ... FILTER`, `COUNT ... FILTER`, `HAVING` (100 labelled rows). **Metric:** median per channel for is_fraud = 1 and = 0; ratio = labelled / other. **Output:** `channel, labelled_transactions, other_transactions, median_labelled, median_other, median_ratio`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 6 rows. Mobile_App: 1,809 labelled, median 2,751.01 vs 2,041.06 (ratio 1.35). Branch ratio 1.06; API 3,000.00 vs 2,024.39 (1.48). **Interpretation:** medians are only modestly higher for labelled rows; the large mean gap in E11 comes from a small number of very large amounts. **Limitations:** amounts on labelled rows are not losses. `PERCENTILE_CONT ... FILTER` is the construct most worth confirming in PostgreSQL.

### A13 - Rolling 3-month failed-or-reversed rate
*Advanced: multi-step.* **Question:** is the failed-or-reversed share drifting once monthly noise is smoothed? **Concepts:** `generate_series` month calendar, `LEFT JOIN` + `COALESCE`, framed window `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW`, ratio of sums. **Metric:** SUM(failed + reversed) / SUM(transactions) over the current and previous 2 calendar months; only full 3-month windows; Mar 2019 - Dec 2023. **Output:** `month_start, transactions, failed_or_reversed, monthly_rate_pct, window_transactions, window_bad, rolling_3m_rate_pct`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 58 rows. Mar 2019: monthly 6.26%, rolling 6.16%. Dec 2023: rolling 6.04%. Rolling rate stays between 5.70% and 6.24%. **Interpretation:** no visible drift. **Limitations:** descriptive; a ratio of sums, not an average of monthly rates.

### A14 - How concentrated is activity across customer_id values?
*Advanced: multi-step.* **Question:** do a few customer_id values account for much of the activity? **Concepts:** three CTE steps, `NTILE(10)` over an aggregate, cumulative `SUM() OVER`. **Metric:** ten equal-count groups of IDs by transactions (group 1 most active); share = group rows / all rows. **Output:** `activity_group, customer_ids, min_transactions_per_id, max_transactions_per_id, transactions, pct_of_transactions, cumulative_pct, total_amount`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 10 rows. Group 1: 7,992 IDs, 10-20 transactions each, 94,222 transactions (17.13%). Cumulative 54.82% by group 4; group 10 holds 4.00%. **Interpretation:** moderate concentration: the most active 10% of IDs hold 17% of rows. **Limitations:** customer_id is not a stable customer (DQ-02), so this is not customer concentration.

### A15 - Do customer_id attributes stay constant? (data-quality exception summary)
*Intermediate.* **Question:** for IDs with at least two rows, how often do state, account type, credit score, KYC status or loan flag change? **Concepts:** CTE, `COUNT(DISTINCT)`, conditional aggregation, `HAVING`. **Metric:** share = IDs whose attribute has more than one value / IDs with at least 2 rows (79,337). **Output:** count and percentage per attribute plus `all_five_constant`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 1 row. State varies for 78,998 (99.57%); account type 77,937 (98.24%); credit score 79,334 (100.00%); KYC 45,037 (56.77%); has_loan 71,922 (90.65%); all five constant for 0 IDs. **Interpretation:** evidences finding DQ-02: customer_id does not identify a customer with stable attributes. **Limitations:** shows the pattern, not its cause.

### A16 - Loan-flag consistency profile: three groups compared
*Advanced: single technique.* **Question:** how do the 19,422 DQ-01 rows compare with rows that have a named loan type and with no-loan rows? **Concepts:** `CASE` grouping, window share, `PERCENTILE_CONT`, conditional aggregation. **Metric:** per group: rows, share of all rows, median and mean EMI, median credit score, failed-or-reversed %, fraud-label rate (denominator = rows in the group). **Output:** `loan_group, transactions, pct_of_all_rows, median_emi, mean_emi, median_credit_score, failed_or_reversed_pct, fraud_labelled, fraud_label_rate_pct, mean_amount`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 3 rows. No loan 357,712 (65.04%); named type 172,866 (31.43%), median EMI 4,907.09; DQ-01 19,422 (3.53%), median EMI 4,872.50, mean EMI 6,697.62, median credit score 605 (others 600), failed-or-reversed 5.44% (others 6.01%), label rate 0.978% (others 0.879% and 0.889%). **Interpretation:** EMI levels of the DQ-01 rows are in line with the named-type borrower rows (median 4,872.50 vs 4,907.09). The small differences in credit score, failure rate and label rate rest on 190 labelled rows and are not tested; they do not establish why the loan type is missing. **Limitations:** rows are flagged, not corrected; cause unknown (UQ-07).

### A17 - Do customer IDs with DQ-01 rows also have rows with a named loan type?
*Advanced: multi-step.* **Question:** for IDs with a has_loan = 1 / loan_type = 'None' row, what do their other rows show? **Concepts:** CTE with `DISTINCT`, correlated `EXISTS` / `NOT EXISTS`, conditional aggregation. **Metric:** counts of customer_id values (categories overlap, except only_dq01_rows). **Output:** `customer_ids_with_dq01_rows, also_have_named_loan_rows, also_have_no_loan_rows, only_dq01_rows`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 1 row: 17,241; 15,302; 17,048; 26. **Interpretation:** most such IDs also appear with a named loan type (15,302 of 17,241, 88.8%) and with no loan (17,048, 98.9%); only 26 have DQ-01 rows alone. This is another sign that the ID is not a stable customer. **Limitations:** overlap is expected given DQ-02. This query relies on the index `idx_transactions_customer`; it may take a few seconds.

### A18 - Amount relative to account_balance, by direction (descriptive only)
*Intermediate.* **Question:** how large are amounts relative to the recorded balance, and does the label rate change with the ratio? **Concepts:** CTE, `CASE` banding of a ratio, `NULLIF`, window share within direction. **Metric:** ratio = amount / balance; pct_of_direction; label rate within band. **Output:** `transaction_direction, ratio_band, transactions, pct_of_direction, fraud_labelled, fraud_label_rate_pct`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 12 rows. Credit, ratio under 0.1: 92,098 (51.28%); ratio 10 and over: 8,426 (4.69%), label rate 2.884%. Debit, ratio 10 and over: 9,350 (2.52%), label rate 2.460%. **Interpretation:** the label rate rises with the ratio; because amount and balance are essentially uncorrelated (A19), a high ratio mostly means a large amount, so this is largely the amount effect from A09-A10. **Limitations:** balance has no reliable definition (UQ-01). A ratio above 1 is not evidence of an overdraft.

### A19 - Do amount and account_balance move together?
*Advanced: single technique.* **Question:** is there any linear relationship between amount and balance? **Concepts:** `CORR`, `PERCENTILE_CONT` on a derived ratio, `GROUP BY`. **Metric:** Pearson correlation per direction; percentiles of amount / balance. **Output:** `transaction_direction, transactions, corr_amount_balance, median_ratio, p95_ratio, p99_ratio`. **Status:** SQLite verified (CORR via equivalent function), pandas matched, PostgreSQL pending. **Reference:** 2 rows. Credit: 179,606 rows, correlation -0.0034, median ratio 0.0921, p95 9.2486, p99 47.9618. Debit: 370,394 rows, correlation -0.0001, median ratio 0.0576, p95 4.0106, p99 26.8116. **Interpretation:** correlation is essentially zero, so the balance does not track the amount, which supports not building balance-based metrics. **Limitations:** Pearson correlation is sensitive to large values; no overdraft or causal reading.

### A20 - ID sequence and date-order integrity (exception detection)
*Advanced: single technique.* **Question:** are IDs gap-free and is the file in date order? **Concepts:** `LAG`, `LEAD`, derived numeric ID, date arithmetic. **Metric:** id_gaps, date_regressions, next_before_current, max_day_jump. **Output:** `rows_checked, id_gaps, date_regressions, next_before_current, max_day_jump`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 1 row: 550,000; 0; 0; 0; 1. **Interpretation:** a perfectly regular sequence, consistent with generated or processed data; not proof. **Limitations:** a regular sequence does not show the data is synthetic. Runs a full-table window; may take a few seconds.

### A21 - Days between consecutive transactions of the same customer_id
*Advanced: multi-step.* **Question:** how soon does a customer_id transact again? **Concepts:** `LAG` with `PARTITION BY`, date difference, `CASE` bucketing, window share. **Metric:** days between consecutive rows of an ID (ordered by date, time, transaction_id); pct = bucket / all pairs (470,084; the 79,916 first rows per ID are excluded). **Output:** `gap_bucket, transaction_pairs, pct_of_pairs`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 6 rows. Same day 1,063 (0.23%); 1-7 days 14,184 (3.02%); 8-30 days 43,856 (9.33%); 31-90 days 96,021 (20.43%); 91-365 days 224,086 (47.67%); over 365 days 90,874 (19.33%). **Interpretation:** about 67% of gaps exceed 90 days (47.67% + 19.33%); same-day repeats are rare (0.23%). **Limitations:** customer_id is not a stable customer (DQ-02). Runs a partitioned window over all rows; may take a few seconds.

### A22 - State comparison of the fraud-label rate with confidence intervals
*Advanced: multi-step.* **Question:** do any states have a label rate distinguishable from the overall rate? **Concepts:** three CTE steps, `HAVING COUNT(*) >= 1000`, Wilson interval, z-score, `RANK`, `CASE`. **Metric:** rate = labelled / rows in the state; z = (p - overall) / sqrt(overall x (1 - overall) / n). **Output:** `rank_by_rate, state, transactions, fraud_labelled, label_rate_pct, overall_rate_pct, ci_low_pct, ci_high_pct, z_score, signal`. **Status:** SQLite verified, pandas matched, PostgreSQL pending. **Reference:** 10 rows. Rank 1: UP 0.948% (z +1.10); Maharashtra 0.895% (z +0.29); Rajasthan 0.782% (z -2.17, "below overall"); lowest Punjab 0.761% (z -1.98). Overall 0.886%. **Interpretation:** states are close to the overall rate; with 10 states, one nominal outlier is expected by chance. **Limitations:** the meaning of `state` is undocumented (UQ-05); no causal reading.

## 4. View catalogue (sql/05)

All views are read-only, schema-qualified, created with `CREATE OR REPLACE VIEW`, and based only on the existing typed table. Create `v_transactions_enriched` first (V5 reads it). **PostgreSQL status for every view: pending.** If you must reload the typed table with `01_schema_and_load.sql` SECTION B, run the commented `DROP VIEW` block at the end of `05_views.sql` first, because a view depending on the table blocks `DROP TABLE`.

### V1 - `banking.v_transactions_enriched`
**Purpose:** the typed table plus derived fields planned in the data dictionary. **Grain:** one row per transaction (550,000). **Columns (27):** the 20 source columns plus `transaction_ts`, `month_start`, `calendar_year`, `amount_band` (provisional, same edges as E09), `loan_group` (No loan / Loan flag set, named loan type / Loan flag set, loan type not recorded), `is_stub_period`, `amount_exceeds_balance_flag`. **Use:** main fact table for Power BI and Excel. **Limitations:** band edges are provisional; the flag compares two columns and is not an overdraft indicator. **Reference (SQLite and pandas):** 550,000 rows; loan_group 357,712 / 172,866 / 19,422; is_stub_period = 1 for 295 rows; flag = 1 for 79,494 rows.

### V2 - `banking.v_monthly_summary`
**Purpose:** monthly activity, status mix and label rate. **Grain:** one row per calendar month (61 rows). **Key columns:** `month_start, calendar_year, month_number, days_covered, days_in_month, is_complete_month, transactions, total_amount, avg_amount`, status counts and percentages, `fraud_labelled, fraud_label_rate_pct`. **Use:** trend page, executive KPIs, Excel pivot. **Limitations:** 2024-01 has one day (`is_complete_month = 0`); amounts are attempted. **Reference:** 61 rows, 60 complete; per-month counts, amounts, label counts and days covered match pandas; Feb 2020 `days_in_month` = 29.

### V3 - `banking.v_status_summary`
**Purpose:** status distribution by year. **Grain:** one row per calendar year x transaction_status (24 rows). **Key columns:** `calendar_year, days_covered, is_complete_year, transaction_status, transactions, pct_of_year, attempted_amount, avg_amount, fraud_labelled, fraud_label_rate_pct`. **Use:** Transaction Status and Data Quality page. **Limitations:** 2024 is a one-day year; amounts on non-success rows are attempted. **Reference:** 24 rows; counts match pandas; `pct_of_year` sums to 100 per year; only 2024 has `is_complete_year = 0`.

### V4 - `banking.v_channel_type_summary`
**Purpose:** channel x type comparison of volume, value, failure and label rate. **Grain:** one row per channel x transaction_type (60 rows). **Key columns:** `channel, transaction_type, transactions, pct_of_all, total_amount, avg_amount, failed_transactions, reversed_transactions, failed_or_reversed_pct, fraud_labelled, fraud_label_rate_pct, meets_min_sample` (1 when at least 500 rows). **Use:** Transaction Activity page, pivots. **Limitations:** filter on `meets_min_sample = 1` before reading rates; the combinations may not reflect real payment behaviour (see A07). **Reference:** 60 rows, all with at least 500 rows; counts match pandas; `pct_of_all` sums to 100.

### V5 - `banking.v_fraud_label_summary`
**Purpose:** the fraud-label rate for each value of seven dimensions, with counts, overall rate, ratio, Wilson interval and a signal. **Grain:** one row per dimension x value (56 rows: channel 6, transaction_type 10, state 10, merchant_category 15, account_type 5, kyc_status 3, amount_band 7). **Key columns:** `dimension, dimension_value, transactions, fraud_labelled, fraud_label_rate_pct, overall_rate_pct, rate_ratio_to_overall, ci_low_pct, ci_high_pct, meets_min_sample` (1 when at least 1,000 rows), `signal`. **Use:** Fraud-Label Analysis page. **Limitations:** supplied label, not confirmed fraud; each dimension is analysed alone, so the amount effect is not removed (see A09). **Reference:** 56 rows; within every dimension transactions sum to 550,000 and labelled rows to 4,873; RTGS rate about 1.854%.

### V6 - `banking.v_data_quality_exceptions`
**Purpose:** a register of documented data-quality findings and open questions with counts and shares. **Grain:** one row per documented exception (9 rows). **Key columns:** `display_order, exception_id, status` (Confirmed pattern / Open question), `description, unit, affected, population, affected_pct, handling`. **Use:** Data Quality page, interview evidence. **Limitations:** fixed to the Day 1-3 findings; discovers nothing new and cleans nothing. **Reference (affected / population):** DQ-01 19,422 / 550,000 (3.53%); DQ-02a 78,998 / 79,337; DQ-02b 79,334 / 79,337; DQ-03 295 / 550,000; DQ-04a 4; DQ-04b 38; DQ-04c 288 (each of 550,000); UQ-01 79,494 / 550,000 (14.45%); UQ-02 29,402 / 43,937 (66.92%).

## 5. Execution order and result grids to send (PostgreSQL 18, pgAdmin 4)

Prerequisite: `banking.transactions` exists with 550,000 rows (Day 2 done).

1. Open `sql/05_views.sql`, run the **whole file** (F5). Expected: six "CREATE VIEW" completions. Then run `SELECT COUNT(*) FROM banking.v_transactions_enriched;` (550000). Send any error text exactly.
2. Open `sql/04_advanced_analytical_queries.sql` and run **one query at a time** (select from the comment header to the semicolon, F5). Each is independent and may be run in any order.
3. Send these grids: **A01 (first 15 rows), A02, A09, A10, A11, A12, A13 (first and last rows), A15, A16, A17, A19, A20, A21, A22**, plus **views V5 and V6** (`SELECT * FROM banking.v_fraud_label_summary ORDER BY dimension, dimension_value;` and `SELECT * FROM banking.v_data_quality_exceptions ORDER BY display_order;`).
4. Most important to confirm in PostgreSQL (constructs that SQLite cannot fully test): **A02 and A13** (`generate_series` calendars), **A11, A12, A16, A19** (`PERCENTILE_CONT`, `FILTER`, `CORR`), **A17** (correlated `EXISTS`) and **V2, V5** (interval arithmetic, `UNION ALL`).
5. Optional: run A03-A08, A14, A18 and report only if one fails. If any query returns a different value from its reference, send the grid.

Pandas reference grids for comparison: `python python\advanced_sql_reference.py --input data\raw\indian_banking_transactions.csv` (saved in [`evidence/day3_python_reference.txt`](evidence/day3_python_reference.txt)).
