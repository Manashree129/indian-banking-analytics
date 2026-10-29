# PostgreSQL Setup, Loading and Reconciliation (Windows + pgAdmin 4)

**Status:** Day 2 setup, loading, reconciliation, and exploratory analysis have been completed using PostgreSQL 18, pgAdmin 4, and the `indian_banking` database. The instructions below document the setup process for reproducibility.

## What you will build

| Layer | Object | Purpose |
|---|---|---|
| Raw | `raw_data.transactions_raw` | All 20 columns as text, loaded from the CSV and preserved unchanged |
| Typed | `banking.transactions` | Same rows with appropriate types and constraints; the table used for analysis |
| Check | `banking.v_reconciliation_checks` | Read-only view with 72 reconciliation checks comparing Python reference values with PostgreSQL values |

No source rows were deleted, and no source values were cleaned, imputed, or corrected. The literal text `None` in `loan_type` remains text rather than being converted to SQL `NULL`.

## 1. Prerequisites

- PostgreSQL 12 or later with pgAdmin 4.
- The file `indian_banking_transactions.csv`, obtained from the same dataset version used for this project.
- Python 3 with pandas, if you want to run the optional independent comparison in Section 6.

## 2. Create the database

1. Open pgAdmin 4 and connect to your PostgreSQL server.
2. If the database does not already exist, right-click **Databases → Create → Database**.
3. Set the database name to `indian_banking` and choose the appropriate owner.
4. Click **Save**.
5. Select `indian_banking`, then open **Tools → Query Tool**.
6. Open `sql/01_schema_and_load.sql`.

If the database and tables have already been created, do not recreate them unnecessarily.

## 3. Create the schemas and raw table (Section A)

The setup script creates the `raw_data` and `banking` schemas and the raw table.

1. In `sql/01_schema_and_load.sql`, select the statements from `CREATE SCHEMA IF NOT EXISTS raw_data;` through the end of Section A.
2. Execute the selected statements using **F5**.
3. Refresh the schema tree in pgAdmin.
4. Confirm that the schemas and `raw_data.transactions_raw` table exist.

**Expected result:** Section A executes successfully.

## 4. Load the CSV

### Option 1: pgAdmin Import/Export

1. Check the raw table row count:

   ```sql
   SELECT COUNT(*)
   FROM raw_data.transactions_raw;
   ```

2. If this is a fresh load, the table should contain zero rows. If it already contains data, do not load the CSV again without first deciding whether a reload is necessary.
3. In the pgAdmin tree, locate `raw_data → Tables → transactions_raw`.
4. Right-click the table and select **Import/Export Data**.
5. Configure the import:

   | Field | Value |
   |---|---|
   | Import/Export | Import |
   | Filename | Path to your CSV |
   | Format | csv |
   | Encoding | UTF8 |
   | Header | On |
   | Delimiter | `,` |
   | Quote | `"` |
   | Escape | `"` |
   | NULL Strings | Leave empty |
   | Columns | All 20 columns in CSV order |

6. Click **OK** and wait for the import to finish.
7. Verify the result:

   ```sql
   SELECT COUNT(*)
   FROM raw_data.transactions_raw;
   ```

   **Expected result:** `550000`.

### Option 2: psql

If you prefer the PostgreSQL command-line client, connect to the database and run:

```sql
\c indian_banking

\copy raw_data.transactions_raw
FROM 'C:/data/indian_banking_transactions.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
```

The `\copy` command works in `psql`, not in the pgAdmin Query Tool.

**Important:** Leave the import dialog's NULL Strings field empty. Setting it to `None` would convert the dataset's 377,134 literal `None` values in `loan_type` into SQL NULLs and change the data.

## 5. Build the typed table and verify the load

### Section B — Create the typed table

The typed table is `banking.transactions`. The script explicitly converts the raw text columns to suitable PostgreSQL types, applies constraints, creates five additional indexes, and runs `ANALYZE`.

This section includes drop-and-recreate logic for the typed table. Execute it only when you intend to rebuild that table.

### Section C — Verify the load

The Section C summary query returned the following results:

| raw_rows | typed_rows | rows_lost | loan_type_none | loan_type_null | first_date | last_date |
|---:|---:|---:|---:|---:|---|---|
| 550000 | 550000 | 0 | 377134 | 0 | 2019-01-01 | 2024-01-01 |

The raw and typed tables both contain 550,000 rows, with no rows lost during loading. The literal `None` was preserved as text, and there are zero SQL NULLs in `loan_type`.

## 6. Data quality checks and exploratory analysis

### Data quality checks

The script `sql/02_data_quality_checks.sql` was executed in pgAdmin.

| Statement | Purpose | Result |
|---|---|---|
| Part 1 | Creates the reconciliation view | Executed successfully |
| Part 2a | Compares Python reference values with PostgreSQL values | All 72 checks returned `MATCH` |
| Part 2b | Summarizes matching and mismatching checks | 72 MATCH; 0 MISMATCH |
| Part 3 | Checks the date range | 2019-01-01 to 2024-01-01 |
| Part 4a | Inspects rows with `has_loan = 1` and `loan_type = 'None'` | Executed successfully |
| Part 4b | Inspects transactions at the maximum amount | Executed successfully |
| Part 5a–5c | Checks column types, constraints, and indexes | Executed successfully |

The metadata checks reported 20 columns, 37 constraints, and 6 indexes in total, including the primary-key index.

### Exploratory analysis

The script `sql/03_exploratory_analysis.sql` was executed successfully. All queries E01–E21 ran.

The queries cover transaction volumes, yearly trends, transaction status, channels, transaction types, merchant categories, states, account types, amount bands and percentiles, the supplied fraud label, hourly and monthly patterns, loan inconsistencies, KYC status, customer ID frequency, large transactions, amount-versus-balance comparisons, and weekday patterns.

The `is_fraud` field is treated as a **supplied label**, not confirmed fraud. Amounts associated with `is_fraud = 1` are not described as confirmed fraud losses.

### Optional independent comparison

The project includes a Python reference script:

```bash
pip install pandas

python python/reconciliation_reference.py --input data/raw/indian_banking_transactions.csv --compare 02_part2a_results.csv
```

The comparison expects the Part 2a results to have been exported to `02_part2a_results.csv`. The reference comparison script was also tested with a simulated export and a deliberately altered value to verify that it detects mismatches.

The SQLite logic cross-check is supplementary. It does not replace actual PostgreSQL execution.

## 7. Troubleshooting

| Message or symptom | Likely cause and response |
|---|---|
| `database "indian_banking" does not exist` | Create the database or check that the Query Tool is connected to the correct database. |
| Import dialog reports a utility or binary-path error | Check pgAdmin's PostgreSQL binary path settings. |
| `permission denied` or `could not open file` | Use pgAdmin Import/Export or `psql`'s `\copy` rather than server-side `COPY`. |
| `extra data after last expected column` or `missing data for column` | Check the delimiter, header option, column order, and table structure. |
| Row count is 1,100,000 | The CSV was likely loaded twice. Inspect the table before reloading. |
| Section B reports that the raw row count is not 550,000 | Check whether the import was incomplete or duplicated. |
| Section B fails on a CHECK constraint | Investigate whether the file differs from the version analysed. Do not remove constraints just to force the load to succeed. |
| `loan_type_none` is 0 and `loan_type_null` is 377134 | The import may have converted `None` to SQL NULL. Review the import settings and reload only if necessary. |
| Part 2a contains `MISMATCH` rows | Investigate the differences. Do not alter values merely to make the checks pass. |
| pgAdmin shows only one result grid | Run each query or selected statement separately. |

## 8. Reloading from scratch

**Warning:** Reloading deletes data from the raw table. Only do this if you intentionally want to reload the dataset.

To clear the raw table before importing again:

```sql
TRUNCATE TABLE raw_data.transactions_raw;
```

Then repeat the CSV import and the typed-table creation steps as appropriate.

To remove both schemas and all their objects:

```sql
DROP SCHEMA banking CASCADE;
DROP SCHEMA raw_data CASCADE;
```

**Warning:** These commands permanently delete the schemas, tables, views, indexes, and data stored in them. They do not delete the original CSV file.

## 9. Current project status

- PostgreSQL loading: Complete.
- Raw-to-typed reconciliation: Complete; 72 of 72 checks matched.
- Exploratory SQL: Complete; E01–E21 executed successfully.
- Data-quality investigation: Complete for the current Day 2 scope.
- Original dataset source, publisher, licence, and generation method: Still unverified.
- Advanced SQL, derived fields, and subsequent Excel, Power Query, and Power BI work: Planned for later project stages.
