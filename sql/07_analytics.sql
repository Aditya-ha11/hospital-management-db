-- =============================================================================
-- Hospital Appointment and Patient Management System
-- File: sql/07_analytics.sql
-- Description: 20 Advanced SQL Analytics Queries for Data Science & Engineering
-- Features: JOINs, CTEs, Window Functions, Aggregates, Cohorts, and Reconciliation
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Query 01: Department Financial Performance & Collection Efficiency
-- Uses pre-aggregated CTEs to completely prevent 1:N fan-out discrepancies.
-- -----------------------------------------------------------------------------
WITH dept_invoices AS (
    SELECT 
        d.department_id,
        COALESCE(SUM(i.total_amount), 0.00) AS total_invoiced,
        COUNT(DISTINCT i.invoice_id) AS invoice_count
    FROM invoices i
    JOIN appointments a ON i.appointment_id = a.appointment_id
    JOIN doctors d ON a.doctor_id = d.doctor_id
    GROUP BY d.department_id
),
dept_payments AS (
    SELECT 
        d.department_id,
        COALESCE(SUM(p.amount), 0.00) AS total_collected,
        COUNT(DISTINCT p.payment_id) AS payment_count
    FROM payments p
    JOIN invoices i ON p.invoice_id = i.invoice_id
    JOIN appointments a ON i.appointment_id = a.appointment_id
    JOIN doctors d ON a.doctor_id = d.doctor_id
    WHERE p.payment_type = 'payment'
    GROUP BY d.department_id
)
SELECT 
    dept.department_name,
    COUNT(DISTINCT d.doctor_id) AS active_doctors,
    COUNT(DISTINCT a.appointment_id) AS total_appointments,
    COALESCE(di.total_invoiced, 0.00) AS total_amount_invoiced,
    COALESCE(dp.total_collected, 0.00) AS total_amount_collected,
    (COALESCE(di.total_invoiced, 0.00) - COALESCE(dp.total_collected, 0.00)) AS outstanding_balance,
    ROUND(
        COALESCE(dp.total_collected, 0.00) / NULLIF(di.total_invoiced, 0.00) * 100, 1
    ) AS collection_efficiency_pct
FROM departments dept
LEFT JOIN doctors d ON dept.department_id = d.department_id
LEFT JOIN appointments a ON d.doctor_id = a.doctor_id
LEFT JOIN dept_invoices di ON dept.department_id = di.department_id
LEFT JOIN dept_payments dp ON dept.department_id = dp.department_id
GROUP BY dept.department_id, dept.department_name, di.total_invoiced, dp.total_collected
ORDER BY total_amount_invoiced DESC;


-- -----------------------------------------------------------------------------
-- Query 02: Doctor Workload, Completion Rate & Revenue Ranking
-- Features: DENSE_RANK() Window Function over Billed Revenue
-- -----------------------------------------------------------------------------
WITH doctor_billed AS (
    SELECT 
        a.doctor_id,
        COALESCE(SUM(i.total_amount), 0.00) AS billed_revenue
    FROM appointments a
    JOIN invoices i ON a.appointment_id = i.appointment_id
    GROUP BY a.doctor_id
)
SELECT 
    d.doctor_id,
    'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
    dept.department_name,
    d.specialty,
    COUNT(a.appointment_id) AS total_appointments,
    COUNT(CASE WHEN a.status = 'completed' THEN 1 END) AS completed_appointments,
    COUNT(CASE WHEN a.status = 'cancelled' THEN 1 END) AS cancelled_appointments,
    ROUND(
        COUNT(CASE WHEN a.status = 'completed' THEN 1 END)::NUMERIC / 
        NULLIF(COUNT(a.appointment_id), 0) * 100, 1
    ) AS completion_rate_pct,
    COALESCE(db.billed_revenue, 0.00) AS total_billed_revenue,
    DENSE_RANK() OVER (ORDER BY COALESCE(db.billed_revenue, 0.00) DESC) AS revenue_rank
FROM doctors d
JOIN departments dept ON d.department_id = dept.department_id
LEFT JOIN appointments a ON d.doctor_id = a.doctor_id
LEFT JOIN doctor_billed db ON d.doctor_id = db.doctor_id
GROUP BY d.doctor_id, d.first_name, d.last_name, dept.department_name, d.specialty, db.billed_revenue
ORDER BY revenue_rank;


-- -----------------------------------------------------------------------------
-- Query 03: Doctor Shift Capacity Utilization Rate
-- Compares weekly rostered hours against actual booked hours
-- -----------------------------------------------------------------------------
WITH doctor_roster AS (
    SELECT 
        doctor_id,
        SUM(EXTRACT(EPOCH FROM (end_time - start_time)) / 3600.0) AS weekly_available_hours
    FROM doctor_availability
    GROUP BY doctor_id
),
doctor_bookings AS (
    SELECT 
        doctor_id,
        ROUND(SUM(EXTRACT(EPOCH FROM (end_at - start_at)) / 3600.0)::NUMERIC, 2) AS booked_hours,
        COUNT(appointment_id) AS total_bookings
    FROM appointments
    WHERE status != 'cancelled'
    GROUP BY doctor_id
)
SELECT 
    d.doctor_id,
    'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
    dept.department_name,
    COALESCE(dr.weekly_available_hours, 0) AS weekly_shift_hours,
    COALESCE(db.booked_hours, 0) AS actual_booked_hours,
    COALESCE(db.total_bookings, 0) AS active_appointments,
    CASE 
        WHEN COALESCE(dr.weekly_available_hours, 0) > 0 THEN 
            ROUND((COALESCE(db.booked_hours, 0) / dr.weekly_available_hours * 100), 1)
        ELSE 0.0 
    END AS capacity_utilization_pct
FROM doctors d
JOIN departments dept ON d.department_id = dept.department_id
LEFT JOIN doctor_roster dr ON d.doctor_id = dr.doctor_id
LEFT JOIN doctor_bookings db ON d.doctor_id = db.doctor_id
ORDER BY capacity_utilization_pct DESC;


-- -----------------------------------------------------------------------------
-- Query 04: Patient Lifetime Value (LTV) & Top Healthcare Consumers
-- -----------------------------------------------------------------------------
SELECT 
    p.patient_id,
    p.first_name || ' ' || p.last_name AS patient_name,
    p.email,
    COUNT(DISTINCT a.appointment_id) AS total_visits,
    COUNT(DISTINCT i.invoice_id) AS total_invoices_issued,
    COALESCE(SUM(i.total_amount), 0.00) AS total_lifetime_billed,
    COALESCE(SUM(p_agg.total_paid), 0.00) AS total_lifetime_paid,
    (COALESCE(SUM(i.total_amount), 0.00) - COALESCE(SUM(p_agg.total_paid), 0.00)) AS total_outstanding_due
FROM patients p
LEFT JOIN appointments a ON p.patient_id = a.patient_id
LEFT JOIN invoices i ON a.appointment_id = i.appointment_id
LEFT JOIN (
    SELECT invoice_id, SUM(amount) AS total_paid
    FROM payments
    WHERE payment_type = 'payment'
    GROUP BY invoice_id
) p_agg ON i.invoice_id = p_agg.invoice_id
GROUP BY p.patient_id, p.first_name, p.last_name, p.email
HAVING COUNT(a.appointment_id) > 0
ORDER BY total_lifetime_billed DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Query 05: Patient Revisit Interval Analysis using LAG()
-- Calculates the number of days between consecutive visits for each patient
-- -----------------------------------------------------------------------------
WITH patient_timeline AS (
    SELECT 
        p.patient_id,
        p.first_name || ' ' || p.last_name AS patient_name,
        a.appointment_id,
        a.start_at,
        d.first_name || ' ' || d.last_name AS doctor_name,
        ROW_NUMBER() OVER (PARTITION BY p.patient_id ORDER BY a.start_at ASC) AS visit_seq,
        LAG(a.start_at) OVER (PARTITION BY p.patient_id ORDER BY a.start_at ASC) AS previous_visit_start
    FROM patients p
    JOIN appointments a ON p.patient_id = a.patient_id
    JOIN doctors d ON a.doctor_id = d.doctor_id
)
SELECT 
    patient_id,
    patient_name,
    visit_seq,
    doctor_name,
    start_at::DATE AS visit_date,
    previous_visit_start::DATE AS prior_visit_date,
    (start_at::DATE - previous_visit_start::DATE) AS days_since_last_visit
FROM patient_timeline
WHERE previous_visit_start IS NOT NULL
ORDER BY days_since_last_visit ASC, patient_id;


-- -----------------------------------------------------------------------------
-- Query 06: Operational Peak-Hour Heatmap
-- Analyzes appointment distribution across day of week and hour of day
-- -----------------------------------------------------------------------------
SELECT 
    TO_CHAR(start_at, 'Day') AS day_of_week,
    EXTRACT(DOW FROM start_at) AS day_num,
    EXTRACT(HOUR FROM start_at) AS hour_of_day,
    COUNT(appointment_id) AS appointment_volume,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) AS completed_count,
    COUNT(CASE WHEN status = 'cancelled' THEN 1 END) AS cancelled_count
FROM appointments
GROUP BY day_of_week, day_num, hour_of_day
ORDER BY day_num, hour_of_day;


-- -----------------------------------------------------------------------------
-- Query 07: Appointment Scheduling Lead-Time Analysis
-- Measures the duration between when a booking is created vs when it occurs
-- -----------------------------------------------------------------------------
SELECT 
    a.status,
    COUNT(a.appointment_id) AS count_appointments,
    ROUND(AVG(EXTRACT(EPOCH FROM (a.start_at - a.created_at)) / 86400.0), 1) AS avg_lead_time_days,
    ROUND(MIN(EXTRACT(EPOCH FROM (a.start_at - a.created_at)) / 86400.0), 1) AS min_lead_time_days,
    ROUND(MAX(EXTRACT(EPOCH FROM (a.start_at - a.created_at)) / 86400.0), 1) AS max_lead_time_days
FROM appointments a
GROUP BY a.status
ORDER BY count_appointments DESC;


-- -----------------------------------------------------------------------------
-- Query 08: Cancellation & No-Show Rate by Clinical Department
-- -----------------------------------------------------------------------------
SELECT 
    dept.department_name,
    COUNT(a.appointment_id) AS total_scheduled,
    COUNT(CASE WHEN a.status = 'completed' THEN 1 END) AS completed,
    COUNT(CASE WHEN a.status = 'cancelled' THEN 1 END) AS cancelled_no_show,
    ROUND(
        COUNT(CASE WHEN a.status = 'cancelled' THEN 1 END)::NUMERIC / 
        NULLIF(COUNT(a.appointment_id), 0) * 100, 1
    ) AS cancellation_rate_pct
FROM departments dept
JOIN doctors d ON dept.department_id = d.department_id
JOIN appointments a ON d.doctor_id = a.doctor_id
GROUP BY dept.department_id, dept.department_name
ORDER BY cancellation_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- Query 09: 7-Day Moving Average of Billed Revenue (Window Functions)
-- -----------------------------------------------------------------------------
WITH daily_billing AS (
    SELECT 
        a.start_at::DATE AS billing_date,
        SUM(i.total_amount) AS daily_billed
    FROM appointments a
    JOIN invoices i ON a.appointment_id = i.appointment_id
    GROUP BY a.start_at::DATE
)
SELECT 
    billing_date,
    daily_billed,
    ROUND(
        AVG(daily_billed) OVER (
            ORDER BY billing_date 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) AS rolling_7day_avg_revenue
FROM daily_billing
ORDER BY billing_date DESC;


-- -----------------------------------------------------------------------------
-- Query 10: Cumulative Running Total Revenue
-- -----------------------------------------------------------------------------
WITH daily_revenue AS (
    SELECT 
        a.start_at::DATE AS rev_date,
        SUM(i.total_amount) AS daily_rev
    FROM appointments a
    JOIN invoices i ON a.appointment_id = i.appointment_id
    GROUP BY a.start_at::DATE
)
SELECT 
    rev_date,
    daily_rev,
    SUM(daily_rev) OVER (ORDER BY rev_date ASC) AS cumulative_running_total
FROM daily_revenue
ORDER BY rev_date ASC;


-- -----------------------------------------------------------------------------
-- Query 11: Payment Method Breakdown & Financial Channel Share
-- -----------------------------------------------------------------------------
SELECT 
    payment_method,
    COUNT(payment_id) AS transaction_count,
    SUM(amount) AS total_amount_collected,
    ROUND(AVG(amount), 2) AS avg_transaction_size,
    ROUND(
        SUM(amount) / (SELECT SUM(amount) FROM payments WHERE payment_type = 'payment') * 100, 1
    ) AS market_share_pct
FROM payments
WHERE payment_type = 'payment'
GROUP BY payment_method
ORDER BY total_amount_collected DESC;


-- -----------------------------------------------------------------------------
-- Query 12: Outstanding Receivables Aging Analysis (0-30, 31-60, 60+ Days)
-- -----------------------------------------------------------------------------
WITH aging_buckets AS (
    SELECT 
        invoice_id,
        outstanding_balance,
        due_date,
        CASE 
            WHEN CURRENT_DATE <= due_date THEN 'Current (Not Due)'
            WHEN CURRENT_DATE - due_date BETWEEN 1 AND 30 THEN '1-30 Days Past Due'
            WHEN CURRENT_DATE - due_date BETWEEN 31 AND 60 THEN '31-60 Days Past Due'
            ELSE '60+ Days Past Due'
        END AS aging_tier
    FROM v_invoice_ledger
    WHERE outstanding_balance > 0
)
SELECT 
    aging_tier,
    COUNT(invoice_id) AS invoice_count,
    SUM(outstanding_balance) AS total_uncollected_balance,
    ROUND(
        SUM(outstanding_balance) / (SELECT SUM(outstanding_balance) FROM v_invoice_ledger) * 100, 1
    ) AS pct_of_total_receivables
FROM aging_buckets
GROUP BY aging_tier
ORDER BY total_uncollected_balance DESC;


-- -----------------------------------------------------------------------------
-- Query 13: High-Risk Chronic Care Patients (Hypertension & Diabetes)
-- -----------------------------------------------------------------------------
SELECT 
    p.patient_id,
    p.first_name || ' ' || p.last_name AS patient_name,
    EXTRACT(YEAR FROM AGE(p.date_of_birth)) AS age,
    p.phone,
    COUNT(a.appointment_id) AS total_visits,
    STRING_AGG(DISTINCT dept.department_name, ', ') AS departments_consulted
FROM patients p
JOIN appointments a ON p.patient_id = a.patient_id
JOIN doctors d ON a.doctor_id = d.doctor_id
JOIN departments dept ON d.department_id = dept.department_id
WHERE a.reason ILIKE '%hypertens%' 
   OR a.reason ILIKE '%diabet%'
GROUP BY p.patient_id, p.first_name, p.last_name, p.date_of_birth, p.phone
HAVING COUNT(a.appointment_id) >= 1
ORDER BY total_visits DESC;


-- -----------------------------------------------------------------------------
-- Query 14: Patient Retention Rate (First-Time vs Returning Patients)
-- -----------------------------------------------------------------------------
WITH patient_visit_counts AS (
    SELECT 
        patient_id,
        COUNT(appointment_id) AS total_bookings
    FROM appointments
    GROUP BY patient_id
)
SELECT 
    CASE WHEN total_bookings > 1 THEN 'Returning Patient' ELSE 'One-Time Visitor' END AS patient_segment,
    COUNT(patient_id) AS patient_count,
    ROUND(COUNT(patient_id)::NUMERIC / (SELECT COUNT(*) FROM patient_visit_counts) * 100, 1) AS segment_share_pct
FROM patient_visit_counts
GROUP BY patient_segment;


-- -----------------------------------------------------------------------------
-- Query 15: Average Consultation Duration by Medical Specialty
-- -----------------------------------------------------------------------------
SELECT 
    dept.department_name,
    d.specialty,
    COUNT(a.appointment_id) AS sample_size,
    ROUND(AVG(EXTRACT(EPOCH FROM (a.end_at - a.start_at)) / 60.0), 1) AS avg_duration_minutes,
    MIN(ROUND(EXTRACT(EPOCH FROM (a.end_at - a.start_at)) / 60.0)) AS min_duration_minutes,
    MAX(ROUND(EXTRACT(EPOCH FROM (a.end_at - a.start_at)) / 60.0)) AS max_duration_minutes
FROM doctors d
JOIN departments dept ON d.department_id = dept.department_id
JOIN appointments a ON d.doctor_id = a.doctor_id
GROUP BY dept.department_name, d.specialty
ORDER BY avg_duration_minutes DESC;


-- -----------------------------------------------------------------------------
-- Query 16: Active Operational Pipeline Roster
-- -----------------------------------------------------------------------------
SELECT 
    a.appointment_id,
    a.start_at,
    p.first_name || ' ' || p.last_name AS patient_name,
    'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
    dept.department_name,
    a.status,
    a.reason
FROM appointments a
JOIN patients p ON a.patient_id = p.patient_id
JOIN doctors d ON a.doctor_id = d.doctor_id
JOIN departments dept ON d.department_id = dept.department_id
WHERE a.status IN ('scheduled', 'confirmed', 'checked_in')
ORDER BY a.start_at ASC
LIMIT 15;


-- -----------------------------------------------------------------------------
-- Query 17: Audit Trail of Appointment Reschedules & Status Transitions
-- -----------------------------------------------------------------------------
SELECT 
    al.audit_id,
    al.appointment_id,
    al.action_type,
    al.old_status,
    al.new_status,
    al.old_start_at,
    al.new_start_at,
    al.changed_by,
    al.changed_at,
    al.notes
FROM appointment_audit_log al
ORDER BY al.changed_at DESC
LIMIT 15;


-- -----------------------------------------------------------------------------
-- Query 18: Payment Reversals and Financial Auditing
-- -----------------------------------------------------------------------------
SELECT 
    p.payment_id AS reversal_id,
    p.invoice_id,
    p.amount AS reversed_amount,
    p.paid_at AS reversal_timestamp,
    orig.payment_id AS original_payment_id,
    orig.amount AS original_amount,
    orig.paid_at AS original_payment_date
FROM payments p
LEFT JOIN payments orig ON p.reversed_payment_id = orig.payment_id
WHERE p.payment_type = 'reversal'
ORDER BY p.paid_at DESC;


-- -----------------------------------------------------------------------------
-- Query 19: Doctor Daily Scheduling Density
-- -----------------------------------------------------------------------------
SELECT 
    a.doctor_id,
    'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
    a.start_at::DATE AS appointment_date,
    COUNT(a.appointment_id) AS daily_patient_load,
    ROUND(SUM(EXTRACT(EPOCH FROM (a.end_at - a.start_at)) / 3600.0)::NUMERIC, 1) AS consultation_hours
FROM appointments a
JOIN doctors d ON a.doctor_id = d.doctor_id
WHERE a.status != 'cancelled'
GROUP BY a.doctor_id, d.first_name, d.last_name, a.start_at::DATE
HAVING COUNT(a.appointment_id) > 1
ORDER BY daily_patient_load DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Query 20: Mathematical Ledger Reconciliation Proof (Zero-Discrepancy Assert)
-- Proves that Total Billed = Total Collected + Outstanding Balance = Sum of Departments
-- -----------------------------------------------------------------------------
WITH invoice_totals AS (
    SELECT COALESCE(SUM(total_amount), 0.00) AS total_invoiced FROM invoices
),
payment_totals AS (
    SELECT COALESCE(SUM(amount), 0.00) AS total_collected FROM payments WHERE payment_type = 'payment'
),
ledger_balance AS (
    SELECT COALESCE(SUM(outstanding_balance), 0.00) AS total_outstanding FROM v_invoice_ledger
),
dept_totals AS (
    SELECT COALESCE(SUM(i.total_amount), 0.00) AS total_dept_invoiced
    FROM invoices i
    JOIN appointments a ON i.appointment_id = a.appointment_id
    JOIN doctors d ON a.doctor_id = d.doctor_id
)
SELECT 
    it.total_invoiced,
    pt.total_collected,
    lb.total_outstanding,
    dt.total_dept_invoiced,
    (it.total_invoiced - (pt.total_collected + lb.total_outstanding)) AS ledger_discrepancy,
    (it.total_invoiced - dt.total_dept_invoiced) AS department_fanout_discrepancy,
    CASE 
        WHEN (it.total_invoiced = pt.total_collected + lb.total_outstanding)
         AND (it.total_invoiced = dt.total_dept_invoiced)
        THEN 'PERFECT RECONCILIATION [PASS]'
        ELSE 'RECONCILIATION FAILED [FAIL]'
    END AS audit_verdict
FROM invoice_totals it
CROSS JOIN payment_totals pt
CROSS JOIN ledger_balance lb
CROSS JOIN dept_totals dt;
