-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Test File: tests/03_foreign_keys_and_checks.sql
-- Description: Asserts relational schema integrity, foreign keys, and check constraints
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '>>> TEST SUITE 3: SCHEMA INTEGRITY, FOREIGN KEYS & CHECK CONSTRAINTS';

    -- 1. Foreign Key: Doctor referencing non-existent department (99999) -> REJECTED
    BEGIN
        INSERT INTO doctors (department_id, first_name, last_name, specialty, consultation_fee, email)
        VALUES (99999, 'Test', 'Doctor', 'General', 500.00, 'fk.test@hospital.org');
        RAISE EXCEPTION 'FAILED: Foreign key allowed non-existent department_id!';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE '  [PASS] 3.1: Foreign key fk_doctor_department correctly rejected invalid department.';
    END;

    -- 2. Check Constraint: Doctor consultation fee < 0 -> REJECTED
    BEGIN
        INSERT INTO doctors (department_id, first_name, last_name, specialty, consultation_fee, email)
        VALUES (1, 'Test', 'Doctor', 'Cardiology', -100.00, 'neg.fee@hospital.org');
        RAISE EXCEPTION 'FAILED: Check constraint allowed negative consultation fee!';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '  [PASS] 3.2: Check constraint chk_consultation_fee correctly rejected negative fee.';
    END;

    -- 3. Check Constraint: Patient date of birth in the future -> REJECTED
    BEGIN
        INSERT INTO patients (first_name, last_name, date_of_birth, phone, email)
        VALUES ('Future', 'Baby', CURRENT_DATE + 10, '+91-9999900000', 'future.baby@hospital.org');
        RAISE EXCEPTION 'FAILED: Check constraint allowed future date of birth!';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '  [PASS] 3.3: Check constraint chk_patient_dob correctly rejected future date of birth.';
    END;

    -- 4. Check Constraint: Appointment end time <= start time -> REJECTED
    BEGIN
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (1, 1, '2026-12-15 10:00:00+05:30', '2026-12-15 09:30:00+05:30', 'scheduled', 'Time Travel');
        RAISE EXCEPTION 'FAILED: Check constraint allowed end_at <= start_at!';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '  [PASS] 3.4: Check constraint chk_appointment_time correctly rejected backwards time range.';
    END;

    -- 5. Foreign Key: Restrict deletion of department with active doctors -> REJECTED
    BEGIN
        DELETE FROM departments WHERE department_id = 1;
        RAISE EXCEPTION 'FAILED: Department with active doctors was deleted!';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE '  [PASS] 3.5: ON DELETE RESTRICT on fk_doctor_department protected active department.';
    END;

    RAISE NOTICE '>>> TEST SUITE 3 COMPLETE: All schema integrity & constraint tests PASSED.';
END $$;
