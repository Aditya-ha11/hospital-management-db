-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Phase 1: Schema Definition & Database Design
-- Database: hospital_management_db
-- =============================================================================

-- Step 1: Enable required extensions
-- btree_gist enables B-tree indexing within GiST (Generalized Search Tree),
-- allowing scalar columns (like BIGINT doctor_id / patient_id) to be combined
-- with range columns in EXCLUDE constraints.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Step 2: Departments table
CREATE TABLE IF NOT EXISTS departments (
    department_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Step 3: Doctors table
CREATE TABLE IF NOT EXISTS doctors (
    doctor_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id BIGINT NOT NULL,
    first_name VARCHAR(80) NOT NULL,
    last_name VARCHAR(80) NOT NULL,
    specialty VARCHAR(100) NOT NULL,
    consultation_fee NUMERIC(10, 2) NOT NULL,
    email VARCHAR(255) UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_doctor_department
        FOREIGN KEY (department_id)
        REFERENCES departments(department_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_consultation_fee
        CHECK (consultation_fee >= 0)
);

-- Step 4: Patients table
CREATE TABLE IF NOT EXISTS patients (
    patient_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name VARCHAR(80) NOT NULL,
    last_name VARCHAR(80) NOT NULL,
    date_of_birth DATE,
    phone VARCHAR(20),
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_patient_dob
        CHECK (date_of_birth IS NULL OR date_of_birth <= CURRENT_DATE)
);

-- Step 5: Doctor Availability table (recurring weekly schedule)
CREATE TABLE IF NOT EXISTS doctor_availability (
    availability_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    weekday SMALLINT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,

    CONSTRAINT fk_availability_doctor
        FOREIGN KEY (doctor_id)
        REFERENCES doctors(doctor_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_weekday
        CHECK (weekday BETWEEN 0 AND 6),

    CONSTRAINT chk_availability_time
        CHECK (start_time < end_time),

    CONSTRAINT uq_doctor_availability
        UNIQUE (doctor_id, weekday, start_time, end_time)
);

-- Step 6: Appointments table (with GiST exclusion constraints for overlapping slots)
CREATE TABLE IF NOT EXISTS appointments (
    appointment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'scheduled',
    reason VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_appointment_patient
        FOREIGN KEY (patient_id)
        REFERENCES patients(patient_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_appointment_doctor
        FOREIGN KEY (doctor_id)
        REFERENCES doctors(doctor_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_appointment_time
        CHECK (start_at < end_at),

    CONSTRAINT chk_appointment_status
        CHECK (status IN (
            'scheduled',
            'confirmed',
            'checked_in',
            'completed',
            'cancelled'
        )),

    -- Prevents double-booking the doctor across active appointment statuses.
    -- Half-open range '[)' ensures consecutive appointments (e.g. 10:00-10:30 and 10:30-11:00) do NOT conflict.
    CONSTRAINT no_doctor_overlapping_appointments
        EXCLUDE USING gist (
            doctor_id WITH =,
            tstzrange(start_at, end_at, '[)') WITH &&
        )
        WHERE (status IN ('scheduled', 'confirmed', 'checked_in')),

    -- Prevents a patient from having simultaneous active appointments
    CONSTRAINT no_patient_overlapping_appointments
        EXCLUDE USING gist (
            patient_id WITH =,
            tstzrange(start_at, end_at, '[)') WITH &&
        )
        WHERE (status IN ('scheduled', 'confirmed', 'checked_in'))
);

-- Step 7: Invoices table (1:0..1 relationship with appointments)
CREATE TABLE IF NOT EXISTS invoices (
    invoice_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id BIGINT NOT NULL UNIQUE,
    total_amount NUMERIC(10, 2) NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_date DATE,

    CONSTRAINT fk_invoice_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES appointments(appointment_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_invoice_amount
        CHECK (total_amount >= 0),

    CONSTRAINT chk_invoice_due_date
        CHECK (due_date IS NULL OR due_date >= issued_at::DATE)
);

-- Step 8: Payments table (1:N relationship with invoices)
CREATE TABLE IF NOT EXISTS payments (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id BIGINT NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    payment_method VARCHAR(20) NOT NULL,
    paid_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reference_code VARCHAR(100) UNIQUE,

    CONSTRAINT fk_payment_invoice
        FOREIGN KEY (invoice_id)
        REFERENCES invoices(invoice_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_payment_amount
        CHECK (amount > 0),

    CONSTRAINT chk_payment_method
        CHECK (payment_method IN (
            'cash',
            'card',
            'upi',
            'bank_transfer',
            'insurance'
        ))
);
