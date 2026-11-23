'use strict';

// ---------------------------------------------------------------------------
// Kernel registry — the single source of truth for module identity.
//
// Everything the border system needs to know about a module is declared here
// once: label, UI grouping, API path segments, permission keys (coarse CRUD,
// fine capabilities), per-record grant sources, Track labels, asset-entity
// guards, and (provisionally) table ownership for the territory meter.
//
// server.js consumes the derived exports at the bottom; their shapes are
// exactly the structures that used to be defined inline across seven separate
// maps. Adding a module = adding one manifest entry below. Forgetting a
// parallel map is no longer possible, because there are no parallel maps.
//
// Kernel constitution (see Docs/architecture/00-kernel-and-items-evacuation.md):
//   K1 inversion · K2 legacy freeze · K3 territory metering
//   K4 one question, one border · K5 ports/events only between modules
// ---------------------------------------------------------------------------

const CRUD_OPS = ['create', 'read', 'update', 'delete'];

const OP_LABELS = {
  create: 'Create',
  read: 'View',
  update: 'Update',
  delete: 'Delete',
};

// Declaration order matters: it is the module order shown in permission UIs.
// `pathSegments`: first URL segment(s) after /api that this module answers for
//   (central CRUD gate). Special-case routing rules stay in moduleOpForRequest.
// `recordSource`: how to list/label records for per-record (row-level) grants.
// `trackTables`: table name -> singular noun for the Track activity feed.
// `tables`: DECLARED ownership for the territory meter. Declared != evacuated:
//   `evacuated: false` means the code still lives in legacy/server.js.
const MODULES = {
  orders: {
    label: 'Orders',
    pathSegments: ['orders', 'order-items', 'order-po-uploads', 'order-po-documents'],
    recordSource: { table: 'order_items', idCol: 'id', label: "COALESCE(NULLIF(TRIM(order_no), ''), 'Order ' || id)" },
    tables: [
      'order_headers', 'order_items', 'order_activity_log', 'order_status_history',
      'order_material_requirements', 'order_po_documents',
      'po_documents', 'po_upload_sessions',
      'procurement_requests', 'procurement_request_lines',
      'procurement_request_line_sources', 'procurement_activity_log',
      // What came back against an order. It belonged to no module until now.
      'order_returns',
    ],
    // Declared reads: see the note on production's. The order list computes
    // each line's delivered quantity from challans' lines inside the one
    // paged, filtered query, and its run status from production's runs
    // through a fragment production hands over as text.
    reads: {
      delivery_challan_items: 'the order list sums what was delivered against each line inside its paged, filtered query',
      delivery_challans: 'the same subquery leaves cancelled challans out',
    },
    evacuated: true,
  },
  inventory: {
    label: 'Inventory',
    pathSegments: ['inventory', 'materials', 'barcode'],
    recordSource: { table: 'materials', idCol: 'barcode', label: "COALESCE(NULLIF(TRIM(name), ''), barcode)" },
    tables: [
      'materials', 'material_activity', 'material_group_item_links',
      'material_group_preferences', 'material_group_properties', 'material_group_units',
      'inventory_movements', 'inventory_reservations', 'inventory_alerts',
      'inventory_stock_positions', 'inventory_sets', 'inventory_set_lines',
      'scan_history',
    ],
    evacuated: true,
  },
  challans: {
    label: 'Delivery Challans',
    pathSegments: [
      'challans', 'delivery-challans', 'invoices', 'reconciliation',
      'challan-templates', 'reports', 'templates',
    ],
    recordSource: { table: 'delivery_challans', idCol: 'id', label: "COALESCE(NULLIF(TRIM(challan_no), ''), 'Challan ' || id)" },
    tables: [
      'delivery_challans', 'delivery_challan_items', 'delivery_challan_order_items',
      'delivery_challan_report_groups', 'delivery_challan_activity_log',
      'challan_templates', 'challan_template_mappings', 'challan_template_upload_sessions',
      'report_groups', 'invoice_headers', 'invoice_lines',
      'piece_barcodes', 'reconciliation_conversion_overrides', 'reconciliation_waste_audit',
    ],
    // Declared reads: see the note on production's.
    reads: {
      order_items: 'the reconciliation report joins every issued challan line to its order line, in one statement',
      inventory_movements: 'the waste audit finds which reception an older material came in on, by joining the ledger to its own challans',
    },
    evacuated: true,
  },
  production: {
    label: 'Production',
    pathSegments: ['production', 'production-runs', 'pipeline-runs', 'telemetry'],
    // stage_reconciliations is written only by production (a stage's numbers).
    // piece_barcodes is not here: the tags are made and marked returned by
    // challans, and production only reads one when a sheet is scanned.
    // order_pipeline_assignments is the run's link to the order lines it makes:
    // production writes it when a run is created.
    tables: [
      'production_runs', 'pipeline_runs', 'run_barcode_inputs', 'production_scrap',
      'stage_reconciliations', 'order_pipeline_assignments',
      // Which machine a run's stage is on. Claimed 2026-11-18.
      'run_machine_assignments',
    ],
    // Tables of other modules this one still reads directly, and why. A
    // declared read is a known debt, counted apart from the undeclared ones by
    // test/module-borders.test.js. It goes when the owner can keep a copy
    // up to date (events) or answer the whole question itself.
    reads: {
      // Finished output for a challan is searched by item name and leaves out
      // archived items, inside one filtered, limited query.
      items: 'the completed-output list filters and searches on the item, in one query',
    },
    evacuated: true,
  },
  jobs: {
    label: 'Jobs',
    // The routes answer under freelancer-*, not under `jobs`. Declared here so
    // the territory meter counts them as this module's; the inline gate in
    // server.js still does not map them, so they keep the legacy write gate.
    pathSegments: ['jobs', 'freelancer-jobs', 'freelancer-portal'],
    tables: ['freelancer_jobs', 'freelancer_job_batches', 'freelancer_job_tasks'],
    evacuated: true,
  },
  action_center: {
    label: 'Action Center',
    // `delete-requests` is declared so the meter counts those routes as this
    // module's. The central gate still excludes it (reviewers are checked by
    // delete_requests.review and the write gate), and server.js's inline copy of
    // the gate maps does not change.
    pathSegments: ['action-center', 'trash', 'delete-requests'],
    tables: ['delete_requests', 'deleted_records'],
    // Declared reads: see the note on production's. The integrity scan is the
    // one place whose job is to look across modules; each of these is a
    // LEFT JOIN that finds a reference to a record that is gone.
    reads: Object.fromEntries(
      ['items', 'groups', 'units', 'order_items', 'clients', 'sub_contractors',
        'delivery_challans', 'vendors', 'inventory_movements'].map((table) => [
        table,
        'the integrity scan joins across modules to find references to records that no longer exist',
      ]),
    ),
    evacuated: true,
  },
  // Masters sub-entities (grouped under "Masters" in the UI tree):
  people: {
    label: 'People',
    group: 'Masters',
    pathSegments: ['employees', 'departments'],
    recordSource: { table: 'employees', idCol: 'id', label: 'name' },
    trackTables: { employees: 'Person' },
    tables: ['employees', 'departments'],
    evacuated: true,
  },
  clients: {
    label: 'Clients',
    group: 'Masters',
    // `portal` is the B2B buyer's side of a client (login, catalogue, cart,
    // order). Declared so the meter counts it as this module's; the inline gate
    // in server.js does not map it, so it keeps the legacy write gate.
    pathSegments: ['clients', 'sub-contractors', 'portal'],
    recordSource: { table: 'clients', idCol: 'id', label: 'name' },
    // party_contacts (056) is generic over party_type, but only clients use it
    // today and its routes nest under /api/clients, so clients owns it.
    trackTables: { clients: 'Client', party_contacts: 'Contact' },
    tables: [
      'clients', 'sub_contractors', 'party_contacts',
      'portal_users', 'portal_carts', 'client_portal_catalog',
      'portal_invites',
    ],
    evacuated: true,
  },
  vendors: {
    label: 'Vendors',
    group: 'Masters',
    pathSegments: ['vendors'],
    recordSource: { table: 'vendors', idCol: 'id', label: 'name' },
    trackTables: { vendors: 'Vendor' },
    tables: ['vendors'],
    evacuated: true,
  },
  items: {
    label: 'Items',
    group: 'Masters',
    pathSegments: ['items', 'groups', 'item-sheet-properties'],
    recordSource: { table: 'items', idCol: 'id', label: "COALESCE(NULLIF(TRIM(display_name), ''), name)" },
    trackTables: { items: 'Item' },
    tables: [
      'items', 'groups', 'group_item_memberships',
      'item_variation_nodes', 'item_variations', 'item_variation_values',
      'item_variation_dimensions', 'item_property_schema', 'item_unit_conversions',
      'item_bom_lines', 'variation_stock',
      'item_deal_contacts', 'item_deals', 'item_deal_people', 'item_sheet_properties',
      // Claimed 2026-11-18; nobody declared them. item_dies and item_machines
      // are the part's own record of its tools (the legacy pair entity_links
      // did not replace); material_types is the Material input type's master.
      'item_dies', 'item_machines', 'item_attachments', 'item_pipeline_baselines',
      'material_types',
    ],
    // Declared reads: see the note on production's.
    reads: {
      order_items: 'a group\'s overview and its cover pictures rank items by how often they are ordered, inside the ranking query; the item list counts them for usage',
      // The item list and a group's row are one statement each, with usage
      // counted and the developed-for names joined in; an item's DTO is built
      // for every row of a list, so its unit, machine and die joins stay too.
      // Asking per row would multiply the calls by the length of the list.
      delivery_challan_items: 'the item list counts the challan lines that carry each item, in its one statement',
      order_material_requirements: 'the item list counts the requirements that name each item, in its one statement',
      materials: 'the item list and a group\'s row count the materials that stand for them, in their one statement',
      material_group_item_links: 'the item list counts the material-group links that name each item, in its one statement',
      pipeline_templates: 'the item list joins each item\'s default pipeline name, in its one statement',
      clients: 'the item list joins who each item was developed for, in its one statement',
      sub_contractors: 'the item list joins the contractor each item was developed for, in its one statement',
      party_contacts: 'the item list folds the people of each item\'s deal into one JSON column, in its one statement',
      units: 'an item\'s DTO joins the names of its conversion units, for every row of a list',
      machines: 'an item\'s DTO joins its linked machines, for every row of a list',
      dies: 'an item\'s DTO joins its linked dies, for every row of a list',
    },
    evacuated: true,
  },
  units: {
    label: 'Units',
    group: 'Masters',
    // `unit-groups` (the families) was answered by no module's gate until
    // 2026-11-18: any signed-in user could read it and the legacy write gate
    // decided writes.
    pathSegments: ['units', 'unit-groups'],
    recordSource: { table: 'units', idCol: 'id', label: 'name' },
    trackTables: { units: 'Unit' },
    tables: ['units', 'unit_groups', 'unit_conversion_points'],
    evacuated: true,
  },
  process_routes: {
    label: 'Process Routes',
    group: 'Masters',
    // Nested under /api/items on purpose (see modules/process_routes/routes.js),
    // so there is no path segment of its own to declare here. Listed so the
    // tables below have one owner rather than being nobody's.
    pathSegments: [],
    trackTables: { process_stages: 'Stage' },
    tables: ['process_stages', 'process_routes', 'process_route_steps'],
    evacuated: true,
  },
  machines: {
    label: 'Machines',
    group: 'Masters',
    pathSegments: ['machines'],
    recordSource: { table: 'machines', idCol: 'id', label: 'name' },
    trackTables: { machines: 'Machine' },
    tables: ['machines'],
    evacuated: true,
  },
  dies: {
    label: 'Dies',
    group: 'Masters',
    // `die-makers` is the master behind a die's "made by". It is part of die
    // tooling rather than a module of its own, so it carries no permission
    // keys of its own and is gated by dies.read/create/update/delete.
    pathSegments: ['dies', 'die-makers'],
    recordSource: { table: 'dies', idCol: 'id', label: "COALESCE(NULLIF(TRIM(tool_code), ''), 'Die ' || id)" },
    trackTables: { dies: 'Die', die_makers: 'Die maker' },
    tables: ['dies', 'die_makers'],
    evacuated: true,
  },
  pipelines: {
    label: 'Pipelines',
    group: 'Masters',
    // The pipeline designer lives under /production/pipeline-templates; the
    // special-case prefix test stays in moduleOpForRequest.
    pathSegments: [],
    recordSource: { table: 'pipeline_templates', idCol: 'id', label: 'name' },
    trackTables: { pipeline_templates: 'Pipeline' },
    tables: ['pipeline_templates'],
    evacuated: true,
  },
};

// ---------------------------------------------------------------------------
// Table ownership beyond the fifteen modules.
//
// Every table has exactly one owner: a module above, the kernel, or a module
// that has code and tables but is not registered yet. TABLE_OWNERS is the one
// map the border meter (test/module-borders.test.js) and the territory meter
// read. A table missing from it is a failure, not a default.
// ---------------------------------------------------------------------------

// Identity, sessions, permissions, assets, config, sync and replay
// infrastructure, search telemetry, and the records that are polymorphic by
// construction (links, variation trees, the activity log, the custody ledger),
// which no single business module can own.
const KERNEL_TABLES = [
  // Retried writes apply once (kernel/idempotency.js).
  'idempotency_log',
  'users', 'auth_sessions', 'auth_events',
  'role_permissions', 'user_permission_overrides', 'user_permission_templates',
  'permission_templates', 'permission_template_permissions', 'user_record_permissions',
  'company_profiles', 'uploaded_assets', 'asset_upload_sessions',
  'search_history', 'search_clicks', 'entity_activity_log',
  // A user's favourite items: a preference of the account, read and written
  // by settings and cleared with the account. Reassigned from items 2026-11-19.
  'user_favorite_items',
  'entity_links',
  'entity_variation_nodes', 'entity_variation_versions',
  // Claimed 2026-11-18. The append-only custody ledger and the change log every
  // table's triggers write to; the older audit log; a phone's photo requests;
  // per-user settings; the two migration ledgers.
  'barcode_ledger', 'changelog', 'global_audit_logs', 'photo_requests',
  'user_preferences', 'schema_migrations', '_migrations',
];

// Code and tables, but no entry in MODULES yet (no permission keys, no place in
// the permission screens). Listed so their tables have an owner; registering
// them properly is its own change.
const UNREGISTERED_MODULE_TABLES = {
  payroll: [
    'attendance_records', 'leave_types', 'leave_balances', 'leave_requests',
    'payroll_components', 'payroll_runs', 'payroll_run_details', 'payslips',
    'employee_salary_structures', 'employee_salary_structure_lines',
    'statutory_config',
  ],
};

// Created by old migration files (001, 005) and named by no code at all. They
// are given the owner they would have had, so a fresh database has no unowned
// table; they are candidates for removal, not for use.
const UNUSED_TABLE_OWNERS = {
  orders: 'orders',
  order_material_allocations: 'orders',
  delivery_challan_orders: 'challans',
  portal_messages: 'clients',
};

const TABLE_OWNERS = { ...UNUSED_TABLE_OWNERS };
for (const [moduleKey, manifest] of Object.entries(MODULES)) {
  for (const table of manifest.tables || []) TABLE_OWNERS[table] = moduleKey;
}
for (const [moduleKey, tables] of Object.entries(UNREGISTERED_MODULE_TABLES)) {
  for (const table of tables) TABLE_OWNERS[table] = moduleKey;
}
for (const table of KERNEL_TABLES) TABLE_OWNERS[table] = 'kernel';

// Path segments the central CRUD gate deliberately skips — auth, account
// management, Track, generic asset/upload, and infrastructure paths keep their
// own guards (or the legacy write gate) instead of module CRUD enforcement.
//
// `links` joins them for the same reason `assets` is here: a link spans two
// masters, so there is no single (module, op) to map the path to. Its guard
// asks about both sides instead — see modules/links/routes.js.
//
// `variations` is here because the module it belongs to is named by the entity
// type IN the path (/variations/die/7 is the dies module), which the segment
// map cannot express — see modules/variations/routes.js.
const MODULE_GATE_EXCLUDED_SEGMENTS = new Set([
  '', 'auth', 'me', 'users', 'admins', 'permissions', 'permission-templates',
  'audit', 'sessions', 'track', 'delete-requests', 'assets', 'upload',
  'delete-s3-object', 'favorites', 'sandbox-config', 'notifications', 'health',
  'record-options', 'links', 'variations', 'dev',
  // kernel/system-routes.js: status for any signed-in user, metrics for an
  // admin or the metrics token — guarded there, not by a module's CRUD keys.
  'system',
]);

// Capability keys — signed off individually, NOT part of the module CRUD grid.
const CAPABILITY_DESCRIPTORS = {
  'challans.reconcile': {
    label: 'In-use reconciliation',
    description: 'Settle internal-use (in-use) challans back into inventory.',
  },
  'inventory.request_delete': {
    label: 'Request inventory deletion',
    description: 'Create delete requests for inventory records.',
  },
  'delete_requests.review': {
    label: 'Review delete requests',
    description: 'Approve or reject pending delete requests.',
  },
  'users.read': {
    label: 'View accounts',
    description: 'Read the account directory.',
  },
  'users.create_user': {
    label: 'Create staff logins',
    description: 'Create staff login accounts.',
  },
  'users.create_admin': {
    label: 'Create admins',
    description: 'Create admin accounts (super admin only).',
  },
  'users.update_status': {
    label: 'Activate / deactivate accounts',
    description: 'Enable or disable login accounts.',
  },
  'users.reset_password': {
    label: 'Reset passwords',
    description: 'Reset passwords for managed accounts.',
  },
  'users.manage_permissions': {
    label: 'Manage permissions',
    description: "Edit other users' permissions and roles.",
  },
  'sessions.manage': {
    label: 'Manage sessions',
    description: 'View and revoke user sessions.',
  },
  'audit.read': {
    label: 'View Track / activity',
    description: 'Read activity and security events.',
  },
  'config.read': {
    label: 'Legacy config read',
    description: 'Internal legacy key (superseded by per-module View).',
  },
  'config.write': {
    label: 'Legacy config write',
    description: 'Internal legacy key (superseded by module Create/Update/Delete).',
  },
  'login.mobile': {
    label: 'Mobile login access',
    description: 'Allow the user to sign in from the mobile app.',
  },
  'login.desktop': {
    label: 'Desktop login access',
    description: 'Allow the user to sign in from the desktop/web app.',
  },
};

// Fine capability keys. Each belongs to a module and falls back to a coarse
// `<module>.<parentOp>` right when not explicitly granted. Kept as one flat
// ordered map (insertion order is the UI listing order).
const FINE_PERMISSION_DESCRIPTORS = {
  'orders.status_change': { module: 'orders', parentOp: 'update', label: 'Change order status', description: 'Change order status across workflow stages.' },
  'orders.po_upload': { module: 'orders', parentOp: 'update', label: 'Upload PO documents', description: 'Attach PO documents to an order.' },
  'orders.po_download': { module: 'orders', parentOp: 'read', label: 'Download PO documents', description: 'Download attached PO documents.' },
  'orders.report.view': { module: 'orders', parentOp: 'read', label: 'View production reports', description: 'View order production summary reports.' },
  'orders.report.export': { module: 'orders', parentOp: 'read', label: 'Export production reports', description: 'Export order production reports to PDF/CSV.' },
  'orders.item_history.read': { module: 'orders', parentOp: 'read', label: 'View item history', description: 'View historical variation line changes.' },
  'orders.production.read': { module: 'orders', parentOp: 'read', label: 'View order pipeline runs', description: 'View linked production runs for an order.' },

  'challans.issue': { module: 'challans', parentOp: 'update', label: 'Issue delivery challan', description: 'Transition draft challans to issued state.' },
  'challans.cancel': { module: 'challans', parentOp: 'update', label: 'Cancel delivery challan', description: 'Cancel issued delivery challans.' },
  'challans.assign_report_group': { module: 'challans', parentOp: 'update', label: 'Assign report group', description: 'Assign report group tags to challans.' },
  'challans.print': { module: 'challans', parentOp: 'read', label: 'Print delivery challan', description: 'Print or preview delivery challans.' },
  'challans.asset.upload': { module: 'challans', parentOp: 'update', label: 'Upload challan assets', description: 'Attach signatures or files to a challan.' },

  'inventory.stock.read': { module: 'inventory', parentOp: 'read', label: 'View stock overview', description: 'View aggregate inventory stock balances.' },
  'inventory.health.read': { module: 'inventory', parentOp: 'read', label: 'View inventory health KPIs', description: 'View health indicators and alerts.' },
  'inventory.material.read': { module: 'inventory', parentOp: 'read', label: 'View material details', description: 'View material master details.' },
  'inventory.material.activity.read': { module: 'inventory', parentOp: 'read', label: 'View material activity', description: 'View audit activity log for materials.' },
  'inventory.barcode.lookup': { module: 'inventory', parentOp: 'read', label: 'Lookup barcodes', description: 'Scan and resolve material barcodes.' },
  'inventory.material.create': { module: 'inventory', parentOp: 'create', label: 'Create materials', description: 'Add new material master records.' },
  'inventory.material.update': { module: 'inventory', parentOp: 'update', label: 'Update materials', description: 'Edit existing material properties.' },
  'inventory.material.delete': { module: 'inventory', parentOp: 'delete', label: 'Delete materials', description: 'Hard delete material records.' },
  'inventory.material.scan': { module: 'inventory', parentOp: 'update', label: 'Scan material stock', description: 'Perform material barcode scans.' },
  'inventory.material.link': { module: 'inventory', parentOp: 'update', label: 'Link materials', description: 'Link parent/child material relationships.' },
  'inventory.material.unlink': { module: 'inventory', parentOp: 'update', label: 'Unlink materials', description: 'Remove material linkages.' },
  'inventory.movement.create': { module: 'inventory', parentOp: 'create', label: 'Create stock movements', description: 'Log manual inventory transfers/movements.' },
  'inventory.set.read': { module: 'inventory', parentOp: 'read', label: 'View inventory sets', description: 'View material sets.' },
  'inventory.set.create': { module: 'inventory', parentOp: 'create', label: 'Create inventory sets', description: 'Create new material sets.' },
  'inventory.set.update': { module: 'inventory', parentOp: 'update', label: 'Update inventory sets', description: 'Modify material set definitions.' },
  'inventory.set.delete': { module: 'inventory', parentOp: 'delete', label: 'Delete inventory sets', description: 'Delete material sets.' },

  'items.short_code.set': { module: 'items', parentOp: 'update', label: 'Set item short code', description: 'Assign or update item short codes.' },
  'items.group.reassign': { module: 'items', parentOp: 'update', label: 'Reassign item group', description: 'Change item group assignments.' },
  'items.variation.manage': { module: 'items', parentOp: 'update', label: 'Manage variation nodes', description: 'Configure item variation trees.' },
  'items.unit.manage': { module: 'items', parentOp: 'update', label: 'Manage item units', description: 'Set primary/secondary units for items.' },
  'items.available_for_purchase.toggle': { module: 'items', parentOp: 'update', label: 'Toggle purchase status', description: 'Mark items available for purchase.' },
  'items.asset.upload': { module: 'items', parentOp: 'update', label: 'Upload item images/assets', description: 'Attach images or files to items.' },
  'items.asset.list': { module: 'items', parentOp: 'read', label: 'View item assets', description: 'List attached item images and files.' },
  'items.track.read': { module: 'items', parentOp: 'read', label: 'View item track history', description: 'View audit log for items.' },

  'people.employee.read': { module: 'people', parentOp: 'read', label: 'View employee directory', description: 'List employee staff records.' },
  'people.employee.create': { module: 'people', parentOp: 'create', label: 'Create employees', description: 'Add new staff employee records.' },
  'people.employee.update': { module: 'people', parentOp: 'update', label: 'Update employees', description: 'Edit employee staff details.' },
  'people.employee.delete': { module: 'people', parentOp: 'delete', label: 'Delete employees', description: 'Remove employee staff records.' },
  'people.department.read': { module: 'people', parentOp: 'read', label: 'View departments', description: 'View department structure.' },
  'people.department.create': { module: 'people', parentOp: 'create', label: 'Create departments', description: 'Add new department units.' },
  'people.department.update': { module: 'people', parentOp: 'update', label: 'Update departments', description: 'Edit department details.' },
  'people.department.delete': { module: 'people', parentOp: 'delete', label: 'Delete departments', description: 'Delete department units.' },

  'users.delete': { module: 'people', parentOp: 'delete', label: 'Delete user login accounts', description: 'Permanently remove login accounts.' },
  'users.link_login': { module: 'people', parentOp: 'update', label: 'Link employee login', description: 'Link staff employee to a login account.' },
  'users.unlink_login': { module: 'people', parentOp: 'update', label: 'Unlink employee login', description: 'Unlink employee staff from a login account.' },

  'audit.export': { module: 'action_center', parentOp: 'read', label: 'Export audit logs', description: 'Download Track/Audit logs as CSV.' },
};

// Legacy route-guard keys whose per-route requirePermission() is a no-op:
// enforcement moved to the central per-module CRUD middleware. The keys remain
// valid so hasPermission()/role defaults keep working.
const LEGACY_GUARD_PASSTHROUGH = new Set(['config.read', 'config.write']);

// Entity-aware guards for the generic asset routes (/assets/*, /upload/*).
// Keyed by uploaded_assets.entity_type. Fine keys fall back to the coarse
// module right via FINE_KEY_TO_COARSE_MAP (e.g. items.asset.upload -> items.update).
const ASSET_ENTITY_PERMISSIONS = {
  item: { write: 'items.asset.upload', read: 'items.asset.list' },
  delivery_challan: { write: 'challans.asset.upload', read: 'challans.read' },
  machine: { write: 'machines.update', read: 'machines.read' },
  die: { write: 'dies.update', read: 'dies.read' },
};

// ---------------------------------------------------------------------------
// Derived exports — the exact shapes server.js consumed before consolidation.
// ---------------------------------------------------------------------------

const CRUD_MODULES = Object.keys(MODULES);

const MODULE_LABELS = Object.fromEntries(
  CRUD_MODULES.map((m) => [m, MODULES[m].label]),
);

const MODULE_GROUPS = Object.fromEntries(
  CRUD_MODULES.filter((m) => MODULES[m].group).map((m) => [m, MODULES[m].group]),
);

const MODULE_PERMISSION_KEYS = CRUD_MODULES.flatMap((m) =>
  CRUD_OPS.map((op) => `${m}.${op}`),
);
const MODULE_PERMISSION_SET = new Set(MODULE_PERMISSION_KEYS);

const FINE_PERMISSION_KEYS = Object.keys(FINE_PERMISSION_DESCRIPTORS);
const FINE_KEY_TO_COARSE_MAP = Object.fromEntries(
  Object.entries(FINE_PERMISSION_DESCRIPTORS).map(([key, info]) => [
    key,
    `${info.module}.${info.parentOp}`,
  ]),
);

const CAPABILITY_PERMISSION_KEYS = Object.keys(CAPABILITY_DESCRIPTORS);

const PERMISSION_KEYS = [
  ...MODULE_PERMISSION_KEYS,
  ...CAPABILITY_PERMISSION_KEYS,
  ...FINE_PERMISSION_KEYS,
];

// First-path-segment -> module, for the central CRUD gate. Special cases
// (pipeline designer prefix, employee login sub-actions, challan reconcile)
// remain in moduleOpForRequest.
const PATH_SEGMENT_TO_MODULE = {};
for (const [moduleKey, manifest] of Object.entries(MODULES)) {
  for (const segment of manifest.pathSegments || []) {
    PATH_SEGMENT_TO_MODULE[segment] = moduleKey;
  }
}

// Modules that support per-record (row-level) grants, and how to list/label
// their records for the picker. entity_type == the module key.
const RECORD_OPTION_SOURCES = Object.fromEntries(
  CRUD_MODULES.filter((m) => MODULES[m].recordSource).map((m) => [
    m,
    MODULES[m].recordSource,
  ]),
);

// Human label per tracked entity type (table name -> singular noun).
const TRACK_ENTITY_LABELS = Object.assign(
  {},
  ...CRUD_MODULES.filter((m) => MODULES[m].trackTables).map(
    (m) => MODULES[m].trackTables,
  ),
);

module.exports = {
  MODULES,
  KERNEL_TABLES,
  UNREGISTERED_MODULE_TABLES,
  UNUSED_TABLE_OWNERS,
  TABLE_OWNERS,
  CRUD_MODULES,
  CRUD_OPS,
  OP_LABELS,
  MODULE_LABELS,
  MODULE_GROUPS,
  MODULE_PERMISSION_KEYS,
  MODULE_PERMISSION_SET,
  CAPABILITY_DESCRIPTORS,
  CAPABILITY_PERMISSION_KEYS,
  FINE_PERMISSION_DESCRIPTORS,
  FINE_PERMISSION_KEYS,
  FINE_KEY_TO_COARSE_MAP,
  PERMISSION_KEYS,
  LEGACY_GUARD_PASSTHROUGH,
  ASSET_ENTITY_PERMISSIONS,
  PATH_SEGMENT_TO_MODULE,
  MODULE_GATE_EXCLUDED_SEGMENTS,
  RECORD_OPTION_SOURCES,
  TRACK_ENTITY_LABELS,
};
