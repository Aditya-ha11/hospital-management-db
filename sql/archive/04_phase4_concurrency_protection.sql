-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Phase 4: Advanced Booking Protection & Overlap Prevention
-- Database: hospital_management_db
-- =============================================================================

-- Phase 4 rigorously tests the EXCLUDE USING gist constraints
-- backed by the btree_gist extension and tstzrange('[)').

DO $$
DECLARE
    v_appt_id BIGINT;
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'Starting Phase 4 Advanced Booking Protection Tests';
    RAISE NOTICE '==================================================';

    -- -------------------------------------------------------------------------
    -- TEST 1: Doctor Double-Booking Conflict Prevention
    -- In Phase 2, Doctor 1 has an active 'checked_in' appointment on 2026-10-19 
    -- from 11:30 to 12:00.
    -- Attempting to book Doctor 1 from 11:45 to 12:15 MUST FAIL.
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (7, 1, '2026-10-19 11:45:00+05:30', '2026-10-19 12:15:00+05:30', 'scheduled', 'Overlapping slot conflict');
        RAISE EXCEPTION 'TEST 1 FAILED: Doctor exclusion constraint allowed overlapping appointment (11:45-12:15)!';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE '[PASS] Test 1: no_doctor_overlapping_appointments blocked overlapping slot (11:45-12:15).';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 2: Patient Double-Booking Conflict Prevention
    -- Patient 5 has an active 'confirmed' appointment with Doctor 1 from 14:00 to 14:45 on 2026-10-19.
    -- If Patient 5 tries to schedule another appointment with Doctor 2 from 14:15 to 15:00,
    -- it MUST FAIL due to patient overlap exclusion.
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (5, 2, '2026-10-19 14:15:00+05:30', '2026-10-19 15:00:00+05:30', 'scheduled', 'Patient simultaneous appointment');
        RAISE EXCEPTION 'TEST 2 FAILED: Patient exclusion constraint allowed double-booked patient!';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE '[PASS] Test 2: no_patient_overlapping_appointments blocked simultaneous booking for patient.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 3: Half-Open Range Boundary Test (Consecutive / Adjacent Bookings)
    -- Doctor 2 has availability. Let us schedule two consecutive slots:
    -- Slot A: 13:00 to 13:30
    -- Slot B: 13:30 to 14:00
    -- Because tstzrange uses '[)' (inclusive start, exclusive end), these MUST SUCCEED.
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (8, 2, '2026-10-20 13:00:00+05:30', '2026-10-20 13:30:00+05:30', 'scheduled', 'Boundary Slot A');

        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (9, 2, '2026-10-20 13:30:00+05:30', '2026-10-20 14:00:00+05:30', 'scheduled', 'Boundary Slot B');

        RAISE NOTICE '[PASS] Test 3: Half-open range ''[)'' correctly allowed adjacent consecutive appointments.';
    END;

    -- -------------------------------------------------------------------------
    -- TEST 4: Slot Recycling on Cancellation
    -- Cancel an appointment and ensure the slot is immediately re-bookable.
    -- -------------------------------------------------------------------------
    BEGIN
        -- Book a temporary test appointment
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (10, 4, '2026-10-23 09:00:00+05:30', '2026-10-23 09:30:00+05:30', 'scheduled', 'Slot to cancel')
        RETURNING appointment_id INTO v_appt_id;

        -- Cancel this appointment
        UPDATE appointments
        SET status = 'cancelled'
        WHERE appointment_id = v_appt_id;

        -- Now another patient books the EXACT same slot
        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
        VALUES (1, 4, '2026-10-23 09:00:00+05:30', '2026-10-23 09:30:00+05:30', 'scheduled', 'Replacement booking in freed slot');

        RAISE NOTICE '[PASS] Test 4: Cancelling appointment freed slot; re-booking same slot succeeded seamlessly.';
    END;

    RAISE NOTICE '==================================================';
    RAISE NOTICE 'All Phase 4 Booking Protection Tests Passed!';
    RAISE NOTICE '==================================================';
END $$;
