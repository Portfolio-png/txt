---
name: design-philosophy
description: Core architectural principles and design philosophy for Paper ERP. Use whenever designing a new feature, adding or modifying database schemas, creating or adapting UI screens for different clients, designing event logging or audit trails, structuring business rules between backend and frontend, or planning analytics and metric clusters.
---

# Paper — Design Philosophy

*Adopted 2026-10-04 · @Funnel*

This document is the contract for feature architecture, multi-client screen adaptation, canonical data modeling, backend rule enforcement, event logging, and product metric clustering in Paper. If code, a pull request, or a proposed UI/schema violates this contract, the code is wrong and must be moved toward this standard.

The model for single-pattern domain execution is the **units** skill (`.claude/skills/units/SKILL.md`). This skill generalizes that discipline across the entire system.

---

## 1. Why this exists

Paper serves manufacturing factories that operate and think very differently. Our first client may demand a classic 10-dropdown screen (one box per process stage, each listing every stage in the factory, exactly one selection per box). Subsequent clients will expect visual drag-and-drop pipelines, fast batch-entry tables, or cloned template workflows, and will demand rich analytics from their floor data.

If we build each client's idiosyncratic screen preferences directly into database schemas or backend APIs:
1. Every new client requires a structural rewrite.
2. Cross-client analytics become impossible due to fragmented data shapes.
3. Client-specific UI validation hacks will inevitably leak and corrupt data integrity.

This skill establishes the rules that keep the data core unified, robust, and extensible, while enabling screens to adapt freely per client. It also defines how floor events naturally cluster into standalone analytical products (flow analytics, quality yield, rework tracking, capacity planning).

---

## 2. The Six Principles (in priority order)

When two principles conflict, the **higher-priority (lower number) principle wins**.

### Principle 1: Model once, render many
Every feature has **exactly one canonical data shape**. A screen is merely a view over that shape. One feature can have multiple distinct views chosen per client or per user.
- **Rule:** Never alter database schemas or API DTOs to fit a specific screen widget.
- **Rule:** The view a client sees is determined by a per-client configuration setting, never by code branches, separate tables, or forked endpoints.

### Principle 2: Rules live in the data layer, not in widgets
Uniqueness, ordering, required fields, state transitions, and business limits are enforced in the **backend data layer and validators**.
- **Rule:** If a rule exists only because a dropdown or UI form prevents a user from making a mistake, the moment an alternative view (or API / mobile scan / CSV import) is introduced, the rule will break.
- **Rule:** Frontends may provide validation for responsive user feedback, but the backend is the authoritative enforcer and single source of truth.

### Principle 3: Familiar surface, structured core
Meet each factory where it is today. A legacy-style screen that mirrors their old desktop software or physical paper traveler is fine, but it must **never bend the canonical schema** to achieve that familiarity.
- **Rule:** Translate messy shop-floor habits into clean canonical structures at the ingress boundary.
- **Rule:** Never store denormalized, ambiguous, or screen-coupled representations in the database.

### Principle 4: Record events, not just state
Store **what happened and when**, not only where things currently stand.
- **Rule:** Current state can always be computed or rebuilt from an append-only event stream; historical context and shop-floor reality can **never** be reconstructed from current state.
- **Rule:** Read-optimized current-state tables are permitted for fast querying, but they are downstream projections and must be strictly rebuildable from the event log.

### Principle 5: Every feature declares what it feeds
Every feature specification must explicitly document:
1. The entities it touches.
2. The domain events it emits.
3. The operational questions and metrics that data answers.
- **Rule:** Features that capture related data naturally cluster into commercial products (e.g. bottleneck detection, scrap analytics, machine utilization).
- **Rule:** Before building any feature, map its outputs to the **Feature-to-Metric Map** (§5).

### Principle 6: One way to do a common thing
Fundamental concepts have **exactly one handling pattern** across Flutter and Node.
- **Quantities & Units:** Follow `.claude/skills/units/SKILL.md` — integer base units, no floats, single formatter `QuantityText`.
- **Dates & Times:** Standard ISO-8601 UTC in storage and APIs. Separate floor occurrence (`occurred_at`) from data entry (`recorded_at`).
- **Process Stages & Routes:** Master stage catalog, ordered sequences, immutability upon release.
- **Identifiers & Barcodes:** Unified entity prefixes, symbology, and scan resolution (see `Docs/architecture/03-universal-barcode-ecosystem.md`).
- **Entity Variations & Versions:** Shared node trees and explicit version spend rules (see `Docs/architecture/09-variation-trees-and-versions.md`).

---

## 3. Worked Architectural Example: Process Routing

A route is an ordered list of process stages for a manufactured part. A 10-dropdown screen is merely one view among many to edit that route.

### Canonical Model

```
+--------------------------------------------------------------------------+
|                              Canonical Model                             |
|                                                                          |
|  +--------------------+         +---------------+                        |
|  |   process_stage    |         |     route     |                        |
|  |--------------------|         |---------------|                        |
|  | id                 |         | id            |                        |
|  | code               |         | part_id       |                        |
|  | name               |         | version       |                        |
|  | active             |         | status        |                        |
|  +---------+----------+         +-------+-------+                        |
|            |                            |                                |
|            +---------------+   +--------+                                |
|                            |   |                                         |
|                       +----+---+----+                                    |
|                       | route_step  |                                    |
|                       |-------------|                                    |
|                       | route_id    |                                    |
|                       | seq (1..n)  |                                    |
|                       | stage_id    |                                    |
|                       | notes       |                                    |
|                       +-------------+                                    |
+--------------------------------------------------------------------------+
                                     ^
                                     |
                       [ Single Ingress Validator ]
                       - seq is contiguous 1..n
                       - stage at most once (unless repeatable)
                       - versioned if route has active jobs
                                     ^
       +-----------------------------+-----------------------------+
       |                             |                             |
+--------------+              +--------------+              +--------------+
| Classic View |              |  List View   |              |Template View |
| (Dropdowns)  |              |(Drag-palette)|              | (Clone/Tweak)|
+--------------+              +--------------+              +--------------+
```

| Table | Key Fields | Purpose |
|---|---|---|
| `process_stage` | `id, code, name, is_repeatable, active` | Master catalog of stages for the factory (e.g. shearing, punching, bending, welding, powder coating, assembly, QC, packing). |
| `route` | `id, part_id, version, status` | One route per part per version; status is `draft`, `active`, or `retired`. |
| `route_step` | `route_id, seq, stage_id, notes` | The ordered sequence of steps; `seq` is strictly contiguous from 1 to $n$. |

### Rules (Enforced in Backend Data Layer)

1. **Contiguous Sequence:** `seq` runs from 1 to $n$ with no gaps and no duplicate ranks.
2. **Stage Uniqueness:** A stage appears at most once per route, unless `process_stage.is_repeatable = 1`. This moves the client's "one stage per dropdown" rule to the backend where every view inherits it.
3. **Route Immutability / Versioning:** An active route that jobs on the shop floor have already executed or are currently using is **never edited in place**. Any alteration creates a new `version` (status `draft`), keeping historical job runs linked to their original route.
4. **Single Ingress Endpoint:** Every save goes through one backend endpoint (`POST /api/routes` or `PUT /api/routes/:id/steps`) and one validator, regardless of which screen or view submitted it.

### Alternative Views on the Same Data

| View | Editing Interaction | Target Factory Persona |
|---|---|---|
| **Classic** | One dropdown per step, each listing all available stages; new steps added with a button. | First client; operators accustomed to legacy desktop ERPs. |
| **List / Canvas** | Pick stages from a sidebar palette, drag-and-drop to reorder sequence. | Modern planners; complex routes with 15+ operations. |
| **Template** | Clone the complete route of an existing similar part, tweak deviations. | Factories manufacturing families of near-identical components. |

**The Contract:** Every view converts its UI state into the exact same payload shape:
```json
{
  "part_id": 1042,
  "steps": [
    { "seq": 1, "stage_id": 12, "notes": "Shear 2mm sheet" },
    { "seq": 2, "stage_id": 15, "notes": "Bend 90 deg" },
    { "seq": 3, "stage_id": 22, "notes": "Powder coat black" }
  ]
}
```
Which view a client sees is controlled by client settings (`company_preferences.route_editor_view = 'classic' | 'list' | 'template'`), never by code branching.

---

## 4. Event Logging Standard

Every shop-floor mutation or state change writes one record to a shared, append-only `event` table.

### Event Schema

```sql
CREATE TABLE event (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  occurred_at  TEXT NOT NULL,              -- ISO-8601 UTC: when it happened on the factory floor
  recorded_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')), -- when entered into system
  entity_type  TEXT NOT NULL,              -- 'job', 'route', 'part', 'machine', 'stock_item'
  entity_id    INTEGER NOT NULL,           -- primary key of the target entity
  event_type   TEXT NOT NULL,              -- fixed vocabulary, snake_case past tense (e.g. 'stage_entered')
  payload      TEXT NOT NULL,              -- JSON object containing facts specific to this event
  actor_id     INTEGER NOT NULL,           -- user or operator id who performed/reported it
  client_id    INTEGER                     -- multi-tenant scope if applicable
);

CREATE INDEX idx_event_entity ON event(entity_type, entity_id);
CREATE INDEX idx_event_type_occurred ON event(event_type, occurred_at);
CREATE INDEX idx_event_recorded ON event(recorded_at);
```

### Event Logging Invariants

- **E1. Append-Only (Immutability):** Event rows are never updated and never deleted. An entry mistake is corrected by recording a new compensating/correcting event (e.g., `stage_entry_cancelled` or `rework_corrected`).
- **E2. Floor Time vs Entry Time:** `occurred_at` records physical floor time; `recorded_at` records database entry time. The discrepancy (`recorded_at - occurred_at`) measures operational data-entry lag.
- **E3. Single Shared Vocabulary:** Event types must come from a centralized, pre-registered vocabulary. Free-text or ad-hoc strings in `event_type` are prohibited.
- **E4. Payload Minimality:** The `payload` JSON records only the facts specific to that transition (e.g., `{ "stage_id": 12, "qty_base": 500, "machine_id": 3 }`), not a full entity dump.
- **E5. State Rebuildability:** Materialized current-state tables exist for fast query performance, but they must be completely reproducible from the event stream.

---

## 5. Feature-to-Metric Map & Product Clustering

When multiple features capture related events, that cluster forms a standalone commercial product. Always consult and update this map when designing new features or responding to client requests.

| Feature | Entities Touched | Events Emitted | Metrics Enabled | Product Cluster |
|---|---|---|---|---|
| **Process Routing** | `part`, `route` | `route_created`, `route_versioned` | Route complexity, step count distribution | **Shop-Floor Flow** |
| **Job Cards** | `job` | `job_released`, `job_closed`, `job_cancelled` | Order lead time, on-time completion rate | **Shop-Floor Flow** |
| **Stage Tracking** | `job`, `route_step` | `stage_entered`, `stage_exited` | Cycle time per stage, WIP aging, bottlenecks | **Shop-Floor Flow** |
| **Rework Entry** | `job`, `route_step` | `rework_logged`, `rework_resolved` | Rework rate by stage, operator & part | **Quality** |
| **QC Inspection** | `job`, `inspection` | `qc_passed`, `qc_failed` | First-pass yield, defect Pareto distribution | **Quality** |
| **Machine Assignment** | `job`, `machine` | `machine_assigned`, `machine_released` | Machine utilization, idle/setup duration | **Capacity** |
| **Stock Issue & Scrap**| `stock_item`, `job` | `stock_issued`, `scrap_logged` | Material yield per part, scrap variance | **Material Yield** |

### The Candidate Product Clusters

1. **Shop-Floor Flow:** Pinpoints where jobs queue, actual cycle times vs standards, and chronic part delays.
2. **Quality:** Isolates where rework originates, which stages/tools fail first time, and vendor defect correlation.
3. **Capacity:** Highlights constraint machines, setup-to-run ratios, and starvation/blocking patterns.
4. **Material Yield:** Measures actual material consumption and scrap against bill-of-materials standards.

### Client Insight Decision Rule

When a client asks for a new report, dashboard, or insight:
1. **Check the Map First:** Can the metric be computed from existing events? If yes, build the analytical projection/query without touching operational tables.
2. **If Events are Missing:** Identify the specific feature that captures that floor transition and update it to emit the required canonical event into the shared log.

---

## 6. Pre-Implementation Checklist

Run this checklist before writing any schema migration, backend endpoint, or Flutter screen:

- [ ] **Data Shape vs View:** Is this request a new canonical data shape, or an alternative view of an existing one? If it is a view, **do not change the core schema**.
- [ ] **Backend Rule Placement:** Are all required business constraints (uniqueness, sequences, limits, validity) enforced in the backend validator, rather than relying on frontend widgets?
- [ ] **Event Emission:** What floor transition does this feature represent? Does it emit an append-only event into `event`? Is the `event_type` registered in the shared vocabulary?
- [ ] **Metric Mapping:** Which row does this feature add or update in the Feature-to-Metric Map? Which product cluster does it feed?
- [ ] **Multi-Client Adaptation:** Is the client-specific behavior configured via tenant/client preferences rather than a hardcoded code branch?
- [ ] **Consistency Patterns:** Does the implementation strictly follow the single house patterns for:
  - Quantities (integer base units via `units` skill)?
  - Dates (`occurred_at` floor time vs `recorded_at` entry time)?
  - Stages and Routes (canonical master + contiguous steps)?
  - Identifiers and Barcodes (standardized symbology and resolver)?
