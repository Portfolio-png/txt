# ERP Deployment Readiness Assessment

_Generated 2026-07-01 from a survey of the actual repo (frontend, backend/deploy, tests)._

**Net:** You're closer to a deployable single-client pilot than it might seem — the
deploy machinery already exists. The gaps are concentrated in security hardening,
backups, and a few untested money/inventory paths.

---

## What's in place (works today)

- **Frontend: ~16 modules production-ready** — Orders, Clients, Vendors, Items
  (variation trees), Groups, Units, Delivery/Reception Challans, Inventory + barcode
  scan, Departments, Machines, Dies, Production pipelines (7 screens), Jobs/freelancer
  portal, PM, Dashboard + Reports. Codebase is clean (no TODO/FIXME litter). Two app
  builds share `core_erp`: the full app and `challans_only`.
- **Backend: ~223 endpoints**, full CRUD across all the above. Auth is genuinely solid
  — JWT + server-side sessions, PBKDF2 (120k iters), login lockout, granular
  permissions + roles, audit-event logging with IP/UA.
- **Feature-flag system works** — 14 flags, per-client config served from
  `/sandbox-config/:clientId`, offline dev overlay. This is the core "tailor per
  client" mechanic and it's functioning.
- **Deploy automation already exists** (the good news for "on the go"):
  `ecosystem.config.js` (PM2), `deploy/nginx.paper.conf`,
  `.github/workflows/deploy-backend.yml` (push-to-main → SCP to EC2 → pm2 restart),
  `deploy/redeploy.sh` with health check, `.env.example` (27 vars), and a `/health`
  endpoint. Seeding/smoke tooling is good (`reseed-demo-data`, `simulate-user-flow`,
  `smoke-check`).

---

## Real blockers before a client touches it

1. **Auth-bypass endpoints are wide open** — `/sandbox-*`, `/config`, `/activation`,
   `/build` skip auth entirely (`backend/server.js:1317`). Fine on localhost,
   dangerous on a public box. Lock these to internal/IP-allowlist or a shared token
   before exposing.
2. **No TLS** — nginx config listens on port 80 only. Terminate TLS upstream
   (ALB/CloudFront) or add certbot. Non-negotiable for real auth tokens.
3. **No automated DB backup** — `paper.db` is a single file; `backup-sqlite.js` exists
   but nothing schedules it. One cron → S3 and you're safe. **Highest
   value-to-effort item on this list.**
4. **"Multi-client" today is config-only, not data-isolated** — all clients share one
   dataset; only feature config differs (`backend/server.js:21675`). **Decision
   point:** if it's *one client per server*, you're fine now. If you intend *multiple
   real clients on one backend*, that's a hard blocker (needs tenant scoping).

---

## Verify before invoicing real money/stock (surveyed as under-tested)

- **Invoice tax/rounding math** — only basic creation is tested; no edge cases for
  decimal rates, rounding, negative lines (`createInvoice`, ~`server.js:10016`).
- **Order merge when invoiced-qty exceeds new qty** — underflow risk, untested
  (`saveOrder`, ~`server.js:12495`).
- **Challan cancel/delete reversal chains** — one atomicity bug here was just fixed
  (see below); the cancel path's multi-reversal cases are still untested.
- **Cascade deletes** (client → orders → challans → invoices) — approval workflow is
  tested, cascade integrity is not.

---

## Not blockers (don't get distracted)

- **SQLite single-writer** — totally fine for one shop/pilot. Plan Postgres only when
  concurrency or true multi-tenancy arrives.
- **Demo-mode `UnimplementedError` stubs** (mock order-edit, pipeline metrics) — only
  affect `useMockResponses`, not the real backend.
- **Finance Aging** — widgets + mock only, no screen wired in; it's unreachable, so it
  ships dark. Leave it.
- **CI runs deploy but not tests** — add `npm test` as a gate when convenient; not
  blocking a pilot.

---

## Shortest path to "test on the go" (single-client pilot)

1. Set real secrets in `.env` on EC2 (`PAPER_JWT_SECRET`, super-admin creds,
   `PAPER_CORS_ORIGIN`).
2. Lock the auth-bypass routes + put TLS in front.
3. Add a backup cron (`backup-sqlite.js` → S3, hourly/daily).
4. `reseed-demo-data` on a staging copy → run `smoke-check` + `simulate-user-flow` →
   hand a client the build with their flags set.

**Skipped for now:** Postgres, multi-tenant isolation, CI test gate — add when you go
past one client or hit concurrency.

---

## Appendix: survey detail

### Backend / deploy

- **API:** ~223 endpoints across challans, inventory, orders, invoices, users/auth,
  config masters, production, reports, freelancer jobs.
- **Auth strengths:** HS256 JWT + `auth_sessions` table (token-hash verification, TTL
  via `PAPER_JWT_TTL_SECONDS`); PBKDF2-SHA256 120k/32-byte/timing-safe; permission
  keys + role fallback; session revocation; auth-event logging (retention via
  `PAPER_AUTH_EVENTS_RETENTION_DAYS`); 5-attempt/15-min lockout.
- **Auth gaps:** dev JWT-secret fallback (`paper-local-development-secret`); no CORS by
  default; no CSRF tokens; no global rate limiting (login only); `auth_sessions` never
  pruned; super-admin seeded from env.
- **Database:** SQLite WAL, single file. Migrations = `001-init.sql` + JS migrations
  (002–004), tracked in `_migrations`, **one-way (no rollback)**. `initDb()` does
  defensive-but-fragile ad-hoc ALTERs on boot. No connection pooling (serialized,
  single writer). `PAPER_BACKUP_DIR` documented but unused; no automated backup.
- **Multi-client:** `sandbox_client_configs` table + `/sandbox-config/:clientId`
  fallback to `default`; feature registry via `bin/generate_registry.dart` →
  `feature_registry.json`. **No row-level tenant isolation** — `clientId` is advisory;
  `/api/sandbox-sync/:clientId` is unauthenticated.
- **Deploy artifacts:** `ecosystem.config.js` (fork mode, 300M limit, auto-restart, `instances: 1`);
  `deploy/nginx.paper.conf` (reverse proxy, 20M upload, HTTP only); `.env.example`;
  `.github/workflows/deploy-backend.yml`; `deploy/redeploy.sh` (git pull, npm install,
  pm2 start, health + smoke check, `pm2-logrotate`).
- **Deploy blockers:** no secrets management (manual `.env`); single instance
  hard-coded; manual EC2 prep (Node, pm2, sqlite3 build tools); forward-only redeploy;
  CI does not run tests; SQLite concurrency.

### Frontend

- **Production-ready (16):** Orders, Clients, Vendors, Items, Groups, Units, Delivery
  Challans, Inventory, Departments, Machines, Dies, Production (7 screens), Production
  Pipelines, Jobs, PM, Dashboard + Reports.
- **Partial (1):** Finance Aging — widgets + mock data only, no screen entry point, no
  backend.
- **Demo-mode stubs (don't affect real backend):** mock order edit
  (`api_order_repository.dart:204`), pipeline metrics/scrap/batch logging
  (`sqlite_pipeline_run_repository.dart:475/486/494`).
- **Feature flags (14):** module gates `modules.{orders,masters,inventory,production,
  pm,jobs,delivery_challans}`; feature toggles `orders.allowCustomActions`,
  `orders.allowOrdersCreation`, `features.disableMachineCustomFields`,
  `enhancements.catalogInventory`, `challans.singleTypeView`. Backend-served with
  15-min polling; offline dev overlay; defaults true.
- **Apps:** main (`lib/`) and `challans_only` (stripped nav, full challan impl), shared
  via `core_erp`.
- **Known BUG-NN markers (frontend):** BUG-02 draft orders skip variation-path check
  (`orders_screen.dart:4259`); BUG-11 barcode lookup flag vs loading state
  (`inventory_provider.dart:25`); BUG-12 master-only group visibility
  (`inventory_screen.dart:1553`); BUG-14 top-level-property items with no leaf variants
  (`orders_screen.dart:4239`); plus BUG-05/06/07/09.

### Tests

- **Backend:** `node:test` via `npm test` → `node --test ./test/*.test.js`. 7 files.
  Strong: auth/roles/permissions, delivery-challan creation/issuance/reconciliation.
  Medium: orders, inventory sets, material governance, integrity-safety. Low:
  demo-seed.
- **Frontend:** `flutter_test`, 15 files. Solid: production (ledger math, run
  lifecycle, pipeline validation, batch flow). Partial: clients/groups/job-work logic.
  Most UI screens lack integration tests.
- **Manual/seed tooling:** `reseed-demo-data`, `smoke-check`, `simulate-user-flow`,
  `validate-full-seed-data`, `populate-challans`, `seed_variance`,
  `create-test-invoice`, `backup-sqlite`/`restore-sqlite`.
- **Top areas to verify before deploy:** invoice tax calculations; order merge with
  invoiced qty; challan cancellation reversal chain; cascade-delete integrity.
- **Overall estimated coverage ~25%** — happy paths well covered; financial math,
  cascades, and error/edge handling under-tested.

### Recently fixed (this session)

- **Reception/issued-challan deletion FK bug** — delete committed successfully, then a
  post-commit `logDeliveryChallanActivity()` insert into
  `delivery_challan_activity_log` (which has `ON DELETE CASCADE` on `challan_id`) hit a
  `FOREIGN KEY constraint failed`. The API reported failure for a delete that had
  already happened → the red "record in use" toast + a vanished challan + "not found"
  on retry. Fix: dropped the impossible post-delete activity-log write
  (`backend/server.js`, `deleteDraftDeliveryChallan`). Verified against a copy of the
  live DB: intact issued challan deletes cleanly with correct inventory reversal; draft
  delivery challans still delete; partially-consumed reception challans correctly block
  with a clean `Insufficient stock` message and stay atomic.
