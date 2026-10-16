-- =============================================================================
-- Hospital Appointment and Patient Management System
-- File: sql/01_extensions.sql
-- Description: Enable required PostgreSQL extensions for the system
-- =============================================================================

-- btree_gist allows combining scalar B-Tree types (e.g., BIGINT doctor_id / patient_id)
-- with geometric and range types (e.g., tstzrange) in GiST exclusion constraints.
-- This is the foundational prerequisite for database-level overlap prevention.
CREATE EXTENSION IF NOT EXISTS btree_gist;
