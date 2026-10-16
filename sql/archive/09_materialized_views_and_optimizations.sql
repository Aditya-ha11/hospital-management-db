-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Phase 5 Extension: Materialized Views, Doctor Utilization & Advanced Analytics
-- Database: hospital_management_db
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Materialized View: Daily Executive KPI Dashboard
-- Computes aggregated operations & finance by appointment date.
-- Includes a UNIQUE index to allow CONCURRENT refreshes without locking reads.
-- -----------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_hospital_daily_kpi CASCADE;

CREATE MATERIALIZED VIEW mv_hospital_daily_kpi AS
SELECT 
    a.start_at::DATE AS report_date,
    COUNT(a.appointment_id) AS total_appointments,
    COUNT(CASE WHEN a.status = 'completed' THEN 1 END) AS completed_appointments,
    COUNT(CASE WHEN a.status = 'cancelled' THEN 1 END) AS cancelled_appointments,
    COUNT(CASE WHEN a.status IN ('scheduled', 'confirmed', 'checked_in') THEN 1 END) AS active_pipeline,
    COUNT(DISTINCT a.patient_id) AS unique_patients_served,
    COUNT(DISTINCT a.doctor_id) AS active_doctors_on_duty,
    COALESCE(SUM(i.total_amount), 0.00) AS total_invoiced_revenue,
    COALESCE(SUM(p_agg.total_paid), 0.00) AS total_cash_collected,
    (COALESCE(SUM(i.total_amount), 0.00) - COALESCE(SUM(p_agg.total_paid), 0.00)) AS outstanding_receivables
FROM appointments a
LEFT JOIN invoices i ON a.appointment_id = i.appointment_id
LEFT JOIN (
    SELECT invoice_id, SUM(amount) AS total_paid
    FROM payments
    GROUP BY invoice_id
) p_agg ON i.invoice_id = p_agg.invoice_id
GROUP BY a.start_at::DATE
ORDER BY report_date DESC;

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

-- -----------------------------------------------------------------------------
-- 2. Advanced Analytics Query: Doctor Capacity Utilization Rate
-- Compares weekly scheduled appointment hours against total weekly available hours
-- -----------------------------------------------------------------------------
WITH doctor_available_hours AS (
    SELECT 
        doctor_id,
        SUM(EXTRACT(EPOCH FROM (end_time - start_time)) / 3600.0) AS weekly_available_hours
    FROM doctor_availability
    GROUP BY doctor_id
),
doctor_booked_hours AS (
    SELECT 
        doctor_id,
        ROUND(SUM(EXTRACT(EPOCH FROM (end_at - start_at)) / 3600.0)::NUMERIC, 2) AS total_booked_hours,
        COUNT(appointment_id) AS total_bookings
    FROM appointments
    WHERE status != 'cancelled'
    GROUP BY doctor_id
)
SELECT 
    d.doctor_id,
    'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
    dept.department_name,
    COALESCE(dah.weekly_available_hours, 0) AS weekly_shift_hours,
    COALESCE(dbh.total_booked_hours, 0) AS actual_booked_hours,
    COALESCE(dbh.total_bookings, 0) AS active_appointments,
    CASE 
        WHEN COALESCE(dah.weekly_available_hours, 0) > 0 THEN 
            ROUND((COALESCE(dbh.total_booked_hours, 0) / dah.weekly_available_hours * 100), 1)
        ELSE 0.0 
    END AS capacity_utilization_pct
FROM doctors d
JOIN departments dept ON d.department_id = dept.department_id
LEFT JOIN doctor_available_hours dah ON d.doctor_id = dah.doctor_id
LEFT JOIN doctor_booked_hours dbh ON d.doctor_id = dbh.doctor_id
ORDER BY capacity_utilization_pct DESC;

-- -----------------------------------------------------------------------------
-- 3. Advanced Analytics Query: Patient Lifetime Value & Invoicing Cohort
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
    GROUP BY invoice_id
) p_agg ON i.invoice_id = p_agg.invoice_id
GROUP BY p.patient_id, p.first_name, p.last_name, p.email
HAVING COUNT(a.appointment_id) > 0
ORDER BY total_lifetime_billed DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- 4. Hourly Peak Booking Distribution (Operational Scheduling Heatmap)
-- -----------------------------------------------------------------------------
SELECT 
    TO_CHAR(start_at, 'Day') AS day_of_week,
    EXTRACT(DOW FROM start_at) AS day_num,
    EXTRACT(HOUR FROM start_at) AS hour_of_day,
    COUNT(appointment_id) AS appointment_volume
FROM appointments
GROUP BY day_of_week, day_num, hour_of_day
ORDER BY day_num, hour_of_day;

-- -----------------------------------------------------------------------------
-- 5. Execution Plan Performance Verification (Index Scan vs Sequential Scan)
-- -----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT a.appointment_id, p.first_name, d.first_name, a.start_at
FROM appointments a
JOIN patients p ON a.patient_id = p.patient_id
JOIN doctors d ON a.doctor_id = d.doctor_id
WHERE a.doctor_id = 1 
  AND a.start_at >= '2026-10-01' 
  AND a.start_at <= '2026-10-31';
