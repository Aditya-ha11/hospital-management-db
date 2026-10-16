# Hospital Appointment and Management System — Data Dictionary

This document provides a comprehensive technical reference for all database entities, tables, columns, constraints, and views within `hospital_management_db`.

---

## 1. Relational Entities (Tables)

### 1.1 `departments`
Stores clinical hospital departments.

| Column | Type | Nullable | Default | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- | :--- |
| `department_id` | `BIGINT` | No | `GENERATED ALWAYS AS IDENTITY` | `PRIMARY KEY` | Unique surrogate identifier for the department. |
| `department_name` | `VARCHAR(100)` | No | — | `UNIQUE` | Department name (e.g., Cardiology, Neurology). |
| `description` | `TEXT` | Yes | — | — | Detailed clinical scope and medical specialty description. |
| `created_at` | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — | Timestamp of department creation. |

---

### 1.2 `doctors`
Stores credentialed medical practitioners and their consultation tariffs.

| Column | Type | Nullable | Default | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- | :--- |
| `doctor_id` | `BIGINT` | No | `GENERATED ALWAYS AS IDENTITY` | `PRIMARY KEY` | Unique identifier for the physician. |
| `department_id` | `BIGINT` | No | — | `FOREIGN KEY` (`departments.department_id`) `ON DELETE RESTRICT` | Associated clinical department. |
| `first_name` | `VARCHAR(80)` | No | — | — | Doctor given name. |
| `last_name` | `VARCHAR(80)` | No | — | — | Doctor family name. |
| `specialty` | `VARCHAR(100)` | No | — | — | Specific medical sub-specialty (e.g., Interventional Cardiology). |
| `consultation_fee` | `NUMERIC(10, 2)` | No | — | `CHECK (consultation_fee >= 0)` | Standard out-of-pocket consultation fee in INR (₹). |
| `email` | `VARCHAR(255)` | Yes | — | `UNIQUE` | Official hospital email address. |
| `is_active` | `BOOLEAN` | No | `TRUE` | — | Soft-delete flag; whether physician is actively accepting bookings. |
| `created_at` | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — | Record creation timestamp. |

---

### 1.3 `patients`
Stores demographic, contact, and registration profiles of patients.

| Column | Type | Nullable | Default | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- | :--- |
| `patient_id` | `BIGINT` | No | `GENERATED ALWAYS AS IDENTITY` | `PRIMARY KEY` | Unique patient medical record number (MRN). |
| `first_name` | `VARCHAR(80)` | No | — | — | Patient given name. |
| `last_name` | `VARCHAR(80)` | No | — | — | Patient family name. |
| `date_of_birth` | `DATE` | Yes | — | `CHECK (date_of_birth <= CURRENT_DATE)` | Birthdate for age-cohort analytics and pediatric routing. |
| `phone` | `VARCHAR(20)` | Yes | — | — | Verified contact telephone number. |
| `email` | `VARCHAR(255)` | Yes | — | `UNIQUE` | Contact email address. |
| `created_at` | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — | Patient registration timestamp. |

---

### 1.4 `doctor_availability`
Rosters recurring weekly working shifts for physicians.

| Column | Type | Nullable | Default | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- | :--- |
| `availability_id` | `BIGINT` | No | `GENERATED ALWAYS AS IDENTITY` | `PRIMARY KEY` | Unique shift schedule identifier. |
| `doctor_id` | `BIGINT` | No | — | `FOREIGN KEY` (`doctors.doctor_id`) `ON DELETE RESTRICT` | Doctor assigned to this shift. |
| `weekday` | `SMALLINT` | No | — | `CHECK (weekday BETWEEN 0 AND 6)` | Day of week (`0=Sun`, `1=Mon`, ..., `6=Sat`). |
| `start_time` | `TIME` | No | — | — | Shift start time in local hospital timezone. |
| `end_time` | `TIME` | No | — | `CHECK (start_time < end_time)` | Shift concluding time. |

*Table Constraints:* `UNIQUE (doctor_id, weekday, start_time, end_time)`.

---

### 1.5 `appointments`
Encounter scheduling ledger protected by PostgreSQL GiST exclusion constraints.

| Column | Type | Nullable | Default | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- | :--- |
| `appointment_id` | `BIGINT` | No | `GENERATED ALWAYS AS IDENTITY` | `PRIMARY KEY` | Unique booking encounter identifier. |
| `patient_id` | `BIGINT` | No | — | `FOREIGN KEY` (`patients.patient_id`) `ON DELETE RESTRICT` | Booked patient. |
| `doctor_id` | `BIGINT` | No | — | `FOREIGN KEY` (`doctors.doctor_id`) `ON DELETE RESTRICT` | Attending doctor. |
| `start_at` | `TIMESTAMPTZ` | No | — | — | Appointment commencement timestamp. |
| `end_at` | `TIMESTAMPTZ` | No | — | `CHECK (start_at < end_at)` | Appointment conclusion timestamp. |
| `status` | `VARCHAR(20)` | No | `'scheduled'` | `CHECK (status IN ('scheduled', 'confirmed', 'checked_in', 'completed', 'cancelled'))` | Clinical status lifecycle. |
| `reason` | `VARCHAR(255)` | Yes | — | — | Chief complaint or encounter objective. |
| `created_at` | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — | Timestamp booking was submitted. |
| `updated_at` | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — | Timestamp of last status or timing update. |

*Storage-Level Exclusion Constraints:*
1. `no_doctor_overlapping_appointments`: `EXCLUDE USING gist (doctor_id WITH =, tstzrange(start_at, end_at, '[)') WITH &&) WHERE (status IN ('scheduled', 'confirmed', 'checked_in'))`
2. `no_patient_overlapping_appointments`: `EXCLUDE USING gist (patient_id WITH =, tstzrange(start_at, end_at, '[)') WITH &&) WHERE (status IN ('scheduled', 'confirmed', 'checked_in'))`

---

### 1.6 `appointment_audit_log`
Immutable audit log tracking all modifications, reschedules, and cancellations.

| Column | Type | Nullable | Default | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- | :--- |
| `audit_id` | `BIGINT` | No | `GENERATED ALWAYS AS IDENTITY` | `PRIMARY KEY` | Unique audit event log sequence. |
| `appointment_id` | `BIGINT` | No | — | `FOREIGN KEY` (`appointments.appointment_id`) `ON DELETE CASCADE` | Target appointment tracked. |
| `action_type` | `VARCHAR(20)` | No | — | — | Action: `'INSERT'`, `'UPDATE_STATUS'`, `'RESCHEDULE'`, `'CANCEL'`. |
| `old_status` | `VARCHAR(20)` | Yes | — | — | Pre-update appointment status. |
| `new_status` | `VARCHAR(20)` | Yes | — | — | Post-update appointment status. |
| `old_start_at` | `TIMESTAMPTZ` | Yes | — | — | Prior commencement time before rescheduling. |
| `new_start_at` | `TIMESTAMPTZ` | Yes | — | — | Updated commencement time. |
| `changed_by` | `VARCHAR(80)` | Yes | `CURRENT_USER` | — | Database session role performing mutation. |
| `changed_at` | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — | Audit event occurrence timestamp. |
| `notes` | `TEXT` | Yes | — | — | Cancellation reason or system message. |

---

### 1.7 `invoices`
Billing ledger records issued for hospital encounters.

| Column | Type | Nullable | Default | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- | :--- |
| `invoice_id` | `BIGINT` | No | `GENERATED ALWAYS AS IDENTITY` | `PRIMARY KEY` | Unique invoice number. |
| `appointment_id` | `BIGINT` | No | — | `FOREIGN KEY` (`appointments.appointment_id`) `ON DELETE RESTRICT`, `UNIQUE` | 1:0..1 encounter coupling. |
| `total_amount` | `NUMERIC(10, 2)` | No | — | `CHECK (total_amount >= 0)` | Billed amount in INR (₹). |
| `status` | `VARCHAR(20)` | No | `'unpaid'` | `CHECK (status IN ('unpaid', 'partially_paid', 'paid_in_full', 'reversed'))` | Synchronized billing lifecycle status. |
| `issued_at` | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — | Invoicing timestamp. |
| `due_date` | `DATE` | Yes | — | `CHECK (due_date >= issued_at::DATE)` | Payment remittance deadline. |

---

### 1.8 `payments`
Transaction-safe cash flow ledger supporting partial payments and reversals.

| Column | Type | Nullable | Default | Constraints | Description |
| :--- | :--- | :---: | :--- | :--- | :--- |
| `payment_id` | `BIGINT` | No | `GENERATED ALWAYS AS IDENTITY` | `PRIMARY KEY` | Transaction ledger identifier. |
| `invoice_id` | `BIGINT` | No | — | `FOREIGN KEY` (`invoices.invoice_id`) `ON DELETE RESTRICT` | Target invoice settled. |
| `amount` | `NUMERIC(10, 2)` | No | — | `CHECK (amount > 0)` | Payment transaction amount in INR (₹). |
| `payment_type` | `VARCHAR(20)` | No | `'payment'` | `CHECK (payment_type IN ('payment', 'refund', 'reversal'))` | Transaction category. |
| `payment_method` | `VARCHAR(20)` | No | — | `CHECK (payment_method IN ('cash', 'card', 'upi', 'bank_transfer', 'insurance'))` | Settlement instrument. |
| `paid_at` | `TIMESTAMPTZ` | No | `CURRENT_TIMESTAMP` | — | Transaction processing timestamp. |
| `reference_code` | `VARCHAR(100)` | Yes | — | `UNIQUE` | External banking gateway transaction reference. |
| `reversed_payment_id` | `BIGINT` | Yes | — | `FOREIGN KEY` (`payments.payment_id`) `ON DELETE RESTRICT` | Pointer to original transaction if reversed. |

---

## 2. Dynamic Views

### 2.1 `v_appointment_schedules`
Denormalized operational view joining appointments with patients, doctors, and departments. Includes computed duration in minutes.

### 2.2 `v_invoice_ledger`
High-concurrency financial view that uses a pre-aggregated CTE to sum payments per invoice *before* joining to the parent record. This guarantees zero-fanout duplicate elimination, computing exact `total_paid`, `outstanding_balance`, `payment_status`, and `is_overdue` flags.
