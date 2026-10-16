-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Phase 2: Seed Test Data (Synthetic Records)
-- Database: hospital_management_db
-- =============================================================================

-- 1. Insert Departments
INSERT INTO departments (department_name, description) VALUES
('Cardiology', 'Diagnosis and treatment of congenital heart defects, coronary artery disease, and heart failure.'),
('Neurology', 'Specialized care for disorders of the nervous system, brain, and spinal cord.'),
('Orthopedics', 'Treatment of musculoskeletal system disorders, sports injuries, and joint replacement.'),
('Pediatrics', 'Medical care of infants, children, and adolescents.'),
('General Medicine', 'Primary adult healthcare, preventive medicine, and routine checkups.'),
('Oncology', 'Diagnosis, staging, and therapeutic management of cancers.')
ON CONFLICT (department_name) DO NOTHING;

-- 2. Insert Doctors
-- Note: consultation_fee is in standard currency units (e.g., INR or USD)
INSERT INTO doctors (department_id, first_name, last_name, specialty, consultation_fee, email, is_active) VALUES
(1, 'Aditi', 'Sharma', 'Interventional Cardiology', 1200.00, 'aditi.sharma@hospital.org', TRUE),
(1, 'Vikram', 'Mehta', 'Electrophysiology', 1500.00, 'vikram.mehta@hospital.org', TRUE),
(2, 'Rohit', 'Verma', 'Neurosurgeon', 1800.00, 'rohit.verma@hospital.org', TRUE),
(2, 'Priya', 'Nair', 'Cognitive Neurology', 1100.00, 'priya.nair@hospital.org', TRUE),
(3, 'Rajesh', 'Iyer', 'Joint Replacement Surgeon', 1400.00, 'rajesh.iyer@hospital.org', TRUE),
(3, 'Ananya', 'Deshmukh', 'Sports Orthopedics', 950.00, 'ananya.deshmukh@hospital.org', TRUE),
(4, 'Suresh', 'Kulkarni', 'Pediatrician', 800.00, 'suresh.kulkarni@hospital.org', TRUE),
(4, 'Neha', 'Gupta', 'Neonatology', 1000.00, 'neha.gupta@hospital.org', TRUE),
(5, 'Arun', 'Patel', 'Internal Medicine', 600.00, 'arun.patel@hospital.org', TRUE),
(6, 'Sunita', 'Rao', 'Medical Oncology', 2000.00, 'sunita.rao@hospital.org', TRUE)
ON CONFLICT (email) DO NOTHING;

-- 3. Insert Patients (Synthetic Demographics)
INSERT INTO patients (first_name, last_name, date_of_birth, phone, email) VALUES
('Aarav', 'Kapoor', '1988-04-12', '+91-9876543210', 'aarav.kapoor@example.com'),
('Diya', 'Saxena', '1995-11-23', '+91-9823456781', 'diya.saxena@example.com'),
('Kabir', 'Bose', '1976-08-05', '+91-9812345672', 'kabir.bose@example.com'),
('Meera', 'Menon', '2001-02-17', '+91-9734567893', 'meera.menon@example.com'),
('Rohan', 'Chatterjee', '1965-06-30', '+91-9645678904', 'rohan.chatterjee@example.com'),
('Ishaan', 'Malhotra', '2016-09-14', '+91-9556789015', 'ishaan.malhotra@example.com'),
('Ananya', 'Sen', '1992-12-01', '+91-9467890126', 'ananya.sen@example.com'),
('Tanvi', 'Joshi', '1983-07-19', '+91-9378901237', 'tanvi.joshi@example.com'),
('Siddharth', 'Rathore', '1958-03-25', '+91-9289012348', 'siddharth.rathore@example.com'),
('Pooja', 'Chopra', '2004-10-10', '+91-9190123459', 'pooja.chopra@example.com')
ON CONFLICT (email) DO NOTHING;

-- 4. Insert Doctor Availability (Recurring Weekly Shifts)
-- weekday: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
INSERT INTO doctor_availability (doctor_id, weekday, start_time, end_time) VALUES
(1, 1, '09:00:00', '13:00:00'),
(1, 1, '14:00:00', '17:00:00'),
(1, 3, '09:00:00', '13:00:00'),
(1, 5, '09:00:00', '13:00:00'),
(2, 2, '10:00:00', '16:00:00'),
(2, 4, '10:00:00', '16:00:00'),
(3, 1, '08:00:00', '12:00:00'),
(3, 3, '14:00:00', '18:00:00'),
(4, 2, '09:00:00', '14:00:00'),
(4, 5, '09:00:00', '14:00:00'),
(5, 1, '10:00:00', '15:00:00'),
(5, 4, '10:00:00', '15:00:00'),
(6, 2, '11:00:00', '16:00:00'),
(7, 1, '09:00:00', '13:00:00'),
(7, 3, '09:00:00', '13:00:00'),
(7, 5, '09:00:00', '13:00:00'),
(8, 2, '08:30:00', '12:30:00'),
(9, 1, '08:00:00', '14:00:00'),
(9, 2, '08:00:00', '14:00:00'),
(9, 3, '08:00:00', '14:00:00'),
(9, 4, '08:00:00', '14:00:00'),
(9, 5, '08:00:00', '14:00:00'),
(10, 3, '10:00:00', '16:00:00'),
(10, 5, '10:00:00', '16:00:00')
ON CONFLICT (doctor_id, weekday, start_time, end_time) DO NOTHING;

-- 5. Insert Sample Appointments
-- Notice: Consecutive appointments (e.g. 09:00-09:30 and 09:30-10:00) test half-open range compliance!
INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason) VALUES
-- Doctor 1 (Dr. Aditi Sharma) appointments on 2026-10-19 (Monday)
(1, 1, '2026-10-19 09:00:00+05:30', '2026-10-19 09:30:00+05:30', 'completed', 'Chest discomfort and ECG evaluation'),
(2, 1, '2026-10-19 09:30:00+05:30', '2026-10-19 10:00:00+05:30', 'completed', 'Routine post-angioplasty review'),
(3, 1, '2026-10-19 10:30:00+05:30', '2026-10-19 11:15:00+05:30', 'cancelled', 'Patient had scheduling emergency'),
(4, 1, '2026-10-19 11:30:00+05:30', '2026-10-19 12:00:00+05:30', 'checked_in', 'Hypertension management follow-up'),
(5, 1, '2026-10-19 14:00:00+05:30', '2026-10-19 14:45:00+05:30', 'confirmed', 'Palpitations and Holter monitor results'),

-- Doctor 3 (Dr. Rohit Verma - Neurology)
(5, 3, '2026-10-19 08:00:00+05:30', '2026-10-19 08:45:00+05:30', 'completed', 'Chronic migraine consultations'),
(6, 7, '2026-10-19 09:30:00+05:30', '2026-10-19 10:00:00+05:30', 'completed', 'Annual pediatric vaccination & wellness check'),

-- Doctor 5 (Dr. Rajesh Iyer - Orthopedics) on 2026-10-22 (Thursday)
(7, 5, '2026-10-22 10:00:00+05:30', '2026-10-22 10:45:00+05:30', 'scheduled', 'Knee joint pain after injury'),
(8, 9, '2026-10-22 11:00:00+05:30', '2026-10-22 11:30:00+05:30', 'scheduled', 'Routine blood glucose & thyroid panel review'),
(9, 10, '2026-10-21 10:30:00+05:30', '2026-10-21 11:30:00+05:30', 'completed', 'Oncology second opinion consultation');

-- 6. Insert Invoices (For Completed and Checked-in Appointments)
-- total_amount corresponds to consultation fee + diagnostic charges
INSERT INTO invoices (appointment_id, total_amount, due_date) VALUES
(1, 1700.00, '2026-10-26'),  -- Dr. Aditi (1200) + ECG (500)
(2, 1200.00, '2026-10-26'),  -- Dr. Aditi consultation
(4, 1200.00, '2026-10-26'),  -- Checked-in appointment
(6, 2500.00, '2026-10-26'),  -- Dr. Rohit (1800) + MRI review fee (700)
(7, 800.00,  '2026-10-26'),  -- Pediatric checkup
(10, 2000.00, '2026-10-28')   -- Oncology consultation
ON CONFLICT (appointment_id) DO NOTHING;

-- 7. Insert Payments (Demonstrating full, partial, and installment payments)
INSERT INTO payments (invoice_id, amount, payment_method, reference_code) VALUES
(1, 1700.00, 'upi', 'PAY-UPI-20261019-001'),        -- Invoice 1 paid in full
(2, 600.00,  'cash', 'PAY-CSH-20261019-002'),       -- Invoice 2: 1st installment
(2, 600.00,  'card', 'PAY-CRD-20261019-003'),       -- Invoice 2: 2nd installment (settled)
(3, 1200.00, 'card', 'PAY-CRD-20261019-004'),       -- Invoice 3 paid in full
(4, 2500.00, 'insurance', 'PAY-INS-20261019-005'),  -- Invoice 4 paid via insurance
(5, 800.00,  'upi', 'PAY-UPI-20261019-006'),        -- Invoice 5 paid in full
(6, 1000.00, 'bank_transfer', 'PAY-BNK-20261019-007') -- Invoice 6: Partial payment (1000 of 2000)
ON CONFLICT (reference_code) DO NOTHING;
