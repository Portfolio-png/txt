# Phase 2 Roadmap — Deferred Machine Telemetry

> Status: DEFERRED. Recorded 2026-08-12 as part of the Telemetry, Barcodes & Tracing
> handover. These items are intentionally **not** shipped in Phase 1.

## Why these are deferred

The shop-floor operators who would feed and read these metrics have limited literacy and
training. Every metric below requires either **continuous machine instrumentation** or
**repeated manual operator input** at each cycle — process friction that outweighs the
Phase-1 value. Phase 1 therefore ships only what needs **no new per-cycle capture**: the
machine **barcode** and the **queue popup** (backed by real run/assignment data). The three
items here wait until the floor has the hardware and/or the operator workflows to sustain
them without corrupting the data.

Common prerequisite: a **machine state / activity log** — timestamped state transitions
(`running / idle / setup / faulted / offline`) per machine, sourced from a PLC/IoT feed or a
disciplined operator start/stop capture. No such log or per-machine run timestamps exist
today (the current `MachineTelemetry` model in
`lib/features/machines/domain/machine_telemetry.dart` is a **client-side random simulation**,
not real data). Until that pipeline exists, none of the following can be computed honestly.

---

## 1. Machine idle-time %  *(spec §1A)*

- **What**: "percentage of scheduled operational hours a machine remained inactive," shown as
  a color-coded dot (green <15%, amber 15–40%, red >40%) on the machine card.
- **Blocked on**: a machine state/activity log (above) **and** a notion of *scheduled
  operational hours* (shift calendar) to divide idle time against. Neither exists.
- **Phase-2 build sketch**: new `machine_activity_log(machine_id, state, started_at,
  ended_at)`; derive idle% over a window = Σ idle-interval ÷ scheduled hours. Feed it from the
  same run assignment/timestamps introduced for the queue, plus a shift calendar.

## 2. Stroke-cycle counting  *(spec §4.1)*

- **What**: live mechanical stroke counts per machine/die.
- **Blocked on**: per-stroke telemetry from the press (sensor / PLC counter). There is no live
  stroke feed; the `dies` table already carries **static** `stroke_count`, `max_strokes`,
  `strokes_per_piece` fields (`backend/server.js`, `dies` table) but nothing increments them
  from real cycles.
- **Phase-2 build sketch**: ingest a stroke counter per run/die-node, accumulate onto
  `dies.stroke_count`, expose per-run stroke tallies.

## 3. Die-wear %  *(spec §4.2)*

- **What**: automated wear-degradation percentage per die.
- **Blocked on**: (2) above — wear% is a function of accumulated strokes vs. `max_strokes`
  (and material hardness). Without real stroke counting it can only be a static ratio, which
  would mislead operators.
- **Phase-2 build sketch**: `wear% = stroke_count / max_strokes` once stroke counting is live;
  surface as a maintenance indicator on the die card with a service threshold.

---

## Not deferred (shipped in Phase 1)
- **Machine barcode** — `machines.barcode` (system-generated, defaults to `asset_id`);
  scannable chip on the machine card.
- **Queue popup** — real `machine_id` run assignment + `created_by` + `weight_kg`, surfaced as
  the battery-level indicator and click-through queue list. This work also lays the
  run↔machine-timestamp groundwork that the idle-time metric (1) will reuse.
