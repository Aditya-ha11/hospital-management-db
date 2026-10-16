import json
import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import psycopg

DB_URI = "postgresql://postgres:@127.0.0.1:5432/hospital_management_db"
WEB_DIR = os.path.abspath("C:/Users/Nitro/.gemini/antigravity-ide/scratch/hospital-management-db/web")

class HospitalAPIHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def send_json(self, status_code, data):
        payload = json.dumps(data, default=str).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(payload)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path.startswith("/api/"):
            query_params = parse_qs(parsed.query)
            try:
                with psycopg.connect(DB_URI) as conn:
                    with conn.cursor() as cur:
                        if path == "/api/overview":
                            self.handle_overview(cur, query_params)
                        elif path == "/api/doctors":
                            self.handle_doctors(cur)
                        elif path == "/api/patients":
                            self.handle_patients(cur)
                        elif path == "/api/appointments":
                            self.handle_appointments(cur, query_params)
                        elif path == "/api/appointments/detail":
                            self.handle_appointment_detail(cur, query_params)
                        elif path == "/api/invoices":
                            self.handle_invoices(cur, query_params)
                        elif path == "/api/payments/history":
                            self.handle_payment_history(cur, query_params)
                        elif path == "/api/analytics":
                            self.handle_analytics(cur, query_params)
                        elif path == "/api/calendar":
                            self.handle_calendar(cur, query_params)
                        else:
                            self.send_json(404, {"error": "API route not found"})
            except Exception as e:
                self.send_json(500, {"error": str(e)})
        else:
            super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8") if length > 0 else "{}"
        try:
            payload = json.loads(body)
        except Exception:
            payload = {}

        if path == "/api/appointments":
            self.handle_book_appointment(payload)
        elif path == "/api/appointments/cancel":
            self.handle_cancel_appointment(payload)
        elif path == "/api/payments":
            self.handle_record_payment(payload)
        else:
            self.send_json(404, {"error": "API route not found"})

    def handle_overview(self, cur, query_params=None):
        start_date = query_params.get("start_date", [None])[0] if query_params else None
        end_date = query_params.get("end_date", [None])[0] if query_params else None

        if start_date and end_date:
            cur.execute("""
                SELECT 
                    (SELECT count(*) FROM departments) AS departments_count,
                    (SELECT count(*) FROM doctors) AS doctors_count,
                    (SELECT count(DISTINCT patient_id) FROM appointments WHERE start_at::DATE BETWEEN %s AND %s) AS patients_count,
                    -- Active appointments (strictly excluding completed and cancelled)
                    (SELECT count(*) FROM appointments WHERE status IN ('scheduled', 'confirmed', 'checked_in') AND start_at::DATE BETWEEN %s AND %s) AS active_appointments,
                    -- Total all appointments in date window
                    (SELECT count(*) FROM appointments WHERE start_at::DATE BETWEEN %s AND %s) AS total_appointments,
                    -- Completed visits in date window
                    (SELECT count(*) FROM appointments WHERE status = 'completed' AND start_at::DATE BETWEEN %s AND %s) AS completed_appointments,
                    -- Cancelled visits in date window
                    (SELECT count(*) FROM appointments WHERE status = 'cancelled' AND start_at::DATE BETWEEN %s AND %s) AS cancelled_appointments,
                    -- Total Billed in date window
                    (SELECT COALESCE(SUM(i.total_amount), 0) FROM invoices i 
                     JOIN appointments a ON i.appointment_id = a.appointment_id 
                     WHERE a.start_at::DATE BETWEEN %s AND %s) AS total_billed,
                    -- Total Collected in date window
                    (SELECT COALESCE(SUM(p.amount), 0) FROM payments p 
                     JOIN invoices i ON p.invoice_id = i.invoice_id 
                     JOIN appointments a ON i.appointment_id = a.appointment_id 
                     WHERE p.payment_type = 'payment' AND a.start_at::DATE BETWEEN %s AND %s) AS total_collected;
            """, (start_date, end_date, start_date, end_date, start_date, end_date, start_date, end_date, start_date, end_date, start_date, end_date, start_date, end_date))
        else:
            cur.execute("""
                SELECT 
                    (SELECT count(*) FROM departments) AS departments_count,
                    (SELECT count(*) FROM doctors) AS doctors_count,
                    (SELECT count(*) FROM patients) AS patients_count,
                    -- Active appointments (strictly excluding completed and cancelled)
                    (SELECT count(*) FROM appointments WHERE status IN ('scheduled', 'confirmed', 'checked_in')) AS active_appointments,
                    -- Total appointments across entire database
                    (SELECT count(*) FROM appointments) AS total_appointments,
                    -- Completed appointments
                    (SELECT count(*) FROM appointments WHERE status = 'completed') AS completed_appointments,
                    -- Cancelled appointments
                    (SELECT count(*) FROM appointments WHERE status = 'cancelled') AS cancelled_appointments,
                    -- Total Billed
                    (SELECT COALESCE(SUM(total_amount), 0) FROM invoices) AS total_billed,
                    -- Total Collected
                    (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE payment_type = 'payment') AS total_collected;
            """)
        row = cur.fetchone()
        active_appts = int(row[3])
        total_appts = int(row[4])
        completed_appts = int(row[5])
        cancelled_appts = int(row[6])
        total_billed = float(row[7])
        total_collected = float(row[8])
        outstanding = float(total_billed - total_collected)

        self.send_json(200, {
            "departments": row[0],
            "doctors": row[1],
            "patients": row[2],
            "active_appointments": active_appts,
            "appointments": total_appts,
            "completed_appointments": completed_appts,
            "cancelled_appointments": cancelled_appts,
            "total_billed": total_billed,
            "total_collected": total_collected,
            "outstanding": outstanding,
            "discrepancy": 0.00,
            "filter_applied": bool(start_date and end_date),
            "start_date": start_date,
            "end_date": end_date
        })

    def handle_doctors(self, cur):
        cur.execute("""
            SELECT 
                d.doctor_id,
                d.first_name || ' ' || d.last_name AS name,
                dept.department_name,
                d.specialty,
                d.consultation_fee,
                d.email,
                d.is_active,
                COALESCE(
                    json_agg(
                        json_build_object(
                            'weekday', da.weekday,
                            'start_time', da.start_time,
                            'end_time', da.end_time
                        ) ORDER BY da.weekday, da.start_time
                    ) FILTER (WHERE da.availability_id IS NOT NULL), '[]'
                ) AS shifts
            FROM doctors d
            JOIN departments dept ON d.department_id = dept.department_id
            LEFT JOIN doctor_availability da ON d.doctor_id = da.doctor_id
            GROUP BY d.doctor_id, d.first_name, d.last_name, dept.department_name, d.specialty, d.consultation_fee, d.email, d.is_active
            ORDER BY d.doctor_id;
        """)
        cols = [desc[0] for desc in cur.description]
        doctors = [dict(zip(cols, row)) for row in cur.fetchall()]
        self.send_json(200, doctors)

    def handle_patients(self, cur):
        cur.execute("""
            SELECT 
                patient_id, 
                first_name || ' ' || last_name AS name,
                date_of_birth,
                phone,
                email
            FROM patients
            ORDER BY patient_id;
        """)
        cols = [desc[0] for desc in cur.description]
        patients = [dict(zip(cols, row)) for row in cur.fetchall()]
        self.send_json(200, patients)

    def handle_appointments(self, cur, query_params=None):
        start_date = query_params.get("start_date", [None])[0] if query_params else None
        end_date = query_params.get("end_date", [None])[0] if query_params else None

        sql = """
            SELECT 
                a.appointment_id,
                p.first_name || ' ' || p.last_name AS patient_name,
                'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
                dept.department_name,
                a.start_at,
                a.end_at,
                ROUND(EXTRACT(EPOCH FROM (a.end_at - a.start_at)) / 60) AS duration_minutes,
                a.status,
                a.reason
            FROM appointments a
            JOIN patients p ON a.patient_id = p.patient_id
            JOIN doctors d ON a.doctor_id = d.doctor_id
            JOIN departments dept ON d.department_id = dept.department_id
        """
        params = []
        if start_date and end_date:
            sql += " WHERE a.start_at::DATE BETWEEN %s AND %s"
            params.extend([start_date, end_date])
        sql += " ORDER BY a.start_at DESC, a.appointment_id DESC;"

        cur.execute(sql, tuple(params))
        cols = [desc[0] for desc in cur.description]
        appts = [dict(zip(cols, row)) for row in cur.fetchall()]
        self.send_json(200, appts)

    def handle_invoices(self, cur, query_params=None):
        start_date = query_params.get("start_date", [None])[0] if query_params else None
        end_date = query_params.get("end_date", [None])[0] if query_params else None

        sql = """
            SELECT 
                v.*
            FROM v_invoice_ledger v
            JOIN appointments a ON v.appointment_id = a.appointment_id
        """
        params = []
        if start_date and end_date:
            sql += " WHERE a.start_at::DATE BETWEEN %s AND %s"
            params.extend([start_date, end_date])
        sql += " ORDER BY v.invoice_id DESC;"

        cur.execute(sql, tuple(params))
        cols = [desc[0] for desc in cur.description]
        invoices = [dict(zip(cols, row)) for row in cur.fetchall()]
        self.send_json(200, invoices)

    def handle_appointment_detail(self, cur, query_params=None):
        appt_id = query_params.get("appointment_id", [None])[0] if query_params else None
        if not appt_id:
            self.send_json(400, {"error": "Missing appointment_id parameter"})
            return

        cur.execute("""
            SELECT 
                a.appointment_id,
                a.start_at,
                a.end_at,
                ROUND(EXTRACT(EPOCH FROM (a.end_at - a.start_at)) / 60) AS duration_minutes,
                a.status,
                a.reason,
                a.created_at,
                p.patient_id,
                p.first_name || ' ' || p.last_name AS patient_name,
                p.date_of_birth,
                p.phone AS patient_phone,
                p.email AS patient_email,
                d.doctor_id,
                'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
                dept.department_name,
                d.specialty,
                d.consultation_fee,
                d.email AS doctor_email,
                i.invoice_id,
                i.total_amount,
                i.status AS invoice_status,
                COALESCE(v.total_paid, 0) AS total_paid,
                COALESCE(v.outstanding_balance, i.total_amount) AS outstanding_balance,
                COALESCE(v.payment_status, 'Unpaid') AS payment_status
            FROM appointments a
            JOIN patients p ON a.patient_id = p.patient_id
            JOIN doctors d ON a.doctor_id = d.doctor_id
            JOIN departments dept ON d.department_id = dept.department_id
            LEFT JOIN invoices i ON a.appointment_id = i.appointment_id
            LEFT JOIN v_invoice_ledger v ON i.invoice_id = v.invoice_id
            WHERE a.appointment_id = %s;
        """, (appt_id,))
        row = cur.fetchone()
        if not row:
            self.send_json(404, {"error": f"Appointment #{appt_id} not found"})
            return

        cols = [desc[0] for desc in cur.description]
        appt_data = dict(zip(cols, row))
        appt_data["start_at"] = str(appt_data["start_at"])
        appt_data["end_at"] = str(appt_data["end_at"])
        appt_data["created_at"] = str(appt_data["created_at"])
        appt_data["date_of_birth"] = str(appt_data["date_of_birth"])
        appt_data["consultation_fee"] = float(appt_data["consultation_fee"])
        if appt_data["total_amount"] is not None:
            appt_data["total_amount"] = float(appt_data["total_amount"])
        if appt_data["total_paid"] is not None:
            appt_data["total_paid"] = float(appt_data["total_paid"])
        if appt_data["outstanding_balance"] is not None:
            appt_data["outstanding_balance"] = float(appt_data["outstanding_balance"])

        cur.execute("""
            SELECT 
                audit_id,
                action_type,
                old_status,
                new_status,
                changed_by,
                changed_at,
                notes
            FROM appointment_audit_log
            WHERE appointment_id = %s
            ORDER BY changed_at ASC, audit_id ASC;
        """, (appt_id,))
        audit_cols = [desc[0] for desc in cur.description]
        audit_rows = []
        for r in cur.fetchall():
            item = dict(zip(audit_cols, r))
            item["changed_at"] = str(item["changed_at"])
            audit_rows.append(item)
        appt_data["audit_logs"] = audit_rows

        self.send_json(200, appt_data)

    def handle_payment_history(self, cur, query_params=None):
        invoice_id = query_params.get("invoice_id", [None])[0] if query_params else None
        if not invoice_id:
            self.send_json(400, {"error": "Missing invoice_id parameter"})
            return

        cur.execute("""
            SELECT 
                v.invoice_id,
                v.appointment_id,
                v.patient_name,
                v.doctor_name,
                v.department_name,
                v.total_amount,
                v.total_paid,
                v.outstanding_balance,
                v.payment_status,
                v.is_overdue
            FROM v_invoice_ledger v
            WHERE v.invoice_id = %s;
        """, (invoice_id,))
        row = cur.fetchone()
        if not row:
            self.send_json(404, {"error": f"Invoice INV-{invoice_id} not found"})
            return

        cols = [desc[0] for desc in cur.description]
        inv_data = dict(zip(cols, row))
        inv_data["total_amount"] = float(inv_data["total_amount"])
        inv_data["total_paid"] = float(inv_data["total_paid"])
        inv_data["outstanding_balance"] = float(inv_data["outstanding_balance"])

        cur.execute("""
            SELECT 
                payment_id,
                invoice_id,
                amount,
                payment_type,
                payment_method,
                reference_code,
                paid_at,
                reversed_payment_id
            FROM payments
            WHERE invoice_id = %s
            ORDER BY paid_at DESC, payment_id DESC;
        """, (invoice_id,))
        pay_cols = [desc[0] for desc in cur.description]
        payments = []
        for r in cur.fetchall():
            p_dict = dict(zip(pay_cols, r))
            p_dict["amount"] = float(p_dict["amount"])
            p_dict["paid_at"] = str(p_dict["paid_at"])
            payments.append(p_dict)
        inv_data["payments"] = payments

        self.send_json(200, inv_data)

    def handle_analytics(self, cur, query_params=None):
        start_date = query_params.get("start_date", [None])[0] if query_params else None
        end_date = query_params.get("end_date", [None])[0] if query_params else None

        where_clause = ""
        params = []
        if start_date and end_date:
            where_clause = " WHERE a.start_at::DATE BETWEEN %s AND %s "
            params = [start_date, end_date]

        # 1. Department revenue (Pre-aggregated CTE to eliminate 1:N fan-out / double counting)
        sql_dept = f"""
            WITH dept_invoices AS (
                SELECT 
                    d.department_id,
                    COALESCE(SUM(i.total_amount), 0) AS total_invoiced
                FROM invoices i
                JOIN appointments a ON i.appointment_id = a.appointment_id
                JOIN doctors d ON a.doctor_id = d.doctor_id
                {where_clause}
                GROUP BY d.department_id
            ),
            dept_payments AS (
                SELECT 
                    d.department_id,
                    COALESCE(SUM(p.amount), 0) AS total_collected
                FROM payments p
                JOIN invoices i ON p.invoice_id = i.invoice_id
                JOIN appointments a ON i.appointment_id = a.appointment_id
                JOIN doctors d ON a.doctor_id = d.doctor_id
                {where_clause}
                GROUP BY d.department_id
            )
            SELECT 
                dept.department_name,
                COALESCE(di.total_invoiced, 0) AS invoiced,
                COALESCE(dp.total_collected, 0) AS collected
            FROM departments dept
            LEFT JOIN dept_invoices di ON dept.department_id = di.department_id
            LEFT JOIN dept_payments dp ON dept.department_id = dp.department_id
            ORDER BY invoiced DESC;
        """
        cur.execute(sql_dept, tuple(params + params) if params else ())
        dept_rev = [dict(zip([d[0] for d in cur.description], row)) for row in cur.fetchall()]

        # 2. Status breakdown
        sql_status = f"""
            SELECT status, count(*) AS count 
            FROM appointments a
            {where_clause}
            GROUP BY status;
        """
        cur.execute(sql_status, tuple(params) if params else ())
        statuses = dict(cur.fetchall())

        # 3. Doctor utilization
        sql_doc = f"""
            SELECT 
                'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
                dept.department_name,
                COUNT(a.appointment_id) AS bookings,
                COALESCE(SUM(i.total_amount), 0) AS revenue
            FROM doctors d
            JOIN departments dept ON d.department_id = dept.department_id
            LEFT JOIN appointments a ON d.doctor_id = a.doctor_id {'AND a.start_at::DATE BETWEEN %s AND %s' if params else ''}
            LEFT JOIN invoices i ON a.appointment_id = i.appointment_id
            GROUP BY d.doctor_id, d.first_name, d.last_name, dept.department_name
            ORDER BY revenue DESC;
        """
        cur.execute(sql_doc, tuple(params) if params else ())
        doc_workload = [dict(zip([d[0] for d in cur.description], row)) for row in cur.fetchall()]

        # 4. Daily Trends for chart visualization
        sql_trends = f"""
            SELECT 
                TO_CHAR(a.start_at::DATE, 'YYYY-MM-DD') AS day_iso,
                TO_CHAR(a.start_at::DATE, 'Mon DD') AS day_label,
                COUNT(a.appointment_id) AS total_appts,
                COUNT(CASE WHEN a.status = 'completed' THEN 1 END) AS completed_appts,
                COUNT(CASE WHEN a.status = 'cancelled' THEN 1 END) AS cancelled_appts,
                COALESCE(SUM(i.total_amount), 0) AS billed,
                COALESCE(SUM(p_agg.collected), 0) AS collected
            FROM appointments a
            LEFT JOIN invoices i ON a.appointment_id = i.appointment_id
            LEFT JOIN (
                SELECT invoice_id, SUM(amount) AS collected
                FROM payments
                WHERE payment_type = 'payment'
                GROUP BY invoice_id
            ) p_agg ON i.invoice_id = p_agg.invoice_id
            {where_clause}
            GROUP BY a.start_at::DATE
            ORDER BY a.start_at::DATE ASC;
        """
        cur.execute(sql_trends, tuple(params) if params else ())
        trend_cols = [d[0] for d in cur.description]
        daily_trends = []
        for r in cur.fetchall():
            td = dict(zip(trend_cols, r))
            td["billed"] = float(td["billed"])
            td["collected"] = float(td["collected"])
            daily_trends.append(td)

        total_appts_count = sum(statuses.values()) or 1
        cancelled_count = statuses.get("cancelled", 0)
        cancellation_rate = round((cancelled_count / total_appts_count) * 100, 1)

        self.send_json(200, {
            "department_revenue": dept_rev,
            "appointment_statuses": statuses,
            "doctor_workload": doc_workload,
            "daily_trends": daily_trends,
            "cancellation_rate": cancellation_rate,
            "filter_applied": bool(start_date and end_date),
            "start_date": start_date,
            "end_date": end_date
        })

    def handle_calendar(self, cur, query_params=None):
        doctor_id = query_params.get("doctor_id", [None])[0] if query_params else None
        department_name = query_params.get("department_name", [None])[0] if query_params else None
        status = query_params.get("status", [None])[0] if query_params else None
        start_date = query_params.get("start_date", [None])[0] if query_params else None
        end_date = query_params.get("end_date", [None])[0] if query_params else None

        where_clauses = []
        params = []
        if doctor_id and doctor_id != "all":
            where_clauses.append("a.doctor_id = %s")
            params.append(doctor_id)
        if department_name and department_name != "all":
            where_clauses.append("dept.department_name = %s")
            params.append(department_name)
        if status and status != "all":
            where_clauses.append("a.status = %s")
            params.append(status)
        if start_date:
            where_clauses.append("a.start_at::DATE >= %s")
            params.append(start_date)
        if end_date:
            where_clauses.append("a.start_at::DATE <= %s")
            params.append(end_date)

        where_sql = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

        cur.execute(f"""
            SELECT 
                a.appointment_id,
                a.patient_id,
                p.first_name || ' ' || p.last_name AS patient_name,
                a.doctor_id,
                'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
                dept.department_name,
                a.start_at,
                a.end_at,
                ROUND(EXTRACT(EPOCH FROM (a.end_at - a.start_at)) / 60) AS duration_minutes,
                a.status,
                a.reason
            FROM appointments a
            JOIN patients p ON a.patient_id = p.patient_id
            JOIN doctors d ON a.doctor_id = d.doctor_id
            JOIN departments dept ON d.department_id = dept.department_id
            {where_sql}
            ORDER BY a.start_at ASC;
        """, tuple(params))
        cols = [desc[0] for desc in cur.description]
        appts = [dict(zip(cols, row)) for row in cur.fetchall()]

        shift_where_clauses = []
        shift_params = []
        if doctor_id and doctor_id != "all":
            shift_where_clauses.append("d.doctor_id = %s")
            shift_params.append(doctor_id)
        if department_name and department_name != "all":
            shift_where_clauses.append("dept.department_name = %s")
            shift_params.append(department_name)
        shift_where = ("WHERE " + " AND ".join(shift_where_clauses)) if shift_where_clauses else ""

        cur.execute(f"""
            SELECT 
                da.availability_id,
                da.doctor_id,
                'Dr. ' || d.first_name || ' ' || d.last_name AS doctor_name,
                dept.department_name,
                da.weekday,
                da.start_time,
                da.end_time
            FROM doctor_availability da
            JOIN doctors d ON da.doctor_id = d.doctor_id
            JOIN departments dept ON d.department_id = dept.department_id
            {shift_where}
            ORDER BY da.weekday, da.start_time;
        """, tuple(shift_params))
        s_cols = [desc[0] for desc in cur.description]
        shifts = [dict(zip(s_cols, row)) for row in cur.fetchall()]

        self.send_json(200, {
            "appointments": appts,
            "shifts": shifts,
            "doctor_id": doctor_id,
            "start_date": start_date,
            "end_date": end_date
        })

    def handle_book_appointment(self, payload):
        patient_id = payload.get("patient_id")
        doctor_id = payload.get("doctor_id")
        start_at = payload.get("start_at")
        end_at = payload.get("end_at")
        reason = payload.get("reason", "Outpatient Consultation")

        if not all([patient_id, doctor_id, start_at, end_at]):
            self.send_json(400, {
                "success": False,
                "title": "Missing Required Fields",
                "error": "Please select a patient, doctor, and complete time window."
            })
            return

        try:
            with psycopg.connect(DB_URI, autocommit=True) as conn:
                with conn.cursor() as cur:
                    # 1. Fetch doctor name & fee
                    cur.execute("""
                        SELECT d.first_name || ' ' || d.last_name AS name, d.consultation_fee
                        FROM doctors d WHERE d.doctor_id = %s;
                    """, (doctor_id,))
                    doc_row = cur.fetchone()
                    doc_name = doc_row[0] if doc_row else f"Doctor #{doctor_id}"
                    consultation_fee = doc_row[1] if doc_row else 500.00

                    # 2. Insert into appointments
                    cur.execute("""
                        INSERT INTO appointments (patient_id, doctor_id, start_at, end_at, status, reason)
                        VALUES (%s, %s, %s, %s, 'scheduled', %s)
                        RETURNING appointment_id;
                    """, (patient_id, doctor_id, start_at, end_at, reason))
                    new_id = cur.fetchone()[0]

                    # 3. Create initial billing invoice for real financial tracking
                    cur.execute("""
                        INSERT INTO invoices (appointment_id, total_amount, due_date)
                        VALUES (%s, %s, CURRENT_DATE + 14)
                        RETURNING invoice_id;
                    """, (new_id, consultation_fee))
                    new_inv_id = cur.fetchone()[0]

                    self.send_json(201, {
                        "success": True, 
                        "appointment_id": new_id,
                        "invoice_id": new_inv_id,
                        "consultation_fee": float(consultation_fee),
                        "message": f"Appointment #{new_id} confirmed with Dr. {doc_name}! Invoice #{new_inv_id} (₹{consultation_fee:,.2f}) issued."
                    })
        except psycopg.errors.ExclusionViolation as ex:
            ex_str = str(ex)
            if "no_doctor" in ex_str:
                title = "Doctor Already Booked"
                friendly_msg = "This doctor already has an appointment during the selected time. Please choose another slot or another doctor."
                constraint = "no_doctor_overlapping_appointments"
            elif "no_patient" in ex_str:
                title = "Patient Overlap Detected"
                friendly_msg = "This patient is already booked for another appointment during this time window. Please pick a different time."
                constraint = "no_patient_overlapping_appointments"
            else:
                title = "Scheduling Conflict"
                friendly_msg = "The requested appointment overlaps with an existing active booking."
                constraint = "exclusion_violation"

            self.send_json(409, {
                "success": False,
                "conflict": True,
                "title": title,
                "error": friendly_msg,
                "technical_detail": f"PostgreSQL GiST constraint: {constraint} (SQLSTATE 23P01)"
            })
        except psycopg.errors.CheckViolation as ex:
            ex_str = str(ex)
            if "does not have an active shift" in ex_str:
                title = "Outside Doctor's Working Hours"
                friendly_msg = "The chosen appointment time is outside this doctor's scheduled working shift. Please select a time during the doctor's active clinic hours."
            elif "chk_appointment_time" in ex_str:
                title = "Invalid Time Range"
                friendly_msg = "Appointment end time must be after the start time."
            else:
                title = "Validation Error"
                friendly_msg = str(ex).strip().split("\n")[0]

            self.send_json(422, {
                "success": False,
                "title": title,
                "error": friendly_msg,
                "technical_detail": f"PostgreSQL CHECK constraint failure: {str(ex).strip()}"
            })
        except Exception as ex:
            self.send_json(400, {
                "success": False,
                "title": "Booking Failed",
                "error": str(ex)
            })

    def handle_cancel_appointment(self, payload):
        appointment_id = payload.get("appointment_id")
        reason = payload.get("reason", "Cancelled by user via Dashboard")

        if not appointment_id:
            self.send_json(400, {"success": False, "error": "Missing appointment_id."})
            return

        try:
            with psycopg.connect(DB_URI, autocommit=True) as conn:
                with conn.cursor() as cur:
                    cur.execute("CALL sp_cancel_appointment(%s, %s);", (appointment_id, reason))
                    
                    cur.execute("""
                        UPDATE invoices 
                        SET status = 'reversed' 
                        WHERE appointment_id = %s AND status = 'unpaid';
                    """, (appointment_id,))

                    self.send_json(200, {
                        "success": True,
                        "message": f"Appointment #{appointment_id} has been cancelled in PostgreSQL. The time slot is now liberated for other patients."
                    })
        except Exception as ex:
            self.send_json(400, {"success": False, "error": str(ex)})

    def handle_record_payment(self, payload):
        invoice_id = payload.get("invoice_id")
        amount = payload.get("amount")
        method = payload.get("payment_method", "upi")
        ref = payload.get("reference_code") or f"PAY-WEB-{invoice_id}-{int(os.times().elapsed * 1000)}"

        try:
            with psycopg.connect(DB_URI, autocommit=True) as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO payments (invoice_id, amount, payment_method, reference_code)
                        VALUES (%s, %s, %s, %s)
                        RETURNING payment_id;
                    """, (invoice_id, amount, method, ref))
                    new_id = cur.fetchone()[0]

                    cur.execute("""
                        SELECT outstanding_balance, payment_status 
                        FROM v_invoice_ledger 
                        WHERE invoice_id = %s;
                    """, (invoice_id,))
                    inv_state = cur.fetchone()
                    rem_bal = float(inv_state[0]) if inv_state else 0.0
                    p_status = inv_state[1] if inv_state else "Updated"

                    self.send_json(201, {
                        "success": True,
                        "payment_id": new_id,
                        "remaining_balance": rem_bal,
                        "payment_status": p_status,
                        "message": f"Payment #{new_id} of ₹{float(amount):,.2f} recorded! Invoice #{invoice_id} is now '{p_status}' (Remaining balance: ₹{rem_bal:,.2f})."
                    })
        except psycopg.errors.CheckViolation as ex:
            ex_str = str(ex)
            if "exceeds remaining invoice balance" in ex_str:
                title = "Payment Exceeds Outstanding Balance"
                friendly_msg = "The entered payment amount is greater than the remaining balance on this invoice. Please enter an amount less than or equal to the outstanding balance."
            elif "chk_payment_amount" in ex_str:
                title = "Invalid Payment Amount"
                friendly_msg = "Payment amount must be greater than ₹0.00."
            else:
                title = "Payment Validation Error"
                friendly_msg = str(ex).strip().split("\n")[0]

            self.send_json(422, {
                "success": False,
                "title": title,
                "error": friendly_msg,
                "technical_detail": f"Database trigger trg_validate_payment blocked transaction with FOR UPDATE lock."
            })
        except Exception as ex:
            self.send_json(400, {"success": False, "error": str(ex)})

def run(port=8080):
    server = HTTPServer(("127.0.0.1", port), HospitalAPIHandler)
    print(f"Hospital Management Server running at http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    run(port)
