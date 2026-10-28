# Source and Provenance

**Status: provenance NOT verified.** The original publisher, licence and generation method of this dataset could not be confirmed. This page separates what was verified from the supplied file from what is unknown, so that nothing unverified is presented as fact.

Last reviewed: 2026-10-28.

## 1. Verified from the supplied file

These facts were measured directly from the uploaded archive (see `python/data_profiling.py` and `documentation/evidence/day1_profiling_output.txt`).

| Item | Verified value |
|---|---|
| Archive name | `archive.zip` (18,260,840 bytes) |
| Archive SHA-256 | `c11e7924d2bc5f89f59f1fa39d23403ef16c8319898fb06c12b158f3fd4261c1` |
| Files inside | One file: `indian_banking_transactions.csv` (79,702,197 bytes uncompressed) |
| CSV SHA-256 | `995498d3efc3813dda9d4366e12df81a48276b4abcb7023a1a55f974c664d71b` |
| File timestamp inside ZIP | 2026-04-07 04:43 (this is the archive entry date, not proof of when the data was created) |
| Format | ASCII CSV, comma-separated, header row, 550,000 data rows, 20 columns |
| Date range | 2019-01-01 to 2024-01-01 (every one of the 1,827 calendar days present) |
| Fraud-labelled rows | 4,873 (0.886%) |

Record the SHA-256 values with any published results so that anyone can confirm they are using the same file.

## 2. Observations consistent with simulated data (not proof)

None of the following proves the data is synthetic, and none proves it is real. They are listed because they affect how the results may be described.

- `transaction_id` runs `TXN000000001` to `TXN000550000` with no gaps, in date order.
- Transactions are spread almost evenly across weekdays (about 78,300-78,800 rows each) and across years (about 110,000 per year for 2019-2023).
- The fraud-labelled count is almost flat by year (968, 972, 990, 960, 981 for 2019-2023).
- Fraud-label rates are close to flat across the 24 hours of the day, across channels and across states.
- `customer_id` values do not keep a stable state, account type, credit score or loan status from one row to the next (79,334 of 79,916 customers show more than one credit score). Real bank customers do not behave like this.
- Maximum and minimum values repeat (4 transactions of exactly 10,000,000.00; 38 balances of exactly 5,000,000.00; 288 balances of exactly 500.00), which suggests values were capped or floored by a generator or a processing step.

Reasonable working position: **treat the data as simulated or heavily processed unless the publisher states otherwise.** Describe findings as "patterns in this dataset", not as facts about Indian banking.

## 3. Not verified (unknown)

| Question | Status |
|---|---|
| Who published the dataset | Not confirmed |
| Original platform and page URL | Not confirmed |
| Licence and redistribution terms | **Not confirmed** |
| Whether the data is real, anonymised, simulated or synthetic | Not confirmed |
| How `is_fraud` was assigned | Not documented |
| Currency and units of `transaction_amount`, `account_balance`, `emi_amount` | Not documented (INR is assumed, see data dictionary) |
| Meaning of `account_balance` (before or after the transaction) | Not documented |
| Meaning of `loan_type = 'None'` when `has_loan = 1` | Not documented |
| Whether the CSV was altered after publication | Not known |

## 4. What was searched

Web searches on 2026-10-28 for the filename `indian_banking_transactions.csv`, the 550,000-row size and the column set returned **no page that could be matched to this file**. The results were other datasets (for example an Indian banking narration text dataset, a different Indian financial fraud dataset, PaySim and several Kaggle/Mendeley synthetic banking datasets). Those are different datasets, and their licences and descriptions must not be attributed to this one.

The preliminary baseline supplied with the project brief (about 550,000 rows, 20 columns, 4,873 fraud-labelled records) matches the file. That confirms the file matches the brief; it does not identify the publisher.

## 5. Action required from you

1. Check where you downloaded the file (the Kaggle page, repository or link). Copy the dataset page URL, author name, the licence shown on the page, and the "About Dataset" text into `data/README.md`.
2. If the page calls the data synthetic or simulated, say so in the README. If it gives no description, keep the wording "provenance not verified".
3. If no licence is shown, or it forbids redistribution, do **not** commit the CSV to a public repository. The repository's `.gitignore` already excludes `data/raw/`.

## 6. Wording to use until provenance is confirmed

> The dataset was obtained as `archive.zip` containing `indian_banking_transactions.csv`. Its original publisher, licence and generation method have not been independently verified, and several characteristics suggest it may be simulated. Results describe patterns within this dataset only. The dataset covers 2019-01-01 to 2024-01-01 and says nothing about current (2025-2026) banking activity. `is_fraud` is a supplied label and is not treated as confirmed fraud.
