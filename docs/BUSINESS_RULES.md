# Business Rules & Implementation Traceability Matrix

This document defines the core business logic of the Hospital Appointment and Patient Management System and maps each rule directly to its PostgreSQL database enforcement mechanism and regression test suite.

---

## 1. Traceability Matrix

| Rule ID | Business Rule Description | Database Enforcement Mechanism | SQL Test / Verification |
| :---: | :--- | :--- | :--- |
| **BR-01** | **No Doctor Double-Booking**<br>A doctor cannot be scheduled for two overlapping appointments unless the prior appointment is cancelled. | `EXCLUDE USING gist (doctor_id WITH =, tstzrange(start_at, end_at, '[)') WITH &&)` on `appointments` | `tests/01_booking_conflict_tests.sql` (Test 1.1) |
| **BR-02** | **No Patient Simultaneous Bookings**<br>A patient cannot have two overlapping appointments across any doctors or departments. | `EXCLUDE USING gist (patient_id WITH =, tstzrange(start_at, end_at, '[)') WITH &&)` on `appointments` | `tests/01_booking_conflict_tests.sql` (Test 1.3) |
| **BR-03** | **Adjacent Slot Tolerance**<br>Back-to-back consecutive appointments (e.g., 09:00-09:30 and 09:30-10:00) must be accepted. | Half-open range interval `[)`: right boundary is open, meaning intersection with adjacent left boundary is empty. | `tests/01_booking_conflict_tests.sql` (Test 1.2) |
| **BR-04** | **Slot Reusability upon Cancellation**<br>When an appointment is cancelled, its time slot is immediately liberated for other patients. | `WHERE (status IN ('scheduled', 'confirmed', 'checked_in'))` in GiST constraint filters out `'cancelled'` status. | `tests/01_booking_conflict_tests.sql` (Test 1.4) |
| **BR-05** | **Doctor Shift Adherence**<br>Appointments must strictly fall within the attending doctor's declared weekly shift roster. | Trigger `trg_validate_doctor_shift` executing `fn_validate_doctor_shift_hours()` before insert/update. | `tests/05_concurrency_stress_test.py` |
| **BR-06** | **Referential Integrity on Deletions**<br>Active clinical departments or patient records with historical encounters cannot be dropped. | `ON DELETE RESTRICT` on foreign keys `fk_doctor_department` and `fk_appointment_patient`. | `tests/03_foreign_keys_and_checks.sql` (Test 3.5) |
| **BR-07** | **Single Invoice per Encounter**<br>An appointment can generate at most one invoice. | `UNIQUE(appointment_id)` on `invoices` enforcing strict `1:0..1` relationship. | `sql/02_schema.sql` line 200 |
| **BR-08** | **Overpayment Prevention with Concurrency Locking**<br>Payments exceeding the remaining invoice balance are strictly rejected, serialized via row locks. | Trigger `trg_validate_payment` with `SELECT ... FROM invoices WHERE invoice_id = NEW.invoice_id FOR UPDATE`. | `tests/02_billing_integrity_tests.sql` (Test 2.2) |
| **BR-09** | **Automatic Invoice Status Synchronization**<br>Invoice status dynamically transitions between `unpaid`, `partially_paid`, and `paid_in_full`. | Trigger `trg_sync_invoice_status` executing `fn_sync_invoice_status_after_payment()` on payment table mutations. | `tests/02_billing_integrity_tests.sql` (Tests 2.1, 2.3) |
| **BR-10** | **Immutable Financial Reversals**<br>Payments are never deleted. Refunds and dispute reversals are represented as reversal rows referencing original payment. | Self-referencing FK `reversed_payment_id` on `payments` and stored procedure `sp_reverse_payment`. | `tests/02_billing_integrity_tests.sql` (Test 2.5) |

---

## 2. In-Depth Technical Deep Dives

### 2.1 GiST Exclusion & The Race Condition Proof
Traditional application-level validation:
```sql
-- Step 1 (App checks availability):
SELECT count(*) FROM appointments WHERE doctor_id = 1 AND start_at < '10:30' AND end_at > '10:00';
-- Step 2 (App inserts if count == 0):
INSERT INTO appointments ...
```
**Vulnerability:** Between Step 1 and Step 2, a concurrent web request from another user can execute Step 1, also find `count == 0`, and proceed to Step 2, creating an overlapping double-booking.

**PostgreSQL GiST Solution:**
PostgreSQL's `btree_gist` builds an R-Tree index over `(doctor_id, tstzrange)`. When an `INSERT` executes, PostgreSQL's index engine acquires an exclusive index predicate lock on the range during page tuple insertion. If another concurrent backend tries to insert an intersecting bounding box, it is immediately blocked or aborted with `exclusion_violation` (SQLSTATE `23P01`).

### 2.2 Financial Concurrency & Balance Protection
```sql
CREATE OR REPLACE FUNCTION fn_validate_payment_against_balance()
RETURNS TRIGGER AS $$
DECLARE
    v_total_amount NUMERIC(10, 2);
    v_net_paid NUMERIC(10, 2);
    v_remaining_balance NUMERIC(10, 2);
BEGIN
    -- EXCLUSIVE ROW LOCK: Serializes concurrent payment attempts on the same invoice
    SELECT total_amount INTO v_total_amount
    FROM invoices
    WHERE invoice_id = NEW.invoice_id
    FOR UPDATE;

    SELECT COALESCE(SUM(amount), 0.00) INTO v_net_paid
    FROM payments
    WHERE invoice_id = NEW.invoice_id
      AND payment_type = 'payment'
      AND payment_id IS DISTINCT FROM NEW.payment_id;

    v_remaining_balance := v_total_amount - v_net_paid;

    IF NEW.payment_type = 'payment' AND NEW.amount > v_remaining_balance THEN
        RAISE EXCEPTION 'Payment Rejected: Amount (₹%) exceeds remaining invoice balance (₹%).',
            NEW.amount, v_remaining_balance
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```
By acquiring `FOR UPDATE` on the parent `invoices` row, if two users submit ₹600 payments concurrently for a ₹1,000 invoice (balance ₹1,000), Transaction B waits on the lock until Transaction A commits. Once Transaction A commits (balance now ₹400), Transaction B wakes up, recalculates `v_remaining_balance` as ₹400, and raises an exception.
