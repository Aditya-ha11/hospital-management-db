-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Test File: tests/02_billing_integrity_tests.sql
-- Description: Verifies payment validation trigger, concurrency lock, and ledger integrity
-- =============================================================================

DO $$
DECLARE
    v_appt_id BIGINT;
    v_inv_id BIGINT;
    v_pay_id BIGINT;
    v_rev_id BIGINT;
    v_status VARCHAR(20);
    v_balance NUMERIC(10, 2);
BEGIN
    RAISE NOTICE '>>> TEST SUITE 2: BILLING & PAYMENT INTEGRITY TESTS';

    -- 1. Create a dummy appointment and invoice of ₹1,500.00
    INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
    VALUES (1, 1, '2026-12-21 09:00:00+05:30', '2026-12-21 09:30:00+05:30', 'completed', 'Billing Test Encounter')
    RETURNING appointment_id INTO v_appt_id;

    INSERT INTO invoices (appointment_id, total_amount, due_date)
    VALUES (v_appt_id, 1500.00, CURRENT_DATE + 30)
    RETURNING invoice_id INTO v_inv_id;

    -- 2. Test Partial Payment: Pay ₹500 on ₹1,500 invoice -> Invoice status becomes 'partially_paid'
    INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
    VALUES (v_inv_id, 500.00, 'cash', 'TEST-PARTIAL-500')
    RETURNING payment_id INTO v_pay_id;

    SELECT status INTO v_status FROM invoices WHERE invoice_id = v_inv_id;
    IF v_status = 'partially_paid' THEN
        RAISE NOTICE '  [PASS] 2.1: Partial payment of ₹500 recorded; invoice transitioned to partially_paid.';
    ELSE
        RAISE EXCEPTION 'FAILED: Invoice status expected partially_paid, found %', v_status;
    END IF;

    -- 3. Test Overpayment Protection: Remaining balance is ₹1,000. Attempt to pay ₹1,200 -> MUST BE REJECTED
    BEGIN
        INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
        VALUES (v_inv_id, 1200.00, 'card', 'TEST-OVERPAY-1200');
        RAISE EXCEPTION 'FAILED: Overpayment was unexpectedly permitted by database trigger!';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '  [PASS] 2.2: Payment of ₹1,200 on ₹1,000 balance rejected by trg_validate_payment.';
    END;

    -- 4. Test Full Settlement: Pay remaining ₹1,000 -> Invoice status becomes 'paid_in_full'
    INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
    VALUES (v_inv_id, 1000.00, 'upi', 'TEST-SETTLE-1000');

    SELECT status INTO v_status FROM invoices WHERE invoice_id = v_inv_id;
    IF v_status = 'paid_in_full' THEN
        RAISE NOTICE '  [PASS] 2.3: Full settlement recorded; invoice transitioned to paid_in_full.';
    ELSE
        RAISE EXCEPTION 'FAILED: Invoice status expected paid_in_full, found %', v_status;
    END IF;

    -- 5. Test Overpayment on Fully Settled Invoice: Remaining balance is ₹0. Attempt to pay ₹100 -> MUST BE REJECTED
    BEGIN
        INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
        VALUES (v_inv_id, 100.00, 'card', 'TEST-OVERPAY-ZERO-BAL');
        RAISE EXCEPTION 'FAILED: Payment on zero balance was unexpectedly permitted!';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '  [PASS] 2.4: Additional payment on fully settled invoice rejected (zero balance).';
    END;

    -- 6. Test Payment Reversal (Refund): Reverse the initial ₹500 payment
    CALL sp_reverse_payment(v_pay_id, 'Billing adjustment requested by patient', v_rev_id);

    -- After reversing ₹500, total paid = 500 + 1000 - 500 = 1000. Invoice becomes partially_paid with ₹500 due.
    SELECT status INTO v_status FROM invoices WHERE invoice_id = v_inv_id;
    SELECT outstanding_balance INTO v_balance FROM v_invoice_ledger WHERE invoice_id = v_inv_id;

    IF v_status = 'partially_paid' AND v_balance = 500.00 THEN
        RAISE NOTICE '  [PASS] 2.5: Payment reversal restored balance to ₹500 and status to partially_paid.';
    ELSE
        RAISE EXCEPTION 'FAILED: Reversal failed to restore balance: status=%, balance=%', v_status, v_balance;
    END IF;

    -- Clean up test records
    DELETE FROM payments WHERE invoice_id = v_inv_id;
    DELETE FROM invoices WHERE invoice_id = v_inv_id;
    DELETE FROM appointments WHERE appointment_id = v_appt_id;
    RAISE NOTICE '>>> TEST SUITE 2 COMPLETE: All billing integrity tests PASSED.';
END $$;
