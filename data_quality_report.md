# Data Quality Report

**Version:** Day 1 (initial). To be updated on Day 2 with PostgreSQL reconciliation.
**Dataset:** `indian_banking_transactions.csv`, 550,000 rows x 20 columns, 2019-01-01 to 2024-01-01.
**Evidence:** `python/data_profiling.py` and `python/data_validation.py`; saved outputs are in `documentation/evidence/`.
**Raw data status:** unchanged. No rows were deleted, no values imputed or corrected.

## 1. Summary

The file is structurally clean: no empty cells, no duplicate rows or IDs, valid dates and times, and only expected category values. Validation result: **33 PASS, 8 REVIEW, 0 FAIL**.

The 8 REVIEW items are not structural errors. They are inconsistencies or unusual patterns whose correct handling depends on field definitions the publisher has not provided. They are separated below into **confirmed findings** (the number is measured and the pattern is real) and **unresolved questions** (what it means is not known).

## 2. Checks that passed (confirmed clean)

| Check | Result |
|---|---|
| Row count | 550,000 (matches the preliminary baseline) |
| Column count and names | 20, as listed in the data dictionary |
| Empty cells in any column | 0 |
| Duplicate `transaction_id` | 0 (550,000 distinct) |
| Exact duplicate rows | 0 |
| Duplicates ignoring `transaction_id` | 0 |
| ID formats | All `TXN` + 9 digits and `CUST` + 6 digits |
| Dates | All parse as `YYYY-MM-DD`; 2019-01-01 to 2024-01-01; all 1,827 calendar days present |
| Times | All valid `HH:MM`; `transaction_hour` equals the hour of `transaction_time` in every row |
| Category columns | Only the observed values listed in the data dictionary (no spelling variants, no stray whitespace) |
| `transaction_amount` | Always > 0 (min 2.40) |
| `account_balance`, `emi_amount` | Never negative |
| `credit_score` | 300 to 899 |
| `is_fraud`, `has_loan` | Only 0 and 1 |
| `has_loan = 0` rows | `loan_type = 'None'` and `emi_amount = 0` in all 357,712 rows |
| `has_loan = 1` rows | `emi_amount > 0` in all 192,288 rows |

The dataset's literal text `None` in `loan_type` is not a missing value (see data dictionary note 2).

## 3. Confirmed findings (measured; handling decided or pending)

### DQ-01 - Borrowers with no recorded loan type
- **Finding:** 19,422 rows (3.53% of all rows; 10.10% of the 192,288 rows with `has_loan = 1`) have `has_loan = 1` and `loan_type = 'None'`. All 19,422 have `emi_amount > 0` (median 4,872.50).
- **Spread:** present in every year (about 3,800-3,900 per year for 2019-2023, 12 in 2024), so it is not a one-off load problem.
- **Fraud-label rate in these rows:** 0.978%, against 0.886% overall. This is a descriptive observation only; no conclusion is drawn.
- **Not known:** whether `None` means "type not recorded", "other loan type" or an error.
- **Day 1 decision:** keep the rows and the original columns unchanged. In Day 3-4 analysis, label them "Loan - type not recorded" in a derived column and always show them separately from named loan types. Do not guess a type and do not drop them.

### DQ-02 - `customer_id` does not describe a stable customer
- **Finding:** within the same `customer_id`, `state`, `account_type`, `credit_score`, `has_loan` and `kyc_status` frequently change (78,998 / 77,937 / 79,334 / 71,922 / 45,037 customers of 79,916 respectively). 579 IDs appear once; the maximum is 20 rows.
- **Impact:** customer-level conclusions are unreliable.
- **Decision:** report "distinct customer IDs" as an ID count only. Do not build customer-level segments or loan-holder profiles. Keep analysis at transaction level.

### DQ-03 - Coverage ends after one day of 2024
- **Finding:** 2024 contains a single date (2024-01-01, 295 rows, about a normal day's volume). 2019-2023 are complete years of about 109,600-110,250 rows each.
- **Decision:** exclude 2024 from year-over-year comparisons; keep it in totals and state the coverage clearly on the dashboard.

### DQ-04 - Repeated extreme values (possible capping)
- **Finding:** the maximum `transaction_amount` of 10,000,000.00 occurs 4 times; `account_balance` equals exactly 5,000,000.00 in 38 rows and exactly 500.00 in 288 rows. A continuous quantity rarely repeats its extreme value like this, so these look like ceilings or floors.
- **Impact:** averages and maxima are influenced by the cap. Use medians and percentiles as well as means.
- **Decision:** keep the rows. Report the cap as a limitation.

### DQ-05 - Amounts are highly skewed
- **Finding:** `transaction_amount` mean 29,907.09 versus median 2,035.74; 95th percentile 140,856.62; 99th percentile 530,534.67. The most frequent amounts are round numbers (1,000 x 16,542; 2,000 x 13,938; 500 x 8,216; 5,000 x 8,146).
- **Decision:** report mean and median together; use `PERCENTILE_CONT` in Day 3; do not remove "outliers" without a documented reason.

## 4. Unresolved questions (cannot be settled from the file)

| ID | Question | Why it matters | Evidence so far |
|---|---|---|---|
| UQ-01 | What does `account_balance` represent (before or after the transaction)? | Affects any balance-based metric | 79,494 rows (14.5%) have `transaction_amount > account_balance`; this may be normal if the balance is "after" a debit, or not |
| UQ-02 | Why are 66.9% of `merchant_category = 'Salary'` rows Debits (29,402 of 43,937)? | A salary is normally a credit; direction analysis by category could mislead | Salary rows also appear on non-Salary account types (Current 11,053; Savings 17,417; etc.) |
| UQ-03 | How was `is_fraud` assigned and what does it mean? | All fraud analysis depends on it | Label rate is almost flat by year, hour, channel, state and category; clearly higher only for RTGS (1.85% vs 0.89% overall) |
| UQ-04 | What currency and units apply to the money columns? | Reporting units | INR assumed from the context of the title; not stated |
| UQ-05 | What does `state` refer to (customer home state or transaction location)? | Interpretation of state-level results | Not stated |
| UQ-06 | Is the data real, anonymised or simulated? | Wording of every conclusion | See `source_and_provenance.md`; several indicators point to simulation, none is proof |
| UQ-07 | What does `loan_type = 'None'` mean for a borrower? | Resolves DQ-01 | Not stated |

## 5. Descriptive observations about the fraud label (not findings about fraud)

These are counts of the supplied label and nothing more.

| Observation | Figure |
|---|---|
| Rows labelled `is_fraud = 1` | 4,873 of 550,000 = 0.886% |
| Mean `transaction_amount`, labelled vs not | 119,446.21 vs 29,106.69 |
| Median `transaction_amount`, labelled vs not | 2,691.95 vs 2,030.99 (the mean gap is driven by a few large values) |
| Highest label rate by `transaction_type` | RTGS 1.85% (611 of 32,964); next highest Cheque 1.18% |
| Spread by `channel` | 0.85% (ATM) to 0.95% (Branch) |
| Label rate by `transaction_status` | Success 0.88%; Failed 0.94%; Pending 0.95%; Reversed 0.91% |

Statistical significance has not been tested. Day 3 will apply minimum sample sizes and show denominators with every rate. "Fraud-labelled" amounts must never be described as confirmed losses.

## 6. Transformations applied so far

None. The raw CSV is read only. Planned handling is listed under each finding and will be implemented, logged and reconciled on Days 2-4.

## 7. How to reproduce

```bash
python python/data_profiling.py  --input data/raw/indian_banking_transactions.csv
python python/data_validation.py --input data/raw/indian_banking_transactions.csv
```

Either script also accepts the original `archive.zip` as input.

## 8. Open work

- Day 2: reproduce row count, ID uniqueness, date range, missingness and DQ-01 counts in PostgreSQL and reconcile with Python.
- Day 2: confirm `'None'` loads as text, not NULL.
- Provenance: user to supply the original dataset page, publisher, licence and any description (see `source_and_provenance.md`, section 5).
