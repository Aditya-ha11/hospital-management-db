-- =============================================================================
-- Hospital Appointment and Patient Management System
-- File: sql/06_indexes_views.sql
-- Description: Justified indexes, dynamic reporting views, and materialized KPI views
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Justified Performance Indexes
-- -----------------------------------------------------------------------------
-- Speeds up filtering doctors by department
CREATE INDEX IF NOT EXISTS idx_doctors_department 
    ON doctors(department_id);

-- Composite index: speeds up conflict lookups, doctor scheduling, and date ranges
CREATE INDEX IF NOT EXISTS idx_appointments_doctor_date 
    ON appointments(doctor_id, start_at);

-- Speeds up patient historical visit lookups and timeline queries
CREATE INDEX IF NOT EXISTS idx_appointments_patient 
    ON appointments(patient_id, start_at);

-- Speeds up operational pipeline queries filtering by status
CREATE INDEX IF NOT EXISTS idx_appointments_status 
    ON appointments(status);

-- Speeds up aging and overdue invoice searches
CREATE INDEX IF NOT EXISTS idx_invoices_due 
    ON invoices(due_date);

-- Speeds up payment aggregations for invoices
CREATE INDEX IF NOT EXISTS idx_payments_invoice 
    ON payments(invoice_id);

-- Speeds up audit log lookups by appointment
CREATE INDEX IF NOT EXISTS idx_audit_appointment 
    ON appointment_audit_log(appointment_id, changed_at DESC);

-- -----------------------------------------------------------------------------
-- 2. View: Comprehensive Appointment & Clinical Schedule View
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_appointment_schedules AS
SELECT 
    a.appointment_id,
    p.patient_id,
    p.first_name || ' ' || p.last_name AS patient_name,
    p.phone AS patient_phone,
    d.doctor_id,
    'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
    dept.department_name,
    d.specialty,
    a.start_at,
    a.end_at,
    ROUND(EXTRACT(EPOCH FROM (a.end_at - a.start_at)) / 60) AS duration_minutes,
    a.status,
    a.reason
FROM appointments a
JOIN patients p ON a.patient_id = p.patient_id
JOIN doctors d ON a.doctor_id = d.doctor_id
JOIN departments dept ON d.department_id = dept.department_id;

-- -----------------------------------------------------------------------------
-- 3. View: Dynamic Billing Ledger (Eliminates 1:N Fan-Out Double Counting)
-- Pre-aggregates payments in a CTE before joining to invoices.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_invoice_ledger AS
WITH payment_summary AS (
    SELECT 
        invoice_id,
        COALESCE(SUM(CASE 
            WHEN payment_type = 'payment' THEN amount 
            WHEN payment_type IN ('refund', 'reversal') THEN -amount 
            ELSE 0 
        END), 0.00) AS net_paid,
        COUNT(CASE WHEN payment_type = 'payment' THEN 1 END) AS payment_count,
        MAX(paid_at) AS last_payment_date
    FROM payments
    GROUP BY invoice_id
)
SELECT 
    i.invoice_id,
    i.appointment_id,
    a.patient_id,
    p.first_name || ' ' || p.last_name AS patient_name,
    d.doctor_id,
    'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
    dept.department_name,
    i.total_amount,
    COALESCE(ps.net_paid, 0.00) AS total_paid,
    (i.total_amount - COALESCE(ps.net_paid, 0.00)) AS outstanding_balance,
    CASE 
        WHEN COALESCE(ps.net_paid, 0.00) >= i.total_amount THEN 'Paid in Full'
        WHEN COALESCE(ps.net_paid, 0.00) > 0 THEN 'Partially Paid'
        ELSE 'Unpaid'
    END AS payment_status,
    i.due_date,
    CASE 
        WHEN (i.total_amount - COALESCE(ps.net_paid, 0.00)) > 0 AND CURRENT_DATE > i.due_date THEN TRUE 
        ELSE FALSE 
    END AS is_overdue
FROM invoices i
JOIN appointments a ON i.appointment_id = a.appointment_id
JOIN patients p ON a.patient_id = p.patient_id
JOIN doctors d ON a.doctor_id = d.doctor_id
JOIN departments dept ON d.department_id = dept.department_id
LEFT JOIN payment_summary ps ON i.invoice_id = ps.invoice_id;

-- -----------------------------------------------------------------------------
-- 4. Materialized View: Daily Executive KPI Dashboard
-- Computes aggregated operations & finance by appointment date.
-- Includes a UNIQUE index to allow CONCURRENT refreshes without locking reads.
-- -----------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_hospital_daily_kpi CASCADE;

CREATE MATERIALIZED VIEW mv_hospital_daily_kpi AS
WITH invoice_agg AS (
    SELECT 
        a.start_at::DATE AS report_date,
        COUNT(a.appointment_id) AS total_appointments,
        COUNT(CASE WHEN a.status = 'completed' THEN 1 END) AS completed_appointments,
        COUNT(CASE WHEN a.status = 'cancelled' THEN 1 END) AS cancelled_appointments,
        COUNT(CASE WHEN a.status IN ('scheduled', 'confirmed', 'checked_in') THEN 1 END) AS active_pipeline,
        COUNT(DISTINCT a.patient_id) AS unique_patients_served,
        COUNT(DISTINCT a.doctor_id) AS active_doctors_on_duty,
        COALESCE(SUM(i.total_amount), 0.00) AS total_invoiced_revenue
    FROM appointments a
    LEFT JOIN invoices i ON a.appointment_id = i.appointment_id
    GROUP BY a.start_at::DATE
),
payment_daily AS (
    SELECT 
        a.start_at::DATE AS report_date,
        COALESCE(SUM(p.amount), 0.00) AS total_cash_collected
    FROM appointments a
    JOIN invoices i ON a.appointment_id = i.appointment_id
    JOIN payments p ON i.invoice_id = p.invoice_id
    WHERE p.payment_type = 'payment'
    GROUP BY a.start_at::DATE
)
SELECT 
    ia.report_date,
    ia.total_appointments,
    ia.completed_appointments,
    ia.cancelled_appointments,
    ia.active_pipeline,
    ia.unique_patients_served,
    ia.active_doctors_on_duty,
    ia.total_invoiced_revenue,
    COALESCE(pd.total_cash_collected, 0.00) AS total_cash_collected,
    (ia.total_invoiced_revenue - COALESCE(pd.total_cash_collected, 0.00)) AS outstanding_receivables
FROM invoice_agg ia
LEFT JOIN payment_daily pd ON ia.report_date = pd.report_date
ORDER BY ia.report_date DESC;

-- Unique index required for REFRESH MATERIALIZED VIEW CONCURRENTLY
CREATE UNIQUE INDEX idx_mv_daily_kpi_date ON mv_hospital_daily_kpi(report_date);

-- Procedure to refresh KPI view concurrently
CREATE OR REPLACE PROCEDURE sp_refresh_kpis()
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_hospital_daily_kpi;
    RAISE NOTICE 'Materialized view mv_hospital_daily_kpi refreshed successfully.';
END;
$$;
