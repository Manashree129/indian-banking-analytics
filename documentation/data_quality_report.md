Data Quality Report
Version: Day 2 completed. This report records the Python profiling and validation findings and the completed PostgreSQL loading, reconciliation, and exploratory analysis.

Dataset: indian_banking_transactions.csv, 550,000 rows x 20 columns, 2019-01-01 to 2024-01-01.

Evidence: python/data_profiling.py, python/data_validation.py, and PostgreSQL execution of sql/01_schema_and_load.sql, sql/02_data_quality_checks.sql, and sql/03_exploratory_analysis.sql. Save actual query exports or screenshots in documentation/evidence/ if they are not already present.

Raw data status: unchanged. No rows were deleted, no values imputed or corrected.
1. Summary
The file is structurally clean: no empty cells, no duplicate rows or IDs, valid dates and times, and only expected category values. Validation result: 33 PASS, 8 REVIEW, 0 FAIL.

The 8 REVIEW items are not structural errors. They are inconsistencies or unusual patterns whose correct handling depends on field definitions the publisher has not provided. They are separated below into confirmed findings (the number is measured and the pattern is real) and unresolved questions (what it means is not known).
2. Checks that passed (confirmed clean)
Check	Result
Row count	550,000 (matches the preliminary baseline)
Column count and names	20, as listed in the data dictionary
Empty cells in any column	0
Duplicate transaction_id	0 (550,000 distinct)
Exact duplicate rows	0
Duplicates ignoring transaction_id	0
ID formats	All TXN + 9 digits and CUST + 6 digits
Dates	All parse as YYYY-MM-DD; 2019-01-01 to 2024-01-01; all 1,827 calendar days present
Times	All valid HH:MM; transaction_hour equals the hour of transaction_time in every row
Category columns	Only the observed values listed in the data dictionary (no spelling variants, no stray whitespace)
transaction_amount	Always > 0 (min 2.40)
account_balance, emi_amount	Never negative
credit_score	300 to 899
is_fraud, has_loan	Only 0 and 1
has_loan = 0 rows	loan_type = 'None' and emi_amount = 0 in all 357,712 rows
has_loan = 1 rows	emi_amount > 0 in all 192,288 rows


The dataset's literal text None in loan_type is not a missing value (see data dictionary note 2).
3. Confirmed findings (measured; handling decided or pending)
DQ-01 - Borrowers with no recorded loan type
- Finding: 19,422 rows (3.53% of all rows; 10.10% of the 192,288 rows with has_loan = 1) have has_loan = 1 and loan_type = 'None'. All 19,422 have emi_amount > 0 (median 4,872.50).
- Spread: present in every year (about 3,800-3,900 per year for 2019-2023, 12 in 2024), so it is not a one-off load problem.
- Fraud-label rate in these rows: 0.978%, against 0.886% overall. This is a descriptive observation only; no conclusion is drawn.
- Not known: whether None means "type not recorded", "other loan type" or an error.
- Day 1 decision: keep the rows and the original columns unchanged. In Day 3-4 analysis, label them "Loan - type not recorded" in a derived column and always show them separately from named loan types. Do not guess a type and do not drop them.
DQ-02 - customer_id does not describe a stable customer
- Finding: within the same customer_id, state, account_type, credit_score, has_loan and kyc_status frequently change (78,998 / 77,937 / 79,334 / 71,922 / 45,037 customers of 79,916 respectively). 579 IDs appear once; the maximum is 20 rows.
- Impact: customer-level conclusions are unreliable.
- Decision: report "distinct customer IDs" as an ID count only. Do not build customer-level segments or loan-holder profiles. Keep analysis at transaction level.
DQ-03 - Coverage ends after one day of 2024
- Finding: 2024 contains a single date (2024-01-01, 295 rows, about a normal day's volume). 2019-2023 are complete years of about 109,600-110,250 rows each.
- Decision: exclude 2024 from year-over-year comparisons; keep it in totals and state the coverage clearly on the dashboard.
DQ-04 - Repeated extreme values (possible capping)
- Finding: the maximum transaction_amount of 10,000,000.00 occurs 4 times; account_balance equals exactly 5,000,000.00 in 38 rows and exactly 500.00 in 288 rows. A continuous quantity rarely repeats its extreme value like this, so these look like ceilings or floors.
- Impact: averages and maxima are influenced by the cap. Use medians and percentiles as well as means.
- Decision: keep the rows. Report the cap as a limitation.
DQ-05 - Amounts are highly skewed
- Finding: transaction_amount mean 29,907.09 versus median 2,035.74; 95th percentile 140,856.62; 99th percentile 530,534.67. The most frequent amounts are round numbers (1,000 x 16,542; 2,000 x 13,938; 500 x 8,216; 5,000 x 8,146).
- Decision: report mean and median together; use PERCENTILE_CONT in Day 3; do not remove "outliers" without a documented reason.
4. Unresolved questions (cannot be settled from the file)
ID	Question	Why it matters	Evidence so far
UQ-01	What does account_balance represent (before or after the transaction)?	Affects any balance-based metric	79,494 rows (14.5%) have transaction_amount > account_balance; this may be normal if the balance is "after" a debit, or not
UQ-02	Why are 66.9% of merchant_category = 'Salary' rows Debits (29,402 of 43,937)?	A salary is normally a credit; direction analysis by category could mislead	Salary rows also appear on non-Salary account types (Current 11,053; Savings 17,417; etc.)
UQ-03	How was is_fraud assigned and what does it mean?	All fraud analysis depends on it	Label rate is almost flat by year, hour, channel, state and category; clearly higher only for RTGS (1.85% vs 0.89% overall)
UQ-04	What currency and units apply to the money columns?	Reporting units	INR assumed from the context of the title; not stated
UQ-05	What does state refer to (customer home state or transaction location)?	Interpretation of state-level results	Not stated
UQ-06	Is the data real, anonymised or simulated?	Wording of every conclusion	See source_and_provenance.md; several indicators point to simulation, none is proof
UQ-07	What does loan_type = 'None' mean for a borrower?	Resolves DQ-01	Not stated


5. Descriptive observations about the fraud label (not findings about fraud)
These are counts of the supplied label and nothing more.
Observation	Figure
Rows labelled is_fraud = 1	4,873 of 550,000 = 0.886%
Mean transaction_amount, labelled vs not	119,446.21 vs 29,106.69
Median transaction_amount, labelled vs not	2,691.95 vs 2,030.99 (the mean gap is driven by a few large values)
Highest label rate by transaction_type	RTGS 1.85% (611 of 32,964); next highest Cheque 1.18%
Spread by channel	0.85% (ATM) to 0.95% (Branch)
Label rate by transaction_status	Success 0.88%; Failed 0.94%; Pending 0.95%; Reversed 0.91%


Statistical significance has not been tested. Day 3 will apply minimum sample sizes and show denominators with every rate. "Fraud-labelled" amounts must never be described as confirmed losses.
6. Transformations applied so far
No source values were changed, imputed, or removed. PostgreSQL loading created a raw text layer (raw_data.transactions_raw) and a typed layer (banking.transactions) using explicit type conversions. Both layers contain 550,000 rows. The literal None in loan_type was preserved as text, not converted to SQL NULL.

No analytical cleaning has been applied to the source columns. Planned derived fields and labels will be implemented and documented during Days 3-4, with the original fields preserved.
7. How to reproduce
python python/data_profiling.py  --input data/raw/indian_banking_transactions.csv

python python/data_validation.py --input data/raw/indian_banking_transactions.csv
Either script also accepts the original archive.zip as input.
8. Open work
- PostgreSQL loading, reconciliation, and exploratory analysis: Completed for Day 2. The raw and typed tables each contain 550,000 rows, no rows were lost during loading, all 72 reconciliation checks returned MATCH, and exploratory queries E01-E21 executed successfully.
- Dataset provenance: Still open. The original dataset page, publisher, licence, and data-generation method have not been verified. See source_and_provenance.md, section 5.
- Evidence files: Confirm that actual PostgreSQL result exports or screenshots are saved in documentation/evidence/ if persistent evidence is required.
9. Day 2: PostgreSQL loading and reconciliation
9.1 Execution status
Item	Status
PostgreSQL / pgAdmin	Available; database indian_banking
sql/01_schema_and_load.sql	Executed successfully; raw and typed tables created and loaded
raw_data.transactions_raw	550,000 rows
banking.transactions	550,000 rows
Rows lost during loading	0
sql/02_data_quality_checks.sql	Executed; all 72 reconciliation checks returned MATCH
sql/03_exploratory_analysis.sql	All 21 exploratory queries, E01-E21, executed successfully
loan_type = 'None'	377,134 literal text values; 0 SQL NULLs
Date coverage	2019-01-01 to 2024-01-01
Database metadata	20 columns, 37 constraints, and 6 indexes reported by the metadata checks


PostgreSQL loading, reconciliation, and exploratory analysis have been completed for Day 2. These results are based on actual pgAdmin execution, not solely on Python reference calculations or the SQLite cross-check.

The original dataset's publisher, licence, and generation method remain unverified.
9.2 Schema and loading design (decisions)
Decision	Reason
Two layers: raw_data.transactions_raw (all TEXT, loaded unchanged) and banking.transactions (typed)	The raw data is preserved and the only transformation, type casting, is explicit and auditable
loan_type keeps the literal text None (not NULL) in both layers	None is a value in the file; NULL would hide the DQ-01 exception rows inside "missing". The loader's NULL string is left empty
No row removed, no value changed or imputed	No documented reason exists for any change (rules 10-11 of the brief)
19,422 has_loan = 1 / loan_type = 'None' rows kept	Cause unknown (UQ-07); they are labelled and reported, not guessed
Types: DATE, TIME, NUMERIC(14,2) / (12,2) for money, SMALLINT for flags and scores, VARCHAR for codes	Exact decimals for money; sizes cover the observed ranges (max amount 10,000,000.00)
CHECK constraints for rules that hold on all rows (positive amount, 300-900 score, valid flags and category lists, hour = hour of time, has_loan = 0 implies no loan type and no EMI)	A broken rule in a future file fails the load instead of passing silently
No CHECK constraint for has_loan = 1 implies a loan type	It is violated by the 19,422 known rows
transaction_ts and amount_band not stored in the table	Derived fields will be exposed through views on Day 3 so the table stays a faithful copy of the file
Five indexes (date, customer, type, channel, state)	For later queries; performance not benchmarked


9.3 What the checks cover
sql/02_data_quality_checks.sql creates one read-only view with 72 checks (each with a Python value and a PostgreSQL value): raw row count and distinct IDs; empty cells and stray spaces in the raw table; ID format; typed row count and rows lost; duplicates; the None text kept as text (377,134 rows) and no NULLs; exact checksums of the money and score columns (raw-to-typed fidelity); date range and per-year counts; distinct values per category and status counts; minimum and maximum of amount, balance, score and EMI; and the DQ/UQ counts in sections 3 and 4. Metadata queries list column types, constraints and indexes.
9.4 Supplementary logic cross-check in SQLite
python/sqlite_logic_check.py loads the CSV into SQLite, applies mechanical dialect rewrites and runs the same statements. Result: 72 of 72 checks MATCH, every non-PG-only statement in 02 and 03 ran without error (6 of 9 statements in 02, 19 of 21 in 03; the skipped ones use information_schema, pg_catalog or PERCENTILE_CONT), and the results for the key exploratory queries agree with the independent pandas calculation (day2_python_reference_exploratory.txt). This supplementary check shows that the SQL logic and expected values are consistent across the tested statements. It does not itself test PostgreSQL syntax, the schema script, or the percentile queries; those PostgreSQL scripts and exploratory queries were subsequently executed successfully in pgAdmin.

python/reconciliation_reference.py --compare was tested with a simulated export (72 of 72 match) and with one deliberately altered value (the mismatch was reported); that tests the script only.
9.5 New descriptive observations from the exploratory queries
These descriptive observations were initially cross-checked using SQLite and pandas. The corresponding exploratory SQL queries E01-E21 were subsequently executed successfully in PostgreSQL. They describe the supplied label, not confirmed fraud.
Observation	Figures
The fraud-label rate rises sharply with amount	Under 100,000: 0.77%-0.82% in every band. 100,000-999,999.99: 1.78% (612 of 34,333). 1,000,000 and over: 8.25% (144 of 1,746). The earlier RTGS and Cheque differences (1.85%, 1.18%) are consistent with this, because those types carry the largest amounts (average 269,254 and 130,362)
Amounts are large on labelled rows only in the tail	Median 2,691.95 (labelled) vs 2,030.99 (other); mean 119,446.21 vs 29,106.69
Label rate is flat across other dimensions	Years 0.87%-0.90% (2019-2023), hours 0.79%-1.01%, channels 0.85%-0.95%, states 0.76%-0.95%
DQ-01 is evenly spread	9.94%-10.28% of has_loan = 1 rows each year (2019-2023); 12 of 100 in 2024
Named loan types are clean	Each of the six named loan types appears only with has_loan = 1; their average positive EMI is 6,756-6,810, similar to the 'None' rows (6,698)
KYC status does not change outcomes	Success rate 91.80%-92.12% across Verified, Pending and Expired
Volume is uniform in time	4.09%-4.23% of rows per hour; 14.2%-14.3% per weekday
Status shares are stable	Success 92.04%, Failed 3.98%, Reversed 2.00%, Pending 1.97%; failed share 3.87%-4.21% across channels and types


9.6 Updates to open questions
- UQ-01 (account_balance). 79,494 rows (14.45%) have amount > balance: 35,592 of 179,606 credits (19.82%) and 43,902 of 370,394 debits (11.85%). If the balance were the balance after a transaction, a credit larger than the balance would require a negative prior balance, yet the minimum balance is 500. If it were the balance before, 11.85% of debits exceed the balance available. Neither reading fits every row, which suggests the balance is not tightly linked to the transaction amount. The definition remains undocumented, so balance-based metrics should not be built.
- UQ-03 (is_fraud). The amount pattern above is the only strong driver found so far. How the label was produced is still unknown.
- All four rows at the 10,000,000.00 ceiling have account balances between 12,230.57 and 80,694.61, and none is fraud-labelled.
9.7 Day 2 completion status
- [x] Load the CSV into PostgreSQL and create the typed table.
- [x] Reconcile the raw and typed tables using 72 checks; all returned MATCH.
- [x] Execute exploratory analysis queries E01-E21 successfully.
- [x] Investigate the loan-type inconsistency, transaction amount distribution, supplied fraud label, and other data-quality questions.
- [ ] Verify the original dataset's publisher, source URL, licence, and data-generation method.
- [ ] Preserve actual PostgreSQL result exports or screenshots in documentation/evidence/ if they are not already saved.
Day 2 status: Complete. Dataset provenance remains an open documentation task.