-- =============================================================================
-- Hospital Appointment and Patient Management System
-- Phase 1: Schema Verification Queries
-- Run these queries after executing 01_phase1_schema.sql
-- =============================================================================

-- Query 1: Verify all 7 base tables exist in public schema
SELECT 
    table_name 
FROM 
    information_schema.tables
WHERE 
    table_schema = 'public'
    AND table_type = 'BASE TABLE'
ORDER BY 
    table_name;

-- Expected result (7 rows):
-- appointments
-- departments
-- doctor_availability
-- doctors
-- invoices
-- patients
-- payments


-- Query 2: Verify btree_gist extension is active
SELECT 
    extname, 
    extversion 
FROM 
    pg_extension 
WHERE 
    extname = 'btree_gist';


-- Query 3: Inspect all Primary, Foreign Key, and Unique constraints
SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type
FROM 
    information_schema.table_constraints tc
WHERE 
    tc.table_schema = 'public'
ORDER BY 
    tc.table_name, 
    tc.constraint_type, 
    tc.constraint_name;


-- Query 4: Verify Exclusion Constraints on appointments (btree_gist)
SELECT 
    conrelid::regclass AS table_name,
    conname AS exclusion_constraint_name,
    pg_get_constraintdef(c.oid) AS constraint_definition
FROM 
    pg_constraint c
WHERE 
    contype = 'x'
    AND conrelid = 'appointments'::regclass;
