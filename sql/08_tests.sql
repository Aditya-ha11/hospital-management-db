-- =============================================================================
-- Hospital Appointment and Patient Management System
-- File: sql/08_tests.sql
-- Description: Automated SQL regression test suite asserting all database constraints,
--              concurrency rules, trigger logic, and mathematical financial reconciliation.
-- =============================================================================

DO $$
DECLARE
    v_appt_id BIGINT;
    v_appt_id2 BIGINT;
    v_inv_id BIGINT;
    v_pay_id BIGINT;
    v_rev_id BIGINT;
    v_audit_count INT;
    v_discrepancy NUMERIC(10, 2);
BEGIN
    RAISE NOTICE '============================================================';
    RAISE NOTICE 'STARTING AUTOMATED REGRESSION & INTEGRITY TEST SUITE';
    RAISE NOTICE '============================================================';

    -- -------------------------------------------------------------------------
    -- TEST 1: Foreign Key Enforcement (Invalid Department)
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO doctors (department_id, first_name, last_name, specialty, consultation_fee, email)
        VALUES (99999, 'Invalid', 'DeptDoctor', 'General', 500.00, 'invalid.dept@hospital.org');
        RAISE EXCEPTION 'TEST 1 FAILED: Foreign key did not reject department_id 99999';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE '[PASS] Test 01: Foreign key fk_doctor_department correctly rejected invalid department.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 2: CHECK Constraint: Consultation Fee Non-Negative
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO doctors (department_id, first_name, last_name, specialty, consultation_fee, email)
        VALUES (1, 'Negative', 'FeeDoctor', 'Cardiology', -250.00, 'neg.fee.test@hospital.org');
        RAISE EXCEPTION 'TEST 2 FAILED: Check constraint allowed negative fee';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '[PASS] Test 02: Check constraint chk_consultation_fee correctly rejected negative fee.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 3: CHECK Constraint: Patient DOB Must Be <= CURRENT_DATE
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO patients (first_name, last_name, date_of_birth, phone, email)
        VALUES ('Future', 'Patient', CURRENT_DATE + 5, '+91-9999999999', 'future.patient.test@hospital.org');
        RAISE EXCEPTION 'TEST 3 FAILED: Check constraint allowed future DOB';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '[PASS] Test 03: Check constraint chk_patient_dob correctly rejected future birthdate.';
    END;

    -- -------------------------------------------------------------------------
    -- Establish Baseline Booking for Tests 4, 5, 6, 7
    -- Idempotent pre-cleanup ensures repeatability across repeated runs
    -- -------------------------------------------------------------------------
    DELETE FROM payments WHERE invoice_id IN (
        SELECT invoice_id FROM invoices WHERE appointment_id IN (
            SELECT appointment_id FROM appointments WHERE start_at >= '2026-12-07 00:00:00+05:30' AND start_at < '2026-12-08 00:00:00+05:30'
        )
    );
    DELETE FROM invoices WHERE appointment_id IN (
        SELECT appointment_id FROM appointments WHERE start_at >= '2026-12-07 00:00:00+05:30' AND start_at < '2026-12-08 00:00:00+05:30'
    );
    DELETE FROM appointments WHERE start_at >= '2026-12-07 00:00:00+05:30' AND start_at < '2026-12-08 00:00:00+05:30';

    INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
    VALUES (1, 1, '2026-12-07 09:00:00+05:30', '2026-12-07 09:30:00+05:30', 'scheduled', 'Initial Baseline Slot A')
    RETURNING appointment_id INTO v_appt_id;

    -- -------------------------------------------------------------------------
    -- TEST 4: GiST Exclusion: Doctor Overlapping Bookings Rejected
    -- -------------------------------------------------------------------------
    BEGIN
        -- Attempt overlapping slot: 09:15 to 09:45 with same Doctor 1 (overlaps 09:00-09:30)
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (2, 1, '2026-12-07 09:15:00+05:30', '2026-12-07 09:45:00+05:30', 'scheduled', 'Overlapping Slot')
        RETURNING appointment_id INTO v_appt_id2;

        RAISE EXCEPTION 'TEST 4 FAILED: GiST exclusion allowed overlapping booking for Doctor 1!';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE '[PASS] Test 04: no_doctor_overlapping_appointments blocked doctor double-booking.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 5: GiST Exclusion: Patient Simultaneous Bookings Rejected
    -- -------------------------------------------------------------------------
    BEGIN
        -- Patient 1 is booked 09:00-09:30 with Doctor 1.
        -- Attempt to book Patient 1 at 09:10-09:40 with Doctor 3 (Neurology - Monday shift 08:00-12:00)
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (1, 3, '2026-12-07 09:10:00+05:30', '2026-12-07 09:40:00+05:30', 'scheduled', 'Patient Double Booking');

        RAISE EXCEPTION 'TEST 5 FAILED: GiST exclusion allowed simultaneous booking for Patient 1!';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE '[PASS] Test 05: no_patient_overlapping_appointments blocked patient simultaneous booking.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 6: Half-Open Range '[)' Boundary Tolerance (Adjacent Consecutive Slots)
    -- -------------------------------------------------------------------------
    BEGIN
        -- Doctor 1 is booked 09:00 to 09:30.
        -- Consecutive slot: 09:30 to 10:00 MUST BE ACCEPTED without error.
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (3, 1, '2026-12-07 09:30:00+05:30', '2026-12-07 10:00:00+05:30', 'scheduled', 'Consecutive Slot B');

        RAISE NOTICE '[PASS] Test 06: Half-open range ''[)'' correctly accepted consecutive meeting boundary.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 7: Slot Liberation on Cancellation
    -- -------------------------------------------------------------------------
    BEGIN
        -- Cancel appointment A (09:00 - 09:30)
        UPDATE appointments SET status = 'cancelled' WHERE appointment_id = v_appt_id;

        -- Now another patient books the EXACT same slot (09:00 - 09:30)
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (4, 1, '2026-12-07 09:00:00+05:30', '2026-12-07 09:30:00+05:30', 'scheduled', 'Re-booked Slot A');

        RAISE NOTICE '[PASS] Test 07: Slot liberation succeeded; cancelled slot was immediately re-bookable.';
    END;

    -- -------------------------------------------------------------------------
    -- Establish Test Invoice of ₹1,000 and Baseline Partial Payment of ₹600
    -- -------------------------------------------------------------------------
    INSERT INTO invoices (appointment_id, total_amount, due_date)
    VALUES (v_appt_id, 1000.00, CURRENT_DATE + 14)
    RETURNING invoice_id INTO v_inv_id;

    INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
    VALUES (v_inv_id, 600.00, 'cash', 'TEST-PAY-01')
    RETURNING payment_id INTO v_pay_id;

    -- -------------------------------------------------------------------------
    -- TEST 08: Trigger Overpayment Protection (Business Rule 8)
    -- Remaining balance is ₹400. Attempt to pay ₹500 MUST FAIL with check_violation.
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
        VALUES (v_inv_id, 500.00, 'card', 'TEST-PAY-OVERPAY');

        RAISE EXCEPTION 'TEST 8 FAILED: Trigger allowed overpayment of ₹500 on ₹400 balance!';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '[PASS] Test 08: trg_validate_payment correctly blocked overpayment exceeding balance.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 09: Payment Reversal (Refund) & Balance Recalculation
    -- Reverses the ₹600 payment, restoring remaining balance back to ₹1,000.
    -- -------------------------------------------------------------------------
    BEGIN
        -- Call reversal procedure
        CALL sp_reverse_payment(v_pay_id, 'Patient overcharged / billing dispute', v_rev_id);

        -- After reversing ₹600, the remaining balance is ₹1,000.
        -- A payment of ₹1,000 MUST SUCCEED without triggering overpayment.
        INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
        VALUES (v_inv_id, 1000.00, 'upi', 'TEST-PAY-SETTLED');

        RAISE NOTICE '[PASS] Test 09: Payment reversal sp_reverse_payment restored invoice balance correctly.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 10: Appointment Audit Trail Verification
    -- -------------------------------------------------------------------------
    BEGIN
        SELECT COUNT(*) INTO v_audit_count 
        FROM appointment_audit_log 
        WHERE appointment_id = v_appt_id;

        IF v_audit_count >= 2 THEN
            RAISE NOTICE '[PASS] Test 10: appointment_audit_log captured lifecycle history (% events logged).', v_audit_count;
        ELSE
            RAISE EXCEPTION 'TEST 10 FAILED: Expected at least 2 audit entries, found %', v_audit_count;
        END IF;
    END;

    -- -------------------------------------------------------------------------
    -- TEST 11: Zero-Discrepancy Mathematical Reconciliation Audit
    -- -------------------------------------------------------------------------
    BEGIN
        SELECT 
            (SELECT COALESCE(SUM(total_amount), 0.00) FROM invoices) -
            ((SELECT COALESCE(SUM(amount), 0.00) FROM payments WHERE payment_type = 'payment') -
             (SELECT COALESCE(SUM(amount), 0.00) FROM payments WHERE payment_type = 'reversal') +
             (SELECT COALESCE(SUM(outstanding_balance), 0.00) FROM v_invoice_ledger))
        INTO v_discrepancy;

        IF v_discrepancy = 0.00 THEN
            RAISE NOTICE '[PASS] Test 11: Financial reconciliation PASSED with ZERO discrepancy (0.00).';
        ELSE
            RAISE EXCEPTION 'TEST 11 FAILED: Financial ledger discrepancy detected: ₹%', v_discrepancy;
        END IF;
    END;

    -- Clean up test records respecting referential integrity (payments -> invoice -> appointment)
    DELETE FROM payments WHERE invoice_id = v_inv_id;
    DELETE FROM invoices WHERE invoice_id = v_inv_id;
    DELETE FROM appointments WHERE appointment_id = v_appt_id;

    RAISE NOTICE '============================================================';
    RAISE NOTICE 'ALL 11 REGRESSION AND INTEGRITY TESTS PASSED FLAWLESSLY!';
    RAISE NOTICE '============================================================';
END $$;
