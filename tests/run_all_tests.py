# =============================================================================
# Hospital Appointment and Patient Management System
# Test Runner: tests/run_all_tests.py
# Description: Executes all SQL test suites and Python concurrency tests
# =============================================================================

import os
import subprocess
import sys
import time

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PSQL_EXE = os.path.join(BASE_DIR, "pgsql", "bin", "psql.exe")
TESTS_DIR = os.path.join(BASE_DIR, "tests")

HOST = "127.0.0.1"
PORT = "5432"
USER = "postgres"
DB = "hospital_management_db"

def run_sql_test(script_name):
    script_path = os.path.join(TESTS_DIR, script_name)
    cmd = [PSQL_EXE, "-h", HOST, "-p", PORT, "-U", USER, "-d", DB, "-f", script_path]
    start = time.time()
    res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    elapsed = (time.time() - start) * 1000
    return res.returncode == 0, res.stdout, res.stderr, elapsed

def run_py_test(script_name):
    script_path = os.path.join(TESTS_DIR, script_name)
    cmd = ["uv", "run", "--with", "psycopg[binary]", "python", script_path]
    start = time.time()
    res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    elapsed = (time.time() - start) * 1000
    return res.returncode == 0, res.stdout, res.stderr, elapsed

def main():
    print("=" * 80)
    print(" HOSPITAL MANAGEMENT SYSTEM — AUTOMATED INTEGRITY & REGRESSION SUITE")
    print(f" Target Database: {DB} on {HOST}:{PORT}")
    print("=" * 80)

    test_scripts = [
        ("01_booking_conflict_tests.sql", "Booking Conflicts & Exclusion Constraints (GiST)", "sql"),
        ("02_billing_integrity_tests.sql", "Billing Integrity, Overpayment & Reversals", "sql"),
        ("03_foreign_keys_and_checks.sql", "Schema Integrity, FK Deletion & Check Constraints", "sql"),
        ("04_financial_reconciliation.sql", "Zero-Discrepancy Financial Reconciliation Audit", "sql"),
        ("05_concurrency_stress_test.py", "Multi-Threaded Concurrency Race Condition Test", "py"),
    ]

    all_passed = True
    summary = []

    for fname, title, stype in test_scripts:
        print(f"\n[RUNNING] {title} ({fname})...")
        if stype == "sql":
            ok, out, err, dur = run_sql_test(fname)
        else:
            ok, out, err, dur = run_py_test(fname)

        if ok:
            print(f"[PASSED]  {title} ({dur:.1f} ms)")
            summary.append((title, "PASS", dur))
        else:
            print(f"[FAILED]  {title} ({dur:.1f} ms)")
            print("Error output:\n", err or out)
            all_passed = False
            summary.append((title, "FAIL", dur))

    print("\n" + "=" * 80)
    print(" TEST EXECUTION SUMMARY MATRIX")
    print("=" * 80)
    print(f"{'Test Suite':<55} | {'Status':<8} | {'Duration'}")
    print("-" * 80)
    for title, status, dur in summary:
        print(f"{title:<55} | {status:<8} | {dur:>6.1f} ms")
    print("-" * 80)

    if all_passed:
        print("\n[FINAL VERDICT: ALL TEST SUITES PASSED FLAWLESSLY! (0 FAILURES)]")
        return 0
    else:
        print("\n[FINAL VERDICT: FAILURES DETECTED IN TEST RUN!]")
        return 1

if __name__ == "__main__":
    sys.exit(main())
