/* =============================================================================
   03_exploratory_analysis.sql
   Project : Indian Banking Transactions Analytics & Risk Insights
   Table   : banking.transactions (typed copy built by 01_schema_and_load.sql)

   PURPOSE
     Foundational exploratory queries (E01-E21): shape of the data, volumes, amounts,
     status, channel, type, geography, time patterns, the fraud LABEL and the loan
     inconsistency. Advanced techniques (ranking, LAG/LEAD, running totals, multi-step
     CTEs, correlated subqueries, views) are Day 3 and are deliberately not used here.

   HOW TO RUN (pgAdmin 4 Query Tool): select ONE query (from its comment to its semicolon)
   and press F5. pgAdmin displays only the last result grid of a multi-statement run.
   Queries marked [PG-ONLY] use PERCENTILE_CONT, which is PostgreSQL syntax.

   DEFINITIONS USED THROUGHOUT
     transactions         = rows (COUNT(*)); one row is one transaction record
     distinct customer_id = count of distinct ID values; NOT "unique customers" (finding DQ-02)
     fraud-labelled       = is_fraud = 1, a SUPPLIED LABEL, not confirmed fraud
     fraud label rate     = fraud-labelled rows / all rows IN THE SAME GROUP, as a percentage
     amount               = transaction_amount; currency undocumented (INR assumed)
     Amounts on Failed, Reversed and Pending rows are attempted amounts, not money moved.
     2024 holds a single day (2024-01-01); exclude it from year-over-year comparison.

   STATUS: written and logic-checked outside PostgreSQL (see documentation/data_quality_report.md).
           Python reference results: python python/reconciliation_reference.py --input <csv> --exploratory
   ============================================================================= */


/* E01 - Table overview
   Business question: how big is the dataset and what does it cover?
   Concepts: aggregate functions, COUNT(DISTINCT), TO_CHAR
   Metric: totals over all rows. Expected: 550,000 rows, 550,000 distinct IDs, 79,916 distinct
   customer_id values, 1,827 dates, 2019-01-01 to 2024-01-01, 4,873 fraud-labelled (0.886%). */
SELECT COUNT(*)                                          AS transactions,
       COUNT(DISTINCT transaction_id)                    AS distinct_transaction_ids,
       COUNT(DISTINCT customer_id)                       AS distinct_customer_ids,
       TO_CHAR(MIN(transaction_date), 'YYYY-MM-DD')      AS first_date,
       TO_CHAR(MAX(transaction_date), 'YYYY-MM-DD')      AS last_date,
       COUNT(DISTINCT transaction_date)                  AS distinct_dates,
       SUM(transaction_amount)                           AS total_amount,
       ROUND(AVG(transaction_amount), 2)                 AS avg_amount,
       SUM(is_fraud)                                     AS fraud_labelled,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3)        AS fraud_label_rate_pct
FROM banking.transactions;


/* E02 - Volume, amount and fraud-label rate by calendar year
   Business question: is activity stable across years, and is 2024 comparable?
   Concepts: GROUP BY on a derived value, conditional rate, coverage column
   Metric: rate = fraud-labelled / transactions in that year. 2024 has days_covered = 1. */
SELECT TO_CHAR(transaction_date, 'YYYY')                 AS calendar_year,
       COUNT(*)                                          AS transactions,
       SUM(transaction_amount)                           AS total_amount,
       SUM(is_fraud)                                     AS fraud_labelled,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3)        AS fraud_rate_pct,
       COUNT(DISTINCT transaction_date)                  AS days_covered
FROM banking.transactions
GROUP BY TO_CHAR(transaction_date, 'YYYY')
ORDER BY calendar_year;


/* E03 - Transaction status distribution
   Business question: what share of transactions succeed, fail, reverse or stay pending?
   Concepts: GROUP BY, window aggregate over grouped counts for the denominator
   Metric: pct = status rows / all 550,000 rows. Expected: Success 92.04, Failed 3.98,
   Reversed 2.00, Pending 1.97. */
SELECT transaction_status,
       COUNT(*)                                          AS transactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_transactions,
       SUM(transaction_amount)                           AS attempted_amount
FROM banking.transactions
GROUP BY transaction_status
ORDER BY transactions DESC;


/* E04 - Channel summary
   Business question: which channels carry the most transactions and value, and how do
   failure and fraud-label rates compare?
   Concepts: GROUP BY, conditional aggregation (CASE inside SUM), window denominator
   Metric: pct = channel rows / all rows; failed_pct and fraud_rate_pct use the channel's own rows. */
SELECT channel,
       COUNT(*)                                          AS transactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_transactions,
       SUM(transaction_amount)                           AS total_amount,
       ROUND(AVG(transaction_amount), 2)                 AS avg_amount,
       SUM(is_fraud)                                     AS fraud_labelled,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3)        AS fraud_rate_pct,
       ROUND(100.0 * SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failed_pct
FROM banking.transactions
GROUP BY channel
ORDER BY transactions DESC;


/* E05 - Transaction type summary
   Business question: same as E04 by payment method (UPI, IMPS, NEFT, RTGS ...).
   Concepts: GROUP BY, conditional aggregation, window denominator
   Note: RTGS shows the highest label rate (about 1.85%). Counts are shown so the rate is
   read with its denominator; no significance test has been run. */
SELECT transaction_type,
       COUNT(*)                                          AS transactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_transactions,
       SUM(transaction_amount)                           AS total_amount,
       ROUND(AVG(transaction_amount), 2)                 AS avg_amount,
       SUM(is_fraud)                                     AS fraud_labelled,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3)        AS fraud_rate_pct,
       ROUND(100.0 * SUM(CASE WHEN transaction_status = 'Failed' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failed_pct
FROM banking.transactions
GROUP BY transaction_type
ORDER BY transactions DESC;


/* E06 - Merchant category summary
   Business question: where is activity concentrated by category?
   Concepts: GROUP BY, window denominator
   Caveat: 'Salary' rows are two-thirds Debits (open question UQ-02), so category labels
   should not be read as real-world merchant types. */
SELECT merchant_category,
       COUNT(*)                                          AS transactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_transactions,
       SUM(transaction_amount)                           AS total_amount,
       ROUND(AVG(transaction_amount), 2)                 AS avg_amount
FROM banking.transactions
GROUP BY merchant_category
ORDER BY transactions DESC;


/* E07 - State summary
   Business question: how is activity and the fraud label spread across the 10 states?
   Concepts: GROUP BY, window denominator
   Caveat: what state represents (customer home or transaction location) is undocumented. */
SELECT state,
       COUNT(*)                                          AS transactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_transactions,
       SUM(transaction_amount)                           AS total_amount,
       SUM(is_fraud)                                     AS fraud_labelled,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3)        AS fraud_rate_pct
FROM banking.transactions
GROUP BY state
ORDER BY transactions DESC;


/* E08 - Account type by direction
   Business question: how do debits and credits split within each account type?
   Concepts: conditional aggregation (pivot with CASE)
   Metric: debit_share_pct = debit rows / all rows of that account type. */
SELECT account_type,
       COUNT(*)                                          AS transactions,
       SUM(CASE WHEN transaction_direction = 'Debit'  THEN 1 ELSE 0 END)                      AS debit_transactions,
       SUM(CASE WHEN transaction_direction = 'Credit' THEN 1 ELSE 0 END)                      AS credit_transactions,
       SUM(CASE WHEN transaction_direction = 'Debit'  THEN transaction_amount ELSE 0 END)     AS debit_amount,
       SUM(CASE WHEN transaction_direction = 'Credit' THEN transaction_amount ELSE 0 END)     AS credit_amount,
       ROUND(100.0 * SUM(CASE WHEN transaction_direction = 'Debit' THEN 1 ELSE 0 END) / COUNT(*), 2) AS debit_share_pct
FROM banking.transactions
GROUP BY account_type
ORDER BY transactions DESC;


/* E09 - Amount bands (PROVISIONAL band edges)
   Business question: how are transaction amounts distributed, and does the label rate change by size?
   Concepts: CASE WHEN banding, GROUP BY on the band, window denominator
   Metric: pct = band rows / all rows; fraud_rate_pct = labelled rows / rows in the band.
   Band edges are provisional (lower edge inclusive) and may change after review on Day 3. */
SELECT amount_band,
       COUNT(*)                                          AS transactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_transactions,
       SUM(is_fraud)                                     AS fraud_labelled,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3)        AS fraud_rate_pct
FROM (
    SELECT is_fraud,
           CASE WHEN transaction_amount <      500 THEN '1 under 500'
                WHEN transaction_amount <     1000 THEN '2 500-999.99'
                WHEN transaction_amount <     5000 THEN '3 1,000-4,999.99'
                WHEN transaction_amount <    25000 THEN '4 5,000-24,999.99'
                WHEN transaction_amount <   100000 THEN '5 25,000-99,999.99'
                WHEN transaction_amount <  1000000 THEN '6 100,000-999,999.99'
                ELSE                                    '7 1,000,000 and over'
           END AS amount_band
    FROM banking.transactions
) AS banded
GROUP BY amount_band
ORDER BY amount_band;


/* E10 - [PG-ONLY] Amount percentiles
   Business question: because amounts are very skewed, what do the median and tail look like?
   Concepts: PERCENTILE_CONT (ordered-set aggregate)
   Metric: continuous percentile of transaction_amount over all rows.
   Expected median about 2,035.74 against a mean of 29,907.09 (the mean is pulled up by a few large values). */
-- [PG-ONLY]
SELECT ROUND(CAST(PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p01,
       ROUND(CAST(PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p05,
       ROUND(CAST(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p25,
       ROUND(CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS median,
       ROUND(CAST(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p75,
       ROUND(CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p95,
       ROUND(CAST(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p99,
       ROUND(AVG(transaction_amount), 2)                                                           AS mean
FROM banking.transactions;


/* E11 - [PG-ONLY] Amount of fraud-labelled vs other transactions
   Business question: do labelled rows differ in size from the rest, by mean and by median?
   Concepts: GROUP BY, PERCENTILE_CONT
   Expected (Day 1): mean 119,446.21 vs 29,106.69, but medians 2,691.95 vs 2,030.99. The mean gap
   is driven by a few large values. These are amounts on LABELLED rows, not confirmed losses. */
-- [PG-ONLY]
SELECT is_fraud,
       COUNT(*)                                          AS transactions,
       ROUND(AVG(transaction_amount), 2)                 AS mean_amount,
       ROUND(CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS median_amount
FROM banking.transactions
GROUP BY is_fraud
ORDER BY is_fraud;


/* E12 - Fraud-label rate by merchant category with a minimum sample size
   Business question: do any categories have a label rate clearly different from the overall rate?
   Concepts: HAVING with a minimum sample threshold, scalar subquery for the overall rate
   Metric: rate = labelled / rows in the category. Groups under 1,000 rows are not reported. */
SELECT merchant_category,
       COUNT(*)                                          AS transactions,
       SUM(is_fraud)                                     AS fraud_labelled,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3)        AS fraud_rate_pct,
       ROUND(100.0 * (SELECT SUM(is_fraud) FROM banking.transactions)
                   / (SELECT COUNT(*) FROM banking.transactions), 3) AS overall_rate_pct
FROM banking.transactions
GROUP BY merchant_category
HAVING COUNT(*) >= 1000
ORDER BY fraud_rate_pct DESC;


/* E13 - Transactions by hour of day
   Business question: is there a daily rhythm in volume or in the label rate?
   Concepts: GROUP BY, window denominator
   Metric: pct = hour rows / all rows. Volumes are close to uniform (about 4.2% per hour). */
SELECT transaction_hour,
       COUNT(*)                                          AS transactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_transactions,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 3)        AS fraud_rate_pct
FROM banking.transactions
GROUP BY transaction_hour
ORDER BY transaction_hour;


/* E14 - Monthly volume, 2019-01 to 2023-12
   Business question: how does volume move month to month (complete years only)?
   Concepts: date-based aggregation with TO_CHAR, date filter
   Metric: transactions and total attempted amount per month. 2024 excluded (one day only). */
SELECT TO_CHAR(transaction_date, 'YYYY-MM')              AS year_month,
       COUNT(*)                                          AS transactions,
       SUM(transaction_amount)                           AS total_amount
FROM banking.transactions
WHERE transaction_date < '2024-01-01'
GROUP BY TO_CHAR(transaction_date, 'YYYY-MM')
ORDER BY year_month;


/* E15 - Loan investigation (DQ-01): has_loan = 1 but loan_type = 'None', by year
   Business question: is the missing loan type a one-off or present throughout?
   Concepts: conditional aggregation, percentage of a conditional denominator
   Metric: pct = exception rows / rows with has_loan = 1 in that year. Expected about 10.1% in every year. */
SELECT TO_CHAR(transaction_date, 'YYYY')                 AS calendar_year,
       SUM(CASE WHEN has_loan = 1 THEN 1 ELSE 0 END)     AS borrower_rows,
       SUM(CASE WHEN has_loan = 1 AND loan_type = 'None' THEN 1 ELSE 0 END) AS type_not_recorded,
       ROUND(100.0 * SUM(CASE WHEN has_loan = 1 AND loan_type = 'None' THEN 1 ELSE 0 END)
                   / SUM(CASE WHEN has_loan = 1 THEN 1 ELSE 0 END), 2)      AS pct_of_borrower_rows
FROM banking.transactions
GROUP BY TO_CHAR(transaction_date, 'YYYY')
ORDER BY calendar_year;


/* E16 - Loan type cross-check (has_loan flag by loan_type, with EMI)
   Business question: does each loan type line up with the has_loan flag and an EMI amount?
   Concepts: conditional aggregation, AVG over a CASE (ignores non-matching rows)
   Expected: 'None' appears under both has_loan = 0 (357,712) and has_loan = 1 (19,422); all
   named loan types appear only under has_loan = 1. */
SELECT loan_type,
       COUNT(*)                                          AS transactions,
       SUM(CASE WHEN has_loan = 1 THEN 1 ELSE 0 END)     AS has_loan_1,
       SUM(CASE WHEN has_loan = 0 THEN 1 ELSE 0 END)     AS has_loan_0,
       ROUND(AVG(CASE WHEN emi_amount > 0 THEN emi_amount END), 2) AS avg_emi_where_positive
FROM banking.transactions
GROUP BY loan_type
ORDER BY transactions DESC;


/* E17 - KYC status against transaction status
   Business question: does the outcome of a transaction differ by KYC status?
   Concepts: conditional aggregation as percentages of the group
   Metric: each pct = rows with that status / rows with that KYC status. Expected to be nearly identical
   across KYC groups (about 92% Success). */
SELECT kyc_status,
       COUNT(*)                                          AS transactions,
       ROUND(100.0 * SUM(CASE WHEN transaction_status = 'Success'  THEN 1 ELSE 0 END) / COUNT(*), 2) AS success_pct,
       ROUND(100.0 * SUM(CASE WHEN transaction_status = 'Failed'   THEN 1 ELSE 0 END) / COUNT(*), 2) AS failed_pct,
       ROUND(100.0 * SUM(CASE WHEN transaction_status = 'Reversed' THEN 1 ELSE 0 END) / COUNT(*), 2) AS reversed_pct,
       ROUND(100.0 * SUM(CASE WHEN transaction_status = 'Pending'  THEN 1 ELSE 0 END) / COUNT(*), 2) AS pending_pct
FROM banking.transactions
GROUP BY kyc_status
ORDER BY transactions DESC;


/* E18 - How many transactions does each customer_id have?
   Business question: how is activity spread across customer_id values?
   Concepts: CTE, aggregate of an aggregate
   Metric: number of distinct customer_id values at each transaction count. Expected range 1 to 20;
   579 IDs appear once. Reminder: customer_id is not a stable customer profile (DQ-02). */
WITH per_customer AS (
    SELECT customer_id, COUNT(*) AS n
    FROM banking.transactions
    GROUP BY customer_id
)
SELECT n AS transactions_per_customer_id,
       COUNT(*) AS customer_ids
FROM per_customer
GROUP BY n
ORDER BY n;


/* E19 - Ten largest transactions
   Business question: what do the extreme transactions look like (status, label, channel)?
   Concepts: ORDER BY with a tie-breaker, LIMIT
   Note: four rows share the maximum 10,000,000.00 (possible ceiling, DQ-04), so transaction_id breaks ties. */
SELECT transaction_id, transaction_date, transaction_type, channel, transaction_direction,
       transaction_amount, account_balance, transaction_status, is_fraud
FROM banking.transactions
ORDER BY transaction_amount DESC, transaction_id
LIMIT 10;


/* E20 - Amount larger than account balance, by direction
   Business question: how common is transaction_amount above account_balance (open question UQ-01)?
   Concepts: conditional aggregation
   Metric: pct = rows with amount > balance / all rows of that direction. Expected 79,494 rows overall (14.45%).
   Interpretation depends on whether account_balance is before or after the transaction (undocumented). */
SELECT transaction_direction,
       COUNT(*)                                          AS transactions,
       SUM(CASE WHEN transaction_amount > account_balance THEN 1 ELSE 0 END) AS amount_exceeds_balance,
       ROUND(100.0 * SUM(CASE WHEN transaction_amount > account_balance THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_of_direction
FROM banking.transactions
GROUP BY transaction_direction
ORDER BY transaction_direction;


/* E21 - Transactions by day of week
   Business question: is activity different on weekends?
   Concepts: EXTRACT(DOW ...) in a subquery, CASE for readable names
   Note: PostgreSQL DOW numbers Sunday as 0. Volumes are expected to be close to uniform. */
SELECT dow_number,
       CASE dow_number WHEN 0 THEN 'Sunday'    WHEN 1 THEN 'Monday'   WHEN 2 THEN 'Tuesday'
                       WHEN 3 THEN 'Wednesday' WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'
                       ELSE 'Saturday' END               AS day_name,
       COUNT(*)                                          AS transactions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_transactions
FROM (
    SELECT EXTRACT(DOW FROM transaction_date) AS dow_number
    FROM banking.transactions
) AS d
GROUP BY dow_number
ORDER BY dow_number;
