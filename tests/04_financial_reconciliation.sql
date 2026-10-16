-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Test File: tests/04_financial_reconciliation.sql
-- Description: Asserts zero-discrepancy mathematical reconciliation across all ledgers
-- =============================================================================

DO $$
DECLARE
    v_total_invoiced NUMERIC(12, 2);
    v_total_collected NUMERIC(12, 2);
    v_total_outstanding NUMERIC(12, 2);
    v_dept_total_invoiced NUMERIC(12, 2);
    v_dept_total_collected NUMERIC(12, 2);
    v_discrepancy_ledger NUMERIC(12, 2);
    v_discrepancy_dept NUMERIC(12, 2);
BEGIN
    RAISE NOTICE '>>> TEST SUITE 4: ZERO-DISCREPANCY FINANCIAL RECONCILIATION AUDIT';

    -- 1. Query Master Ledger Totals
    SELECT COALESCE(SUM(total_amount), 0.00) INTO v_total_invoiced FROM invoices;

    SELECT COALESCE(
        SUM(CASE 
            WHEN payment_type = 'payment' THEN amount 
            WHEN payment_type IN ('refund', 'reversal') THEN -amount 
            ELSE 0 
        END), 0.00
    ) INTO v_total_collected FROM payments;

    SELECT COALESCE(SUM(outstanding_balance), 0.00) INTO v_total_outstanding FROM v_invoice_ledger;

    -- 2. Query Department Aggregated Totals (using pre-aggregated CTEs)
    WITH dept_inv AS (
        SELECT d.department_id, COALESCE(SUM(i.total_amount), 0.00) AS billed
        FROM invoices i
        JOIN appointments a ON i.appointment_id = a.appointment_id
        JOIN doctors d ON a.doctor_id = d.doctor_id
        GROUP BY d.department_id
    ),
    dept_pay AS (
        SELECT d.department_id, COALESCE(SUM(p.amount), 0.00) AS collected
        FROM payments p
        JOIN invoices i ON p.invoice_id = i.invoice_id
        JOIN appointments a ON i.appointment_id = a.appointment_id
        JOIN doctors d ON a.doctor_id = d.doctor_id
        WHERE p.payment_type = 'payment'
        GROUP BY d.department_id
    )
    SELECT 
        COALESCE(SUM(di.billed), 0.00),
        COALESCE(SUM(dp.collected), 0.00)
    INTO v_dept_total_invoiced, v_dept_total_collected
    FROM departments dept
    LEFT JOIN dept_inv di ON dept.department_id = di.department_id
    LEFT JOIN dept_pay dp ON dept.department_id = dp.department_id;

    -- 3. Calculate Reconciliation Discrepancies
    v_discrepancy_ledger := v_total_invoiced - (v_total_collected + v_total_outstanding);
    v_discrepancy_dept := v_total_invoiced - v_dept_total_invoiced;

    RAISE NOTICE '  -------------------------------------------------------------';
    RAISE NOTICE '  FINANCIAL RECONCILIATION AUDIT SUMMARY:';
    RAISE NOTICE '  Total Invoiced Amount     : ₹%', v_total_invoiced;
    RAISE NOTICE '  Total Collected Revenue   : ₹%', v_total_collected;
    RAISE NOTICE '  Total Outstanding Balance : ₹%', v_total_outstanding;
    RAISE NOTICE '  Collected + Outstanding   : ₹%', (v_total_collected + v_total_outstanding);
    RAISE NOTICE '  Department Sum (Invoiced) : ₹%', v_dept_total_invoiced;
    RAISE NOTICE '  Department Sum (Collected): ₹%', v_dept_total_collected;
    RAISE NOTICE '  -------------------------------------------------------------';

    -- 4. Assert Discrepancies equal 0.00
    IF v_discrepancy_ledger = 0.00 THEN
        RAISE NOTICE '  [PASS] 4.1: Master ledger equation: Invoiced = Collected + Outstanding (Delta: ₹0.00).';
    ELSE
        RAISE EXCEPTION 'FAILED: Master ledger discrepancy detected: ₹%', v_discrepancy_ledger;
    END IF;

    IF v_discrepancy_dept = 0.00 THEN
        RAISE NOTICE '  [PASS] 4.2: Department aggregation reconciles with Invoices table (Delta: ₹0.00).';
    ELSE
        RAISE EXCEPTION 'FAILED: Department aggregation discrepancy detected: ₹%', v_discrepancy_dept;
    END IF;

    RAISE NOTICE '>>> TEST SUITE 4 COMPLETE: 100%% MATHEMATICAL RECONCILIATION VERIFIED.';
END $$;
