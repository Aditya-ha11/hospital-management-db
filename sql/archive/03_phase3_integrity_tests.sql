-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Phase 3: Relationships and Integrity Testing
-- Database: hospital_management_db
-- =============================================================================

-- In PostgreSQL, we can use DO blocks with EXCEPTION handling to run these tests
-- and verify that constraints correctly trigger and reject invalid operations.

DO $$
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'Starting Phase 3 Integrity and Relationship Tests';
    RAISE NOTICE '==================================================';

    -- -------------------------------------------------------------------------
    -- TEST 1: Foreign Key Violation (Doctor -> Department)
    -- Expectation: Department 9999 does not exist, insert MUST fail.
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO doctors (department_id, first_name, last_name, specialty, consultation_fee, email)
        VALUES (9999, 'Test', 'Doctor', 'General', 500.00, 'test.invalid.dept@hospital.org');
        RAISE EXCEPTION 'TEST 1 FAILED: Foreign key constraint did not reject non-existent department_id 9999';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE '[PASS] Test 1: Foreign key fk_doctor_department correctly rejected invalid department_id.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 2: CHECK Constraint Violation (Negative Consultation Fee)
    -- Expectation: consultation_fee >= 0
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO doctors (department_id, first_name, last_name, specialty, consultation_fee, email)
        VALUES (1, 'Negative', 'FeeDoctor', 'Cardiology', -150.00, 'neg.fee@hospital.org');
        RAISE EXCEPTION 'TEST 2 FAILED: Check constraint allowed negative consultation fee';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '[PASS] Test 2: Check constraint chk_consultation_fee correctly rejected negative fee.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 3: CHECK Constraint Violation (Future Date of Birth)
    -- Expectation: date_of_birth <= CURRENT_DATE
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO patients (first_name, last_name, date_of_birth, phone, email)
        VALUES ('Future', 'Baby', CURRENT_DATE + INTERVAL '10 days', '+91-9999999999', 'future.baby@example.com');
        RAISE EXCEPTION 'TEST 3 FAILED: Check constraint allowed future date of birth';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '[PASS] Test 3: Check constraint chk_patient_dob correctly rejected future birthdate.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 4: CHECK Constraint Violation (Invalid Appointment Status)
    -- Expectation: status IN ('scheduled', 'confirmed', 'checked_in', 'completed', 'cancelled')
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status)
        VALUES (1, 1, '2026-11-01 10:00:00+05:30', '2026-11-01 10:30:00+05:30', 'in_limbo');
        RAISE EXCEPTION 'TEST 4 FAILED: Check constraint allowed invalid appointment status';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '[PASS] Test 4: Check constraint chk_appointment_status correctly rejected invalid status.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 5: Unique Invoice per Appointment (1:0..1 Relationship)
    -- Expectation: Appointment 1 already has an invoice (Invoice #1), duplicate must fail.
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO invoices (appointment_id, total_amount, due_date)
        VALUES (1, 999.00, CURRENT_DATE + 7);
        RAISE EXCEPTION 'TEST 5 FAILED: Allowed duplicate invoice for appointment 1';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE '[PASS] Test 5: Unique constraint correctly rejected duplicate invoice for the same appointment.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 6: Referential Integrity Protection (ON DELETE RESTRICT)
    -- Expectation: Cannot delete Cardiology department while doctors belong to it.
    -- -------------------------------------------------------------------------
    BEGIN
        DELETE FROM departments WHERE department_id = 1;
        RAISE EXCEPTION 'TEST 6 FAILED: Allowed deleting parent department with active child doctors';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE '[PASS] Test 6: ON DELETE RESTRICT correctly prevented deleting department with active doctors.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 7: Payment Amount Check
    -- Expectation: amount > 0 (Reject zero or negative payment)
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO payments (invoice_id, amount, payment_method)
        VALUES (1, 0.00, 'cash');
        RAISE EXCEPTION 'TEST 7 FAILED: Allowed zero payment amount';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '[PASS] Test 7: Check constraint chk_payment_amount correctly rejected 0.00 payment.';
    END;

    RAISE NOTICE '==================================================';
    RAISE NOTICE 'All Phase 3 Integrity Tests Passed Successfully!';
    RAISE NOTICE '==================================================';
END $$;
