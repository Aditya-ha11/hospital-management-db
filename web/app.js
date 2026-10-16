// Aegis Hospital Management System — Frontend Engine
const API_BASE = window.location.origin;

// Global Application State
let allAppointments = [];
let allInvoices = [];
let doctorsData = [];
let patientsData = [];

// Table State
let apptSearchQuery = '';
let apptStatusFilter = 'all';
let apptDeptFilter = 'all';
let apptCurrentPage = 1;
let apptPageSize = 25;

let ledgerSearchQuery = '';
let ledgerStatusFilter = 'all';
let ledgerDeptFilter = 'all';
let ledgerCurrentPage = 1;
let ledgerPageSize = 25;

let doctorSearchQuery = '';
let doctorDeptFilter = 'all';

// Calendar State
let calMode = 'week'; // 'week' or 'day'
let calDoctorId = 'all';
let calDeptFilter = 'all';
let calStatusFilter = 'all';
// Default reference to Nov 02, 2026 (a Monday in our encounter dataset)
let calRefDate = new Date(2026, 10, 2); 

// Global Initialization
document.addEventListener('DOMContentLoaded', () => {
    initDefaultDates();
    fetchData();

    // A11y keyboard listener (Escape closes modals and drawer)
    window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closePaymentModal();
            closePaymentHistoryModal();
            closeAppointmentDrawer();
        }
    });
});

function initDefaultDates() {
    const defaultStart = new Date(2026, 10, 2, 10, 0, 0); // Monday 10:00 AM
    const defaultEnd = new Date(2026, 10, 2, 10, 30, 0);

    const pad = (n) => String(n).padStart(2, '0');
    const formatForInput = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;

    const startInput = document.getElementById('book-start');
    const endInput = document.getElementById('book-end');
    if (startInput) startInput.value = formatForInput(defaultStart);
    if (endInput) endInput.value = formatForInput(defaultEnd);
}

function toggleSidebar() {
    const sidebar = document.querySelector('.sidebar');
    if (sidebar) {
        sidebar.classList.toggle('open');
    }
}

function switchTab(tabName) {
    document.querySelectorAll('.nav-btn').forEach(btn => btn.classList.remove('active'));
    document.querySelectorAll('.view-panel').forEach(panel => panel.classList.remove('active'));

    const activeBtn = document.getElementById(`tab-${tabName}`);
    const activePanel = document.getElementById(`view-${tabName}`);

    if (activeBtn) activeBtn.classList.add('active');
    if (activePanel) activePanel.classList.add('active');

    // Close mobile sidebar if open
    const sidebar = document.querySelector('.sidebar');
    if (sidebar && sidebar.classList.contains('open')) {
        sidebar.classList.remove('open');
    }

    // Topbar headings
    const headings = {
        overview: ["Executive Hospital Dashboard", "Live operational status, scheduling metrics, and financial reconciliation."],
        calendar: ["Appointment Calendar & Doctor Rosters", "Daily & weekly schedules, available slots, and active/cancelled bookings."],
        booking: ["Booking Engine (GiST Overlap Protection)", "Interactive slot booking backed by PostgreSQL btree_gist exclusion constraints."],
        schedule: ["Medical Staff Rosters & Shifts", "Doctor departments, consultation fees, and recurring weekly shift schedules."],
        ledger: ["Dynamic Billing & Payments Ledger", "Live outstanding balance computation and database-trigger overpayment validation."],
        analytics: ["SQL Analytics & Capacity Utilization", "Comprehensive operational KPI charts, workload rankings, and collection metrics."],
        schema: ["PostgreSQL Schema Architecture", "7 normalized tables with GiST exclusion constraints, foreign keys, and checks."]
    };

    if (headings[tabName]) {
        document.getElementById('section-heading').textContent = headings[tabName][0];
        document.getElementById('section-subheading').textContent = headings[tabName][1];
    }

    if (tabName === 'calendar') {
        renderCalendar();
    }
}

async function fetchData() {
    try {
        await Promise.all([
            loadOverview(currentFilter.start, currentFilter.end),
            loadDoctors(),
            loadPatients(),
            loadAppointments(currentFilter.start, currentFilter.end),
            loadLedger(currentFilter.start, currentFilter.end),
            loadAnalytics(currentFilter.start, currentFilter.end)
        ]);
        renderCalendar();
    } catch (err) {
        console.error("Error fetching hospital data from PostgreSQL:", err);
    }
}

// =============================================================================
// Overview & Date Filters
// =============================================================================
let currentFilter = { start: null, end: null, preset: 'all' };

function applyDatePreset(preset) {
    currentFilter.preset = preset;
    document.querySelectorAll('.filter-chip').forEach(c => c.classList.remove('active'));

    const startInput = document.getElementById('filter-start-date');
    const endInput = document.getElementById('filter-end-date');

    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const formatDate = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

    if (preset === 'all') {
        const chip = document.getElementById('filter-chip-all');
        if (chip) chip.classList.add('active');
        if (startInput) startInput.value = '';
        if (endInput) endInput.value = '';
        currentFilter.start = null;
        currentFilter.end = null;
    } else if (preset === 'this-month') {
        const chip = document.getElementById('filter-chip-month');
        if (chip) chip.classList.add('active');
        const firstDay = new Date(2026, 10, 1); // Nov 1, 2026
        const lastDay = new Date(2026, 10, 30);
        if (startInput) startInput.value = formatDate(firstDay);
        if (endInput) endInput.value = formatDate(lastDay);
        currentFilter.start = formatDate(firstDay);
        currentFilter.end = formatDate(lastDay);
    } else if (preset === 'last-30') {
        const chip = document.getElementById('filter-chip-last30');
        if (chip) chip.classList.add('active');
        if (startInput) startInput.value = '2026-10-15';
        if (endInput) endInput.value = '2026-11-15';
        currentFilter.start = '2026-10-15';
        currentFilter.end = '2026-11-15';
    } else if (preset === 'q4-2026') {
        const chip = document.getElementById('filter-chip-q4');
        if (chip) chip.classList.add('active');
        if (startInput) startInput.value = '2026-10-01';
        if (endInput) endInput.value = '2026-12-31';
        currentFilter.start = '2026-10-01';
        currentFilter.end = '2026-12-31';
    }

    fetchData();
}

function applyCustomFilter() {
    const startVal = document.getElementById('filter-start-date').value;
    const endVal = document.getElementById('filter-end-date').value;

    if (!startVal || !endVal) {
        alert("Please select both a Start Date and an End Date.");
        return;
    }

    if (startVal > endVal) {
        alert("Start Date cannot be after End Date.");
        return;
    }

    document.querySelectorAll('.filter-chip').forEach(c => c.classList.remove('active'));
    currentFilter.preset = 'custom';
    currentFilter.start = startVal;
    currentFilter.end = endVal;

    fetchData();
}

async function loadOverview(startDate = null, endDate = null) {
    let url = `${API_BASE}/api/overview`;
    if (startDate && endDate) {
        url += `?start_date=${encodeURIComponent(startDate)}&end_date=${encodeURIComponent(endDate)}`;
    }

    const res = await fetch(url);
    const data = await res.json();

    const activeCount = data.active_appointments !== undefined ? data.active_appointments : (data.appointments || 0);
    document.getElementById('kpi-appointments').textContent = activeCount.toLocaleString();
    
    const apptBreakdown = document.getElementById('kpi-appointments-breakdown');
    if (apptBreakdown) {
        const comp = data.completed_appointments || 0;
        const canc = data.cancelled_appointments || 0;
        apptBreakdown.innerHTML = `Completed: <strong>${comp.toLocaleString()}</strong> &bull; Cancelled: <strong>${canc.toLocaleString()}</strong>`;
    }

    document.getElementById('kpi-patients').textContent = (data.patients || 0).toLocaleString();
    document.getElementById('kpi-revenue').textContent = `₹${(data.total_collected || 0).toLocaleString('en-IN')}`;
    document.getElementById('kpi-outstanding').textContent = `₹${(data.outstanding || 0).toLocaleString('en-IN')}`;

    // Update zero-discrepancy reconciliation banner values
    const reconInvoiced = document.getElementById('recon-invoiced');
    const reconCollected = document.getElementById('recon-collected');
    const reconOutstanding = document.getElementById('recon-outstanding');
    const reconDeptSum = document.getElementById('recon-dept-sum');

    if (reconInvoiced) reconInvoiced.textContent = `₹${(data.total_billed || 0).toLocaleString('en-IN')}`;
    if (reconCollected) reconCollected.textContent = `₹${(data.total_collected || 0).toLocaleString('en-IN')}`;
    if (reconOutstanding) reconOutstanding.textContent = `₹${(data.outstanding || 0).toLocaleString('en-IN')}`;
    if (reconDeptSum) reconDeptSum.textContent = `₹${(data.total_billed || 0).toLocaleString('en-IN')}`;
}

// =============================================================================
// Doctors & Shifts
// =============================================================================
async function loadDoctors() {
    const res = await fetch(`${API_BASE}/api/doctors`);
    doctorsData = await res.json();

    // Populate dropdowns
    const select = document.getElementById('book-doctor');
    if (select) {
        select.innerHTML = '<option value="">-- Choose Attending Doctor --</option>';
        doctorsData.forEach(d => {
            const opt = document.createElement('option');
            opt.value = d.doctor_id;
            opt.textContent = `${d.name} (${d.department_name} — ${d.specialty})`;
            select.appendChild(opt);
        });
    }

    // Populate calendar doctor filter
    const calDocSelect = document.getElementById('cal-doctor-filter');
    if (calDocSelect) {
        calDocSelect.innerHTML = '<option value="all">All Physicians (10 Doctors)</option>';
        doctorsData.forEach(d => {
            const opt = document.createElement('option');
            opt.value = d.doctor_id;
            opt.textContent = `${d.name} (${d.department_name})`;
            calDocSelect.appendChild(opt);
        });
        calDocSelect.value = calDoctorId;
    }

    // Populate department filters in tables
    const depts = Array.from(new Set(doctorsData.map(d => d.department_name))).sort();
    const apptDept = document.getElementById('appt-dept-filter');
    if (apptDept && apptDept.options.length <= 1) {
        depts.forEach(dept => {
            const opt = document.createElement('option');
            opt.value = dept;
            opt.textContent = dept;
            apptDept.appendChild(opt);
        });
    }

    const docDept = document.getElementById('doctor-dept-filter');
    if (docDept && docDept.options.length <= 1) {
        depts.forEach(dept => {
            const opt = document.createElement('option');
            opt.value = dept;
            opt.textContent = dept;
            docDept.appendChild(opt);
        });
    }

    const ledgerDept = document.getElementById('ledger-dept-filter');
    if (ledgerDept && ledgerDept.options.length <= 1) {
        depts.forEach(dept => {
            const opt = document.createElement('option');
            opt.value = dept;
            opt.textContent = dept;
            ledgerDept.appendChild(opt);
        });
    }

    const calDept = document.getElementById('cal-dept-filter');
    if (calDept && calDept.options.length <= 1) {
        depts.forEach(dept => {
            const opt = document.createElement('option');
            opt.value = dept;
            opt.textContent = dept;
            calDept.appendChild(opt);
        });
    }

    renderDoctorsTable();
}

function renderDoctorsTable() {
    const tbody = document.getElementById('doctors-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    const weekdayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    const filtered = doctorsData.filter(d => {
        const matchesSearch = !doctorSearchQuery || 
            d.name.toLowerCase().includes(doctorSearchQuery) ||
            d.specialty.toLowerCase().includes(doctorSearchQuery) ||
            d.email.toLowerCase().includes(doctorSearchQuery);
        const matchesDept = doctorDeptFilter === 'all' || d.department_name === doctorDeptFilter;
        return matchesSearch && matchesDept;
    });

    if (filtered.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="loading" style="color:var(--text-muted)">No doctors matching the selected filters.</td></tr>';
        return;
    }

    filtered.forEach(d => {
        const shiftBadges = d.shifts.map(s => 
            `<span class="pill">${weekdayNames[s.weekday]} ${s.start_time.slice(0,5)}-${s.end_time.slice(0,5)}</span>`
        ).join(' ');

        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td><strong>${d.name}</strong><br><small style="color:var(--text-muted)">${d.email}</small></td>
            <td><span class="badge">${d.department_name}</span></td>
            <td>${d.specialty}</td>
            <td style="color:var(--primary);font-weight:600">₹${parseFloat(d.consultation_fee).toLocaleString('en-IN')}</td>
            <td>${shiftBadges || '<span style="color:var(--text-muted)">On Call</span>'}</td>
            <td><span class="status-pill status-confirmed">Active</span></td>
        `;
        tbody.appendChild(tr);
    });
}

function onDoctorFilterChange() {
    doctorSearchQuery = document.getElementById('doctor-search-input').value.toLowerCase().trim();
    doctorDeptFilter = document.getElementById('doctor-dept-filter').value;
    renderDoctorsTable();
}

function clearDoctorFilters() {
    document.getElementById('doctor-search-input').value = '';
    document.getElementById('doctor-dept-filter').value = 'all';
    doctorSearchQuery = '';
    doctorDeptFilter = 'all';
    renderDoctorsTable();
}

// =============================================================================
// Patients
// =============================================================================
async function loadPatients() {
    const res = await fetch(`${API_BASE}/api/patients`);
    patientsData = await res.json();

    const select = document.getElementById('book-patient');
    if (select) {
        select.innerHTML = '<option value="">-- Select Registered Patient --</option>';
        patientsData.forEach(p => {
            const opt = document.createElement('option');
            opt.value = p.patient_id;
            opt.textContent = `${p.name} (MRN #${p.patient_id} — ${p.phone || 'No phone'})`;
            select.appendChild(opt);
        });
    }
}

// =============================================================================
// Appointments (Search, Filter, Pagination)
// =============================================================================
async function loadAppointments(startDate = null, endDate = null) {
    let url = `${API_BASE}/api/appointments`;
    if (startDate && endDate) {
        url += `?start_date=${encodeURIComponent(startDate)}&end_date=${encodeURIComponent(endDate)}`;
    }
    const res = await fetch(url);
    allAppointments = await res.json();
    renderAppointmentsTable();
}

function renderAppointmentsTable() {
    const tbody = document.getElementById('recent-appointments-tbody');
    if (!tbody) return;

    const filtered = allAppointments.filter(a => {
        const matchesSearch = !apptSearchQuery ||
            a.patient_name.toLowerCase().includes(apptSearchQuery) ||
            a.doctor_name.toLowerCase().includes(apptSearchQuery) ||
            a.department_name.toLowerCase().includes(apptSearchQuery) ||
            String(a.appointment_id).includes(apptSearchQuery) ||
            (a.reason && a.reason.toLowerCase().includes(apptSearchQuery));

        const matchesStatus = apptStatusFilter === 'all' || a.status === apptStatusFilter;
        const matchesDept = apptDeptFilter === 'all' || a.department_name === apptDeptFilter;

        return matchesSearch && matchesStatus && matchesDept;
    });

    // Update summary and badge
    const totalCount = filtered.length;
    const badge = document.getElementById('appt-total-badge');
    if (badge) badge.textContent = `${totalCount} Total`;

    const totalPages = Math.max(1, Math.ceil(totalCount / apptPageSize));
    if (apptCurrentPage > totalPages) apptCurrentPage = totalPages;

    const startIdx = (apptCurrentPage - 1) * apptPageSize;
    const pageItems = filtered.slice(startIdx, startIdx + apptPageSize);

    const summaryText = document.getElementById('appt-pagination-summary');
    if (summaryText) {
        summaryText.textContent = totalCount === 0 
            ? "Showing 0 of 0" 
            : `Showing ${startIdx + 1}–${Math.min(startIdx + apptPageSize, totalCount)} of ${totalCount}`;
    }

    const pageDisplay = document.getElementById('appt-page-display');
    if (pageDisplay) pageDisplay.textContent = `Page ${apptCurrentPage} of ${totalPages}`;

    const prevBtn = document.getElementById('appt-prev-btn');
    const nextBtn = document.getElementById('appt-next-btn');
    if (prevBtn) prevBtn.disabled = apptCurrentPage <= 1;
    if (nextBtn) nextBtn.disabled = apptCurrentPage >= totalPages;

    tbody.innerHTML = '';
    if (pageItems.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="loading" style="color:var(--text-muted)">No appointments match the search and filter criteria.</td></tr>';
        return;
    }

    pageItems.forEach(a => {
        const startDate = new Date(a.start_at);
        const dateStr = startDate.toLocaleDateString('en-IN', { month: 'short', day: 'numeric', year: 'numeric' });
        const timeStr = startDate.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' });

        const canCancel = ['scheduled', 'confirmed'].includes(a.status);
        const actionBtn = `
            <div class="btn-action-group">
                <button class="btn-history" onclick="openAppointmentDrawer(${a.appointment_id})" title="View full appointment details and audit trail">Details</button>
                ${canCancel ? `<button class="btn-sm btn-cancel-appt" onclick="cancelAppointment(${a.appointment_id})" title="Liberate slot in GiST index">Cancel</button>` : ''}
            </div>
        `;

        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td><code onclick="openAppointmentDrawer(${a.appointment_id})" title="Click to view details & audit trail" style="cursor:pointer;color:var(--primary);text-decoration:underline">#${a.appointment_id}</code></td>
            <td><strong>${a.patient_name}</strong></td>
            <td><strong>${a.doctor_name}</strong><br><small style="color:var(--text-secondary)">${a.department_name}</small></td>
            <td>${dateStr} <br><small style="color:var(--text-secondary)">${timeStr}</small></td>
            <td>${a.duration_minutes} min</td>
            <td><span class="status-pill status-${a.status}">${a.status}</span></td>
            <td>${actionBtn}</td>
        `;
        tbody.appendChild(tr);
    });
}

function onApptFilterChange() {
    apptSearchQuery = document.getElementById('appt-search-input').value.toLowerCase().trim();
    apptStatusFilter = document.getElementById('appt-status-filter').value;
    apptDeptFilter = document.getElementById('appt-dept-filter').value;
    apptCurrentPage = 1;
    renderAppointmentsTable();
}

function changeApptPage(delta) {
    apptCurrentPage += delta;
    renderAppointmentsTable();
}

function onApptPageSizeChange() {
    apptPageSize = parseInt(document.getElementById('appt-page-size').value);
    apptCurrentPage = 1;
    renderAppointmentsTable();
}

function clearApptFilters() {
    document.getElementById('appt-search-input').value = '';
    document.getElementById('appt-status-filter').value = 'all';
    document.getElementById('appt-dept-filter').value = 'all';
    apptSearchQuery = '';
    apptStatusFilter = 'all';
    apptDeptFilter = 'all';
    apptCurrentPage = 1;
    renderAppointmentsTable();
}

// =============================================================================
// Appointment Calendar Engine (Requirement 1)
// =============================================================================
function setCalendarMode(mode) {
    calMode = mode;
    document.querySelectorAll('.cal-mode-btn').forEach(b => b.classList.remove('active'));
    const activeBtn = document.getElementById(`cal-mode-${mode}`);
    if (activeBtn) activeBtn.classList.add('active');
    renderCalendar();
}

function onCalendarDoctorChange() {
    calDoctorId = document.getElementById('cal-doctor-filter').value;
    renderCalendar();
}

function navigateCalendar(direction) {
    if (direction === 0) {
        // Current/base dataset week
        calRefDate = new Date(2026, 10, 2);
    } else {
        const daysToShift = calMode === 'week' ? 7 * direction : 1 * direction;
        calRefDate.setDate(calRefDate.getDate() + daysToShift);
    }
    renderCalendar();
}

async function renderCalendar() {
    const gridContainer = document.getElementById('calendar-grid');
    if (!gridContainer) return;

    // Calculate dates for current view
    const pad = (n) => String(n).padStart(2, '0');
    const formatDateISO = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

    let viewDates = [];
    if (calMode === 'week') {
        gridContainer.className = "calendar-grid week-view";
        // Calculate Monday of current week
        const d = new Date(calRefDate);
        const dayOfWeek = d.getDay(); // 0 is Sun, 1 is Mon
        const diff = d.getDate() - dayOfWeek + (dayOfWeek === 0 ? -6 : 1);
        const monday = new Date(d.setDate(diff));

        for (let i = 0; i < 7; i++) {
            const nextDay = new Date(monday);
            nextDay.setDate(monday.getDate() + i);
            viewDates.push(nextDay);
        }
    } else {
        gridContainer.className = "calendar-grid day-view";
        viewDates.push(new Date(calRefDate));
    }

    const startDateStr = formatDateISO(viewDates[0]);
    const endDateStr = formatDateISO(viewDates[viewDates.length - 1]);

    // Update Header Date Text
    const heading = document.getElementById('cal-date-heading');
    if (heading) {
        if (calMode === 'week') {
            const m1 = viewDates[0].toLocaleDateString('en-IN', { month: 'short', day: 'numeric' });
            const m2 = viewDates[6].toLocaleDateString('en-IN', { month: 'short', day: 'numeric', year: 'numeric' });
            heading.textContent = `Week of ${m1} – ${m2}`;
        } else {
            heading.textContent = viewDates[0].toLocaleDateString('en-IN', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
        }
    }

    // Fetch calendar data from backend
    let url = `${API_BASE}/api/calendar?start_date=${startDateStr}&end_date=${endDateStr}`;
    if (calDoctorId && calDoctorId !== 'all') {
        url += `&doctor_id=${encodeURIComponent(calDoctorId)}`;
    }
    const deptSelect = document.getElementById('cal-dept-filter');
    if (deptSelect && deptSelect.value && deptSelect.value !== 'all') {
        url += `&department_name=${encodeURIComponent(deptSelect.value)}`;
    }
    const statusSelect = document.getElementById('cal-status-filter');
    if (statusSelect && statusSelect.value && statusSelect.value !== 'all') {
        url += `&status=${encodeURIComponent(statusSelect.value)}`;
    }

    let calendarData = { appointments: [], shifts: [] };
    try {
        const res = await fetch(url);
        calendarData = await res.json();
    } catch (e) {
        console.error("Failed to load calendar data:", e);
    }

    const appts = calendarData.appointments || [];
    const shifts = calendarData.shifts || [];

    // Build the grid
    gridContainer.innerHTML = '';

    // 1. Top Header Row
    // Time label cell
    const timeHead = document.createElement('div');
    timeHead.className = 'cal-header-cell';
    timeHead.innerHTML = '<span class="cal-header-day">Time</span><div class="cal-header-date">IST</div>';
    gridContainer.appendChild(timeHead);

    const weekdayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    viewDates.forEach(dt => {
        const dayHead = document.createElement('div');
        dayHead.className = 'cal-header-cell';
        const isToday = dt.toDateString() === new Date().toDateString();
        dayHead.innerHTML = `
            <div class="cal-header-day">${weekdayNames[dt.getDay()]}</div>
            <div class="cal-header-date ${isToday ? 'today' : ''}">${dt.getDate()} ${dt.toLocaleDateString('en-IN', { month: 'short' })}</div>
        `;
        gridContainer.appendChild(dayHead);
    });

    // 2. Hour Rows (from 08:00 to 18:00)
    const hours = [8, 9, 10, 11, 12, 13, 14, 15, 16, 17];
    hours.forEach(hr => {
        // Time gutter cell
        const tCell = document.createElement('div');
        tCell.className = 'cal-time-cell';
        tCell.textContent = `${pad(hr)}:00`;
        gridContainer.appendChild(tCell);

        // Columns for each viewDate
        viewDates.forEach(dt => {
            const slotCell = document.createElement('div');
            slotCell.className = 'cal-slot-cell';

            const curDateISO = formatDateISO(dt);
            const curDOW = dt.getDay(); // 0-6

            // Check if physician(s) are on shift during this hour
            const onShift = shifts.some(s => {
                if (s.weekday !== curDOW) return false;
                const sStart = parseInt(s.start_time.split(':')[0]);
                const sEnd = parseInt(s.end_time.split(':')[0]);
                return hr >= sStart && hr < sEnd;
            });

            if (onShift) {
                slotCell.classList.add('on-shift');
            } else {
                slotCell.classList.add('off-duty');
            }

            // Find appointments on this day in this hour
            const rawMatching = appts.filter(a => {
                const aDate = new Date(a.start_at);
                const aDateStr = formatDateISO(aDate);
                const aHour = aDate.getHours();
                return aDateStr === curDateISO && aHour === hr;
            });

            // If a doctor has a cancelled slot that was subsequently re-booked, display the active booking
            const slotMap = new Map();
            rawMatching.forEach(a => {
                const key = `${a.doctor_id || a.doctor_name}_${a.start_at}`;
                if (!slotMap.has(key)) {
                    slotMap.set(key, a);
                } else if (slotMap.get(key).status === 'cancelled' && a.status !== 'cancelled') {
                    slotMap.set(key, a);
                }
            });
            const matchingAppts = Array.from(slotMap.values());

            if (matchingAppts.length > 0) {
                matchingAppts.forEach(a => {
                    const card = document.createElement('div');
                    card.className = `cal-event-card ${a.status}`;
                    const aStart = new Date(a.start_at);
                    const timeLabel = aStart.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' });

                    card.title = `Appointment #${a.appointment_id}: ${a.patient_name} with ${a.doctor_name} (${a.status}). Click to view detail drawer & audit trail.`;
                    card.innerHTML = `
                        <span class="cal-event-time">${timeLabel} (${a.duration_minutes}m)</span>
                        <div class="cal-event-patient">${a.patient_name}</div>
                        <div class="cal-event-doctor">${a.doctor_name} &bull; ${a.department_name}</div>
                    `;
                    card.onclick = () => {
                        openAppointmentDrawer(a.appointment_id);
                    };
                    slotCell.appendChild(card);
                });
            } else if (onShift) {
                // If on shift and empty, show clickable "+ Book Slot"
                const bookBtn = document.createElement('button');
                bookBtn.className = 'cal-book-btn';
                bookBtn.textContent = '+ Book Slot';
                const defaultDoctorId = calDoctorId !== 'all' ? calDoctorId : (shifts.find(s => s.weekday === curDOW)?.doctor_id || 1);
                const slotDateTime = `${curDateISO}T${pad(hr)}:00`;
                bookBtn.onclick = () => quickBookSlot(defaultDoctorId, slotDateTime);
                slotCell.appendChild(bookBtn);
            }

            gridContainer.appendChild(slotCell);
        });
    });
}

function quickBookSlot(doctorId, startDateTime) {
    switchTab('booking');
    const docSelect = document.getElementById('book-doctor');
    if (docSelect && doctorId) {
        docSelect.value = doctorId;
        updateDoctorShiftHint();
    }

    const startInput = document.getElementById('book-start');
    const endInput = document.getElementById('book-end');

    if (startInput) startInput.value = startDateTime;
    if (endInput) {
        const start = new Date(startDateTime);
        start.setMinutes(start.getMinutes() + 30);
        const pad = (n) => String(n).padStart(2, '0');
        endInput.value = `${start.getFullYear()}-${pad(start.getMonth() + 1)}-${pad(start.getDate())}T${pad(start.getHours())}:${pad(start.getMinutes())}`;
    }

    document.getElementById('booking-form')?.scrollIntoView({ behavior: 'smooth' });
}

// =============================================================================
// Billing Ledgers (Search, Filter, Pagination)
// =============================================================================
async function loadLedger(startDate = null, endDate = null) {
    let url = `${API_BASE}/api/invoices`;
    if (startDate && endDate) {
        url += `?start_date=${encodeURIComponent(startDate)}&end_date=${encodeURIComponent(endDate)}`;
    }
    const res = await fetch(url);
    allInvoices = await res.json();
    renderLedgerTable();
}

function renderLedgerTable() {
    const tbody = document.getElementById('ledger-tbody');
    if (!tbody) return;

    const filtered = allInvoices.filter(inv => {
        const matchesSearch = !ledgerSearchQuery ||
            String(inv.invoice_id).includes(ledgerSearchQuery) ||
            String(inv.appointment_id).includes(ledgerSearchQuery) ||
            inv.patient_name.toLowerCase().includes(ledgerSearchQuery) ||
            inv.doctor_name.toLowerCase().includes(ledgerSearchQuery) ||
            inv.department_name.toLowerCase().includes(ledgerSearchQuery);

        let matchesStatus = true;
        if (ledgerStatusFilter === 'Overdue') {
            matchesStatus = inv.is_overdue === true;
        } else if (ledgerStatusFilter !== 'all') {
            matchesStatus = inv.payment_status === ledgerStatusFilter;
        }

        const matchesDept = ledgerDeptFilter === 'all' || inv.department_name === ledgerDeptFilter;

        return matchesSearch && matchesStatus && matchesDept;
    });

    const totalCount = filtered.length;
    const badge = document.getElementById('ledger-total-badge');
    if (badge) badge.textContent = `${totalCount} Invoices`;

    const totalPages = Math.max(1, Math.ceil(totalCount / ledgerPageSize));
    if (ledgerCurrentPage > totalPages) ledgerCurrentPage = totalPages;

    const startIdx = (ledgerCurrentPage - 1) * ledgerPageSize;
    const pageItems = filtered.slice(startIdx, startIdx + ledgerPageSize);

    const summaryText = document.getElementById('ledger-pagination-summary');
    if (summaryText) {
        summaryText.textContent = totalCount === 0
            ? "Showing 0 of 0"
            : `Showing ${startIdx + 1}–${Math.min(startIdx + ledgerPageSize, totalCount)} of ${totalCount}`;
    }

    const pageDisplay = document.getElementById('ledger-page-display');
    if (pageDisplay) pageDisplay.textContent = `Page ${ledgerCurrentPage} of ${totalPages}`;

    const prevBtn = document.getElementById('ledger-prev-btn');
    const nextBtn = document.getElementById('ledger-next-btn');
    if (prevBtn) prevBtn.disabled = ledgerCurrentPage <= 1;
    if (nextBtn) nextBtn.disabled = ledgerCurrentPage >= totalPages;

    tbody.innerHTML = '';
    if (pageItems.length === 0) {
        tbody.innerHTML = '<tr><td colspan="9" class="loading" style="color:var(--text-muted)">No invoices match the search and filter criteria.</td></tr>';
        return;
    }

    pageItems.forEach(inv => {
        const total = parseFloat(inv.total_amount);
        const paid = parseFloat(inv.total_paid);
        const balance = parseFloat(inv.outstanding_balance);

        const statusClass = inv.payment_status === 'Paid in Full' ? 'completed' : (inv.payment_status === 'Partially Paid' ? 'partially-paid' : 'unpaid');
        const overdueBadge = inv.is_overdue ? '<span class="pill" style="background:rgba(244,63,94,0.2);color:var(--danger)">OVERDUE</span>' : '';

        const actionBtn = `
            <div class="btn-action-group">
                ${balance > 0 
                    ? `<button class="btn-pay" onclick="openPaymentModal(${inv.invoice_id}, '${inv.patient_name.replace("'", "\\'")}', ${total}, ${balance})">Pay ₹${balance.toLocaleString('en-IN')}</button>`
                    : `<span class="settled-badge">Settled ✓</span>`}
                <button class="btn-history" onclick="openPaymentHistoryModal(${inv.invoice_id})" title="View complete payment transaction ledger">History</button>
            </div>
        `;

        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td><code>INV-${inv.invoice_id}</code></td>
            <td><code onclick="openAppointmentDrawer(${inv.appointment_id})" title="View appointment details" style="cursor:pointer;color:var(--primary);text-decoration:underline">#${inv.appointment_id}</code></td>
            <td><strong>${inv.patient_name}</strong></td>
            <td><strong>${inv.doctor_name}</strong><br><small style="color:var(--text-secondary)">${inv.department_name}</small></td>
            <td class="text-right num-neutral">₹${total.toLocaleString('en-IN')}</td>
            <td class="text-right num-neutral">₹${paid.toLocaleString('en-IN')}</td>
            <td class="text-right" style="color:${balance > 0 ? 'var(--warning)' : 'var(--text-muted)'};font-weight:600">₹${balance.toLocaleString('en-IN')}</td>
            <td><span class="status-pill status-${statusClass}">${inv.payment_status}</span> ${overdueBadge}</td>
            <td>${actionBtn}</td>
        `;
        tbody.appendChild(tr);
    });
}

function onLedgerFilterChange() {
    ledgerSearchQuery = document.getElementById('ledger-search-input').value.toLowerCase().trim();
    ledgerStatusFilter = document.getElementById('ledger-status-filter').value;
    ledgerDeptFilter = document.getElementById('ledger-dept-filter').value;
    ledgerCurrentPage = 1;
    renderLedgerTable();
}

function changeLedgerPage(delta) {
    ledgerCurrentPage += delta;
    renderLedgerTable();
}

function onLedgerPageSizeChange() {
    ledgerPageSize = parseInt(document.getElementById('ledger-page-size').value);
    ledgerCurrentPage = 1;
    renderLedgerTable();
}

function clearLedgerFilters() {
    document.getElementById('ledger-search-input').value = '';
    document.getElementById('ledger-status-filter').value = 'all';
    document.getElementById('ledger-dept-filter').value = 'all';
    ledgerSearchQuery = '';
    ledgerStatusFilter = 'all';
    ledgerDeptFilter = 'all';
    ledgerCurrentPage = 1;
    renderLedgerTable();
}

// Payment Modal functions
let currentInvoiceBalance = 0;

function openPaymentModal(invId, patientName, total, balance) {
    currentInvoiceBalance = balance;
    document.getElementById('pay-invoice-id').value = invId;
    document.getElementById('pay-invoice-summary').innerHTML = `
        <strong>Invoice #${invId}</strong> for <em>${patientName}</em><br>
        Total Billed: ₹${total.toLocaleString('en-IN')} &bull; Outstanding Balance: <strong style="color:var(--warning)">₹${balance.toLocaleString('en-IN')}</strong>
    `;
    const amtInput = document.getElementById('pay-amount');
    amtInput.value = balance;
    amtInput.max = balance;
    const chk = document.getElementById('pay-confirm-checkbox');
    if (chk) chk.checked = false;
    document.getElementById('modal-feedback').className = "feedback-banner hidden";
    document.getElementById('payment-modal').classList.remove('hidden');
    amtInput.focus();
}

function closePaymentModal() {
    document.getElementById('payment-modal').classList.add('hidden');
}

async function handlePaymentSubmit(event) {
    event.preventDefault();
    const invId = parseInt(document.getElementById('pay-invoice-id').value);
    const amount = parseFloat(document.getElementById('pay-amount').value);
    const method = document.getElementById('pay-method').value;
    const feedback = document.getElementById('modal-feedback');
    const chk = document.getElementById('pay-confirm-checkbox');

    if (chk && !chk.checked) {
        feedback.className = "feedback-banner error";
        feedback.innerHTML = `
            <div class="fb-title">✕ Confirmation Required</div>
            <div class="fb-msg">Please check the confirmation box to authorize recording this transaction in PostgreSQL.</div>
        `;
        return;
    }

    try {
        const res = await fetch(`${API_BASE}/api/payments`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ invoice_id: invId, amount, payment_method: method })
        });

        const data = await res.json();

        if (res.status === 201) {
            feedback.className = "feedback-banner success";
            feedback.innerHTML = `
                <div class="fb-title">✓ Payment Recorded in PostgreSQL</div>
                <div class="fb-msg">${data.message}</div>
                <span class="fb-tech">Ledger updated &bull; Status: ${data.payment_status} &bull; Balance: ₹${data.remaining_balance.toLocaleString('en-IN')}</span>
            `;
            setTimeout(() => {
                closePaymentModal();
                fetchData();
            }, 1000);
        } else {
            feedback.className = "feedback-banner error";
            feedback.innerHTML = `
                <div class="fb-title">✕ ${data.title || 'Payment Blocked'}</div>
                <div class="fb-msg">${data.error}</div>
                ${data.technical_detail ? `<span class="fb-tech">${data.technical_detail}</span>` : ''}
            `;
        }
    } catch (err) {
        feedback.className = "feedback-banner error";
        feedback.innerHTML = `<div class="fb-title">Error</div><div class="fb-msg">${err.message}</div>`;
    }
}

// =============================================================================
// Analytics
// =============================================================================
async function loadAnalytics(startDate = null, endDate = null) {
    let url = `${API_BASE}/api/analytics`;
    if (startDate && endDate) {
        url += `?start_date=${encodeURIComponent(startDate)}&end_date=${encodeURIComponent(endDate)}`;
    }
    const res = await fetch(url);
    const data = await res.json();

    // 0. Analytics KPI Metrics Calculation
    const totalVisits = Object.values(data.appointment_statuses || {}).reduce((a, b) => a + b, 0) || 1;
    const completedVisits = (data.appointment_statuses && data.appointment_statuses.completed) || 0;
    const realizationRate = ((completedVisits / totalVisits) * 100).toFixed(1);
    const cancRate = data.cancellation_rate !== undefined 
        ? data.cancellation_rate 
        : ((( (data.appointment_statuses && data.appointment_statuses.cancelled) || 0) / totalVisits) * 100).toFixed(1);

    const totalInvoiced = (data.department_revenue || []).reduce((acc, d) => acc + parseFloat(d.invoiced), 0);
    const totalCollected = (data.department_revenue || []).reduce((acc, d) => acc + parseFloat(d.collected), 0);
    const collEfficiency = totalInvoiced > 0 ? ((totalCollected / totalInvoiced) * 100).toFixed(1) : '0.0';
    const avgTariff = totalVisits > 0 ? Math.round(totalInvoiced / totalVisits) : 0;

    const kpiReal = document.getElementById('kpi-realization-rate');
    if (kpiReal) kpiReal.textContent = `${realizationRate}%`;
    const kpiCanc = document.getElementById('kpi-cancellation-rate');
    if (kpiCanc) kpiCanc.textContent = `${cancRate}%`;
    const kpiEff = document.getElementById('kpi-collection-efficiency');
    if (kpiEff) kpiEff.textContent = `${collEfficiency}%`;
    const kpiAvg = document.getElementById('kpi-avg-tariff');
    if (kpiAvg) kpiAvg.textContent = `₹${avgTariff.toLocaleString('en-IN')}`;

    // 1. Render Time-Series Encounter & Revenue Velocity Trend Chart (in Overview & Analytics)
    if (data.daily_trends) {
        renderTrendChart('overview-trend-chart', 'overview-trend-tooltip', data.daily_trends);
        renderTrendChart('analytics-trend-chart', 'analytics-trend-tooltip', data.daily_trends);
    }

    // 2. Department Revenue Cards (Billed vs Collected vs Outstanding)
    const deptDiv = document.getElementById('chart-dept-revenue');
    if (deptDiv) {
        deptDiv.innerHTML = '';
        const maxVal = Math.max(...(data.department_revenue || []).map(d => Math.max(parseFloat(d.invoiced), parseFloat(d.collected)))) || 1;

        (data.department_revenue || []).forEach(d => {
            const inv = parseFloat(d.invoiced);
            const col = parseFloat(d.collected);
            const due = Math.max(0, inv - col);
            const invPct = Math.round((inv / maxVal) * 100);
            const colPct = Math.round((col / maxVal) * 100);

            const card = document.createElement('div');
            card.className = 'dept-revenue-card';
            card.innerHTML = `
                <div class="dept-header-row">
                    <span class="dept-title">${d.department_name}</span>
                    <span class="dept-stats">
                        <span class="stat-item billed" title="Total Invoiced">Billed: <strong>₹${inv.toLocaleString('en-IN')}</strong></span>
                        <span class="stat-divider">•</span>
                        <span class="stat-item collected" title="Settled Payments">Collected: <strong>₹${col.toLocaleString('en-IN')}</strong></span>
                        <span class="stat-divider">•</span>
                        <span class="stat-item due" title="Outstanding Due Balance">Due: <strong>₹${due.toLocaleString('en-IN')}</strong></span>
                    </span>
                </div>
                <div class="dept-bars-group">
                    <div class="sub-bar-row">
                        <span class="sub-bar-label">Billed</span>
                        <div class="bar-track" title="Total Invoiced: ₹${inv.toLocaleString('en-IN')} (${invPct}%)">
                            <div class="bar-fill billed" style="width:${invPct}%"></div>
                        </div>
                    </div>
                    <div class="sub-bar-row">
                        <span class="sub-bar-label">Collected</span>
                        <div class="bar-track" title="Realized Collections: ₹${col.toLocaleString('en-IN')} (${colPct}%)">
                            <div class="bar-fill collected" style="width:${colPct}%"></div>
                        </div>
                    </div>
                </div>
            `;
            deptDiv.appendChild(card);
        });
    }

    // 3. Department Breakdown List in Overview
    const summaryList = document.getElementById('dept-summary-list');
    if (summaryList) {
        summaryList.innerHTML = '';
        (data.department_revenue || []).forEach(d => {
            const item = document.createElement('div');
            item.className = 'summary-item';
            item.innerHTML = `
                <span class="summary-title">${d.department_name}</span>
                <span class="summary-val">₹${parseFloat(d.collected).toLocaleString('en-IN')}</span>
            `;
            summaryList.appendChild(item);
        });
    }

    // 4. Status Pipeline Chart
    const statusDiv = document.getElementById('chart-statuses');
    if (statusDiv) {
        statusDiv.innerHTML = '';
        const totalAppts = Object.values(data.appointment_statuses || {}).reduce((a, b) => a + b, 0) || 1;

        for (const [st, count] of Object.entries(data.appointment_statuses || {})) {
            const pct = Math.round((count / totalAppts) * 100);
            const row = document.createElement('div');
            row.className = 'bar-row';
            row.innerHTML = `
                <div class="bar-label" style="text-transform:capitalize">${st.replace('_', ' ')}</div>
                <div class="bar-track">
                    <div class="bar-fill status-${st}" style="width:${pct}%"></div>
                </div>
                <div class="bar-val">${count} (${pct}%)</div>
            `;
            statusDiv.appendChild(row);
        }
    }

    // 5. Doctor Workload Table
    const docTbody = document.getElementById('analytics-doctor-tbody');
    if (docTbody) {
        docTbody.innerHTML = '';
        (data.doctor_workload || []).forEach(dw => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><strong>${dw.doctor_name}</strong></td>
                <td><span class="badge">${dw.department_name}</span></td>
                <td>${dw.bookings} appointments</td>
                <td class="text-right num-neutral" style="font-weight:600;color:var(--primary)">₹${parseFloat(dw.revenue).toLocaleString('en-IN')}</td>
            `;
            docTbody.appendChild(tr);
        });
    }
}

// =============================================================================
// Time-Series Trend Chart (SVG Dual-Axis Volume & Revenue)
// =============================================================================
function renderTrendChart(containerId, tooltipId, trends) {
    const container = document.getElementById(containerId);
    const tooltip = document.getElementById(tooltipId);
    if (!container || !trends || trends.length === 0) return;

    // Dimensions
    const width = 800;
    const height = 200;
    const padding = { top: 20, right: 65, bottom: 30, left: 45 };
    const plotW = width - padding.left - padding.right;
    const plotH = height - padding.top - padding.bottom;

    const maxAppts = Math.max(...trends.map(t => t.total_appts), 6);
    const maxMoney = Math.max(...trends.map(t => Math.max(t.billed, t.collected)), 2000);

    const getX = (i) => padding.left + (i / Math.max(trends.length - 1, 1)) * plotW;
    const getYAppts = (v) => padding.top + (1 - (v / maxAppts)) * plotH;
    const getYMoney = (v) => padding.top + (1 - (v / maxMoney)) * plotH;

    // Build SVG paths
    let apptsPath = '';
    let billedPath = '';
    let collectedPath = '';
    let collectedAreaPath = `M ${getX(0)} ${padding.top + plotH}`;

    trends.forEach((t, i) => {
        const x = getX(i);
        const yA = getYAppts(t.total_appts);
        const yB = getYMoney(t.billed);
        const yC = getYMoney(t.collected);

        if (i === 0) {
            apptsPath += `M ${x} ${yA}`;
            billedPath += `M ${x} ${yB}`;
            collectedPath += `M ${x} ${yC}`;
        } else {
            apptsPath += ` L ${x} ${yA}`;
            billedPath += ` L ${x} ${yB}`;
            collectedPath += ` L ${x} ${yC}`;
        }
        collectedAreaPath += ` L ${x} ${yC}`;
    });
    collectedAreaPath += ` L ${getX(trends.length - 1)} ${padding.top + plotH} Z`;

    // Horizontal grid lines
    const gridLines = [0, 0.5, 1].map(pct => {
        const y = padding.top + pct * plotH;
        const apptVal = Math.round((1 - pct) * maxAppts);
        const moneyVal = Math.round((1 - pct) * maxMoney);
        return `
            <line x1="${padding.left}" y1="${y}" x2="${width - padding.right}" y2="${y}" stroke="rgba(255,255,255,0.06)" stroke-dasharray="3,3" />
            <text x="${padding.left - 8}" y="${y + 4}" fill="#22D3EE" font-size="10" text-anchor="end" font-family="'Consolas', monospace">${apptVal}</text>
            <text x="${width - padding.right + 8}" y="${y + 4}" fill="#34D399" font-size="10" text-anchor="start" font-family="'Consolas', monospace">₹${(moneyVal >= 1000 ? (moneyVal/1000).toFixed(0) + 'k' : moneyVal)}</text>
        `;
    }).join('');

    // X-axis day labels (show every few days to avoid crowding)
    const step = Math.max(1, Math.floor(trends.length / 8));
    const xLabels = trends.map((t, i) => {
        if (i % step === 0 || i === trends.length - 1) {
            const x = getX(i);
            return `<text x="${x}" y="${height - 8}" fill="#94A3B8" font-size="10" text-anchor="middle" font-family="'Inter', sans-serif">${t.day_label || t.day_iso.slice(5)}</text>`;
        }
        return '';
    }).join('');

    // Interactive hover circles
    const circles = trends.map((t, i) => {
        const x = getX(i);
        const yA = getYAppts(t.total_appts);
        return `
            <circle cx="${x}" cy="${yA}" r="4.5" fill="#0B1220" stroke="#22D3EE" stroke-width="2" class="trend-node" data-idx="${i}" style="cursor:pointer;transition:transform 0.15s ease;" />
        `;
    }).join('');

    container.innerHTML = `
        <svg viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
            <defs>
                <linearGradient id="colGradient-${containerId}" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stop-color="#34D399" stop-opacity="0.28"/>
                    <stop offset="100%" stop-color="#34D399" stop-opacity="0.0"/>
                </linearGradient>
            </defs>
            ${gridLines}
            ${xLabels}
            <path d="${collectedAreaPath}" fill="url(#colGradient-${containerId})" />
            <path d="${billedPath}" fill="none" stroke="#FBBF24" stroke-width="1.75" stroke-dasharray="4,4" />
            <path d="${collectedPath}" fill="none" stroke="#34D399" stroke-width="2" />
            <path d="${apptsPath}" fill="none" stroke="#22D3EE" stroke-width="2.5" />
            ${circles}
        </svg>
    `;

    // Tooltip event handlers
    const nodes = container.querySelectorAll('.trend-node');
    nodes.forEach(n => {
        n.addEventListener('mouseenter', (e) => {
            const idx = parseInt(e.target.getAttribute('data-idx'));
            const t = trends[idx];
            if (!t || !tooltip) return;

            e.target.setAttribute('r', '7');
            tooltip.style.display = 'block';
            tooltip.innerHTML = `
                <div class="trend-tooltip-title">${t.day_label || t.day_iso}</div>
                <div>Appointments: <strong style="color:#22D3EE">${t.total_appts}</strong> (${t.completed_appts || 0} completed, ${t.cancelled_appts || 0} cancelled)</div>
                <div>Invoiced Tariffs: <strong style="color:#FBBF24">₹${t.billed.toLocaleString('en-IN')}</strong></div>
                <div>Collected Payments: <strong style="color:#34D399">₹${t.collected.toLocaleString('en-IN')}</strong></div>
            `;
            const rect = container.getBoundingClientRect();
            const nodeX = parseFloat(e.target.getAttribute('cx')) / width * rect.width;
            const nodeY = parseFloat(e.target.getAttribute('cy')) / height * rect.height;
            tooltip.style.left = `${Math.min(nodeX + 12, rect.width - 190)}px`;
            tooltip.style.top = `${Math.max(nodeY - 50, 10)}px`;
        });

        n.addEventListener('mouseleave', (e) => {
            e.target.setAttribute('r', '4.5');
            if (tooltip) tooltip.style.display = 'none';
        });
    });
}

// =============================================================================
// Appointment Detail Drawer (Full Audit Trail & Metadata)
// =============================================================================
async function openAppointmentDrawer(apptId) {
    const backdrop = document.getElementById('drawer-backdrop');
    const drawer = document.getElementById('appointment-drawer');
    const body = document.getElementById('drawer-body');
    const footer = document.getElementById('drawer-footer');
    const title = document.getElementById('drawer-appt-id');
    const pill = document.getElementById('drawer-status-pill');

    if (!drawer) return;

    backdrop.classList.add('open');
    drawer.classList.add('open');
    title.textContent = `Appointment #${apptId}`;
    pill.className = "status-pill";
    pill.textContent = "Loading...";
    body.innerHTML = `<div class="loading" style="padding:40px;text-align:center;color:var(--text-muted)">Loading encounter details & database audit log...</div>`;
    footer.innerHTML = `<button class="action-btn" onclick="closeAppointmentDrawer()">Close</button>`;

    try {
        const res = await fetch(`${API_BASE}/api/appointments/detail?appointment_id=${apptId}`);
        if (!res.ok) {
            body.innerHTML = `<div class="feedback-banner error"><div class="fb-title">Not Found</div><div class="fb-msg">Encounter #${apptId} does not exist in PostgreSQL.</div></div>`;
            return;
        }
        const data = await res.json();
        const a = data;
        const p = { 
            name: data.patient_name, 
            patient_id: data.patient_id, 
            phone: data.patient_phone, 
            dob: data.date_of_birth, 
            blood_group: data.blood_group || 'O+' 
        };
        const d = { 
            name: data.doctor_name, 
            department: data.department_name, 
            specialty: data.specialty, 
            consultation_fee: data.consultation_fee 
        };
        const inv = data.invoice_id ? { 
            invoice_id: data.invoice_id, 
            total_amount: data.total_amount, 
            total_paid: data.total_paid, 
            outstanding_balance: data.outstanding_balance, 
            payment_status: data.payment_status 
        } : null;
        const audits = data.audit_logs || data.audit_log || [];

        // Update status badge
        pill.className = `status-pill status-${a.status}`;
        pill.textContent = a.status;

        const startDate = new Date(a.start_at);
        const endDate = new Date(a.end_at);
        const dateStr = startDate.toLocaleDateString('en-IN', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
        const timeRangeStr = `${startDate.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })} – ${endDate.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })} IST`;

        let auditRowsHtml = '';
        if (audits.length === 0) {
            auditRowsHtml = `<tr><td colspan="4" style="color:var(--text-muted);text-align:center;padding:12px;">No historical status transitions recorded yet.</td></tr>`;
        } else {
            audits.forEach(au => {
                const auTime = new Date(au.changed_at).toLocaleString('en-IN', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
                const transition = au.old_status ? `${au.old_status} ➔ ${au.new_status}` : `Initial: ${au.new_status}`;
                auditRowsHtml += `
                    <tr>
                        <td><code>#${au.audit_id}</code></td>
                        <td>${auTime}</td>
                        <td><span class="status-pill status-${au.new_status}">${transition}</span></td>
                        <td>${au.reason || 'Database operation'}</td>
                    </tr>
                `;
            });
        }

        let invHtml = '';
        if (inv) {
            invHtml = `
                <div class="drawer-section">
                    <div class="drawer-section-title">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>
                        Financial Invoice Ledger (INV-${inv.invoice_id})
                    </div>
                    <div class="drawer-row">
                        <span class="drawer-label">Total Billed:</span>
                        <span class="drawer-val">₹${parseFloat(inv.total_amount).toLocaleString('en-IN')}</span>
                    </div>
                    <div class="drawer-row">
                        <span class="drawer-label">Total Paid:</span>
                        <span class="drawer-val" style="color:var(--success)">₹${parseFloat(inv.total_paid).toLocaleString('en-IN')}</span>
                    </div>
                    <div class="drawer-row">
                        <span class="drawer-label">Outstanding Balance:</span>
                        <span class="drawer-val" style="color:${parseFloat(inv.outstanding_balance) > 0 ? 'var(--warning)' : 'var(--text-muted)'}">₹${parseFloat(inv.outstanding_balance).toLocaleString('en-IN')}</span>
                    </div>
                    <div class="drawer-row">
                        <span class="drawer-label">Invoice Status:</span>
                        <span class="status-pill status-${inv.payment_status === 'Paid in Full' ? 'completed' : (inv.payment_status === 'Partially Paid' ? 'partially-paid' : 'unpaid')}">${inv.payment_status}</span>
                    </div>
                </div>
            `;
        }

        body.innerHTML = `
            <div class="drawer-section">
                <div class="drawer-section-title">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                    Patient Profile
                </div>
                <div class="drawer-row">
                    <span class="drawer-label">Full Name:</span>
                    <span class="drawer-val">${p.name} (MRN #${p.patient_id})</span>
                </div>
                <div class="drawer-row">
                    <span class="drawer-label">Contact Phone:</span>
                    <span class="drawer-val">${p.phone || 'N/A'}</span>
                </div>
                <div class="drawer-row">
                    <span class="drawer-label">Date of Birth & Blood Group:</span>
                    <span class="drawer-val">${p.dob} &bull; ${p.blood_group}</span>
                </div>
            </div>

            <div class="drawer-section">
                <div class="drawer-section-title">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="8.5" cy="7" r="4"/></svg>
                    Attending Physician
                </div>
                <div class="drawer-row">
                    <span class="drawer-label">Doctor Name:</span>
                    <span class="drawer-val">${d.name}</span>
                </div>
                <div class="drawer-row">
                    <span class="drawer-label">Department:</span>
                    <span class="drawer-val">${d.department}</span>
                </div>
                <div class="drawer-row">
                    <span class="drawer-label">Consultation Tariff:</span>
                    <span class="drawer-val" style="color:var(--primary)">₹${parseFloat(d.consultation_fee).toLocaleString('en-IN')}</span>
                </div>
            </div>

            <div class="drawer-section">
                <div class="drawer-section-title">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
                    Schedule & Clinical Notes
                </div>
                <div class="drawer-row">
                    <span class="drawer-label">Encounter Date:</span>
                    <span class="drawer-val">${dateStr}</span>
                </div>
                <div class="drawer-row">
                    <span class="drawer-label">Time Window:</span>
                    <span class="drawer-val">${timeRangeStr} (${a.duration_minutes} min)</span>
                </div>
                <div class="drawer-row" style="margin-top:8px;">
                    <span class="drawer-label">Clinical Notes:</span>
                    <span class="drawer-val" style="font-weight:400;color:var(--text-secondary);">${a.reason || 'General clinical follow-up.'}</span>
                </div>
            </div>

            ${invHtml}

            <div class="drawer-section">
                <div class="drawer-section-title">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                    PostgreSQL Audit Trail (<code>appointment_audit_log</code>)
                </div>
                <table class="drawer-audit-table">
                    <thead>
                        <tr>
                            <th>Audit #</th>
                            <th>Timestamp</th>
                            <th>Transition</th>
                            <th>Trigger / Reason</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${auditRowsHtml}
                    </tbody>
                </table>
            </div>
        `;

        const canCancel = ['scheduled', 'confirmed'].includes(a.status);
        let footerBtns = `<button class="action-btn" onclick="closeAppointmentDrawer()">Close</button>`;

        if (inv && parseFloat(inv.outstanding_balance) > 0) {
            footerBtns = `<button class="btn-pay" onclick="closeAppointmentDrawer();openPaymentModal(${inv.invoice_id}, '${p.name.replace("'", "\\'")}', ${inv.total_amount}, ${inv.outstanding_balance})">Pay Balance ₹${parseFloat(inv.outstanding_balance).toLocaleString('en-IN')}</button>` + footerBtns;
        }

        if (canCancel) {
            footerBtns = `<button class="btn-danger-outline" onclick="closeAppointmentDrawer();cancelAppointment(${a.appointment_id})">Cancel Appointment</button>` + footerBtns;
        }

        footer.innerHTML = footerBtns;
    } catch (err) {
        body.innerHTML = `<div class="feedback-banner error"><div class="fb-title">Error</div><div class="fb-msg">${err.message}</div></div>`;
    }
}

function closeAppointmentDrawer() {
    const backdrop = document.getElementById('drawer-backdrop');
    const drawer = document.getElementById('appointment-drawer');
    if (backdrop) backdrop.classList.remove('open');
    if (drawer) drawer.classList.remove('open');
}

// =============================================================================
// Payment History Ledger Modal
// =============================================================================
async function openPaymentHistoryModal(invoiceId) {
    const modal = document.getElementById('payment-history-modal');
    const title = document.getElementById('history-modal-title');
    const badge = document.getElementById('history-invoice-id');
    const tbody = document.getElementById('payment-history-tbody');
    const histInvoiced = document.getElementById('hist-invoiced');
    const histPaid = document.getElementById('hist-paid');
    const histBalance = document.getElementById('hist-balance');

    if (!modal) return;
    badge.textContent = `INV-${invoiceId}`;
    modal.classList.remove('hidden');
    tbody.innerHTML = `<tr><td colspan="6" class="loading">Loading transaction records from PostgreSQL...</td></tr>`;

    try {
        const res = await fetch(`${API_BASE}/api/payments/history?invoice_id=${invoiceId}`);
        if (!res.ok) {
            tbody.innerHTML = `<tr><td colspan="6" class="loading" style="color:var(--danger)">Failed to load invoice history.</td></tr>`;
            return;
        }
        const data = await res.json();
        title.textContent = `Payment Ledger for ${data.patient_name}`;
        histInvoiced.textContent = `₹${parseFloat(data.total_amount).toLocaleString('en-IN')}`;
        histPaid.textContent = `₹${parseFloat(data.total_paid).toLocaleString('en-IN')}`;
        histBalance.textContent = `₹${parseFloat(data.outstanding_balance).toLocaleString('en-IN')}`;

        const payments = data.payments || [];
        tbody.innerHTML = '';
        if (payments.length === 0) {
            tbody.innerHTML = `<tr><td colspan="6" class="loading" style="color:var(--text-muted)">No payment transactions recorded for this invoice yet.</td></tr>`;
            return;
        }

        payments.forEach(p => {
            const tr = document.createElement('tr');
            const pDate = new Date(p.paid_at).toLocaleString('en-IN', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
            const pTypeBadge = p.payment_type === 'reversal' 
                ? '<span class="status-pill status-cancelled">Reversal</span>' 
                : '<span class="status-pill status-completed">Payment</span>';

            tr.innerHTML = `
                <td><code>PAY-${p.payment_id}</code></td>
                <td>${pDate}</td>
                <td style="text-transform:capitalize">${(p.payment_method || 'N/A').replace('_', ' ')}</td>
                <td><code>${p.reference_code || 'REF-N/A'}</code></td>
                <td class="text-right num-neutral" style="font-weight:600">₹${parseFloat(p.amount).toLocaleString('en-IN')}</td>
                <td>${pTypeBadge}</td>
            `;
            tbody.appendChild(tr);
        });
    } catch (err) {
        tbody.innerHTML = `<tr><td colspan="6" class="loading" style="color:var(--danger)">Error: ${err.message}</td></tr>`;
    }
}

function closePaymentHistoryModal() {
    const modal = document.getElementById('payment-history-modal');
    if (modal) modal.classList.add('hidden');
}

function onCalendarFilterChange() {
    renderCalendar();
}

// =============================================================================
// Booking Form & Conflict Simulator (Requirement 2 & 4)
// =============================================================================
async function handleBookingSubmit(event) {
    event.preventDefault();
    const btn = document.getElementById('btn-submit-booking');
    const feedback = document.getElementById('booking-feedback');

    const patient_id = parseInt(document.getElementById('book-patient').value);
    const doctor_id = parseInt(document.getElementById('book-doctor').value);
    const start_at = document.getElementById('book-start').value;
    const end_at = document.getElementById('book-end').value;
    const reason = document.getElementById('book-reason').value;

    btn.disabled = true;
    btn.textContent = "Verifying constraints in PostgreSQL...";
    feedback.className = "feedback-banner hidden";

    try {
        const res = await fetch(`${API_BASE}/api/appointments`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ patient_id, doctor_id, start_at, end_at, reason })
        });

        const data = await res.json();

        if (res.status === 201) {
            feedback.className = "feedback-banner success";
            feedback.innerHTML = `
                <div class="fb-title">✓ Booking Confirmed in PostgreSQL</div>
                <div class="fb-msg">${data.message}</div>
                <span class="fb-tech">PostgreSQL GiST constraint verified &bull; No overlaps &bull; Invoice #${data.invoice_id} created</span>
            `;
            fetchData();
        } else if (res.status === 409) {
            // User-friendly error message as requested
            feedback.className = "feedback-banner error";
            feedback.innerHTML = `
                <div class="fb-title">✕ ${data.title || 'Booking Conflict'}</div>
                <div class="fb-msg">${data.error}</div>
                <span class="fb-tech">${data.technical_detail || 'PostgreSQL GiST exclusion constraint rejected overlapping range'}</span>
            `;
        } else if (res.status === 422) {
            feedback.className = "feedback-banner error";
            feedback.innerHTML = `
                <div class="fb-title">✕ ${data.title || 'Shift / Validation Error'}</div>
                <div class="fb-msg">${data.error}</div>
                <span class="fb-tech">${data.technical_detail || 'Validation constraint'}</span>
            `;
        } else {
            feedback.className = "feedback-banner error";
            feedback.innerHTML = `
                <div class="fb-title">✕ ${data.title || 'Booking Failed'}</div>
                <div class="fb-msg">${data.error || 'Unable to record appointment'}</div>
            `;
        }
    } catch (err) {
        feedback.className = "feedback-banner error";
        feedback.innerHTML = `<div class="fb-title">Network Error</div><div class="fb-msg">${err.message}</div>`;
    } finally {
        btn.disabled = false;
        btn.textContent = "Book Appointment via PostgreSQL";
    }
}

function triggerPresetConflict() {
    // Select Doctor 1 (Dr. Aditi Sharma) and choose a time that overlaps an existing active appointment
    // (e.g. 2026-11-02 09:15 to 09:45, which conflicts with Monday 09:00 to 09:30)
    document.getElementById('book-doctor').value = "1";
    updateDoctorShiftHint();
    document.getElementById('book-start').value = "2026-11-02T09:15";
    document.getElementById('book-end').value = "2026-11-02T09:45";
    document.getElementById('book-reason').value = "Intentional double-booking conflict test";

    document.getElementById('btn-submit-booking').click();
}

function updateDoctorShiftHint() {
    const docId = parseInt(document.getElementById('book-doctor').value);
    const hint = document.getElementById('doctor-shift-hint');
    if (!hint) return;

    if (!docId) {
        hint.style.display = 'none';
        return;
    }

    const doc = doctorsData.find(d => d.doctor_id === docId);
    if (!doc) return;

    const weekdayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const shiftStrings = doc.shifts.map(s => `${weekdayNames[s.weekday]} ${s.start_time.slice(0,5)}-${s.end_time.slice(0,5)}`).join(', ');

    hint.style.display = 'block';
    hint.innerHTML = `<strong>Dr. ${doc.name}'s Shift Hours:</strong> ${shiftStrings || 'No fixed shifts'}`;
}

async function cancelAppointment(apptId) {
    if (!confirm(`Are you sure you want to cancel Appointment #${apptId}?\n\nCancelling will immediately update its status in PostgreSQL and liberate the time slot in the GiST exclusion index.`)) {
        return;
    }

    try {
        const res = await fetch(`${API_BASE}/api/appointments/cancel`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ appointment_id: apptId, reason: "Cancelled by user via Dashboard" })
        });
        const data = await res.json();
        alert(data.message || data.error);
        fetchData();
    } catch (err) {
        alert("Failed to cancel: " + err.message);
    }
}
