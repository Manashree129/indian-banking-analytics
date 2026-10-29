/* =============================================================================
   01_schema_and_load.sql
   Project : Indian Banking Transactions Analytics & Risk Insights
   Target  : PostgreSQL 12 or later (written for pgAdmin 4 on Windows; no features newer than v12)
   Database: indian_banking  (create it first - see documentation/database_setup.md)

   DESIGN (two layers, so the raw data is never modified)
     raw_data.transactions_raw  every column stored as TEXT, exactly as in the CSV
                                (loaded as-is; never updated, never deleted from)
     banking.transactions       typed copy with constraints, built from the raw table

   TRANSFORMATIONS applied between the two layers (the complete list)
     1. Text -> DATE / TIME / NUMERIC / SMALLINT casts
     2. Nothing else. No rows are removed, no values are changed, nothing is imputed,
        and the literal text 'None' in loan_type stays the text 'None' (it is NOT
        converted to NULL). The 19,422 rows with has_loan = 1 and loan_type = 'None'
        are kept unchanged; they are investigated, not cleaned (see data_quality_report.md).
     If any value cannot be cast, the INSERT fails loudly and nothing is loaded.

   HOW TO RUN (important: pgAdmin runs a whole script as ONE transaction, so run the
   sections separately by selecting the text of one section and pressing F5)
     SECTION A  create schemas and the raw table                      (run once)
     STEP 2     load the CSV into raw_data.transactions_raw           (manual, see below)
     SECTION B  verify the raw load, build the typed table, index it  (run after STEP 2)
     SECTION C  post-load summary                                     (run last)

   STATUS: written and reviewed, NOT yet executed on a PostgreSQL server in the
   environment where it was authored. Execution results must be confirmed by the user.
   ============================================================================= */


/* =============================================================================
   SECTION A - schemas and raw table  (select from here to the end of SECTION A)
   ============================================================================= */
CREATE SCHEMA IF NOT EXISTS raw_data;
CREATE SCHEMA IF NOT EXISTS banking;

-- Column names and ORDER must match the CSV header exactly (the loader maps by position).
CREATE TABLE IF NOT EXISTS raw_data.transactions_raw (
    transaction_id        TEXT,
    customer_id           TEXT,
    transaction_date      TEXT,
    transaction_time      TEXT,
    account_type          TEXT,
    transaction_type      TEXT,
    transaction_amount    TEXT,
    transaction_direction TEXT,
    account_balance       TEXT,
    merchant_category     TEXT,
    state                 TEXT,
    credit_score          TEXT,
    has_loan              TEXT,
    loan_type             TEXT,
    emi_amount            TEXT,
    transaction_status    TEXT,
    channel               TEXT,
    kyc_status            TEXT,
    is_fraud              TEXT,
    transaction_hour      TEXT
);
/* END OF SECTION A */


/* =============================================================================
   STEP 2 - load the CSV into raw_data.transactions_raw   (manual; not SQL you run here)

   Before loading, the raw table must be empty (a second load would double the rows):
       SELECT COUNT(*) FROM raw_data.transactions_raw;      -- expect 0
   If it is not 0 and you want to reload from scratch:
       TRUNCATE TABLE raw_data.transactions_raw;

   OPTION 1 - pgAdmin Import/Export wizard (recommended on Windows)
     Object tree: indian_banking > Schemas > raw_data > Tables > transactions_raw
     Right-click the table > Import/Export Data...
       Import/Export : Import
       Filename      : browse to indian_banking_transactions.csv
       Format        : csv
       Encoding      : UTF8
       Options tab   : Header = ON, Delimiter = ",", Quote = '"', Escape = '"',
                       NULL Strings = leave EMPTY
       Columns tab   : all 20 columns selected, in the CSV order
     Click OK. Expected: "Successfully completed".

   OPTION 2 - psql \copy (SQL Shell, client-side so no server file permissions needed)
       \c indian_banking
       \copy raw_data.transactions_raw FROM 'C:/Users/YOUR_NAME/Downloads/indian_banking_transactions.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
     Use forward slashes in the path. \copy is a psql command, not SQL: it does not work
     in the pgAdmin Query Tool.

   Do not use server-side COPY ... FROM 'C:\...' unless you know the PostgreSQL service
   account can read that folder; "permission denied" is the usual failure.

   In both options only an EMPTY unquoted field is treated as NULL. The CSV has none, and
   the text None in loan_type is loaded as the five characters N-o-n-e.
   ============================================================================= */


/* =============================================================================
   SECTION B - verify the raw load, build the typed table  (select all of SECTION B)
   Runs as a single transaction: if anything fails, nothing in SECTION B is kept.
   ============================================================================= */

-- B1. Guard: stop with a clear message if the raw table does not hold the expected 550,000 rows.
DO $$
DECLARE
    n BIGINT;
BEGIN
    SELECT COUNT(*) INTO n FROM raw_data.transactions_raw;
    IF n <> 550000 THEN
        RAISE EXCEPTION 'raw_data.transactions_raw holds % rows; expected 550000. Re-run STEP 2 (TRUNCATE first if needed).', n;
    END IF;
END $$;

-- B2. Typed table. Rebuilt from the raw table every time SECTION B is run.
DROP VIEW  IF EXISTS banking.v_reconciliation_checks;
DROP TABLE IF EXISTS banking.transactions;

CREATE TABLE banking.transactions (
    transaction_id        VARCHAR(12)   NOT NULL,
    customer_id           VARCHAR(10)   NOT NULL,
    transaction_date      DATE          NOT NULL,
    transaction_time      TIME          NOT NULL,
    account_type          VARCHAR(20)   NOT NULL,
    transaction_type      VARCHAR(20)   NOT NULL,
    transaction_amount    NUMERIC(14,2) NOT NULL,
    transaction_direction VARCHAR(6)    NOT NULL,
    account_balance       NUMERIC(14,2) NOT NULL,
    merchant_category     VARCHAR(30)   NOT NULL,
    state                 VARCHAR(30)   NOT NULL,
    credit_score          SMALLINT      NOT NULL,
    has_loan              SMALLINT      NOT NULL,
    loan_type             VARCHAR(20)   NOT NULL,   -- literal text 'None' is kept as a value
    emi_amount            NUMERIC(12,2) NOT NULL,
    transaction_status    VARCHAR(10)   NOT NULL,
    channel               VARCHAR(15)   NOT NULL,
    kyc_status            VARCHAR(10)   NOT NULL,
    is_fraud              SMALLINT      NOT NULL,   -- supplied label, not confirmed fraud
    transaction_hour      SMALLINT      NOT NULL,

    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id),

    -- Rules that hold for every row of the supplied file (verified in Day 1 profiling).
    -- A future file that breaks one of them will fail to load, which is intentional.
    CONSTRAINT chk_amount_positive   CHECK (transaction_amount > 0),
    CONSTRAINT chk_balance_nonneg    CHECK (account_balance >= 0),
    CONSTRAINT chk_emi_nonneg        CHECK (emi_amount >= 0),
    CONSTRAINT chk_credit_score      CHECK (credit_score BETWEEN 300 AND 900),
    CONSTRAINT chk_hour_range        CHECK (transaction_hour BETWEEN 0 AND 23),
    CONSTRAINT chk_hour_matches_time CHECK (transaction_hour = EXTRACT(HOUR FROM transaction_time)),
    CONSTRAINT chk_has_loan_flag     CHECK (has_loan IN (0, 1)),
    CONSTRAINT chk_is_fraud_flag     CHECK (is_fraud IN (0, 1)),
    CONSTRAINT chk_direction         CHECK (transaction_direction IN ('Debit', 'Credit')),
    CONSTRAINT chk_status            CHECK (transaction_status IN ('Success', 'Failed', 'Reversed', 'Pending')),
    CONSTRAINT chk_kyc               CHECK (kyc_status IN ('Verified', 'Pending', 'Expired')),
    CONSTRAINT chk_channel           CHECK (channel IN ('Mobile_App', 'Web', 'ATM', 'POS_Terminal', 'Branch', 'API')),
    CONSTRAINT chk_account_type      CHECK (account_type IN ('Savings', 'Current', 'Salary', 'NRI', 'Fixed Deposit')),
    CONSTRAINT chk_transaction_type  CHECK (transaction_type IN ('UPI', 'IMPS', 'NEFT', 'POS', 'ATM_Withdrawal',
                                                                  'Net_Banking', 'RTGS', 'Auto_Debit', 'Cheque', 'Credit_Card')),
    CONSTRAINT chk_loan_type         CHECK (loan_type IN ('None', 'Personal', 'Home', 'Auto', 'Business', 'Education', 'Gold')),
    -- Someone without a loan must have loan_type 'None' and no EMI (true for all 357,712 such rows).
    -- The reverse is NOT enforced: 19,422 rows have has_loan = 1 and loan_type = 'None' (finding DQ-01).
    CONSTRAINT chk_no_loan_consistent CHECK (has_loan = 1 OR (loan_type = 'None' AND emi_amount = 0))
);

-- B3. Populate: casts only. ORDER BY keeps the table in file order.
INSERT INTO banking.transactions
SELECT transaction_id,
       customer_id,
       CAST(transaction_date AS DATE),
       CAST(transaction_time AS TIME),
       account_type,
       transaction_type,
       CAST(transaction_amount AS NUMERIC(14,2)),
       transaction_direction,
       CAST(account_balance AS NUMERIC(14,2)),
       merchant_category,
       state,
       CAST(credit_score AS SMALLINT),
       CAST(has_loan AS SMALLINT),
       loan_type,
       CAST(emi_amount AS NUMERIC(12,2)),
       transaction_status,
       channel,
       kyc_status,
       CAST(is_fraud AS SMALLINT),
       CAST(transaction_hour AS SMALLINT)
FROM raw_data.transactions_raw
ORDER BY transaction_id;

-- B4. Indexes for the analysis queries (built after the load; performance not benchmarked).
CREATE INDEX idx_transactions_date     ON banking.transactions (transaction_date);
CREATE INDEX idx_transactions_customer ON banking.transactions (customer_id);
CREATE INDEX idx_transactions_type     ON banking.transactions (transaction_type);
CREATE INDEX idx_transactions_channel  ON banking.transactions (channel);
CREATE INDEX idx_transactions_state    ON banking.transactions (state);

-- B5. Refresh planner statistics.
ANALYZE banking.transactions;
/* END OF SECTION B */


/* =============================================================================
   SECTION C - post-load summary  (run as its own statement)
   Expected: raw_rows = 550000, typed_rows = 550000, rows_lost = 0,
             loan_type_none = 377134, loan_type_null = 0
   ============================================================================= */
SELECT (SELECT COUNT(*) FROM raw_data.transactions_raw)                                AS raw_rows,
       (SELECT COUNT(*) FROM banking.transactions)                                     AS typed_rows,
       (SELECT COUNT(*) FROM raw_data.transactions_raw)
         - (SELECT COUNT(*) FROM banking.transactions)                                 AS rows_lost,
       (SELECT COUNT(*) FROM banking.transactions WHERE loan_type = 'None')            AS loan_type_none,
       (SELECT COUNT(*) FROM banking.transactions WHERE loan_type IS NULL)             AS loan_type_null,
       (SELECT TO_CHAR(MIN(transaction_date), 'YYYY-MM-DD') FROM banking.transactions) AS first_date,
       (SELECT TO_CHAR(MAX(transaction_date), 'YYYY-MM-DD') FROM banking.transactions) AS last_date;
