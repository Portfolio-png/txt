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
      'order_material_requirements', 'order_pipeline_assignments', 'order_po_documents',
      'po_documents', 'po_upload_sessions',
      'procurement_requests', 'procurement_request_lines',
      'procurement_request_line_sources', 'procurement_activity_log',
    ],
    evacuated: false,
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
    evacuated: false,
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
      'stage_reconciliations', 'reconciliation_conversion_overrides', 'reconciliation_waste_audit',
    ],
    evacuated: false,
  },
  production: {
    label: 'Production',
    pathSegments: ['production', 'production-runs', 'pipeline-runs', 'telemetry'],
    tables: ['production_runs', 'pipeline_runs', 'run_barcode_inputs', 'production_scrap', 'piece_barcodes'],
    evacuated: false,
  },
  jobs: {
    label: 'Jobs',
    pathSegments: ['jobs'],
    tables: ['freelancer_jobs', 'freelancer_job_batches', 'freelancer_job_tasks'],
    evacuated: false,
  },
  action_center: {
    label: 'Action Center',
    pathSegments: ['action-center', 'trash'],
    tables: ['delete_requests', 'deleted_records'],
    evacuated: false,
  },
  // Masters sub-entities (grouped under "Masters" in the UI tree):
  people: {
    label: 'People',
    group: 'Masters',
    pathSegments: ['employees', 'departments'],
    recordSource: { table: 'employees', idCol: 'id', label: 'name' },
    trackTables: { employees: 'Person' },
    tables: ['employees', 'departments'],
    evacuated: false,
  },
  clients: {
    label: 'Clients',
    group: 'Masters',
    pathSegments: ['clients', 'sub-contractors'],
    recordSource: { table: 'clients', idCol: 'id', label: 'name' },
    trackTables: { clients: 'Client' },
    tables: ['clients', 'sub_contractors'],
    evacuated: false,
  },
  vendors: {
    label: 'Vendors',
    group: 'Masters',
    pathSegments: ['vendors'],
    recordSource: { table: 'vendors', idCol: 'id', label: 'name' },
    trackTables: { vendors: 'Vendor' },
    tables: ['vendors'],
    evacuated: false,
  },
  items: {
    label: 'Items',
    group: 'Masters',
    pathSegments: ['items', 'groups'],
    recordSource: { table: 'items', idCol: 'id', label: "COALESCE(NULLIF(TRIM(display_name), ''), name)" },
    trackTables: { items: 'Item' },
    tables: [
      'items', 'groups', 'group_item_memberships',
      'item_variation_nodes', 'item_variations', 'item_variation_values',
      'item_variation_dimensions', 'item_property_schema', 'item_unit_conversions',
      'item_bom_lines', 'variation_stock', 'user_favorite_items',
    ],
    evacuated: true,
  },
  units: {
    label: 'Units',
    group: 'Masters',
    pathSegments: ['units'],
    recordSource: { table: 'units', idCol: 'id', label: 'name' },
    trackTables: { units: 'Unit' },
    tables: ['units', 'unit_groups'],
    evacuated: false,
  },
  machines: {
    label: 'Machines',
    group: 'Masters',
    pathSegments: ['machines'],
    recordSource: { table: 'machines', idCol: 'id', label: 'name' },
    trackTables: { machines: 'Machine' },
    tables: ['machines'],
    evacuated: false,
  },
  dies: {
    label: 'Dies',
    group: 'Masters',
    pathSegments: ['dies'],
    recordSource: { table: 'dies', idCol: 'id', label: "COALESCE(NULLIF(TRIM(tool_code), ''), 'Die ' || id)" },
    trackTables: { dies: 'Die' },
    tables: ['dies'],
    evacuated: false,
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
    evacuated: false,
  },
};

// Path segments the central CRUD gate deliberately skips — auth, account
// management, Track, generic asset/upload, and infrastructure paths keep their
// own guards (or the legacy write gate) instead of module CRUD enforcement.
const MODULE_GATE_EXCLUDED_SEGMENTS = new Set([
  '', 'auth', 'me', 'users', 'admins', 'permissions', 'permission-templates',
  'audit', 'sessions', 'track', 'delete-requests', 'assets', 'upload',
  'delete-s3-object', 'favorites', 'sandbox-config', 'notifications', 'health',
  'record-options',
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
