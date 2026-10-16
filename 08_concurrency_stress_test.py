import concurrent.futures
import time
import psycopg

DB_URI = "postgresql://postgres:@127.0.0.1:5432/hospital_management_db"

DOCTOR_ID = 1  # Dr. Aditi Sharma
TARGET_START = "2026-10-25 10:00:00+05:30"
TARGET_END = "2026-10-25 10:30:00+05:30"
NUM_CONCURRENT_REQUESTS = 10

def attempt_booking(worker_id):
    patient_id = (worker_id % 10) + 1
    reason = f"Concurrent stress booking attempt by Worker #{worker_id}"

    try:
        with psycopg.connect(DB_URI, autocommit=True) as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
                    VALUES (%s, %s, %s, %s, 'scheduled', %s)
                    RETURNING appointment_id;
                """, (patient_id, DOCTOR_ID, TARGET_START, TARGET_END, reason))
                appt_id = cur.fetchone()[0]
                return (worker_id, True, f"SUCCESS (Appointment #{appt_id} booked)")
    except psycopg.errors.ExclusionViolation as ex:
        return (worker_id, False, "BLOCKED by PostgreSQL GiST exclusion constraint (exclusion_violation)")
    except Exception as ex:
        return (worker_id, False, f"ERROR: {type(ex).__name__} - {ex}")

def main():
    print("=" * 70)
    print("Hospital Appointment and Patient Management System")
    print(f"Phase 4: Concurrency Stress Test ({NUM_CONCURRENT_REQUESTS} Simultaneous Booking Requests)")
    print(f"Target: Doctor #{DOCTOR_ID} on {TARGET_START} -> {TARGET_END}")
    print("=" * 70)

    # First clean up any prior test appointment for this slot
    with psycopg.connect(DB_URI, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("""
                DELETE FROM appointments 
                WHERE doctor_id = %s AND start_at = %s;
            """, (DOCTOR_ID, TARGET_START))

    time.sleep(0.5)

    results = []
    start_time = time.time()

    with concurrent.futures.ThreadPoolExecutor(max_workers=NUM_CONCURRENT_REQUESTS) as executor:
        futures = [executor.submit(attempt_booking, i + 1) for i in range(NUM_CONCURRENT_REQUESTS)]
        for f in concurrent.futures.as_completed(futures):
            results.append(f.result())

    elapsed = time.time() - start_time
    results.sort(key=lambda r: r[0])

    successes = [r for r in results if r[1]]
    blocked = [r for r in results if not r[1]]

    print("\nExecution Results:")
    for wid, ok, msg in results:
        status_tag = "[WON SLOT]" if ok else "[REJECTED]"
        print(f"  Worker #{wid:02d}: {status_tag} {msg}")

    print("\n" + "-" * 70)
    print(f"Summary:")
    print(f"  Total Concurrent Threads: {NUM_CONCURRENT_REQUESTS}")
    print(f"  Successfully Booked:      {len(successes)}")
    print(f"  Safely Rejected:          {len(blocked)}")
    print(f"  Execution Time:           {elapsed * 1000:.2f} ms")
    print("-" * 70)

    if len(successes) == 1 and len(blocked) == NUM_CONCURRENT_REQUESTS - 1:
        print("[VERDICT: PASS] Zero race conditions! PostgreSQL exclusion constraint flawlessly isolated the slot.")
    else:
        print("[VERDICT: FAIL] Unexpected booking count.")

    print("=" * 70)

if __name__ == "__main__":
    main()
