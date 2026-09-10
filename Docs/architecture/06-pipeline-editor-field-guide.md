# Pipeline Editor Field Guide — Prior Art for the Node Panel Rework

> Status: RESEARCH, not a plan. Compiled 2026-09-03 from a GitHub + web survey,
> at the requester's request, to supply vocabulary and reference implementations
> for **rework #2** in `02-bathroom-thoughts-2026-08-24.md` (the pipeline node
> configuration panel).
>
> A styled, browsable version of this same content sits beside it as
> `06-pipeline-editor-field-guide.html` — open it in any browser, no login and
> no network needed (webfonts degrade to declared fallbacks offline).
>
> Star counts and activity verified against the GitHub API on **2026-09-03**.

---

## 1. Why nothing turned up when you searched

"Pipeline node panel clutter" is **three different solved problems wearing one
coat**. No single project solves all three, which is exactly why no single
search phrase found anything.

| | Problem | Status | Is it your complaint? |
|---|---|---|---|
| **A** | **The canvas** — nodes, ports, links, pan/zoom, layout | Fully commoditised; dozens of libraries, one native Flutter | No — yours works |
| **B** | **The inspector** — the panel that edits the selected node | Solved thoroughly by the BPMN tooling world, almost nowhere else | **Yes.** Clutter and save-state both live here |
| **C** | **The node taxonomy** — what *kinds* of node exist and what each may carry | Settled vocabulary in manufacturing execution systems | **Yes.** Scrap-vs-rejection is a typing question, not a form-field question |

---

## 2. The vocabulary you were missing

These are the terms that make the rest of the internet searchable on this topic.

| Term | From | What it gives you |
|---|---|---|
| **Element template** | Camunda Modeler | A named node *kind* that declares which fields it exposes and with what defaults. The panel renders the template, not every field that exists. **This is the whole clutter fix.** |
| **Conditional property** | Camunda Modeler | A field that appears only when another field has a given value. Pick "Scrap node" and the scrap group appears; pick "Rejection node" and it doesn't. |
| **Group · Entry · ListGroup** | `bpmn-io/properties-panel` | The three structural units of an inspector. A panel is a list of declared Groups, each a list of Entries — not a hand-assembled column of widgets, which is what yours is now. |
| **Disposition** | MES routing | The industry's answer to your exact question. A non-conforming unit gets a disposition of **scrap**, **rework**, or **use-as-is**. Your "rejection node" is rework; your "scrap node" is scrap. **Three values, not two.** |
| **Operation yield** | MES routing | Expected pass-through percentage on a step. Turns the scrap branch into a number that lives on the node and can be planned against, rather than a destination picked at reconcile time. |
| **Rework loop** | MES routing | A rejection route back into an earlier step, with declared entrance/exit criteria and a **repeat limit**. The limit is the part you don't have — without it a part cycles forever and is counted twice. |
| **Boundary error event** | BPMN 2.0 | The graph-level notation for "what leaves the happy path here". Draws scrap and rejection as edges off a step rather than as fields buried inside it. |
| **Sink node** | Dataflow graphs | A terminal node that consumes and never emits. Scrap destinations are sinks; naming them so makes it obvious why they carry no output item or machine. |

---

## 3. The one idea worth stealing: element templates

Your panel today asks every question of every node and then hides some of them
with `if (_isAssemblyStep)` and `if (!_isOutputNode)` branches written by hand in
the widget tree ([pipeline_builder_screen.dart](../../lib/features/production/screens/pipeline_builder_screen.dart)).

Camunda hit the same wall and **inverted it**: a node points at a *template*, and
the template declares its fields — type, label, default, and the condition under
which it shows at all. The panel becomes a renderer.

### Why this collapses two of your four complaints at once

"Is this a rejection node or a scrap node?" stops being a new dropdown you bolt
on. It becomes **which template this node uses** — and the template already knows
that a scrap node needs a destination group and a material, while a rejection
node needs a repeat limit and a return step. Ask the question once, at the top,
and the rest of the panel follows from the answer.

It also gives the scrap-versus-rejection distinction somewhere to live that
**survives to reconcile time**, which the current single untyped `scrapItems`
list does not — see the `ponytail:` note at
[process_node.dart:67-69](../../lib/features/production_pipelines/domain/process_node.dart#L67-L69).

---

## 4. Prior art

### 4.1 Flutter — things you could actually build on

| Repo | Stars | Notes |
|---|---|---|
| **[vyuh-tech/vyuh_node_flow](https://github.com/vyuh-tech/vyuh_node_flow)** | 197★ · Dart · MIT · active | **START HERE.** The only live Flutter node editor of any maturity. React Flow's model ported properly: typed node data via generics, ports, connection styles, minimap, read-only viewer mode, JSON serialisation, extension architecture. Its own demo ships a **manufacturing** example workflow. Level-of-detail rendering keeps it usable at real pipeline size. [Live demo](https://flow.demo.vyuh.tech) |
| [WilliamKarolDiCioccio/fl_nodes](https://github.com/WilliamKarolDiCioccio/fl_nodes) | 193★ · Dart · MIT | **ARCHIVED 2026-08-31 — read-only. Do not build on it.** Was the other Flutter option. Still worth reading for how it structured node definitions; treat as a dead reference, not a dependency. |

### 4.2 The inspector — your actual problem

| Repo | Stars | Notes |
|---|---|---|
| **[bpmn-io/properties-panel](https://github.com/bpmn-io/properties-panel)** | 43★ · JS · MIT | **The closest thing to a solved version of your panel.** Small enough to read in an afternoon. The component vocabulary is the payload: `Group`, `ListGroup`, `ListItem`, `Header`, `Placeholder`, plus entries `TextField`, `TextArea`, `NumberField`, `Select`, `Checkbox`, `CheckboxGroup`, `ToggleSwitch`, `Collapsible`, `Description`, `Tooltip`, `List`, `JsonEditor`. That set covers every field in your Step Properties panel. |
| [bpmn-io/bpmn-js-properties-panel](https://github.com/bpmn-io/bpmn-js-properties-panel) | 337★ · JS · active | The reference implementation on top of that library — how a real domain maps element types onto declared groups. What "decluttered" looks like after eight years of iteration. |
| **[camunda/camunda-modeler](https://github.com/camunda/camunda-modeler)** | 1.7k★ · desktop app | **Where element templates ship.** Download it, model a two-step process, watch the properties panel change shape as you switch element types. |
| [bpmn-io/bpmn-js-example-react-properties-panel](https://github.com/bpmn-io/bpmn-js-example-react-properties-panel) | 53★ · example | Deliberately minimal "build your own panel" example. Clearest single file for the declared-groups pattern without BPMN domain on top. |
| [n8n-io/n8n](https://github.com/n8n-io/n8n) | 203k★ · TS · active | Node parameter panels at enormous scale — 400+ node types each declaring parameters with display conditions. **Look specifically at save state:** the panel commits on change and the canvas node shows the dirty marker. |
| [node-red/node-red](https://github.com/node-red/node-red) | 23.6k★ · JS · active | The *other* answer to save state: explicit modal edit dialog with Cancel/Done, plus a badge on the node for undeployed changes. Separates "edited" from "deployed" visually — exactly the distinction you need between a node edit and a pipeline save. |

### 4.3 The canvas — the genre, for reference

| Repo | Stars | Notes |
|---|---|---|
| **[xyflow/awesome-node-based-uis](https://github.com/xyflow/awesome-node-based-uis)** | 3.7k★ · list | **This is the search result you were looking for and couldn't phrase.** Curated index of node-based UI libraries across every language, plus an **Applications** section cataloguing ~50 shipped products — Retool Workflows, Stately, ComfyUI, Power Automate, customer.io, Benthos Studio, Tracardi. **Browse the applications, not the libraries.** |
| [xyflow/xyflow](https://github.com/xyflow/xyflow) | 38.2k★ · TS · active | React Flow — defined the current conventions, and what `vyuh_node_flow` is modelled on. Read its docs for the naming (handles, edges, node types) everyone else adopted. |
| [retejs/rete](https://github.com/retejs/rete) | 12.2k★ · TS · active | Stronger opinions than React Flow about node **schemas** and validation — closer to your case, where a node's inputs/outputs must be type-checked against the items flowing through. |
| [comfyanonymous/ComfyUI](https://github.com/comfyanonymous/ComfyUI) | 131k★ · Python | Most-used node graph UI in the world, and instructive **as a warning**: it puts every property *inside* the node body rather than in an inspector. Open a large graph and you feel precisely the clutter problem you're trying to avoid. |

Other genre libraries worth knowing by name: `baklavajs` (2.1k, Vue),
`litegraph.js`, `thedmd/imgui-node-editor` (4.5k, C++), `paceholder/nodeeditor`
(3.7k, Qt), `Siccity/xNode` (3.7k, Unity), `nocode-js/sequential-workflow-designer` (1.5k).

### 4.4 The domain — manufacturing routing and MES

| Repo | Stars | Notes |
|---|---|---|
| **[jukbot/smart-industry](https://github.com/jukbot/smart-industry)** | 441★ · MES | **Closest domain fit.** An open MES for **job-shop** manufacturers — which is what Sarvadnya is. Job shop means routing varies per order rather than per product, the exact assumption behind assigning a pipeline to an order. Read its routing and operation models. |
| **[frappe/erpnext](https://github.com/frappe/erpnext)** | 38.8k★ · Python · active | Most complete open manufacturing data model available. **Read only three doctypes: Routing, Operation, BOM.** Its scrap-item handling on a BOM is a direct precedent for the split you want, and it already separates scrap items from process loss. |
| [ricefishtech/industry4.0-mes](https://github.com/ricefishtech/industry4.0-mes) | 508★ · Java | Conventional MES schema; useful as a second opinion on table naming for operations, work orders and scrap records. Docs largely Chinese; schema reads fine regardless. |
| [metaxk-company/free-mes](https://github.com/metaxk-company/free-mes) | 410★ · PLpgSQL | Another MES schema for cross-reference. |

### 4.5 Factory games — for the interaction feel

| Repo | Stars | Notes |
|---|---|---|
| [tobspr-games/shapez.io](https://github.com/tobspr-games/shapez.io) | 6.9k★ · JS · MIT | You mentioned factory simulators — this is the open one worth an hour. Its lesson is **legibility at a glance**: every building announces its function through shape and colour alone, so a large graph stays readable without opening anything. Your stage nodes currently do not. |
| [satisfactory-factories/application](https://github.com/satisfactory-factories/application) | 52★ · TS | Production-chain planner with dependency management. Small and readable. Its treatment of **by-products** — outputs you didn't ask for but must route somewhere — is structurally the same problem as scrap. |
| [JamboChen/endfield-calc](https://github.com/JamboChen/endfield-calc) | 114★ · TS | Production chain calculator; another small readable take on the same maths. |

---

## 5. What to open first

In this order, and **stop when you can describe what you want in your own
words** — that is the whole purpose of this exercise.

1. **Camunda Modeler, twenty minutes, hands on.** Model any two-step process and
   switch element types while watching the right-hand panel. Fastest route from
   "I can picture it" to "I can name it".
2. **The Applications section of `awesome-node-based-uis`.** Fifty shipped
   products. Skim for screenshots. You'll find three or four whose inspector is
   what you had in mind — then you can point instead of describe.
3. **`vyuh_node_flow`'s live demo, on the manufacturing example.** The only one
   here that is Flutter and could become a dependency rather than an
   inspiration. Judge whether its canvas beats what you already have.
4. **ERPNext's Routing, Operation and BOM doctypes.** Read only these three.
   They'll tell you whether scrap belongs on the operation, on the BOM, or on
   both — a question your current model answers by accident.

### One thing that needs no research

Your fourth complaint — Save shows a toast but leaves you on the builder — is a
single missing call. `_deletePipeline` already calls `onBack?.call()`;
`_saveAndNotify` never learned to. Not a design question, and it shouldn't wait
for any of the above. Note there are **two** save paths (`_savePipeline` and
`_saveAndNotify`) and both need the same treatment or the behaviour stays
inconsistent.

---

## Sources

- GitHub Search API, queried 2026-09-03 (star counts, languages, `pushed_at`, archive status)
- [Camunda — About element templates](https://docs.camunda.io/docs/components/modeler/desktop-modeler/element-templates/about-templates/)
- [Camunda — Defining templates](https://docs.camunda.io/docs/components/modeler/desktop-modeler/element-templates/defining-templates/)
- [MES routing & operation sequencing](https://sgsystemsglobal.com/glossary/routing-and-operation-sequencing/)
- [Rework limits in MES](https://devblog.criticalmanufacturing.com/blog/20251028_rework_limit/)
- [Handling scrap, yield loss and rework](https://us.fitgap.com/stack-guides/handling-scrap-yield-loss-and-rework-so-variable-costs-reflect-true-throughput)
- [Process visualization of MES data (arXiv 2201.06465)](https://arxiv.org/pdf/2201.06465)
