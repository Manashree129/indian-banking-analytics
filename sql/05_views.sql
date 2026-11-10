/* =============================================================================
   05_views.sql
   Project : Indian Banking Transactions Analytics & Risk Insights
   Source  : banking.transactions  (typed table built by 01_schema_and_load.sql)

   PURPOSE
     Six reusable, read-only views for Excel and Power BI. They add no data: each is a
     query over banking.transactions. Nothing here modifies, drops or reloads any table, schema
     or existing object. Views are created with CREATE OR REPLACE VIEW, so the script can be re-run.

   HOW TO RUN (pgAdmin 4, PostgreSQL 18)
     Run the whole file once (Query Tool > open file > F5), or run each CREATE OR REPLACE VIEW
     statement on its own. The only order dependency: v_fraud_label_summary reads
     v_transactions_enriched, so create that one first (it is first in this file).
     Then check each view with: SELECT * FROM banking.<view_name> LIMIT 20;

   IMPORTANT NOTES
     * A view that depends on banking.transactions blocks DROP TABLE banking.transactions. The
       reload section of 01_schema_and_load.sql (SECTION B) drops that table, so run the
       commented DROP VIEW block at the bottom of this file before re-running SECTION B, then re-run
       this file afterwards. Nothing in this file runs that block automatically.
     * CREATE OR REPLACE VIEW cannot change a view's existing columns. To change a view's columns,
       DROP VIEW it first (see the bottom block).
     * Definitions follow the project conventions: fraud-labelled = is_fraud = 1 (a supplied label, not
       confirmed fraud); currency undocumented; account_balance has no reliable definition; customer_id
       is not a stable customer; 2024 holds a single day; minimum sample size 1,000 rows for rates.

   STATUS: written and logic-checked in SQLite (python/sqlite_logic_check.py). NOT yet executed on
   PostgreSQL. See documentation/sql_query_catalogue.md for each view's documentation.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   VIEW 1 - banking.v_transactions_enriched
   Purpose   : the typed table plus derived fields the project planned (data dictionary): a
               timestamp, month and year, provisional amount band, loan-flag group, and two
               neutral flags. Main fact table for Power BI.
   Grain     : one row per transaction (550,000 rows).
   Key cols  : transaction_ts, month_start, calendar_year, amount_band, loan_group,
               is_stub_period, amount_exceeds_balance_flag (+ all 20 source columns).
   Used for  : Power BI data model, Excel PivotTables, ad hoc slicing.
   Limits    : amount_band edges are provisional. amount_exceeds_balance_flag only compares two
               columns; it is NOT an overdraft indicator (balance definition unknown).
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW banking.v_transactions_enriched AS
SELECT t.transaction_id,
       t.customer_id,
       t.transaction_date,
       t.transaction_time,
       (t.transaction_date + t.transaction_time)                          AS transaction_ts,
       CAST(DATE_TRUNC('month', t.transaction_date) AS DATE)              AS month_start,
       CAST(EXTRACT(YEAR FROM t.transaction_date) AS INTEGER)             AS calendar_year,
       t.account_type,
       t.transaction_type,
       t.transaction_amount,
       t.transaction_direction,
       t.account_balance,
       t.merchant_category,
       t.state,
       t.credit_score,
       t.has_loan,
       t.loan_type,
       t.emi_amount,
       t.transaction_status,
       t.channel,
       t.kyc_status,
       t.is_fraud,
       t.transaction_hour,
       CASE WHEN t.transaction_amount <      500 THEN '1 under 500'
            WHEN t.transaction_amount <     1000 THEN '2 500-999.99'
            WHEN t.transaction_amount <     5000 THEN '3 1,000-4,999.99'
            WHEN t.transaction_amount <    25000 THEN '4 5,000-24,999.99'
            WHEN t.transaction_amount <   100000 THEN '5 25,000-99,999.99'
            WHEN t.transaction_amount <  1000000 THEN '6 100,000-999,999.99'
            ELSE                                      '7 1,000,000 and over'
       END                                                                AS amount_band,
       CASE WHEN t.has_loan = 0                          THEN 'No loan'
            WHEN t.has_loan = 1 AND t.loan_type = 'None' THEN 'Loan flag set, loan type not recorded'
            ELSE                                              'Loan flag set, named loan type'
       END                                                                AS loan_group,
       CASE WHEN t.transaction_date >= '2024-01-01' THEN 1 ELSE 0 END     AS is_stub_period,
       CASE WHEN t.transaction_amount > t.account_balance THEN 1 ELSE 0 END AS amount_exceeds_balance_flag
FROM banking.transactions t;


/* -----------------------------------------------------------------------------
   VIEW 2 - banking.v_monthly_summary
   Purpose   : monthly activity, status mix and fraud-label rate in one table.
   Grain     : one row per calendar month (61 rows: 2019-01 to 2024-01).
   Key cols  : month_start, days_covered, days_in_month, is_complete_month, transactions,
               total_amount (attempted), success/failed/reversed/pending counts and %,
               fraud_labelled, fraud_label_rate_pct.
   Used for  : Power BI trend page, Excel monthly pivot, executive KPIs.
   Limits    : 2024-01 is a one-day month (is_complete_month = 0); exclude it from trends. Amounts are
               attempted amounts in an undocumented currency.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW banking.v_monthly_summary AS
SELECT x.month_start,
       x.calendar_year,
       x.month_number,
       x.days_covered,
       x.days_in_month,
       CASE WHEN x.days_covered = x.days_in_month THEN 1 ELSE 0 END AS is_complete_month,
       x.transactions,
       x.total_amount,
       ROUND(x.total_amount / NULLIF(x.transactions, 0), 2)         AS avg_amount,
       x.success_transactions,
       x.failed_transactions,
       x.reversed_transactions,
       x.pending_transactions,
       ROUND(100.0 * x.success_transactions  / NULLIF(x.transactions, 0), 2) AS success_pct,
       ROUND(100.0 * x.failed_transactions   / NULLIF(x.transactions, 0), 2) AS failed_pct,
       ROUND(100.0 * x.reversed_transactions / NULLIF(x.transactions, 0), 2) AS reversed_pct,
       ROUND(100.0 * x.pending_transactions  / NULLIF(x.transactions, 0), 2) AS pending_pct,
       x.fraud_labelled,
       ROUND(100.0 * x.fraud_labelled / NULLIF(x.transactions, 0), 3)        AS fraud_label_rate_pct
FROM (
    SELECT m.*,
           CAST(EXTRACT(DAY FROM (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')) AS INTEGER) AS days_in_month
    FROM (
        SELECT CAST(DATE_TRUNC('month', transaction_date) AS DATE)          AS month_start,
               CAST(EXTRACT(YEAR  FROM transaction_date) AS INTEGER)        AS calendar_year,
               CAST(EXTRACT(MONTH FROM transaction_date) AS INTEGER)        AS month_number,
               COUNT(DISTINCT transaction_date)                             AS days_covered,
               COUNT(*)                                                     AS transactions,
               SUM(transaction_amount)                                      AS total_amount,
               SUM(CASE WHEN transaction_status = 'Success'  THEN 1 ELSE 0 END) AS success_transactions,
               SUM(CASE WHEN transaction_status = 'Failed'   THEN 1 ELSE 0 END) AS failed_transactions,
               SUM(CASE WHEN transaction_status = 'Reversed' THEN 1 ELSE 0 END) AS reversed_transactions,
               SUM(CASE WHEN transaction_status = 'Pending'  THEN 1 ELSE 0 END) AS pending_transactions,
               SUM(is_fraud)                                                AS fraud_labelled
        FROM banking.transactions
        GROUP BY CAST(DATE_TRUNC('month', transaction_date) AS DATE),
                 CAST(EXTRACT(YEAR  FROM transaction_date) AS INTEGER),
                 CAST(EXTRACT(MONTH FROM transaction_date) AS INTEGER)
    ) m
) x;


/* -----------------------------------------------------------------------------
   VIEW 3 - banking.v_status_summary
   Purpose   : transaction-status distribution by year (Success, Failed, Reversed, Pending).
   Grain     : one row per calendar year x transaction_status (24 rows).
   Key cols  : calendar_year, days_covered, is_complete_year, transaction_status, transactions,
               pct_of_year, attempted_amount, avg_amount, fraud_labelled, fraud_label_rate_pct.
   Used for  : the Transaction Status and Data Quality dashboard page, status KPIs.
   Limits    : 2024 is a one-day year (is_complete_year = 0). Amounts on Failed, Reversed and
               Pending rows are attempted, not completed.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW banking.v_status_summary AS
SELECT s.calendar_year,
       d.days_covered,
       CASE WHEN d.days_covered >= 365 THEN 1 ELSE 0 END                  AS is_complete_year,
       s.transaction_status,
       s.transactions,
       ROUND(100.0 * s.transactions / NULLIF(SUM(s.transactions) OVER (PARTITION BY s.calendar_year), 0), 2) AS pct_of_year,
       s.attempted_amount,
       ROUND(s.attempted_amount / NULLIF(s.transactions, 0), 2)           AS avg_amount,
       s.fraud_labelled,
       ROUND(100.0 * s.fraud_labelled / NULLIF(s.transactions, 0), 3)     AS fraud_label_rate_pct
FROM (
    SELECT CAST(EXTRACT(YEAR FROM transaction_date) AS INTEGER) AS calendar_year,
           transaction_status,
           COUNT(*)                                               AS transactions,
           SUM(transaction_amount)                                AS attempted_amount,
           SUM(is_fraud)                                          AS fraud_labelled
    FROM banking.transactions
    GROUP BY CAST(EXTRACT(YEAR FROM transaction_date) AS INTEGER), transaction_status
) s
JOIN (
    SELECT CAST(EXTRACT(YEAR FROM transaction_date) AS INTEGER) AS calendar_year,
           COUNT(DISTINCT transaction_date)                       AS days_covered
    FROM banking.transactions
    GROUP BY CAST(EXTRACT(YEAR FROM transaction_date) AS INTEGER)
) d ON d.calendar_year = s.calendar_year;


/* -----------------------------------------------------------------------------
   VIEW 4 - banking.v_channel_type_summary
   Purpose   : channel x transaction-type comparison of volume, value, failure and label rates.
   Grain     : one row per channel x transaction_type (60 rows).
   Key cols  : channel, transaction_type, transactions, pct_of_all, total_amount, avg_amount,
               failed_transactions, reversed_transactions, failed_or_reversed_pct, fraud_labelled,
               fraud_label_rate_pct, meets_min_sample (1 when transactions >= 500).
   Used for  : the Transaction Activity page (channel and type comparisons), Excel pivots.
   Limits    : filter on meets_min_sample = 1 before reading rates. Type and channel look unrelated in
               this file (every type appears in every channel), so combinations may not reflect real
               payment behaviour.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW banking.v_channel_type_summary AS
SELECT c.channel,
       c.transaction_type,
       c.transactions,
       ROUND(100.0 * c.transactions / NULLIF(SUM(c.transactions) OVER (), 0), 2) AS pct_of_all,
       c.total_amount,
       ROUND(c.total_amount / NULLIF(c.transactions, 0), 2)                      AS avg_amount,
       c.failed_transactions,
       c.reversed_transactions,
       ROUND(100.0 * (c.failed_transactions + c.reversed_transactions) / NULLIF(c.transactions, 0), 2) AS failed_or_reversed_pct,
       c.fraud_labelled,
       ROUND(100.0 * c.fraud_labelled / NULLIF(c.transactions, 0), 3)            AS fraud_label_rate_pct,
       CASE WHEN c.transactions >= 500 THEN 1 ELSE 0 END                         AS meets_min_sample
FROM (
    SELECT channel, transaction_type,
           COUNT(*)                                                         AS transactions,
           SUM(transaction_amount)                                          AS total_amount,
           SUM(CASE WHEN transaction_status = 'Failed'   THEN 1 ELSE 0 END) AS failed_transactions,
           SUM(CASE WHEN transaction_status = 'Reversed' THEN 1 ELSE 0 END) AS reversed_transactions,
           SUM(is_fraud)                                                    AS fraud_labelled
    FROM banking.transactions
    GROUP BY channel, transaction_type
) c;


/* -----------------------------------------------------------------------------
   VIEW 5 - banking.v_fraud_label_summary
   Purpose   : the fraud-label rate for every value of seven dimensions, with counts, the
               overall rate, a ratio to overall and a 95% Wilson interval.
   Grain     : one row per dimension x dimension_value (channel 6, transaction_type 10, state 10,
               merchant_category 15, account_type 5, kyc_status 3, amount_band 7 = 56 rows).
   Key cols  : dimension, dimension_value, transactions, fraud_labelled, fraud_label_rate_pct,
               overall_rate_pct, rate_ratio_to_overall, ci_low_pct, ci_high_pct, meets_min_sample
               (1 when transactions >= 1,000), signal.
   Used for  : the Fraud-Label Analysis dashboard page (one long table drives all the bar charts).
   Limits    : is_fraud is a supplied label, not confirmed fraud. The dimensions are analysed one at a
               time, so the amount_band effect is not removed from the others (see query A09 in
               04_advanced_analytical_queries.sql for the stratified view). Differences are descriptive.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW banking.v_fraud_label_summary AS
WITH grouped AS (
    SELECT 'channel' AS dimension, channel AS dimension_value, COUNT(*) AS transactions, SUM(is_fraud) AS fraud_labelled
    FROM banking.transactions GROUP BY channel
    UNION ALL
    SELECT 'transaction_type', transaction_type, COUNT(*), SUM(is_fraud)
    FROM banking.transactions GROUP BY transaction_type
    UNION ALL
    SELECT 'state', state, COUNT(*), SUM(is_fraud)
    FROM banking.transactions GROUP BY state
    UNION ALL
    SELECT 'merchant_category', merchant_category, COUNT(*), SUM(is_fraud)
    FROM banking.transactions GROUP BY merchant_category
    UNION ALL
    SELECT 'account_type', account_type, COUNT(*), SUM(is_fraud)
    FROM banking.transactions GROUP BY account_type
    UNION ALL
    SELECT 'kyc_status', kyc_status, COUNT(*), SUM(is_fraud)
    FROM banking.transactions GROUP BY kyc_status
    UNION ALL
    SELECT 'amount_band', amount_band, COUNT(*), SUM(is_fraud)
    FROM banking.v_transactions_enriched GROUP BY amount_band
),
overall AS (
    SELECT 1.0 * SUM(is_fraud) / NULLIF(COUNT(*), 0) AS overall_p
    FROM banking.transactions
),
rates AS (
    SELECT g.dimension, g.dimension_value, g.transactions AS n, g.fraud_labelled,
           1.0 * g.fraud_labelled / NULLIF(g.transactions, 0) AS p,
           o.overall_p
    FROM grouped g
    CROSS JOIN overall o
),
ci AS (
    SELECT r.*,
           ((p + 3.8416 / (2.0 * n) - 1.96 * SQRT(p * (1 - p) / n + 3.8416 / (4.0 * n * n))) / (1 + 3.8416 / n))  AS ci_low,
           ((p + 3.8416 / (2.0 * n) + 1.96 * SQRT(p * (1 - p) / n + 3.8416 / (4.0 * n * n))) / (1 + 3.8416 / n)) AS ci_high
    FROM rates r
)
SELECT dimension,
       dimension_value,
       n AS transactions,
       fraud_labelled,
       ROUND(100.0 * p, 3)                      AS fraud_label_rate_pct,
       ROUND(100.0 * overall_p, 3)              AS overall_rate_pct,
       ROUND(p / NULLIF(overall_p, 0), 2)       AS rate_ratio_to_overall,
       ROUND(100.0 * ci_low, 3)                 AS ci_low_pct,
       ROUND(100.0 * ci_high, 3)                AS ci_high_pct,
       CASE WHEN n >= 1000 THEN 1 ELSE 0 END    AS meets_min_sample,
       CASE WHEN ci_low  > overall_p THEN 'above overall (interval excludes overall)'
            WHEN ci_high < overall_p THEN 'below overall (interval excludes overall)'
            ELSE 'consistent with overall' END  AS signal
FROM ci;


/* -----------------------------------------------------------------------------
   VIEW 6 - banking.v_data_quality_exceptions
   Purpose   : one-table register of the documented data-quality findings and open questions, each
               with its count and share, for the Data Quality dashboard page.
   Grain     : one row per documented exception (9 rows).
   Key cols  : display_order, exception_id (matches documentation/data_quality_report.md), status
               ('Confirmed pattern' or 'Open question'), description, unit ('rows' or 'customer_ids'),
               affected, population, affected_pct, handling.
   Used for  : the Transaction Status and Data Quality page; interview evidence for data-quality decisions.
   Limits    : the rules are fixed to the findings of the Day 1-3 review. It does not discover new issues
               and it does not clean anything; all rows are kept. 'Open question' rows are not proven errors.
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW banking.v_data_quality_exceptions AS
SELECT e.seq AS display_order,
       e.exception_id,
       e.status,
       e.description,
       e.unit,
       e.affected,
       e.population,
       ROUND(100.0 * e.affected / NULLIF(e.population, 0), 2) AS affected_pct,
       e.handling
FROM (
    SELECT 1 AS seq, 'DQ-01' AS exception_id, 'Confirmed pattern' AS status,
           'has_loan = 1 but loan_type = None' AS description, 'rows' AS unit,
           (SELECT COUNT(*) FROM banking.transactions WHERE has_loan = 1 AND loan_type = 'None') AS affected,
           (SELECT COUNT(*) FROM banking.transactions) AS population,
           'Kept unchanged, reported as its own loan group' AS handling
    UNION ALL
    SELECT 2, 'DQ-02a', 'Confirmed pattern',
           'customer_id has more than one state across its rows', 'customer_ids',
           (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(DISTINCT state) > 1) a),
           (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(*) >= 2) b),
           'No customer-level conclusions drawn'
    UNION ALL
    SELECT 3, 'DQ-02b', 'Confirmed pattern',
           'customer_id has more than one credit_score across its rows', 'customer_ids',
           (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(DISTINCT credit_score) > 1) a),
           (SELECT COUNT(*) FROM (SELECT customer_id FROM banking.transactions GROUP BY customer_id HAVING COUNT(*) >= 2) b),
           'No customer-level conclusions drawn'
    UNION ALL
    SELECT 4, 'DQ-03', 'Confirmed pattern',
           'Rows in the one-day final year (2024-01-01)', 'rows',
           (SELECT COUNT(*) FROM banking.transactions WHERE transaction_date >= '2024-01-01'),
           (SELECT COUNT(*) FROM banking.transactions),
           'Excluded from year-over-year comparisons'
    UNION ALL
    SELECT 5, 'DQ-04a', 'Confirmed pattern',
           'transaction_amount equal to the file maximum (possible ceiling)', 'rows',
           (SELECT COUNT(*) FROM banking.transactions WHERE transaction_amount = (SELECT MAX(transaction_amount) FROM banking.transactions)),
           (SELECT COUNT(*) FROM banking.transactions),
           'Kept, medians and percentiles reported beside means'
    UNION ALL
    SELECT 6, 'DQ-04b', 'Confirmed pattern',
           'account_balance equal to the file maximum (possible ceiling)', 'rows',
           (SELECT COUNT(*) FROM banking.transactions WHERE account_balance = (SELECT MAX(account_balance) FROM banking.transactions)),
           (SELECT COUNT(*) FROM banking.transactions),
           'Kept, balance not used for metrics'
    UNION ALL
    SELECT 7, 'DQ-04c', 'Confirmed pattern',
           'account_balance equal to the file minimum (possible floor)', 'rows',
           (SELECT COUNT(*) FROM banking.transactions WHERE account_balance = (SELECT MIN(account_balance) FROM banking.transactions)),
           (SELECT COUNT(*) FROM banking.transactions),
           'Kept, balance not used for metrics'
    UNION ALL
    SELECT 8, 'UQ-01', 'Open question',
           'transaction_amount larger than account_balance (balance meaning undocumented)', 'rows',
           (SELECT COUNT(*) FROM banking.transactions WHERE transaction_amount > account_balance),
           (SELECT COUNT(*) FROM banking.transactions),
           'Not interpreted as overdraft, balance not used for metrics'
    UNION ALL
    SELECT 9, 'UQ-02', 'Open question',
           'Salary-category rows that are Debits', 'rows',
           (SELECT COUNT(*) FROM banking.transactions WHERE merchant_category = 'Salary' AND transaction_direction = 'Debit'),
           (SELECT COUNT(*) FROM banking.transactions WHERE merchant_category = 'Salary'),
           'Direction analysis by category treated with caution'
) e;


/* =============================================================================
   OPTIONAL TEARDOWN (commented out; NOT run by this script)
   Run these lines yourself, one statement at a time, only if you need to re-run
   SECTION B of 01_schema_and_load.sql (which drops banking.transactions), or to
   change the columns of a view. They remove only the views, never any data.
   ============================================================================= */
-- DROP VIEW IF EXISTS banking.v_fraud_label_summary;
-- DROP VIEW IF EXISTS banking.v_data_quality_exceptions;
-- DROP VIEW IF EXISTS banking.v_channel_type_summary;
-- DROP VIEW IF EXISTS banking.v_status_summary;
-- DROP VIEW IF EXISTS banking.v_monthly_summary;
-- DROP VIEW IF EXISTS banking.v_transactions_enriched;
