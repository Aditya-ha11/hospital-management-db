# Entity-Relationship (ER) Model & Architecture

This document specifies the relational data model for the Hospital Appointment and Patient Management System, including entity definitions, relationship cardinalities, foreign key actions, and PostgreSQL-specific GiST exclusion constraints.

---

## 1. Mermaid Visual ER Diagram

```mermaid
erDiagram
    DEPARTMENTS ||--o{ DOCTORS : "1 department employs many doctors"
    DOCTORS ||--o{ DOCTOR_AVAILABILITY : "1 doctor has weekly recurring shifts"
    DOCTORS ||--o{ APPOINTMENTS : "1 doctor attends many appointments"
    PATIENTS ||--o{ APPOINTMENTS : "1 patient books many appointments"
    APPOINTMENTS ||--o| INVOICES : "1 appointment has at most 1 invoice"
    INVOICES ||--o{ PAYMENTS : "1 invoice settled by multiple payments"
    APPOINTMENTS ||--o{ APPOINTMENT_AUDIT_LOG : "1 appointment logs lifecycle audits"
    PAYMENTS ||--o| PAYMENTS : "1 payment can be reversed by a reversal record"

    DEPARTMENTS {
        bigint department_id PK
        varchar department_name UK
        text description
        timestamptz created_at
    }

    DOCTORS {
        bigint doctor_id PK
        bigint department_id FK
        varchar first_name
        varchar last_name
        varchar specialty
        numeric consultation_fee
        varchar email UK
        boolean is_active
        timestamptz created_at
    }

    DOCTOR_AVAILABILITY {
        bigint availability_id PK
        bigint doctor_id FK
        smallint weekday
        time start_time
        time end_time
    }

    PATIENTS {
        bigint patient_id PK
        varchar first_name
        varchar last_name
        date date_of_birth
        varchar phone
        varchar email UK
        timestamptz created_at
    }

    APPOINTMENTS {
        bigint appointment_id PK
        bigint patient_id FK
        bigint doctor_id FK
        timestamptz start_at
        timestamptz end_at
        varchar status
        varchar reason
        timestamptz created_at
        timestamptz updated_at
    }

    APPOINTMENT_AUDIT_LOG {
        bigint audit_id PK
        bigint appointment_id FK
        varchar action_type
        varchar old_status
        varchar new_status
        timestamptz old_start_at
        timestamptz new_start_at
        varchar changed_by
        timestamptz changed_at
        text notes
    }

    INVOICES {
        bigint invoice_id PK
        bigint appointment_id FK, UK
        numeric total_amount
        varchar status
        timestamptz issued_at
        date due_date
    }

    PAYMENTS {
        bigint payment_id PK
        bigint invoice_id FK
        numeric amount
        varchar payment_type
        varchar payment_method
        timestamptz paid_at
        varchar reference_code UK
        bigint reversed_payment_id FK
    }
```

---

## 2. Cardinality & Relationship Matrix

| Entity A | Entity B | Cardinality | Enforcing Constraint | Deletion Rule | Design Rationale |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **Department** | **Doctor** | `1:N` | `fk_doctor_department` | `ON DELETE RESTRICT` | Prevents deleting a clinical department that has active staff. |
| **Doctor** | **Availability** | `1:N` | `fk_availability_doctor` | `ON DELETE RESTRICT` | A doctor can have multiple distinct morning/afternoon weekly shifts. |
| **Doctor** | **Appointment** | `1:N` | `fk_appointment_doctor` | `ON DELETE RESTRICT` | Doctors attend numerous patient appointments over time. |
| **Patient** | **Appointment** | `1:N` | `fk_appointment_patient` | `ON DELETE RESTRICT` | Clinical history cannot be deleted while referenced by bookings. |
| **Appointment** | **Invoice** | `1:0..1` | `fk_invoice_appointment` + `UNIQUE(appointment_id)` | `ON DELETE RESTRICT` | Strict 1:0..1 coupling; an appointment can have at most one invoice. |
| **Invoice** | **Payment** | `1:N` | `fk_payment_invoice` | `ON DELETE RESTRICT` | Invoices can be paid in full, through partial installments, or co-pay. |
| **Appointment** | **Audit Log** | `1:N` | `fk_audit_appointment` | `ON DELETE CASCADE` | Complete timeline of reschedules, status transitions, and cancellations. |
| **Payment** | **Payment (Reversal)** | `1:0..1` | `fk_payment_reversal` | `ON DELETE RESTRICT` | Self-referencing FK models refund/reversal records without deleting history. |

---

## 3. Database-Level Overlap Isolation Engine

```sql
CONSTRAINT no_doctor_overlapping_appointments
    EXCLUDE USING gist (
        doctor_id WITH =,
        tstzrange(start_at, end_at, '[)') WITH &&
    )
    WHERE (status != 'cancelled');

CONSTRAINT no_patient_overlapping_appointments
    EXCLUDE USING gist (
        patient_id WITH =,
        tstzrange(start_at, end_at, '[)') WITH &&
    )
    WHERE (status != 'cancelled');
```

### Why Half-Open Ranges `[)`?
* `[10:00, 10:30)` and `[10:30, 11:00)` share the exact instant `10:30`.
* Because the interval is right-exclusive, their intersection `&&` evaluates to `EMPTY`.
* Result: Consecutive back-to-back appointments are accepted, but any real overlapping collision (e.g. `10:15 - 10:45`) is blocked.
