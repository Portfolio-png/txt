# Falcon View — Control Plane

A vendor-side service that ingests telemetry from Paper client deployments and
renders a fleet dashboard: cross-client business benchmarks and every user
(staff → admin) across all deployments.

It runs on **one vendor-owned box**, separate from any client. Each client
deployment pushes a periodic snapshot to it.

```
client backend (per-client AWS)        vendor control plane (1 box)
  computeTelemetrySnapshot()   ──POST /api/ingest──►  SQLite store
  (KPIs + user roster)          x-deployment-key       GET /  → Falcon View
```

## ⚠️ Disclosure — read before enabling

The data collected here (business aggregates **and the user roster, which is
PII**) is a **managed-service / benchmarking** feature. It is legitimate and
sellable — but only if it is **disclosed and agreed** in the client contract /
Data Processing Agreement, and consented where required (India DPDP Act 2023;
GDPR if any EU data). Do **not** enable the emitter for a client who has not
agreed. Anonymize/aggregate where you can; keep the roster to what the managed
service actually needs. Selling it as "benchmarking + managed hosting" is the
right framing; hiding it is not.

The emitter is **off by default** — it only runs when the client deployment sets
`CONTROL_PLANE_URL` + `DEPLOYMENT_KEY`. That opt-in gate is deliberate.

## Run the control plane

```bash
cd control-plane
npm install
FALCON_PASSWORD='a-strong-secret' \
DEPLOYMENT_KEYS='key-clientA,key-clientB' \   # optional allow-list; omit for trust-on-first-use
node server.js
```

Env:

| var | default | purpose |
|-----|---------|---------|
| `CONTROL_PLANE_PORT` | `19090` | listen port |
| `CONTROL_PLANE_DB` | `./control_plane.db` | SQLite store path |
| `FALCON_USER` / `FALCON_PASSWORD` | `vendor` / `change-me` | HTTP Basic auth for the dashboard — **change these** |
| `DEPLOYMENT_KEYS` | *(empty)* | comma-separated allow-list of deployment keys; empty = accept + register any key |

The **website** is at `http://<box>:19090/` and `http://<box>:19090/control-plane`
(the AWS IP). Log in with `FALCON_USER` / `FALCON_PASSWORD`. Put it behind TLS (a
reverse proxy) before exposing it publicly.

Leave `DEPLOYMENT_KEYS` **unset** for zero-friction onboarding — deployments
self-enroll (trust-on-first-use). Set it only if you want to pin an allow-list.

## Enable the emitter on a client deployment (low friction)

The **only** thing to set on the client's `backend` process is where to report —
the deployment generates and persists its own id + key on first boot, so there's
no per-client key to hand off:

```bash
CONTROL_PLANE_URL='https://control.yourvendor.com'   # the only required value
DEPLOYMENT_NAME='Client A Pvt Ltd'                   # optional, nicer label
TELEMETRY_INTERVAL_MS=3600000                        # optional, default hourly
COMMAND_POLL_MS=60000                                # optional, admin-command poll
```

The self-enrolled identity is written to `deployment-identity.json` next to the
database, and reused on every boot. (You can still pin `DEPLOYMENT_ID` /
`DEPLOYMENT_KEY` via env if you prefer.) Leave `CONTROL_PLANE_URL` unset and
nothing is collected or provisioned — it's opt-in, per the disclosure above.

The backend pushes a snapshot ~10s after boot and every interval after, and polls
for admin-provisioning commands every `COMMAND_POLL_MS`.

## Managed deployments have no default super admin

When `CONTROL_PLANE_URL` is set (a managed client), the app does **not** create a
baked-in `super@paper.local` login. The deployment starts with no users and you
provision the first **admin** from the Falcon View ("Provision admin logins").
Break-glass: set `PAPER_SUPER_ADMIN_EMAIL` + `PAPER_SUPER_ADMIN_PASSWORD` to mint
a one-off super admin. (Dev/standalone runs without a control plane still get the
convenient `super@paper.local` default.)

## What a snapshot contains

- **metrics**: orders, open orders, challans, items, on-hand inventory qty,
  production runs, clients, active users.
- **users**: id, name, email, role, active flag, last login — the roster the
  Falcon View "handle every user (staff → admin)" view is built from.

## Endpoints

- `POST /api/ingest` — client → control plane (auth: `x-deployment-key`).
- `GET /` — Falcon View dashboard (auth: HTTP Basic).
- `GET /api/fleet` — same data as JSON (auth: HTTP Basic).
- `GET /healthz` — liveness.

## MVP boundaries / next steps

This is a working foundation. Natural follow-ups: TLS + per-key rotation, trend
charts from snapshot history (the store already keeps every snapshot), alerting
on stale deployments, role-based access for the dashboard, and richer
benchmarking (percentiles, cohorts). None are required to run it today.
