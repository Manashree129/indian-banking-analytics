/* =============================================================================
   02_data_quality_checks.sql
   Project : Indian Banking Transactions Analytics & Risk Insights
   Database: indian_banking      Schemas: raw_data (untouched raw copy), banking (typed)

   PURPOSE
     Reconcile the PostgreSQL tables with the Day 1 Python profiling and test the
     loaded data against explicit rules. No data is changed; the only object created is one read-only view.

   HOW TO RUN (pgAdmin 4, Query Tool)
     pgAdmin shows only the LAST result grid when several statements run together,
     so run ONE numbered statement at a time: select its text, press F5.

   WHAT EACH PART RETURNS
     PART 1  Creates one read-only view, banking.v_reconciliation_checks (72 numeric checks).
     PART 2  2a lists the 72 checks (python_value vs postgres_value, MATCH or MISMATCH);
             2b counts MATCH / MISMATCH.
     PART 3  First and last date (text checks).
     PART 4  Example rows for two confirmed findings (DQ-01 and the amount ceiling).
     PART 5  PostgreSQL metadata: column types, constraints and indexes (PG-only).

   The python_value numbers were computed by python/reconciliation_reference.py.
   Re-compute them yourself:  python python/reconciliation_reference.py --input <csv>
   or compare an exported result:  ... --compare 02_part2a_results.csv

   STATUS: written and logic-checked outside PostgreSQL; see documentation/data_quality_report.md
           for what has and has not been executed on a real PostgreSQL server.
   ============================================================================= */


/* ---------------------------------------------------------------------------
   PART 1 - Create the reconciliation view (72 checks)
   This is the only object this file creates. It is read-only and can be dropped with
   DROP VIEW banking.v_reconciliation_checks;
   Each row is one count, sum, minimum or maximum (areas: raw load, typed table, dates,
   categories, numeric ranges, consistency and data-quality rules). Tolerance 0.005.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW banking.v_reconciliation_checks AS
SELECT seq, check_id, area, check_name, python_value, postgres_value,
       postgres_value - python_value AS difference,
       CASE WHEN ABS(postgres_value - python_value) < 0.005 THEN 'MATCH' ELSE 'MISMATCH' END AS result
FROM (
SELECT 1 AS seq, 'R01' AS check_id, '1 Raw load' AS area, 'Rows in raw_data.transactions_raw' AS check_name, 550000 AS python_value, (SELECT COUNT(*) FROM raw_data.transactions_raw) AS postgres_value
UNION ALL
SELECT 2 AS seq, 'R02' AS check_id, '1 Raw load' AS area, 'Distinct transaction_id in raw table' AS check_name, 550000 AS python_value, (SELECT COUNT(DISTINCT transaction_id) FROM raw_data.transactions_raw) AS postgres_value
UNION ALL
SELECT 3 AS seq, 'R03' AS check_id, '1 Raw load' AS area, 'Raw rows with any NULL or empty cell' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM raw_data.transactions_raw WHERE transaction_id IS NULL OR TRIM(transaction_id) = '' OR customer_id IS NULL OR TRIM(customer_id) = '' OR transaction_date IS NULL OR TRIM(transaction_date) = '' OR transaction_time IS NULL OR TRIM(transaction_time) = '' OR account_type IS NULL OR TRIM(account_type) = '' OR transaction_type IS NULL OR TRIM(transaction_type) = '' OR transaction_amount IS NULL OR TRIM(transaction_amount) = '' OR transaction_direction IS NULL OR TRIM(transaction_direction) = '' OR account_balance IS NULL OR TRIM(account_balance) = '' OR merchant_category IS NULL OR TRIM(merchant_category) = '' OR state IS NULL OR TRIM(state) = '' OR credit_score IS NULL OR TRIM(credit_score) = '' OR has_loan IS NULL OR TRIM(has_loan) = '' OR loan_type IS NULL OR TRIM(loan_type) = '' OR emi_amount IS NULL OR TRIM(emi_amount) = '' OR transaction_status IS NULL OR TRIM(transaction_status) = '' OR channel IS NULL OR TRIM(channel) = '' OR kyc_status IS NULL OR TRIM(kyc_status) = '' OR is_fraud IS NULL OR TRIM(is_fraud) = '' OR transaction_hour IS NULL OR TRIM(transaction_hour) = '') AS postgres_value
UNION ALL
SELECT 4 AS seq, 'R04' AS check_id, '1 Raw load' AS area, 'Raw rows with leading/trailing spaces in any column' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM raw_data.transactions_raw WHERE transaction_id <> TRIM(transaction_id) OR customer_id <> TRIM(customer_id) OR transaction_date <> TRIM(transaction_date) OR transaction_time <> TRIM(transaction_time) OR account_type <> TRIM(account_type) OR transaction_type <> TRIM(transaction_type) OR transaction_amount <> TRIM(transaction_amount) OR transaction_direction <> TRIM(transaction_direction) OR account_balance <> TRIM(account_balance) OR merchant_category <> TRIM(merchant_category) OR state <> TRIM(state) OR credit_score <> TRIM(credit_score) OR has_loan <> TRIM(has_loan) OR loan_type <> TRIM(loan_type) OR emi_amount <> TRIM(emi_amount) OR transaction_status <> TRIM(transaction_status) OR channel <> TRIM(channel) OR kyc_status <> TRIM(kyc_status) OR is_fraud <> TRIM(is_fraud) OR transaction_hour <> TRIM(transaction_hour)) AS postgres_value
UNION ALL
SELECT 5 AS seq, 'R05' AS check_id, '1 Raw load' AS area, 'Raw transaction_id not TXN + 9 digits' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM raw_data.transactions_raw WHERE transaction_id !~ '^TXN[0-9]{9}$') AS postgres_value
UNION ALL
SELECT 6 AS seq, 'R06' AS check_id, '1 Raw load' AS area, 'Raw customer_id not CUST + 6 digits' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM raw_data.transactions_raw WHERE customer_id !~ '^CUST[0-9]{6}$') AS postgres_value
UNION ALL
SELECT 7 AS seq, 'R07' AS check_id, '1 Raw load' AS area, 'Raw loan_type equal to the literal text None' AS check_name, 377134 AS python_value, (SELECT COUNT(*) FROM raw_data.transactions_raw WHERE loan_type = 'None') AS postgres_value
UNION ALL
SELECT 8 AS seq, 'T01' AS check_id, '2 Typed table' AS area, 'Rows in banking.transactions' AS check_name, 550000 AS python_value, (SELECT COUNT(*) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 9 AS seq, 'T02' AS check_id, '2 Typed table' AS area, 'Rows lost between raw and typed table' AS check_name, 0 AS python_value, ((SELECT COUNT(*) FROM raw_data.transactions_raw) - (SELECT COUNT(*) FROM banking.transactions)) AS postgres_value
UNION ALL
SELECT 10 AS seq, 'T03' AS check_id, '2 Typed table' AS area, 'Distinct transaction_id' AS check_name, 550000 AS python_value, (SELECT COUNT(DISTINCT transaction_id) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 11 AS seq, 'T04' AS check_id, '2 Typed table' AS area, 'Distinct customer_id' AS check_name, 79916 AS python_value, (SELECT COUNT(DISTINCT customer_id) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 12 AS seq, 'T05' AS check_id, '2 Typed table' AS area, 'Exact duplicate rows' AS check_name, 0 AS python_value, ((SELECT COUNT(*) FROM banking.transactions) - (SELECT COUNT(*) FROM (SELECT DISTINCT transaction_id, customer_id, transaction_date, transaction_time, account_type, transaction_type, transaction_amount, transaction_direction, account_balance, merchant_category, state, credit_score, has_loan, loan_type, emi_amount, transaction_status, channel, kyc_status, is_fraud, transaction_hour FROM banking.transactions) d)) AS postgres_value
UNION ALL
SELECT 13 AS seq, 'T06' AS check_id, '2 Typed table' AS area, 'Duplicate rows ignoring transaction_id' AS check_name, 0 AS python_value, ((SELECT COUNT(*) FROM banking.transactions) - (SELECT COUNT(*) FROM (SELECT DISTINCT customer_id, transaction_date, transaction_time, account_type, transaction_type, transaction_amount, transaction_direction, account_balance, merchant_category, state, credit_score, has_loan, loan_type, emi_amount, transaction_status, channel, kyc_status, is_fraud, transaction_hour FROM banking.transactions) d)) AS postgres_value
UNION ALL
SELECT 14 AS seq, 'T07' AS check_id, '2 Typed table' AS area, 'loan_type values that are NULL (should be 0)' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE loan_type IS NULL) AS postgres_value
UNION ALL
SELECT 15 AS seq, 'T08' AS check_id, '2 Typed table' AS area, 'loan_type equal to the literal text None' AS check_name, 377134 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE loan_type = 'None') AS postgres_value
UNION ALL
SELECT 16 AS seq, 'T09' AS check_id, '2 Typed table' AS area, 'Checksum: SUM(transaction_amount)' AS check_name, 16448901663.56 AS python_value, (SELECT SUM(transaction_amount) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 17 AS seq, 'T10' AS check_id, '2 Typed table' AS area, 'Checksum: SUM(account_balance)' AS check_name, 46502563291.60 AS python_value, (SELECT SUM(account_balance) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 18 AS seq, 'T11' AS check_id, '2 Typed table' AS area, 'Checksum: SUM(emi_amount)' AS check_name, 1301222985.56 AS python_value, (SELECT SUM(emi_amount) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 19 AS seq, 'T12' AS check_id, '2 Typed table' AS area, 'Checksum: SUM(credit_score)' AS check_name, 329893855 AS python_value, (SELECT SUM(credit_score) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 20 AS seq, 'D01' AS check_id, '3 Dates' AS area, 'Distinct transaction_date values' AS check_name, 1827 AS python_value, (SELECT COUNT(DISTINCT transaction_date) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 21 AS seq, 'D02' AS check_id, '3 Dates' AS area, 'Rows dated before 2019-01-01' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_date < '2019-01-01') AS postgres_value
UNION ALL
SELECT 22 AS seq, 'D03' AS check_id, '3 Dates' AS area, 'Rows dated after 2024-01-01' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_date > '2024-01-01') AS postgres_value
UNION ALL
SELECT 23 AS seq, 'D04' AS check_id, '3 Dates' AS area, 'Rows in 2019' AS check_name, 110083 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_date >= '2019-01-01' AND transaction_date <= '2019-12-31') AS postgres_value
UNION ALL
SELECT 24 AS seq, 'D05' AS check_id, '3 Dates' AS area, 'Rows in 2020' AS check_name, 109767 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_date >= '2020-01-01' AND transaction_date <= '2020-12-31') AS postgres_value
UNION ALL
SELECT 25 AS seq, 'D06' AS check_id, '3 Dates' AS area, 'Rows in 2021' AS check_name, 110024 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_date >= '2021-01-01' AND transaction_date <= '2021-12-31') AS postgres_value
UNION ALL
SELECT 26 AS seq, 'D07' AS check_id, '3 Dates' AS area, 'Rows in 2022' AS check_name, 110247 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_date >= '2022-01-01' AND transaction_date <= '2022-12-31') AS postgres_value
UNION ALL
SELECT 27 AS seq, 'D08' AS check_id, '3 Dates' AS area, 'Rows in 2023' AS check_name, 109584 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_date >= '2023-01-01' AND transaction_date <= '2023-12-31') AS postgres_value
UNION ALL
SELECT 28 AS seq, 'D09' AS check_id, '3 Dates' AS area, 'Rows in 2024' AS check_name, 295 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_date >= '2024-01-01' AND transaction_date <= '2024-12-31') AS postgres_value
UNION ALL
SELECT 29 AS seq, 'D10' AS check_id, '3 Dates' AS area, 'Rows where transaction_hour differs from hour of transaction_time' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE EXTRACT(HOUR FROM transaction_time) <> transaction_hour) AS postgres_value
UNION ALL
SELECT 30 AS seq, 'C01' AS check_id, '4 Categories' AS area, 'Distinct values of account_type' AS check_name, 5 AS python_value, (SELECT COUNT(DISTINCT account_type) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 31 AS seq, 'C02' AS check_id, '4 Categories' AS area, 'Distinct values of transaction_type' AS check_name, 10 AS python_value, (SELECT COUNT(DISTINCT transaction_type) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 32 AS seq, 'C03' AS check_id, '4 Categories' AS area, 'Distinct values of transaction_direction' AS check_name, 2 AS python_value, (SELECT COUNT(DISTINCT transaction_direction) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 33 AS seq, 'C04' AS check_id, '4 Categories' AS area, 'Distinct values of merchant_category' AS check_name, 15 AS python_value, (SELECT COUNT(DISTINCT merchant_category) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 34 AS seq, 'C05' AS check_id, '4 Categories' AS area, 'Distinct values of state' AS check_name, 10 AS python_value, (SELECT COUNT(DISTINCT state) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 35 AS seq, 'C06' AS check_id, '4 Categories' AS area, 'Distinct values of loan_type' AS check_name, 7 AS python_value, (SELECT COUNT(DISTINCT loan_type) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 36 AS seq, 'C07' AS check_id, '4 Categories' AS area, 'Distinct values of transaction_status' AS check_name, 4 AS python_value, (SELECT COUNT(DISTINCT transaction_status) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 37 AS seq, 'C08' AS check_id, '4 Categories' AS area, 'Distinct values of channel' AS check_name, 6 AS python_value, (SELECT COUNT(DISTINCT channel) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 38 AS seq, 'C09' AS check_id, '4 Categories' AS area, 'Distinct values of kyc_status' AS check_name, 3 AS python_value, (SELECT COUNT(DISTINCT kyc_status) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 39 AS seq, 'C10' AS check_id, '4 Categories' AS area, 'transaction_status = Success' AS check_name, 506247 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_status = 'Success') AS postgres_value
UNION ALL
SELECT 40 AS seq, 'C11' AS check_id, '4 Categories' AS area, 'transaction_status = Failed' AS check_name, 21905 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_status = 'Failed') AS postgres_value
UNION ALL
SELECT 41 AS seq, 'C12' AS check_id, '4 Categories' AS area, 'transaction_status = Reversed' AS check_name, 11019 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_status = 'Reversed') AS postgres_value
UNION ALL
SELECT 42 AS seq, 'C13' AS check_id, '4 Categories' AS area, 'transaction_status = Pending' AS check_name, 10829 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_status = 'Pending') AS postgres_value
UNION ALL
SELECT 43 AS seq, 'C14' AS check_id, '4 Categories' AS area, 'is_fraud = 1 (fraud-labelled rows)' AS check_name, 4873 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE is_fraud = 1) AS postgres_value
UNION ALL
SELECT 44 AS seq, 'C15' AS check_id, '4 Categories' AS area, 'has_loan = 1' AS check_name, 192288 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE has_loan = 1) AS postgres_value
UNION ALL
SELECT 45 AS seq, 'C16' AS check_id, '4 Categories' AS area, 'transaction_direction = Debit' AS check_name, 370394 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_direction = 'Debit') AS postgres_value
UNION ALL
SELECT 46 AS seq, 'N01' AS check_id, '5 Numeric ranges' AS area, 'Minimum transaction_amount' AS check_name, 2.40 AS python_value, (SELECT MIN(transaction_amount) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 47 AS seq, 'N02' AS check_id, '5 Numeric ranges' AS area, 'Maximum transaction_amount' AS check_name, 10000000.00 AS python_value, (SELECT MAX(transaction_amount) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 48 AS seq, 'N03' AS check_id, '5 Numeric ranges' AS area, 'Rows with transaction_amount <= 0' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_amount <= 0) AS postgres_value
UNION ALL
SELECT 49 AS seq, 'N04' AS check_id, '5 Numeric ranges' AS area, 'Rows with transaction_amount = 10,000,000.00' AS check_name, 4 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_amount = 10000000) AS postgres_value
UNION ALL
SELECT 50 AS seq, 'N05' AS check_id, '5 Numeric ranges' AS area, 'Minimum account_balance' AS check_name, 500.00 AS python_value, (SELECT MIN(account_balance) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 51 AS seq, 'N06' AS check_id, '5 Numeric ranges' AS area, 'Maximum account_balance' AS check_name, 5000000.00 AS python_value, (SELECT MAX(account_balance) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 52 AS seq, 'N07' AS check_id, '5 Numeric ranges' AS area, 'Rows with account_balance = 500.00' AS check_name, 288 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE account_balance = 500) AS postgres_value
UNION ALL
SELECT 53 AS seq, 'N08' AS check_id, '5 Numeric ranges' AS area, 'Rows with account_balance = 5,000,000.00' AS check_name, 38 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE account_balance = 5000000) AS postgres_value
UNION ALL
SELECT 54 AS seq, 'N09' AS check_id, '5 Numeric ranges' AS area, 'Minimum credit_score' AS check_name, 300 AS python_value, (SELECT MIN(credit_score) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 55 AS seq, 'N10' AS check_id, '5 Numeric ranges' AS area, 'Maximum credit_score' AS check_name, 899 AS python_value, (SELECT MAX(credit_score) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 56 AS seq, 'N11' AS check_id, '5 Numeric ranges' AS area, 'Maximum emi_amount' AS check_name, 153325.74 AS python_value, (SELECT MAX(emi_amount) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 57 AS seq, 'N12' AS check_id, '5 Numeric ranges' AS area, 'Distinct transaction_hour values' AS check_name, 24 AS python_value, (SELECT COUNT(DISTINCT transaction_hour) FROM banking.transactions) AS postgres_value
UNION ALL
SELECT 58 AS seq, 'Q01' AS check_id, '6 Consistency / DQ' AS area, 'DQ-01 has_loan=1 and loan_type=None' AS check_name, 19422 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE has_loan = 1 AND loan_type = 'None') AS postgres_value
UNION ALL
SELECT 59 AS seq, 'Q02' AS check_id, '6 Consistency / DQ' AS area, 'DQ-01 of those, emi_amount > 0' AS check_name, 19422 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE has_loan = 1 AND loan_type = 'None' AND emi_amount > 0) AS postgres_value
UNION ALL
SELECT 60 AS seq, 'Q03' AS check_id, '6 Consistency / DQ' AS area, 'has_loan=0 but loan_type is not None' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE has_loan = 0 AND loan_type <> 'None') AS postgres_value
UNION ALL
SELECT 61 AS seq, 'Q04' AS check_id, '6 Consistency / DQ' AS area, 'has_loan=0 but emi_amount > 0' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE has_loan = 0 AND emi_amount > 0) AS postgres_value
UNION ALL
SELECT 62 AS seq, 'Q05' AS check_id, '6 Consistency / DQ' AS area, 'has_loan=1 but emi_amount = 0' AS check_name, 0 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE has_loan = 1 AND emi_amount = 0) AS postgres_value
UNION ALL
SELECT 63 AS seq, 'Q06' AS check_id, '6 Consistency / DQ' AS area, 'UQ-01 transaction_amount > account_balance' AS check_name, 79494 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE transaction_amount > account_balance) AS postgres_value
UNION ALL
SELECT 64 AS seq, 'Q07' AS check_id, '6 Consistency / DQ' AS area, 'merchant_category = Salary (all rows)' AS check_name, 43937 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE merchant_category = 'Salary') AS postgres_value
UNION ALL
SELECT 65 AS seq, 'Q08' AS check_id, '6 Consistency / DQ' AS area, 'UQ-02 Salary rows that are Debits' AS check_name, 29402 AS python_value, (SELECT COUNT(*) FROM banking.transactions WHERE merchant_category = 'Salary' AND transaction_direction = 'Debit') AS postgres_value
UNION ALL
SELECT 66 AS seq, 'Q09' AS check_id, '6 Consistency / DQ' AS area, 'DQ-02 customer_ids with more than one state' AS check_name, 78998 AS python_value, (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(DISTINCT state) > 1) x) AS postgres_value
UNION ALL
SELECT 67 AS seq, 'Q10' AS check_id, '6 Consistency / DQ' AS area, 'DQ-02 customer_ids with more than one account_type' AS check_name, 77937 AS python_value, (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(DISTINCT account_type) > 1) x) AS postgres_value
UNION ALL
SELECT 68 AS seq, 'Q11' AS check_id, '6 Consistency / DQ' AS area, 'DQ-02 customer_ids with more than one credit_score' AS check_name, 79334 AS python_value, (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(DISTINCT credit_score) > 1) x) AS postgres_value
UNION ALL
SELECT 69 AS seq, 'Q12' AS check_id, '6 Consistency / DQ' AS area, 'DQ-02 customer_ids with more than one kyc_status' AS check_name, 45037 AS python_value, (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(DISTINCT kyc_status) > 1) x) AS postgres_value
UNION ALL
SELECT 70 AS seq, 'Q13' AS check_id, '6 Consistency / DQ' AS area, 'DQ-02 customer_ids with more than one has_loan value' AS check_name, 71922 AS python_value, (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(DISTINCT has_loan) > 1) x) AS postgres_value
UNION ALL
SELECT 71 AS seq, 'Q14' AS check_id, '6 Consistency / DQ' AS area, 'customer_ids with exactly one transaction' AS check_name, 579 AS python_value, (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(*) = 1) x) AS postgres_value
UNION ALL
SELECT 72 AS seq, 'Q15' AS check_id, '6 Consistency / DQ' AS area, 'Maximum transactions for one customer_id' AS check_name, 20 AS python_value, (SELECT MAX(n) FROM (SELECT COUNT(*) AS n FROM banking.transactions GROUP BY customer_id) x) AS postgres_value
) AS checks;


/* ---------------------------------------------------------------------------
   PART 2 - Run the checks
   2a. Full list (72 rows). Export this grid to CSV to compare with Python:
       python python/reconciliation_reference.py --input <csv> --compare <exported file>
   --------------------------------------------------------------------------- */
SELECT check_id, area, check_name, python_value, postgres_value, difference, result
FROM banking.v_reconciliation_checks
ORDER BY seq;


/* 2b. Summary. Expected after a correct load: MATCH = 72, no MISMATCH row. */
SELECT result, COUNT(*) AS checks
FROM banking.v_reconciliation_checks
GROUP BY result
ORDER BY result;


/* ---------------------------------------------------------------------------
   PART 3 - Date boundaries (text comparison)
   --------------------------------------------------------------------------- */
SELECT check_id, check_name, python_value, postgres_value,
       CASE WHEN python_value = postgres_value THEN 'MATCH' ELSE 'MISMATCH' END AS result
FROM (
  SELECT 'D11' AS check_id, 'First transaction_date' AS check_name, '2019-01-01' AS python_value,
         TO_CHAR(MIN(transaction_date), 'YYYY-MM-DD') AS postgres_value
  FROM banking.transactions
  UNION ALL
  SELECT 'D12', 'Last transaction_date', '2024-01-01', TO_CHAR(MAX(transaction_date), 'YYYY-MM-DD')
  FROM banking.transactions
) AS d
ORDER BY check_id;


/* ---------------------------------------------------------------------------
   PART 4a - DQ-01 example rows: has_loan = 1 but loan_type = 'None'
   Business question: what do the borrower rows with no recorded loan type look like?
   Shows the first 10 by transaction_id. Total expected: 19,422 rows (check Q01).
   --------------------------------------------------------------------------- */
SELECT transaction_id, customer_id, transaction_date, account_type, has_loan, loan_type, emi_amount
FROM banking.transactions
WHERE has_loan = 1 AND loan_type = 'None'
ORDER BY transaction_id
LIMIT 10;


/* ---------------------------------------------------------------------------
   PART 4b - Rows at the transaction_amount ceiling
   Business question: which rows sit exactly at the maximum amount (possible capping, DQ-04)?
   Expected: 4 rows at 10,000,000.00 (check N04).
   --------------------------------------------------------------------------- */
SELECT transaction_id, transaction_date, transaction_type, channel, transaction_amount,
       account_balance, transaction_status, is_fraud
FROM banking.transactions
WHERE transaction_amount = (SELECT MAX(transaction_amount) FROM banking.transactions)
ORDER BY transaction_id;


/* ---------------------------------------------------------------------------
   PART 5a - [PG-ONLY] Column names and data types of banking.transactions
   Expected: 20 rows. See 01_schema_and_load.sql for the intended types.
   --------------------------------------------------------------------------- */
-- [PG-ONLY]
SELECT ordinal_position, column_name, data_type, character_maximum_length,
       numeric_precision, numeric_scale, is_nullable
FROM information_schema.columns
WHERE table_schema = 'banking' AND table_name = 'transactions'
ORDER BY ordinal_position;


/* ---------------------------------------------------------------------------
   PART 5b - [PG-ONLY] Constraints defined on banking.transactions
   Expected: a primary key plus the CHECK constraints created in 01_schema_and_load.sql.
   --------------------------------------------------------------------------- */
-- [PG-ONLY]
SELECT conname AS constraint_name, contype AS type, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'banking.transactions'::regclass
ORDER BY contype, conname;


/* ---------------------------------------------------------------------------
   PART 5c - [PG-ONLY] Indexes on banking.transactions
   --------------------------------------------------------------------------- */
-- [PG-ONLY]
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'banking' AND tablename = 'transactions'
ORDER BY indexname;
