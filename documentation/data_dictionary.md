# Data Dictionary

Source file: `indian_banking_transactions.csv` (550,000 rows, 20 columns). All profile figures were measured from the supplied file on 2026-10-28.

**How to read this document.** No publisher documentation was found (see `source_and_provenance.md`). The "Meaning" column is therefore an interpretation based on column names and observed values. Where a meaning is uncertain it is marked **Assumed** or **Undocumented**. Nothing here comes from the publisher.

Raw values are stored as text in the CSV. "Suggested PostgreSQL type" is a Day 2 design proposal, not a decision yet.

## Columns

| # | Column | Observed type | Suggested PostgreSQL type | Distinct | Missing | Meaning (status) | Observed values / range |
|---|---|---|---|---|---|---|---|
| 1 | `transaction_id` | text | `VARCHAR(12)` PRIMARY KEY | 550,000 | 0 | Unique transaction identifier (Verified unique) | `TXN000000001` to `TXN000550000`, no gaps |
| 2 | `customer_id` | text | `VARCHAR(10)` | 79,916 | 0 | Customer identifier (**Assumed**; see note 1) | `CUST` + 6 digits; 1 to 20 rows per ID, median 7 |
| 3 | `transaction_date` | text `YYYY-MM-DD` | `DATE` | 1,827 | 0 | Calendar date of the transaction | 2019-01-01 to 2024-01-01 |
| 4 | `transaction_time` | text `HH:MM` | `TIME` | 1,440 | 0 | Time of day, minute precision (time zone **Undocumented**) | 00:00 to 23:59 |
| 5 | `account_type` | text | `VARCHAR(20)` | 5 | 0 | Type of the account (Assumed) | Savings 219,651; Current 137,648; Salary 110,067; NRI 43,746; Fixed Deposit 38,888 |
| 6 | `transaction_type` | text | `VARCHAR(20)` | 10 | 0 | Payment method or instrument (Assumed) | UPI 153,986; IMPS 77,038; NEFT 66,615; POS 60,278; ATM_Withdrawal 55,106; Net_Banking 38,458; RTGS 32,964; Auto_Debit 27,418; Cheque 21,711; Credit_Card 16,426 |
| 7 | `transaction_amount` | decimal | `NUMERIC(14,2)` | 374,552 | 0 | Amount of the transaction. Currency **Undocumented** (INR assumed) | 2.40 to 10,000,000.00; mean 29,907.09; median 2,035.74; 4 rows at exactly 10,000,000.00 |
| 8 | `transaction_direction` | text | `VARCHAR(6)` | 2 | 0 | Money in (Credit) or out (Debit) from the account's perspective (Assumed) | Debit 370,394; Credit 179,606 |
| 9 | `account_balance` | decimal | `NUMERIC(14,2)` | 536,170 | 0 | Account balance. Whether before or after the transaction is **Undocumented** | 500.00 to 5,000,000.00; 288 rows at 500.00; 38 rows at 5,000,000.00 |
| 10 | `merchant_category` | text | `VARCHAR(30)` | 15 | 0 | Spending or purpose category (Assumed) | Retail 66,180; Food & Dining 54,776; E-Commerce 54,767; Travel 44,177; Salary 43,937; Peer Transfer 38,753; Utilities 38,575; Healthcare 33,015; Entertainment 32,997; Government 27,508; Investment 27,380; Education 27,359; Insurance 22,020; Fuel 21,929; Real Estate 16,627 |
| 11 | `state` | text | `VARCHAR(30)` | 10 | 0 | Indian state or territory (Assumed to be customer or transaction location; **Undocumented**) | Maharashtra 98,911; Karnataka 76,659; Tamil Nadu 71,747; Delhi 66,114; Gujarat 54,798; Telangana 49,610; West Bengal 43,950; Rajasthan 38,725; UP 27,414; Punjab 22,072 |
| 12 | `credit_score` | integer | `SMALLINT` | 600 | 0 | Credit score (scale assumed to be 300-900) | 300 to 899; mean 599.8; median 600 |
| 13 | `has_loan` | integer flag | `SMALLINT` (0/1) | 2 | 0 | 1 if the customer has a loan (Assumed) | 0: 357,712; 1: 192,288 |
| 14 | `loan_type` | text | `VARCHAR(20)` | 7 | 0 | Type of loan. The literal text `None` means "no loan type recorded" (see note 2) | None 377,134; Personal 47,810; Home 38,252; Auto 29,219; Business 28,863; Education 19,074; Gold 9,648 |
| 15 | `emi_amount` | decimal | `NUMERIC(12,2)` | 177,524 | 0 | Monthly loan instalment (EMI) (Assumed) | 0 for every `has_loan = 0` row; 185.94 to 153,325.74 where positive |
| 16 | `transaction_status` | text | `VARCHAR(10)` | 4 | 0 | Outcome of the transaction | Success 506,247 (92.04%); Failed 21,905 (3.98%); Reversed 11,019 (2.00%); Pending 10,829 (1.97%) |
| 17 | `channel` | text | `VARCHAR(15)` | 6 | 0 | Channel through which the transaction was made (Assumed) | Mobile_App 208,368; Web 121,010; ATM 66,177; POS_Terminal 60,853; Branch 54,957; API 38,635 |
| 18 | `kyc_status` | text | `VARCHAR(10)` | 3 | 0 | Know-Your-Customer verification state (Assumed) | Verified 483,457; Pending 44,288; Expired 22,255 |
| 19 | `is_fraud` | integer flag | `SMALLINT` (0/1) | 2 | 0 | **Supplied label.** Method of assignment is undocumented. Not confirmed fraud | 0: 545,127; 1: 4,873 (0.886%) |
| 20 | `transaction_hour` | integer | `SMALLINT` | 24 | 0 | Hour of day (0-23) | Equals the hour part of `transaction_time` in all 550,000 rows |

## Notes

**Note 1 - `customer_id` is not a stable customer profile.** Customer-level attributes change from row to row within the same `customer_id`: of 79,916 IDs, 78,998 have more than one `state`, 77,937 more than one `account_type`, 79,334 more than one `credit_score`, 71,922 more than one `has_loan` value and 45,037 more than one `kyc_status`. Consequences for the project:

- "Distinct customer IDs" can be reported as a count of distinct ID values only. It must not be labelled "unique customers" or "customers who ..." until the meaning of the ID is documented.
- Customer-level analysis (retention, lifetime value, customer segmentation, loan-holder behaviour) is not defensible from this file. Analysis stays at transaction level.

**Note 2 - the text `None` in `loan_type`.** The CSV contains the five-character text `None`, not an empty cell. Pandas, Power Query and some database loaders can convert it to a missing value. In this project:

- Python reads with `keep_default_na=False`.
- Day 2 PostgreSQL loading must keep `'None'` as text and not convert it to NULL (to be decided and documented in `01_schema_and_load.sql`).
- Power Query must treat it as a value, not as null.

**Note 3 - `has_loan`, `loan_type` and `emi_amount`.**

| | `loan_type` = 'None' | `loan_type` = named type | Total |
|---|---:|---:|---:|
| `has_loan` = 0 | 357,712 | 0 | 357,712 |
| `has_loan` = 1 | **19,422** | 172,866 | 192,288 |
| Total | 377,134 | 172,866 | 550,000 |

All 19,422 exceptional rows have `emi_amount > 0` (min 211.47, median 4,872.50). The cause is not documented; see `data_quality_report.md`, issue DQ-01.

**Note 4 - `is_fraud`.** Throughout the project, `is_fraud = 1` is called "fraud-labelled". Amounts on those rows are "amounts on fraud-labelled transactions", not "fraud losses".

## Derived fields planned for later days (not in the source file)

These do not exist in the CSV. They will be created in SQL or Power Query and clearly named as derived.

| Planned field | Definition | Day |
|---|---|---|
| `transaction_ts` | `transaction_date + transaction_time` as a timestamp | 2 |
| `amount_band` | Banded `transaction_amount` (band edges to be set after distribution review) | 3 |
| `loan_type_clean` | `loan_type` with the 19,422 exception rows labelled "Loan - type not recorded" (original column preserved) | 3-4 |
