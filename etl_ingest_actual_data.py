import csv
import datetime
import os
import random
import sys
import psycopg

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

DB_URI = "postgresql://postgres:@127.0.0.1:5432/hospital_management_db"
CSV_PATH = os.path.abspath("C:/Users/Nitro/.gemini/antigravity-ide/scratch/hospital-management-db/data_medical_appointments.csv")

# Fictional first & last name pools to pair with real Patient IDs
FIRST_NAMES_M = ["Aarav", "Rohan", "Vikram", "Kabir", "Aditya", "Dev", "Rahul", "Arjun", "Siddharth", "Manish", "Gaurav", "Naveen", "Deepak", "Anand", "Rajesh", "Amit", "Kunal", "Sunil", "Suresh", "Harish"]
FIRST_NAMES_F = ["Priya", "Ananya", "Diya", "Meera", "Kavita", "Pooja", "Simran", "Neha", "Sunita", "Tanvi", "Shraddha", "Deepika", "Kriti", "Alia", "Sara", "Janhvi", "Rhea", "Isha", "Shweta", "Sneha"]
LAST_NAMES = ["Sharma", "Verma", "Patel", "Mehta", "Iyer", "Nair", "Bose", "Chatterjee", "Kulkarni", "Gupta", "Deshmukh", "Singhania", "Kapoor", "Rathore", "Saxena", "Menon", "Joshi", "Malhotra", "Sen", "Bhatt"]

def get_doctor_and_reason(age, hipertension, diabetes, alcoholism, handcap):
    """
    Maps clinical indicators from actual medical dataset to appropriate hospital department and doctor.
    """
    if age < 16:
        # Pediatrics: Doctor 7 (Dr. Suresh Kulkarni) or Doctor 8 (Dr. Neha Gupta)
        doc_id = 7 if (age % 2 == 0) else 8
        reasons = [
            f"Pediatric wellness evaluation (Age {age})",
            f"Childhood immunization and growth screening (Age {age})",
            f"Pediatric febrile illness assessment (Age {age})"
        ]
        return doc_id, random.choice(reasons)
    
    if hipertension == '1':
        # Cardiology: Doctor 1 (Dr. Aditi Sharma) or Doctor 2 (Dr. Vikram Mehta)
        doc_id = 1 if (hash(str(age)) % 2 == 0) else 2
        reasons = [
            "Essential hypertension cardiac review & BP optimization",
            "Hypertensive heart disease follow-up & ECG evaluation",
            "Cardiovascular risk assessment and lipid profile review"
        ]
        return doc_id, random.choice(reasons)

    if handcap != '0':
        # Orthopedics: Doctor 5 (Dr. Rajesh Iyer) or Doctor 6 (Dr. Ananya Deshmukh)
        doc_id = 5 if (int(handcap) % 2 == 1) else 6
        reasons = [
            f"Physical disability mobility assessment (Grade {handcap})",
            "Chronic musculoskeletal joint pain evaluation",
            "Orthopedic rehabilitation & physical therapy review"
        ]
        return doc_id, random.choice(reasons)

    if alcoholism == '1':
        # Neurology: Doctor 3 (Dr. Rohit Verma) or Doctor 4 (Dr. Priya Nair)
        doc_id = 4
        return doc_id, "Neurological screening for cognitive stability & neuropathy"

    if diabetes == '1':
        # General Medicine: Doctor 9 (Dr. Arun Patel)
        return 9, "Type-2 Diabetes metabolic panel & glycemic control review"

    # General Outpatient / Oncology
    rand_choice = hash(str(age) + str(hipertension)) % 10
    if rand_choice == 0:
        return 10, "Oncology routine clinical consultation & tumor biomarker screening"
    elif rand_choice in (1, 2):
        return 3, "Neurological evaluation for persistent headaches"
    elif rand_choice in (3, 4):
        return 5, "Orthopedic consultation for knee and lower back pain"
    else:
        return 9, "General primary care checkup & preventive medical panel"

def main():
    print("=" * 70)
    print("ETL: Ingesting Real-World Healthcare Dataset into PostgreSQL")
    print(f"Source: {CSV_PATH} (110,527 real medical records)")
    print("=" * 70)

    if not os.path.exists(CSV_PATH):
        print(f"Error: Dataset not found at {CSV_PATH}")
        return

    # Target: Sample 300 diverse real patient records and their encounters
    NUM_TARGET_RECORDS = 300

    print(f"Reading and filtering top {NUM_TARGET_RECORDS} authentic patient records...")

    extracted_records = []
    with open(CSV_PATH, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            extracted_records.append(row)
            if len(extracted_records) >= NUM_TARGET_RECORDS:
                break

    print(f"Extracted {len(extracted_records)} real encounter rows from dataset.")

    with psycopg.connect(DB_URI, autocommit=False) as conn:
        with conn.cursor() as cur:
            # 1. Ingest Patients
            print("\n[1/4] Ingesting authentic patients into 'patients' table...")
            patient_id_map = {}  # maps dataset PatientId -> DB patient_id

            # Cache existing patients to avoid duplicate emails
            cur.execute("SELECT email, patient_id FROM patients;")
            existing_emails = dict(cur.fetchall())

            patient_insert_count = 0
            for idx, r in enumerate(extracted_records):
                raw_pid = r['PatientId']
                if raw_pid in patient_id_map:
                    continue

                gender = r['Gender']
                age = max(0, min(100, int(r['Age'])))
                
                # Deterministic name selection based on raw PatientId
                name_seed = int(float(raw_pid)) % 1000
                first_name = FIRST_NAMES_F[name_seed % len(FIRST_NAMES_F)] if gender == 'F' else FIRST_NAMES_M[name_seed % len(FIRST_NAMES_M)]
                last_name = LAST_NAMES[(name_seed // 7) % len(LAST_NAMES)]
                email = f"patient_{raw_pid}@med-dataset.org"

                # Calculate DOB from Age (strictly in the past <= CURRENT_DATE)
                days_offset = int(age * 365.25) + (name_seed % 300)
                # For age 0, offset by at least 10 days in the past
                if days_offset < 10:
                    days_offset = 10 + (name_seed % 30)
                dob = datetime.date.today() - datetime.timedelta(days=days_offset)

                phone = f"+91-98{name_seed:04d}{(idx % 100):02d}"

                if email in existing_emails:
                    patient_id_map[raw_pid] = existing_emails[email]
                else:
                    cur.execute("""
                        INSERT INTO patients (first_name, last_name, date_of_birth, phone, email)
                        VALUES (%s, %s, %s, %s, %s)
                        RETURNING patient_id;
                    """, (first_name, last_name, dob, phone, email))
                    new_db_id = cur.fetchone()[0]
                    patient_id_map[raw_pid] = new_db_id
                    existing_emails[email] = new_db_id
                    patient_insert_count += 1

            conn.commit()
            print(f"✓ Ingested {patient_insert_count} new patients (Total tracked: {len(patient_id_map)}).")

            # 2. Ingest Appointments
            print("\n[2/4] Scheduling appointments compliant with doctor shifts & GiST exclusion...")
            
            # Keep track of booked slots per doctor to avoid any overlapping slot:
            # doctor_slots: { doctor_id: set of (start_at, end_at) }
            doctor_slots = {doc_id: set() for doc_id in range(1, 11)}

            # Query existing appointments in DB so we never collide with any non-cancelled appointment
            cur.execute("SELECT doctor_id, start_at, end_at FROM appointments WHERE status != 'cancelled';")
            for d_id, s, e in cur.fetchall():
                if d_id in doctor_slots:
                    doctor_slots[d_id].add((s, e))

            # Fetch doctor availability shifts
            cur.execute("SELECT doctor_id, weekday, start_time, end_time FROM doctor_availability;")
            shifts_by_doc = {}
            for d_id, wk, st, et in cur.fetchall():
                shifts_by_doc.setdefault(d_id, []).append((wk, st, et))

            # Base anchor date for historical vs upcoming appointments (spanning Nov 2026)
            base_date = datetime.date(2026, 11, 2)  # Monday

            appt_inserted = 0
            invoices_to_create = []

            for idx, r in enumerate(extracted_records):
                raw_pid = r['PatientId']
                db_pid = patient_id_map.get(raw_pid)
                if not db_pid:
                    continue

                age = int(r['Age'])
                doc_id, reason = get_doctor_and_reason(
                    age, r['Hipertension'], r['Diabetes'], r['Alcoholism'], r['Handcap']
                )

                no_show = (r['No-show'] == 'Yes')
                status = 'cancelled' if no_show else ('completed' if idx < 200 else 'confirmed')

                # Find next available shift slot for this doctor
                doc_shifts = shifts_by_doc.get(doc_id, [])
                if not doc_shifts:
                    continue

                slot_found = False
                # Try finding a slot across 4 weeks
                for week_offset in range(4):
                    for (wk, st, et) in doc_shifts:
                        # Compute calendar date for this weekday
                        day_delta = (wk - base_date.weekday()) % 7
                        target_day = base_date + datetime.timedelta(days=day_delta + (week_offset * 7))

                        # Generate 30-minute intervals within this shift
                        shift_start_dt = datetime.datetime.combine(target_day, st, tzinfo=datetime.timezone(datetime.timedelta(hours=5, minutes=30)))
                        shift_end_dt = datetime.datetime.combine(target_day, et, tzinfo=datetime.timezone(datetime.timedelta(hours=5, minutes=30)))

                        current_slot_start = shift_start_dt
                        while current_slot_start + datetime.timedelta(minutes=30) <= shift_end_dt:
                            current_slot_end = current_slot_start + datetime.timedelta(minutes=30)

                            if (current_slot_start, current_slot_end) not in doctor_slots[doc_id]:
                                # Found valid slot!
                                doctor_slots[doc_id].add((current_slot_start, current_slot_end))
                                slot_found = True
                                break
                            current_slot_start += datetime.timedelta(minutes=30)

                        if slot_found:
                            break
                    if slot_found:
                        break

                if not slot_found:
                    continue

                # Insert appointment
                cur.execute("""
                    INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    RETURNING appointment_id;
                """, (db_pid, doc_id, current_slot_start, current_slot_end, status, reason))
                new_appt_id = cur.fetchone()[0]
                appt_inserted += 1

                if status == 'completed':
                    invoices_to_create.append((new_appt_id, doc_id))

            conn.commit()
            print(f"✓ Ingested {appt_inserted} realistic appointments compliant with GiST exclusion!")

            # 3. Create Invoices for completed appointments
            print("\n[3/4] Generating invoices for completed medical appointments...")
            from decimal import Decimal
            cur.execute("SELECT doctor_id, consultation_fee FROM doctors;")
            fee_map = dict(cur.fetchall())

            invoice_count = 0
            payments_to_create = []

            for appt_id, doc_id in invoices_to_create:
                base_fee = fee_map.get(doc_id, Decimal("1000.00"))
                # Extra clinical charges: diagnostic labs, medication, monitoring
                extra_charges = Decimal(str(random.choice([0, 250, 500, 800, 1200])))
                total = base_fee + extra_charges
                due = datetime.date.today() + datetime.timedelta(days=random.randint(7, 30))

                cur.execute("""
                    INSERT INTO invoices (appointment_id, total_amount, due_date)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (appointment_id) DO NOTHING
                    RETURNING invoice_id;
                """, (appt_id, total, due))
                res = cur.fetchone()
                if res:
                    inv_id = res[0]
                    invoice_count += 1
                    payments_to_create.append((inv_id, total))

            conn.commit()
            print(f"✓ Generated {invoice_count} billing invoices.")

            # 4. Generate Payments (Full, Partial, Insurance)
            print("\n[4/4] Recording payments and financial settlements...")
            payment_methods = ['upi', 'card', 'cash', 'bank_transfer', 'insurance']
            payment_count = 0

            for inv_id, total in payments_to_create:
                # 70% paid in full, 20% partial installment, 10% unpaid
                scenario = random.random()
                if scenario < 0.70:
                    amt = total
                    ref = f"PAY-REAL-{inv_id}-FULL"
                    method = random.choice(payment_methods)
                    cur.execute("""
                        INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT (reference_code) DO NOTHING;
                    """, (inv_id, amt, method, ref))
                    payment_count += 1
                elif scenario < 0.90:
                    part1 = (total * Decimal("0.50")).quantize(Decimal("0.01"))
                    ref1 = f"PAY-REAL-{inv_id}-P1"
                    method1 = random.choice(['upi', 'card', 'cash'])
                    cur.execute("""
                        INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT (reference_code) DO NOTHING;
                    """, (inv_id, part1, method1, ref1))
                    payment_count += 1

            conn.commit()
            print(f"✓ Recorded {payment_count} payment transactions.")

            # 5. Refresh Materialized Views
            cur.execute("CALL sp_refresh_kpis();")
            conn.commit()
            print("✓ Materialized KPI view refreshed with actual dataset records.")

    print("\n" + "=" * 70)
    print("ETL Ingestion Completed Successfully!")
    print("=" * 70)

if __name__ == "__main__":
    main()
