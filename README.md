# Data

## Dataset used

| Item | Value |
|---|---|
| File | `indian_banking_transactions.csv` (supplied inside `archive.zip`) |
| Size | 550,000 rows x 20 columns; 79,702,197 bytes (CSV), 18,260,840 bytes (ZIP) |
| Coverage | 2019-01-01 to 2024-01-01 (historical; not current banking activity) |
| ZIP SHA-256 | `c11e7924d2bc5f89f59f1fa39d23403ef16c8319898fb06c12b158f3fd4261c1` |
| CSV SHA-256 | `995498d3efc3813dda9d4366e12df81a48276b4abcb7023a1a55f974c664d71b` |

## Source and licence: TO BE COMPLETED BY THE PROJECT OWNER

The original publisher, page URL and licence **could not be verified** during Day 1 (see [`documentation/source_and_provenance.md`](../documentation/source_and_provenance.md)). Fill in the following from the page you downloaded the file from:

- Dataset name and URL: `<to be added>`
- Author / publisher: `<to be added>`
- Licence shown on the page: `<to be added>`
- Description of how the data was generated (real / anonymised / synthetic): `<to be added>`
- Date downloaded: `<to be added>`

## Redistribution

The CSV is **not included in this repository** and `data/raw/` is excluded by `.gitignore`. Do not commit the file unless the licence explicitly permits redistribution.

## How to obtain and place the data

1. Download the dataset from the original source above and unzip it.
2. Create the folder `data/raw/` and place `indian_banking_transactions.csv` inside it.
3. Check the file matches the one analysed: compute its SHA-256 and compare with the value above.

   ```bash
   # Linux / macOS
   sha256sum data/raw/indian_banking_transactions.csv
   # Windows PowerShell
   Get-FileHash data\raw\indian_banking_transactions.csv -Algorithm SHA256
   ```

   If the hash differs, the file is a different version and the figures in this project may not match.
4. Run the Python checks:

   ```bash
   pip install pandas
   python python/data_profiling.py  --input data/raw/indian_banking_transactions.csv
   python python/data_validation.py --input data/raw/indian_banking_transactions.csv
   ```

## Reading the file safely

`loan_type` contains the literal text `None`. Default readers (pandas, Power Query type detection, some SQL loaders) may convert it to a missing value. The project scripts preserve it as text.
