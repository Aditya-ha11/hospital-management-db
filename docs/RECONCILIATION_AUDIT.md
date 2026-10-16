# Financial Reconciliation & Fan-Out Elimination Audit

This report documents the root-cause analysis, mathematical proof, and SQL solution for the ₹1,200 revenue discrepancy identified between the Executive Dashboard and Department Aggregations.

---

## 1. The Discrepancy Phenomenon

In the initial dashboard evaluation, the following figures were observed:
* **Collected Revenue:** ₹2,35,075
* **Outstanding Receivables:** ₹56,625
* **Their Sum (Actual Billed Total):** ₹2,91,700
* **Department Breakdown Sum:** ₹2,92,900
* **Discrepancy:** ₹1,200

---

## 2. Root Cause Analysis: The 1:N Fan-Out Join Trap

In a normalized relational schema:
* `1 appointment` has `0 or 1 invoice` (`1:0..1`)
* `1 invoice` has `1 or more payments` (`1:N` installment payments or co-pay)

### The Naïve Faulty Query:
```sql
-- INCORRECT QUERY (Causes Fan-Out Multiplication):
SELECT 
    d.department_name,
    SUM(i.total_amount) AS total_invoiced,
    SUM(p.amount) AS total_collected
FROM departments d
JOIN doctors doc ON d.department_id = doc.department_id
JOIN appointments a ON doc.doctor_id = a.doctor_id
JOIN invoices i ON a.appointment_id = i.appointment_id
LEFT JOIN payments p ON i.invoice_id = p.invoice_id
GROUP BY d.department_name;
```

### Why it failed:
Suppose an invoice for Doctor Aditi Sharma had `total_amount = ₹1,200` and was paid in two installments:
1. Payment 1: `₹600`
2. Payment 2: `₹600`

When `invoices` is joined directly to `payments` with a `1:N` cardinality, the SQL join produces **two Cartesian rows** for that single invoice:
| Row | `i.invoice_id` | `i.total_amount` | `p.payment_id` | `p.amount` |
| :---: | :---: | :---: | :---: | :---: |
| 1 | 14 | ₹1,200 | 101 | ₹600 |
| 2 | 14 | ₹1,200 | 102 | ₹600 |

When `SUM(i.total_amount)` is evaluated over these two joined rows, it sums `₹1,200 + ₹1,200 = ₹2,400`!
The invoice amount was counted **twice**, injecting an exact **₹1,200 phantom over-statement** into the department total!

---

## 3. The CTE Solution: Independent Granular Pre-Aggregation

To prevent Cartesian product duplication across 1:N branches, invoice totals and payment totals must be pre-aggregated in separate Common Table Expressions (CTEs) at the `department_id` level *before* joining:

```sql
WITH dept_invoices AS (
    SELECT 
        doc.department_id,
        COALESCE(SUM(i.total_amount), 0.00) AS total_invoiced
    FROM invoices i
    JOIN appointments a ON i.appointment_id = a.appointment_id
    JOIN doctors doc ON a.doctor_id = doc.doctor_id
    GROUP BY doc.department_id
),
dept_payments AS (
    SELECT 
        doc.department_id,
        COALESCE(SUM(p.amount), 0.00) AS total_collected
    FROM payments p
    JOIN invoices i ON p.invoice_id = i.invoice_id
    JOIN appointments a ON i.appointment_id = a.appointment_id
    JOIN doctors doc ON a.doctor_id = doc.doctor_id
    WHERE p.payment_type = 'payment'
    GROUP BY doc.department_id
)
SELECT 
    d.department_name,
    COALESCE(di.total_invoiced, 0.00) AS total_amount_invoiced,
    COALESCE(dp.total_collected, 0.00) AS total_amount_collected,
    (COALESCE(di.total_invoiced, 0.00) - COALESCE(dp.total_collected, 0.00)) AS outstanding_balance
FROM departments d
LEFT JOIN dept_invoices di ON d.department_id = di.department_id
LEFT JOIN dept_payments dp ON d.department_id = dp.department_id
ORDER BY total_amount_invoiced DESC;
```

---

## 4. Reconciliation Verification Results

Executing this corrected logic yields exact mathematical parity across all tables:

| Department Name | Total Invoiced (₹) | Total Collected (₹) | Outstanding Balance (₹) | Collection % |
| :--- | :---: | :---: | :---: | :---: |
| **Cardiology** | ₹67,200.00 | ₹54,300.00 | ₹12,900.00 | 80.8% |
| **Oncology** | ₹66,000.00 | ₹54,000.00 | ₹12,000.00 | 81.8% |
| **Neurology** | ₹65,200.00 | ₹51,800.00 | ₹13,400.00 | 79.4% |
| **Orthopedics** | ₹48,000.00 | ₹39,400.00 | ₹8,600.00 | 82.1% |
| **Pediatrics** | ₹26,500.00 | ₹20,775.00 | ₹5,725.00 | 78.4% |
| **General Medicine** | ₹18,800.00 | ₹14,800.00 | ₹4,000.00 | 78.7% |
| **Total Sum** | **₹2,91,700.00** | **₹2,35,075.00** | **₹56,625.00** | **80.6%** |

### Mathematical Proof:
$$\text{Total Invoiced} = ₹2,91,700.00$$
$$\text{Total Collected} + \text{Total Outstanding} = ₹2,35,075.00 + ₹56,625.00 = ₹2,91,700.00$$
$$\text{Department Invoiced Sum} = ₹2,91,700.00$$
$$\text{Net Discrepancy} = ₹0.00$$
