# Paper ERP — Identifier Atlas

_A census of every identifier the app assigns — database keys, business sequence codes, barcodes, session tokens, and the frontend fields that carry them. Generated from a static read of `backend/server.js` and `packages/core_erp`; line references point at definitions/generators. ⚙ = internal rowid, never shown to users._

**243 identifier types** · 118 DB keys · 28 generated · 15 barcodes · 13 identity · 69 frontend fields

## Quick reference — the headline IDs

| ID | Field | Format | How it's made |
|---|---|---|---|
| **Order** | `order_headers.order_no` | `free text (TEXT PK)` | user-entered — not generated |
| **Item** | `items.id` | `int⚙` | SQLite rowid; shown via display_name |
| **Production run** | `production_runs.run_code` | `RUN-XXXXXXXX / RUN-0001 / MFG-0001` | first 8 of pipeline id, uppercased |
| **Pipeline run** | `pipeline_runs.id` | `run-<epochMs>` | `run-${Date.now()}` |
| **Pipeline template** | `pipeline_templates.id` | `slug (dolly, aluminum-anodize-line)` | authored / seeded |
| **Challan** | `delivery_challans.challan_no` | `DC- / RC- / IC-#####` | DB-sequenced (+1, zero-padded 5) |
| **Invoice** | `invoice_headers.invoice_no` | `INV-#####` | DB-sequenced |
| **Material barcode** | `materials.barcode` | `RAW-MLL-ANO · MAT-<ts>-<rand> · PAR-/CHD-` | variation codes joined, else timestamp |
| **Inventory movement** | `inventory_movements.id` | `mov-<ts>-<rand>` | `mov-${Date.now()}-${rand}` |
| **Session** | `auth_sessions.id` | `sess-<uuid> (+ HS256 JWT)` | `crypto.randomUUID()` |

## ID schemes (the ones with a shape)

### Human-facing sequences

| Name | Field | Format | Example | Generation | Location |
|---|---|---|---|---|---|
| Production Run Code | `production_runs.run_code` | `'RUN-XXXXXXXX' (first 8 of run id, upper) \| 'RUN-0001' \| 'MFG-0001'` | `RUN-1721140800` | Backend-generated. On pipeline completion: `RUN-${pipelineRunId.substring(0,8).toUpperCase()}` (server.js:23027), guarded by a uniqueness SELECT (:23030). Order-seed path: `RUN-${(index+1).padStart(4,'0')}` (:9663). Manufacturing demo seed: literal 'MFG-0001' (:24323). | `backend/server.js:3538 (def, UNIQUE); :23027 (gen from pipeline run id); :9663 & :24323 (seed variants)` |
| Delivery / Reception / Internal Challan number | `challan_no` | `<DC\|RC\|IC>-<5digit zero-padded sequence>` | `DC-00001, RC-00042, IC-00007` | generateChallanNumber(type): prefix = reception?'RC':(internal?'IC':'DC'); SELECT last challan_no LIKE '<prefix>-%' ORDER BY id DESC; next = match?(Number(match[1])+1):1; return `${prefix}-${String(next).padStart(5,'0')}`; | `backend/server.js:7869-7887 (called at 9962 createOrUpdateDeliveryChallan, 23382, 23505 internal challans)` |
| Invoice number | `invoice_no` | `INV-<5digit zero-padded sequence>` | `INV-00001` | generateInvoiceNumber(): SELECT invoice_no LIKE 'INV-%' ORDER BY id DESC LIMIT 1; next = match?(Number(match[1])+1):1; return `INV-${String(next).padStart(5,'0')}`; | `backend/server.js:10730-10743 (called at 10762 createInvoice)` |
| Production run code (demo backfill) | `run_code` | `RUN-<4digit zero-padded index>` | `RUN-0001` | ensureDemoProductionRunsPresent(): `RUN-${String(index + 1).padStart(4, '0')}` for each seeded order slice. | `backend/server.js:9663 (loop 9652-9678)` |
| Production run code (from pipeline run) | `run_code` | `RUN-<first 8 chars of pipeline run id, uppercased>` | `RUN-RUN-1789  (from pipeline run id 'run-1789000000000')` | const runCode = `RUN-${req.params.id.substring(0, 8).toUpperCase()}`; then existence-checked against production_runs before insert. | `backend/server.js:23027 (insert 23032-23039)` |
| Production run code (hardcoded demo seed) | `run_code` | `MFG-<4digit> (single hardcoded literal)` | `MFG-0001` | productionSeeds.push({ runCode: 'MFG-0001', ... }); existence-checked, then INSERT INTO production_runs. | `backend/server.js:24323 (insert 24340-24346)` |
| B2B portal order number | `order_no` | `B2B-ORD-<epochMs>` | `B2B-ORD-1789000000000` | const orderNo = 'B2B-ORD-' + Date.now(); | `backend/server.js:25023 (insert 25026)` |
| Report group / order reference code | `reportGroupCode (source_reference)` | `ORD-<orderId>  \|  ORDSET-<id>-<id>-...` | `ORD-42  \|  ORDSET-42-43-58` | deriveReportGroupCodesFromOrderIds(orderIds): 1 id -> `ORD-${normalizedOrderIds[0]}`; multiple -> `ORDSET-${normalizedOrderIds.join('-')}`. | `backend/server.js:7576, 7578 (deriveReportGroupCodesFromOrderIds 7564-7579)` |
| Challan template PDF display reference | `displayId (REF)` | `REF: <5digit zero-padded challan row id>` | `REF: 00042` | const displayId = `REF: ${String(challanDto.id \|\| challanRow?.id \|\| 0).padStart(5, '0')}`; | `backend/server.js:9204 (generateChallanTemplatePdf)` |
| Procurement Request Number _(edge)_ | `request_number` | `TEXT, UNIQUE. Format not yet fixed by any generator (likely a human-facing PR-###### style code, by analogy to INV-/DC- schemes).` | `(none produced at runtime yet; declared column only)` | Declared as a UNIQUE business key but there is NO INSERT INTO procurement_requests or request_number generator anywhere in server.js (route layer appears unimplemented in the current runtime). Value would be supplied/generated when the procurement feature is wired up. | `backend/server.js:4270 ; also backend/migrations/001-init.sql:415 ; backend/schema.txt:416` |

### Barcodes, codes & lots

| Name | Field | Format | Example | Generation | Location |
|---|---|---|---|---|---|
| Variation-Code Composed Material Barcode | `barcode` | `<code1>-<code2>-...-<codeN>  where each codeK = item_variation_nodes.code of a selected value node, ordered by parent-property position; separator = '-'` | `RAW-MLL-ANO  (or  DRW-INS)` | backend-generated by generateBarcodeFromItemSelection(itemId, customVariationValues): for each {propertyName: valueName} pair it looks up the selected value node's `code` via a self-join of item_variation_nodes (value v JOIN its parent property p), sorts the found codes by the parent property's `position`, and joins the codes with '-'. Returns null if no codes resolve. This is the PREFERRED barcode; only if it is null does the MAT- fallback run. | `backend/server.js:9769-9786 (generateBarcodeFromItemSelection); consumed at 9804 inside ensureMaterialForItemSelection` |
| Standalone Material Barcode (timestamp fallback) | `barcode` | `MAT-<epochMillis>-<rand[0..99999], zero-padded to 5>` | `MAT-1721145600000-04213` | backend-generated by generateStandaloneMaterialBarcode(): concatenates the literal 'MAT-', Date.now() epoch milliseconds, '-', and Math.floor(Math.random()*100000) zero-padded to 5 digits. Used as fallback in ensureMaterialForItemSelection when generateBarcodeFromItemSelection returns null (no variation codes). | `backend/server.js:9788-9792 (generateStandaloneMaterialBarcode); invoked at 9805-9806` |
| Collision-Disambiguated Material Barcode | `barcode` | `<composedBarcode>-<rand[0..999], zero-padded to 3>` | `RAW-MLL-ANO-042` | backend-generated: after generateBarcodeFromItemSelection produces a code-chain barcode, ensureMaterialForItemSelection checks getMaterialRowByBarcode; if a DIFFERENT material already holds that barcode (a collision not caught by findMaterialByItemSelection), it appends '-' + Math.floor(Math.random()*1000) zero-padded to 3 digits. | `backend/server.js:9808-9814` |
| Parent (Group) Material Barcode | `barcode` | `PAR-<epochMillis>-<rand[1000..9999]>` | `PAR-1721145600000-7421` | backend-generated by generateParentBarcode(): literal 'PAR-', Date.now() epoch millis, '-', and a suffix = 1000 + Math.floor(Math.random()*9000) (a 4-digit number 1000..9999). | `backend/server.js:1521-1524 (generateParentBarcode); used at 6185 and inserted 6203-6234 in the group/parent material creation flow` |
| Child Material Barcode | `barcode` | `CHD-<parentSuffix>-<index, zero-padded to 2>  where parentSuffix = last '-' segment of the parent barcode` | `CHD-7421-01, CHD-7421-02  (children of PAR-1721145600000-7421)` | backend-generated by generateChildBarcode(parentBarcode, index): splits parentBarcode on '-', takes the LAST segment as `suffix` (i.e. the parent's 4-digit random suffix), then forms 'CHD-'+suffix+'-'+index zero-padded to 2. index is 1-based (loop passes index+1). | `backend/server.js:1526-1530 (generateChildBarcode); generated at 6186-6189 and inserted 6236-6267` |
| Item Display Name | `display_name` | `<name> / <alias>   (the ' / <alias>' portion is omitted when alias is empty)` | `Aluminium Sheet / ALU-100` | derived by buildItemDisplayName(name, alias, quantity) when an explicit displayName is not supplied: filters name and alias for non-empty and joins them with ' / '. (quantity param is currently unused in the join.) | `backend/server.js:13766-13769 (buildItemDisplayName); applied at 13799-13800 in saveItem` |
| Variation Path Label (node display_name) | `display_name` | `<seg1> \| <seg2> \| ... \| <segN>   (value-node names along the leaf path, separator = ' \| ')` | `Red \| 10mm` | derived by buildVariationPathLabel(segments): trims each ancestor value-node name, drops empties, and joins with ' \| '. In sanitizeNodes a value node's display_name defaults to this path label when no explicit displayName is given. variationPathLabelForNodeIds / resolveLeafSelectionFromDb build the segment list from the value nodes along the path. | `backend/server.js:13771-13776 (buildVariationPathLabel); sanitizeNodes default at 6991-6992; path builders at 6520-6533 and 6535-6557` |
| Material Name / Particulars (composition) | `name (materials) / particulars` | `<itemDisplayName> - <variationPathLabel>[ - <customVal1> - <customVal2> ...]` | `Aluminium Sheet - Red \| 10mm - Copper` | derived: getItemSelectionSnapshot sets particulars = variationPathLabel ? '<item.display_name\|\|item.name> - <variationPathLabel>' : (item.display_name\|\|item.name). In ensureMaterialForItemSelection the material name starts from that particulars/display name, then any customVariationValues (ordered by sorted key) are appended as a ' - '-joined suffix (only if not already present). | `backend/server.js:9577-9579 (particulars in getItemSelectionSnapshot); custom-value suffix at 9821-9831 (ensureMaterialForItemSelection)` |
| Material Barcode Uniqueness / Normalization Key | `barcode (normalized)` | `uppercase ASCII with whitespace removed` | `'  raw-mll-ano ' -> 'RAW-MLL-ANO'` | normalizeBarcode(value): String(value) -> remove all whitespace (\s+) -> strip non-printable/non-ASCII ([^\x20-\x7E]) -> trim -> toUpperCase(). Used for equality lookups, not stored separately. | `backend/server.js:1513-1519 (normalizeBarcode); UNIQUE constraint at 2623; getMaterialRowByBarcode at 15043-15046 (loads all materials and matches on normalized barcode); collision check at 9808-9814; incrementMaterialScanCount at 15950` |
| Run Barcode Input ID | `run_barcode_inputs.id` | `'barcode-<epochMillis>-<0-999>' e.g. 'barcode-1721140800000-274'; seed: '<runId>-<stageId>-<barcode>'` | `barcode-1721140800000-274` | Backend-generated on scan: `barcode-${Date.now()}-${floor(rand*1000)}` (server.js:23145). Seed full-pipeline composes `${runSeed.id}-${stageId}-${barcode}` (:5350). ensurePipelineRunRecord uses caller-supplied assignment.id (demo: 'demo-anodize-barcode-1'). | `backend/server.js:4245 (def); :23145 (scan gen); :5350 (seed compose)` |
| Production Run Variation Path Label | `production_runs.variation_path_label` | `free text / ' · '-joined variation path, e.g. 'Raw · Milled · Anodized'` | `Raw · Milled · Anodized` | Backend-derived human string: variation leaf display_name/name (server.js:23020) or a composed path when no single leaf, e.g. 'Raw · Milled · Anodized' (:24326). | `backend/server.js:3543 (def); :23020 (from leaf); :24326 (composed)` |
| Inventory Stock Position Natural Key | `inventory_stock_positions (material_barcode, location_id, lot_code)` | `(barcode, location, lot) e.g. ('RAW-MLL-ANO','MAIN','LOT-RUN-1721140800-42')` | `('MAT-1721140800000-01234','MAIN','')` | Not generated: composed from the movement being applied. upsertInventoryStockPosition normalizes location_id (trim, fallback 'MAIN') and lot_code (trim, may be '') then SELECTs by the triple before insert/update (server.js:16074-16112). | `backend/server.js:2887 (UNIQUE def); :16064-16112 (upsert)` |
| Material Barcode | `material_barcode / barcode` | `'PAR-<ts>-<4d>' \| 'CHD-<suffix>-<NN>' \| 'MAT-<ts>-<5d>' \| variation codes 'RAW-MLL-ANO' \| 'LOT-*'` | `RAW-MLL-ANO` | Backend-generated, several schemes: parent `PAR-${Date.now()}-${1000+rand*9000}` (server.js:1521); child `CHD-<parentSuffix>-<NN>` (:1526); standalone `MAT-${Date.now()}-${rand5}` (:9788); variation-derived = item_variation_nodes.code joined by position, e.g. 'RAW-MLL-ANO' (generateBarcodeFromItemSelection :9769, collision suffix -NNN :9813); lot barcodes LOT-*/LOT-SCRAP-*. | `backend/server.js:1521 (parent); :1526 (child); :9788 (standalone); :9769-9785 (variation-derived); :4027 (item_variation_nodes.code)` |
| Parent material barcode | `barcode` | `PAR-<epochMs>-<4digit 1000-9999>` | `PAR-1789000000000-4821` | generateParentBarcode(): const suffix = 1000 + Math.floor(Math.random() * 9000); return `PAR-${Date.now()}-${suffix}`; | `backend/server.js:1521-1524 (called at 6185)` |
| Standalone material barcode | `barcode` | `MAT-<epochMs>-<5digit zero-padded 00000-99999>` | `MAT-1789000000000-04821` | generateStandaloneMaterialBarcode(): return `MAT-${Date.now()}-${Math.floor(Math.random() * 100000).toString().padStart(5, '0')}`; | `backend/server.js:9788-9792 (called at 9806, 24122)` |
| Item-selection variation barcode | `barcode` | `<varCode>-<varCode>-... (optionally + -<3digit rand> or -<itemId> on collision)` | `RAW-MLL-ANO  (collision: RAW-MLL-ANO-042)` | generateBarcodeFromItemSelection(): looks up v.code for each variation prop, sorts by position, joins with '-': codes.map(c => c.code).join('-'). Collision suffixes: `${barcode}-${Math.floor(Math.random()*1000).toString().padStart(3,'0')}` (9813) or `${barcode}-${item.id}` (24125). | `backend/server.js:9769-9785 (collision suffixes 9813, 24125)` |
| Run barcode input id | `id` | `barcode-<epochMs>-<0-999>  \|  input-<epochMs>  \|  <runId>-<stageId>-<barcode>` | `barcode-1789000000000-482` | Runtime scan: const barcodeInputId = `barcode-${Date.now()}-${Math.floor(Math.random() * 1000)}` (23145). Demo helper: `input-${Date.now()}` (22860). Full-seed composite: `${runSeed.id}-${assignment.stageId}-${assignment.barcode}` (5350). Sync path uses caller-supplied assignment.id (17573). | `backend/server.js:23145 (also 22860, seed 5350)` |
| run_barcode_inputs PK | `id` | `free-form id TEXT` | `id string` | backend/client-supplied string id | `backend/server.js:4244` |
| Employee Barcode ID | `barcode_id` | `TEXT barcode value` | `(scanned/assigned barcode)` | User-entered/assigned on employee create/update (not auto-generated by this server code path). | `backend/server.js:3053 (column), backend/server.js:24546 (looked up from decrypted portal token), backend/server.js:24645/24678 (insert/update)` |
| Pipeline-output & scrap lot barcode _(edge)_ | `barcode (material_barcode for freshly created lots)` | ``LOT-RUN-XXXXXXXX-<0..999>` and `LOT-SCRAP-<epochMillis>-<0..999>`` | `LOT-RUN-A1B2C3D4-742  \|  LOT-SCRAP-1721140000000-317` | On pipeline-run completion a fresh output lot barcode `LOT-${runCode}-${rand(0..999)}` (server.js:23058). On scrap capture a scrap lot barcode `LOT-SCRAP-${Date.now()}-${rand(0..999)}` (server.js:23463). runCode itself is `RUN-${pipelineRunId.substring(0,8).toUpperCase()}` (server.js:23027). | `backend/server.js:23058 and :23463 (runCode at :23027)` |

### Identity & security

| Name | Field | Format | Example | Generation | Location |
|---|---|---|---|---|---|
| Variation Node Code | `code` | `short free-text mnemonic token, by app convention uppercase letters, e.g. 'RAW', 'MLL', 'ANO', 'DRW', 'INS'` | `MLL` | user-entered in the desktop item editor's variation tree; persisted verbatim (String(node.code\|\|'').trim()) on saveItem. Never auto-derived. | `schema backend/server.js:4027 & 4044; sanitized/carried at 6976 & 6990 (sanitizeNodes) and 6412/6740 (tree read); persisted on upsert at 13986/13992 (UPDATE) and 14003/14012 (INSERT); also seeded at 14520-14522; composed into the barcode at 9774-9785` |
| Item Naming Format | `naming_format` | `JSON-serialized array of naming-format tokens, e.g. '[]' when unset` | `[]` | user-entered; on saveItem it is JSON.stringify(namingFormat array) into serializedNamingFormat and written; on read it is JSON.parse'd back (guarded, returns [] on parse error). | `schema backend/server.js:4037; serialized at 13796 and written at 13912 (INSERT) / 13950 (UPDATE); parsed on read at 1975-1981; also selected for naming queries at 19320/19400/24978` |
| Location ID | `location_id / from_location_id / to_location_id` | `free text location token, default 'MAIN'; e.g. 'Rack B, Shelf 3'` | `MAIN` | Not sequenced — a free-text warehouse/rack token. Resolution: payload.toLocationId else material.location else 'MAIN' (server.js:16522-16525); normalized to 'MAIN' fallback in stock upsert (:16074). | `backend/server.js:2880 (stock def); :2899-2900 (movement from/to); :16522-16525 (resolution)` |
| Lot Code | `lot_code` | `free lot token / defaults to material barcode / 'LOT-<runCode>-<rand>' / 'LOT-SCRAP-<ts>-<rand>'` | `LOT-RUN-1721140800-042` | Backend-resolved/generated. On issue/consume without explicit lot, defaults to the material barcode (lotCode = explicitLot \|\| barcode, server.js:16526) and issue/consume auto-picks the fullest existing lot (:16534). Fresh lots are minted as barcodes: finished-good `LOT-${runCode}-${floor(rand*1000)}` (:23058) and scrap `LOT-SCRAP-${Date.now()}-${floor(rand*1000)}` (:23463). | `backend/server.js:2881 (stock def); :2911 (movement def); :16526 (default-to-barcode); :23058 & :23463 (minted lots)` |
| User mobile login PIN | `mobile_pin` | `<4digit 1000-9999>` | `4821` | generateUniqueMobilePin(): loop up to 1000x: pin = Math.floor(1000 + Math.random()*9000).toString(); retry until no existing users row has that pin. | `backend/server.js:1204-1213 (used in createUserAccount at 1254)` |
| Auth session id | `sessionId` | `sess-<uuid v4>` | `sess-3f5d710d-dee7-4ce9-93f7-c204041d8865` | const sessionId = `sess-${crypto.randomUUID()}`; | `backend/server.js:1059` |
| auth_sessions PK | `id` | `sess-<uuid>` | `sess-<crypto.randomUUID()>` | backend-generated in code | `backend/server.js:2704` |
| challan_template_upload_sessions PK | `id` | `uuid/session token TEXT` | `<uuid>` | backend-generated session id (TEXT) | `backend/server.js:3370` |
| po_upload_sessions PK | `id` | `uuid/session token TEXT` | `<uuid>` | backend-generated session id (TEXT) | `backend/server.js:3642` |
| asset_upload_sessions PK | `id` | `uuid/session token TEXT` | `<uuid>` | backend-generated session id (TEXT) | `backend/server.js:3690` |
| Mobile PIN | `mobile_pin` | `4-digit numeric string` | `4821` | generateUniqueMobilePin(): Math.floor(1000 + Math.random()*9000).toString(), retried up to 1000x against a uniqueness check. Assigned automatically at user creation. | `backend/server.js:1204-1213 (generation), backend/server.js:1254/1269 (assigned on INSERT), backend/migrations/017-mobile-pin.sql:1-2 (column + unique index); packages/core_erp/lib/features/auth/domain/auth_user.dart:19` |
| Auth Token (JWT) | `token` | `base64url(header).base64url(payload).base64url(HMAC-SHA256 signature)` | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.<payload>.<sig>` | signJwt({sub:userId, role, sid:sessionId}): HS256 HMAC over base64url(header).base64url(body) using JWT_SECRET; iat/exp added, exp = now + JWT_TTL_SECONDS (default 12h = 43200s). | `backend/server.js:557-571 (signJwt), backend/server.js:574-600 (verifyJwt), backend/server.js:1060 (issued in createAuthSession), backend/server.js:1391-1402 (Bearer parse + verify in requireAuth)` |
| JWT Signing Secret | `JWT_SECRET` | `arbitrary string secret` | `paper-local-development-secret (dev fallback)` | resolveJwtSecret(): uses process.env.PAPER_JWT_SECRET; falls back to the hardcoded literal 'paper-local-development-secret' when unset. Required (startup throws) only when NODE_ENV=production (ensureRuntimeConfig). | `backend/server.js:58 (const), backend/server.js:378-384 (resolveJwtSecret), backend/server.js:391-393 (production requirement)` |
| Session ID | `id` | `sess-<uuid-v4>` | `sess-3f5d710d-dee7-4ce9-93f7-c204041d8865` | `sess-${crypto.randomUUID()}` created in createAuthSession; a new login revokes all other sessions for that user first (single-session model). | `backend/server.js:1059 (generation), backend/server.js:2704-2716 (auth_sessions schema), backend/server.js:1060 (embedded as JWT sid); packages/core_erp/lib/features/auth/domain/auth_user.dart:171` |
| Session Token Hash | `token_hash` | `64-char lowercase hex (SHA-256)` | `9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08` | hashToken(token) = crypto.createHash('sha256').update(token).digest('hex'). Computed from the issued JWT at session creation. | `backend/server.js:973-975 (hashToken), backend/server.js:1061 (stored), backend/server.js:1402 (re-derived for lookup)` |
| Password Hash | `password_hash` | `pbkdf2$<iterations>$<saltHex>$<hashHex>` | `pbkdf2$120000$<32hexsalt>$<64hexhash>` | hashPassword(): PBKDF2-SHA256 with a per-user 16-byte random salt (crypto.randomBytes(16)), 120000 iterations, 32-byte key. Stored as a composite string. | `backend/server.js:602-608 (hashPassword), backend/server.js:610-624 (verifyPassword, timingSafeEqual), backend/server.js:2689 (column)` |
| Sandbox Activation PIN | `activation_pin` | `6-digit numeric string` | `482913` | Math.floor(100000 + Math.random()*900000).toString(); created lazily the first time a client config is saved if no PIN row exists. | `backend/server.js:23809-23810 (generation), backend/server.js:4462-4468 (schema), backend/server.js:23827-23830 (verified on machine activation)` |
| Sandbox Machine Activation Token | `token` | `64-char hex (32 random bytes)` | `3b1f...<64 hex>` | crypto.randomBytes(32).toString('hex') on successful activation; upserted per (client_id, machine_fingerprint). Max 3 activated machines per client. | `backend/server.js:23843 (generation), backend/server.js:4470-4479 (schema), backend/server.js:23845-23849 (upsert)` |
| Machine Fingerprint | `machine_fingerprint` | `opaque client device string` | `(client-provided)` | Client-supplied device fingerprint (req.body.fingerprint); not generated server-side. | `backend/server.js:4474 (column), backend/server.js:23821/23836/23846 (used in activation)` |
| Freelancer Portal Access Token | `token` | `<ivHex>:<ciphertextHex> (AES-256-CBC)` | `1a2b...<32hex iv>:9f8e...<hex ciphertext>` | AES-256-CBC of an employee's barcode_id, formatted iv:ciphertext, using a HARDCODED key SECRET = 'my-very-secret-key-32charslong!!' (encryption/generation side not present in server.js; server only decrypts). | `backend/server.js:24528-24546 (GET /api/freelancer-portal/data: decrypt token -> barcode_id -> employee lookup); hardcoded key at backend/server.js:24532` |

### System-generated (timestamp)

| Name | Field | Format | Example | Generation | Location |
|---|---|---|---|---|---|
| Pipeline Template Flow ID | `flows_json[].id (inside pipeline_templates.flows_json)` | `'{templateId}-flow-{n}' e.g. 'sheet-metal-flow-1','alu-flow-1' OR bare 'flow-1'..'flow-5' (dolly)` | `alu-flow-2` | Seed generator builds `${pipeline.id}-flow-${index+1}` (server.js:5031); hand-authored seeds use per-template prefixes; frontend supplies for user templates. fromNodeId/toNodeId reference node ids. | `backend/server.js:4178 (flows_json col); :5031 (generator); :2371 (dolly flow-1); :24242 (alu-flow-1)` |
| Pipeline Run ID | `pipeline_runs.id` | `'run-<epochMillis>' e.g. 'run-1721140800000'; demo rows use fixed slugs` | `run-1721140800000` | Backend-generated `run-${Date.now()}` in createRunFromTemplate (server.js:17435). ensurePipelineRunRecord accepts a caller-supplied id (seed/demo rows use literals like 'demo-anodize-run-active'). Seed full-pipeline reuses runSeed.id. | `backend/server.js:4190 (def); :17435 (gen); :24286 (demo literal)` |
| Inventory Movement ID | `inventory_movements.id` | `'mov-<epochMillis>-<0-999>'` | `mov-1721140800000-482` | Backend-generated `mov-${Date.now()}-${floor(rand*1000)}` — three call sites: applyInventoryMovementCore (server.js:16521) and two challan/reconciliation paths (:10373, :10485). | `backend/server.js:2893 (def); :16521, :10373, :10485 (gen)` |
| Inventory movement id | `id` | `mov-<epochMs>-<int 0-999>` | `mov-1789000000000-482` | const movementId = `mov-${Date.now()}-${Math.floor(Math.random() * 1000)}`; | `backend/server.js:10373, 10485, 16521 (three call sites)` |
| Pipeline run id | `id` | `run-<epochMs>` | `run-1789000000000` | createRunFromTemplate(): const runId = `run-${Date.now()}`; | `backend/server.js:17435` |
| Freelancer job batch number | `batch_number` | `BATCH-<epochMs>` | `BATCH-1789000000000` | const batch_number = 'BATCH-' + Date.now(); | `backend/server.js:24450 (insert 24451-24453)` |
| Generic upload session id | `uploadSessionId` | `generic-upload-<epochMs>-<16 hex chars>` | `generic-upload-1789000000000-9f3a1c0b7d2e4a56` | const uploadSessionId = `generic-upload-${now.getTime()}-${crypto.randomBytes(8).toString('hex')}`; objectKey = `generic/${Date.now()}-${sha256.slice(0,12)}-${normalizedName}`. | `backend/server.js:21206 (objectKey 21202-21203)` |
| inventory_movements PK | `id` | `mov-<epochMs>-<rand0-999>` | `mov-1718000000000-547` | backend-generated in code | `backend/server.js:2892` |
| S3 Object Key (asset storage key) _(edge)_ | `object_key / background_object_key / asset_object_key` | ``{prefix}{Date.now()}-{sha256[0:12]}-{fileName}` generally; for ITEM_IMAGE `{prefix}{entityType}-{entityId}/{uniqueStem}-{fileName}`. Prefixes: masters/items/, orders/po-docs/, logistics/challans/, logistics/challan-templates/, masters/machines/, masters/dies/, masters/departments/` | `orders/po-docs/1721140000000-9f8 e1c2ad3b4-po.pdf  \|  masters/items/item-42/1721140000000-9f8e1c2ad3b4-front.png` | Built by buildS3ObjectKey() at server.js:12049. prefix from S3_UPLOAD_PREFIXES (server.js:64) keyed by uploadType; uniqueStem = `${Date.now()}-${sha256.slice(0,12)}`. | `backend/server.js:12049 (buildS3ObjectKey), :64 (prefixes), :3681/:3634/:3648/:3698/:3377/:3394/:3416 (columns)` |
| Machine asset-code fallback _(edge)_ | `asset_id (generated)` | ``MACH-<epochMillis>`` | `MACH-1721140000000 (curated seeds use MAC-1001, MAC-1002 at server.js:6051/6068)` | When the client sends no assetId on create, server generates `MACH-${Date.now()}` at server.js:19073. | `backend/server.js:19073` |
| Die tool-code fallback _(edge)_ | `tool_code (generated)` | ``DIE-<epochMillis>`` | `DIE-1721140000000 (curated seeds use TL-890-A, TL-102-B at server.js:6088/6107; demo uses DIE-DEMO-<ts> at :22824)` | When the client sends no toolCode on create, server generates `DIE-${Date.now()}` at server.js:19198. | `backend/server.js:19198` |
| Sentinel/virtual location ids _(edge)_ | `location_id constants (e.g. SCRAP-BIN)` | `fixed string literal` | `SCRAP-BIN` | Hardcoded string constant in the scrap flow: toLocationId 'SCRAP-BIN' (server.js:23496). | `backend/server.js:23496` |

### Natural & user-entered keys

| Name | Field | Format | Example | Generation | Location |
|---|---|---|---|---|---|
| Pipeline Template ID | `pipeline_templates.id` | `human-authored kebab-case slug, e.g. 'sheet-metal-flow' \| 'dolly' \| 'aluminum-anodize-line'` | `dolly` | NOT auto. Client/frontend-supplied verbatim on POST (data.id at server.js:20683) and PUT keyed on :id. Seed rows use hardcoded slug literals. Never backend-generated. | `backend/server.js:4168 (def); :20683 (POST accepts data.id); :2159/:2271/:24225 (seed literals)` |
| Seed PO number | `po_number` | `PO-<orderNo>` | `PO-SO-1001` | `PO-${order.orderNo}` used as po_number in the full demo seed for both the order header and each order item row. | `backend/server.js:5090 (header), 5106 (item)` |
| report_groups PK | `code` | `free-text code` | `'MONTHLY'` | user-entered code | `backend/server.js:3339` |
| order_headers PK | `order_no` | `free-text order number` | `'PO-1024' / client order code` | user-entered order number (client-supplied) | `backend/server.js:3580` |
| pipeline_templates PK | `id` | `free-form template id TEXT` | `'ptl-...' / template id` | client/backend-supplied string id | `backend/server.js:4167` |
| pipeline_runs PK | `id` | `free-form run id TEXT` | `run id string` | client/backend-supplied string id | `backend/server.js:4189` |

## Database primary keys (118 tables)

Most tables use `INTEGER PRIMARY KEY AUTOINCREMENT` (int⚙ — an internal rowid; the real business key is the `UNIQUE` column noted at right). A few use TEXT or composite keys.

| Table | Key field | Kind | Natural / business key & notes |
|---|---|---|---|
| `asset_upload_sessions` | `id` | TEXT | Polymorphic (entity_type, entity_id) upload session. |
| `auth_events` | `id` | int⚙ | Auth audit log; actor_user_id / target_user_id -> users(id). |
| `auth_events.id / AuthEvent.id` | `id` | int⚙ | Security event log id (login_success, login_blocked_lockout, etc.). Carries actor_user_id/target_user_id (FK users.id), ip_address, user_agent, metadata_json. Q |
| `auth_sessions` | `id` | TEXT | Session id generated as `sess-${crypto.randomUUID()}` (server.js:1059); user_id -> users(id). |
| `challan_template_mappings` | `id` | int⚙ | UNIQUE(template_id, field_key) natural key. |
| `challan_template_upload_sessions` | `id` | TEXT | Upload session; sha256 indexed for dedup. |
| `challan_templates` | `id` | int⚙ | Referenced by challan_template_mappings.template_id (CASCADE). |
| `changelog.id` | `id` | int⚙ | Monotonic cursor for the realtime SSE change stream; client passes it as `since`/`lastChangeId` to resume. Emitted as the SSE `id:` field. |
| `changelog.record_id` | `record_id` | int⚙ | Points at the changed row (table_name + record_id) so SSE clients refetch that specific record. Carries no row data itself. |
| `clients` | `id` | int⚙ | Referenced by order_headers/order_items/vendors-relations/sub_contractors/invoice_headers etc. |
| `clients.id` | `id` | int⚙ | Master client/factory entity id. FK target for users.client_id, order_headers.client_id, order_items.client_id, delivery_challans.material_owner_client_id, sub_ |
| `company_profiles` | `id` | int⚙ | Company issuer profile; snapshotted into challans. |
| `delete_requests` | `id` | int⚙ | entity_id is a generic TEXT reference (not FK-constrained). |
| `delete_requests.entity_id` | `entity_id` | int⚙ | Polymorphic reference (with entity_type/entity_label) to the record proposed for deletion. |
| `delete_requests.id / DeleteRequest.id` | `id` | int⚙ | Deletion-approval workflow record. Carries requested_by_user_id/reviewed_by_user_id (FK users.id) and entity_id (TEXT) + entity_type identifying the target. Act |
| `deleted_records` | `id` | int⚙ | Soft-delete archive; table_name + record_id (INTEGER) identify the deleted row generically (no FK). |
| `deleted_records.id` | `id` | int⚙ | Trash/undo row id; used to compensate/rollback a failed delete (server.js:1694) and to restore/list soft-deleted records. |
| `deleted_records.record_id` | `record_id` | int⚙ | Identifies the source row so it can be restored. deleted_by is stored as a TEXT user NAME (req.user.name or 'System'), not a user id (server.js:1676, 3562). |
| `delivery_challan_activity_log` | `id` | int⚙ | challan_id -> delivery_challans(id) CASCADE. Re-declared at :3805. |
| `delivery_challan_items` | `id` | int⚙ | challan_id -> delivery_challans(id) CASCADE. Also declared at :3785 and re-created by quantity/weight->REAL migration at :5683. |
| `delivery_challan_order_items` | `(challan_id, order_id)` | composite | Composite join PK; challan_id -> delivery_challans(id), order_id -> order_items(id). Re-declared at :3867. |
| `delivery_challan_report_groups` | `(challan_id, report_group_code)` | composite | Composite join PK; FKs to delivery_challans(id) and report_groups(code). Re-declared at :3883. |
| `delivery_challans` | `id` | int⚙ | UNIQUE identifier: challan_no (TEXT UNIQUE), generated as `<DC\|RC\|IC>-#####` per type via generateChallanNumber() (server.js:7869-7886). A second, thinner CREAT |
| `departments` | `id` | int⚙ | Referenced by employees.department_id (ON DELETE CASCADE). |
| `dies` | `id` | int⚙ | UNIQUE identifier: tool_code (TEXT NOT NULL UNIQUE). |
| `employees` | `id` | int⚙ | barcode_id is a free-text column (not unique); referenced by freelancer_job_batches.freelancer_id / freelancer_jobs. |
| `freelancer_job_batches` | `id` | int⚙ | UNIQUE identifier: batch_number (TEXT UNIQUE), generated as `BATCH-${Date.now()}` (server.js:24450). |
| `freelancer_job_tasks` | `id` | int⚙ | job_id -> freelancer_jobs(id) CASCADE; item_id -> items(id). |
| `freelancer_jobs` | `id` | int⚙ | batch_id -> freelancer_job_batches(id); item_id -> items(id). |
| `global_audit_logs.entity_id` | `entity_id` | int⚙ | Polymorphic reference to the audited record, paired with entity_type. Not a typed FK. |
| `global_audit_logs.id / GlobalAuditLog.id` | `id` | int⚙ | Audit trail row id. Row also carries actor_user_id (FK users.id), entity_type (TEXT) and entity_id (TEXT, the affected entity's id as a string). On user delete, |
| `group_item_memberships` | `id` | int⚙ | UNIQUE(group_id, item_id) natural key; FKs to groups/items. |
| `groups` | `id` | int⚙ | Self-FK parent_group_id; referenced by items.group_id, materials.linked_group_id, machines.group_id, group_item_memberships.group_id. Also re-created in a migra |
| `Inventory movement reference discriminator` | `reference_type (+ reference_id), reason_code, source_challan_type` | int⚙ | Together they form the polymorphic 'source' pointer for a stock movement/reservation and drive audit strings like `${referenceType} ${referenceId}` (server.js:1 |
| `inventory_alerts` | `inventory_alerts.id` | int⚙ | Open/close alert log per material_barcode; alert_type e.g. 'low_stock', severity 'warning' |
| `inventory_alerts` | `id` | int⚙ | Keyed by material_barcode (non-unique). |
| `inventory_movements` | `id` | TEXT | id generated as `mov-${Date.now()}-${rand}` (server.js:10373,10485,16521); reverses_movement_id self-references id. |
| `inventory_reservations` | `inventory_reservations.id` | int⚙ | Active reservation ledger; material_barcode->materials.barcode; reference_id defaults to the movementId when caller gives none (:16638); status 'active' until r |
| `inventory_reservations` | `id` | int⚙ | reference_type/reference_id are generic (non-FK) references. |
| `inventory_set_lines` | `id` | int⚙ | UNIQUE(set_id, item_id, variation_leaf_node_id). Re-created by nullable-leaf migration at :5786. |
| `inventory_sets` | `id` | int⚙ | Referenced by inventory_set_lines.set_id (CASCADE). |
| `inventory_stock_positions` | `inventory_stock_positions.id` | int⚙ | Surrogate PK; real identity is the composite unique key below |
| `inventory_stock_positions` | `inventory_stock_positions (material_barcode, location_id, lot_code)` | composite | One on_hand/reserved/damaged bucket per material+location+lot; the granularity all inventory movements read/write against |
| `inventory_stock_positions` | `id` | int⚙ | UNIQUE(material_barcode, location_id, lot_code) natural key. |
| `inventory_stock_positions, inventory_movements` | `location_id / from_location_id / to_location_id` | int⚙ | Part of stock-position natural key; movement from/to for transfers |
| `invoice_headers` | `id` | int⚙ | UNIQUE identifier: invoice_no (TEXT UNIQUE), generated as `INV-#####` via generateInvoiceNumber() (server.js:10730-10742). |
| `invoice_lines` | `id` | int⚙ | invoice_id -> invoice_headers(id) CASCADE; challan_id/challan_item_id -> challan tables. |
| `item_bom_lines` | `id` | int⚙ | UNIQUE(item_id, material_barcode) natural key. |
| `item_property_schema` | `id` | int⚙ | UNIQUE(item_id, property_key) natural key. |
| `item_unit_conversions` | `id` | int⚙ | UNIQUE(item_id, unit_id) natural key. |
| `item_variation_dimensions` | `id` | int⚙ | item_id -> items(id) CASCADE; referenced by item_variation_values.dimension_id. |
| `item_variation_nodes` | `id` | int⚙ | Self-FK parent_node_id (CASCADE); item_id -> items(id); this is the variation-tree leaf id referenced everywhere as variation_leaf_node_id. |
| `item_variation_values` | `id` | int⚙ | variation_id -> item_variations(id), dimension_id -> item_variation_dimensions(id), both CASCADE. |
| `item_variations` | `id` | int⚙ | item_id -> items(id) CASCADE; referenced by item_variation_values.variation_id. |
| `items` | `id` | int⚙ | Self-FK base_item_id; group_id -> groups, unit_id -> units; heavily referenced across order/variation/stock tables. |
| `machines` | `id` | int⚙ | UNIQUE identifier: asset_id (TEXT NOT NULL UNIQUE); group_id -> groups(id). |
| `material_activity` | `id` | int⚙ | Activity log keyed by barcode (non-unique). |
| `material_group_item_links` | `id` | int⚙ | UNIQUE(material_id, item_id) acts as the natural key. |
| `material_group_preferences` | `id` | int⚙ | UNIQUE(material_id) — one prefs row per material. |
| `material_group_properties` | `id` | int⚙ | UNIQUE(material_id, property_key) natural key. |
| `material_group_units` | `id` | int⚙ | UNIQUE(material_id, unit_id) natural key. |
| `materials` | `id` | int⚙ | UNIQUE identifier: barcode (TEXT NOT NULL UNIQUE) is the real scanned business key; id referenced by material_group_* tables. |
| `order_activity_log` | `id` | int⚙ | order_id -> order_items(id) CASCADE; columns backfilled via ensureColumnExists at :3820. |
| `order_headers` | `order_no` | TEXT | order_no is the natural TEXT PK (upserted via ON CONFLICT(order_no)); referenced by order_items.order_no. client_id -> clients(id), sub_contractor_id -> sub_con |
| `order_items` | `id` | int⚙ | The per-line order id (referred to as order_id across challan/requirement/assignment tables); order_no -> order_headers(order_no), item_id -> items(id). |
| `order_material_allocations` | `id (+ order_id, requirement_id, reservation_id, material_barcode)` | composite | Links an order material requirement to a concrete inventory reservation/allocation (allocated_qty/consumed_qty). Appears to be a legacy/planned table superseded |
| `order_material_requirements` | `id` | int⚙ | order_id -> order_items(id) CASCADE; referenced by procurement_request_line_sources.requirement_id. |
| `order_pipeline_assignments` | `order_pipeline_assignments.id` | int⚙ | Join row: order_item_id->order_items.id (ON DELETE CASCADE), pipeline_run_id->pipeline_runs.id (ON DELETE CASCADE); allocated_quantity apportions order qty to a |
| `order_pipeline_assignments` | `id` | int⚙ | order_item_id -> order_items(id), pipeline_run_id -> pipeline_runs(id), both CASCADE. |
| `order_po_documents` | `(order_id, document_id)` | composite | Composite join PK; order_id -> order_items(id), document_id -> po_documents(id), both CASCADE. |
| `order_status_history` | `id` | int⚙ | order_id -> order_items(id) CASCADE. |
| `permission_template_permissions` | `(template_id, permission_key)` | composite | Composite PK; template_id -> permission_templates(id). |
| `permission_templates` | `id` | int⚙ | UNIQUE identifier: name (TEXT NOT NULL UNIQUE). |
| `pipeline_runs` | `id` | TEXT | template_id -> pipeline_templates(id); referenced by stage_reconciliations/production_scrap/run_barcode_inputs/order_pipeline_assignments. |
| `pipeline_templates` | `pipeline_templates.id` | TEXT | PK; referenced by pipeline_runs.template_id (:4191), and by createRunFromTemplate/ensurePipelineRunRecord lookups; delete blocked if any pipeline_runs reference |
| `pipeline_templates` | `id` | TEXT | Referenced by pipeline_runs.template_id, items.default_pipeline_id. |
| `pipeline_templates (embedded JSON)` | `nodes_json[].id (inside pipeline_templates.nodes_json)` | int⚙ | Referenced everywhere as node_id: stage_reconciliations.node_id, run_barcode_inputs.node_id, production_scrap.node_id, pipeline_runs.node_status_json keys, over |
| `po_documents` | `id` | int⚙ | UNIQUE identifiers: sha256 (content hash) and object_key (storage key), both UNIQUE. |
| `po_upload_sessions` | `id` | TEXT | Presigned upload session; sha256 indexed. |
| `Procurement Request Number` | `request_number` | int⚙ | Human-facing unique reference for a procurement/purchase request, sibling to invoice_no and challan_no. |
| `procurement_activity_log` | `id` | int⚙ | procurement_request_id -> procurement_requests(id) CASCADE; actor_user_id -> users(id). |
| `procurement_request_line_sources` | `id` | int⚙ | UNIQUE(procurement_request_line_id, requirement_id); FKs to procurement_request_lines, order_items, order_material_requirements, all CASCADE. |
| `procurement_request_lines` | `id` | int⚙ | UNIQUE(procurement_request_id, material_barcode); FK to procurement_requests(id) CASCADE. |
| `procurement_requests` | `id` | int⚙ | UNIQUE identifier: request_number (TEXT NOT NULL UNIQUE, client/route-supplied — no generator in server.js); multiple *_by_user_id -> users(id). |
| `production_runs` | `production_runs.id` | int⚙ | Internal surrogate PK; business identity carried by run_code |
| `production_runs` | `production_runs.variation_leaf_node_id` | int⚙ | Identifies the exact variation leaf produced; paired with variation_path_label; indexed with item_id (:3553) |
| `production_runs` | `id` | int⚙ | UNIQUE identifier: run_code (TEXT UNIQUE), seeded as `RUN-0001` zero-padded (server.js:9663); item_id -> items(id). |
| `production_scrap` | `production_scrap.id` | int⚙ | Legacy scrap log; pipeline_run_id->pipeline_runs.id, node_id->template node id, material_barcode->materials.barcode. Endpoint also bridges to real inventory by |
| `production_scrap` | `id` | int⚙ | pipeline_run_id -> pipeline_runs(id); node_id/material_barcode unconstrained refs. |
| `reconciliation_conversion_overrides` | `id` | int⚙ | UNIQUE(item_id, variation_leaf_node_id) natural key. |
| `reconciliation_waste_audit` | `id` | int⚙ | challan_id -> delivery_challans(id); client_id/item_id are unconstrained references. |
| `report_groups` | `code` | TEXT | code is the natural TEXT PK; referenced by delivery_challan_report_groups.report_group_code. Re-declared at :3875. |
| `role_permissions` | `(role, permission_key)` | composite | Composite PK; no surrogate id. Seeded via seedRolePermissions(). |
| `run_barcode_inputs` | `id` | TEXT | run_id -> pipeline_runs(id); material_id is TEXT (unconstrained). |
| `sandbox_activated_machines` | `id` | int⚙ | UNIQUE(client_id, machine_fingerprint) natural key. |
| `sandbox_client_configs` | `client_id` | TEXT | client_id is natural TEXT PK; stores per-client feature-flag config_json served by GET /sandbox-config/:clientId. |
| `sandbox_client_configs.client_id (the clientId in /sandbox-config/:clientId)` | `client_id` | TEXT | Per-client feature-flag/config partition. GET /sandbox-config/:clientId returns that client's config_json, falling back to the 'default' row then a static JSON. |
| `sandbox_client_pins` | `client_id` | TEXT | One activation_pin per client_id. |
| `sandbox_client_users` | `id` | int⚙ | UNIQUE(client_id, user_email) natural key. |
| `sandbox_replays` | `id` | int⚙ | client_id/session_id are TEXT columns (not unique). |
| `sandbox_replays.session_id` | `session_id` | int⚙ | Groups recorded UI/session replay events for a sandbox client. The replay row's own INTEGER `id` is used to fetch a single replay (GET /api/sandbox-dashboard/re |
| `sandbox_sync_states` | `client_id` | TEXT | One sync-state row per client_id. |
| `scan_history` | `id` | int⚙ | Barcode scan log; barcode column is not unique. |
| `search_clicks` | `id` | int⚙ | entity_id is a generic TEXT reference; user_id -> users(id). |
| `search_history` | `id` | int⚙ | user_id -> users(id). |
| `stage_reconciliations` | `stage_reconciliations (run_id, node_id)` | composite | One reconciliation row per run+node; stores allotted/output/leftover/scrap/good_yield/actual_hours etc. Mirrors legacy nodeMetrics so the app still reads pipeli |
| `stage_reconciliations` | `(run_id, node_id)` | composite | Composite PK; run_id -> pipeline_runs(id). |
| `sub_contractors` | `id` | int⚙ | client_id -> clients(id) CASCADE; referenced by order_headers/order_items.sub_contractor_id. |
| `unit_groups` | `id` | int⚙ | Referenced by units.unit_group_id. |
| `units` | `id` | int⚙ | Self-FK conversion_base_unit_id; referenced by items/materials/order_items/etc. |
| `uploaded_assets` | `id` | int⚙ | UNIQUE identifier: object_key (UNIQUE); polymorphic (entity_type, entity_id) target. |
| `user_favorite_items` | `id` | int⚙ | UNIQUE(user_id, item_id, variation_leaf_node_id) natural key. |
| `user_permission_overrides` | `(user_id, permission_key)` | composite | Composite PK; user_id -> users(id). |
| `user_permission_templates` | `(user_id, template_id)` | composite | Composite join PK; user_id -> users(id), template_id -> permission_templates(id). |
| `users` | `id` | int⚙ | UNIQUE identifier: email (TEXT NOT NULL UNIQUE). Self-FK created_by_user_id; widely referenced as actor/owner FK. |
| `users.client_id -> clients.id` | `client_id` | int⚙ | Associates a user with a factory/client (clients table). Surfaced as `clientId`/`clientName` in the user DTO. Governs which factory a user belongs to. |
| `variation_stock` | `id` | int⚙ | UNIQUE(item_id, variation_leaf_node_id, location_id) natural key; FKs to items/item_variation_nodes. |
| `vendors` | `id` | int⚙ | Referenced by delivery_challans.vendor_id. |

## Frontend model identifiers (69 fields)

| Model / DTO | Field | Type |
|---|---|---|
| OrderEntry | `id` | int (Dart, non-null) |
| OrderEntry / OrderGroup | `orderNo` | String |
| OrderEntry / OrderGroup / OrderDto | `clientId` | int |
| OrderEntry / OrderDto | `subContractorId` | int? (nullable) |
| OrderEntry / OrderDto | `itemId` | int |
| OrderEntry / OrderDto | `variationLeafNodeId` | int |
| OrderEntry / OrderDto | `variationPathNodeIds` | List<int> |
| OrderEntry / OrderDto | `unitId` | int? (nullable) |
| OrderDto | `id / orderNo / clientId / subContractorId / itemId / variationLeafNodeId / variationPathNodeIds / unitId` | same types as domain (int, String, int?, List<int>) |
| OrderActivityDto | `id / orderId / actorUserId` | int / int / int? |
| OrderStatusHistoryDto | `id / orderId / changedByUserId` | int / int / int? |
| PoDocumentEntry / PoDocumentDto | `id` | int |
| OrderReportRun | `runId` | String |
| OrderReportItem | `orderItemId` | int |
| ItemDefinition / ItemDto | `id` | int |
| ItemDefinition | `groupId` | int |
| ItemDefinition | `combinationGroupIds` | List<int> |
| ItemDefinition | `unitId` | int |
| ItemDefinition | `baseItemId` | int? (nullable) |
| ItemDefinition | `defaultPipelineId` | String? (nullable) |
| ItemVariationNodeDefinition / ItemVariationNodeDto | `id` | int |
| ItemVariationNodeDefinition | `itemId` | int |
| ItemVariationNodeDefinition | `parentNodeId` | int? (nullable) |
| ItemPropertySchemaEntry | `unitId / sourceGroupId / sourceItemIds` | int? / int? / List<int> |
| ItemAsset / ItemAssetUploadIntentInput | `id / entityId (+ itemId on intent)` | int / int (itemId int? on CompleteInput) |
| ItemUsageRecord | `id` | String |
| PipelineTemplate | `id` | String |
| PipelineTemplate | `factoryId / shopFloorId` | String? / String? |
| PipelineTemplate | `linkedOrderId` | int? (nullable) |
| PipelineRun | `templateId / templateVersion` | String / int |
| PipelineRun | `orderItemId` | int? (nullable) |
| ProcessNode | `id` | String |
| ProcessNode | `dieId / machineGroupId (+ machine)` | dieId String, machineGroupId int?, machine String |
| ScrapItemRef / ProcessNode | `id (ScrapItemRef) / scrapItemId (getter)` | int / int? |
| PipelineItemEndpoint | `itemId / unitId / groupId / variationLeafNodeId` | int / int / int? / int |
| MaterialBatch | `id / currentNodeId / parentBatchId` | String / String / String? |
| BarcodeInput | `barcode` | String |
| ReconcileRequest / ProductionRunCommit / offline DB helper | `runId` | String |
| ProductionRunCommit | `stageId` | String |
| Factory | `id (+ code)` | String / String |
| ShopFloor | `id / factoryId (+ code)` | String / String / String |
| FloorSummary / PipelineSummary / StationNode / ProductionZone / PipelineRoute | `id / pipelineId / zoneId / topBottleneckPipelineId` | String (all) |
| MaterialBase / MaterialRecord / MaterialDto | `id` | int? (nullable) |
| MaterialBase / MaterialRecord / MaterialDto | `barcode` | String |
| MaterialRecord / ParentMaterial / ChildMaterial | `parentBarcode / linkedChildBarcodes` | String? / List<String> |
| MaterialRecord / MaterialDto / InventoryMaterialModel | `linkedGroupId / linkedItemId / linkedVariationLeafNodeId / unitId` | int? (all nullable) |
| VariationStockRecord | `stockId / itemId / variationLeafNodeId / variationPathNodeIds / unitId / locationId` | int / int / int / List<int> / int? / String |
| VariationStockEntry / VariationStockLeaf | `itemId / leafNodeId` | int / int |
| InventoryMovementDto | `fromLocationId / toLocationId / referenceId / sourceChallanId / sourceChallanLineId` | String? / String? / String? / int? / int? |
| InventorySetDto / InventorySetLineDto | `id (InventorySetDto) / id,itemId,variationLeafNodeId (InventorySetLineDto)` | int / int? / int / int |
| ScanEventModel / MaterialActivityEvent / MaterialActivityEventDto | `id (+ barcode)` | int? / String |
| ClientDefinition | `id` | int |
| SubContractorDefinition | `id / clientId` | int / int |
| VendorDefinition | `id` | int |
| AuthSession | `id / userId` | String / int |
| AuthEvent / PermissionTemplate | `id` | int |
| DeleteRequest | `id / entityId (+ entityType)` | int / String |
| DeliveryChallan | `id` | int |
| DeliveryChallan | `challanNo` | String |
| DeliveryChallan | `orderId / orderIds / clientId / vendorId / orderNo / orderNos` | int? / List<int> / int? / int? / String / List<String> |
| DeliveryChallanItem | `id / orderItemId / productionRunId / itemId / variationLeafNodeId / lineNo / variationPathNodeIds` | int / int? / int? / int? / int / int / List<int> |
| CompletedProductionRun | `id / runCode` | int / String |
| CompanyProfile | `id` | int |
| DepartmentDefinition | `id` | int |
| EmployeeDefinition | `id / departmentId / barcodeId` | int / int / String |
| GroupDefinition | `id / parentGroupId / unitId` | int / int? / int? |
| UnitDefinition | `id / unitGroupId / conversionBaseUnitId` | int / int? / int? |
| Die | `id / toolCode / compatibleMachineGroupIds` | String / String / List<int> |
| Machine | `id / assetId / groupId` | String / String / int? |

## Conventions & caveats

_Cross-cutting observations from the audit — read before minting a new identifier._

1. Three coexisting ID families cause inconsistency: (a) SQLite INTEGER PRIMARY KEY AUTOINCREMENT rowids for almost every core table; (b) TEXT natural/business keys as PKs (order_headers PK = order_no, report_groups PK = code, sandbox_client_configs/pins/sync_states PK = client_id, asset_upload_sessions.id is TEXT); (c) timestamp-based generated codes.

2. The timestamp-code family is large and internally inconsistent in style: PAR-${Date.now()}-${rand} (1523), CHD-${suffix}-${idx} (1529), MAT-${Date.now()}-${rand5} (9789), mov-${Date.now()}-${rand} (10373/10485), MACH-${Date.now()} (19073), DIE-${Date.now()} (19198), LOT-SCRAP-${Date.now()}-${rand} (23463), BATCH-${Date.now()} (24450), and object_key uniqueStem ${Date.now()}-${sha256[:12]} (12057). These rely on Date.now()+Math.random() for uniqueness (no DB uniqueness guarantee on most), so they are collision-prone under high throughput and non-monotonic across clock skew; contrast with the DB-sequenced monotonic schemes below.

3. Sequential zero-padded human codes are generated via SELECT MAX/COUNT + padStart, a separate convention: DC-/RC-#####  (generateChallanNumber, 7869-7886), INV-##### (generateInvoiceNumber, 10730-10742). These are DB-derived (race-prone without a transaction/lock but monotonic), unlike the timestamp family.

4. Barcode prefix taxonomy: PAR- (parent), CHD- (child), MAT- (standalone material), LOT-RUN-.../LOT-SCRAP-... (lot barcodes), plus item-selection/variation-composed barcodes. normalizeBarcode (1513) enforces a normalization/uniqueness key. The LOT- family overlaps conceptually with both 'Material Barcode' and 'Lot Code' entries, a potential duplicate/overlap.

5. Migration-vs-runtime table drift: migrations/001-init.sql defines legacy tables `orders`, `delivery_challan_orders`, and `order_material_allocations` that the runtime server.js schema replaced with order_headers/order_items, delivery_challan_order_items, and inventory_reservations respectively. order_material_allocations (with its own PK+FKs) was never migrated into the inventory. The inventory was clearly generated from server.js CREATE TABLE blocks only, so migration-exclusive identifiers are systematically absent.

6. changelog and global_audit_logs tables live only in .sql migrations (012, 016), not in server.js CREATE TABLE; their id/record_id/entity_id columns are in the list but no explicit 'changelog PK (id)' / 'global_audit_logs PK (id)' row exists, unlike every server.js table which got an explicit '<table> PK' entry — a labeling inconsistency in the inventory itself.

7. object_key is UNIQUE on uploaded_assets and po_documents but merely NOT NULL (non-unique) on the *_upload_sessions staging tables and on challan_templates — same identifier, inconsistent uniqueness guarantees across tables.

8. reason_code, source_challan_type, and reference_type on inventory_movements are free-text enum strings set at call sites with no lookup table, so they are effectively un-validated identifier-ish discriminators (e.g. 'challan-deletion' hyphenated vs 'pipeline_run' underscored — inconsistent casing/separators within the same column).

