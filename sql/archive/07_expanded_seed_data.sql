-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Phase 2 Extension: High-Volume Expanded Synthetic Dataset
-- Database: hospital_management_db
-- =============================================================================

-- 1. Insert Additional Diverse Patients
INSERT INTO patients (first_name, last_name, date_of_birth, phone, email) VALUES
('Vikramaditya', 'Singhania', '1972-05-18', '+91-9811223344', 'vikram.singhania@example.com'),
('Kavita', 'Raman', '1989-08-29', '+91-9822334455', 'kavita.raman@example.com'),
('Devendra', 'Pandey', '1961-01-14', '+91-9833445566', 'devendra.pandey@example.com'),
('Simran', 'Kaur', '1998-11-04', '+91-9844556677', 'simran.kaur@example.com'),
('Farhan', 'Akhtar', '1985-03-22', '+91-9855667788', 'farhan.akhtar@example.com'),
('Deepika', 'Padukone', '1990-09-15', '+91-9866778899', 'deepika.p@example.com'),
('Karan', 'Johar', '1975-06-12', '+91-9877889900', 'karan.j@example.com'),
('Shraddha', 'Kapoor', '1993-02-28', '+91-9888990011', 'shraddha.k@example.com'),
('Ayushmann', 'Khurrana', '1984-12-09', '+91-9899001122', 'ayushmann.k@example.com'),
('Bhumi', 'Pednekar', '1991-07-21', '+91-9900112233', 'bhumi.p@example.com'),
('Varun', 'Dhawan', '1987-04-24', '+91-9911223344', 'varun.d@example.com'),
('Alia', 'Bhatt', '1993-03-15', '+91-9922334455', 'alia.b@example.com'),
('Ranbir', 'Kapoor', '1982-09-28', '+91-9933445566', 'ranbir.k@example.com'),
('Kriti', 'Sanon', '1990-07-26', '+91-9944556677', 'kriti.s@example.com'),
('Kartik', 'Aaryan', '1990-11-22', '+91-9955667788', 'kartik.a@example.com'),
('Kiara', 'Advani', '1992-07-31', '+91-9966778899', 'kiara.a@example.com'),
('Sidharth', 'Malhotra', '1985-01-16', '+91-9977889900', 'sidharth.m@example.com'),
('Sara', 'Ali Khan', '1995-08-12', '+91-9988990011', 'sara.ak@example.com'),
('Janhvi', 'Kapoor', '1997-03-06', '+91-9999001122', 'janhvi.k@example.com'),
('Ananya', 'Panday', '1998-10-30', '+91-9900011223', 'ananya.p@example.com')
ON CONFLICT (email) DO NOTHING;

-- 2. Bulk Appointments across past, current, and upcoming days
-- Using email lookup for robustness against sequence gaps
WITH appt_data(email, doctor_id, start_at, end_at, status, reason) AS (
    VALUES
    ('vikram.singhania@example.com', 1, '2026-10-12 09:00:00+05:30'::timestamptz, '2026-10-12 09:30:00+05:30'::timestamptz, 'completed', 'Pre-op cardiac fitness check'),
    ('kavita.raman@example.com', 1, '2026-10-12 09:30:00+05:30'::timestamptz, '2026-10-12 10:00:00+05:30'::timestamptz, 'completed', 'Echocardiogram follow-up'),
    ('devendra.pandey@example.com', 2, '2026-10-13 10:00:00+05:30'::timestamptz, '2026-10-13 10:45:00+05:30'::timestamptz, 'completed', 'Cardiac arrhythmia consultation'),
    ('simran.kaur@example.com', 2, '2026-10-13 11:00:00+05:30'::timestamptz, '2026-10-13 11:30:00+05:30'::timestamptz, 'completed', 'Pacemaker battery check'),
    ('farhan.akhtar@example.com', 3, '2026-10-12 08:00:00+05:30'::timestamptz, '2026-10-12 09:00:00+05:30'::timestamptz, 'completed', 'Trigeminal neuralgia review'),
    ('deepika.p@example.com', 4, '2026-10-13 09:30:00+05:30'::timestamptz, '2026-10-13 10:15:00+05:30'::timestamptz, 'completed', 'Epilepsy medication titration'),
    ('karan.j@example.com', 5, '2026-10-15 10:00:00+05:30'::timestamptz, '2026-10-15 10:30:00+05:30'::timestamptz, 'completed', 'Post-arthroscopy review'),
    ('shraddha.k@example.com', 6, '2026-10-13 11:00:00+05:30'::timestamptz, '2026-10-13 11:45:00+05:30'::timestamptz, 'completed', 'Rotator cuff injury rehab plan'),
    ('ayushmann.k@example.com', 7, '2026-10-12 09:00:00+05:30'::timestamptz, '2026-10-12 09:30:00+05:30'::timestamptz, 'completed', 'Infant 6-month developmental milestone assessment'),
    ('bhumi.p@example.com', 8, '2026-10-13 09:00:00+05:30'::timestamptz, '2026-10-13 09:45:00+05:30'::timestamptz, 'completed', 'Pre-term infant growth monitoring'),
    ('varun.d@example.com', 9, '2026-10-14 08:30:00+05:30'::timestamptz, '2026-10-14 09:00:00+05:30'::timestamptz, 'completed', 'Seasonal viral fever and dehydration management'),
    ('alia.b@example.com', 9, '2026-10-14 09:00:00+05:30'::timestamptz, '2026-10-14 09:30:00+05:30'::timestamptz, 'completed', 'Annual executive executive health panel'),
    ('ranbir.k@example.com', 10, '2026-10-14 10:00:00+05:30'::timestamptz, '2026-10-14 11:00:00+05:30'::timestamptz, 'completed', 'Post-chemotherapy blood count analysis'),
    ('kriti.s@example.com', 1, '2026-10-19 12:00:00+05:30'::timestamptz, '2026-10-19 12:30:00+05:30'::timestamptz, 'scheduled', 'Treadmill stress test discussion'),
    ('kartik.a@example.com', 2, '2026-10-20 10:30:00+05:30'::timestamptz, '2026-10-20 11:15:00+05:30'::timestamptz, 'confirmed', 'Holter monitoring analysis'),
    ('kiara.a@example.com', 3, '2026-10-21 14:00:00+05:30'::timestamptz, '2026-10-21 14:45:00+05:30'::timestamptz, 'confirmed', 'Lumbar disc herniation surgical evaluation'),
    ('sidharth.m@example.com', 4, '2026-10-23 10:00:00+05:30'::timestamptz, '2026-10-23 10:30:00+05:30'::timestamptz, 'scheduled', 'Memory clinic & cognitive evaluation'),
    ('sara.ak@example.com', 5, '2026-10-22 11:00:00+05:30'::timestamptz, '2026-10-22 11:45:00+05:30'::timestamptz, 'scheduled', 'Hip arthritis injection procedure'),
    ('janhvi.k@example.com', 6, '2026-10-20 12:00:00+05:30'::timestamptz, '2026-10-20 12:30:00+05:30'::timestamptz, 'scheduled', 'ACL reconstruction post-operative evaluation'),
    ('ananya.p@example.com', 7, '2026-10-21 09:00:00+05:30'::timestamptz, '2026-10-21 09:30:00+05:30'::timestamptz, 'scheduled', 'Pediatric asthma allergy testing'),
    ('aarav.kapoor@example.com', 8, '2026-10-20 09:00:00+05:30'::timestamptz, '2026-10-20 09:30:00+05:30'::timestamptz, 'scheduled', 'Toddler nutritional counseling'),
    ('diya.saxena@example.com', 9, '2026-10-21 08:30:00+05:30'::timestamptz, '2026-10-21 09:00:00+05:30'::timestamptz, 'scheduled', 'Type-2 diabetes quarterly HbA1c review'),
    ('kabir.bose@example.com', 10, '2026-10-23 10:00:00+05:30'::timestamptz, '2026-10-23 11:00:00+05:30'::timestamptz, 'confirmed', 'Immunotherapy treatment round 3')
)
INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
SELECT 
    p.patient_id, 
    ad.doctor_id, 
    ad.start_at, 
    ad.end_at, 
    ad.status, 
    ad.reason
FROM appt_data ad
JOIN patients p ON ad.email = p.email
WHERE NOT EXISTS (
    SELECT 1 FROM appointments a 
    WHERE a.doctor_id = ad.doctor_id 
      AND a.start_at = ad.start_at
);

-- 3. Invoices for Newly Completed Past Appointments
INSERT INTO invoices (appointment_id, total_amount, due_date)
SELECT 
    a.appointment_id,
    d.consultation_fee + (FLOOR(RANDOM() * 800 / 100) * 100)::NUMERIC(10, 2) AS total_amount,
    CURRENT_DATE + 7 AS due_date
FROM appointments a
JOIN doctors d ON a.doctor_id = d.doctor_id
WHERE a.status = 'completed'
  AND a.appointment_id NOT IN (SELECT appointment_id FROM invoices)
ON CONFLICT (appointment_id) DO NOTHING;

-- 4. Realistic Payments (Full & Installment) for Invoices
INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
SELECT 
    i.invoice_id,
    ROUND((i.total_amount * (CASE WHEN (i.invoice_id % 3) = 0 THEN 0.50 ELSE 1.00 END)), 2) AS amount,
    (ARRAY['upi', 'card', 'cash', 'bank_transfer', 'insurance'])[1 + (i.invoice_id % 5)] AS payment_method,
    'PAY-AUTO-' || i.invoice_id || '-' || FLOOR(RANDOM() * 90000 + 10000)::TEXT AS reference_code
FROM invoices i
WHERE i.invoice_id NOT IN (SELECT invoice_id FROM payments)
ON CONFLICT (reference_code) DO NOTHING;
