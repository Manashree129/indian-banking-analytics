/* =============================================================================
   04_advanced_analytical_queries.sql
   Project : Indian Banking Transactions Analytics & Risk Insights
   Table   : banking.transactions  (typed table built by 01_schema_and_load.sql)
   Queries : A01 - A22  (22 additional queries; E01-E21 in 03_exploratory_analysis.sql are NOT counted)

   HOW TO RUN (pgAdmin 4, PostgreSQL 18)
     1. 01_schema_and_load.sql and 02_data_quality_checks.sql must already have been run
        (banking.transactions must hold 550,000 rows). This file creates nothing and changes nothing.
     2. Every query is self-contained (own CTEs, no temporary tables, no dependence on
        05_views.sql or on any other query) and ends with a semicolon. Run ONE query at a
        time: select it from its comment header to its semicolon, then press F5.
        pgAdmin shows only the result of the last statement when several run together.
     3. Heavy queries (full-table windows or sorts: A10, A14, A20, A21) may take a few
        seconds on 550,000 rows.

   CONVENTIONS
     * transactions    = rows. fraud-labelled = is_fraud = 1, a SUPPLIED LABEL, not confirmed fraud.
     * Amounts are in an undocumented currency; attempted amounts on Failed, Reversed and
       Pending rows are not money moved. account_balance has no reliable definition, so no
       query treats it as an opening or closing balance or infers an overdraft.
     * customer_id is NOT a stable customer profile (finding DQ-02). Customer-level queries
       (A05, A14, A15, A17, A21) describe customer_id values only.
     * Complete years are 2019-2023. 2024 holds one day (2024-01-01) and is excluded from
       trend and year-over-year logic wherever it would distort a comparison.
     * Minimum sample sizes: dimension rates need at least 1,000 rows, cross-tab cells at
       least 500 (failure) or 200 (label rate), and medians at least 100 rows.
     * Confidence intervals are 95% Wilson score intervals (z = 1.96, z squared = 3.8416).
       They are shown so small differences are not over-read. Comparing many groups produces
       some 'significant' differences by chance, and nothing here establishes causes.
     * Rolling windows: A02 uses the previous 7 CALENDAR days and A13 the current plus
       previous 2 CALENDAR months. Both are built on a generated calendar so a missing day or
       month counts as zero instead of silently shortening the window. (No day or month is
       missing in this dataset; the windows still report how many periods they contain.)
     * Zero denominators are handled with NULLIF; first-period lags are NULL and shown as NULL.
     * Ranking tie-breakers are explicit (transaction_id, customer_id or a category name).

   LEVEL LABELS (counts: 11 multi-step, 9 single technique, 2 intermediate = 22)
     Advanced: multi-step       = at least two CTE steps (or a correlated subquery) combined with
                                  at least one windowed, ranking, percentile or generated-calendar
                                  technique: A01 A02 A04 A08 A09 A10 A13 A14 A17 A21 A22.
     Advanced: single technique = one clearly advanced feature (framed or partitioned window, ranking,
                                  LAG/LEAD, NTILE, PERCENTILE_CONT, CORR) in a short query:
                                  A03 A05 A06 A07 A11 A12 A16 A19 A20.
     Intermediate               = grouped and conditional aggregation with CTEs, no window or
                                  ordered-set logic: A15 A18.
     The 'genuinely advanced' count used in the project documentation is the 11 multi-step queries;
     the 9 single-technique queries are additional advanced-feature demonstrations.

   STATUS: written and logic-checked in SQLite with mechanical dialect rewrites (see
   python/sqlite_logic_check.py). NOT yet executed on PostgreSQL; see
   documentation/sql_query_catalogue.md for the status of each query.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   A01 - Monthly volume with month-over-month and year-over-year change   [Advanced: multi-step]
   Business question: how do monthly transaction counts and attempted amounts move from
     one month to the next and against the same month a year earlier?
   Concepts: CTE chain, LAG, self-join on (year, month), NULLIF, gap-safe comparison
   Metric: change % = (current - comparison) / comparison x 100. Month-over-month is shown
     only when the previous row is exactly the previous calendar month; year-over-year
     joins on (year - 1, same month), so it is correct even if a month were missing.
   Scope: January 2019 - December 2023 (2024 is a one-day stub). 2019 has no prior year.
   ----------------------------------------------------------------------------- */
WITH monthly AS (
    SELECT CAST(DATE_TRUNC('month', transaction_date) AS DATE)            AS month_start,
           CAST(EXTRACT(YEAR  FROM transaction_date) AS INTEGER)          AS yr,
           CAST(EXTRACT(MONTH FROM transaction_date) AS INTEGER)          AS mo,
           COUNT(*)                                                       AS transactions,
           SUM(transaction_amount)                                        AS total_amount
    FROM banking.transactions
    WHERE transaction_date < '2024-01-01'
    GROUP BY CAST(DATE_TRUNC('month', transaction_date) AS DATE),
             CAST(EXTRACT(YEAR  FROM transaction_date) AS INTEGER),
             CAST(EXTRACT(MONTH FROM transaction_date) AS INTEGER)
),
lagged AS (
    SELECT month_start, yr, mo, transactions, total_amount,
           LAG(transactions) OVER (ORDER BY month_start)       AS prev_transactions,
           LAG(total_amount) OVER (ORDER BY month_start)       AS prev_amount,
           LAG(yr * 12 + mo) OVER (ORDER BY month_start)       AS prev_month_index
    FROM monthly
)
SELECT l.month_start,
       l.transactions,
       CASE WHEN l.yr * 12 + l.mo - l.prev_month_index = 1
            THEN ROUND(100.0 * (l.transactions - l.prev_transactions) / NULLIF(l.prev_transactions, 0), 2)
       END                                                                     AS mom_transactions_pct,
       py.transactions                                                         AS same_month_prev_year_transactions,
       ROUND(100.0 * (l.transactions - py.transactions) / NULLIF(py.transactions, 0), 2) AS yoy_transactions_pct,
       l.total_amount,
       CASE WHEN l.yr * 12 + l.mo - l.prev_month_index = 1
            THEN ROUND(100.0 * (l.total_amount - l.prev_amount) / NULLIF(l.prev_amount, 0), 2)
       END                                                                     AS mom_amount_pct,
       ROUND(100.0 * (l.total_amount - py.total_amount) / NULLIF(py.total_amount, 0), 2) AS yoy_amount_pct
FROM lagged l
LEFT JOIN monthly py ON py.yr = l.yr - 1 AND py.mo = l.mo
ORDER BY l.month_start;


/* -----------------------------------------------------------------------------
   A02 - Unusual days against the previous 7 calendar days   [Advanced: multi-step]
   Business question: which days had transaction counts furthest from the recent norm?
   Concepts: generated calendar (generate_series), LEFT JOIN with COALESCE, framed window
     (ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING), ROW_NUMBER with tie-breaker
   Metric: baseline = average daily transactions over the 7 CALENDAR days before the day
     (the day itself is excluded). deviation % = (transactions - baseline) / baseline x 100.
     A day with no rows would count as 0 transactions. Days without a full 7-day history
     (the first 7) are excluded. Output = the 15 days with the largest absolute deviation.
   Limitation: a descriptive screen only. Daily counts vary naturally, so the top days are
     expected to look large without being meaningful on their own.
   ----------------------------------------------------------------------------- */
WITH calendar AS (
    SELECT CAST(g AS DATE) AS day
    FROM generate_series(CAST((SELECT MIN(transaction_date) FROM banking.transactions) AS TIMESTAMP),
                         CAST((SELECT MAX(transaction_date) FROM banking.transactions) AS TIMESTAMP),
                         INTERVAL '1 day') AS g
),
daily AS (
    SELECT transaction_date AS day, COUNT(*) AS transactions
    FROM banking.transactions
    GROUP BY transaction_date
),
filled AS (
    SELECT c.day, COALESCE(d.transactions, 0) AS transactions
    FROM calendar c
    LEFT JOIN daily d ON d.day = c.day
),
baseline AS (
    SELECT day, transactions,
           COUNT(*) OVER w                  AS days_in_baseline,
           AVG(transactions) OVER w         AS baseline_avg
    FROM filled
    WINDOW w AS (ORDER BY day ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING)
),
scored AS (
    SELECT day, transactions, baseline_avg,
           100.0 * (transactions - baseline_avg) / NULLIF(baseline_avg, 0) AS deviation_pct
    FROM baseline
    WHERE days_in_baseline = 7
),
ranked AS (
    SELECT s.*, ROW_NUMBER() OVER (ORDER BY ABS(deviation_pct) DESC, day) AS rn
    FROM scored s
)
SELECT rn AS rank_by_abs_deviation,
       day,
       transactions,
       ROUND(baseline_avg, 1)  AS baseline_7d_avg,
       ROUND(deviation_pct, 1) AS deviation_pct
FROM ranked
WHERE rn <= 15
ORDER BY rn;


/* -----------------------------------------------------------------------------
   A03 - Running totals by month and year-to-date   [Advanced: single technique]
   Business question: how do transactions and attempted amounts accumulate over the five
     complete years, and what share of the five-year total is reached by each month?
   Concepts: SUM() OVER with UNBOUNDED PRECEDING frame, PARTITION BY year for YTD,
     whole-table window for the denominator
   Metric: cumulative_pct = running total / five-year total x 100 (2019-2023 only).
   ----------------------------------------------------------------------------- */
WITH monthly AS (
    SELECT CAST(DATE_TRUNC('month', transaction_date) AS DATE) AS month_start,
           CAST(EXTRACT(YEAR FROM transaction_date) AS INTEGER) AS yr,
           COUNT(*)                                             AS transactions,
           SUM(transaction_amount)                              AS total_amount
    FROM banking.transactions
    WHERE transaction_date < '2024-01-01'
    GROUP BY CAST(DATE_TRUNC('month', transaction_date) AS DATE),
             CAST(EXTRACT(YEAR FROM transaction_date) AS INTEGER)
)
SELECT month_start,
       transactions,
       SUM(transactions) OVER (ORDER BY month_start
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)    AS cumulative_transactions,
       ROUND(100.0 * SUM(transactions) OVER (ORDER BY month_start
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                   / NULLIF(SUM(transactions) OVER (), 0), 2)                       AS cumulative_pct_of_total,
       SUM(transactions) OVER (PARTITION BY yr ORDER BY month_start
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)    AS year_to_date_transactions,
       total_amount,
       SUM(total_amount) OVER (ORDER BY month_start
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)    AS cumulative_amount
FROM monthly
ORDER BY month_start;


/* -----------------------------------------------------------------------------
   A04 - Year-over-year change by transaction type, with yearly rank   [Advanced: multi-step]
   Business question: which payment types grew or shrank between complete years, and how
     does each type rank by amount within each year?
   Concepts: CTE, LAG with PARTITION BY, DENSE_RANK with PARTITION BY, NULLIF
   Metric: yoy % = (year - previous year) / previous year x 100, shown only when the previous
     row is the immediately preceding year. 2019 has no prior year; 2024 is excluded.
   Limitation: attempted amounts include Failed, Reversed and Pending rows.
   ----------------------------------------------------------------------------- */
WITH yearly AS (
    SELECT transaction_type,
           CAST(EXTRACT(YEAR FROM transaction_date) AS INTEGER) AS yr,
           COUNT(*)                                             AS transactions,
           SUM(transaction_amount)                              AS total_amount
    FROM banking.transactions
    WHERE transaction_date < '2024-01-01'
    GROUP BY transaction_type, CAST(EXTRACT(YEAR FROM transaction_date) AS INTEGER)
),
lagged AS (
    SELECT transaction_type, yr, transactions, total_amount,
           LAG(yr)           OVER (PARTITION BY transaction_type ORDER BY yr) AS prev_yr,
           LAG(transactions) OVER (PARTITION BY transaction_type ORDER BY yr) AS prev_transactions,
           LAG(total_amount) OVER (PARTITION BY transaction_type ORDER BY yr) AS prev_amount,
           DENSE_RANK()      OVER (PARTITION BY yr ORDER BY total_amount DESC, transaction_type) AS amount_rank_in_year
    FROM yearly
)
SELECT transaction_type,
       yr AS calendar_year,
       transactions,
       CASE WHEN yr - prev_yr = 1
            THEN ROUND(100.0 * (transactions - prev_transactions) / NULLIF(prev_transactions, 0), 2) END AS yoy_transactions_pct,
       total_amount,
       CASE WHEN yr - prev_yr = 1
            THEN ROUND(100.0 * (total_amount - prev_amount) / NULLIF(prev_amount, 0), 2) END AS yoy_amount_pct,
       amount_rank_in_year
FROM lagged
ORDER BY transaction_type, yr;


/* -----------------------------------------------------------------------------
   A05 - Customer ID activity ranking: ROW_NUMBER vs RANK vs DENSE_RANK   [Advanced: single technique]
   Business question: which customer_id values have the most transactions, and how do the
     three ranking functions treat ties?
   Concepts: CTE, ROW_NUMBER, RANK, DENSE_RANK, COUNT(DISTINCT) as a data-quality signal
   Metric: ranked by number of rows per customer_id (many IDs share the same count).
     ROW_NUMBER is unique (tie-break: customer_id), RANK leaves gaps after ties, DENSE_RANK does not.
   Limitation: customer_id is not a stable customer profile (DQ-02), so this ranks ID values.
     distinct_states > 1 on the top IDs shows the same ID appearing with several states.
   ----------------------------------------------------------------------------- */
WITH per_customer AS (
    SELECT customer_id,
           COUNT(*)                     AS transactions,
           SUM(transaction_amount)      AS total_amount,
           COUNT(DISTINCT state)        AS distinct_states
    FROM banking.transactions
    GROUP BY customer_id
)
SELECT customer_id,
       transactions,
       total_amount,
       distinct_states,
       ROW_NUMBER() OVER (ORDER BY transactions DESC, customer_id) AS row_number_rank,
       RANK()       OVER (ORDER BY transactions DESC)              AS rank_with_gaps,
       DENSE_RANK() OVER (ORDER BY transactions DESC)              AS dense_rank
FROM per_customer
ORDER BY row_number_rank
LIMIT 15;


/* -----------------------------------------------------------------------------
   A06 - Three largest transactions in each merchant category   [Advanced: single technique]
   Business question: what are the highest-value transactions in each category, through
     which channel, and with what status and label?
   Concepts: ROW_NUMBER with PARTITION BY, deterministic tie-break, top-N per group
   Metric: rank by transaction_amount within category (ties broken by transaction_id).
   Limitation: amounts at the 10,000,000.00 ceiling are probably capped values (DQ-04), so
     ties at the top are expected. Status shows whether the amount was actually completed.
   ----------------------------------------------------------------------------- */
WITH ranked AS (
    SELECT merchant_category, transaction_id, transaction_date, transaction_type, channel,
           transaction_direction, transaction_amount, transaction_status, is_fraud,
           ROW_NUMBER() OVER (PARTITION BY merchant_category
                              ORDER BY transaction_amount DESC, transaction_id) AS rank_in_category
    FROM banking.transactions
)
SELECT merchant_category, rank_in_category, transaction_id, transaction_date,
       transaction_type, channel, transaction_direction, transaction_amount,
       transaction_status, is_fraud
FROM ranked
WHERE rank_in_category <= 3
ORDER BY merchant_category, rank_in_category;


/* -----------------------------------------------------------------------------
   A07 - Channel mix within each transaction type   [Advanced: single technique]
   Business question: through which channels does each payment type flow, and which channel
     carries the most completed amount for that type?
   Concepts: conditional aggregation, window SUM with PARTITION BY (share of group),
     RANK with PARTITION BY
   Metric: pct_of_type = channel rows / all rows of the type. success_amount sums amounts of
     Success rows only. Ties in rank are shared (RANK), then ordered by channel name.
   Limitation: some type/channel pairs look unnatural (for example ATM_Withdrawal via Web); the
     pairing logic of the source data is undocumented, so this is a description of the file.
   ----------------------------------------------------------------------------- */
WITH combo AS (
    SELECT transaction_type, channel,
           COUNT(*) AS transactions,
           SUM(CASE WHEN transaction_status = 'Success' THEN transaction_amount ELSE 0 END) AS success_amount
    FROM banking.transactions
    GROUP BY transaction_type, channel
)
SELECT transaction_type,
       channel,
       transactions,
       ROUND(100.0 * transactions / NULLIF(SUM(transactions) OVER (PARTITION BY transaction_type), 0), 2) AS pct_of_type,
       RANK() OVER (PARTITION BY transaction_type ORDER BY transactions DESC) AS channel_rank_in_type,
       success_amount,
       ROUND(100.0 * success_amount / NULLIF(SUM(success_amount) OVER (PARTITION BY transaction_type), 0), 2) AS pct_of_type_success_amount
FROM combo
ORDER BY transaction_type, channel_rank_in_type, channel;


/* -----------------------------------------------------------------------------
   A08 - Failed-or-reversed rate by transaction type and channel   [Advanced: multi-step]
   Business question: are any type/channel combinations meaningfully worse than the overall
     failed-or-reversed rate?
   Concepts: multi-CTE pipeline, scalar overall rate via CROSS JOIN, HAVING minimum sample
     (500 rows), Wilson interval, RANK, CASE signal
   Metric: rate = (Failed + Reversed rows) / all rows in the combination. overall = same ratio
     over all 550,000 rows. signal compares the combination's 95% interval with the overall rate.
   Limitation: 60 combinations are compared, so some will look 'different' by chance alone. The
     reason a transaction failed or was reversed is not in the data. Output shows the 15 highest rates.
   ----------------------------------------------------------------------------- */
WITH overall AS (
    SELECT 1.0 * SUM(CASE WHEN transaction_status IN ('Failed', 'Reversed') THEN 1 ELSE 0 END)
                 / NULLIF(COUNT(*), 0) AS overall_p
    FROM banking.transactions
),
combo AS (
    SELECT transaction_type, channel,
           COUNT(*) AS n,
           SUM(CASE WHEN transaction_status = 'Failed'   THEN 1 ELSE 0 END) AS failed,
           SUM(CASE WHEN transaction_status = 'Reversed' THEN 1 ELSE 0 END) AS reversed
    FROM banking.transactions
    GROUP BY transaction_type, channel
    HAVING COUNT(*) >= 500
),
rates AS (
    SELECT c.transaction_type, c.channel, c.n, c.failed, c.reversed,
           1.0 * (c.failed + c.reversed) / c.n AS p,
           o.overall_p
    FROM combo c
    CROSS JOIN overall o
),
ci AS (
    SELECT r.*,
           ((p + 3.8416 / (2.0 * n) - 1.96 * SQRT(p * (1 - p) / n + 3.8416 / (4.0 * n * n))) / (1 + 3.8416 / n))  AS ci_low,
           ((p + 3.8416 / (2.0 * n) + 1.96 * SQRT(p * (1 - p) / n + 3.8416 / (4.0 * n * n))) / (1 + 3.8416 / n)) AS ci_high
    FROM rates r
)
SELECT RANK() OVER (ORDER BY p DESC, transaction_type, channel) AS rank_by_rate,
       transaction_type,
       channel,
       n AS transactions,
       failed,
       reversed,
       ROUND(100.0 * p, 2)         AS failed_or_reversed_pct,
       ROUND(100.0 * overall_p, 2) AS overall_pct,
       ROUND(100.0 * ci_low, 2)    AS ci_low_pct,
       ROUND(100.0 * ci_high, 2)   AS ci_high_pct,
       ROUND(p / NULLIF(overall_p, 0), 2) AS ratio_to_overall,
       CASE WHEN ci_low  > overall_p THEN 'above overall (interval excludes overall)'
            WHEN ci_high < overall_p THEN 'below overall (interval excludes overall)'
            ELSE 'consistent with overall' END AS signal
FROM ci
ORDER BY rank_by_rate
LIMIT 15;


/* -----------------------------------------------------------------------------
   A09 - Fraud-label rate by transaction type WITHIN amount band   [Advanced: multi-step]
   Business question: RTGS and Cheque show higher label rates overall, but they also carry
     the largest amounts. Do they still stand out once amount size is held roughly constant?
   Concepts: multi-CTE pipeline, CASE banding, stratified comparison, HAVING minimum sample
     (200 rows per cell), Wilson interval, ratio to the band's own rate
   Metric: rate = fraud-labelled rows / rows in the (band, type) cell. band rate = labelled / rows
     in the whole band (all types). Bands are provisional and coarser than E09.
   Limitation: the label is supplied, not confirmed fraud; a stratified table shows association only
     and cannot show why the label was assigned. Cells under 200 rows are not shown.
   ----------------------------------------------------------------------------- */
WITH banded AS (
    SELECT transaction_type, is_fraud,
           CASE WHEN transaction_amount <   25000 THEN '1 under 25,000'
                WHEN transaction_amount <  100000 THEN '2 25,000-99,999.99'
                WHEN transaction_amount < 1000000 THEN '3 100,000-999,999.99'
                ELSE                                   '4 1,000,000 and over'
           END AS amount_band
    FROM banking.transactions
),
band_totals AS (
    SELECT amount_band, COUNT(*) AS band_n, SUM(is_fraud) AS band_labelled
    FROM banded
    GROUP BY amount_band
),
cells AS (
    SELECT amount_band, transaction_type, COUNT(*) AS n, SUM(is_fraud) AS x
    FROM banded
    GROUP BY amount_band, transaction_type
    HAVING COUNT(*) >= 200
),
stats AS (
    SELECT c.amount_band, c.transaction_type, c.n, c.x,
           1.0 * c.x / c.n                     AS p,
           1.0 * b.band_labelled / b.band_n    AS band_p
    FROM cells c
    JOIN band_totals b ON b.amount_band = c.amount_band
),
ci AS (
    SELECT s.*,
           ((p + 3.8416 / (2.0 * n) - 1.96 * SQRT(p * (1 - p) / n + 3.8416 / (4.0 * n * n))) / (1 + 3.8416 / n))  AS ci_low,
           ((p + 3.8416 / (2.0 * n) + 1.96 * SQRT(p * (1 - p) / n + 3.8416 / (4.0 * n * n))) / (1 + 3.8416 / n)) AS ci_high
    FROM stats s
)
SELECT amount_band,
       transaction_type,
       n AS transactions,
       x AS fraud_labelled,
       ROUND(100.0 * p, 3)       AS label_rate_pct,
       ROUND(100.0 * band_p, 3)  AS band_rate_pct,
       ROUND(p / NULLIF(band_p, 0), 2) AS ratio_to_band,
       ROUND(100.0 * ci_low, 3)  AS ci_low_pct,
       ROUND(100.0 * ci_high, 3) AS ci_high_pct,
       CASE WHEN ci_low  > band_p THEN 'above band rate'
            WHEN ci_high < band_p THEN 'below band rate'
            ELSE 'consistent with band rate' END AS signal
FROM ci
ORDER BY amount_band, ratio_to_band DESC, transaction_type;


/* -----------------------------------------------------------------------------
   A10 - Fraud-label concentration by amount decile (gains table)   [Advanced: multi-step]
   Business question: what share of fraud-labelled rows sits in the largest transactions?
   Concepts: NTILE(10), CTE, cumulative SUM() OVER, whole-table window denominators, lift
   Metric: decile 1 = the largest 10% of rows by transaction_amount (ties broken by
     transaction_id, so equal amounts can straddle a boundary). cumulative_share = labelled rows in
     deciles 1..k / all labelled rows. lift = decile rate / overall rate.
   Limitation: shows where the supplied label concentrates, not that large amounts cause fraud
     and not confirmed losses. The label's assignment method is undocumented.
   ----------------------------------------------------------------------------- */
WITH ranked AS (
    SELECT transaction_amount, is_fraud,
           NTILE(10) OVER (ORDER BY transaction_amount DESC, transaction_id) AS amount_decile
    FROM banking.transactions
),
by_decile AS (
    SELECT amount_decile,
           COUNT(*)                 AS transactions,
           MIN(transaction_amount)  AS min_amount,
           MAX(transaction_amount)  AS max_amount,
           SUM(is_fraud)            AS fraud_labelled
    FROM ranked
    GROUP BY amount_decile
)
SELECT amount_decile,
       transactions,
       min_amount,
       max_amount,
       fraud_labelled,
       ROUND(100.0 * fraud_labelled / NULLIF(transactions, 0), 3) AS label_rate_pct,
       SUM(fraud_labelled) OVER (ORDER BY amount_decile
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_labelled,
       ROUND(100.0 * SUM(fraud_labelled) OVER (ORDER BY amount_decile
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                   / NULLIF(SUM(fraud_labelled) OVER (), 0), 2)                    AS cumulative_share_of_labelled_pct,
       ROUND((1.0 * fraud_labelled / NULLIF(transactions, 0))
             / NULLIF(1.0 * SUM(fraud_labelled) OVER () / NULLIF(SUM(transactions) OVER (), 0), 0), 2) AS lift_vs_overall
FROM by_decile
ORDER BY amount_decile;


/* -----------------------------------------------------------------------------
   A11 - Amount distribution by transaction type (percentiles)   [Advanced: single technique]
   Business question: how skewed are amounts within each payment type?
   Concepts: PERCENTILE_CONT (ordered-set aggregate), mean-to-median ratio, HAVING minimum sample
   Metric: continuous percentiles of transaction_amount per type; mean_to_median = mean / median.
     Types with fewer than 1,000 rows are omitted.
   Limitation: amounts include Failed, Reversed and Pending rows; the currency is undocumented;
     the 10,000,000.00 ceiling (DQ-04) caps the upper tail.
   ----------------------------------------------------------------------------- */
SELECT transaction_type,
       COUNT(*) AS transactions,
       ROUND(CAST(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p25,
       ROUND(CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS median,
       ROUND(CAST(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p75,
       ROUND(CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p95,
       ROUND(CAST(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 2) AS p99,
       ROUND(AVG(transaction_amount), 2) AS mean,
       ROUND(AVG(transaction_amount)
             / NULLIF(CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY transaction_amount) AS NUMERIC), 0), 2) AS mean_to_median
FROM banking.transactions
GROUP BY transaction_type
HAVING COUNT(*) >= 1000
ORDER BY median DESC, transaction_type;


/* -----------------------------------------------------------------------------
   A12 - Median amount of fraud-labelled vs other transactions, by channel   [Advanced: single technique]
   Business question: is the labelled-versus-other amount gap consistent across channels, or
     does a few large values drive it?
   Concepts: PERCENTILE_CONT with FILTER, conditional aggregation, HAVING minimum sample
   Metric: median of transaction_amount for is_fraud = 1 and for is_fraud = 0 within each channel;
     ratio = labelled median / other median. Channels need at least 100 labelled rows.
   Limitation: amounts on labelled rows are not confirmed losses. Medians resist the large-value
     tail that inflates the means (compare E11).
   ----------------------------------------------------------------------------- */
SELECT channel,
       COUNT(*) FILTER (WHERE is_fraud = 1) AS labelled_transactions,
       COUNT(*) FILTER (WHERE is_fraud = 0) AS other_transactions,
       ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY transaction_amount) FILTER (WHERE is_fraud = 1) AS NUMERIC), 2) AS median_labelled,
       ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY transaction_amount) FILTER (WHERE is_fraud = 0) AS NUMERIC), 2) AS median_other,
       ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY transaction_amount) FILTER (WHERE is_fraud = 1) AS NUMERIC)
             / NULLIF(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY transaction_amount) FILTER (WHERE is_fraud = 0) AS NUMERIC), 0), 2) AS median_ratio
FROM banking.transactions
GROUP BY channel
HAVING COUNT(*) FILTER (WHERE is_fraud = 1) >= 100
ORDER BY channel;


/* -----------------------------------------------------------------------------
   A13 - Rolling 3-month failed-or-reversed rate   [Advanced: multi-step]
   Business question: is the share of failed or reversed transactions drifting over time once
     monthly noise is smoothed?
   Concepts: generated month calendar, LEFT JOIN with COALESCE, framed window
     (ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), ratio of sums
   Metric: rolling rate = SUM(failed + reversed) / SUM(transactions) over the current month and the
     previous 2 CALENDAR months. A month with no rows would count as 0. Only windows holding 3 months
     are reported (so the first two months are excluded). Output covers Mar 2019 - Dec 2023.
   Limitation: ratio of sums (not the average of monthly rates). Descriptive only.
   ----------------------------------------------------------------------------- */
WITH months AS (
    SELECT CAST(g AS DATE) AS month_start
    FROM generate_series(CAST(CAST(DATE_TRUNC('month', (SELECT MIN(transaction_date) FROM banking.transactions)) AS DATE) AS TIMESTAMP),
                         CAST(CAST(DATE_TRUNC('month', (SELECT MAX(transaction_date) FROM banking.transactions)) AS DATE) AS TIMESTAMP),
                         INTERVAL '1 month') AS g
),
monthly AS (
    SELECT CAST(DATE_TRUNC('month', transaction_date) AS DATE) AS month_start,
           COUNT(*) AS transactions,
           SUM(CASE WHEN transaction_status IN ('Failed', 'Reversed') THEN 1 ELSE 0 END) AS bad
    FROM banking.transactions
    GROUP BY CAST(DATE_TRUNC('month', transaction_date) AS DATE)
),
filled AS (
    SELECT m.month_start,
           COALESCE(a.transactions, 0) AS transactions,
           COALESCE(a.bad, 0)          AS bad
    FROM months m
    LEFT JOIN monthly a ON a.month_start = m.month_start
),
rolling AS (
    SELECT month_start, transactions, bad,
           COUNT(*)          OVER w AS months_in_window,
           SUM(transactions) OVER w AS window_transactions,
           SUM(bad)          OVER w AS window_bad
    FROM filled
    WINDOW w AS (ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
)
SELECT month_start,
       transactions,
       bad AS failed_or_reversed,
       ROUND(100.0 * bad / NULLIF(transactions, 0), 2)               AS monthly_rate_pct,
       window_transactions,
       window_bad,
       ROUND(100.0 * window_bad / NULLIF(window_transactions, 0), 2) AS rolling_3m_rate_pct
FROM rolling
WHERE months_in_window = 3
  AND month_start < '2024-01-01'
ORDER BY month_start;


/* -----------------------------------------------------------------------------
   A14 - How concentrated is activity across customer_id values?   [Advanced: multi-step]
   Business question: do a small number of customer_id values account for much of the activity?
   Concepts: CTE pipeline, NTILE(10) over an aggregate, cumulative SUM() OVER
   Metric: customer_id values are split into 10 equal-count groups by transactions (group 1 = most
     active, ties broken by customer_id). pct_of_transactions = group rows / all rows;
     cumulative_pct sums those shares.
   Limitation: customer_id is not a stable customer (DQ-02), so this describes ID values only and
     must not be reported as customer concentration.
   ----------------------------------------------------------------------------- */
WITH per_customer AS (
    SELECT customer_id, COUNT(*) AS transactions, SUM(transaction_amount) AS total_amount
    FROM banking.transactions
    GROUP BY customer_id
),
bucketed AS (
    SELECT customer_id, transactions, total_amount,
           NTILE(10) OVER (ORDER BY transactions DESC, customer_id) AS activity_group
    FROM per_customer
),
by_group AS (
    SELECT activity_group,
           COUNT(*)          AS customer_ids,
           MIN(transactions) AS min_transactions_per_id,
           MAX(transactions) AS max_transactions_per_id,
           SUM(transactions) AS transactions,
           SUM(total_amount) AS total_amount
    FROM bucketed
    GROUP BY activity_group
)
SELECT activity_group,
       customer_ids,
       min_transactions_per_id,
       max_transactions_per_id,
       transactions,
       ROUND(100.0 * transactions / NULLIF(SUM(transactions) OVER (), 0), 2) AS pct_of_transactions,
       ROUND(100.0 * SUM(transactions) OVER (ORDER BY activity_group
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                   / NULLIF(SUM(transactions) OVER (), 0), 2)                AS cumulative_pct,
       total_amount
FROM by_group
ORDER BY activity_group;


/* -----------------------------------------------------------------------------
   A15 - Do customer_id attributes stay constant? (data-quality exception summary)   [Intermediate]
   Business question: for IDs with at least two rows, how often do state, account type, credit
     score, KYC status or loan flag change between rows of the same customer_id?
   Concepts: CTE, COUNT(DISTINCT) per group, conditional aggregation, HAVING
   Metric: share = IDs whose attribute has more than one distinct value / IDs with at least 2 rows.
     all_five_constant = IDs where none of the five attributes ever changes.
   Limitation: this evidences finding DQ-02; it does not explain it. A real customer's credit
     score and state would not normally vary like this.
   ----------------------------------------------------------------------------- */
WITH per_customer AS (
    SELECT customer_id,
           COUNT(*)                          AS transactions,
           COUNT(DISTINCT state)             AS n_state,
           COUNT(DISTINCT account_type)      AS n_account_type,
           COUNT(DISTINCT credit_score)      AS n_credit_score,
           COUNT(DISTINCT kyc_status)        AS n_kyc_status,
           COUNT(DISTINCT has_loan)          AS n_has_loan
    FROM banking.transactions
    GROUP BY customer_id
    HAVING COUNT(*) >= 2
)
SELECT COUNT(*) AS customer_ids_with_2plus_rows,
       SUM(CASE WHEN n_state > 1        THEN 1 ELSE 0 END) AS state_varies,
       ROUND(100.0 * SUM(CASE WHEN n_state > 1        THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS state_varies_pct,
       SUM(CASE WHEN n_account_type > 1 THEN 1 ELSE 0 END) AS account_type_varies,
       ROUND(100.0 * SUM(CASE WHEN n_account_type > 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS account_type_varies_pct,
       SUM(CASE WHEN n_credit_score > 1 THEN 1 ELSE 0 END) AS credit_score_varies,
       ROUND(100.0 * SUM(CASE WHEN n_credit_score > 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS credit_score_varies_pct,
       SUM(CASE WHEN n_kyc_status > 1   THEN 1 ELSE 0 END) AS kyc_status_varies,
       ROUND(100.0 * SUM(CASE WHEN n_kyc_status > 1   THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS kyc_status_varies_pct,
       SUM(CASE WHEN n_has_loan > 1     THEN 1 ELSE 0 END) AS has_loan_varies,
       ROUND(100.0 * SUM(CASE WHEN n_has_loan > 1     THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS has_loan_varies_pct,
       SUM(CASE WHEN n_state = 1 AND n_account_type = 1 AND n_credit_score = 1
                 AND n_kyc_status = 1 AND n_has_loan = 1 THEN 1 ELSE 0 END)                       AS all_five_constant
FROM per_customer;


/* -----------------------------------------------------------------------------
   A16 - Loan-flag consistency profile: three groups compared   [Advanced: single technique]
   Business question: how do the 19,422 rows with has_loan = 1 and loan_type = 'None' (DQ-01)
     compare with rows that have a named loan type and rows with no loan?
   Concepts: CASE to define groups, window share of total, PERCENTILE_CONT, conditional aggregation
   Metric: group sizes and shares of all rows; median and mean EMI and credit score; failed-or-reversed
     rate and fraud-label rate within each group (denominator = rows in the group).
   Limitation: the exception rows are flagged, not corrected, and the cause is unknown (UQ-07). A group
     difference is descriptive. Credit score varies within customer_id (DQ-02), so it is read per row.
   ----------------------------------------------------------------------------- */
WITH grouped AS (
    SELECT CASE WHEN has_loan = 0                          THEN '1 No loan (has_loan = 0)'
                WHEN has_loan = 1 AND loan_type = 'None'   THEN '3 Loan flag set, loan_type None (DQ-01)'
                ELSE                                            '2 Loan flag set, named loan type'
           END AS loan_group,
           emi_amount, credit_score, transaction_status, is_fraud, transaction_amount
    FROM banking.transactions
)
SELECT loan_group,
       COUNT(*) AS transactions,
       ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS pct_of_all_rows,
       ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY emi_amount) AS NUMERIC), 2)     AS median_emi,
       ROUND(AVG(emi_amount), 2)                                                              AS mean_emi,
       ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY credit_score) AS NUMERIC), 1)   AS median_credit_score,
       ROUND(100.0 * SUM(CASE WHEN transaction_status IN ('Failed', 'Reversed') THEN 1 ELSE 0 END)
                   / NULLIF(COUNT(*), 0), 2)                                                  AS failed_or_reversed_pct,
       SUM(is_fraud)                                                                          AS fraud_labelled,
       ROUND(100.0 * SUM(is_fraud) / NULLIF(COUNT(*), 0), 3)                                  AS fraud_label_rate_pct,
       ROUND(AVG(transaction_amount), 2)                                                      AS mean_amount
FROM grouped
GROUP BY loan_group
ORDER BY loan_group;


/* -----------------------------------------------------------------------------
   A17 - Do customer IDs with DQ-01 rows also have rows with a named loan type?   [Advanced: multi-step]
   Business question: when has_loan = 1 and loan_type = 'None' appears for a customer_id, do other
     rows of the same ID name a loan type, show no loan, or are all rows exceptions?
   Concepts: CTE with DISTINCT, correlated EXISTS / NOT EXISTS subqueries, conditional aggregation
   Metric: counts of customer_id values (not rows). Categories overlap, so they need not sum to the total,
     except only_dq01_rows which is exclusive.
   Limitation: because customer attributes vary across rows of one ID (DQ-02), overlap here is expected
     and is evidence that the ID is not a stable customer, not that any loan record is right or wrong.
   ----------------------------------------------------------------------------- */
WITH flagged AS (
    SELECT DISTINCT customer_id
    FROM banking.transactions
    WHERE has_loan = 1 AND loan_type = 'None'
)
SELECT COUNT(*) AS customer_ids_with_dq01_rows,
       SUM(CASE WHEN EXISTS (SELECT 1 FROM banking.transactions t2
                             WHERE t2.customer_id = f.customer_id AND t2.loan_type <> 'None')
                THEN 1 ELSE 0 END) AS also_have_named_loan_rows,
       SUM(CASE WHEN EXISTS (SELECT 1 FROM banking.transactions t2
                             WHERE t2.customer_id = f.customer_id AND t2.has_loan = 0)
                THEN 1 ELSE 0 END) AS also_have_no_loan_rows,
       SUM(CASE WHEN NOT EXISTS (SELECT 1 FROM banking.transactions t2
                                 WHERE t2.customer_id = f.customer_id
                                   AND NOT (t2.has_loan = 1 AND t2.loan_type = 'None'))
                THEN 1 ELSE 0 END) AS only_dq01_rows
FROM flagged f;


/* -----------------------------------------------------------------------------
   A18 - Amount relative to account_balance, by direction (descriptive only)   [Intermediate]
   Business question: how large are transaction amounts relative to the recorded account_balance, and
     does the fraud-label rate change with that ratio?
   Concepts: CTE, CASE banding of a ratio, NULLIF, window share within a group
   Metric: ratio = transaction_amount / account_balance. pct_of_direction = rows in the band / rows with that
     direction. The label rate uses rows in the band as the denominator.
   Limitation: account_balance has no reliable definition (UQ-01); a ratio above 1 is NOT evidence of an
     overdraft, and the balance is not an opening or closing balance. This query only describes the file.
   ----------------------------------------------------------------------------- */
WITH base AS (
    SELECT transaction_direction, is_fraud,
           transaction_amount / NULLIF(account_balance, 0) AS amount_to_balance
    FROM banking.transactions
),
banded AS (
    SELECT transaction_direction, is_fraud,
           CASE WHEN amount_to_balance IS NULL THEN '0 balance is zero'
                WHEN amount_to_balance <   0.1 THEN '1 under 0.1'
                WHEN amount_to_balance <   0.5 THEN '2 0.1 to under 0.5'
                WHEN amount_to_balance <   1   THEN '3 0.5 to under 1'
                WHEN amount_to_balance <   2   THEN '4 1 to under 2'
                WHEN amount_to_balance <  10   THEN '5 2 to under 10'
                ELSE                                '6 10 and over'
           END AS ratio_band
    FROM base
)
SELECT transaction_direction,
       ratio_band,
       COUNT(*) AS transactions,
       ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY transaction_direction), 0), 2) AS pct_of_direction,
       SUM(is_fraud) AS fraud_labelled,
       ROUND(100.0 * SUM(is_fraud) / NULLIF(COUNT(*), 0), 3) AS fraud_label_rate_pct
FROM banded
GROUP BY transaction_direction, ratio_band
ORDER BY transaction_direction, ratio_band;


/* -----------------------------------------------------------------------------
   A19 - Do amount and account_balance move together? (correlation and ratio percentiles)   [Advanced: single technique]
   Business question: is there any linear relationship between transaction_amount and account_balance, and
     what do typical and extreme ratios look like?
   Concepts: CORR, PERCENTILE_CONT on a derived ratio, GROUP BY direction
   Metric: Pearson correlation of amount and balance per direction (-1 to 1; near 0 means no linear link);
     ratio percentiles use transaction_amount / account_balance.
   Limitation: the balance definition is unknown (UQ-01). Pearson correlation is sensitive to the large
     amounts (and the 10,000,000.00 ceiling), so the log-free value is indicative only. No overdraft or
     causal reading is implied.
   ----------------------------------------------------------------------------- */
SELECT transaction_direction,
       COUNT(*) AS transactions,
       ROUND(CAST(CORR(transaction_amount, account_balance) AS NUMERIC), 4) AS corr_amount_balance,
       ROUND(CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY transaction_amount / NULLIF(account_balance, 0)) AS NUMERIC), 4) AS median_ratio,
       ROUND(CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY transaction_amount / NULLIF(account_balance, 0)) AS NUMERIC), 4) AS p95_ratio,
       ROUND(CAST(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY transaction_amount / NULLIF(account_balance, 0)) AS NUMERIC), 4) AS p99_ratio
FROM banking.transactions
GROUP BY transaction_direction
ORDER BY transaction_direction;


/* -----------------------------------------------------------------------------
   A20 - ID sequence and date-order integrity (exception detection)   [Advanced: single technique]
   Business question: are transaction IDs gap-free and is the file in date order, as assumed by
     the provenance review?
   Concepts: LAG and LEAD over the whole table, derived numeric ID, date arithmetic
   Metric: id_gaps = rows whose numeric ID is not previous + 1; date_regressions = rows dated
     earlier than the previous row (by transaction_id); next_before_current = rows whose NEXT row
     is dated earlier (LEAD cross-check); max_day_jump = largest forward date step.
   Expected if the data is as profiled: id_gaps 0, regressions 0, max_day_jump 1.
   Limitation: a regular sequence is consistent with generated or processed data but does not prove it.
   ----------------------------------------------------------------------------- */
WITH ordered AS (
    SELECT transaction_id,
           transaction_date AS txn_date,
           CAST(SUBSTR(transaction_id, 4) AS INTEGER)                        AS id_number,
           LAG(CAST(SUBSTR(transaction_id, 4) AS INTEGER)) OVER w            AS prev_id_number,
           LAG(transaction_date) OVER w                                      AS prev_txn_date,
           LEAD(transaction_date) OVER w                                     AS next_txn_date
    FROM banking.transactions
    WINDOW w AS (ORDER BY transaction_id)
)
SELECT COUNT(*) AS rows_checked,
       SUM(CASE WHEN prev_id_number IS NOT NULL AND id_number - prev_id_number <> 1 THEN 1 ELSE 0 END) AS id_gaps,
       SUM(CASE WHEN prev_txn_date  IS NOT NULL AND txn_date < prev_txn_date THEN 1 ELSE 0 END)        AS date_regressions,
       SUM(CASE WHEN next_txn_date  IS NOT NULL AND next_txn_date < txn_date THEN 1 ELSE 0 END)        AS next_before_current,
       MAX(CASE WHEN prev_txn_date  IS NOT NULL THEN (txn_date - prev_txn_date) END)                    AS max_day_jump
FROM ordered;


/* -----------------------------------------------------------------------------
   A21 - Days between consecutive transactions of the same customer_id   [Advanced: multi-step]
   Business question: how soon does a customer_id transact again?
   Concepts: LAG with PARTITION BY, date difference, CASE bucketing, window share
   Metric: for every row with an earlier row for the same customer_id (ordered by date, time,
     transaction_id), days_since_previous = date difference. pct = bucket rows / all such rows.
     First rows per ID (79,916 of them) have no predecessor and are excluded.
   Limitation: customer_id is not a stable customer (DQ-02); the gaps describe ID values.
   ----------------------------------------------------------------------------- */
WITH seq AS (
    SELECT customer_id,
           transaction_date AS txn_date,
           LAG(transaction_date) OVER (PARTITION BY customer_id
                                       ORDER BY transaction_date, transaction_time, transaction_id) AS prev_txn_date
    FROM banking.transactions
),
gaps AS (
    SELECT (txn_date - prev_txn_date) AS days_since_previous
    FROM seq
    WHERE prev_txn_date IS NOT NULL
),
bucketed AS (
    SELECT CASE WHEN days_since_previous = 0    THEN '1 same day'
                WHEN days_since_previous <= 7   THEN '2 1-7 days'
                WHEN days_since_previous <= 30  THEN '3 8-30 days'
                WHEN days_since_previous <= 90  THEN '4 31-90 days'
                WHEN days_since_previous <= 365 THEN '5 91-365 days'
                ELSE                                 '6 more than 365 days'
           END AS gap_bucket
    FROM gaps
)
SELECT gap_bucket,
       COUNT(*) AS transaction_pairs,
       ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS pct_of_pairs
FROM bucketed
GROUP BY gap_bucket
ORDER BY gap_bucket;


/* -----------------------------------------------------------------------------
   A22 - State comparison of the fraud-label rate with confidence intervals   [Advanced: multi-step]
   Business question: do any states have a label rate distinguishable from the overall rate?
   Concepts: multi-CTE pipeline, HAVING minimum sample (1,000 rows), Wilson interval, z-score,
     RANK, CASE signal
   Metric: rate = fraud-labelled rows / rows in the state. z = (p - overall) / sqrt(overall x (1 - overall) / n).
     |z| above about 2 is notable for one comparison; with 10 states about one is expected by chance.
   Limitation: what 'state' means is undocumented (UQ-05) and the label is supplied (UQ-03). No causal reading.
   ----------------------------------------------------------------------------- */
WITH overall AS (
    SELECT 1.0 * SUM(is_fraud) / NULLIF(COUNT(*), 0) AS overall_p
    FROM banking.transactions
),
by_state AS (
    SELECT state, COUNT(*) AS n, SUM(is_fraud) AS x
    FROM banking.transactions
    GROUP BY state
    HAVING COUNT(*) >= 1000
),
stats AS (
    SELECT s.state, s.n, s.x, 1.0 * s.x / s.n AS p, o.overall_p
    FROM by_state s
    CROSS JOIN overall o
),
ci AS (
    SELECT st.*,
           ((p + 3.8416 / (2.0 * n) - 1.96 * SQRT(p * (1 - p) / n + 3.8416 / (4.0 * n * n))) / (1 + 3.8416 / n))  AS ci_low,
           ((p + 3.8416 / (2.0 * n) + 1.96 * SQRT(p * (1 - p) / n + 3.8416 / (4.0 * n * n))) / (1 + 3.8416 / n)) AS ci_high,
           (p - overall_p) / NULLIF(SQRT(overall_p * (1 - overall_p) / n), 0) AS z_score
    FROM stats st
)
SELECT RANK() OVER (ORDER BY p DESC, state) AS rank_by_rate,
       state,
       n AS transactions,
       x AS fraud_labelled,
       ROUND(100.0 * p, 3)         AS label_rate_pct,
       ROUND(100.0 * overall_p, 3) AS overall_rate_pct,
       ROUND(100.0 * ci_low, 3)    AS ci_low_pct,
       ROUND(100.0 * ci_high, 3)   AS ci_high_pct,
       ROUND(z_score, 2)           AS z_score,
       CASE WHEN ci_low  > overall_p THEN 'above overall (interval excludes overall)'
            WHEN ci_high < overall_p THEN 'below overall (interval excludes overall)'
            ELSE 'consistent with overall' END AS signal
FROM ci
ORDER BY rank_by_rate;
