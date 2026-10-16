# Clinical Encounter Dataset & Ingestion Pipeline

This directory documents the data provenance, schemas, and reproducible ETL pipeline used to populate `hospital_management_db`.

---

## 1. Primary Reference Dataset Source

The baseline clinical appointments were sourced and adapted from the public healthcare encounter dataset:
* **Dataset Name:** Medical Appointment No Shows
* **Publisher / Origin:** Kaggle / Brazilian Public Healthcare System (SUS)
* **Total Records in Source:** 110,527 outpatient records
* **Source Attributes:** `PatientId`, `AppointmentID`, `Gender`, `ScheduledDay`, `AppointmentDay`, `Age`, `Neighbourhood`, `Scholarship`, `Hipertension`, `Diabetes`, `Alcoholism`, `Handcap`, `SMS_received`, `No-show`

---

## 2. ETL Transformation & Expansion Pipeline (`etl_ingest_actual_data.py`)

Because the raw Kaggle dataset lacks physician identifiers, department assignments, shift timings, and billing ledgers, an automated Python ETL pipeline was engineered to expand the data into a realistic relational schema:

1. **Patient Extraction & Deduplication:**
   * Filtered distinct `PatientId`s and mapped them to synthetic Indian names with realistic date-of-birth timestamps derived from the `Age` attribute.
   * Ingested **326 unique patients** with phone and email profiles.

2. **Physician & Department Mapping:**
   * Linked patient clinical conditions (e.g., `Hipertension` &rarr; Cardiology; `Diabetes` &rarr; General Medicine; `Age < 18` &rarr; Pediatrics) to relevant clinical departments and attending doctors.
   * Ingested **629 outpatient appointments** strictly within doctors' valid shift rosters.

3. **Financial Billing Ledger Synthesis:**
   * For completed and attended visits, generated `invoices` based on doctor consultation tariffs (varying from ₹600 to ₹2,000).
   * Synthesized `payments` with realistic payment instrument distributions (UPI: 45%, Card: 30%, Cash: 15%, Net Banking: 10%).
   * Modeled partial payments and outstanding accounts receivable, producing a balanced ledger:
     * **Total Invoiced:** ₹2,91,700.00
     * **Total Collected:** ₹2,35,075.00
     * **Total Outstanding:** ₹56,625.00

---

## 3. How to Reproduce the Ingestion

To reproduce the dataset ingestion from scratch:
```bash
# 1. Initialize schema and extensions
psql -h 127.0.0.1 -p 5432 -U postgres -d hospital_management_db -f sql/01_extensions.sql
psql -h 127.0.0.1 -p 5432 -U postgres -d hospital_management_db -f sql/02_schema.sql
psql -h 127.0.0.1 -p 5432 -U postgres -d hospital_management_db -f sql/03_seed_data.sql
psql -h 127.0.0.1 -p 5432 -U postgres -d hospital_management_db -f sql/04_booking_rules.sql
psql -h 127.0.0.1 -p 5432 -U postgres -d hospital_management_db -f sql/05_billing_rules.sql
psql -h 127.0.0.1 -p 5432 -U postgres -d hospital_management_db -f sql/06_indexes_views.sql

# 2. Run the automated ETL pipeline
uv run --with "psycopg[binary]" python etl_ingest_actual_data.py
```
