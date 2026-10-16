-- =============================================================================
-- Hospital Appointment and Patient Management System
-- File: sql/02_schema.sql
-- Description: Core relational schema, primary keys, foreign keys, and audit log
-- =============================================================================

-- 1. Departments Table
CREATE TABLE IF NOT EXISTS departments (
    department_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Doctors Table
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

-- 3. Patients Table
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

-- 4. Doctor Availability (Recurring Weekly Shift Rosters)
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

-- 5. Appointments Table (With GiST exclusion constraints)
CREATE TABLE IF NOT EXISTS appointments (
    appointment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'scheduled',
    reason VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

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

    -- Prevents doctor overlapping bookings across all non-cancelled appointments
    CONSTRAINT no_doctor_overlapping_appointments
        EXCLUDE USING gist (
            doctor_id WITH =,
            tstzrange(start_at, end_at, '[)') WITH &&
        )
        WHERE (status != 'cancelled'),

    -- Prevents patient simultaneous bookings across all non-cancelled appointments
    CONSTRAINT no_patient_overlapping_appointments
        EXCLUDE USING gist (
            patient_id WITH =,
            tstzrange(start_at, end_at, '[)') WITH &&
        )
        WHERE (status != 'cancelled')
);

-- 6. Appointment Audit Log (Priority 4 Data Model Enhancement)
-- Tracks the complete lifecycle, rescheduling history, and status changes
CREATE TABLE IF NOT EXISTS appointment_audit_log (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id BIGINT NOT NULL,
    action_type VARCHAR(20) NOT NULL, -- 'INSERT', 'UPDATE_STATUS', 'RESCHEDULE', 'CANCEL'
    old_status VARCHAR(20),
    new_status VARCHAR(20),
    old_start_at TIMESTAMPTZ,
    new_start_at TIMESTAMPTZ,
    changed_by VARCHAR(80) DEFAULT CURRENT_USER,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,

    CONSTRAINT fk_audit_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES appointments(appointment_id)
        ON DELETE CASCADE
);

-- Audit Trigger Function
CREATE OR REPLACE FUNCTION fn_audit_appointment_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO appointment_audit_log (
            appointment_id, action_type, old_status, new_status, 
            old_start_at, new_start_at, notes
        ) VALUES (
            NEW.appointment_id, 'INSERT', NULL, NEW.status, 
            NULL, NEW.start_at, 'Initial booking created'
        );
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.updated_at := CURRENT_TIMESTAMP;

        -- Detect action type
        IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
            INSERT INTO appointment_audit_log (
                appointment_id, action_type, old_status, new_status, 
                old_start_at, new_start_at, notes
            ) VALUES (
                NEW.appointment_id, 'CANCEL', OLD.status, NEW.status, 
                OLD.start_at, NEW.start_at, NEW.reason
            );
        ELSIF NEW.start_at IS DISTINCT FROM OLD.start_at THEN
            INSERT INTO appointment_audit_log (
                appointment_id, action_type, old_status, new_status, 
                old_start_at, new_start_at, notes
            ) VALUES (
                NEW.appointment_id, 'RESCHEDULE', OLD.status, NEW.status, 
                OLD.start_at, NEW.start_at, 'Appointment rescheduled'
            );
        ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
            INSERT INTO appointment_audit_log (
                appointment_id, action_type, old_status, new_status, 
                old_start_at, new_start_at, notes
            ) VALUES (
                NEW.appointment_id, 'UPDATE_STATUS', OLD.status, NEW.status, 
                OLD.start_at, NEW.start_at, 'Status transition'
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_appointments ON appointments;
CREATE TRIGGER trg_audit_appointments
    AFTER INSERT OR UPDATE ON appointments
    FOR EACH ROW
    EXECUTE FUNCTION fn_audit_appointment_changes();

-- 7. Invoices Table (1:0..1 Relationship with appointments)
CREATE TABLE IF NOT EXISTS invoices (
    invoice_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id BIGINT NOT NULL UNIQUE,
    total_amount NUMERIC(10, 2) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'unpaid',
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_date DATE,

    CONSTRAINT fk_invoice_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES appointments(appointment_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_invoice_amount
        CHECK (total_amount >= 0),

    CONSTRAINT chk_invoice_status
        CHECK (status IN ('unpaid', 'partially_paid', 'paid_in_full', 'reversed')),

    CONSTRAINT chk_invoice_due_date
        CHECK (due_date IS NULL OR due_date >= issued_at::DATE)
);

-- 8. Payments Table (With Refund & Reversal Support)
CREATE TABLE IF NOT EXISTS payments (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id BIGINT NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    payment_type VARCHAR(20) NOT NULL DEFAULT 'payment', -- 'payment', 'refund', 'reversal'
    payment_method VARCHAR(20) NOT NULL,
    paid_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reference_code VARCHAR(100) UNIQUE,
    reversed_payment_id BIGINT,

    CONSTRAINT fk_payment_invoice
        FOREIGN KEY (invoice_id)
        REFERENCES invoices(invoice_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_payment_reversal
        FOREIGN KEY (reversed_payment_id)
        REFERENCES payments(payment_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_payment_amount
        CHECK (amount > 0),

    CONSTRAINT chk_payment_type
        CHECK (payment_type IN ('payment', 'refund', 'reversal')),

    CONSTRAINT chk_payment_method
        CHECK (payment_method IN (
            'cash',
            'card',
            'upi',
            'bank_transfer',
            'insurance'
        ))
);
