-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Phase 3 Extension: Business Logic, Triggers, and Stored Procedures
-- Database: hospital_management_db
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Trigger Function: Validate Payment Against Invoice Balance (Business Rule 8)
-- "Monetary amounts must be non-negative, and payments must be validated
-- against the outstanding balance."
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_payment_against_balance()
RETURNS TRIGGER AS $$
DECLARE
    v_total_amount NUMERIC(10, 2);
    v_already_paid NUMERIC(10, 2);
    v_remaining_balance NUMERIC(10, 2);
BEGIN
    -- Lock the target invoice row for update to prevent concurrent race conditions on balance
    SELECT total_amount INTO v_total_amount
    FROM invoices
    WHERE invoice_id = NEW.invoice_id
    FOR UPDATE;

    IF v_total_amount IS NULL THEN
        RAISE EXCEPTION 'Invoice ID % does not exist.', NEW.invoice_id;
    END IF;

    -- Calculate total paid prior to this transaction
    SELECT COALESCE(SUM(amount), 0.00) INTO v_already_paid
    FROM payments
    WHERE invoice_id = NEW.invoice_id
      AND payment_id IS DISTINCT FROM NEW.payment_id;

    v_remaining_balance := v_total_amount - v_already_paid;

    -- Check if payment exceeds remaining balance
    IF NEW.amount > v_remaining_balance THEN
        RAISE EXCEPTION 'Payment rejected: Amount (₹%) exceeds remaining outstanding balance (₹%).',
            NEW.amount, v_remaining_balance
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_payment ON payments;
CREATE TRIGGER trg_validate_payment
    BEFORE INSERT OR UPDATE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_payment_against_balance();

-- -----------------------------------------------------------------------------
-- 2. Trigger Function: Validate Doctor Availability Window (FR-03 & Business Rule)
-- Ensures appointments fall within doctor's declared working schedule.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_appointment_doctor_shift()
RETURNS TRIGGER AS $$
DECLARE
    v_weekday SMALLINT;
    v_appt_start TIME;
    v_appt_end TIME;
    v_shift_exists BOOLEAN;
BEGIN
    -- Extract weekday (0=Sunday ... 6=Saturday) and time in doctor's local timezone
    v_weekday := EXTRACT(DOW FROM NEW.start_at)::SMALLINT;
    v_appt_start := NEW.start_at::TIME;
    v_appt_end := NEW.end_at::TIME;

    -- Check if there is an availability block covering this appointment
    SELECT EXISTS (
        SELECT 1 
        FROM doctor_availability
        WHERE doctor_id = NEW.doctor_id
          AND weekday = v_weekday
          AND start_time <= v_appt_start
          AND end_time >= v_appt_end
    ) INTO v_shift_exists;

    IF NOT v_shift_exists THEN
        RAISE EXCEPTION 'Appointment rejected: Doctor % has no scheduled shift on weekday % between % and %.',
            NEW.doctor_id, v_weekday, v_appt_start, v_appt_end
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Optional strict trigger (can be enabled if hospital enforces strict roster adherence):
-- CREATE TRIGGER trg_check_doctor_schedule
--     BEFORE INSERT OR UPDATE OF doctor_id, start_at, end_at ON appointments
--     FOR EACH ROW
--     EXECUTE FUNCTION fn_validate_appointment_doctor_shift();

-- -----------------------------------------------------------------------------
-- 3. Stored Procedure: Transactional Safe Appointment Booking
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
        RAISE EXCEPTION 'Appointment start time (%) must be before end time (%).', p_start_at, p_end_at;
    END IF;

    INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
    VALUES (p_patient_id, p_doctor_id, p_start_at, p_end_at, 'scheduled', p_reason)
    RETURNING appointment_id INTO p_appointment_id;

    RAISE NOTICE 'Appointment #% successfully booked for Patient #% with Doctor #%.',
        p_appointment_id, p_patient_id, p_doctor_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Stored Procedure: Cancel Appointment & Free GiST Slot
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancel_appointment(
    IN p_appointment_id BIGINT,
    IN p_cancellation_reason VARCHAR(255)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status VARCHAR(20);
BEGIN
    SELECT status INTO v_current_status
    FROM appointments
    WHERE appointment_id = p_appointment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Appointment #% not found.', p_appointment_id;
    END IF;

    IF v_current_status = 'completed' THEN
        RAISE EXCEPTION 'Cannot cancel appointment #% because it is already completed.', p_appointment_id;
    END IF;

    IF v_current_status = 'cancelled' THEN
        RAISE NOTICE 'Appointment #% is already cancelled.', p_appointment_id;
        RETURN;
    END IF;

    UPDATE appointments
    SET status = 'cancelled',
        reason = COALESCE(reason || ' [Cancelled: ' || p_cancellation_reason || ']', 'Cancelled: ' || p_cancellation_reason)
    WHERE appointment_id = p_appointment_id;

    RAISE NOTICE 'Appointment #% has been cancelled and time slot is now liberated.', p_appointment_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. Stored Procedure: Record Payment with Validation
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_record_payment(
    IN p_invoice_id BIGINT,
    IN p_amount NUMERIC(10, 2),
    IN p_payment_method VARCHAR(20),
    IN p_reference_code VARCHAR(100),
    OUT p_payment_id BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
    VALUES (p_invoice_id, p_amount, p_payment_method, p_reference_code)
    RETURNING payment_id INTO p_payment_id;

    RAISE NOTICE 'Payment #% of ₹% recorded for Invoice #%.',
        p_payment_id, p_amount, p_invoice_id;
END;
$$;
