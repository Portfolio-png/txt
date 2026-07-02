# HR / Payroll completion + Freelancer marketplace loop — Plan

## Context

The **employee master** (departments + employees, with bank/UAN/ESI/tax_regime
columns) already exists, and migration `005-payroll-and-portal.js` already created
**all the HR tables** — `payroll_components`, `employee_salary_structures(+lines)`,
`attendance_records`, `leave_types`, `leave_balances`, `payroll_runs`,
`payroll_run_details`, `payslips`, `statutory_config`. But the feature is **not
usable**:

- The inline payroll routes in `backend/server.js` (~L22579–22722) are **broken
  against the real schema** — they query `user_id` (column is `employee_id`),
  insert `period_start`/`created_by`/`remarks` into `payroll_runs` (columns are
  `month`/`year`/`total_*`), and the CSV reads `d.gross_pay`/`d.net_pay`
  (columns are `amount`/`is_deduction`).
- There is **no payroll processing engine** — nothing computes gross / statutory
  deductions / net into `payroll_run_details`.
- There are **no routes at all** for attendance, leave, or statutory config.
- `backend/routes_payroll.js` is **orphaned dead code** (never `require()`d) and
  carries the same broken schema.
- There is **no Flutter UI** for any HR feature.

Separately, the **Freelancer Jobs** module (`modules.jobs`, tables
`freelancer_job_batches/jobs/tasks`, plus a working Flutter feature) exists but
does manual freelancer assignment — **no skills, no ratings, no matching**. And
"payment reconciliation" doesn't exist for either freelancer payouts or customer
AR (only material/GST challan↔invoice reconciliation does).

**Goal (decided with user):** one phased build — **finish HR first**, then the
**freelancer loop** (weighted-score skill-matching + ratings + payment
reconciliation covering **both** freelancer payouts **and** customer AR).

## Conventions to follow (do not reinvent)

- **Backend:** single `server.js`, global `app`, inline `app.get/post/put/delete`,
  `get/all/run` sqlite promise helpers (server.js:411-445), auth via
  `requirePermission('config.read'|'config.write')`. New tables → a numbered
  migration in `backend/migrations/00X-*.js` (run in sorted order, tracked in
  `_migrations`). Payroll routes return **raw snake_case rows** — keep that.
- **Frontend:** Flutter + `provider` (`ChangeNotifier` + `Consumer`), plain
  `fromJson/toJson` models, feature folder = `domain/ + data/repositories/ +
  presentation/{providers,screens}`. Copy the `features/departments` feature as
  the template. Repos use a raw `http.Client` against `baseUrl + /api/...`.
- **Feature flags (mandatory, CLAUDE.md):** every module ships behind an
  `@FeatureFlag` key in `feature_flags.dart`, gated with `FeatureFlags.isEnabled`,
  wired into `config_service.dart` (`isModuleEnabled` + `_moduleForNavKey`),
  `app_sidebar.dart`, and `app_shell.dart` router, then
  `dart run bin/generate_registry.dart`.

---

## Phase 1 — HR completion (backend)  ← starting here

**Migration `009-hr-followups.js`:**
- `ALTER TABLE payroll_run_details ADD COLUMN label TEXT DEFAULT ''` (so statutory
  lines with `component_id = NULL` still show a name on the payslip).
- `CREATE TABLE leave_requests (id, employee_id, leave_type_id, from_date,
  to_date, days, reason, status['pending'|'approved'|'rejected'], created_at,
  decided_at)` — the missing piece for "leave management" (apply → approve →
  decrement balance).
- Seed a default company `statutory_config` row (`client_id = 0`) with the India
  defaults already in the schema so processing works out of the box.

**Pure calc engine `backend/payroll_calc.js`** (require-able, unit-tested — money
path): `computePayslip({ lines, statCfg, attendanceRatio })` →
`{ gross, deductions, net, detailLines }`.
- Earnings from structure lines (`fixed` or `percent_of_basic`), prorated by
  attendance ratio.
- Statutory: **PF** = rate% × min(basic, `pf_wage_ceiling`); **ESI** = rate% ×
  gross when gross ≤ `esi_eligible_threshold`; **PT** from `pt_slabs_json`;
  **TDS** flat from `tds_config_json` (`{ "monthly": n }`).
- Non-statutory deduction lines subtracted as-is. All money rounded to 2 dp.
- Check: `backend/test/payroll_calc.test.js` (assert-based, no framework).

**Fix + extend routes in `server.js`** (replace the broken payroll block):
- Fix `salary-structure` GET/PUT (`employee_id`, `effective_from`,
  `amount_or_formula`, `sequence`).
- Fix `runs` list/create (`month`/`year`, order by year/month) and CSV summary
  (join employee name; aggregate from details).
- **New** `POST /api/payroll/runs/:id/process` — the engine: for each active
  employee with an active structure, compute attendance ratio (present-equiv /
  `workingDays`, default 26; ratio 1 if no records), run `computePayslip`, write
  `payroll_run_details`, roll up run totals, set `status='processed'`.
- **New** attendance: `GET/POST(upsert)/DELETE /api/attendance`.
- **New** leave: `GET/POST /api/leave/types`, `GET/PUT /api/leave/balances`,
  `GET/POST /api/leave/requests`, `PUT /api/leave/requests/:id` (approve →
  update balance).
- **New** statutory: `GET/PUT /api/statutory-config` (single `client_id=0` row).
- **Delete** `backend/routes_payroll.js` (dead + wrong schema).

Verify: `npm start` boots, `node backend/test/payroll_calc.test.js` passes, curl
create-run → process → summary returns non-zero net.

## Phase 1 — HR completion (frontend)

New Flutter module `features/hr` behind flag `modules.hrPayroll` (default off per
CLAUDE.md selector convention; enable per client). Wire the 6 module touchpoints.
Screens (reuse departments/employee patterns + existing widgets `AppCard`,
`PmSegmentedControl`, `SearchableSelect`):
- **Salary structure** editor on an employee (components + amounts).
- **Attendance** grid (month × employee); barcode clock-in reusing
  `material_barcode_toolkit` + `employees.barcode_id` is a stretch add.
- **Leave** — types, balances, request/approve list.
- **Payroll run** — create month/year → Process → per-employee payslip table →
  CSV export; statutory-config settings screen.
- `payroll_components` master editor.

## Phase 2 — Freelancer loop (the "unique angle")

**Skills + matching** (migration `010`): `skills` master, `employee_skills`
(employee ↔ skill, optional proficiency), `item_required_skills` (or per-job
required skills). `GET /api/jobs/:id/candidates` returns freelancers ranked by a
**weighted score** = skill-overlap × w1 + avg_rating × w2 + availability(inverse
current open-job load) × w3 (weights in one config object). UI: "Suggest
freelancers" on a job shows the ranked list; assign from there.

**Ratings** (migration `010`): `freelancer_ratings(job_id, employee_id, score,
remarks, created_at)`; capture on job completion; feeds the matcher's avg_rating.

## Phase 3 — Payment reconciliation (both)

Migration `011`: generic `payments(id, direction['in'|'out'], party_type
['customer'|'freelancer'], party_id, amount, paid_on, method, reference, note)`
+ `payment_allocations(payment_id, target_type['invoice'|'job'], target_id,
amount)`. Engine matches a payment across open targets, tracks outstanding.
- **Freelancer payouts:** allocate `direction='out'` payments against
  `freelancer_jobs.payout_balance`; show unpaid payout aging.
- **Customer AR:** allocate `direction='in'` payments against `invoice_headers`;
  show receivable aging.
- One reconciliation screen with a customer/freelancer toggle (reuse the existing
  reconciliation report UI shell in `app/reports/`).

---

## Verification (end to end)

1. Backend: `cd backend && node test/payroll_calc.test.js` (calc), `npm start`
   (boots + runs migrations), curl the new routes.
2. App: `flutter run -d windows` with the module flags enabled in
   `dev_config.dart` (`--dart-define=PAPER_OFFLINE_CONFIG=true` for fast UI
   iteration), exercise each screen against the local backend.
3. After adding flags: `dart run bin/generate_registry.dart` and confirm the new
   toggles appear in the dashboard registry.
