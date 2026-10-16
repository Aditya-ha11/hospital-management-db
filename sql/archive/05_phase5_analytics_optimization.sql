-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Phase 5: SQL Analytics, Reporting Views, and Performance Optimization
-- Database: hospital_management_db
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Performance Indexes (Foreign Keys & Common Search/Filter Paths)
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_doctors_department ON doctors(department_id);
CREATE INDEX IF NOT EXISTS idx_appointments_doctor_date ON appointments(doctor_id, start_at);
CREATE INDEX IF NOT EXISTS idx_appointments_patient ON appointments(patient_id, start_at);
CREATE INDEX IF NOT EXISTS idx_appointments_status ON appointments(status);
CREATE INDEX IF NOT EXISTS idx_invoices_due ON invoices(due_date);
CREATE INDEX IF NOT EXISTS idx_payments_invoice ON payments(invoice_id);

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
-- 3. View: Dynamic Billing Ledger (Outstanding Balances without Redundant Columns)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_invoice_ledger AS
WITH payment_summary AS (
    SELECT 
        invoice_id,
        COALESCE(SUM(amount), 0) AS total_paid,
        COUNT(payment_id) AS payment_count,
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
    COALESCE(ps.total_paid, 0) AS total_paid,
    (i.total_amount - COALESCE(ps.total_paid, 0)) AS outstanding_balance,
    CASE 
        WHEN COALESCE(ps.total_paid, 0) >= i.total_amount THEN 'Paid in Full'
        WHEN COALESCE(ps.total_paid, 0) > 0 THEN 'Partially Paid'
        ELSE 'Unpaid'
    END AS payment_status,
    i.due_date,
    CASE 
        WHEN (i.total_amount - COALESCE(ps.total_paid, 0)) > 0 AND CURRENT_DATE > i.due_date THEN TRUE 
        ELSE FALSE 
    END AS is_overdue
FROM invoices i
JOIN appointments a ON i.appointment_id = a.appointment_id
JOIN patients p ON a.patient_id = p.patient_id
JOIN doctors d ON a.doctor_id = d.doctor_id
JOIN departments dept ON d.department_id = dept.department_id
LEFT JOIN payment_summary ps ON i.invoice_id = ps.invoice_id;

-- -----------------------------------------------------------------------------
-- 4. Analytics Query 1: Doctor Workload, Completion Rate & Revenue Generated
-- Uses CTEs, Window Functions, and Aggregate Filtering
-- -----------------------------------------------------------------------------
SELECT 
    d.doctor_id,
    'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
    dept.department_name,
    COUNT(a.appointment_id) AS total_appointments,
    COUNT(CASE WHEN a.status = 'completed' THEN 1 END) AS completed_appointments,
    COUNT(CASE WHEN a.status = 'cancelled' THEN 1 END) AS cancelled_appointments,
    ROUND(
        COUNT(CASE WHEN a.status = 'completed' THEN 1 END)::NUMERIC / 
        NULLIF(COUNT(a.appointment_id), 0) * 100, 1
    ) AS completion_rate_pct,
    COALESCE(SUM(i.total_amount), 0) AS total_billed_revenue,
    DENSE_RANK() OVER (ORDER BY COALESCE(SUM(i.total_amount), 0) DESC) AS revenue_rank
FROM doctors d
JOIN departments dept ON d.department_id = dept.department_id
LEFT JOIN appointments a ON d.doctor_id = a.doctor_id
LEFT JOIN invoices i ON a.appointment_id = i.appointment_id
GROUP BY d.doctor_id, d.first_name, d.last_name, dept.department_name
ORDER BY revenue_rank;

-- -----------------------------------------------------------------------------
-- 5. Analytics Query 2: Departmental Financial Performance & Collection Efficiency
-- -----------------------------------------------------------------------------
SELECT 
    dept.department_name,
    COUNT(DISTINCT d.doctor_id) AS active_doctors,
    COUNT(DISTINCT a.appointment_id) AS total_booked_appointments,
    COALESCE(SUM(i.total_amount), 0) AS total_amount_invoiced,
    COALESCE(SUM(p.amount), 0) AS total_amount_collected,
    (COALESCE(SUM(i.total_amount), 0) - COALESCE(SUM(p.amount), 0)) AS total_outstanding,
    ROUND(
        COALESCE(SUM(p.amount), 0)::NUMERIC / 
        NULLIF(SUM(i.total_amount), 0) * 100, 1
    ) AS collection_efficiency_pct
FROM departments dept
LEFT JOIN doctors d ON dept.department_id = d.department_id
LEFT JOIN appointments a ON d.doctor_id = a.doctor_id
LEFT JOIN invoices i ON a.appointment_id = i.appointment_id
LEFT JOIN payments p ON i.invoice_id = p.invoice_id
GROUP BY dept.department_name
ORDER BY total_amount_invoiced DESC;

-- -----------------------------------------------------------------------------
-- 6. Analytics Query 3: Patient Booking Frequency & Window Function Analytics
-- -----------------------------------------------------------------------------
WITH patient_stats AS (
    SELECT 
        p.patient_id,
        p.first_name || ' ' || p.last_name AS patient_name,
        EXTRACT(YEAR FROM AGE(p.date_of_birth)) AS patient_age,
        a.appointment_id,
        a.start_at,
        d.first_name || ' ' || d.last_name AS doctor_name,
        ROW_NUMBER() OVER (PARTITION BY p.patient_id ORDER BY a.start_at ASC) AS visit_number,
        LAG(a.start_at) OVER (PARTITION BY p.patient_id ORDER BY a.start_at ASC) AS prior_visit_date
    FROM patients p
    JOIN appointments a ON p.patient_id = a.patient_id
    JOIN doctors d ON a.doctor_id = d.doctor_id
)
SELECT 
    patient_id,
    patient_name,
    patient_age,
    visit_number,
    doctor_name,
    start_at::DATE AS visit_date,
    prior_visit_date::DATE AS previous_visit_date,
    (start_at::DATE - prior_visit_date::DATE) AS days_since_last_visit
FROM patient_stats
ORDER BY patient_id, visit_number;
