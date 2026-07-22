# Feature-Permission Map — Paper ERP (condensed)

Every distinct, individually-gateable user action (backend routes + desktop & mobile triggers) — the **decision surface** for which actions deserve their own permission toggle. Grouped by module; base CRUD stated once, then the *finer actions currently hiding under it*.

**Legend:** ✅ wired · 🟡 partial / mismatch / role-only · 🔴 stub · *(pr)* per-record grant also honored.
**Model:** one central middleware maps each `/api` request → `<module>.<op>` (GET=View, POST=Create, PUT/PATCH=Update, DELETE=Delete) across **14 modules** (orders, inventory, challans, production, jobs, action_center, people, clients, vendors, items, units, machines, dies, pipelines). Legacy `config.read/write` guards are **no-ops**; a few **capabilities** gate cross-cutting actions. **Net: nearly every action collapses onto 4 coarse keys/module — the splits below are what those keys hide.** Unless noted, a proposed key is enforced today by its module's own op.

## Governance gaps to decide
- `users.manage_permissions` also gates hard-**deleting a user** — no dedicated `users.delete`. 🟡
- `POST /api/delete-requests` is `requireAuth`-only — **any** authed user can file a delete request (UI-gated only). 🟡
- Audit CSV export isn't role-scoped — a scoped admin gets the full log; propose `audit.export`. 🟡
- Link/unlink employee login is **role-only**, no capability key. 🟡
- Path→module quirks: an order's challans read via `/api/orders/:id/...` is gated by `orders.read` (not `challans.read`); PO/report/asset **downloads** are POSTs → gated as `*.create`. 🟡
- Whole subsystems are effectively **ungated** (fall to the legacy write gate = admin/write-holders only, no granular key): **Payroll, Freelancer Jobs, B2B Portal, Production runs/stages, Assets, Favorites, Search-logging.** 🟡/🔴

## Capabilities (cross-cutting, not module-CRUD)

| Capability | Controls | Today |
|---|---|---|
| `login.desktop` / `login.mobile` | Sign-in on desktop (email+pass) / mobile (4-digit PIN) | ✅ |
| `users.read` | View account directory | ✅ |
| `users.create_user` | Create staff + seed an employee login (also needs admin role) | ✅ |
| `users.create_admin` | Create an admin (super_admin only) | ✅ |
| `users.update_status` | Activate / deactivate a login | ✅ |
| `users.reset_password` | Reset another user's password | ✅ |
| `users.manage_permissions` | **All** RBAC editing (grid, capabilities, presets, per-record) **+ overloaded: delete user** | ✅ / 🟡 |
| `sessions.manage` | View / revoke another user's sessions | ✅ |
| `audit.read` | Read audit trail, security events, per-person Track | ✅ |
| `delete_requests.review` | List / approve (hard-delete) / reject / export delete requests | ✅ |
| `inventory.request_delete` | File an inventory delete request (server route is auth-only) | 🟡 |
| `challans.reconcile` | Reconcile in-use challans → inventory + complete order | ✅ |
| *proposed* `users.delete` · `audit.export` · `users.link_login` / `users.unlink_login` | Dedicated user-delete · role-scoped audit export · employee login link/unlink | — / 🟡 |

## Actions by module

### Orders — `orders`
- **CRUD:** view list/detail/activity/status-history/material-reqs → `.read`; create → `.create`; update (lines/dates/client/PO/qty/price/tax) → `.update`; delete (recovers WIP) → `.delete`.
- **Splits:** lifecycle status → `orders.status_change`; item/variation history → `orders.item_history.read`; production report view/export → `orders.report.{view,export}`; order's pipeline runs → `orders.production.read`.
- **PO docs:** upload/complete → `orders.po_upload`; link → `orders.po_link`; list → `orders.po_document.read`; download → `orders.po_download` 🟡(read gated as create).
- **Order↔challan:** view order's challans → `orders.challans.read` 🟡(gated by orders.read, `/orders` path); "Create challan" button → `challans.create`.

### Delivery Challans — `challans`
- **CRUD:** view list/detail (all types; order-scoped list 🟡 gated by `orders.read`) → `.read`; create draft delivery/reception/internal → `.create`; update draft (header+lines) → `.update`; delete draft → `.delete`.
- **Splits:** issue → `challans.issue`; cancel (+options) → `challans.cancel`; assign report group → `challans.assign_report_group`; print/preview → `challans.print`; asset upload → `challans.asset.upload`; **reconcile in-use → `challans.reconcile`** (dedicated capability ✅).
- **Templates:** view+scans → `challan_templates.read`; create/update/delete → `.create/.update/.delete`; file+stamp upload → `.upload`; test-print → `.test_print`.

### Invoices · Reconciliation · Reports — (module `challans`)
- **Invoices:** list/detail → `invoices.read`; PDF → `invoices.print`; create/update/delete → `.create/.update/.delete`; change status (issued/paid) → `invoices.change_status`.
- **Reconciliation:** report → `reconciliation.read`; conversion overrides view/save → `reconciliation.overrides.{read,update}`; waste-audit → `reconciliation.waste_audit.read`.
- **Reports:** client statement → `reports.client_statement` 🟡(read gated as create); export/print → `reports.client_statement.print`.

### Inventory — `inventory`
- **Views:** stock overview → `inventory.stock.read`; health KPI → `.health.read`; material list/single/detail → `.material.read`; activity/trace → `.material.activity.read`; barcode lookup → `.barcode.lookup`.
- **Material writes:** create parent/child → `.material.create`; edit → `.material.update`; group-config/governance → `.material.group_config`; delete → `.material.delete`; **request delete → `inventory.request_delete`** 🟡(route auth-only); link/unlink → `.material.{link,unlink}`; scan/scan-reset → `.material.{scan,scan_reset}`.
- **Movements/Sets:** manual movement → `inventory.movement.create` (needs create+update); sets read/create/update/delete → `inventory.set.{read,create,update,delete}`.

### Items — `items`
- **CRUD:** list/detail/usage → `.read`; create/update/delete → `.create/.update/.delete`. *(pr on detail/update/delete)*
- **Bundled in saveItem (worth splitting):** short-code → `items.short_code.set`; reassign group → `items.group.reassign`; variation nodes → `items.variation.manage`; units+conversions → `items.unit.manage`; available-for-purchase → `items.available_for_purchase.toggle`.
- **Assets** 🟡(shared route, legacy write gate): upload → `items.asset.upload`; list → `.asset.list` (✓ read); set-primary/delete/download → `.asset.{set_primary,delete,download}`.
- **Track tab** → `items.track.read` 🟡(any authed).

### Groups (module `items`) · Units — `units`
- **Groups:** view/members/schema → `groups.{read,members.read,schema.read}`; create (hierarchical/combination) → `groups.create`; update/re-parent → `groups.update`; bulk-assign variants → `groups.members.assign`; delete → `groups.delete`. *(all via `items.*`)*
- **Units:** CRUD → `units.{read,create,update,delete}`.

### Clients · Vendors · Sub-contractors · Portal · Company Profile
- **Clients** `clients`: CRUD → `clients.{read,create,update,delete}` *(pr on detail/update/delete)*.
- **Sub-contractors** (module `clients`): read/create/update/delete → `clients.subcontractors.*`.
- **Vendors** `vendors`: CRUD → `vendors.{read,create,update,delete}` *(pr)*; purchase-history → `.read`.
- **Client portal:** set credentials → `clients.portal.manage_credentials`; view catalog → `.portal.read_catalog`; replace catalog → `.portal.manage_catalog` *(no dedicated guard; via `clients.*`)*.
- **Company profile:** view/edit → `clients.company_profile.{read,update}` 🟡(unmapped path — GET any-authed, edit legacy write gate).

### People — `people` · Payroll · Freelancer · B2B Portal
- **Employees:** CRUD → `people.employee.{read,create,update,delete}` (edit re-derives login PIN from DOB).
- **Departments:** CRUD → `people.department.*` (delete cascade-trashes employees).
- **Logins:** create employee login (+seed PIN) → `users.create_user` (+role); link/unlink → `users.{link_login,unlink_login}` 🟡(role-only, no capability); PIN rotate → side-effect of `people.update`.
- **Payroll** 🟡/🔴(all ungated → legacy write gate): components read/create → `payroll.component.*`; salary read/upsert → `payroll.salary.*`; runs read/create/finalize/export → `payroll.run.{read,create,finalize,export}`.
- **Freelancer jobs** 🟡(ungated): read/assign/create/update/delete → `people.freelancer_job.*`; portal-token read → `people.freelancer_portal.read` 🔴.
- **B2B portal** 🔴(mock/ungated): login/catalog/cart/order → `portal.{auth.login,catalog.read,cart.update,order.create}`.

### Pipelines — `pipelines` · Production — `production`
- **Pipeline templates:** view/create/update/delete → `pipelines.template.*` (✅ on `/api`; 🟡 legacy `/templates` route ungated).
- **Production runs** 🟡(most via legacy `config.write`, ungated): list/monitor → `production.run.read` (✅ completed); start → `.run.start`; advance/complete stage → `.run.advance`; delete → `.run.delete`; stage-input add/update/remove → `.run.stage_input.*`; stage reconcile (auto leftover challan) → `.run.reconcile_stage`; batches → `.run.batches.update`.
- **Scrap:** log → `production.scrap.create` 🟡; view → `.scrap.read`. **Order report** → `orders.read`. **Telemetry ingest** → `production.telemetry.ingest` 🔴(no inbound route).

### Machines — `machines` · Dies — `dies`
- **Both:** view list/detail → `.read` *(pr)*; create/duplicate → `.create`; **update → gated as `.create`** 🟡(POST upsert); delete → `.delete` *(pr)*; assets list/upload → `.assets.{read,upload}`.
- **Machine telemetry view** → `production.read` (cross-module).

### Accounts & Permissions
- **Self:** profile/session read, logout/revoke, change password, clear-data → `self.*` *(any authed; password + clear-data allow-listed in write gate)*.
- **Users** (capabilities): view → `users.read`; create staff/admin → `users.create_user` / `create_admin`; reset pw → `users.reset_password`; activate/deactivate → `users.update_status`; **delete user → `users.manage_permissions`** 🟡(overloaded → propose `users.delete`).
- **Sessions:** view/revoke others → `sessions.manage`.
- **Presets & permissions** (all under `users.manage_permissions`): descriptors read; preset create/update/delete; assign presets to a user; edit CRUD-grid + capability overrides; per-record grants read/set; record-option search.

### Action Center — `action_center`
- **Delete requests** (capability `delete_requests.review`): view / approve (hard-deletes target) / reject / export; **create request → any authed** 🟡.
- **Trash:** view → `.read`; restore / revert broken-ref → `.create`.
- **Issues:** view broken refs → `.read`; resolve → client-side navigation (any authed).

### Track (Audit)
- Per-record activity feed → `audit.read` 🟡(currently **ungated** per-record); per-person / global / security events → `audit.read`; export events CSV → `audit.export` 🟡(= `audit.read` today, not role-scoped).

### Cross-cutting
- **Search:** results/history → `inventory.read`; record query/click → `search.{history.write,click.log}` (legacy write gate).
- **Favorites:** list/add/remove → `favorites.{read,add,remove}` (mostly ungated).
- **Assets:** upload/read-url/set-primary/delete/delete-s3 → `assets.*` (legacy write gate; read gated as write).
- **Barcode lookup** → `inventory.read`.
- **Mobile relays** (socket, no persistence): staged/removed-item, inventory-lock, challan-ack broadcasts → `mobile.*`; scan session + dock-health → local UI (any authed).
