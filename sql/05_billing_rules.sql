-- =============================================================================
-- Hospital Appointment and Patient Management System
-- File: sql/05_billing_rules.sql
-- Description: Transaction-safe billing, overpayment protection, and payment reversals
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Trigger Function: Overpayment Prevention with Row Locking (Business Rule 8)
-- Prevents race conditions by locking the target invoice row with FOR UPDATE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_payment_against_balance()
RETURNS TRIGGER AS $$
DECLARE
    v_total_amount NUMERIC(10, 2);
    v_net_paid NUMERIC(10, 2);
    v_remaining_balance NUMERIC(10, 2);
BEGIN
    -- Acquire exclusive row lock on the invoice to serialize concurrent payments
    SELECT total_amount INTO v_total_amount
    FROM invoices
    WHERE invoice_id = NEW.invoice_id
    FOR UPDATE;

    IF v_total_amount IS NULL THEN
        RAISE EXCEPTION 'Invoice #% does not exist.', NEW.invoice_id;
    END IF;

    -- Calculate net settled amount (payments minus reversals)
    SELECT COALESCE(
        SUM(CASE 
            WHEN payment_type = 'payment' THEN amount 
            WHEN payment_type IN ('refund', 'reversal') THEN -amount 
            ELSE 0 
        END), 0.00
    ) INTO v_net_paid
    FROM payments
    WHERE invoice_id = NEW.invoice_id
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

DROP TRIGGER IF EXISTS trg_validate_payment ON payments;
CREATE TRIGGER trg_validate_payment
    BEFORE INSERT OR UPDATE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_payment_against_balance();

-- -----------------------------------------------------------------------------
-- 2. Trigger Function: Synchronize Invoice Status after Payment
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_sync_invoice_status_after_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_target_invoice_id BIGINT;
    v_total NUMERIC(10, 2);
    v_net_paid NUMERIC(10, 2);
BEGIN
    v_target_invoice_id := COALESCE(NEW.invoice_id, OLD.invoice_id);

    SELECT total_amount INTO v_total
    FROM invoices
    WHERE invoice_id = v_target_invoice_id;

    SELECT COALESCE(
        SUM(CASE 
            WHEN payment_type = 'payment' THEN amount 
            WHEN payment_type IN ('refund', 'reversal') THEN -amount 
            ELSE 0 
        END), 0.00
    ) INTO v_net_paid
    FROM payments
    WHERE invoice_id = v_target_invoice_id;

    UPDATE invoices
    SET status = CASE 
        WHEN v_net_paid >= v_total THEN 'paid_in_full'
        WHEN v_net_paid > 0 THEN 'partially_paid'
        ELSE 'unpaid'
    END
    WHERE invoice_id = v_target_invoice_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_invoice_status ON payments;
CREATE TRIGGER trg_sync_invoice_status
    AFTER INSERT OR UPDATE OR DELETE ON payments
    FOR EACH ROW
    EXECUTE FUNCTION fn_sync_invoice_status_after_payment();

-- -----------------------------------------------------------------------------
-- 3. Stored Procedure: Record Payment
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
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero.';
    END IF;

    INSERT INTO payments (invoice_id, amount, payment_type, payment_method, reference_code)
    VALUES (p_invoice_id, p_amount, 'payment', p_payment_method, p_reference_code)
    RETURNING payment_id INTO p_payment_id;

    RAISE NOTICE 'Payment #% of ₹% recorded for Invoice #%.', p_payment_id, p_amount, p_invoice_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. Stored Procedure: Reverse Payment (Refund/Correction)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_reverse_payment(
    IN p_original_payment_id BIGINT,
    IN p_reversal_reason VARCHAR(255),
    OUT p_reversal_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_orig_inv_id BIGINT;
    v_orig_amt NUMERIC(10, 2);
    v_orig_method VARCHAR(20);
    v_already_reversed BOOLEAN;
BEGIN
    SELECT invoice_id, amount, payment_method
    INTO v_orig_inv_id, v_orig_amt, v_orig_method
    FROM payments
    WHERE payment_id = p_original_payment_id AND payment_type = 'payment'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Original payment #% not found or not eligible for reversal.', p_original_payment_id;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM payments WHERE reversed_payment_id = p_original_payment_id
    ) INTO v_already_reversed;

    IF v_already_reversed THEN
        RAISE EXCEPTION 'Payment #% has already been reversed.', p_original_payment_id;
    END IF;

    INSERT INTO payments (
        invoice_id, amount, payment_type, payment_method, 
        reference_code, reversed_payment_id
    )
    VALUES (
        v_orig_inv_id, v_orig_amt, 'reversal', v_orig_method,
        'REV-' || p_original_payment_id || '-' || EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)::BIGINT,
        p_original_payment_id
    )
    RETURNING payment_id INTO p_reversal_id;

    RAISE NOTICE 'Payment #% reversed successfully via Reversal Record #%. Reason: %',
        p_original_payment_id, p_reversal_id, p_reversal_reason;
END;
$$;
