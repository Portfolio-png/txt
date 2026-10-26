# Paper — Design Philosophy

Oct 4, 2026 · @Funnel

## Why this exists

Paper will serve factories that think very differently, so the data model must stay the same while the screens adapt to each client.

Our first client wants the classic pattern: one dropdown per process stage, each listing every stage, one pick per box. Later clients will expect faster, more visual tools and will ask questions of their data. If we build each client's preferred screen straight into the schema, every new client means a rewrite.

This doc sets the rules that prevent that. It also sets up a second goal: groups of features that capture related data can later be packaged as products in their own right, such as flow analytics or rework tracking.

## Principles

Six rules, in priority order. When two conflict, the higher one wins.

1. **Model once, render many.** Every feature has one canonical data shape. A screen is a view of that shape. One feature can have several views, chosen per client or per user.
2. **Rules live in the data layer, not in widgets.** Uniqueness, ordering, required fields and limits are enforced by the backend. If a rule exists only because a dropdown prevents a mistake, a second view will break it.
3. **Familiar surface, structured core.** Meet each factory where it is today. A legacy-style screen is fine, but it must never bend the schema to match it.
4. **Record events, not just state.** Store what happened and when, not only where things stand now. Current state can always be rebuilt from events; history can never be rebuilt from current state.
5. **Every feature declares what it feeds.** A feature spec lists the entities it touches, the events it emits and the questions that data could answer. This is how features later cluster into products.
6. **One way to do a common thing.** Quantities, dates, stages and IDs each have exactly one handling pattern across Flutter and Node. The units skill is the model for this.

## Worked example: process routing

A route is an ordered list of process stages for a part; the 10-dropdown screen is just one way to edit it.

Whichever screen a client uses, the save goes through the same validator and lands in the same tables and event log.

### Canonical model

| Table | Key fields | Purpose |
| --- | --- | --- |
| `process_stage` | id, code, name, active | Master list of stages for this factory (e.g. shearing, punching, bending, welding, powder coating, assembly, QC, packing) |
| `route` | id, part_id, version, status | One route per part per version; status is draft, active or retired |
| `route_step` | route_id, seq, stage_id, notes | The ordered steps; `seq` runs 1 to n |

### Rules, enforced in the backend

- `seq` is contiguous from 1, with no gaps.
- A stage appears at most once per route, unless that stage is flagged as repeatable. This is the client's "one stage per dropdown" rule, moved to where every view inherits it.
- An active route that jobs have already used is never edited in place. Changes create a new version, so old jobs keep their history.
- Every save goes through one endpoint and one validator, whichever screen sent it.

### Views on the same data

| View | How the user edits | Suits |
| --- | --- | --- |
| Classic | One dropdown per step, each listing all stages; steps added with a button | The first client; operators used to older desktop software |
| List | Pick stages from a palette, drag to reorder | Faster planners; long routes |
| Template | Copy the route of a similar part, then adjust | Factories with many near-identical parts |

Each view produces the same payload: a list of stage ids in order. The view a client sees is a per-client setting, not a code branch.

## Event logging standard

Every change that matters on the shop floor writes one row to a shared, append-only `event` table.

| Field | Example | Note |
| --- | --- | --- |
| id | auto | Never reused |
| occurred_at | 2026-10-04 10:14 | When it happened on the floor, not when it was typed |
| recorded_at | 2026-10-04 10:31 | When it was entered; the gap shows data-entry lag |
| entity_type | job | job, route, part, machine, stock_item |
| entity_id | 42 | |
| event_type | stage_entered | A fixed vocabulary per entity, defined in one place |
| payload | stage_id, qty, machine_id | Only the facts specific to this event |
| actor | operator or user id | Who did or reported it |

Rules:

- Events are never updated or deleted. A mistake is fixed with a correcting event.
- Screens may read current-state tables for speed, but those tables must be rebuildable from events.
- A new event type is added to the shared vocabulary first, then used. No free-text event names.

## Feature-to-metric map

When several features feed the same metrics, that cluster is a candidate product. Keep one row per feature and review the map whenever a client shares a new insight.

| Feature | Entities | Events emitted | Metrics enabled | Cluster |
| --- | --- | --- | --- | --- |
| Process routing | part, route | route_created, route_versioned | Route complexity, steps per part | Shop-floor flow |
| Job cards | job | job_released, job_closed | Lead time, on-time completion | Shop-floor flow |
| Stage tracking | job, route_step | stage_entered, stage_exited | Cycle time per stage, WIP ageing, bottlenecks | Shop-floor flow |
| Rework entry | job | rework_logged | Rework rate by stage and part | Quality |
| QC inspection | job | qc_passed, qc_failed | First-pass yield | Quality |
| Machine assignment | job, machine | machine_assigned, machine_released | Machine utilisation, idle time | Capacity |
| Stock issue | stock_item, job | stock_issued, scrap_logged | Material per part, scrap rate | Material yield |
| Developed For | part, client, sub_contractor | none — a part attribute, with field history through `entity_activity_log` | Parts developed per client, quotation value per client, quote-to-first-order lag, share of in-house vs client-driven development | Commercial |
| Development margin | part, client | none — two part attributes, with field history through `entity_activity_log` | Margin per development job, margin by client, share of jobs quoted below cost, jobs quoted but never costed | Commercial |
| Deal contacts | client, party_contact, part | none — people are master data and the ticks a part attribute; field history through `entity_activity_log` (`party_contacts` rows, item diffs) | Deals per person, who at a client brings work, parts dealt with someone since archived (whose relationship to re-establish) | Commercial |
| Die sheet | die, part | none — a tool attribute; `item_dies` records which part it makes | Dies made per month and per maker, PO-to-date-in lead time, dies per part, where a die is when it is wanted | Tooling |
| Machine sheet | machine, part | none — an asset attribute; `item_machines` records which parts it runs | Machines per type, rated tonnage available, strokes/min by machine, running hours between services, which parts a press is the only home for | Capacity |

Candidate products from these clusters:

- **Shop-floor flow:** where jobs wait, how long each stage really takes, which parts are always late.
- **Quality:** where rework starts, which parts and stages fail first time.
- **Capacity:** which machines are the constraint, and when — and now what they are: how much tonnage the plant actually has, how fast each press runs, and which part has only one machine that can make it.
- **Material yield:** scrap and consumption per part, against the standard.
- **Commercial:** which clients the catalogue was actually built for, what was quoted, and how much of that turned into orders. The one cluster so far whose rows are part attributes rather than floor events — a part being developed for someone is a fact about the part, not a transition it goes through.
- **Tooling:** how long a die takes to arrive after it is ordered, who makes the ones that last, and which part is waiting on a tool that is not in its rack.

When a client asks for a new insight, check the map first. Either the events already exist and the insight can be packaged, or the map shows exactly which feature needs to start emitting what.

## Checklist for every feature or client request

Run this before building anything new, including a client's screen request.

- [ ] Is this a new data shape, or a new view of an existing one? If a view, no schema change.
- [ ] Which rules does it need, and are they in the backend validator?
- [ ] Which events does it emit? Are they in the shared vocabulary?
- [ ] Which row does it add to the feature-to-metric map, and which cluster does it join?
- [ ] Is the client-specific part a per-client setting rather than a code branch?
- [ ] Does it follow the one-way patterns for units, dates, stages and IDs?
