@echo off
setlocal

set PG_BIN=%~dp0pgsql\bin
set HOST=127.0.0.1
set PORT=5432
set USER=postgres
set DB=hospital_management_db

echo =========================================================================
echo Hospital Appointment and Patient Management System
echo Canonical Reproducible Execution Pipeline (SQL 01 - 08 + Test Suite)
echo =========================================================================

echo [1/8] 01_extensions.sql: Enabling btree_gist extension...
"%PG_BIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d %DB% -f "%~dp0sql\01_extensions.sql"
if %ERRORLEVEL% NEQ 0 goto error

echo [2/8] 02_schema.sql: Initializing relational schema, audit log, and GiST constraints...
"%PG_BIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d %DB% -f "%~dp0sql\02_schema.sql"
if %ERRORLEVEL% NEQ 0 goto error

echo [3/8] 03_seed_data.sql: Seeding departments, doctors, patients, and shift rosters...
"%PG_BIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d %DB% -f "%~dp0sql\03_seed_data.sql"
if %ERRORLEVEL% NEQ 0 goto error

echo [4/8] 04_booking_rules.sql: Installing shift validation triggers and booking procedures...
"%PG_BIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d %DB% -f "%~dp0sql\04_booking_rules.sql"
if %ERRORLEVEL% NEQ 0 goto error

echo [5/8] 05_billing_rules.sql: Installing concurrency row locks and overpayment triggers...
"%PG_BIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d %DB% -f "%~dp0sql\05_billing_rules.sql"
if %ERRORLEVEL% NEQ 0 goto error

echo [6/8] 06_indexes_views.sql: Creating justified B-Tree indexes and dynamic ledger views...
"%PG_BIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d %DB% -f "%~dp0sql\06_indexes_views.sql"
if %ERRORLEVEL% NEQ 0 goto error

echo [7/8] 07_analytics.sql: Validating 20 analytical SQL queries (CTEs, Window Functions)...
"%PG_BIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d %DB% -f "%~dp0sql\07_analytics.sql" > nul
if %ERRORLEVEL% NEQ 0 goto error

echo [8/8] 08_tests.sql: Running automated 11-test integrity and reconciliation audit...
"%PG_BIN%\psql.exe" -h %HOST% -p %PORT% -U %USER% -d %DB% -f "%~dp0sql\08_tests.sql"
if %ERRORLEVEL% NEQ 0 goto error

echo =========================================================================
echo Executing Multi-Threaded Concurrency and Standalone Test Runner...
echo =========================================================================
uv run python "%~dp0tests\run_all_tests.py"
if %ERRORLEVEL% NEQ 0 goto error

echo =========================================================================
echo ALL 8 SQL SCRIPTS AND ALL TEST SUITES COMPLETED AND VERIFIED SUCCESSFULLY!
echo =========================================================================
goto end

:error
echo [ERROR] Pipeline execution failed at step %ERRORLEVEL%.
exit /b %ERRORLEVEL%

:end
endlocal
