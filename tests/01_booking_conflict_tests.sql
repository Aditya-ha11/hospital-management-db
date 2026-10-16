-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Test File: tests/01_booking_conflict_tests.sql
-- Description: Verifies PostgreSQL GiST exclusion constraints and slot mechanics
-- =============================================================================

DO $$
DECLARE
    v_appt_id BIGINT;
    v_appt_id2 BIGINT;
BEGIN
    RAISE NOTICE '>>> TEST SUITE 1: BOOKING CONFLICT & GIST EXCLUSION TESTS';

    -- 1. Establish baseline active booking for Doctor 1: Monday 09:00 - 09:30
    INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
    VALUES (1, 1, '2026-12-14 09:00:00+05:30', '2026-12-14 09:30:00+05:30', 'scheduled', 'Baseline Booking Slot')
    RETURNING appointment_id INTO v_appt_id;

    -- 2. Conflict Test: Same doctor, overlapping times (09:15 - 09:45) -> MUST BE REJECTED
    BEGIN
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (2, 1, '2026-12-14 09:15:00+05:30', '2026-12-14 09:45:00+05:30', 'scheduled', 'Overlapping Booking');
        RAISE EXCEPTION 'FAILED: Doctor overlapping booking was unexpectedly permitted!';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE '  [PASS] 1.1: Same doctor, overlapping slot rejected by no_doctor_overlapping_appointments.';
    END;

    -- 3. Boundary Test: Same doctor, consecutive back-to-back appointment (09:30 - 10:00) -> MUST BE ACCEPTED
    BEGIN
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (3, 1, '2026-12-14 09:30:00+05:30', '2026-12-14 10:00:00+05:30', 'scheduled', 'Consecutive Booking');
        RAISE NOTICE '  [PASS] 1.2: Same doctor, consecutive half-open boundary [) slot accepted seamlessly.';
    END;

    -- 4. Conflict Test: Same patient, overlapping appointment with different doctor -> MUST BE REJECTED
    BEGIN
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (1, 3, '2026-12-14 09:10:00+05:30', '2026-12-14 09:40:00+05:30', 'scheduled', 'Patient Double Booking');
        RAISE EXCEPTION 'FAILED: Patient simultaneous booking was unexpectedly permitted!';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE '  [PASS] 1.3: Same patient, overlapping slot rejected by no_patient_overlapping_appointments.';
    END;

    -- 5. Lifecycle Test: Cancel an appointment, then reuse the exact slot -> MUST BE ACCEPTED
    BEGIN
        UPDATE appointments SET status = 'cancelled' WHERE appointment_id = v_appt_id;

        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (4, 1, '2026-12-14 09:00:00+05:30', '2026-12-14 09:30:00+05:30', 'scheduled', 'Re-booked Slot After Cancellation');
        RAISE NOTICE '  [PASS] 1.4: Cancelled slot liberated immediately and successfully re-booked by new patient.';
    END;

    -- Clean up test appointments
    DELETE FROM appointments WHERE start_at >= '2026-12-14 00:00:00+05:30' AND start_at < '2026-12-15 00:00:00+05:30';
    RAISE NOTICE '>>> TEST SUITE 1 COMPLETE: All booking conflict tests PASSED.';
END $$;
