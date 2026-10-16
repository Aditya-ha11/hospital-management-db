import psycopg
import datetime

def main():
    conn = psycopg.connect("host=127.0.0.1 port=5432 dbname=hospital_management_db user=postgres password=postgres")
    conn.autocommit = False

    with conn.cursor() as cur:
        # 1. Fetch doctor shifts
        cur.execute("SELECT doctor_id, weekday, start_time, end_time FROM doctor_availability ORDER BY doctor_id, weekday, start_time;")
        doctor_shifts = {}
        for doc_id, wk, st, et in cur.fetchall():
            doctor_shifts.setdefault(doc_id, []).append((wk, st, et))

        # 2. Fetch all appointments ordered by appointment_id
        cur.execute("SELECT appointment_id, patient_id, doctor_id, start_at, end_at, status FROM appointments ORDER BY appointment_id;")
        all_appts = cur.fetchall()

        # Track occupied slots:
        # doc_busy: { doc_id: set of (start_at, end_at) }
        # patient_busy: { patient_id: set of (start_at, end_at) }
        doc_busy = {d: set() for d in range(1, 11)}
        patient_busy = {}

        # First pass: preserve all non-conflicting appointments
        to_reschedule = []
        for appt_id, pid, did, start, end, status in all_appts:
            if status == 'cancelled':
                continue # Cancelled slots do not block future bookings

            # Check overlap
            has_doc_conflict = False
            for s, e in doc_busy[did]:
                if max(start, s) < min(end, e):
                    has_doc_conflict = True
                    break

            has_patient_conflict = False
            if pid in patient_busy:
                for s, e in patient_busy[pid]:
                    if max(start, s) < min(end, e):
                        has_patient_conflict = True
                        break

            if not has_doc_conflict and not has_patient_conflict:
                doc_busy[did].add((start, end))
                patient_busy.setdefault(pid, set()).add((start, end))
            else:
                to_reschedule.append((appt_id, pid, did, start, end, status))

        print(f"Preserved {len(all_appts) - len(to_reschedule)} appointments. Need to reallocate {len(to_reschedule)} conflicting appointments.")

        # Reallocate conflicting appointments to free shift slots
        base_date = datetime.date(2026, 11, 2) # Monday (PG DOW = 1)
        rescheduled_count = 0

        for appt_id, pid, did, orig_start, orig_end, status in to_reschedule:
            shifts = doctor_shifts.get(did, [])
            if not shifts:
                raise Exception(f"No shifts found for doctor {did}")

            allocated = False
            # Search across weeks starting from Nov 2, 2026 up to 12 weeks
            for week_offset in range(12):
                for (wk, st, et) in shifts:
                    # wk is PG DOW (0=Sun, 1=Mon, ..., 6=Sat)
                    # base_date is Monday (PG DOW 1)
                    day_delta = (wk - 1) % 7
                    target_day = base_date + datetime.timedelta(days=day_delta + (week_offset * 7))

                    shift_start_dt = datetime.datetime.combine(
                        target_day, st, tzinfo=datetime.timezone(datetime.timedelta(hours=5, minutes=30))
                    )
                    shift_end_dt = datetime.datetime.combine(
                        target_day, et, tzinfo=datetime.timezone(datetime.timedelta(hours=5, minutes=30))
                    )

                    slot_start = shift_start_dt
                    while slot_start + datetime.timedelta(minutes=30) <= shift_end_dt:
                        slot_end = slot_start + datetime.timedelta(minutes=30)

                        # Check collision with doc
                        doc_collides = any(max(slot_start, s) < min(slot_end, e) for s, e in doc_busy[did])
                        # Check collision with patient
                        patient_collides = any(max(slot_start, s) < min(slot_end, e) for s, e in patient_busy.get(pid, set()))

                        if not doc_collides and not patient_collides:
                            # Assign slot
                            doc_busy[did].add((slot_start, slot_end))
                            patient_busy.setdefault(pid, set()).add((slot_start, slot_end))

                            cur.execute("""
                                UPDATE appointments
                                SET start_at = %s, end_at = %s
                                WHERE appointment_id = %s;
                            """, (slot_start, slot_end, appt_id))
                            rescheduled_count += 1
                            allocated = True
                            break

                        slot_start += datetime.timedelta(minutes=30)

                    if allocated:
                        break
                if allocated:
                    break

            if not allocated:
                raise Exception(f"Failed to find open slot for appointment {appt_id}")

        print(f"Successfully rescheduled {rescheduled_count} appointments into guaranteed valid shift slots.")

        # Recreate GiST exclusion constraint with WHERE (status != 'cancelled')
        print("Upgrading PostgreSQL GiST exclusion constraint to protect all non-cancelled appointments...")
        cur.execute("ALTER TABLE appointments DROP CONSTRAINT IF EXISTS no_doctor_overlapping_appointments;")
        cur.execute("ALTER TABLE appointments DROP CONSTRAINT IF EXISTS no_patient_overlapping_appointments;")

        cur.execute("""
            ALTER TABLE appointments ADD CONSTRAINT no_doctor_overlapping_appointments
                EXCLUDE USING gist (
                    doctor_id WITH =,
                    tstzrange(start_at, end_at, '[)') WITH &&
                )
                WHERE (status != 'cancelled');
        """)

        cur.execute("""
            ALTER TABLE appointments ADD CONSTRAINT no_patient_overlapping_appointments
                EXCLUDE USING gist (
                    patient_id WITH =,
                    tstzrange(start_at, end_at, '[)') WITH &&
                )
                WHERE (status != 'cancelled');
        """)

        # Verification query
        cur.execute("""
            SELECT count(*)
            FROM appointments a
            JOIN appointments b
              ON a.doctor_id = b.doctor_id
             AND a.appointment_id < b.appointment_id
             AND tstzrange(a.start_at, a.end_at, '[)') && tstzrange(b.start_at, b.end_at, '[)')
            WHERE a.status != 'cancelled' AND b.status != 'cancelled';
        """)
        overlap_count = cur.fetchone()[0]
        print(f"Overlap check across all non-cancelled appointments: {overlap_count} overlaps found.")
        assert overlap_count == 0, f"Expected 0 overlaps, got {overlap_count}"

        conn.commit()
        print("[SUCCESS] All updates committed and GiST constraints active!")

if __name__ == '__main__':
    main()
