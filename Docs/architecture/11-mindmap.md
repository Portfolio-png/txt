# 11 · Backend mind map

One map of the backend, updated with every change. It reads from the business
down to the code: each module breaks into what the business needs from it, the
API it exposes, the handlers that serve it, the service functions behind those,
the operations it publishes at the kernel desk, the ports it still shares with
other modules, the tables it owns and the tests that
pin it.

Nodes touched by the latest change carry **⟳**. Modules that have left
`server.js` say `evacuated`; the rest say `legacy`. Only the modules that have
been through a change are expanded; the others show what the registry knows.

Source of truth for module identity is `backend/kernel/registry.js`; this map
is what a person reads first, the registry is what the server reads.

## Layers, top to bottom

| Layer | Question it answers | Where it lives |
|---|---|---|
| Business rules | What must always be true? | service functions, guards |
| API surface | What can a client ask? | `modules/<name>/routes.js` |
| Orchestration | Which steps run for one request? | route handlers, `register<Name>Routes(ctx)` |
| Services | What are the reusable operations? | `modules/<name>/service.js` |
| Operations | What can be asked by name, from a terminal, a route or another module? | `modules/<name>/operations.js`, served by `kernel/desk.js` |
| Ports | What may another module ask of this one? (modules not yet at the desk) | `modules/<name>/ports.js` |
| Data | What is stored? | tables in `registry.js` |
| Tests | What pins the behaviour? | `backend/test/*.test.js` |

## The map

```mermaid
mindmap
  root((Paper backend))
    Latest change
      c100["⟳ Change 100: a set's name is built from its items until typed (Create/Edit Set)"]
    Wire ⟳
      w1["wire-budget.test.js: named request sequences against a budget of requests and compressed bytes; UPDATE_WIRE_BUDGETS=1 prints the figures"]
        w1a["sign_in 21 calls 57 KB, orders list 7.8 KB, items list 26.7 KB, inventory 4 calls, replica hydration 14 calls 60 KB (2026-11-19)"]
        w1b["pending until their step: sign_in and inventory_overview (step 3), replica_hydration (step 5)"]
      w2["helpers/sized-workspace.js: 300 parts, 250 lines, 150 challans, 120 materials, 40 clients, 60 dies, 25 machines through the API"]
      w4["start-up: inventory 3 reads together then health; units 2 and action centre 2 overlap; a refresh during a refresh joins one follow-up"]
      w5["phone: providers refresh once per sign-in from _AuthGate (keyed on the user when the demo build has no token), not in every ProxyProvider update, not on tab mount"]
      w6["B39: item editor set buttons keep their guard until the card re-reads its sets"]
      w7["GET /api/inventory/overview: materials, stock, sets, tiles; ETag; ?materials=0 when the replica has them; healthError instead of failing"]
        w7a["InventoryOverviewReader beside InventoryRepository: API and local-first implement it, fakes need not; the provider asks once when it can"]
        w7b["sign_in 18 requests 53.5 KB and inventory_overview 1 request now assert; the N+1s inside stock and sets left: in-process, no bytes"]
      w8["items list: node createdAt, updatedAt, itemId, position, isArchived dropped; 26.7 to 21.8 KB; list row == detail row less those"]
        w8a["B42 open: saves send back the whole list object, so any other field dropped from the list is erased; six masters ~15 KB total, not split"]
      w9["GET /api/replica/bootstrap: head first, then the 13 list endpoints over loopback with the caller's token; missing vs refused"]
        w9a["ReplicaCatchUp: no cursor = bootstrap (or head then lists 4 at a time); cursor = paged /api/changes; below oldestAvailable = fresh copy"]
        w9b["B41: the cursor never left 0, every launch re-downloaded 13 lists; now head recorded, live SSE ids carried, held during catch-up"]
        w9c["B40: the list fill now mirrors item variation nodes"]
      w10["B43: isHydrated is false while catchUp runs, so a launch reads the network until the replay is in"]
      w11["local-first decorators: clients, vendors, units, groups (no covers), machines, dies, departments (subclass); server order kept, json_extract for createdAt"]
        w11a["ReplicaFreshness: a table is behind from a live event or a local write until a drain that started after it applies it; behind = read the network"]
        w11b["all eleven decorators mark what their writes touch; a challan write marks challans, order lines, materials"]
        w11c["not done: stock positions in the replica (overview is ETag'd), the offline badge (needs a UI pass); usageCount can lag"]
      w12["phone: one ConditionalCacheClient per connection, namespaced per user in _AuthGate; MyApp takes cacheDirectory for tests"]
        w12a["not done: the phone replica and offline state, no device to run them on here"]
      w13["extraction triggers: measured scaling, demanded cadence, a named failure, separate ownership; precondition: no transactional operations (27 today)"]
      w14["step 8 dropped: 041 triggers announce order lines live and the SQL takes ms; a projection would only be a drift risk"]
      w15["B42 fixed: ItemsProvider._currentForSave, ItemSheetBinding fetches before its update, the editor opens through _FullItemRecord; no read, no save"]
      w16["items list less attachments and empty CAD (20.9 KB); unitConversions kept for ten quantity-conversion readers"]
      w17["phone replica: 8 tables, bootstrap ?tables=, scoped catch-up moves the cursor past skipped changes, one shared ReplicaSession for both apps"]
        w17a["first load waits for catch-up (3 s max) in both apps; offline banner off SocketService.streamLive with the last sync time"]
        w17b["emulator: warm relaunch = one /api/changes; live vendor = one GET; offline keeps the stock screen; B44 stuck auth error, B45 server forgotten"]
      w18["B44: passcode errors beside the keypad with Try again; the shell never swaps the screen out"]
      w19["B45: server in SharedPreferences, Change server; OfflineUnlock (secure storage, salted hash, bound to server) only when unreachable"]
        w19a["ConditionalCacheClient serves its stored copy, marked stale, when a GET cannot reach the server; never over an answer"]
        w19b["ReplicaSession catches up whenever SocketService.streamLive comes up; catchUp: false for an offline start"]
      w20["benchmark: throttle-proxy (bandwidth, RTT, handshake, slow start, loss) + network-throttle.js, 50 runs, SLOs asserted, report in Docs/benchmarks"]
        w20a["1 Mbps: first launch 1.32 s, relaunch 0.85 s, lists 0.25 s; the August pattern 23.3 s"]
        w20b["B46-B48: items list 7 queries per part + 4 missing indexes, challan list 5 per row; batched, 444 to 13 ms and 96 to 3 ms"]
        w20c["Server-Timing: db (kernel/db-timing.js) separates time in SQLite from JavaScript; server times move with host load"]
      w21["client outbox (core/sync/outbox.dart): client_outbox in its own file per user, so a replica resync never deletes unsent work"]
        w21a["OutboxSyncEngine: strict FIFO, 1/2/4…30 s backoff holds the head, the entry id is X-Idempotency-Key, drained on write, timer and streamLive"]
        w21b["any refusal = conflict for a person (Needs review: Send again / Discard), never resolved alone; a dependent {ref:} entry follows its parent"]
        w21c["challans: negative id + 'Pending upload' until synced; online submits go through it too and a refusal is still shown on the form"]
        w21d["emulator: offline Purchase → kept across a restart → server back → one POST + one issue, one row, RC-00001; B49 found and fixed"]
      w22["B50: ReplicaSession.changedTables → ItemsProvider(replicaChanges:) re-reads when local_items changed, after the copy holds it"]
      w23["B53: offline, type/mine lists answered from the copy filtered by created_by; outbox first; a refusal is not offline"]
      w24["B51: DeliveryChallanItem.weightUnitSymbol = kg; the item's unit says how it is counted, not what the weight means"]
      w25["Sync Health (core_erp): round trip (a stale cached answer is not a ping), copy cursor vs server head, outbox with Flush now, N / N-1 versions"]
        w25a["phone app-bar button; desktop Settings pane for admins + sidebar button for everyone else"]
        w25b["B54: a typed host:port got :18080 appended and was remembered; fixed. B55 open: phone Settings needs PreferencesProvider"]
      w26["B55: the phone's gear opens its own sheet (Sync health, server, Sign out that forgets the offline unlock, version)"]
      w27["⟳ phone camera: ZoomablePreview (pinch, 1×/2×/max) via CaptureSource.zoomRange/setZoom; shootPhoto = app camera then crop, used by the purchase wizard and editor; request camera gains Crop"]
        w27a["⟳ core_erp media: cropPhoto (image pkg, EXIF baked, isolate, whole photo untouched) + PhotoCropScreen (corners, move, Reset, root navigator)"]
        w27b["⟳ B65 image/jpg refused by the local store → photoContentType; B64 open: replica/cache/outbox keyed by user, not server"]
      w3["what exists: gzip on everything, ETag must-revalidate on eight masters, a challan list without lines, orders paged on request, the client replica over SSE"]
    Kernel
      k20["idempotency.js: X-Idempotency-Key per user for a day; replay, 422 reused, 409 in progress / applied / unknown"]
        k20b["telemetry.js: per-route p50/95/99, bytes on the wire, status classes; write lock wait = elapsed − profiled exec (ms resolution, upper bound); timed PASSIVE checkpoint; file sizes"]
        k20c["system-routes.js: /api/system/status for anyone signed in; /api/system/metrics for admins or PAPER_METRICS_TOKEN, JSON or Prometheus"]
        k20d["backup.js: VACUUM INTO on its own connection, .part then rename, integrity_check, keep 14; scheduled + /api/system/backups; B56/B57 scripts fixed"]
        k20e["pin-hash.js: HMAC under PAPER_PIN_KEY (key outside the db), same column + unique index, plain PINs hashed in initDb; shown once; New phone PIN; B59 online guessing open"]
        k20f["pin-throttle.js: 1 s tarpit per wrong PIN; 15 wrong-or-pending per address per rolling minute, counted on arrival, then 429 for a minute; right PINs give their place back"]
        k20a["run() calls beforeCommit() on every COMMIT: the key is marked inside the write's own transaction, all 61 transaction sites, none changed"]
      k1["registry.js: 15 modules, permissions, Track labels, and TABLE_OWNERS: one owner for every table"]
      k2["territory.js: meters routes and tables per module"]
      k3["contracts.js, barcodes.js, event-logger.js"]
      k5["desk.js: operations by name, one result shape, ok or a refusal"]
        k5a["callers: HTTP route handlers for a user, desk.as module for another module, system for boot and tests"]
        k5b["each call: name resolved, actor checked, input checked, function run, result checked against the output contract"]
        k5c["a user needs the operation's permission, its access rule (signedIn, anyRole or anyPermission), or both when both are set; plus roles when set"]
        k5d["a module is refused any operation it has not declared in its uses list, in server.js"]
        k5e["internal operations are for modules, never a user"]
        k5h["enforce refuses a broken input with 400, worded about the field, and throws on a broken result; report records and carries on; the server defaults to enforce, an operator can force report"]
        k5i["catalogue: every operation, its contract, its mode and who uses it; contract-surface.test.js pins it"]
      k6["module-borders.test.js: the places a module names a table it does not own; 26, all declared; undeclared reads and kernel touches must be zero; a read declared in the registry is marked and counted apart"]
      k7["desk-kit.js: refusing, fromRefusal, httpKit; for moved handlers: answer, answerFile, runMoved, deskRoutes; for what a module offers others: operationsFromAsks, clientFromAsks, joinOperations"]
        k5f["in process, on the one connection: a call joins the caller's transaction"]
        k5g["calls per operation are counted and shown by /api/kernel/territory"]
      k4["boot order"]
        k4a["startServer: runMigrations in migrate.js, then initDb"]
        k4b["initDb: inline CREATE TABLEs, then runPendingMigrations in modules/kernel/migration-runner.js"]
        k4c["two ledgers: _migrations and schema_migrations"]
    Masters
      Part tabs ⟳
        pt1["PartTabs: one pill tab per row of the sheet, + adds a part (key part_add_row), × follows the line's rule; Ctrl+Tab steps"]
        pt2["PartTabColors: colour by rowKey, kept until the tab closes; a row replaced in one step keeps its colour; five gradients in SoftErpTheme.partTabGradients, then round again"]
        pt3["⟳ PartFramePainter: one line up round the open tab and on round the sheet, white coat inside, nothing filled; positions read at paint time; fades on a tab change"]
        pt4["PartRowsForm.currentRowOnly: only the open part's line is drawn; the keyboard flow holds that one line"]
        pt5["⟳ workspaceNamespace(baseUrl, user): the replica, cache and outbox folder on desktop and phone (B64); a cursor past the server's head takes a fresh copy"]
      Part identity
        pid1["a part is group + unit + name + Alloy + Thickness (B): two Pattis with different alloys are two parts, each its own number (numbers count per name)"]
        pid2["server: findItemDuplicate compares identityOfTree; refusal names the alloy and thickness; 1.20 is 1.2"]
        pid3["sheet: ColumnDef.identity, SheetEngine.identityKey shared by engine, controller and binding; Part Name options show code · alloy · thickness"]
        pid5["picker: on a new row a name pick is the name (B63); group + type + name + alloy + thickness matching a part opens it, as cells are filled"]
        pid4["guard: an opened part's alloy or thickness changed → Make a new part / Change this part / Cancel; both save paths; a new part takes no Developed For and no raw plan from the old one"]
      Vendors evacuated
        vOps["operations.js: list, get, purchaseHistory, create, update, delete; internal rows.get for challans"]
        vBiz["Business rules"]
          vb1["one vendor per name or GST number"]
          vb2["a vendor named on a challan cannot be deleted"]
          vb3["absent logo or photo keeps what is stored"]
          vb4["name is required"]
        vApi["API surface"]
          va1["GET /api/vendors"]
          va2["GET /api/vendors/:id"]
          va3["GET /api/vendors/:id/purchase-history"]
          va4["POST /api/vendors"]
          va5["PATCH /api/vendors/:id"]
          va6["DELETE /api/vendors/:id"]
        vOrch["Orchestration: modules/vendors/routes.js"]
          vo1["registerVendorRoutes ctx"]
          vo2["emit vendor_added, vendor_updated, vendor_deleted"]
          vo3["trackCreate, trackUpdate, trackDelete"]
        vSvc["Services: modules/vendors/service.js"]
          vs1["createVendorService"]
          vs2["saveVendor"]
          vs3["findVendorDuplicate"]
          vs4["getVendorRowById, getVendorsWithUsage"]
          vs5["rowToVendorDto"]
        vKit["Shared kit: modules/parties/party-kit.js"]
          vk1["normalizePartyValue, normalizeGstNumber"]
          vk2["createPartyDeleteBlockers"]
        vPort["Ports it uses"]
          vp1["challans.vendorUsageCount"]
          vp2["challans.vendorUsageCounts"]
          vp3["challans.vendorPurchaseRows"]
          vp4["itemsPorts.describe"]
        vData["Data"]
          vd1["vendors"]
        vTest["Tests"]
          vt1["vendors-api.test.js"]
          vt2["route-surface.test.js"]
        vLeft["Still in server.js"]
          vl1["ensureFullSeedVendor and scenario seeders"]
          vl2["delete-request approve: DELETE FROM vendors"]
          vl3["getVendorForChallan in the challan code"]
      Items evacuated
        itSvc["service.js assembles variation-tree, property-keys, schema-props, developed-for, variations, dto, reads, save, deletes; server.js destructures the old names"]
        itOps["operations.js: items, groups, Master Data, material types, sheet properties for users; rows, groups, variations and the ports for other modules"]
        itWork["work.js and a work function in master-data.js, material-types.js, sheet-properties.js: what the handlers did"]
        itClient["asks.js and client.js: describe, selection, stock, groups, reconcile helpers, cascade delete; held by eight callers"]
        itAsk["asks pipelines, clients, units, orders, challans, inventory instead of joining their tables"]
        itLeft["nothing of items is left in server.js but its wiring and seeds"]
        i1["modules/items: routes, ports, contract, master-data, section-tree"]
        i2["items ports grow developedForCount"]
      Units evacuated
        u1["modules/units: master.js (units, families, conversion graph), service.js (standard ladders, quantity engine)"]
        u2["operations.js: 13 for users, 2 internal; typed inputs and outputs, enforced; a missing name is a 400, not a 500"]
        u3["routes.js and master-routes.js ask the desk; neither is handed the database"]
        u4["usage of a unit = inventory + items + orders answers at the desk + units that convert through it"]
        u5["unit-groups paths are now gated as units; convert-batch is gated as a read"]
        u6["the conversion graph is built per batch, not only after a save"]
      Process routes evacuated
        pr1["modules/process_routes: routes, service"]
        pr2["operations.js: stages list, create, retire; routes list, save, version"]
        pr3["routes.js is handed neither the database nor the service; it asks the desk"]
        pr4["the part-exists check moved from the handlers into the operations"]
      Clients evacuated
        cOps["operations.js: 7 clients, 5 sub-contractors, 3 contacts, 7 portal; internal rows.get for orders and invoices, exists for dies"]
        cBiz["Business rules"]
          cb1["one client per name or GST number; GST is 15 characters"]
          cb2["a client on a live order keeps its name and GST"]
          cb3["a client something still names cannot be archived or deleted"]
          cb4["a save that does not mention a field keeps what is stored"]
          cb5["the client row and its primary contact land together or not at all"]
          cb6["a sub-contractor update keeps the fields it did not mention"]
        cApi["API surface"]
          ca1["GET /api/clients and /api/clients/:id"]
          ca2["POST /api/clients, PATCH /api/clients/:id"]
          ca3["PATCH /api/clients/:id/archive and /unarchive"]
          ca4["DELETE /api/clients/:id"]
          ca5["sub-contractors: GET all, GET and POST per client, PUT and DELETE by id"]
          ca6["portal: credentials, catalogue, login, catalogue read, cart, orders"]
        cOrch["Orchestration: modules/clients/routes.js and portal-routes.js"]
          co1["registerClientRoutes ctx"]
          co2["registerClientPortalRoutes ctx"]
          co3["archive result is notFound, already, or before and after"]
          co4["emit client_added, client_updated, client_deleted"]
        cSvc["Services: modules/clients/service.js"]
          cs1["createClientService"]
          cs2["saveClient, findClientDuplicate, getClientRowById, getClientsWithUsage"]
          cs3["archiveClient, unarchiveClient"]
          cs4["list, create, update, delete sub-contractor"]
          cs5["rowToClientDto, rowToSubContractorDto"]
        cKit["Shared kit: modules/parties"]
          ck1["party-kit: normalizePartyValue, normalizeGstNumber, createPartyDeleteBlockers"]
          ck2["contacts.js: the company's people, already out"]
        cPort["Ports it uses"]
          cp1["orders.clientLineCount, clientLineCounts, clientLockedLineCount"]
          cp2["orders.insertOrderHeader, saveOrder with useTransaction false"]
          cp3["items.developedForCount"]
        cData["Data"]
          cd1["clients, sub_contractors, party_contacts"]
          cd2["portal_users, portal_carts, client_portal_catalog"]
        cTest["Tests"]
          ct1["clients-api.test.js"]
          ct2["client-archive.test.js"]
          ct3["party-contacts.test.js"]
        cLeft["Still in server.js"]
          cl1["seeds: seedClientsIfEmpty, ensureClientRecord, ensureDemoClientsPresent"]
          cl2["delete-request approve and action-center scans read clients"]
          cl3["a portal order for an item with variations still fails: no selection is sent"]
          cl4["portal passwords are stored and compared as plain text"]
      Machines evacuated
        maOps["operations.js: list, get, save, delete; asks items for the group name a machine is numbered after"]
        mBiz["Business rules"]
          mb1["a machine number is the type initials plus the next in that type"]
          mb2["a taken number is refused by name and a free one is offered"]
          mb3["a save that does not mention a field keeps what is stored"]
          mb4["capacity kind is rated or free hand; only rated carries a figure"]
          mb5["a machine held by a live pipeline run cannot be deleted"]
        mApi["API surface"]
          ma1["GET /api/machines"]
          ma2["GET /api/machines/:id"]
          ma3["POST /api/machines, create or update"]
          ma4["DELETE /api/machines/:id"]
          ma5["GET /api/machines/:id/assets"]
          ma6["POST /api/machines/:id/assets/upload-intent and upload-complete"]
        mOrch["Orchestration: modules/machines/routes.js"]
          mo1["registerMachineRoutes ctx"]
          mo2["a refusal from the service becomes its status and body"]
          mo3["delete purges links and variations, late bound"]
        mSvc["Services: modules/machines/service.js"]
          ms1["createMachineService"]
          ms2["saveMachine, refusal or saved row"]
          ms3["listMachines, getMachine, deleteMachine"]
          ms4["rowToMachineDto, shared with orders report and trace"]
          ms5["machine-identity.js: buildMachineNo, nextMachineNo, nextFreeMachineNo"]
        mPort["Ports it uses"]
          mp1["production.machineAssignedToActiveRun"]
          mp2["assets kernel: listAssetsForEntity, createAssetUploadIntent, completeAssetUpload"]
        mData["Data"]
          md1["machines"]
        mTest["Tests"]
          mt1["machines-api.test.js"]
          mt2["machine-sheet-fields.test.js"]
        mLeft["Still in server.js"]
          ml1["GET /api/machines/:id/queue reads pipeline_runs"]
          ml2["direct SQL on machines from item save, barcode resolve, seeds, delete-request approve"]
      Dies evacuated
        diOps["operations.js: list, get, save, delete; dies.makers list, get, create, update, delete; asks clients whether a client exists"]
        dBiz["Business rules"]
          db1["a die code is the type initials, then D, then the part code"]
          db2["a typed die type is allowed only with its label"]
          db3["a taken code is refused by name and a free one offered"]
          db4["a newly sent die maker must exist and not be archived"]
          db5["a die's client is a link, not a column; absent keeps it, null clears it"]
          db6["a die held by a live pipeline run cannot be deleted"]
          db7["a save that does not mention a field keeps what is stored"]
        dApi["API surface"]
          da1["GET /api/dies"]
          da2["GET /api/dies/:id"]
          da3["POST /api/dies, create or update"]
          da4["DELETE /api/dies/:id"]
          da5["GET /api/dies/:id/assets"]
          da6["POST /api/dies/:id/assets/upload-intent and upload-complete"]
        dOrch["Orchestration: modules/dies/routes.js"]
          do1["registerDieRoutes ctx"]
          do2["a refusal from the service becomes its status and body"]
          do3["delete purges links and variations, late bound"]
        dSvc["Services: modules/dies/service.js"]
          ds1["createDieService"]
          ds2["saveDie, refusal or saved row"]
          ds3["listDies, getDie, deleteDie, diesWithClients"]
          ds4["rowToDieDto, shared with orders report and trace"]
          ds5["dieJsonList, tolerant of free text in a JSON column"]
          ds6["die-identity.js: buildDieCode, nextFreeDieCode, isUsableDieType"]
          ds7["die-makers.js: the made-by master, already out"]
        dPort["Ports it uses"]
          dp1["production.dieAssignedToActiveRun"]
          dp2["links: resolveSoleEntityLinks and setSoleEntityLink, late bound"]
          dp3["assets kernel: listAssetsForEntity, createAssetUploadIntent, completeAssetUpload"]
        dData["Data"]
          dd1["dies, die_makers"]
        dTest["Tests"]
          dt1["dies-api.test.js"]
          dt2["die-sheet-fields.test.js"]
          dt3["die-makers.test.js"]
        dLeft["Still in server.js"]
          dl1["direct SQL on dies from item save, photo sync, barcode resolve, seeds, delete-request approve"]
      People evacuated
        peOps["operations.js: departments and employees, 4 each; create, link and unlink a login, admins only; internal employees.idByBarcode for jobs"]
        pBiz["Business rules"]
          pb1["a department needs a name; an employee needs a name and a department"]
          pb2["deleting a department trashes its employees with it, and records both in Track"]
          pb3["only in-house employees can have a login"]
          pb4["an employee has at most one login, and a login at most one employee"]
          pb5["a staff login code is the birth date as DDMM, or the next free code"]
          pb6["a new birth date re-derives the code of a linked login"]
          pb7["only a super admin can grant admin; a super admin cannot be made from an employee"]
        pApi["API surface"]
          pa1["GET, POST /api/departments; PATCH, DELETE /api/departments/:id"]
          pa2["GET, POST /api/employees; PATCH, DELETE /api/employees/:id"]
          pa3["POST /api/employees/:id/create-login"]
          pa4["POST /api/employees/:id/link-login and /unlink-login"]
        pOrch["Orchestration: modules/people/routes.js"]
          po1["registerPeopleRoutes ctx"]
          po2["login routes add requireRoles and a specific permission on top of the gate"]
          po3["department delete cascades through trashAndDeleteMany"]
        pSvc["Services: modules/people/service.js"]
          ps1["createPeopleService"]
          ps2["createDepartment, updateDepartment, listDepartments, getDepartmentWithEmployees"]
          ps3["createEmployee, updateEmployee, listEmployees, getEmployee"]
          ps4["getEmployeeWithLogin: an employee joined to its account"]
          ps5["rowToDepartmentDto, rowToEmployeeDto"]
        pPort["Ports"]
          pp1["offers: people.employeeIdByBarcode, used by jobs"]
          pp2["uses: auth kernel, handed in by name"]
          pp3["createUserAccount, logAuthEvent, getRequestIp, getRequestUserAgent"]
          pp4["deriveDobPin, nextFreeMobilePin"]
        pData["Data"]
          ped1["employees, departments"]
          ped2["touches users: mobile_pin"]
        pTest["Tests"]
          pt1["people-api.test.js"]
          pt2["activity-sittings.test.js"]
        pLeft["Still in server.js"]
          pl1["payroll: 9 routes at /api/payroll, not claimed by the registry"]
          pl2["freelancer card route reads employees through the people port"]
          pl3["seeds, delete-request approve and the sandbox dashboard read employees"]
      Pipelines evacuated
        piOps["operations.js: templates list, save, update, delete; legacyTemplates for the older /templates set, read by anyone signed in, changed with config.write"]
        plBiz["Business rules"]
          plb1["a template with any run, ongoing or historical, cannot be deleted through the api set"]
          plb2["the api set takes the version from the body; the root set starts at 1 and bumps on every update"]
          plb3["only the api set stores the pen and paper baseline"]
          plb4["a factory sees its own templates and the shared ones with no factory"]
        plApi["API surface"]
          pla1["api set: GET, POST /api/production/pipeline-templates; PUT, DELETE by id"]
          pla2["root set: GET, POST /templates; GET, PUT, DELETE by id"]
        plOrch["Orchestration: modules/pipelines/routes.js"]
          plo1["registerPipelineRoutes ctx"]
          plo2["the root set is outside /api, so it never meets the central gate"]
          plo3["app.use gates for /templates and /runs stay in server.js and run first"]
        plSvc["Services: modules/pipelines/service.js"]
          pls1["createPipelineService"]
          pls2["api set: apiListTemplates, apiSaveTemplate, apiUpdateTemplate"]
          pls3["root set: rootListTemplates, rootCreateTemplate, rootUpdateTemplate"]
          pls4["getTemplateRow, deleteTemplateRow"]
          pls5["rowToTemplate, shared with production when it starts a run"]
        plPort["Ports it uses"]
          plp1["production.templateRunCount"]
        plData["Data"]
          pld1["pipeline_templates"]
        plTest["Tests"]
          plt1["pipelines-api.test.js"]
          plt2["sheet-plan-persistence.test.js"]
          plt3["assembly-job-dedupe.test.js"]
        plLeft["Still in server.js"]
          pll1["/runs routes and the app.use gates that cover them: production"]
          pll2["createRunFromTemplate and seeds read templates"]
          pll3["two implementations not merged; that is a decision, not a move"]
    Flows
      Orders evacuated
        oBiz["Business rules"]
          ob1["adding the same line again merges into it and adds the quantity"]
          ob2["a line names a client, an item and a variation; a simple item needs none"]
          ob3["status moves only along allowed steps; completed is reversed only by an admin"]
          ob4["every change is written to the line's activity log and status history"]
          ob5["deleting a line returns the stock its runs consumed and dissolves those runs"]
          ob6["the header goes when its last line goes"]
          ob7["a PO document must be uploaded before it can be linked to a line"]
        oApi["API surface"]
          oa1["GET, POST /api/orders; GET, PUT, DELETE /api/orders/:id"]
          oa2["PATCH /api/orders/:id/lifecycle"]
          oa3["GET activity, status-history, material-requirements"]
          oa4["PO: documents GET and POST, uploads intent and complete, read-url"]
          oa5["reports: fulfilment, pipeline-runs, production-report, trace"]
          oa6["returns: GET and POST by order number"]
        oOrch["Orchestration"]
          oo1["modules/orders/routes.js: the six line routes ask the desk; PO documents still call the service"]
          oo2["modules/orders/reports.js: registerOrderReportRoutes, read models and returns"]
          oo3["emits orders_changed on create, edit and delete only"]
        oSvc["Services: modules/orders/service.js"]
          os1["createOrdersService"]
          os2["saveOrder with useTransaction, updateOrderLifecycle, ORDER_LIFECYCLE_TRANSITIONS"]
          os3["getOrders, countOrders, buildOrderFilter, getOrderRowById, ORDER_LIST_SELECT"]
          os4["insertOrderActivityLog, getOrderActivity, getOrderStatusHistory"]
          os5["PO documents: createPoUploadIntent, completePoUpload, linkPoDocumentsToOrder, getPoDocumentsForOrder, createPoDocumentReadUrl"]
          os6["resolveOrderUnitSelection; rowToOrderDto and three more DTOs"]
          os7["reports.js: orderReturnRowToDto, nextOrderReturnNo"]
        oOps["Operations: modules/orders/operations.js"]
          ox1["for users: orders.list, get, save, edit, lifecycle.set, delete"]
          ox2["internal: orders.clients line counts, orders.lines get, summary, ids, custom variation values, orders.portal insertHeader and saveLine"]
          ox3["line-writes.js: editOrderLine and deleteOrderLine, out of their HTTP handlers, statements unchanged"]
          ox4["asked by: clients and its portal, parties delete blockers, production, inventory"]
          ox5["a refusal the service throws, 4xx, comes back as a result"]
        oPort["Ports"]
          op1["ports.js is now only the implementation behind the internal operations; nobody is handed it"]
          op2["uses: inventoryPorts.movements.applyCore and productionPorts.runs on delete, clients getClientRowById, items resolveOrderVariationSelection"]
          op3["uses by name from production: getMergedNodeMetrics, rowToRun, machine and die DTOs"]
        oData["Data"]
          od1["order_headers, order_items, order_activity_log, order_status_history"]
          od2["order_material_requirements, order_pipeline_assignments, order_returns"]
          od3["order_po_documents, po_documents, po_upload_sessions"]
          od4["procurement tables: schema only, no code"]
        oTest["Tests"]
          ot1["orders-routes.test.js, 7 tests, written first"]
          ot2["orders-api, wire-weight, order-fulfilment, order-set-provenance, stage-reconciliations"]
        oLeft["Still in server.js"]
          ol1["GET /api/orders/:orderId/delivery-challans and /:orderNo/reconciliation: challans"]
          ol2["DELETE and the reports run SQL on production's run tables, on purpose for now"]
          ol3["production writes order_pipeline_assignments; challans read order lines and complete them"]
          ol4["seeds and demo scenarios; resolveOrderVariationSelection, an items helper"]
          ol5["pinned oddities: PUT answers a raw row, DELETE says success for an unknown id, lifecycle does not notify"]
      Inventory evacuated
        inOps["operations.js: sets, materials, stock, health, movements.record for users; 25 internal from asks.js"]
        inWork["work.js: what the 22 handlers did, returning a status and a body and noting Track entries"]
        inClient["client.js: the ports' shape over the desk; handed to challans, orders, production and jobs"]
        inAsk["asks items, orders, challans, pipelines, machines, dies for rows; six of its operations join the caller's transaction"]
        ivBiz["Business rules"]
          ivb1["a set is a bill of material; saving replaces its lines; a stale expectedVersion is refused as set_changed"]
          ivb2["a material is a parent with children; deleting a parent takes its children, deleting a child gives the parent its count back"]
          ivb3["a material inherits from a group or from an item and variation, never both"]
          ivb4["a receive must name where the stock came from; an over-issue is refused and moves nothing"]
          ivb5["stock lives in positions by location and lot; the material's on-hand is derived from them"]
          ivb6["every movement appends to the material's activity feed; a transfer also records a location move in the custody ledger"]
        ivApi["API surface, moved"]
          iva1["sets: GET, POST /api/inventory/sets; PATCH, DELETE by id"]
          iva2["materials: GET list, one, detail, activity; POST parent and child; PATCH edit, group-config, link-group, link-item, unlink, scan, scan/reset; DELETE"]
          iva3["POST /api/inventory/movements"]
          iva4["GET /api/inventory/health"]
          iva5["GET /api/inventory/stock: stock by item and variation"]
        ivOrch["Orchestration: modules/inventory/routes.js"]
          ivo1["registerInventoryRoutes ctx"]
          ivo2["trackCreate, trackUpdate, trackDelete; currentActor stamps the movement"]
        ivSvc["Services: modules/inventory/service.js"]
          ivs1["createInventoryService, 2500 lines"]
          ivs2["sets: saveInventorySet, deleteInventorySet, getInventorySets, line merge and validation"]
          ivs3["materials: createParentWithChildren, createChildMaterial, updateMaterialRecord, deleteMaterialRecord, link and unlink"]
          ivs4["ensureMaterialForItemSelection: the material behind an item and variation"]
          ivs5["governance: persistMaterialGroupGovernance, getMaterialGroupGovernance, retireMissingGroupProperties"]
          ivs6["ledger: applyInventoryMovementCore, stock positions, recomputeMaterialInventorySummary"]
          ivs7["read models: getMaterialControlTowerDetail, getInventoryHealthSummary, getMaterialActivity"]
          ivs8["rowToMaterialDto, rowToMaterialActivityDto, barcode generators"]
          ivs9["getStockOverview: merges custom variation values from stock, materials, order lines and challan lines"]
        ivPort["Ports"]
          ivp1["offers: sets.*, materials.delete, governance.get and retireMissingProperties, movements.apply and applyCore, scans.increment, ledger.recomputeSummary"]
          ivp5["receipts.usageForChallan, receipts.retire; materialStockTotals shared with recomputeMaterialInventorySummary"]
          ivp7["receipts.materialForChallanLine: the material a reception line became, its unit and on hand"]
          n32x63759["sources.forItem, sources.propose; GET /api/inventory/stock-sources; uses challans.numbersByIds"]
          n31x14111["applyInventoryMovementCore moves whole-item stock for a material linked to an item with no variations; uses items.stock.holdsWholeItemStock"]
          ivp6["a material in state cancelled is kept for the trail and left out of GET /api/materials"]
          ivp4["offers to challans: receipts.mintFromChallanLine, receipts.mintReconcileLot, movements.recordForChallan, forChallan, recordChallanReversal, producedLotCodeForRun"]
          ivp2["uses, by name: items port describe, entity links, variation readers, saveGroup, applyVariationStockDelta, recordLedgerEvent"]
          ivp3["uses, read only: items.variationStockRows, orders.customVariationValueRows, challans.customVariationValueRows"]
        ivData["Data"]
          ivd1["materials, material_activity, scan_history"]
          ivd2["material_group_item_links, material_group_preferences, material_group_properties, material_group_units"]
          ivd3["inventory_movements, inventory_reservations, inventory_alerts, inventory_stock_positions"]
          ivd4["inventory_sets, inventory_set_lines"]
        ivTest["Tests"]
          ivt1["inventory-api.test.js, 7 tests, written first"]
          ivt2["inventory-sets-api, material-governance, integrity-safety, barcode-ledger-events, variation-stock"]
        ivNext["Still in server.js"]
          ivn1["the registry keeps the barcode segment, but /api/barcode/lookup is the resolver and stays"]
          ivn2["the universal barcode resolver, /api/scan, /api/barcode/lookup, recordLedgerEvent: kernel services"]
          ivn3["search routes and their tables"]
          ivn4["production and challans write inventory tables by hand: ensureTemporarySetFromAssembly, stockTemporarySet, mintReceivedMaterial, raw movement inserts"]
          ivn5["seeds and backfills: ensureFullSeedMaterial, backfillInventoryLedgerForMaterials, ensureDemoInventoryPresent"]
          ivn6["items reads inventory tables for usage counts, and its Sets card route reads inventory_sets"]
          ivn7["getMaterialRowByBarcode and the group property normalisers stay: items and inventory both use them"]
      Challans evacuated
        chOps["operations.js: the challan itself, templates, invoices, reports; 42 for users, 11 internal"]
        chWork["work.js, template-work.js, invoice-work.js, report-work.js: what the handlers did, returning a status and a body or a PDF"]
        chClient["asks.js and client.js: stage notes, sheets, vendor usage, numbers by id; held by vendors, parties, production, inventory"]
        chAsk["asks orders for rows and lifecycle moves, production for an output row, items and units for a line's unit, clients and vendors for a party"]
        chBiz["Business rules"]
          chb1["a challan is a draft until issued; issuing freezes its printed snapshot and moves stock"]
          chb2["a reception mints material; a delivery takes stock out; internal use is settled later"]
          chb3["cancelling puts stock back; only a draft is deleted outright"]
          n31x61889["an item with no variations is received, used, returned and cancelled through its own stock figure"]
          chb7["a reception is cancelled only while all it brought in is free: not consumed, not reserved, not claimed by a run"]
          chb8["a partly used reception is not cancelled; its free remainder goes back on a draft vendor return linked to it"]
          chb10["an issued reception is deleted only while all it brought in is free; a used one is refused"]
          chb11["a return of scanned sheets finds its reception from the sheets, when they all came in on one"]
          chb9["a vendor return made from a reception leaves the received material itself, and never more than is free"]
          chb4["a challan with invoices is not cancelled until they are dealt with; draft invoices can go with it"]
          chb5["an internal-use challan settles its full weight into scrap, leftover, lost, rejection and finished goods"]
          chb6["an invoice bills challan lines and is recorded in the custody ledger once per challan"]
        chApi["API surface"]
          cha1["22 doubled registrations under /api/challans and /api/delivery-challans"]
          cha2["piece-barcodes, asset upload intent and complete, an order's challans"]
          cha3["invoices: 7 routes; reports: 6 routes; templates: 14 routes"]
        chO["Orchestration: modules/challans/routes.js"]
          cho1["registerChallanRoutes ctx; one handler per action, registered under both spellings"]
          cho2["handleReconcileChallan: the in-use settle, about 230 lines"]
          cho3["notifies other screens through getIo: challan_generated_ok, item_updated"]
          cho4["POST cancel answers outcome return_challan_created, message and returnChallan when a return was made"]
          cho5["app: ApiChallanRepository carries the message as DeliveryChallan.actionNotice; the challan screen shows it in a dialog"]
        chC["Core: modules/challans/service.js"]
          chc1["createChallanService"]
          chc2["saveDeliveryChallan, issueDeliveryChallan, cancelDeliveryChallan, deleteDraftDeliveryChallan"]
          chc3["mintReceivedMaterial: a reception becomes stock"]
          chc4["listDeliveryChallans, getDeliveryChallanRowById, rowToDeliveryChallanDto, getDeliveryChallanItems"]
          chc5["report groups: effectiveReportGroupCodesForChallan, replaceChallanReportGroups"]
          chc6["generateChallanNumber, used by production too"]
          chc8["receptionUsage: received, on hand, reserved, on runs, free, used per received material"]
          chc9["cancelDeliveryChallan: a movement naming a real material is undone through applyCore, a '-' movement the old way"]
          chc10["createReturnForReception, issueReturnLine, partlyUsedNotice"]
          chc12["reverseIssuedStock: one reversal loop shared by cancel and delete, told its reason code"]
          chc11["data: delivery_challans.source_reception_challan_id; a return line names its material in material_barcode"]
          chc7["stock goes through ports: inventoryPorts receipts and movements, itemsPorts.stock; piece_barcodes still written here"]
        chR["Reports: modules/challans/reports.js and report-routes.js"]
          chr1["buildReconciliationReport, buildClientStatementReport, buildOrderReconciliation"]
          chr2["listConversionOverrides, saveConversionOverride, listWasteAuditRows"]
          chr3["6 routes: /api/reconciliation/*, /api/reports/client-statement, /api/orders/:orderNo/reconciliation"]
        chI["Invoices: modules/challans/invoices.js and invoice-routes.js"]
          chi1["createInvoiceService: createInvoice, listInvoices, getInvoiceDtoById, generateInvoiceNumber"]
          chi2["generateInvoicePdf, numberToIndianWords"]
          chi3["7 routes under /api/invoices; POST records INVOICED once per challan billed"]
        chT["Templates: modules/challans/templates.js and template-routes.js"]
          cht1["createChallanTemplateService: listChallanTemplates, saveChallanTemplate, deleteChallanTemplate"]
          cht2["generateChallanTemplatePdf, buildChallanTemplateSnapshot, buildTemplateTestChallanDto"]
          cht3["scan uploads: createChallanTemplateUploadIntent, completeChallanTemplateUpload, listChallanTemplateScans"]
          cht4["14 routes under /api/challan-templates, /api/templates/:id/test-print, print-template-preview"]
          cht5["route order: /scans and both /test-print routes sit ahead of /:id"]
        ch1["about 26 endpoints, each served twice, 14 tables"]
        ch2["challans ports file created, vendor reads only"]
        chP["Ports"]
          chp1["offers: vendor usage and purchase rows, customVariationValueRows"]
          chp2["uses: inventoryPorts.movements.applyCore, orders getOrderRowById and updateOrderLifecycle, vendors, templates"]
          chp3["uses by name: applyVariationStockDelta, recordLedgerEvent, getItemSelectionSnapshot, the scrap and leftover item helpers"]
        chD["Data"]
          chd1["delivery_challans, delivery_challan_items, delivery_challan_order_items, report groups, activity log"]
          chd2["challan_templates, mappings, upload sessions"]
          chd3["invoice_headers, invoice_lines"]
          chd4["stage_reconciliations, conversion overrides, waste audit"]
        chTe["Tests"]
          chte1["challans-routes.test.js, 11 tests, written first"]
          chte2["delivery-challans-api, variation-stock, challan-stock-bridge, barcode-ledger-events, order-reconciliation"]
        chL["Still in server.js"]
          chl1["GET /api/delivery-challans/health, ahead of the login gate"]
          chl2["normalizeChallanType, getItemSelectionSnapshot, the scrap and leftover group and item helpers, ensureKgUnit"]
          chl3["production writes challan tables in node-metrics and scrap; seeds"]
          chl4["fixed: GET challan-templates/test-print is reachable"]
          chl6["fixed: challan photo upload, intent and complete"]
          chl5["fixed: invoice edit, in-use settle"]
      Outside the fifteen modules
        kr1["accounts/routes.js: auth, users, me, admins, permissions, permission presets, record options; 29 routes"]
        kr2["assets/routes.js: upload intents and completions, signed views, photo gallery, photo requests; 16 routes"]
        kr3["control_plane/routes.js: sandbox config and dashboard, activation, build and update feeds, session replay; 17 routes"]
        kr4["units/master-routes.js: units and unit groups; 11 routes"]
        kr5["payroll/routes.js 9, settings/routes.js 9, search/routes.js 6, track/routes.js 5, realtime/routes.js 2"]
        kr6["each group is registered into a router mounted where its routes were, so matching order and guards are unchanged"]
        kr7["helpers they call (sessions, permission checks, asset store, change log) are still in server.js, handed in by name"]
      Production evacuated
        prOps["operations.js: runs list, get, start, delete, node status and metrics, batches, stock on a node; scrap; finished output; a machine's queue; an item's history; 19 internal"]
        prWork["work.js: what the handlers did, as functions of a plain req that return a status and a body"]
        prAsk["asks pipelines.templates.row, machines.rows.get, items.rows.get, units.rows.get; still uses inventory, items, challans and jobs ports to write"]
        pd1["runs, node status, stock on a run, stage numbers, scrap, completed output"]
        n40x15685["order status rule lives in orders/service.js ORDER_ROW_SELECT; what the runs say comes from production as orderItemRunStatusSql; a hand-made move is checked against stored_status"]
        n39x63718["pinned fault: the order LIST shows the stored status, not the one from its runs; the single read shows the derived one"]
        n39x42855["uses: inventoryPorts.sets.recordProduced and receipts.mintLot, challansPorts.stageNotes and sheets.findByCode, ordersPorts.lines"]
        n38x94392["left in server.js on purpose: seeds and demo scenarios, initDb, the telemetry emitter, the /runs login and write guards"]
        n38x21713["still open: production writes materials, inventory_sets and delivery_challans rows itself, and reads piece_barcodes for a scanned sheet; those want inventory and challans ports"]
        n33x9951["rowToRun: each input carries sourceKind and the code that addresses it"]
        n32x95640["POST runs barcodes by quantity: approved allocations are written one material each through assignMaterialToRunNode; a bad split is refused whole"]
        n31x41609["server.js, still here: assertValidStockVariationLeaf is the one rule for leaf 0; itemHoldsWholeItemStock; backfillWholeItemStock at boot; trigger trg_variation_stock_leaf_gone replaces the leaf foreign key"]
        pd3["POST runs barcodes, sheet branch: consumes from the line's material, never more than on hand; DELETE gives it back"]
        n34x65006["app: PipelineRunRepository.stockSources and attachQuantityToRunNode; pipeline_run_row drop target accepts a StockQuantityRequest"]
        n33x81384["PUT runs barcodes on a sheet row: used weight up to the sheet's weight; stock and the run's batch weight move by the difference"]
        n32x45807["PUT and DELETE runs barcodes on a quantity row move the item's own stock"]
        pd2["production/ports.js: machineAssignedToActiveRun, dieAssignedToActiveRun, templateRunCount, runInputsForChallanLines, read only"]
        n39x14887["service.orderForRun and orderLineForRun: the first linked line that still exists, asked of ordersPorts.lines"]
        n39x84970["offers, runs seen from the order side: linkedToOrderItem, unlinkOrderItem, orderItemIdsForRun, allWithOrderItem, forOrderItems, summariesForOrderItems, inputsForRun, inputsForRuns, stageTotalsForRuns; orderItemRunStatusSql as text"]
        n37x81899["offers: runs.rowById, runs.dissolve, runs.inputCountForBarcode, runs.latestInputForBarcode, runs.stagesForRun, output.sourceById, runInputsForChallanLines, machineAssignedToActiveRun, dieAssignedToActiveRun, templateRunCount"]
        n36x40227["service.setNodeStatus: status and overrides, Assembly job once per run and node, completion booked once and minted as a lot with OUTPUT_MINTED"]
        n36x99224["production/routes.js registerProductionRoutes: /runs x10, /api/production-scrap x2, /api/production-runs/completed, /api/machines/:id/queue, /api/items/:id/pipeline-history"]
        n35x5019["production/service.js createProductionService: rowToRun, getMergedNodeMetrics, createRunFromTemplate, ensurePipelineRunRecord, upsertStageReconciliation, backfillStageReconciliations, ensureTemporarySetFromAssembly, stockTemporarySet, listCompletedProductionRuns, getProductionRunRowById, assignMaterialToRunNode, STAGE_RECON_COLUMNS"]
      Jobs evacuated
        jbOps["operations.js: list, create, update, delete, batches.create, portalData; internal syncAssemblyJob and propagateAssemblyRejection for production"]
        jbAsk["asks items.bom.lines, inventory.materials.linkOf, inventory.movements.issuedToWorkerQty"]
        jBiz["Business rules"]
          jb1["one assembly job per run and node, never duplicated"]
          jb2["a re-synced job is only rewritten while unassigned"]
          jb3["handing a job to a worker issues its assembled set from stock"]
          jb4["scrap booked at reconciliation mirrors onto the job as rejections"]
        jApi["API surface"]
          ja1["GET /api/freelancer-jobs"]
          ja2["POST /api/freelancer-jobs"]
          ja3["POST /api/freelancer-jobs/batches"]
          ja4["PUT /api/freelancer-jobs/:id"]
          ja5["DELETE /api/freelancer-jobs/:id"]
          ja6["GET /api/freelancer-portal/data"]
        jOrch["Orchestration: modules/jobs/routes.js"]
          jo1["registerJobsRoutes ctx"]
          jo2["decrypt worker token, find employee, return their card"]
          jo3["delete rolls back on failure"]
        jSvc["Services: modules/jobs/service.js"]
          js1["createJobsService"]
          js2["createJob, createBatch, setStatus, deleteJob"]
          js3["listAll, dataForFreelancer"]
          js4["issueAssemblySetsForJobs"]
          js5["syncAssemblyJob, called by production"]
          js6["propagateAssemblyRejection, called by reconciliation"]
        jPort["Ports it uses"]
          jp1["people.employeeIdByBarcode"]
          jp2["inventory.getMaterialRowByBarcode, applyInventoryMovementCore"]
        jData["Data"]
          jd1["freelancer_jobs, freelancer_job_batches, freelancer_job_tasks"]
        jTest["Tests"]
          jt1["jobs-api.test.js"]
          jt2["assembly-job-dedupe.test.js"]
        jLeft["Still in server.js"]
          jl1["worker token secret is a literal in routes.js, to be fixed"]
          jl2["freelancer-* not in the inline gate map, legacy write gate only"]
          jl3["production picks the job's item, then hands it to syncAssemblyJob"]
      Action center evacuated
        acOps["operations.js: trash list and restore, delete requests list, create, approve, reject, export, the issue scan"]
        acDel["deletes are asked of the owner: vendors, machines, dies, challans, inventory, items"]
        acScan["the integrity scan reads nine tables of six modules, declared in the registry"]
        acBiz["Business rules"]
          acb1["a delete copies the row to the trash, then removes it with foreign keys off, so a referenced row can go"]
          acb2["what is left dangling is found by the integrity scan, not blocked at delete time"]
          acb3["a failed delete removes its trash row again, so nothing is stranded"]
          acb4["restore keeps the original id and never overwrites a live row; photos come back with it"]
          acb5["only a fixed list of tables can be restored"]
          acb6["anyone signed in may ask for a delete; only a reviewer lists, approves, rejects or exports"]
          acb7["a request is decided once; approving an unknown kind of record is refused"]
          acb8["approve deletes first, then marks the request, so a failed delete leaves it pending"]
        acApi["API surface, moved"]
          aca1["GET /api/trash, optionally by table"]
          aca2["POST /api/trash/restore"]
          aca3["delete requests: GET list, POST create, POST approve, POST reject, GET export"]
          aca4["GET /api/action-center/issues: the integrity scan"]
        acOrch["Orchestration: modules/action_center/routes.js"]
          aco1["registerActionCenterRoutes ctx"]
          aco2["a refusal from the service becomes its status and body"]
        acSvc["Services: modules/action_center/service.js"]
          acs1["createTrashService"]
          acs2["trashAndDelete, trashAndDeleteMany in chunks of 400"]
          acs3["listTrash, restore, RESTORABLE_TABLES"]
          acs4["delete-requests.js: listRequests, createRequest, approve, reject, exportCsv"]
          acs5["scanIntegrity: ten read-only anti-joins across other modules' tables, kept as SQL on purpose"]
        acPort["Ports"]
          acp1["offers: trashAndDelete and trashAndDeleteMany, under their old names, to vendors, clients, people, units and the item and group cascades"]
          acp2["uses by name: runOnDelete, logChange, restoreEntityAssets"]
          acp3["approve calls per kind: inventoryPorts materials and sets, itemsPorts delete for item and group, deleteAsset, deleteChallanTemplate"]
        acData["Data"]
          acd1["deleted_records, delete_requests"]
        acTest["Tests"]
          act1["action-center-api.test.js, 10 tests, written first"]
        acNext["Still in server.js"]
          acn1["the delete connection: deleteDb, runOnDelete, closeDb"]
          acn2["asset trash and restore helpers, deleteAsset, deleteChallanTemplate"]
          acn3["all /api/users routes, including the user delete that also clears delete_requests"]
          acn4["KNOWN GAP, pinned: approving a vendor, machine, die or user request is a raw delete with no in-use check and no trash; a referenced vendor fails as a bare 500"]
```

## Change log

| # | Change | Layers touched |
|---|---|---|
| 1 | Vendors leave `server.js`. Adds `modules/vendors/{routes,service}.js`, `modules/parties/party-kit.js`, `modules/challans/ports.js`; adds `vendors-api` and `route-surface` tests; registry flag `evacuated: true`. | API surface (unchanged paths), Orchestration, Services, Ports, Tests |
| 2 | Jobs leave `server.js`. Adds `modules/jobs/{routes,service}.js` and `modules/people/ports.js`; production's job write and reconciliation's rejection mirror now call the jobs service; adds `jobs-api` test; registry: jobs `evacuated: true` plus its real path segments (meter only). | API surface (unchanged paths), Orchestration, Services, Ports, Tests |
| 3 | Machines leave `server.js`. Adds `modules/machines/{routes,service}.js` and `modules/production/ports.js`; delete asks production whether a live run holds the machine; orders report and trace keep the DTO via the service; adds `machines-api` test; registry `machines` evacuated. `/queue` deliberately stays. | API surface (unchanged paths), Orchestration, Services, Ports, Tests |
| 4 | Dies leave `server.js`. Adds `modules/dies/{routes,service}.js`; the production port gains `dieAssignedToActiveRun` (machines and dies share one helper); orders report and trace keep the DTO via the service; adds `dies-api` test; registry `dies` evacuated. | API surface (unchanged paths), Orchestration, Services, Ports, Tests |
| 5 | Clients leave `server.js`: the master, archive and restore, sub-contractors and the B2B portal. Adds `modules/clients/{routes,portal-routes,service}.js` and `modules/orders/ports.js`; items port gains `developedForCount`; party-kit's delete check now asks ports; adds `clients-api` test; registry `clients` evacuated and claims `portal` plus its three tables. Pins a pre-existing bug: portal order placement always fails on a nested transaction. | API surface (unchanged paths), Orchestration, Services, Ports, Data ownership, Tests |
| 6 | People leave `server.js`: departments, employees and the three login-link routes. Adds `modules/people/{routes,service}.js` beside the existing `ports.js`; auth helpers are handed in by name; adds `people-api` test (the login routes had none); registry `people` evacuated. Payroll stays and stays unclaimed: claiming it would count nine unmoved routes as evacuated. | API surface (unchanged paths), Orchestration, Services, Ports, Tests |
| 7 | Pipelines leave `server.js`: both template route sets. Adds `modules/pipelines/{routes,service}.js`; production port gains `templateRunCount`; the root `/templates` auth gates stay where they were; adds `pipelines-api` test; registry `pipelines` evacuated. Round complete: 10 of 15 modules evacuated. | API surface (unchanged paths), Orchestration, Services, Ports, Tests |
| 8 | Portal order placement fixed. `saveOrder` gains a `useTransaction` option (default true, so every other caller is unchanged); the portal route passes false and owns one transaction for header, lines and cart clear. The clients test that pinned the bug now expects success, and a new one proves a failed order leaves nothing behind. Still open: items with variations cannot be ordered through the portal. | Orchestration, Services, Tests |
| 9 | Inventory step 1 of 4: the sets. Adds `modules/inventory/{routes,service,ports}.js`; the four set routes and eleven set functions move; items' cascade delete, the item-usage read, the items Sets card and action center's delete-request approval reach sets through `inventoryPorts.sets.*`. Registry unchanged until step 4. | API surface (unchanged paths), Orchestration, Services, Ports |
| 10 | Inventory steps 2 and 3, merged: the materials, group governance and the stock ledger. The service grows to about 2,500 lines; 19 more routes move (materials, scans, activity, movements, health); every outside caller of the ledger, scan count, summary recompute, governance and material delete goes through `inventoryPorts`. The items stock port is re-wired to the variation stock write (it had no callers). The two steps are one commit because the functions call each other and a split needed temporary injection both ways. | API surface (unchanged paths), Orchestration, Services, Ports, Tests |
| 11 | Inventory step 4: `GET /api/inventory/stock` moves into the service as `getStockOverview`, with the three reads it needed behind new ports (items `variationStockRows`, orders and challans `customVariationValueRows`). Registry: inventory `evacuated: true`. Territory meter: 11 of 15. `server.js` is 30,580 lines, down from 35,760. | API surface (unchanged paths), Services, Ports, Data ownership |
| 12 | Action center step 1 of 2: the trash. Adds `modules/action_center/{routes,service}.js`; `trashAndDelete`, `trashAndDeleteMany`, listing and restore move, and the nine call sites keep their names via a destructure. Two dead parameters leave the items module. The ten-test action-center suite was written first against the old code. Registry unchanged until step 2. | API surface (unchanged paths), Orchestration, Services, Tests |
| 13 | Action center step 2 of 2: delete requests and the integrity scan. `modules/action_center/delete-requests.js` holds list, create, approve, reject, export and the ten-query scan; six routes move and the registry flags action_center evacuated (and claims `delete-requests`, meter only). The one behaviour change: approving a request whose kind of record is unknown now returns 400 and leaves it pending, where it used to say approved and delete nothing. The raw-delete gap for vendor, machine, die and user approvals is unchanged and pinned. Territory meter: 12 of 15. | API surface (unchanged paths), Orchestration, Services, Business rules, Tests |
| 14 | Orders step 1 of 3: the service. `modules/orders/service.js` takes the order DTOs, `saveOrder`, the lifecycle, the activity log and status history, the list/filter/count and shared SELECT, unit selection and the PO document functions (27 functions, about 1,270 lines). It is built before the clients service because the orders port hands `saveOrder` to the portal at load. Routes still in `server.js`. Seven route tests were committed first. | Services, Tests |
| 15 | Orders step 2 of 3: the line routes. `modules/orders/routes.js` takes 14 routes (list, one, create, edit, lifecycle, delete, activity, status history, material requirements, PO documents and uploads). Verbatim, oddities pinned. DELETE still runs SQL on production's run tables until production has a write port. | API surface (unchanged paths), Orchestration |
| 16 | Orders step 3 of 3: `modules/orders/reports.js` takes fulfilment, pipeline-runs, production-report, returns (read and write) and trace, with production's helpers injected by name. Registry: orders `evacuated: true` and claims `order_returns`. Territory: 13 of 15; `server.js` is 28,019 lines. Two order-path routes (delivery-challans, reconciliation) stay for the challans round. | API surface (unchanged paths), Orchestration, Data ownership |
| 17 | A server started with no database file failed with "no such table: order_items": the old runner in `migrate.js` runs before `initDb` creates the schema, and migration 007 alters a table that is not there yet. It now skips, unrecorded, any migration that finds a missing table or column; `initDb` then creates the schema and its own runner applies every migration. Existing databases are unaffected. | Kernel (boot), Tests |
| 18 | Challans step 1 of 5: templates. `modules/challans/templates.js` (template master, mapping normalisers, page geometry, snapshot, test fixture, PDF generator, scan uploads; about 1,720 lines) and `template-routes.js` (14 routes). The eleven-test challans route suite was committed first and records four things broken today. A local named `templates` shadowed the injected service on the first attempt; the tests caught it and the lifting tool now refuses such clashes. | API surface (unchanged paths), Orchestration, Services, Tests |
| 19 | Challans step 2 of 5: invoices. `modules/challans/invoices.js` (DTOs, list, read, numbering, `createInvoice`, amount in words, the invoice PDF) and `invoice-routes.js` (7 routes). The broken invoice edit moves as it is and is fixed in its own commit. | API surface (unchanged paths), Orchestration, Services |
| 20 | Challans step 3 of 5: reports. `modules/challans/reports.js` (reconciliation report, conversion overrides, waste audit, client statement, `buildOrderReconciliation`) and `report-routes.js` (6 routes, including `GET /api/orders/:orderNo/reconciliation`). | API surface (unchanged paths), Orchestration, Services |
| 21 | Challans step 4a of 5: the core service. `modules/challans/service.js` takes `saveDeliveryChallan`, `issueDeliveryChallan`, `mintReceivedMaterial`, `cancelDeliveryChallan`, `deleteDraftDeliveryChallan`, the list and DTOs, report-group helpers and the settle helpers (35 functions, about 1,900 lines). It is built after the inventory port; the template, invoice and report services built earlier now reach challan readers through functions. The hand-written stock writes move unchanged. | Services, Ports |
| 22 | Challans step 4b of 5: the routes. `modules/challans/routes.js` takes the eleven challan handlers (22 doubled registrations), piece barcodes, the two asset upload routes and `GET /api/orders/:orderId/delivery-challans`. Registry: challans `evacuated: true`; 14 of 15. `server.js` is about 21,500 lines. Only production remains. | API surface (unchanged paths), Orchestration |
| 23 | Fix: editing an invoice. The edit route called `prepare`, which does not exist, so every edit failed. Lines are re-inserted with `run`; an unknown id is a 404. Test flipped. | Orchestration, Business rules, Tests |
| 24 | Fix: settling an in-use challan. Two faults, the second hidden behind the first: the settle's transaction collided with the item save's own (`saveItem` now takes `useTransaction`, default true), and the stock lot row carried a variation leaf of 0, which broke its foreign key (now null). Test flipped to a full settle. | Orchestration, Services, Business rules, Tests |
| 25 | Fix: challan photo upload. Two faults: the intent step's allowed lists left challans out, so an upload could never start, and the completion route called `handleAssetUploadComplete`, which does not exist. Both fixed; completion also checks the upload belongs to that challan. Test is a real round trip against the local file store. | Orchestration, Business rules, Tests |
| 26 | Fix: `GET /api/challan-templates/test-print` was registered after `/:id` and answered as a missing template. It is now registered ahead of it and reaches the print handler. Separately, the timer-sensitive query-count test in `item-developed-for` takes the smallest of three counts. | Orchestration, Tests |
| 27 | Challans no longer runs SQL on inventory's tables in its write paths. The same statements now live in `modules/inventory/service.js` behind `inventoryPorts.receipts.mintFromChallanLine`, `receipts.mintReconcileLot`, `movements.recordForChallan`, `movements.forChallan`, `movements.recordChallanReversal` and `movements.producedLotCodeForRun`; variation stock goes through `itemsPorts.stock`. Behaviour is unchanged (pinned by `challan-stock-rows.test.js`). Not routed through the general movement engine, which refuses an outgoing line's `-` barcode. The order reconciliation report still reads the movement ledger, as a read model. | Services, Ports |
| 28 | Fix: material barcode collisions. A child's barcode is `CHD-<parent's last part>-NN`, and that last part was four random digits, so two parents could give their children the same barcodes and the second create failed on the unique index (seen as a random test failure about once in several runs). `createParentWithChildren` now redraws until the parent barcode and its child prefix are free. Test forces the collision. | Services, Business rules, Tests |
| 29 | Cancelling a reception challan now takes the received stock back. While everything it brought in is free, each receive is undone through the movement engine (`applyCore` issue on the real barcode): position and material go to zero, variation stock goes back once, the material is retired (`inventory_state = cancelled`, left out of `GET /api/materials`). If any of it is consumed, reserved or claimed by a run, the reception stays issued and `createReturnForReception` makes one draft vendor return (internal, `vendor_return`, `source_reception_challan_id`) for the free remainder; its lines name the material in `material_barcode`, issue through the engine and are refused above the free quantity. Nothing free answers 409. New ports: inventory `receipts.usageForChallan`, `receipts.retire`; production `runInputsForChallanLines` (sheet, quantity and unquantified run claims that no movement shows). A vendor return keeps its vendor. Delete of an issued reception is unchanged. App: the cancel answer's message reaches the challan screen as `DeliveryChallan.actionNotice` and is shown in a dialog. | Business rules, API surface, Services, Ports, Data, Tests |
| 30 | Three faults around received material. (1) `DELETE` of an issued reception always answered 409 (it asked the engine for lot `-`); it now follows the cancel rule through the shared `reverseIssuedStock`: untouched goes with its stock taken back and the material retired, used is refused. (2) A vendor sheet scanned onto a run wrote no stock movement; the sheet branch of `POST /runs/:id/barcodes` now consumes from the material its reception line became (`receipts.materialForChallanLine`): the sheet weight for a weighed material, one piece for a counted one, never more than is on hand, recorded in `consumed_qty`; un-assigning gives it back. `runInputsForChallanLines` skips sheets that already moved stock. (3) A return of scanned sheets (the phone flow) went out on `-`; save now ties it to the sheets' reception when they share one, so issuing leaves that material. A reception cancel reuses only its own open draft return. | Business rules, Orchestration, Services, Ports, Tests |
| 31 | An item with no variations can hold stock. `variation_stock` keeps one figure for the whole item under leaf 0; `assertValidStockVariationLeaf` allows 0 only for an item with no active variation properties (`itemHoldsWholeItemStock`, offered as `itemsPorts.stock.holdsWholeItemStock`). The table's CHECK and leaf foreign key refused 0, so initDb rebuilds it once and carries the rows; `trg_variation_stock_leaf_gone` removes a deleted leaf's stock in place of the foreign key; migration 027's insert guard now refuses only a negative leaf. The movement engine moves whole-item stock for a material linked to such an item. `backfillWholeItemStock` gives existing linked materials their figure at boot, once. The hand-written simple-item deltas in challans are gone (the engine does it). | Business rules, Services, Ports, Data, Tests |
| 32 | Issuing to a run by quantity took stock from nowhere. Now `POST /runs/:id/barcodes` without a barcode asks inventory which barcodes hold that item and variation (`inventoryPorts.sources.forItem`, also `GET /api/inventory/stock-sources`, 371 routes). If any do, the request must carry `allocations` (barcode and quantity); without them it answers 409 `allocation_required` with the sources by name and an oldest-first proposal. A split is checked whole (known barcode, not twice, not above free, sums to the quantity) and then each barcode is written as an ordinary material assignment through `assignMaterialToRunNode` (extracted from the barcode branch). If no barcode holds the item, the quantity comes off the item's own stock and is refused when there is less; `PUT` and `DELETE` on such a row move that stock. Challans port gains `numbersByIds`. | Business rules, API surface, Orchestration, Services, Ports, Tests |
| 33 | Changing the quantity of a vendor sheet on a run answered Material not found (the sheet tag was looked up as a material). `PUT /runs/:id/barcodes` on a sheet row now takes the used amount in the material's unit: for a weighed material, above zero and no more than the sheet's weight, with the difference consumed from or given back to the material the sheet's reception line became, and `consumed_qty`, `consumed_weight` and the run's `weight_kg` moved with it; a counted material's sheet is one piece and the edit is refused. Removing a part-used sheet gives back what it had taken. `rowToRun` now sends `sourceKind` and an addressable `barcode` on every input. | Business rules, Orchestration, API surface, Tests |
| 34 | App side of change 32. The Assign Stock sidebar (`inventory_sidebar.dart`) shows a `By quantity` card per item and variation, draggable onto a run node. Dropping it opens `QuantitySourcesDialog`: every barcode that holds the item by name with barcode, supplier, challan and free stock; typing a quantity fills an oldest-first split (`proposeOldestFirst`) that the user can change; Approve is enabled only when the split equals the quantity and no barcode is over-drawn. `PipelineRunRepository` gains `stockSources` and `attachQuantityToRunNode` (HTTP, plus the sqlite, mock and sandbox implementations). `BarcodeInput` parses `sourceKind` and `sheetWeight`. | API surface (client), Tests |
| 35 | Production begins to leave `server.js` (module 15 of 15). `backend/test/production-api.test.js` pins runs (create, list, get, delete), node status through to a completed and booked run, batches, scrap, completed production runs, the machine queue and pipeline history. `modules/production/service.js` (`createProductionService`) takes twelve helpers whole: `rowToRun`, `getMergedNodeMetrics`, `rowToProductionRunDto`, `listCompletedProductionRuns`, `getProductionRunRowById`, `createRunFromTemplate`, `ensurePipelineRunRecord`, `upsertStageReconciliation`, `backfillStageReconciliations`, `ensureTemporarySetFromAssembly`, `stockTemporarySet`, `assignMaterialToRunNode`, plus `STAGE_RECON_COLUMNS`. It is built right after the jobs service; inventory is created later in the file and is handed in through `lateBound`, a proxy that resolves when used. Old names are kept in `server.js` by destructuring. | Services, Tests |
| 36 | Production step 2. `modules/production/routes.js` (`registerProductionRoutes`) takes the fifteen production routes whole: `/runs` (list, create, get, delete, node-status, barcodes POST/PUT/DELETE, node-metrics, batches), `/api/production-scrap` (two), `/api/production-runs/completed`, `/api/machines/:id/queue` and `/api/items/:id/pipeline-history`. URLs and guards are unchanged; the `app.use('/runs', …)` login and write guards stay in `server.js`, registered ahead of it. The 370-line node-status handler body becomes `setNodeStatus({ runId, payload, actor })` in the service, answering `{ run }` or `{ refusal }`. `server.js` is 19,700 lines. | API surface (unchanged paths), Orchestration, Services |
| 37 | Production step 3. `modules/production/ports.js` stops being read-only: `runs.dissolve` replaces the two deletes orders ran on `run_barcode_inputs` and `pipeline_runs` when an order line is deleted; `runs.inputCountForBarcode`, `runs.latestInputForBarcode`, `runs.rowById` and `runs.stagesForRun` replace inventory's reads for a material's summary and control tower; `output.sourceById` replaces the challan service's read of `production_runs` at dispatch. Left as read models: two list queries in `modules/orders/service.js` that join `pipeline_runs`, and the order and challan reports. | Ports, Services |
| 38 | Production step 4, the last module. Registry: `production.evacuated = true`, 15 of 15. Table claims corrected to who writes them: production owns `stage_reconciliations` (was listed under challans), challans owns `piece_barcodes` (was listed under production). `server.js` is 19,700 lines (35,760 at the start) and holds the kernel only: auth and gates, schema and `initDb`, seeds and demo scenarios, assets, search, the barcode resolver, the telemetry emitter, payroll. Deliberately open: production still writes `materials`, `inventory_sets` and, for a stage's leftover, `delivery_challans` rows itself, and reads `piece_barcodes` for a scanned sheet; two order list queries and the reports read production tables as read models. | Data, Ports |
| 39 | The outward reaches of production are closed. Inventory: `sets.recordProduced` (the temporary set an Assembly stage makes, with its stock; `recordProducedSet` and `stockTemporarySet` now live in the inventory service) and `receipts.mintLot` (finished output and scrap lots). Challans: `stageNotes.find/create/setQuantity/remove` (the internal leftover and scrap notes) and `sheets.findByCode`. Orders: `lines.row/summary/idsForOrderNo/idsForItem`. Production now owns `order_pipeline_assignments` (registry moved); `orderForRun` and `orderLineForRun` in the service replace five joins. In the other direction orders, inventory and the order and challan reports read runs only through `productionPorts.runs.*`; the order list's derived-status subquery is published by production as `orderItemRunStatusSql`, as text, because the list filters, counts and pages on it in one statement. No module other than production, the seeds and `initDb` names a production table. Master reads from production (items, units, machines, pipeline templates) remain. Tests: `production-order-links.test.js` and two more in `production-api.test.js`, all run against the previous commit as well. Found and pinned, not fixed: the order list returns the stored status because its wrapping `SELECT *` renames the derived `status` column. | Ports, Services, Data, Tests |
| 40 | Fix: the order list showed only the stored status. Its query selected `o.*` and the run-derived value both as `status`, and the wrapping `SELECT * FROM (…)` renamed the second one, so the list, its status filter and its search never saw the runs, while the single read did (runs always winning). Now one two-level select, `ORDER_ROW_SELECT` in `modules/orders/service.js`, computes `run_status` once (production's `orderItemRunStatusSql`) and `effective_status` by one rule: completed if the line is marked completed or every run is completed; otherwise delayed if marked delayed; otherwise whichever is further along (draft, notStarted, inProgress). `getOrders`, `countOrders`, `getOrderRowById`, the filter and the search all use it; rows carry `status` (shown), `stored_status` and `run_status` (DTO `runStatus`). `updateOrderLifecycle` checks a hand-made move against the stored status. No new announcing was needed: the `trg_derived_pipeline_runs_order_items_*` and `trg_derived_assignments_order_items_*` triggers (migration 041) already log the order line when a run or its link changes; a test now covers that. | Business rules, Services, Tests |
| 41 | Found while checking the merge on Node 18 from a clean copy: `test/payroll-api.test.js` and `test/portal-api.test.js` opened `backend/paper.db`, the developer's working database, directly. With that file present they wrote into it inside a rolled-back transaction; on a clean checkout sqlite created an empty file and both failed on a missing table, so `npm test` in the deploy workflow could not pass. Both are rewritten as ordinary tests on a temporary database. | Tests |
| 42 | Fix found by the pre-merge check on a copy of a real database. The one-time `variation_stock` rebuild only looked for the `CHECK (variation_leaf_node_id > 0)` shape. Real databases made earlier have no such CHECK but have the leaf as a foreign key into `item_variation_nodes`, which refuses leaf 0 just the same, so they were skipped and whole-item stock would have failed on them. `initDb` now rebuilds for either shape, in one transaction and without a table rename (a rename makes SQLite check every trigger, which fails on an empty database still being built); `whole-item-stock.test.js` covers both shapes and `empty-database-boot.test.js` the empty one. Verified on the copy: rebuilt once, rows and totals carried, second boot a no-op, 14 read endpoints answer. | Data, Tests |
| 43 | The 104 routes that belonged to no business module leave `server.js` for nine files: `modules/accounts/routes.js` (29: auth, users, me, admins, permissions, permission presets, record options), `assets` (16), `control_plane` (17), `units/master-routes.js` (11), `payroll` (9), `settings` (9: favourites, company profile, phone signals), `search` (6), `track` (5), `realtime` (2). Matching order is kept exactly: where each group's routes were, `server.js` mounts an empty router, and the group is registered into it further down where everything it uses exists; groups that sat before the login gate or after the mid-file error handler have their own function (`…RoutesBeforeLogin`, `…RoutesAfterErrorHandler`). Checked three ways: `remaining-routes-snapshot.test.js` (112 routes called anonymously and as owner, status and shape compared with before the move), a route-by-route comparison of the old and new stacks (same middleware ahead of all 371 routes; no two routes that swapped places can match one request), and a parser-based check that no handler uses a name it was not given (it found three the text scan missed). Handlers that read files take `serverDir`; the phone-signal routes take `getIo`. The route listers in `kernel/territory.js` and `route-surface.test.js` now walk mounted routers. Helpers these routes call are still in `server.js`. | API surface (unchanged paths), Orchestration, Tests |
| 44 | Why the staging deploy failed: seven tests in `assembly-job-dedupe.test.js` and `order-fulfilment.test.js` required the server by an absolute path on the developer's machine (`/Users/…/backend/server.js`). They passed there and failed on GitHub's runner, where the path does not exist, so `npm test` could not pass and nothing deployed. The same path also made a clean copy of the repository test the original instead of itself. Both now require `../server.js`, and `no-machine-paths.test.js` fails if any backend source or test names a home-directory path. The deploy workflow's failure summary now joins multi-line errors and leaves out lines every healthy boot logs. | Tests |
| 45 | The function level. `kernel/desk.js` keeps every module's operations: a named function with a declared input and a required permission, answering `{ ok, … }` or `{ ok: false, status, code, error }`. Three doors ask it: the terminal (`bin/paper.js`, `npm run paper -- <operation> key=value`), an HTTP handler, and another module through `desk.as('<module>')`. The desk checks who is asking: a user needs the operation's permission (the server's own `hasPermission`; a request the central gate already cleared for that exact key, per-record grants included, is not asked twice), a module needs the name in its `uses` list in `server.js`, an `internal` operation is never a user's, and the terminal is the operator at the machine. Everything stays in one process on one connection, so a call joins the caller's transaction. Converted: process routes (6 operations; `routes.js` no longer receives the database) and orders (6 for users, 10 internal). Order edit and delete left their handlers for `modules/orders/line-writes.js`, statements unchanged, minus the delete's insert into the nonexistent `activity_logs`. Every caller of the orders ports (clients and its portal, the party delete blockers, production, inventory) now asks the desk, which removed one `lateBound` proxy. `/api/kernel/territory` shows calls per operation. Not done: the other 13 modules, PO document operations, a per-client module switch (the system level). Tests: `kernel-desk.test.js` (14), `function-level.test.js` (7, including `paper` as a child process); 399 pass. | Kernel, Operations, Ports, Orchestration, Tests |
| 46 | Contracts first. The terminal program (`bin/paper.js`) is removed and the desk's `terminal` actor is now `system`. The desk checks an operation's result against a declared `output`, holds each operation in `report` mode (a violation is recorded at `/api/kernel/guard-alerts` and the call proceeds) or `enforce` mode (input refused with 400, a broken output throws), and publishes `catalogue()`, pinned by `contract-surface.test.js` (40 operations). `kernel/registry.js` gains `TABLE_OWNERS`: all 137 known tables have exactly one owner (29 had none; payroll's are listed as an unregistered module; four are created by old migrations and named by no code). `module-borders.test.js` scans every module folder's SQL for tables it does not own: 93 at the start, and the fixture may only shrink. Units is the first module taken to the full standard: `saveUnit`, `saveUnitGroup`, the conversion graph, `getUnitsWithUsage`, `getUnitRowById` and `ensureKgUnit` left `server.js` (16,947 → 16,620 lines) for `modules/units/master.js`; 15 operations with typed inputs and outputs; both route files ask the desk; a unit's usage is asked of inventory, items and orders (their first operations) instead of read from their tables, which took the crossings to 87. Inventory asks `units.rows.get` and challans `units.ensureKilogram` instead of being handed functions. Fixed on the way: seed-standard answered 500 after seeding; the converter was dead after a restart; `/api/unit-groups` was gated by no module (behaviour change: users without units rights are now refused); convert-batch needed `units.create`. Plan, checklist and bug log: `12-modules-as-services.md`. Tests: `units-operations.test.js` (6), `module-borders.test.js` (4), `contract-surface.test.js` (2); 412 pass. | Kernel, Operations, Data ownership, Services, API surface (two gate changes), Tests |
| 47 | The six small masters behind the desk. Each gets `modules/<name>/operations.js` and its master routes ask the desk: vendors (7 operations), clients and sub-contractors (14), people (9), machines (4), dies (4), pipeline templates (4); items gains `items.groups.name` and `items.rows.forCatalogue`. Typed inputs where the body has fixed fields, a declared output on every operation that returns data, all in `report` mode; the suite's ordinary use breaks none. A write's result carries the raw rows Track is written from, and the route still writes Track and broadcasts. Hand-offs replaced by declared desk calls: `getVendorRowById` and `getClientRowById` to challans, `getClientRowById` to orders, the people port to jobs. Foreign reads removed: the portal catalogue no longer joins `items`, a die asks `clients.exists`, a machine asks items for its group's name. Crossings 87 → 84. `kernel/desk-kit.js` holds what every operations and routes file was repeating. Left with their own handlers, each for a stated reason: client contacts, the portal, die makers, the three employee login routes (guarded by role), the older `/templates` set (guarded outside `/api`), machine and die photos (the kernel's asset service). Found, not fixed: a die created without status or ownership answers 500 with a raw database error; a sub-contractor update needs the name. Tests: `small-masters-operations.test.js` (4); 416 pass. | Operations, Orchestration, Ports, Tests |
| 48 | The small masters' leftovers. `kernel/desk.js` gains three ways to say who may ask besides `permission`: `access: 'signedIn'`, `access: { anyRole, anyPermission }` and `roles` on top, because some routes were never behind a module permission and an operation must ask exactly what its route's guard asked. With those: a company's contacts (`clients.contacts.*`, work in `modules/parties/contacts.js` as `createClientContactService`), the B2B portal (`clients.portal.*`, work in the new `modules/clients/portal.js`; its three POSTs ask what the old write gate asks), die makers (`dies.makers.*`, `createDieMakerService` in `die-makers.js`), an employee's login (`people.employees.createLogin/linkLogin/unlinkLogin`, admins only, the first also needing `users.create_user`), and the older `/templates` set (`pipelines.legacyTemplates.*`: any signed-in user reads, `config.write` changes). 24 more routes ask the desk; no HTTP answer changed. 107 operations. Found: portal passwords are stored and compared as plain text and a fixed test account signs in anywhere (kept, needs a decision); the portal routes' own comment said any signed-in session could use them, while the gate lets only an admin or a holder of `config.write` or `inventory.update` make a POST. Tests: two more in `small-masters-operations.test.js`, one in `kernel-desk.test.js`; 419 pass. | Kernel, Operations, Orchestration, Tests |
| 49 | Production behind the desk. Its handlers held the work: about 900 lines in 15 route bodies. They are now functions in `modules/production/work.js`, moved mechanically (a script rewrote each `res.status(x).json(y)` into `return answer(x, y)` and checked all 63 sites; one nested helper needed its callers to return what it returned). `operations.js` turns an answer into a result and `routes.js` (110 lines, was 1,150) sends it back as the same status and body. Fifteen operations for users, each asking what its route's guard asked: the `/runs` set outside `/api` is read by any signed-in user and changed with `config.write`; `/api/production-scrap` maps to no module, so the old write gate decides; a machine's queue is a machines read and an item's history an items read, because the gate goes by path. Nineteen internal operations publish `ports.js`; orders (order delete, reports), inventory, challans (service, reports), machines, dies and pipelines ask them at the desk with declared uses, and `production.runs.dissolve` and `unlinkOrderItem` are marked as joining the caller's transaction. Production in turn asks `pipelines.templates.row`, `machines.rows.get`, `items.rows.get` and `units.rows.get` instead of reading those tables. The one read it keeps, a join to `items` inside the finished-output search, is declared in the registry (`reads`) and the border meter marks it. Crossings 84 → 81. Still handed over as text: `orderItemRunStatusSql`. Tests: `production-operations.test.js` (4); 423 pass. | Operations, Services, Orchestration, Ports, Data ownership, Tests |
| 50 | Inventory behind the desk. `modules/inventory/work.js` holds the 22 handlers' bodies, moved by the same script as production's (52 response sites and 7 Track calls, all converted; no nested senders). A moved handler that wrote a Track entry now notes it with `req.track(...)`; the entries ride on the result and `deskRoutes` in `kernel/desk-kit.js` writes them with the real request, because Track reads the actor and the sitting from it. `kernel/desk-kit.js` gains `answer`, `plainRequest`, `answered`, `runMoved` and `deskRoutes`. What other modules ask of inventory is one list, `modules/inventory/asks.js`: 25 functions with their argument names and whether each joins the caller's transaction. From it, `operations.js` publishes internal operations (`inventory.movements.applyCore`, `inventory.receipts.mintFromChallanLine`, …) and `client.js` builds `inventoryClient(desk)`, an object shaped like `ports.js` whose every function asks the desk. Challans, orders, production and jobs are handed that client made from their own desk handle, so their code is unchanged and each call is checked against what they declared; two `lateBound` proxies are gone. The barcode lookup they were handed is `inventory.materials.rowByBarcode`. Inventory's own reads of eight foreign tables became asks: `items.rows.get`, `items.groups.row`, `items.groups.propertyNamesInUse`, `items.variations.node`, `items.variations.codeForValue`, `orders.items.demand`, `challans.rows.brief` (challans' first operation), `pipelines.templates.row`, `machines.rows.byAssetOrName`, `dies.rows.byToolCode`. Crossings 81 → 73. Two mistakes made and caught by the suite: a user operation and an internal one shared the name `inventory.movements.apply` (the user's is now `inventory.movements.record`, and a clash is refused when the operations are built), and `sources.propose` was called without `await`. Still by hand: items and the action centre, whose code is in `server.js`, call the ports directly, and inventory is still handed items' stock and group functions. Tests: `inventory-operations.test.js` (4); 427 pass. | Operations, Services, Orchestration, Ports, Kernel, Tests |
| 51 | Challans behind the desk. Four route files held 42 handlers and 1,609 lines; the move script now also handles named handlers registered on two paths (`/api/challans` and `/api/delivery-challans` reach one operation) and named functions. 101 response sites converted. Hand-fixed: three PDF responses answer with `answerFile` (`kernel/desk-kit.js`; the result carries `file`, `deskRoutes` sends it); issue and cancel sent their answer and then broadcast a stock change, so they now decide the answer, call `announceStockChange` (which cannot throw) and return it; three test-print wrappers return what the shared function returns; `barcodes` was imported at the top of the invoice routes and went to `invoice-work.js`. Route order inside `routes.js` is the original. Operations: 42 for users, each with the key `moduleOpForRequest` gives its path (issue, cancel, print, piece barcodes and the client statement are POSTs and ask for `challans.create`; settle asks for `challans.reconcile`; an order's challans and an order's reconciliation ask for `orders.read`), and 11 internal from `modules/challans/asks.js`. `operationsFromAsks`, `clientFromAsks` and `joinOperations` moved to `kernel/desk-kit.js` and inventory uses them too; a port that answers a Map says `returns: 'map'` and crosses as pairs. The vendor master, the party delete check, production and inventory hold `challansClient(desk)`. In the other direction challans no longer gets `getOrderRowById`, `updateOrderLifecycle` or `getProductionRunRowById` from `server.js`: it asks `orders.rows.get`, `orders.rows.byIds`, `orders.rows.forOrderNo`, `orders.lifecycle.move` and `production.output.row`; an order line's client GST number is two asks where it was a join; a line's unit is `items.rows.get` then `units.rows.get`; a template's party is `clients.rows.get` or `vendors.rows.get`. Two report joins stay and are declared in the registry (`order_items`, `inventory_movements`). Crossings 73 → 69. Still by hand: the reconcile's group and item helpers and the items stock functions, which are items code in `server.js`. Tests: `challans-operations.test.js` (5); 432 pass. | Operations, Services, Orchestration, Ports, Kernel, Data ownership, Tests |
| 52 | Items behind the desk at its borders. Four route sets, 43 handlers: `routes.js` (28) became `work.js`; `master-data.js` (5), `material-types.js` (4) and `sheet-properties.js` (6) keep their helpers and gain a work function beside thin routes. The move script now reads multi-line route declarations and keeps each route's own guards, so `guardContract(contracts.itemWrite)` still stands in front of item and group writes and `requireAssetEntityPermission` in front of a part's photos. Operations ask what stood in front of each route: `items.*` by method under /api/items, /api/groups and /api/item-sheet-properties; `items.asset.list` and `items.asset.upload` for photos; a signed-in session to read and the old write gate to change /api/material-types; a signed-in session for /api/pipelines/:id/master-data. `modules/items/asks.js` lists 16 functions (the ports, plus `groups.rowById` and `groups.save`); `itemsClient(desk)` replaces the ports and five functions `server.js` handed out by name, for production, challans, inventory, orders, vendors, search, the party delete check and the action centre. Items' own foreign reads became asks: an item read asks `pipelines.templates.row`, `clients.rows.get`, `clients.subContractors.row`, `clients.contacts.byIds`, `orders.items.usage`, `challans.items.lineCount` and `inventory.items.usage`; archiving uses the same usage sum; a group's delete check asks `inventory.groups.materialCount`; a part code asks `inventory.sets.name`; the group overview asks `units.rows.get` per unit; Master Data asks for the template row. One read stays and is declared: the overview and cover rankings sort by order counts inside the query. Crossings 69 → 59. Mistakes caught: `if (trackCreate)` guards left naming a variable that was gone (a test failed; a parser-based scan of every module file for names used and never declared now finds none), and a module-level cache of unit names that would have gone stale on rename (removed before it shipped). Not done: the items logic is still in `server.js`, and pure tree helpers and DTO mappers are still passed between modules as code. Tests: `items-operations.test.js` (5), including the old statement run beside the new read; 437 pass. | Operations, Services, Orchestration, Ports, Data ownership, Tests |
| 53 | The last two modules. `kernel/desk.js`: an operation may set both `access` and `permission`, and then both must hold; approving or rejecting a delete request sat behind the old write gate and its own `delete_requests.review`. Jobs: six handlers to `modules/jobs/work.js`; `/api/freelancer-jobs` and `/api/freelancer-portal` map to no module in the gate, so the operations ask for a signed-in session to read and the old write gate to change; `asks.js` and `client.js` publish `syncAssemblyJob` and `propagateAssemblyRejection`, and production holds the client in place of `jobsService`. Jobs no longer reads `item_bom_lines`, `materials` or `inventory_movements`: it asks `items.bom.lines` (the port answered an empty list until now), `inventory.materials.linkOf` and `inventory.movements.issuedToWorkerQty`. Action centre: eight handlers to `modules/action_center/work.js`; the CSV export answers with `answerFile`. The deleters in `server.js` no longer run SQL against other modules' tables: an approved request asks `vendors.rows.remove`, `machines.rows.remove`, `dies.rows.remove`, `challans.templates.remove`, `inventory.materials.deleteRecord`, `inventory.sets.deleteById` or `items.deleteWithCascade`; only a user account, which is the kernel's, is deleted in place. The integrity scan's nine joins across six modules are declared in the registry with one reason. Crossings 59 → 56, of which 13 are undeclared module reads (orders 11, process routes 2). All 15 modules publish operations: 343, of which 121 internal and 14 marked as joining the caller's transaction. Found: the freelancer portal token is encrypted with a key written in the source. Tests: `jobs-action-center-operations.test.js` (3); 440 pass. | Kernel, Operations, Orchestration, Ports, Data ownership, Tests |
| 54 | Contracts enforced. `kernel/desk.js`: `createDesk({ defaultMode, forceMode })`; an operation without a mode takes the desk's default, and `forceMode` overrides every operation's. An enforced input refusal is worded about the field (the operation's name is taken off the front of the message; the full paths stay in `problems`). `server.js` creates the desk with `defaultMode: 'enforce'` and `forceMode: 'report'` when `PAPER_CONTRACTS_MODE=report`; a violation is also appended to the file named by `PAPER_CONTRACT_VIOLATIONS_FILE`, because each test file boots its own server and the in-memory window is lost with it. Evidence gathered that way before the switch: the journey and all 440 tests in report mode, 9 violations in 7 operations (`units.create`, `units.update`, `units.families.create`, `units.families.update`, `clients.create`, `clients.subContractors.create`, `vendors.create`), every one a deliberately missing or empty name, none on a result. Loosened so that enforcing adds no rule the code did not have: a unit's conversion factor is a number (the master requires it above zero only for a unit in a family) and its type and a family's base unit carry no extra constraint; clients, vendors, sub-contractors and die makers leave "needs a name" to the service, which says it in its own words; list arguments the production ports treat as optional are optional. The Flutter request models for those masters were read against the contracts. Behaviour change: POST and PATCH on `/api/units` and `/api/unit-groups` with no name answer 400 "name is required" where they answered 500 (`remaining-routes-snapshot.json` updated). Not done: the same evidence from a real installation, and tightening the loose `any` contracts. Tests: one more in `kernel-desk.test.js`, one more in `units-operations.test.js`; 442 pass. | Kernel, Operations, API surface (four error answers), Tests |
| 55 | Three decisions carried out. (1) Removed, not guarded: `modules/control_plane/routes.js` loses the sandbox dashboard's ten routes, `GET /dashboard`, `POST /api/build/global` and `POST /dev/seed-manufacturing-demo`; `backend/dashboard.html` is deleted; `requireAuth` and the write gate no longer wave `/sandbox-dashboard` and `/build` through; `DataSyncService.syncUser` and its hook in `lib/main.dart` are gone. Kept, still without a login because an installed app calls them first: `/sandbox-config/:clientId`, `/api/sandbox-sync`, `/api/session-replay`, `/api/activation`, the update feed. Crossings 56 → 51 (the demo seeder wrote dies, machines, materials, templates and run inputs). (2) `modules/clients/portal.js`: `setCredentials` stores `hashPassword(password)`, `login` uses `verifyPassword`, `hashStoredPlainPasswords` converts older rows at start-up and before every login check, and the `test@example.com` account is removed here and in `apps/portal`. (3) `modules/jobs/portal-tokens.js`: a card token is `v2.<barcode>.<HMAC>` under a key derived from `PAPER_JWT_SECRET`; new `jobs.portalToken` behind `GET /api/freelancer-jobs/portal-token`; `JobCardPrinter` takes the token and the `encrypt` key is out of the app; tokens made with the old key are refused. Tests: jobs-api (old token and an edited token refused), clients-api (hash stored, plain row upgraded, no test account); 442 pass. | Control plane, Clients portal, Jobs, App (jobs screen, portal app), Tests |
| 56 | P0 of the approved plan. `main` fast-forwarded to `refactor/evacuate-masters` and pushed (deploys staging). `encrypt` removed from `pubspec.yaml` (nothing imported it since change 55). The tracking doc's change-log and decision rows dated 2026-11-19 corrected to 2026-11-18, and it gains the decisions of 2026-11-19, a staging watch list (guard alerts, reprinting job cards, the portal-password hashing log line) and the P1-P8 package table. No code change. | Docs |
| 57 | P1. Backend: `modules/control_plane/` deleted (`GET /sandbox-config/:clientId`, `POST /api/sandbox-sync/:clientId`, `POST /api/session-replay/:clientId`, `POST /api/activation/activate`, `DELETE /api/activate/:clientId/:fingerprint`, `GET /api/appcast/:clientId.xml`); `initDb` loses the six `sandbox_*` CREATE TABLEs and the default-config upsert; `requireAuth` and the write gate lose their path bypasses (`/config` matched no route); `kernel/territory.js` and `kernel/registry.js` lose the segments and tables; `feature_registry.json` and `test/config-defaults-sync.test.js` deleted. socket.io: `new Server`, the connection handler and `let io` removed from `server.js`, `socket.io` uninstalled; `getIo` hand-ins and every emit removed from `modules/items/work.js`, `challans/work.js` (`announceStockChange` gone), `clients/routes.js`, `vendors/routes.js`, `orders/routes.js`, `settings/routes.js` (the four `/api/mobile/*` relays still answer, now as no-ops), `parties/contacts.js` (`emit` option). Decision basis: `socket_io_client` was in two pubspecs but imported nowhere; the desktop `SocketService` is SSE over `/api/events` with a Bearer header. Desktop app: `lib/main.dart` loses the activation gate and `ActivationScreen`, `_skipActivation`, `DataSyncService` and `SessionReplayService` (init, tap `Listener`, `ReplayNavigatorObserver`); the four service/screen files deleted; `ConfigService.init` keeps the offline dev path and otherwise loads the built-in defaults, no fetch, no polling; `socket_io_client` removed from `packages/core_erp` and `apps/challan_mobile`. Route surface −6; 441 tests. Open: B32 (auto-updater has no feed), B33 (mobile relay endpoints are no-ops). | Control plane, Kernel, API surface, Realtime, App |
| 58 | P2 (B24). `backend/test/helpers/temp-dir.js` exports `makeTempDir(prefix)`: `fs.mkdtempSync(path.join(tmpdir(), prefix))`, every folder remembered and removed with `fs.rmSync(..., { recursive: true, force: true })` on `process.once('exit')`. A python rewrite replaced `mkdtempSync(path.join(tmpdir(), X))` (and one `mk(` alias) in 92 test files with `makeTempDir(X)`, dropped the `mkdtempSync`/`tmpdir` imports that became unused, and added the helper require after the last top-of-file require. The helper was first called `tempDir`, which collided with the files' own `const tempDir` (TDZ error in 340 tests); renamed. Verified: `npm test` → 441 pass and the system temp folder has no `paper-*` entries afterwards. | Tests |
| 59 | P3. New `backend/kernel/fields.js` (`text`, `int`, `num`, `flag`, `id` = integer > 0 required, `key` = non-empty string required, `list(items)`, `obj(fields)`, `none` = an object nothing is read from, `both(camel, snake, spec)`). `kernel/desk-kit.js` `plainRequest` defaults a missing body to `{}`. Every `operations.js` typed: items (the `itemWrite`/`groupWrite` contracts of `modules/items/contract.js` are now the desk contracts too, so a direct desk call is checked), inventory, challans (both spellings of each field, line and invoice-line objects, template fields), production (start, node status, metrics, batches, stock moves, scrap), jobs, action centre, and the `any` ids/payloads in clients (portal cart and order), dies, machines, orders (`save` and `edit` list every field the service and `editOrderLine` read; `statuses`/`ids` stay untyped because `toList` takes an array or a csv string), people, pipelines (template payload fields; ids are text), process routes. `test/contract-surface.test.js` gains "every field a user operation takes is typed, except the ones listed here on purpose" with eleven exceptions. Evidence run (`PAPER_CONTRACTS_MODE=report`, `PAPER_CONTRACT_VIOLATIONS_FILE`): 28 violations; the ones that were contracts stricter than code were loosened (`itemFormSections` and the section `tree` are objects, route steps may be ids, unit conversions answer per line, a challan id of 0 is the service's to refuse). One pinned answer changed in `small-masters-operations.test.js`: `machines.get {id:'nope'}` is 400 `input_invalid`, no longer 404. `contract-surface.json` re-recorded (+3,530/−556 lines); `remaining-routes-snapshot.json` unchanged. 442 pass. | Kernel, Operations, Tests |
| 60 | P4. New internal operations: `items.unitConversions.factor {itemId, unitId}`, `inventory.movements.consumedByRun {pipelineRunId}` (joins the caller's transaction: order-line delete), `challans.deliveries.byOrderLines` (the fulfilment report's grouped delivery rows), `challans.sheets.provenance {code}` (a consumed vendor sheet's reception and vendor), `dies.rows.all`, `machines.rows.all` (`allDieRows`/`allMachineRows` added to the services). `modules/orders/service.js`: the unit is `units.rows.get`, the conversion factor `items.unitConversions.factor`, the sub-contractor `clients.subContractors.row`; the order list's delivered-quantity subquery stays and is declared in `kernel/registry.js` (`orders.reads`). `line-writes.js`: client name/alias via `clients.rows.get`; consumed movements via inventory. `ports.js` (`createOrdersPorts` now takes `desk`): `lines.summary` reads its own two tables and asks for the client's name. `reports.js`: `orderHeader(orderNo, extra)` replaces the two header joins; machines, dies and templates come from their owners; the fulfilment grouping and the sheet provenance from challans. `modules/process_routes/service.js` takes `desk`: `pipelineNameFor` is `items.rows.get` + `items.groups.row` for the group and its parent; `partExists` is `items.rows.get`. `server.js` declares the uses. `test/module-borders.test.js` asserts `summary.moduleReadsModule === 0`. Fixture: 13 crossings removed, 2 added as declared. One pinned expectation changed in `units-operations.test.js` (orders may read a unit now; clients still may not). 442 pass. | Orders, Process routes, Challans, Items, Inventory, Dies, Machines, Kernel registry, Tests |
| 61 | P5. A python script cut 49 functions out of `server.js` by name (`^(async )?function NAME(` to the closing `}` at column 0, with the comment above) into `modules/items/`: `variation-tree.js` and `property-keys.js` are pure and export plain functions (inventory requires them too); `schema-props.js`, `developed-for.js`, `variations.js`, `dto.js`, `reads.js`, `save.js`, `deletes.js` are factories `(deps, api)` whose bodies are verbatim, with every sibling reached as `(...a) => api.sibling(...a)` and outside helpers (`get`, `all`, `run`, `logChange`, `parseJson`, `normalizeCustomVariationValues`, `trashAndDelete`, `markEntityAssetsDeleted`, thunks for `purgeEntityLinks`/`purgeEntityVariations`, the inventory client, `desk.as('items')`) from `deps`; `service.js` assembles them into one object. `server.js` builds it before `markEntityAssetsDeleted` and destructures the 42 names (the first attempt inserted the wiring at the line of the first cut, which by then was inside another function). Dead code dropped: the first `normalizePropertyKey`, `ensureItemRecord`, `findItemByDisplayName`, `getActiveChildGroups`. Inventory: `itemHelpers` and the three normalisers are gone from its wiring; it requires `../items/variation-tree` and `../items/property-keys` and asks `items.variationTree`, `items.rowById`, `items.resolveLeaf` (new in `asks.js`/`ports.js`). New owner operations for the single-row reads the move exposed: `units.rows.first`, `dies.rows.get`, `inventory.materials.firstForGroup`, `orders.items.usageRows`, `challans.items.usageRows`, `inventory.items.usageRows`. The list and DTO joins stay and are declared in `kernel/registry.js` (`items.reads`, eleven tables, B35). Trap met: the inventory client only has what `asks.js` lists, so `inventoryPorts.materials.firstForGroup` was a TypeError inside a seed, which left a transaction open and hung the suite; asked at the desk instead. `server.js` 16,707 → 14,019. 359 operations, 136 internal. 442 pass. | Items, Inventory, Units, Dies, Orders, Challans, Kernel registry, Tests |
| 62 | P6. Three kernel folders gain an `operations.js` and register at the desk: accounts (`accounts.users.get`, `accounts.users.byIds`, `accounts.users.setMobilePin`, the last inside the caller's transaction), assets (`assets.forEntity`, `assets.primaryFor`, `assets.attachUploaded` in the caller's transaction, `assets.sessionEntity`), links (`links.byRelation`, `links.remove`, `links.removeRelation`, `links.add`, the writes in the caller's transaction). Module side: `modules/people/service.js` reads its own employee rows and asks for the login accounts (`withLogin` keeps the `login_*` names the DTO reads), `people/operations.js` asks for the account and sets the staff code through accounts; `challans/service.js` asks for a challan's files and attaches a saved one, `challans/work.js` asks which record an upload session was for; `inventory/service.js` asks for a set's primary photo; `items/section-tree.js` takes `{ get, all, desk }` and reconciles a part's tree through links (its three callers in `save.js`, `work.js` and `links/routes.js` changed); `items/deletes.js` asks `links.removeRelation`. Kernel side: `accounts/routes.js` takes `desk`, its user delete asks `action_center.users.forget`, `orders.users.forget` (via `ports.forgetUser`) and `challans.users.forget` inside its transaction, and the user list asks `clients.rows.byIds` instead of joining; `search/routes.js` takes `desk` and asks `items.search.hits`, `items.search.configurations`, `inventory.materials.search` and `challans.pieceBarcodes.lookup`. `kernel/registry.js`: `user_favorite_items` moves from items to the kernel tables. `test/module-borders.test.js` asserts the two kernel counts are zero. Fixture: 24 crossings removed, none added; 26 declared reads remain. 378 operations (155 internal, 23 join the caller's transaction). 442 pass. | Kernel (accounts, assets, links, search), People, Challans, Inventory, Items, Orders, Action centre, Clients, Tests |
| 63 | P7 (stage 2c, B25). New `backend/kernel/db-kit.js`: `withTransaction(run, work, { rollbackWhen })` and `withSavepoint(run, name, work, { rollbackWhen })`; the default predicate undoes a result with `status >= 400` or a `refusal`. A python pass wrapped 28 functions by name (`return withSavepoint(run, 'NAME', async () => { …body… });`), one of them (`ensurePipelineRunRecord`, a multi-line destructured parameter) placed by hand. Seven `inventoryPorts.movements.apply({...})` inside production flows rewritten to `applyCore({...}, { useTransaction: false })`. `jobs.deleteJob` uses `withTransaction`; the handler's own `ROLLBACK` is gone. `cancelDeliveryChallan(id, actor, { dropInvoiceIds })` removes the cascaded draft invoices inside its transaction (and still before the early return of a partly used reception). `kernel/desk.js` gains `trip(name, error)`. Tests: `kernel-db-kit.test.js` on an in-memory SQLite (commit, rollback on throw, rollback on an answered failure, a savepoint alone, nested savepoints, a safe name); `transactions-atomic.test.js` trips `challans.stageNotes.create` under a scrap recording and finds no scrap row, lot, movement or note, then records it whole. 449 pass. | Kernel, Production, Inventory, Jobs, Challans, Tests |
| 64 | P8 (stage 2d). `backend/test/schema-snapshot.test.js` + `fixtures/schema-snapshot.json`: `sqlite_master` (type, name, table, whitespace-folded sql) after `runMigrations()` + `initDb()` on an empty file, and after `initDb()` on a file built from `001-init.sql` with `_migrations` and `schema_migrations` marked complete; re-recorded only with `UPDATE_SCHEMA_SNAPSHOT=1`. A python pass split `initDb` into 454 top-level units, tagged each by the table its CREATE TABLE / INDEX / `ensureColumnExists` / one-line ALTER names, mapped the table to its owner through `registry.TABLE_OWNERS`, and moved the plain ones (349) in original order into `modules/<owner>/schema.js` (`createSchema({ run, all })`; `ensureColumnExists` from the new `kernel/schema-kit.js`, which `server.js` now wraps). Tables a rebuild or seed block in `initDb` reshapes keep every statement there (74, B37), as do the nine triggers. `const SCHEMA_ORDER` names eleven files, kernel first; `initDb` runs them right after `DROP TABLE IF EXISTS orders`: placed at the first moved statement instead, the oracle's fresh path changed eight objects (the module CREATEs were no-ops on the migration-built tables, the stale-drop then removed them, and the end-of-boot runner recreated the old shapes). 450 pass. | Kernel, Schema (every module), Tests |
| 65 | B33. `POST /api/mobile/stage-item`, `remove-staged-item`, `lock-inventory`, `challan-generated` removed (`registerSettingsRoutesAfterErrorHandler` and its router in `server.js` with them). They emitted SSE `custom-event`s; the desktop's `SocketService` dispatches custom events, but no provider listens for `item_staged`, `item_removed` or `inventory_locked`, and the one that listens for `challan_generated_ok` (challans, inventory) gets challan changes from the changelog anyway. Mobile: `SocketService` loses `stageItem`, `removeStagedItem`, `seedDemoManufacturing`; the staging screen keeps its local list and loses the "demo-prod" button (its route was removed in change 55). Route surface −4. 450 pass. | Settings, Mobile app, API surface |
| 66 | B36. New internal operations, all joining the caller's transaction: `jobs.runs.forget {runId}` (tasks, then jobs, of a run), `challans.orderLines.forget {orderItemId}` (`delivery_challan_order_items`), `items.dies.forget {dieId}` and `items.machines.forget {machineId}` (`item_dies`, `item_machines`). Asked by: `production/work.js` `deleteRun` and the `production.runs.dissolve` operation (which now takes `desk`); `orders/line-writes.js` `deleteOrderLine` before its `DELETE FROM order_items`; the `dies.delete`/`dies.rows.remove` and `machines.delete`/`machines.rows.remove` operations. `jobs`, `items` operations take `run`. Uses declared for production, orders, dies, machines. Finding recorded in B36: only the trash uses the foreign-keys-off connection, deliberately. Test `cascades-explicit.test.js` turns foreign keys off on the main connection and checks every dependent row is gone. 453 pass. | Jobs, Challans, Items, Production, Orders, Dies, Machines, Tests |
| 67 | B37. 23 content-anchored segments of `initDb` (the groups NOT-NULL rebuild, the variation_stock rebuild with its column list, the CREATEs of groups, items, clients, vendors, inventory_stock_positions, freelancer_job_batches/jobs/tasks, pipeline_templates, machines, piece_barcodes, their ALTERs, `ensureColumnExists` calls and indexes, the uploaded-asset column loop, auth_sessions' column) plus the employees ALTER block moved, in order, to the end of each owner's `createSchema` (which now takes `get` for the rebuild). New `schema.js` for vendors, machines, pipelines, jobs; `SCHEMA_ORDER` has 15 entries. `initDb` keeps `repairGroupsOldMigrationRefs`, the stale-orders drop, the leaf and guard triggers, the order-line and materials data updates, `migrateOrderActivityLogCompatibilityColumns`, `ensureDeliveryChallanItemNumericColumns`, `ensureInventorySetLineNullableLeafReference`, the seeds and `runPendingMigrations`. Orphaned comments were matched to their statements through the pre-split `initDb` (git 836c04b) and placed above them in the schema files. `server.js` 12,378 → 11,963. 453 pass. | Schema (every module), Kernel |
| 68 | B32. Server: `GET /api/app/latest` (behind `requireAuth` like all of `/api`) answers `{ latestVersion, downloadUrl }` from `PAPER_DESKTOP_LATEST_VERSION` and `PAPER_DESKTOP_DOWNLOAD_URL`, null when unset. App: `AutoUpdaterService.initialize` (fed by the sandbox config) replaced by `checkWithServer(baseUrl, client)`, called from `_refreshAfterAuthentication` with an authenticated client; Windows only; a version that differs is installed, so naming an older one rolls back. Test `app-update-feed.test.js`. 455 pass. | Settings, Desktop app |
| 69 | Step 1 of the wire plan. `test/wire-budget.test.js` replays the desktop's cold sign-in (21 GETs, traced provider by provider), the orders and items list pages, inventory's four refresh calls and the replica's 13 list GETs plus first delta poll, against budgets of requests and compressed bytes; `test/helpers/sized-workspace.js` fills a seeded server to a few hundred rows per master through the API first, because the demo seed is 11 KB and no budget would trip on it. Measured: sign-in 57.3 KB; sign_in (21 > 20), inventory_overview (4 > 1) and replica_hydration (14 > 3) are pending on steps 3 and 5 and assert they are still over until then. 460 tests. | Tests |
| 70 | Step 2 of the wire plan. `InventoryProvider` starts materials, variation stock and sets together and reads health after (its fallback reads the materials); `refresh()` called during a refresh returns one shared follow-up run. `UnitsProvider` and `ActionCenterProvider` start their two reads before awaiting either. Mobile `main.dart`: no refresh in the nine ProxyProvider `update`s; `_AuthGate` refreshes once per session (token, or user id in the demo build) and now includes favourites and challans; `HomeScreen` and `InventoryStockScreen` no longer reload on mount. `MyApp` takes `httpClient` and `demoMode` so a test can count requests. B39: `_runSetWrite` lowers its guard after `_loadMembership`, in a `finally`. Tests: `startup_requests_test.dart`, `inventory_provider_refresh_test.dart`; the mobile smoke test looks for the passcode screen it actually opens on. | App, Tests |
| 71 | Step 3 of the wire plan. Backend: `work.overview` composes `listMaterials`, `stock`, `listSets` and `health` in parallel; operation `inventory.overview` with an output contract; route `GET /api/inventory/overview` with `cacheMasterData`. `test/inventory-overview.test.js`: every part deep-equals its own endpoint, `?materials=0` drops only the materials, ETag gives 304 until a movement. Client: `InventoryOverview` + `InventoryOverviewReader` in `inventory_repository.dart`; `ApiInventoryRepository.getOverview` (stock parser lifted to `_stockFromJson`); `LocalFirstInventoryRepository.getOverview` reads materials off the replica and asks for the rest; `InventoryProvider._loadEverything` uses it via a type pattern, and the health estimate became `_estimatedHealth()`. `wire-budget.test.js`: sign_in and inventory_overview out of PENDING. | Backend, App, Tests |
| 72 | Step 4 of the wire plan, the safe part. `modules/items/work.js` `listItems` maps each tree through `listNode`, which drops `createdAt`, `updatedAt`, `itemId`, `position`, `isArchived` from every node; `GET /api/items/:id` is unchanged. Traced: no Dart reader of those on a node, none in `ItemVariationNodeRequest`, the replica mirror reads only `item_id`. `wire-weight.test.js`: a list row deep-equals its detail row less those five, and `code`, `nameJoin`, `materialTypeId`, `parentNodeId`, `displayName` survive. B40, B41, B42 logged. | Backend, Tests |
| 73 | Step 5 of the wire plan. Backend `modules/realtime/routes.js`: `REPLICA_LISTS`, `firstList`, `GET /api/replica/bootstrap` (head before lists; loopback fetches with the caller's authorization; `missing` and `refused`). Client: `replica_catch_up.dart` (`ChangesPage`, `ReplicaBootstrap`, `ReplicaCatchUp.run`); `ReplicaApi.fetchChangesPage` / `fetchBootstrap` / `parseChanges`; `DeltaSyncEngine` gets `_replaceTable` (with the node mirror), `applyListRows`, a chunked `hydrateLists`; `ReplicaSyncService.catchUp` and `resync` go through `ReplicaCatchUp`, and `_drain` withholds the cursor while `_catchingUp`; `SocketService` emits `changelogId` per block; `lib/main.dart` passes it and wires the two new fetchers. Tests: `replica-bootstrap.test.js`, `replica_catch_up_test.dart` (9). | Backend, App, Tests |
| 74 | B43. `ReplicaSyncService.isHydrated` returns `_hydrated && !_catchingUp`. Found designing step 6: once B41 kept the cursor, every local-first read at sign-in would have come from the replica before the launch replay applied. | App |
| 75 | Step 6 of the wire plan. New `core/sync/replica_freshness.dart`; `ReplicaReader` consults it and offers `wrote(table)`; `ReplicaSyncService.onTableChange` marks, `_drain` snapshots then clears, `start` resets. New decorators: `local_first_{client,vendor,unit,group}_repository.dart`, `local_first_departments_repository.dart` (core_erp), `lib/features/{machines,dies}/data/local_first_*_repository.dart`; vendors, machines and dies expose their parsers as `vendorFromJson` / `machineFromJson` / `dieFromJson`. `lib/main.dart` wires all seven (demo mode stays on the API repositories). The items, orders, challans and inventory decorators route their writes through `_wrote`. | App, Tests |
| 76 | Step 7 of the wire plan, the cache. `apps/challan_mobile/lib/main.dart`: `MyApp.cacheFor` keeps one `ConditionalCacheClient` per inner client (an `Expando`), every repository's `AuthenticatedHttpClient` wraps it, `_AuthGate` takes it and sets `namespace` to the user on sign-in; `MyApp.cacheDirectory` so a widget test avoids real file I/O. Test: a second `/api/units` carries `If-None-Match` and the 304 replays the list. | Mobile, Tests |
| 77 | Step 9 of the wire plan: `Docs/architecture/12-modules-as-services.md` § "When to extract a service" (triggers, precondition with the 27 transactional operations by module, order of work, the off-the-table list). Step 8 held for a decision with the facts in its checklist line. | Docs |
| 78 | Step 8 of the wire plan dropped by decision; the checklist line records why. | Docs |
| 79 | B42. `items_provider.dart`: `_currentForSave` (via `fetchFresh`) replaces the list lookup in `addUnitConversion`, `appendVariationValue`, `appendTopLevelPropertyWithValue`, `appendTopLevelProperty`, `_updateOneField`; `_saveReadFailure` carries the reason. `item_sheet_binding.dart` `saveRow` fetches the existing part. `items_screen.dart`: `_FullItemRecord` around `openEditor` and the workflow details pane (variant rows already hold server rows). | App, Tests |
| 80 | Step 4 finished. `modules/items/work.js` `listItems` omits `attachments` and, when empty, `cadFileKey`/`cadFileName`. `wire-weight.test.js`: list row == detail row less those and the five node fields; a part with a CAD file keeps it on the list; `unitConversions` asserted present. | Backend, Tests |
| 81 | Step 7 finished. Backend `realtime/routes.js`: bootstrap `?tables=`. Core: `replica_session.dart` (`ReplicaSession.start`, `lastSyncedAt`), `ReplicaCatchUp.inScope`, `ReplicaSyncService(tables:)`, `ReplicaApi.fetchBootstrap(tables:)`, `SocketService.streamLive`. Desktop `lib/main.dart`: `startReplicaSync` delegates to the session; first load awaits it (3 s). Phone `main.dart`: eight local-first repositories, `kPhoneReplicaTables`, session at sign-in, first load awaits it; `widgets/offline_banner.dart`. Tests: bootstrap subset, scoped catch-up, three banner tests. | Backend, App, Mobile, Tests |
| 82 | B44, B45. Core: `AuthUser.toJson` (no PIN), `AuthProvider.clearError/signInOffline/isOffline/lastFailureWasUnreachable` and a 10 s PIN-login timeout; `ConditionalCacheClient` stale fallback (`x-paper-cache: stale`, `staleServed`); `ReplicaSession` `catchUp:` and a `streamLive` listener. Phone: `services/offline_unlock.dart`, `NetworkDiscoveryService` remembers/forgets the server, `PasscodeScreen` inline error + Try again + Change server + offline fallback (scrolls on short screens), `_AuthGate` without the error page, `crypto` dependency. Tests: offline_unlock (5), passcode_offline (6), server_memory (4), cache stale (4). | Core, Mobile, Tests |
| 83 | Stage 2f Track 2, server. `kernel/idempotency.js` (middleware, `beforeCommit`, `recover`, `prune`, schema); `server.js`: `rawRun` + a `run` that calls `idempotency.beforeCommit()` before COMMIT/END, the middleware after the permission checks on `/api`, `recover()` at boot and an hourly prune; `modules/kernel/schema.js` creates `idempotency_log`; registry kernel table. `test/idempotency.test.js` (12). | Kernel, Tests |
| 84 | Stage 2f Track 1. `backend/test/benchmarks/{throttle-proxy,network-throttle}.js`, `test/throttle-proxy.test.js`, `npm run bench:network`, `Docs/benchmarks/2026-11-constrained-network-results.md`. Fixes it drove: `items/dto.js` (`RELATED` queries shared by one-part and list reads, `preloadRelated`, `rowsToItemDtos`), `variations.js` `getItemVariationTrees`, `schema-props.js` `getItemPropertySchemas`, `challans/service.js` `preloadChallanSummaries`/`rowsToDeliveryChallanSummaries`, `assets.forEntities`; indexes on order_items, delivery_challan_items, order_material_requirements (item_id), item_variation_nodes, item_property_schema. `kernel/db-timing.js` + `run/get/all` instrumented. Tests: `challan-list-batch.test.js`, stronger `wire-weight.test.js`. | Backend, Kernel, Tests, Docs |
| 85 | Stage 2f Track 2, client. `packages/core_erp/lib/core/sync/outbox.dart` (`OutboxStore`: table `client_outbox` in its own SQLite file per user, `recover` puts cut-off sends back, `prune`; `OutboxSyncEngine`: `submit`, single-flight `drain`, strict FIFO, backoff 1 s doubling to 30 s, entry id as `X-Idempotency-Key`, `{ref:<id>}` endpoints resolved to the parent's server id, 2xx and `idempotency_already_applied` settle it, `in_progress`/401/5xx/network back off, any other refusal is a conflict, `retry`/`discard`); `outbox_session.dart` (one per user, drains when `SocketService.streamLive` comes up). `LocalFirstChallanRepository`: `createChallan`/`issueChallan` through the outbox, pending challans (negative id, "Pending upload") lead the list, kept even when the server part of the list cannot be read (B49). `DeliveryChallan.outboxId/outboxState/outboxError`. Both apps start the session at sign-in; the phone's Challan Book shows Pending sync / Needs review with Send again and Discard; editor, purchase wizard and vendor return say "saved on this phone"; the photo step scrolls (B52). Tests: `outbox_sync_engine_test.dart` (8), `outbox_challan_repository_test.dart` (5). | Sync, Challans, Mobile, Tests |
| 86 | B50, B51, B53. `ReplicaSession.changedTables` relays `ReplicaSyncService.changedTables`; `ItemsProvider(replicaChanges:)` re-reads on `local_items` (one at a time, a burst costs one more), the phone passes it. `LocalFirstChallanRepository(currentUserId:)`: on an unreachable server, `_fromCopy` reads `local_delivery_challans` filtered by type and `created_by`, pending first; both apps pass the signed-in user. `DeliveryChallanItem.weightUnitSymbol`; the purchase wizard's three weight labels use it. Tests: `items_provider_replica_changes_test.dart` (4), two more in `outbox_challan_repository_test.dart`. | Sync, Items, Challans, Mobile, Tests |
| 87 | Stage 2f Track 3. Backend: `kernel/telemetry.js` (`createTelemetry`: middleware before compression, `timedWrite` in `rawRun`/`runOnDelete`, `watchConnection`/`unwatchConnection` for the profile hook, `checkpoint`/`startCheckpoints`, `snapshot`, `prometheus`), `kernel/system-routes.js`, `server.js` (`serverTelemetry`, `startServerTelemetry`/`stopServerTelemetry` in the boot path, `systemBeforeLoginRouter`), registry: `system` excluded from the module gate. Client: `core/sync/sync_health.dart`, `features/sync_health/sync_health_screen.dart`, `OutboxSyncEngine.flushNow`, `ReplicaSession.cursor`; phone app-bar button + `Provider<SyncHealthProbe>` after AuthProvider + `package_info_plus`; desktop Settings pane + sidebar button. B54 `serverUrlFrom`. Tests: `system-telemetry.test.js`, `sync_health_test.dart`, `sync_health_sidebar_test.dart`, `sync_health_entry_test.dart`, `server_url_test.dart`. | Kernel, Sync, Mobile, Desktop shell, Tests |
| 88 | Stage 2f Track 4. Backend: `kernel/backup.js` (`createBackups`: backup, verify, list, prune, schedule), `kernel/pin-hash.js` (`createPinHasher`, `resolvePinKey`, `migrate`), `server.js` (`serverBackups` + schedule in the boot path, `pinHasher` in every PIN read/write, `initDb` converts plain PINs, DTO `hasMobilePin` / one-time `mobilePin`), `kernel/system-routes.js` (`/api/system/backups`), accounts (`POST /api/users/:id/mobile-pin`, login hashes the typed PIN, `setMobilePin` hashes), people (`hasLoginCode`), `scripts/backup-sqlite.js` + `restore-sqlite.js` rewritten on the kernel, `scripts/backup-db.sh`. Client: `AuthUser.hasMobilePin`, `EmployeeLogin.hasLoginCode`, `AuthApi/AuthProvider.issueMobilePin`, employee panel New phone PIN, My Account "Phone PIN set"; phone `widgets/phone_settings_sheet.dart` (`PhoneSession`, `signOutPhone`). Tests: `backup-restore.test.js`, `mobile-pin-hash.test.js`, `phone_settings_sheet_test.dart`; `people-api` and `my_account_dialog` tests updated. | Kernel, Accounts, People, Scripts, Mobile, Tests |
| 89 | B59. `kernel/pin-throttle.js` (`createPinThrottle`: `begin` / `succeeded` / `failed`, bounded map swept every 256 calls); `modules/accounts/routes.js` PIN branch: 429 + Retry-After when blocked, one `login_pin_throttled` event per block, right PIN releases its slot, wrong PIN awaits the tarpit before 401; `server.js` passes it in with `PAPER_PIN_TARPIT_MS`. Test: `pin-throttle.test.js`. | Accounts, Kernel, Tests |
| 90 | B60 guard. `ColumnDef.identity` (Alloy, Thickness), `SheetEngine.identityValue/cellLabel`, `ItemMasterController.confirmIdentityChange` + `identityChangesOf`, asked in `commitRow` and `saveItem`; screen dialog. Test: `sheet_identity_guard_test.dart`. | Sheet, Tests |
| 91 | B60 → B. Backend `part-identity.js` (`IDENTITY_PROPERTIES`, `identityValue`, `identityOfTree`, `sameIdentity`, `describeIdentity`), `reads.js` `findItemDuplicate({identity})` + `storedIdentity`, `save.js` passes it and names it in the 409. Sheet: `SheetEngine.identityKey/identityKeyOf` in the duplicate rule, `SheetController._forgetOwnIdentities` from captured identities (B61) + `takeIdentityOf`, binding `existingPaths` by identity and Part Name option detail; guard gains Make a new part (`_asNewPart`); `_saveRawSheet` saves the row first and reads the part after (B62). Tests: `part-identity-alloy-thickness.test.js` (4), guard test +4, two screen tests. | Masters, Sheet, Tests |
| 92 | `ItemMasterController._asNewPart` claims and resets the deal for the row; `_saveRawSheet` saves no plan when the row became another part (toast says its raw sheet starts empty). Tests: guard test +2 (edited deal not carried; Change this part keeps it), screen test now expects no plan. | Sheet, Tests |
| 93 | B63. `ItemMasterController._pickExisting` opens a part from a new row only on matching alloy and thickness (`_identityCellsMatch`); `_openMatchingPart` (from `_onRowsChanged`) opens a part once a new row's full identity matches one; the loading body is `_openPart`. Test: `sheet_pick_identity_test.dart`. | Sheet, Tests |
| 94 | Phone photos. core_erp `core/media/photo_crop.dart` (`cropPhoto`, `kWholePhoto`) + `photo_crop_screen.dart`; phone `photos/zoom_preview.dart`, `photos/shoot_photo.dart` (`shootPhoto`, `photoFromCrop`, `photoContentType`), `CaptureSource.zoomRange/setZoom`, `PhotoCaptureScreen` Crop button + zoomable preview, purchase wizard and editor use `shootPhoto`. B65. Tests: `photo_crop_test.dart` (7), `photo_zoom_crop_test.dart` (8), capture test +1. | Mobile, Media, Tests |
| 95 | Part tabs on the item sheet. core_erp `sheet/widgets/part_tabs.dart` (`PartTabs`, `PartTabColors`, `PartFrame`), `SoftErpTheme.partTabGradients`, `PartRowsForm.currentRowOnly`, screen `_partArea` / `_stepPart`; `SheetStep` lets Ctrl+Tab through. Drawing only: rows, saves and guards unchanged. Tests: 6 in `item_master_sheet_screen_test.dart` ("the parts are tabs"), 2 updated. | Sheet, Theme, Tests |
| 96 | B64. core_erp `core/sync/workspace_namespace.dart`; `lib/main.dart` and the phone's `main.dart` use it for cache, replica and outbox; `ReplicaCatchUp.run` resets when the cursor is past `head`. Part tabs: `PartFrame` replaced by `PartFramePainter` (joined outline), `PartTabs` takes the sheet as `child`. Tests: `workspace_namespace_test.dart` (4), catch-up +1, outline +1; `app_boot_test.dart` assertion. | Sync, Mobile, Sheet, Tests |
