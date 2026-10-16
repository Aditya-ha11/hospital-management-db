-- =============================================================================
-- Hospital Appointment and Patient Management System
-- File: sql/04_booking_rules.sql
-- Description: Advanced booking protection, GiST exclusion rules, and scheduling procedures
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Trigger Function: Doctor Working Hours Validation
-- Validates that every non-emergency scheduled appointment falls strictly within 
-- the assigned doctor's weekly recurring shift schedule.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_doctor_shift_hours()
RETURNS TRIGGER AS $$
DECLARE
    v_appt_dow SMALLINT;
    v_start_time TIME;
    v_end_time TIME;
    v_shift_found BOOLEAN;
BEGIN
    -- Extract Day-Of-Week (0=Sunday ... 6=Saturday) and times in hospital local timezone
    v_appt_dow := EXTRACT(DOW FROM NEW.start_at)::SMALLINT;
    v_start_time := NEW.start_at::TIME;
    v_end_time := NEW.end_at::TIME;

    SELECT EXISTS (
        SELECT 1
        FROM doctor_availability
        WHERE doctor_id = NEW.doctor_id
          AND weekday = v_appt_dow
          AND start_time <= v_start_time
          AND end_time >= v_end_time
    ) INTO v_shift_found;

    IF NOT v_shift_found THEN
        RAISE EXCEPTION 'Booking Rejected: Doctor #% does not have an active shift on weekday % covering % to %.',
            NEW.doctor_id, v_appt_dow, v_start_time, v_end_time
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger enabled on appointments
DROP TRIGGER IF EXISTS trg_validate_doctor_shift ON appointments;
CREATE TRIGGER trg_validate_doctor_shift
    BEFORE INSERT OR UPDATE OF doctor_id, start_at, end_at ON appointments
    FOR EACH ROW
    WHEN (NEW.status IN ('scheduled', 'confirmed'))
    EXECUTE FUNCTION fn_validate_doctor_shift_hours();

-- -----------------------------------------------------------------------------
-- 2. Stored Procedure: Transactional Safe Booking
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_book_appointment(
    IN p_patient_id BIGINT,
    IN p_doctor_id BIGINT,
    IN p_start_at TIMESTAMPTZ,
    IN p_end_at TIMESTAMPTZ,
    IN p_reason VARCHAR(255),
    OUT p_appointment_id BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_start_at >= p_end_at THEN
        RAISE EXCEPTION 'Appointment start time (%) must precede end time (%).', p_start_at, p_end_at;
    END IF;

    INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
    VALUES (p_patient_id, p_doctor_id, p_start_at, p_end_at, 'scheduled', p_reason)
    RETURNING appointment_id INTO p_appointment_id;

    RAISE NOTICE 'Appointment #% successfully confirmed for Patient #% with Doctor #%.',
        p_appointment_id, p_patient_id, p_doctor_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. Stored Procedure: Reschedule Appointment (With Audit Logging)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_reschedule_appointment(
    IN p_appointment_id BIGINT,
    IN p_new_start_at TIMESTAMPTZ,
    IN p_new_end_at TIMESTAMPTZ,
    IN p_reschedule_reason VARCHAR(255)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
BEGIN
    SELECT status INTO v_status
    FROM appointments
    WHERE appointment_id = p_appointment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Appointment #% not found.', p_appointment_id;
    END IF;

    IF v_status IN ('completed', 'cancelled') THEN
        RAISE EXCEPTION 'Cannot reschedule appointment #% because it is %.', p_appointment_id, v_status;
    END IF;

    UPDATE appointments
    SET start_at = p_new_start_at,
        end_at = p_new_end_at,
        reason = COALESCE(reason || ' [Rescheduled: ' || p_reschedule_reason || ']', 'Rescheduled: ' || p_reschedule_reason)
    WHERE appointment_id = p_appointment_id;

    RAISE NOTICE 'Appointment #% successfully rescheduled to %.', p_appointment_id, p_new_start_at;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Stored Procedure: Cancel Appointment (Frees GiST Slot)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancel_appointment(
    IN p_appointment_id BIGINT,
    IN p_cancellation_reason VARCHAR(255)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
BEGIN
    SELECT status INTO v_status
    FROM appointments
    WHERE appointment_id = p_appointment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Appointment #% not found.', p_appointment_id;
    END IF;

    IF v_status = 'completed' THEN
        RAISE EXCEPTION 'Cannot cancel appointment #% because it has already been completed.', p_appointment_id;
    END IF;

    IF v_status = 'cancelled' THEN
        RAISE NOTICE 'Appointment #% is already cancelled.', p_appointment_id;
        RETURN;
    END IF;

    UPDATE appointments
    SET status = 'cancelled',
        reason = COALESCE(reason || ' [Cancelled: ' || p_cancellation_reason || ']', 'Cancelled: ' || p_cancellation_reason)
    WHERE appointment_id = p_appointment_id;

    RAISE NOTICE 'Appointment #% cancelled; slot liberated in GiST exclusion index.', p_appointment_id;
END;
$$;
