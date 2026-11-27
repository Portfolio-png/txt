require('dotenv').config();
const express = require('express');
const compression = require('compression');
const { Bonjour } = require('bonjour-service');
const {
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  DeleteObjectCommand,
  S3Client,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const cors = require('cors');
const crypto = require('crypto');
// The universal barcode codec: one code space over every entity, derived
// from stable ids rather than minted, so nothing can be allocated twice.
const barcodes = require('./kernel/barcodes');
// The part number and code rule, shared with GET /api/items/next-part-identity
// so a form's suggestion and what saveItem stamps cannot drift.
const {
  buildPartCode,
  buildVariantPartCode,
  propertyCodeFor,
  groupLineage,
  nextPartNo,
} = require('./modules/items/part-identity');
// The people at a company (056). Required up here, not beside its routes,
// because saveClient and the client DTO reads use its helpers.
const partyContacts = require('./modules/parties/contacts');
// How a party's name and GST compare, and what still names it on delete. Shared
// by clients and vendors, so it lives with neither.
const {
  normalizePartyValue,
  normalizeGstNumber,
  createPartyDeleteBlockers,
} = require('./modules/parties/party-kit');
// Vendors left server.js (the first of the masters to). What it needs from the
// challans module comes through a port, not a join.
const { createChallansPorts } = require('./modules/challans/ports');
const { createVendorService, rowToVendorDto } = require('./modules/vendors/service');
const registerVendorRoutes = require('./modules/vendors/routes');
// The freelancer job pool. Its one outward reach, a worker's employee row, is a
// people port.
const { createPeoplePorts } = require('./modules/people/ports');
const { createJobsService } = require('./modules/jobs/service');
const registerJobsRoutes = require('./modules/jobs/routes');
// The machine master. Whether a live run holds a machine is asked of the
// production port.
const { createProductionPorts, orderItemRunStatusSql } = require('./modules/production/ports');
const { createProductionService } = require('./modules/production/service');
const { registerProductionRoutes } = require('./modules/production/routes');
const { createMachineService } = require('./modules/machines/service');
const registerMachineRoutes = require('./modules/machines/routes');
// The die master. Its code rules are in modules/dies/die-identity.js; the
// sibling master "made by" is registered further down.
const { createDieService } = require('./modules/dies/service');
const registerDieRoutes = require('./modules/dies/routes');
// The client master, its sub-contractors and the B2B portal. What it needs from
// orders (line counts, placing an order) comes through the orders port.
const { createOrdersPorts } = require('./modules/orders/ports');
const { createOrdersService } = require('./modules/orders/service');
const registerOrderRoutes = require('./modules/orders/routes');
const registerOrderReportRoutes = require('./modules/orders/reports');
const { createChallanTemplateService } = require('./modules/challans/templates');
const registerChallanTemplateRoutes = require('./modules/challans/template-routes');
const { createInvoiceService } = require('./modules/challans/invoices');
const registerInvoiceRoutes = require('./modules/challans/invoice-routes');
const { createChallanReportService } = require('./modules/challans/reports');
const registerChallanReportRoutes = require('./modules/challans/report-routes');
const { createChallanService } = require('./modules/challans/service');
const registerChallanRoutes = require('./modules/challans/routes');
const { createClientService } = require('./modules/clients/service');
const registerClientRoutes = require('./modules/clients/routes');
const registerClientPortalRoutes = require('./modules/clients/portal-routes');
// The people master. modules/people/ports.js (the read other modules use) was
// already here; the service and routes join it.
const { createPeopleService } = require('./modules/people/service');
const registerPeopleRoutes = require('./modules/people/routes');
// Pipeline templates, on both route sets. Whether a template has runs is asked
// of the production port.
const { createPipelineService } = require('./modules/pipelines/service');
const registerPipelineRoutes = require('./modules/pipelines/routes');
// The inventory module (sets so far), and the port other modules reach it by.
const { createInventoryService } = require('./modules/inventory/service');
const { createInventoryPorts } = require('./modules/inventory/ports');
const registerInventoryRoutes = require('./modules/inventory/routes');
// The action center: the trash today, delete requests and the integrity scan next.
const { createTrashService } = require('./modules/action_center/service');
const registerActionCenterRoutes = require('./modules/action_center/routes');
const { createDeleteRequestService } = require('./modules/action_center/delete-requests');
// A part's section tree and the entity_links it stands for (057).
const sectionTree = require('./modules/items/section-tree');
const fs = require('fs');
const { EventEmitter } = require('events');
const { imageSize } = require('image-size');
const path = require('path');
const PDFDocument = require('pdfkit');
const morgan = require('morgan');
const sqlite3 = require('sqlite3').verbose();
const Sentry = require("@sentry/node");
let nodeProfilingIntegration = null;
try {
  const profilingNode = require("@sentry/profiling-node");
  nodeProfilingIntegration = profilingNode.nodeProfilingIntegration;
} catch (e) {
  console.warn("Sentry CPU Profiler not supported on this Node version. Skipping profiling integration.");
}
const { runMigrations } = require('./migrate');

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    integrations: nodeProfilingIntegration ? [nodeProfilingIntegration()] : [],
    tracesSampleRate: 1.0,
    profilesSampleRate: 1.0,
  });
}

try {
  // Optional local/server convenience. Production should still inject env vars.
  // This makes EC2 redeploys reliable even if PM2 doesn't load env_file.
  require('dotenv').config({ path: path.join(__dirname, '.env') });
} catch (_) {
  // dotenv is optional; ignore if not installed.
}

const app = express();
// First, so a request's whole stay is inside it: how long it spent in SQLite,
// as Server-Timing, when PAPER_DB_TIMING=1 (kernel/db-timing.js).
app.use(require('./kernel/db-timing').middleware);
// Request latency, bytes and status per route, SQLite write and WAL numbers
// (kernel/telemetry.js), read at GET /api/system/metrics. Before compression,
// so the bytes out it counts are the ones on the wire.
const serverTelemetry = require('./kernel/telemetry').createTelemetry({
  checkpointEveryMs: Number(process.env.PAPER_WAL_CHECKPOINT_MS ?? 5 * 60 * 1000),
});
app.use(serverTelemetry.middleware);
// The kernel desk: every module's operations, asked for by name from a
// terminal, an HTTP route or another module (kernel/desk.js). A signed-in
// caller is checked with the same hasPermission the HTTP border uses.
//
// A request the central /api gate already let through for exactly this key is
// not asked again: the gate also honours per-record grants (this one order,
// for a user with no orders.read), and a second, narrower answer here would
// take that away. One question, one border.
//
// CONTRACTS ARE ENFORCED. Every operation's input is held to its contract (a
// breach is refused with 400 input_invalid) and its result to its output
// contract (a breach is the module's bug, and throws). That was switched on
// 2026-11-19 on this evidence: the whole test suite and the journey ran in
// report mode and recorded nine violations, every one a test sending a missing
// or empty name on purpose, and none on any result. PAPER_CONTRACTS_MODE=report
// turns enforcement off for a running installation without a code change;
// violations are then recorded at /api/kernel/guard-alerts as before.
const desk = require('./kernel/desk').createDesk({
  defaultMode: 'enforce',
  forceMode: process.env.PAPER_CONTRACTS_MODE === 'report' ? 'report' : null,
  userMay: (actor, key) =>
    actor.cleared === key ||
    hasPermission({ user: actor.user, userPermissions: actor.permissions }, key),
  // A broken contract is recorded where contract problems already go, and read
  // at GET /api/kernel/guard-alerts. Bounded: it is a window, not a log.
  onViolation: ({ operation, side, mode, problems }) => {
    guardAlerts.push({
      route: `operation ${operation} (${side}, ${mode})`,
      details: { problems },
    });
    if (guardAlerts.length > 500) guardAlerts.splice(0, guardAlerts.length - 500);
    // For gathering evidence across a whole test run (each test file boots its
    // own server, so the window above is lost with it): one JSON line per
    // violation, appended to the file named here. Unset in normal running.
    if (process.env.PAPER_CONTRACT_VIOLATIONS_FILE) {
      try {
        fs.appendFileSync(
          process.env.PAPER_CONTRACT_VIOLATIONS_FILE,
          `${JSON.stringify({ operation, side, mode, problems: problems.slice(0, 3) })}\n`,
        );
      } catch (_) {
        // Evidence gathering must never be why a request fails.
      }
    }
  },
});

// Who may ask what of whom. A module that is not listed against an operation is
// refused it, so this block is the map of what crosses a border through the
// desk. (Borders still crossed through hand-wired ports are not here yet.)
const ORDER_LINE_COUNT = 'orders.clients.lineCount';
desk.register('clients', {
  uses: [
    ORDER_LINE_COUNT,
    'orders.clients.lineCounts',
    'orders.clients.lockedLineCount',
    // The B2B portal lives in the clients module and places orders.
    'orders.portal.insertHeader',
    'orders.portal.saveLine',
    // …and shows a client the items in its catalogue.
    'items.rows.forCatalogue',
  ],
});
// The delete-blocker check shared by the client and vendor masters.
desk.register('parties', {
  uses: [ORDER_LINE_COUNT, 'challans.vendorUsageCount', 'items.developedForCount'],
});
// A vendor is counted, and its deliveries listed, from the challans that name it.
desk.register('vendors', {
  uses: [
    'challans.vendorUsageCount',
    'challans.vendorUsageCounts',
    'challans.vendorPurchaseRows',
    'items.describe',
  ],
});
// Search names the item a hit is about; the action centre removes an item or
// group with what hangs off it.
desk.register('people', { uses: ['accounts.users.get', 'accounts.users.byIds', 'accounts.users.setMobilePin'] });
desk.register('search', {
  uses: ['items.describe', 'items.search.hits', 'items.search.configurations', 'inventory.materials.search', 'challans.pieceBarcodes.lookup'],
});
// The kernel's own services publish what modules need of their tables, and
// ask the modules that name a user to forget one being deleted.
desk.register('accounts', {
  // Deferred: the hasher is made further down, once the JWT secret is known.
  operations: require('./modules/accounts/operations')({ get, all, run, hashPin: (pin) => pinHasher.hash(pin) }),
  uses: ['clients.rows.byIds', 'action_center.users.forget', 'orders.users.forget', 'challans.users.forget'],
});
desk.register('assets', { operations: require('./modules/assets/operations')({ get, all, run }) });
desk.register('links', {
  operations: require('./modules/links/operations')({ all, run }),
  // Its own section-tree reconcile, run after a legacy link write.
  uses: ['links.byRelation', 'links.remove', 'links.add'],
});
// An item names its default pipeline, who it was developed for and the people
// of that deal; how much it is used is the sum of what its neighbours say.
desk.register('items', {
  uses: [
    // A part's section tree is kept as links.
    'links.byRelation',
    'links.remove',
    'links.removeRelation',
    'links.add',
    // A material inherits a group's governance; a set lists an item; deleting
    // an item takes it out of every set.
    'inventory.governance.get',
    'inventory.sets.membershipForItem',
    'inventory.sets.removeLinesForItem',
    'inventory.materials.firstForGroup',
    'inventory.items.usageRows',
    'orders.items.usageRows',
    'challans.items.usageRows',
    // A part's unit, machines and dies are checked with their masters when
    // it is saved; the pipeline it is made on is named when it is read.
    'units.rows.first',
    'machines.rows.get',
    'dies.rows.get',
    'pipelines.templates.row',
    'units.rows.get',
    // A rivet's vendor prices name the vendor, and a price for a vendor
    // that does not exist is refused (modules/items/rivets.js).
    'vendors.rows.get',
    'clients.rows.get',
    'clients.subContractors.row',
    'clients.contacts.byIds',
    'orders.items.usage',
    'challans.items.lineCount',
    'inventory.items.usage',
    'inventory.groups.materialCount',
    'inventory.sets.name',
  ],
});
desk.register('action_center', {
  uses: [
    // An approved delete request is carried out by the module that owns the
    // record.
    'items.deleteWithCascade',
    'inventory.materials.deleteRecord',
    'inventory.sets.deleteById',
    'vendors.rows.remove',
    'machines.rows.remove',
    'dies.rows.remove',
    'challans.templates.remove',
  ],
});
desk.register('production', {
  uses: [
    'jobs.runs.forget',
    'orders.lines.get',
    'orders.lines.summary',
    'orders.lines.idsForOrderNo',
    'orders.lines.idsForItem',
    // The template a run was started from, the machine a queue is for, the
    // item a history or a scrap lot is about, and that item's unit.
    'pipelines.templates.row',
    'machines.rows.get',
    'items.rows.get',
    'units.rows.get',
    // Stock put on a run, taken back, and the lots and sets a run makes.
    'inventory.movements.apply',
    'inventory.movements.applyCore',
    'inventory.receipts.mintLot',
    'inventory.receipts.materialForChallanLine',
    'inventory.sets.recordProduced',
    'inventory.sources.forItem',
    'inventory.sources.propose',
    'inventory.scans.increment',
    'inventory.ledger.recomputeSummary',
    'inventory.materials.rowByBarcode',
    // A stage's leftover and scrap notes, and the sheet a scanned tag is.
    'challans.stageNotes.find',
    'challans.stageNotes.create',
    'challans.stageNotes.setQuantity',
    'challans.stageNotes.remove',
    'challans.sheets.findByCode',
    // What an item is, by name; and its stock, taken and returned.
    'items.lookupByName',
    'items.selectionSnapshot',
    'items.stock.applyDelta',
    // An Assembly stage has a job in the freelancer pool.
    'jobs.syncAssemblyJob',
    'jobs.propagateAssemblyRejection',
  ],
});
desk.register('inventory', {
  uses: [
    'assets.primaryFor',
    // An item's tree and row, for shaping a set line or a material's variation.
    'items.variationTree',
    'items.rowById',
    'items.resolveLeaf',
    'orders.lines.customVariationValues',
    'units.rows.get',
    // A material's life story: which runs took it, and for which order lines.
    'production.runs.inputCountForBarcode',
    'production.runs.latestInputForBarcode',
    'production.runs.row',
    'production.runs.orderItemIds',
    'production.runs.stages',
    // …and what it was made on, received by, and wanted for.
    'pipelines.templates.row',
    'machines.rows.byAssetOrName',
    'dies.rows.byToolCode',
    'challans.rows.brief',
    'challans.numbersByIds',
    'challans.customVariationValueRows',
    'orders.items.demand',
    // A set's lines name variations; a material inherits from a group or item.
    'items.rows.get',
    'items.groups.row',
    'items.groups.propertyNamesInUse',
    'items.variations.node',
    'items.variations.codeForValue',
    // An item's identity and stock, and the group a material inherits from.
    'items.describe',
    'items.selectionSnapshot',
    'items.stock.applyDelta',
    'items.stock.holdsWholeItemStock',
    'items.variationStockRows',
    'items.groups.rowById',
    'items.groups.save',
  ],
});
// How much a unit is used is the sum of what its neighbours say.
desk.register('units', {
  uses: ['inventory.units.usageCounts', 'items.units.usageCounts', 'orders.units.usageCounts'],
});
// Reconciling a challan weighs what came back, in kilograms.
// …and names the vendor a reception came from.
desk.register('challans', {
  uses: [
    // A challan's photos and documents.
    'assets.forEntity',
    'assets.forEntities',
    'assets.attachUploaded',
    'assets.sessionEntity',
    'units.ensureKilogram',
    'vendors.rows.get',
    'clients.rows.get',
    // Where a delivered lot came from, what runs have claimed from a
    // reception, and the runs behind the reconciliation report.
    'production.output.source',
    'production.challanLines.runInputs',
    'production.runs.summariesForOrderItems',
    'production.runs.inputsForRuns',
    'production.runs.stageTotals',
    // Issuing, cancelling and settling a challan move stock in the challan's
    // own transaction.
    'inventory.movements.applyCore',
    'inventory.movements.recordForChallan',
    'inventory.movements.forChallan',
    'inventory.movements.recordChallanReversal',
    'inventory.movements.producedLotCodeForRun',
    'inventory.receipts.mintFromChallanLine',
    'inventory.receipts.mintReconcileLot',
    'inventory.receipts.usageForChallan',
    'inventory.receipts.retire',
    // The order lines a delivery is against, and completing them when an
    // in-use challan is settled.
    'orders.rows.get',
    'orders.rows.byIds',
    'orders.rows.forOrderNo',
    'orders.lines.idsForOrderNo',
    'orders.lifecycle.move',
    // The finished output a line delivers from, and what a line's item is
    // counted in.
    'production.output.row',
    'items.rows.get',
    'units.rows.get',
    // A line's item and variation, its stock, and where settled stock is filed.
    'items.selectionSnapshot',
    'items.stock.assertLeaf',
    'items.stock.applyDelta',
    'items.groups.ensureReconcilePrimary',
    'items.groups.ensureReconcileSub',
    'items.ensureForReconcile',
  ],
});
// An order line is for a client.
desk.register('orders', {
  uses: [
    'challans.orderLines.forget',
    'clients.rows.get',
    'clients.subContractors.row',
    // A line's unit and the item's conversion to its primary unit.
    'units.rows.get',
    'items.unitConversions.factor',
    // Deleting a line puts back the stock its runs consumed.
    'inventory.movements.consumedByRun',
    // The reports: what was delivered, on what machines and dies, through
    // which template, and where a consumed sheet came from.
    'challans.deliveries.byOrderLines',
    'challans.sheets.provenance',
    'machines.rows.all',
    'dies.rows.all',
    'pipelines.templates.row',
    // Deleting an order line dissolves its runs, inside one transaction.
    'production.runs.linksForOrderItem',
    'production.runs.dissolve',
    'production.runs.unlinkOrderItem',
    // The order's reports read its runs.
    'production.runs.forOrderItems',
    'production.runs.allWithOrderItem',
    'production.runs.inputs',
    // …and puts back the stock those runs consumed.
    'inventory.movements.applyCore',
    // Which variation of an item a line is for.
    'items.resolveSelection',
  ],
});
// A die may belong to a client; a machine is numbered after its type.
// …and neither is deleted while a live run holds it.
desk.register('dies', { uses: ['clients.exists', 'production.dies.assignedToActiveRun', 'items.dies.forget'] });
desk.register('machines', {
  uses: ['items.groups.name', 'production.machines.assignedToActiveRun', 'items.machines.forget'],
});
// A template runs were started from is kept.
desk.register('pipelines', { uses: ['production.templates.runCount'] });
// A freelancer job is handed to the person whose badge was scanned.
// …and handing it over moves the set out of stock.
desk.register('jobs', {
  uses: [
    'people.employees.idByBarcode',
    'inventory.materials.rowByBarcode',
    'inventory.movements.applyCore',
    'inventory.movements.issuedToWorkerQty',
    'inventory.materials.linkOf',
    // A job's tasks come from its item's bill of materials.
    'items.bom.lines',
  ],
});
const PORT = Number(process.env.PORT || 18080);
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'paper.db');
const FULL_DEMO_SEED_PATH = path.join(__dirname, 'demo_seed_full.json');
const IS_PRODUCTION = process.env.NODE_ENV === 'production';
const SEED_DEMO_DATA_ON_BOOT = parseBooleanEnv(
  process.env.PAPER_SEED_DEMO_DATA_ON_BOOT,
  false,
);
const JWT_SECRET = resolveJwtSecret();
// Staff login PINs are stored as a keyed hash (kernel/pin-hash.js): the key is
// in the environment, never in the database a backup copies.
const pinHasher = require('./kernel/pin-hash').createPinHasher(
  require('./kernel/pin-hash').resolvePinKey({ jwtSecret: JWT_SECRET }),
);
const JWT_TTL_SECONDS = Number(process.env.PAPER_JWT_TTL_SECONDS || 60 * 60 * 12);
const PASSWORD_ITERATIONS = 120000;
const PASSWORD_KEY_LENGTH = 32;
const PASSWORD_POLICY_ERROR =
  'Use at least 10 characters with letters and numbers. Avoid names or common words.';
const S3_UPLOAD_PREFIXES = Object.freeze({
  ITEM_IMAGE: 'masters/items/',
  ORDER_PO: 'orders/po-docs/',
  DELIVERY_CHALLAN: 'logistics/challans/',
  CHALLAN_TEMPLATE_BACKGROUND: 'logistics/challan-templates/',
  CHALLAN_TEMPLATE_STAMP: 'logistics/challan-template-stamps/',
  MACHINE_IMAGE: 'masters/machines/',
  DIE_IMAGE: 'masters/dies/',
  DEPARTMENT_IMAGE: 'masters/departments/',
  PARTY_IMAGE: 'masters/parties/',
  PARTY_DOCUMENT: 'masters/parties/documents/',
});
const COMMON_WEAK_PASSWORDS = new Set([
  'password',
  'password123',
  '123456',
  '12345678',
  '123456789',
  'qwerty',
  'qwerty123',
  'admin',
  'admin123',
  'paper',
  'paper123',
  'letmein',
]);

function parseBooleanEnv(value, fallback = false) {
  if (value == null || String(value).trim() === '') {
    return fallback;
  }
  const normalized = String(value).trim().toLowerCase();
  return ['1', 'true', 'yes', 'y', 'on'].includes(normalized);
}

// ---------------------------------------------------------
// Railway Track Real-time Change Delivery
// ---------------------------------------------------------
const changeEmitter = new EventEmitter();

/// Tables whose changelog rows are written by database triggers
/// (migrations/040-changelog-triggers.sql) rather than by application code.
///
/// `logChange` must not insert for these or every change would be recorded
/// twice — once by the trigger, once by the caller — and a replica would
/// process each delta a second time for no reason.
const TRIGGER_LOGGED_TABLES = new Set([
  'materials', 'item_variation_nodes', 'order_items', 'order_headers',
  'delivery_challan_items', 'delivery_challans', 'items', 'units',
  'groups', 'pipeline_templates', 'pipeline_runs', 'machines',
  'dies', 'clients', 'vendors', 'departments', 'inventory_stock_positions',
  // 058: the masters added since, which had no triggers and so never reached
  // a replica or another session until it reloaded.
  'die_makers', 'process_stages', 'party_contacts', 'item_deal_contacts',
  // 061: the item sheet's property columns.
  'item_sheet_properties',
]);

/// The highest changelog row already pushed to connected clients.
///
/// Initialised to the current head at boot, so starting the server does not
/// replay the whole history at everyone who happens to be connected.
let lastEmittedChangeId = 0;

/// Pushes changelog rows that no connected client has been told about yet.
///
/// Triggers can write the changelog but cannot notify Node, so the live stream
/// tails the table instead of being emitted alongside each write. That is what
/// keeps trigger-written changes — including ones made by a migration or by
/// sqlite3 on the box — reaching a connected client, rather than only being
/// found on the next reconnect.
///
/// Never throws: a business action must not fail because its notification could
/// not be sent, and an undelivered event is recovered by the client's `since`
/// cursor on reconnect.
/// How many changelog rows to keep.
///
/// The table grows with every write and is never read except by a client
/// catching up, so it needs a ceiling. The number has to exceed the largest gap
/// any client could return from: below it, a client that was away too long
/// finds its cursor pointing at pruned history and takes a full snapshot
/// instead — correct, just expensive.
const CHANGELOG_RETENTION = 50000;

/// Drops changelog history no client could still be catching up from.
///
/// Never prunes above the live push cursor, so a row cannot be removed between
/// being written and being delivered.
/// Moves the live-push cursor to the current head without emitting anything.
///
/// Used after a wipe-and-reseed. Seeding writes through the triggers, so a
/// reseeded workspace leaves thousands of changelog rows the cursor has never
/// seen — and the next drain would push every one of them at every connected
/// client, describing the construction of a workspace they should simply
/// reload. A client whose own cursor is now meaningless takes a fresh snapshot,
/// which is what an unrecognised `since` already does.
async function resyncChangelogCursor() {
  try {
    const head = await get('SELECT MAX(id) AS maxId FROM changelog');
    lastEmittedChangeId = Number(head?.maxId || 0);
  } catch (_) {
    // Leaving the cursor where it is only risks re-sending, never losing.
  }
  return lastEmittedChangeId;
}

async function pruneChangelog() {
  try {
    const row = await get('SELECT COUNT(*) AS total, MAX(id) AS head FROM changelog');
    const total = Number(row?.total || 0);
    if (total <= CHANGELOG_RETENTION) return 0;
    const cutoff = Math.min(
      Number(row.head) - CHANGELOG_RETENTION,
      lastEmittedChangeId,
    );
    if (cutoff <= 0) return 0;
    const result = await run('DELETE FROM changelog WHERE id <= ?', [cutoff]);
    return result?.changes || 0;
  } catch (error) {
    console.error('[Realtime] Could not prune the changelog:', error.message);
    return 0;
  }
}

// One drain at a time. Two overlapping drains read past the same cursor and
// pushed the same rows twice — possible whenever two saves landed together,
// and routine once the sweep below runs every second.
let drainInFlight = null;
let drainAgain = false;

async function drainChangelog() {
  if (drainInFlight) {
    drainAgain = true;
    return drainInFlight;
  }
  drainInFlight = (async () => {
    let total = 0;
    do {
      drainAgain = false;
      total += await drainChangelogOnce();
    } while (drainAgain);
    return total;
  })();
  try {
    return await drainInFlight;
  } finally {
    drainInFlight = null;
  }
}

async function drainChangelogOnce() {
  try {
    const rows = await all(
      `SELECT id, table_name, record_id, event_type
       FROM changelog WHERE id > ? ORDER BY id ASC LIMIT 500`,
      [lastEmittedChangeId],
    );
    for (const row of rows) {
      lastEmittedChangeId = Math.max(lastEmittedChangeId, Number(row.id));
      changeEmitter.emit('table-change', {
        id: row.id,
        table: row.table_name,
        recordId: row.record_id,
        eventType: row.event_type,
      });
    }
    // A full page means more are waiting.
    if (rows.length === 500) drainAgain = true;
    return rows.length;
  } catch (error) {
    console.error('[Realtime] Failed to drain the changelog:', error.message);
    return 0;
  }
}

/// Recreates the changelog triggers dropped around a workspace wipe.
///
/// Reads the migration rather than repeating 51 trigger definitions here: two
/// copies of the same DDL is how one of them ends up a table short, and the
/// symptom would be a table that silently stops replicating.
async function restoreChangelogTriggers() {
  try {
    // Both families. 040 records that a row changed; 041 records which OTHER
    // row that change is visible on. Restoring one without the other leaves
    // derived values — an item's variation tree, an order line's status —
    // silently stale after the first factory reset.
    //
    // Every migration that defines one, found by scanning — not a list. The
    // list stopped at 042, so a reset left entity_links (043), the variation
    // nodes (044), process routes (052) and everything after them replicating
    // nothing until the next restart. Only the two families the wipe drops
    // are recreated; the guard triggers (027, 038) are never dropped.
    const dir = path.join(__dirname, 'migrations');
    const files = fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
    for (const file of files) {
      const sql = fs.readFileSync(path.join(dir, file), 'utf8');
      if (!sql.includes('CREATE TRIGGER')) continue;
      for (const statement of sql.split('END;')) {
        const trimmed = statement.trim();
        if (!trimmed || !trimmed.includes('CREATE TRIGGER')) continue;
        const body = trimmed.slice(trimmed.indexOf('CREATE TRIGGER'));
        if (!/CREATE TRIGGER\s+(IF NOT EXISTS\s+)?trg_(changelog|derived)_/.test(body)) continue;
        await run(`${body}\nEND;`).catch(() => {});
      }
    }
  } catch (error) {
    console.error('[Realtime] Could not restore changelog triggers:', error.message);
  }
}

/// Records that something changed, and pushes it.
///
/// For a table with triggers this only pushes: the row's own change was already
/// written by the database, and inserting again would have a replica fetch the
/// same record twice for nothing.
///
/// `force` is for the other kind of change — announcing that a *related* entity
/// is now stale. Filing items into a combination group writes a link table, so
/// the `items` rows never change and no trigger fires, but every one of those
/// items now belongs somewhere new and the group sidebar reads them. Triggers
/// record row changes; this records logical ones, and only a caller knows the
/// difference.
async function logChange(tableName, recordId, eventType, options = {}) {
  try {
    // A trigger already recorded it; only the push is still needed.
    if (options.force || !TRIGGER_LOGGED_TABLES.has(tableName)) {
      await new Promise((resolve, reject) => {
        db.run(
          `INSERT INTO changelog (table_name, record_id, event_type, timestamp) VALUES (?, ?, ?, datetime('now'))`,
          [tableName, recordId, eventType],
          function (err) {
            if (err) reject(err);
            else resolve(this);
          }
        );
      });
    }
    await drainChangelog();
  } catch (err) {
    console.error(`[Realtime] Failed to log change for ${tableName} ${recordId}:`, err);
    // Ignore error so we don't break transactions if the changelog insert fails
  }
}

const USER_ROLES = new Set(['super_admin', 'admin', 'user']);

// --- Per-module CRUD permission model -------------------------------------
// Every top-level module has create/read/update/delete keys. These are the
// keys shown as the module x CRUD grid in a user's Account & Access pane, and
// are enforced centrally by requireApiModulePermission (request path -> module,
// HTTP method -> op). The `login.*` and account-management keys below are
// capabilities, not module CRUD, and are shown/managed separately.
const CRUD_MODULES = [
  'orders',
  'inventory',
  'challans',
  'production',
  'jobs',
  'action_center',
  // Masters sub-entities (grouped under "Masters" in the UI tree):
  'people',
  'clients',
  'vendors',
  'items',
  'units',
  'machines',
  'dies',
  'pipelines',
];
const CRUD_OPS = ['create', 'read', 'update', 'delete'];
const MODULE_LABELS = {
  orders: 'Orders',
  inventory: 'Inventory',
  challans: 'Delivery Challans',
  production: 'Production',
  jobs: 'Jobs',
  action_center: 'Action Center',
  people: 'People',
  clients: 'Clients',
  vendors: 'Vendors',
  items: 'Items',
  units: 'Units',
  machines: 'Machines',
  dies: 'Dies',
  pipelines: 'Pipelines',
};
// UI tree grouping: these modules render under a collapsible "Masters" parent.
const MODULE_GROUPS = {
  people: 'Masters',
  clients: 'Masters',
  vendors: 'Masters',
  items: 'Masters',
  units: 'Masters',
  machines: 'Masters',
  dies: 'Masters',
  pipelines: 'Masters',
};
const OP_LABELS = {
  create: 'Create',
  read: 'View',
  update: 'Update',
  delete: 'Delete',
};
const MODULE_PERMISSION_KEYS = CRUD_MODULES.flatMap((m) =>
  CRUD_OPS.map((op) => `${m}.${op}`),
);
const MODULE_PERMISSION_SET = new Set(MODULE_PERMISSION_KEYS);

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

// Legacy route-guard keys whose per-route requirePermission() is now a no-op:
// enforcement moved to the central per-module CRUD middleware. The keys remain
// valid so hasPermission()/role defaults keep working.
const LEGACY_GUARD_PASSTHROUGH = new Set(['config.read', 'config.write']);

const DEFAULT_ROLE_PERMISSIONS = {
  super_admin: Object.fromEntries(PERMISSION_KEYS.map((key) => [key, true])),
  // Admin: everything except minting other admins.
  admin: Object.fromEntries(
    PERMISSION_KEYS.map((key) => [key, key !== 'users.create_admin']),
  ),
  // Staff: read every module, write nothing by default; sign-in + request
  // deletes. Admins grant specific create/update/delete per staff via the grid.
  user: Object.fromEntries(
    PERMISSION_KEYS.map((key) => {
      if (MODULE_PERMISSION_SET.has(key)) return [key, key.endsWith('.read')];
      const staffCaps = new Set([
        'inventory.request_delete',
        'config.read',
        'login.mobile',
        'login.desktop',
      ]);
      return [key, staffCaps.has(key)];
    }),
  ),
};

// Seed presets (admins can create their own named roles on top of these).
const DEFAULT_PERMISSION_TEMPLATES = [
  {
    name: 'Viewer',
    description: 'Read-only access across every module.',
    permissions: Object.fromEntries(CRUD_MODULES.map((m) => [`${m}.read`, true])),
  },
  {
    name: 'Inventory Operator',
    description: 'Full inventory; view items and orders.',
    permissions: {
      'inventory.read': true,
      'inventory.create': true,
      'inventory.update': true,
      'inventory.request_delete': true,
      'items.read': true,
      'orders.read': true,
    },
  },
  {
    name: 'Masters Manager',
    description: 'Full masters (people, clients, vendors, items, units, machines, dies, pipelines).',
    permissions: Object.fromEntries(
      ['people', 'clients', 'vendors', 'items', 'units', 'machines', 'dies', 'pipelines']
        .flatMap((m) => CRUD_OPS.map((op) => [`${m}.${op}`, true])),
    ),
  },
  {
    name: 'Orders Manager',
    description: 'Full orders; view items, clients and inventory.',
    permissions: {
      'orders.read': true,
      'orders.create': true,
      'orders.update': true,
      'orders.delete': true,
      'items.read': true,
      'clients.read': true,
      'inventory.read': true,
    },
  },
];
const LOGIN_MAX_ATTEMPTS = Number(process.env.PAPER_LOGIN_MAX_ATTEMPTS || 5);
const LOGIN_WINDOW_MINUTES = Number(process.env.PAPER_LOGIN_WINDOW_MINUTES || 15);
const LOGIN_LOCKOUT_MINUTES = Number(process.env.PAPER_LOGIN_LOCKOUT_MINUTES || 15);
let dbReady = false;
let dbInitError = null;

ensureRuntimeConfig();
ensureDatabaseDirectory();

const db = new sqlite3.Database(DB_PATH, (error) => {
  if (error) {
    console.error('Failed to open SQLite database:', error);
    dbInitError = error;
    return;
  }
  console.log(`SQLite database opened at ${DB_PATH}`);
});

// Dedicated connection used ONLY for FK-bypassing hard-deletes and trash
// restores. Foreign-key enforcement is turned OFF permanently on this
// connection (see initDb), so we can delete a still-referenced master (leaving
// a dangling reference for the Action Center to surface) WITHOUT toggling a
// process-wide PRAGMA on the shared connection — which would otherwise leak
// FK-off into concurrent requests, or be silently no-op'd by another request's
// open transaction. WAL mode (set on the main connection, DB-level) lets these
// two connections coexist; busy_timeout makes cross-connection writes wait.
const deleteDb = new sqlite3.Database(DB_PATH, (error) => {
  if (error) {
    console.error('Failed to open SQLite delete connection:', error);
  }
});

// SQLite's own execution time per statement (to separate it from the time a
// write waited for the shared connection) and the timed WAL checkpoint. Started
// by the running server; a test that wants them starts and stops them, since
// the profile hook holds the process open (kernel/telemetry.js).
// Hot backups (kernel/backup.js): VACUUM INTO on a connection of its own, each
// checked with integrity_check. Every PAPER_BACKUP_EVERY_HOURS (24 by default
// in production, off elsewhere) into PAPER_BACKUP_DIR (beside the database by
// default), the newest PAPER_BACKUP_KEEP (14) kept.
const serverBackups = require('./kernel/backup').createBackups({
  dbPath: DB_PATH,
  dir: process.env.PAPER_BACKUP_DIR || path.join(path.dirname(DB_PATH), 'backups'),
  keep: Number(process.env.PAPER_BACKUP_KEEP || 14),
});
const BACKUP_EVERY_HOURS = Number(process.env.PAPER_BACKUP_EVERY_HOURS ?? (IS_PRODUCTION ? 24 : 0));

function startServerTelemetry() {
  serverTelemetry.watchConnection(db);
  serverTelemetry.watchConnection(deleteDb);
  serverTelemetry.startCheckpoints(get);
}

function stopServerTelemetry() {
  serverTelemetry.unwatchConnection(db);
  serverTelemetry.unwatchConnection(deleteDb);
  serverTelemetry.stop();
}

const PROCESS_HANDLER_GUARD = '__paperProcessHandlersRegistered';
if (!globalThis[PROCESS_HANDLER_GUARD]) {
  process.on('uncaughtException', (error) => {
    console.error('Uncaught exception:', error);
  });

  process.on('unhandledRejection', (error) => {
    console.error('Unhandled rejection:', error);
  });

  globalThis[PROCESS_HANDLER_GUARD] = true;
}

function resolveJwtSecret() {
  const configured = String(process.env.PAPER_JWT_SECRET || '').trim();
  if (configured) {
    return configured;
  }
  return 'paper-local-development-secret';
}

function ensureRuntimeConfig() {
  if (!IS_PRODUCTION) {
    return;
  }
  const missing = [];
  if (!String(process.env.PAPER_JWT_SECRET || '').trim()) {
    missing.push('PAPER_JWT_SECRET');
  }
  if (!String(process.env.PAPER_SUPER_ADMIN_EMAIL || '').trim()) {
    missing.push('PAPER_SUPER_ADMIN_EMAIL');
  }
  if (!String(process.env.PAPER_SUPER_ADMIN_PASSWORD || '').trim()) {
    missing.push('PAPER_SUPER_ADMIN_PASSWORD');
  }
  if (missing.length > 0) {
    throw new Error(
      `Missing required production environment variable${missing.length === 1 ? '' : 's'}: ${missing.join(', ')}`,
    );
  }
}

function ensureDatabaseDirectory() {
  const directory = path.dirname(DB_PATH);
  fs.mkdirSync(directory, { recursive: true });
}

function buildCorsOptions() {
  const rawOrigins = String(process.env.PAPER_CORS_ORIGIN || '').trim();
  if (!rawOrigins) {
    return {};
  }
  const allowedOrigins = new Set(
    rawOrigins.split(',').map((origin) => origin.trim()).filter(Boolean),
  );
  return {
    origin(origin, callback) {
      if (!origin || allowedOrigins.has(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error('Origin is not allowed by CORS.'));
    },
  };
}

app.set('trust proxy', 1);
app.disable('x-powered-by');
app.use(morgan('combined'));
app.use(compression());
app.use(cors(buildCorsOptions()));
// Which address the caller reached this server on, so a link made for them
// points back at it — localhost on this machine, the LAN address from another.
app.use((req, _res, next) => {
  requestOrigin.run(`${req.protocol}://${req.get('host')}`, next);
});
app.use(express.json());

const cacheMasterData = (req, res, next) => {
  res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
  next();
};
app.use('/public', express.static(path.join(__dirname, 'public')));

// What is actually running here.
//
// A deploy that swapped the code but left the old process serving used to be
// indistinguishable from one that worked — both answered /health identically.
// The release stamp and commit make the difference visible, which is what lets
// a deploy verify it is talking to the release it just shipped rather than the
// one it replaced.
//
// Read once at boot: they describe this process, and a process that has been
// reloaded onto new code is a new process.
const RELEASE_INFO = Object.freeze({
  // Written by deploy/release.sh into the release directory.
  release: process.env.PAPER_RELEASE || null,
  commit: process.env.PAPER_COMMIT || null,
  startedAt: new Date().toISOString(),
});

app.get('/health', (_req, res) => {
  res.json({
    success: true,
    status: dbReady ? 'ok' : 'starting',
    port: PORT,
    dbPath: IS_PRODUCTION ? null : DB_PATH,
    dbReady,
    dbInitError: dbInitError?.message ?? null,
    release: RELEASE_INFO.release,
    commit: RELEASE_INFO.commit,
    startedAt: RELEASE_INFO.startedAt,
    // Which deployment this is. A staging box answering a production health
    // check is a mistake worth being able to see.
    environment: process.env.PAPER_ENV || (IS_PRODUCTION ? 'production' : 'development'),
    timestamp: new Date().toISOString(),
  });
});

app.use((req, res, next) => {
  if (req.path === '/health') {
    next();
    return;
  }
  if (dbInitError) {
    res.status(500).json({
      success: false,
      message: `Database initialization failed: ${dbInitError.message}`,
      error: `Database initialization failed: ${dbInitError.message}`,
    });
    return;
  }
  if (!dbReady) {
    res.status(503).json({
      success: false,
      message: 'Backend is still starting. Please retry in a moment.',
      error: 'Backend is still starting. Please retry in a moment.',
    });
    return;
  }
  next();
});

const dbTiming = require('./kernel/db-timing');

function rawRun(sql, params = []) {
  return new Promise((resolve, reject) => {
    dbTiming.timed((done) => serverTelemetry.timedWrite('main', sql, (written) => db.run(sql, params, function onRun(error) {
      written(error);
      done();
      if (error) {
        reject(error);
        return;
      }
      resolve(this);
    })));
  });
}

// Every COMMIT first asks the idempotency kernel whether the request
// committing carries an X-Idempotency-Key; if so its row is marked inside this
// same transaction, so the write and the mark land together
// (kernel/idempotency.js). No handler has to know.
function run(sql, params = []) {
  if (typeof sql === 'string' && /^\s*(COMMIT|END)\b/i.test(sql)) {
    return idempotency.beforeCommit().then(() => rawRun(sql, params));
  }
  return rawRun(sql, params);
}

// Runs a statement on the dedicated FK-off delete connection.
function runOnDelete(sql, params = []) {
  return new Promise((resolve, reject) => {
    serverTelemetry.timedWrite('delete', sql, (written) => deleteDb.run(sql, params, function onRun(error) {
      written(error);
      if (error) {
        reject(error);
        return;
      }
      resolve(this);
    }));
  });
}

function get(sql, params = []) {
  return new Promise((resolve, reject) => {
    dbTiming.timed((done) => db.get(sql, params, (error, row) => {
      done();
      if (error) {
        reject(error);
        return;
      }
      resolve(row);
    }));
  });
}

const idempotency = require('./kernel/idempotency').createIdempotency({
  run: (sql, params) => rawRun(sql, params),
  get: (sql, params) => get(sql, params),
});

function all(sql, params = []) {
  return new Promise((resolve, reject) => {
    dbTiming.timed((done) => db.all(sql, params, (error, rows) => {
      done();
      if (error) {
        reject(error);
        return;
      }
      resolve(rows);
    }));
  });
}

async function enableForeignKeys() {
  await run('PRAGMA foreign_keys = ON');
  const row = await get('PRAGMA foreign_keys');
  if (Number(row?.foreign_keys || 0) !== 1) {
    throw new Error('SQLite foreign key enforcement could not be enabled.');
  }
  // WAL mode: readers don't block writers and vice versa.
  // Safe for single-process Node.js + SQLite; persists across connections.
  await run('PRAGMA journal_mode = WAL');
  // Set synchronous mode to NORMAL inside WAL mode. This guarantees application-level
  // transaction safety and eliminates synchronous disk write blocking, making insertions
  // 10x-100x faster, resolving performance bottlenecks on DMG builds on different Macs.
  await run('PRAGMA synchronous = NORMAL');
  // Let a write wait for another connection's write lock instead of erroring.
  await run('PRAGMA busy_timeout = 5000');

  // Configure the dedicated delete connection: FK enforcement OFF for its whole
  // lifetime, and the same busy_timeout so it waits on the main connection's
  // write lock rather than throwing SQLITE_BUSY.
  await runOnDelete('PRAGMA foreign_keys = OFF');
  await runOnDelete('PRAGMA synchronous = NORMAL');
  await runOnDelete('PRAGMA busy_timeout = 5000');
}

function base64UrlEncode(value) {
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
  return buffer
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function base64UrlDecode(value) {
  const normalized = String(value).replace(/-/g, '+').replace(/_/g, '/');
  const padding = normalized.length % 4 === 0 ? '' : '='.repeat(4 - (normalized.length % 4));
  return Buffer.from(normalized + padding, 'base64').toString('utf8');
}

function signJwt(payload) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const body = {
    ...payload,
    iat: now,
    exp: now + JWT_TTL_SECONDS,
  };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedBody = base64UrlEncode(JSON.stringify(body));
  const signature = crypto
    .createHmac('sha256', JWT_SECRET)
    .update(`${encodedHeader}.${encodedBody}`)
    .digest();
  return `${encodedHeader}.${encodedBody}.${base64UrlEncode(signature)}`;
}

function verifyJwt(token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) {
    return null;
  }
  const [encodedHeader, encodedBody, encodedSignature] = parts;
  const expectedSignature = base64UrlEncode(
    crypto
      .createHmac('sha256', JWT_SECRET)
      .update(`${encodedHeader}.${encodedBody}`)
      .digest(),
  );
  const actual = Buffer.from(encodedSignature);
  const expected = Buffer.from(expectedSignature);
  if (actual.length !== expected.length || !crypto.timingSafeEqual(actual, expected)) {
    return null;
  }
  try {
    const payload = JSON.parse(base64UrlDecode(encodedBody));
    if (payload.exp && Number(payload.exp) < Math.floor(Date.now() / 1000)) {
      return null;
    }
    return payload;
  } catch (_) {
    return null;
  }
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto
    .pbkdf2Sync(String(password), salt, PASSWORD_ITERATIONS, PASSWORD_KEY_LENGTH, 'sha256')
    .toString('hex');
  return `pbkdf2$${PASSWORD_ITERATIONS}$${salt}$${hash}`;
}

function verifyPassword(password, storedHash) {
  const parts = String(storedHash || '').split('$');
  if (parts.length !== 4 || parts[0] !== 'pbkdf2') {
    return false;
  }
  const iterations = Number(parts[1]);
  const salt = parts[2];
  const expectedHex = parts[3];
  const actualHex = crypto
    .pbkdf2Sync(String(password), salt, iterations, PASSWORD_KEY_LENGTH, 'sha256')
    .toString('hex');
  const actual = Buffer.from(actualHex, 'hex');
  const expected = Buffer.from(expectedHex, 'hex');
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

function normalizeEmail(value = '') {
  return String(value).trim().toLowerCase();
}

function validatePasswordPolicy(password) {
  if (!password || password.length < 10) return "Password is too weak.";
  return null;
}

function parsePagination(query = {}, { defaultLimit = 25, maxLimit = 200 } = {}) {
  const limit = Math.min(maxLimit, Math.max(1, Number(query.limit || defaultLimit)));
  const offset = Math.max(0, Number(query.offset || 0));
  return { limit, offset };
}

function normalizeNullableDate(value) {
  const raw = String(value || '').trim();
  if (!raw) {
    return null;
  }
  const parsed = Date.parse(raw);
  if (Number.isNaN(parsed)) {
    return null;
  }
  return new Date(parsed).toISOString();
}

function csvEscape(value) {
  const text = String(value ?? '');
  if (!/[",\n]/.test(text)) {
    return text;
  }
  return `"${text.replace(/"/g, '""')}"`;
}

function toCsv(headers, rows) {
  const headerRow = headers.map(csvEscape).join(',');
  const bodyRows = rows.map((row) => row.map(csvEscape).join(','));
  return [headerRow, ...bodyRows].join('\n');
}

function normalizePermissionKey(value = '') {
  return String(value || '').trim();
}

function isKnownPermissionKey(value = '') {
  return PERMISSION_KEYS.includes(normalizePermissionKey(value));
}

function createEmptyPermissionMap() {
  return Object.fromEntries(PERMISSION_KEYS.map((key) => [key, false]));
}

function permissionMapToList(permissionMap = {}) {
  return PERMISSION_KEYS.filter((key) => permissionMap[key] === true);
}

function parseBooleanFlag(value) {
  if (typeof value === 'boolean') {
    return value;
  }
  if (value == null) {
    return false;
  }
  const normalized = String(value).trim().toLowerCase();
  return normalized === '1' || normalized === 'true' || normalized === 'yes';
}

const GROUP_TYPES = new Set(['item', 'machine', 'die']);

function normalizeGroupType(value = 'item') {
  const normalized = String(value || 'item').trim().toLowerCase();
  return GROUP_TYPES.has(normalized) ? normalized : 'item';
}

function primaryGroupNameForType(groupType = 'item') {
  switch (normalizeGroupType(groupType)) {
    case 'machine':
      return 'Primary Machine Group';
    case 'die':
      return 'Primary Die Group';
    case 'item':
    default:
      return 'Primary Item Group';
  }
}

function isPrimaryGroupNameForType(name = '', groupType = 'item') {
  const trimmedName = String(name || '').trim();
  return (
    trimmedName === primaryGroupNameForType(groupType) ||
    (normalizeGroupType(groupType) === 'item' && trimmedName === 'Primary Group') ||
    (normalizeGroupType(groupType) === 'item' && trimmedName === 'Raw material') ||
    (normalizeGroupType(groupType) === 'item' && trimmedName === 'Scrap')
  );
}

function permissionDescriptorFor(key) {
  if (MODULE_PERMISSION_SET.has(key)) {
    const [module, op] = key.split('.');
    return {
      key,
      label: `${OP_LABELS[op] || op} ${MODULE_LABELS[module] || module}`,
      description: `${OP_LABELS[op] || op} ${(MODULE_LABELS[module] || module).toLowerCase()} records.`,
      category: 'module',
      module,
      moduleLabel: MODULE_LABELS[module] || module,
      group: MODULE_GROUPS[module] || null,
      op,
    };
  }
  const fine = FINE_PERMISSION_DESCRIPTORS[key];
  if (fine) {
    return {
      key,
      label: fine.label,
      description: fine.description,
      category: 'fine',
      module: fine.module,
      moduleLabel: MODULE_LABELS[fine.module] || fine.module,
      group: MODULE_GROUPS[fine.module] || null,
      parentOp: fine.parentOp,
      parentKey: `${fine.module}.${fine.parentOp}`,
    };
  }
  const cap = CAPABILITY_DESCRIPTORS[key] || {};
  return {
    key,
    label: cap.label || key,
    description: cap.description || '',
    category: 'capability',
    module: null,
    moduleLabel: null,
    group: null,
    op: null,
  };
}

function permissionDescriptors() {
  return PERMISSION_KEYS.map(permissionDescriptorFor);
}

async function getRolePermissionMap(role) {
  if (role === 'super_admin') {
    return Object.fromEntries(PERMISSION_KEYS.map((key) => [key, true]));
  }
  const rows = await all(
    'SELECT permission_key, is_allowed FROM role_permissions WHERE role = ?',
    [role],
  );
  // Start from the coded defaults so newly-added keys (e.g. the per-module CRUD
  // keys) resolve to a sane value even on a DB seeded before they existed;
  // stored rows then override. Prevents lockouts pre-reseed.
  const defaults = {
    ...createEmptyPermissionMap(),
    ...(DEFAULT_ROLE_PERMISSIONS[role] || {}),
  };
  for (const row of rows) {
    const key = normalizePermissionKey(row.permission_key);
    if (!isKnownPermissionKey(key)) {
      continue;
    }
    defaults[key] = Number(row.is_allowed || 0) === 1;
  }
  return defaults;
}

async function getTemplatePermissionMapForUser(userId) {
  const rows = await all(
    `
    SELECT ptp.permission_key, MAX(ptp.is_allowed) AS is_allowed
    FROM user_permission_templates upt
    INNER JOIN permission_template_permissions ptp ON ptp.template_id = upt.template_id
    WHERE upt.user_id = ?
    GROUP BY ptp.permission_key
    `,
    [userId],
  );
  const templateMap = createEmptyPermissionMap();
  for (const row of rows) {
    const key = normalizePermissionKey(row.permission_key);
    if (!isKnownPermissionKey(key)) {
      continue;
    }
    templateMap[key] = Number(row.is_allowed || 0) === 1;
  }
  return templateMap;
}

async function getAssignedPermissionTemplates(userId) {
  return all(
    `
    SELECT pt.id, pt.name, pt.description, pt.is_system_default, upt.created_at
    FROM user_permission_templates upt
    INNER JOIN permission_templates pt ON pt.id = upt.template_id
    WHERE upt.user_id = ?
    ORDER BY pt.name ASC
    `,
    [userId],
  );
}

async function getEffectivePermissionMap(userId, role) {
  if (role === 'super_admin') {
    return Object.fromEntries(PERMISSION_KEYS.map((key) => [key, true]));
  }
  const rolePermissions = await getRolePermissionMap(role);
  const templatePermissions = await getTemplatePermissionMapForUser(userId);
  const permissionMap = {};
  for (const key of PERMISSION_KEYS) {
    permissionMap[key] =
      rolePermissions[key] === true || templatePermissions[key] === true;
  }
  const overrideRows = await all(
    'SELECT permission_key, is_allowed FROM user_permission_overrides WHERE user_id = ?',
    [userId],
  );
  for (const row of overrideRows) {
    const key = normalizePermissionKey(row.permission_key);
    if (!isKnownPermissionKey(key)) {
      continue;
    }
    permissionMap[key] = Number(row.is_allowed || 0) === 1;
  }
  return permissionMap;
}

async function getUserPermissionSnapshot(user) {
  const roleDefaults = await getRolePermissionMap(user.role);
  const templateDefaults = await getTemplatePermissionMapForUser(user.id);
  const overrideRows = await all(
    'SELECT permission_key, is_allowed FROM user_permission_overrides WHERE user_id = ?',
    [user.id],
  );
  const overrideMap = {};
  for (const row of overrideRows) {
    const key = normalizePermissionKey(row.permission_key);
    if (!isKnownPermissionKey(key)) {
      continue;
    }
    overrideMap[key] = Number(row.is_allowed || 0) === 1;
  }
  const effective = user.role === 'super_admin'
    ? Object.fromEntries(PERMISSION_KEYS.map((key) => [key, true]))
    : Object.fromEntries(
      PERMISSION_KEYS.map((key) => [
        key,
        overrideMap[key] ?? (roleDefaults[key] === true || templateDefaults[key] === true),
      ]),
    );
  return PERMISSION_KEYS.map((key) => {
    if (user.role === 'super_admin') {
      return { key, allowed: true, source: 'super_admin' };
    }
    if (Object.prototype.hasOwnProperty.call(overrideMap, key)) {
      return {
        key,
        allowed: effective[key] === true,
        source: 'override',
      };
    }
    if (templateDefaults[key] === true) {
      return {
        key,
        allowed: true,
        source: 'template',
      };
    }
    return {
      key,
      allowed: effective[key] === true,
      source: 'role',
    };
  });
}

function safeUserDto(row, permissionMap = null, activeSession = null) {
  if (!row) {
    return null;
  }
  const effectivePermissions = permissionMap || createEmptyPermissionMap();
  const dto = {
    id: row.id,
    name: row.name || '',
    email: row.email || '',
    role: row.role || 'user',
    permissions: permissionMapToList(effectivePermissions),
    isActive: Number(row.is_active || 0) === 1,
    failedLoginAttempts: Number(row.failed_login_attempts || 0),
    lockoutUntil: row.lockout_until || null,
    createdByUserId: row.created_by_user_id || null,
    clientId: row.client_id || null,
    clientName: row.client_name || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
  if (row.mobile_pin !== undefined) {
    // The stored PIN is a keyed hash: whether there is one, never what it is.
    dto.hasMobilePin = Boolean(row.mobile_pin);
  }
  // The one moment a PIN can be shown: in the answer that issued it.
  if (row.issued_mobile_pin) {
    dto.mobilePin = row.issued_mobile_pin;
  }
  if (activeSession !== undefined) {
    dto.activeSession = activeSession ? {
      ipAddress: activeSession.ip_address,
      userAgent: activeSession.user_agent,
      lastUsedAt: activeSession.last_used_at,
    } : null;
  }
  return dto;
}

function rowToDeleteRequestDto(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    entityLabel: row.entity_label || '',
    reason: row.reason || '',
    status: row.status,
    requestedByUserId: row.requested_by_user_id,
    requestedByName: row.requested_by_name || '',
    reviewedByUserId: row.reviewed_by_user_id || null,
    reviewedByName: row.reviewed_by_name || '',
    reviewedNote: row.reviewed_note || '',
    reviewedAt: row.reviewed_at || null,
    createdAt: row.created_at,
  };
}

function rowToAuthSessionDto(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    userId: row.user_id,
    createdAt: row.created_at,
    lastUsedAt: row.last_used_at,
    expiresAt: row.expires_at,
    revokedAt: row.revoked_at || null,
    revokedReason: row.revoked_reason || '',
    ipAddress: row.ip_address || '',
    userAgent: row.user_agent || '',
    // 'desktop' | 'mobile' (migrations/063); older rows were desktop logins.
    clientPlatform: row.client_platform || 'desktop',
  };
}

function rowToAuthEventDto(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    eventType: row.event_type,
    actorUserId: row.actor_user_id || null,
    actorUserName: row.actor_user_name || '',
    targetUserId: row.target_user_id || null,
    targetUserName: row.target_user_name || '',
    ipAddress: row.ip_address || '',
    userAgent: row.user_agent || '',
    metadata: parseJson(row.metadata_json, {}),
    createdAt: row.created_at,
  };
}

function getRequestIp(req) {
  return String(req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '')
    .split(',')[0]
    .trim();
}

function getRequestUserAgent(req) {
  return String(req.headers['user-agent'] || '').trim();
}

function hashToken(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

function nowIso() {
  return new Date().toISOString();
}

function minutesFromNow(minutes) {
  return new Date(Date.now() + minutes * 60 * 1000).toISOString();
}

function secondsFromNow(seconds) {
  return new Date(Date.now() + seconds * 1000).toISOString();
}

function isTimestampInFuture(timestamp) {
  if (!timestamp) {
    return false;
  }
  const parsed = Date.parse(String(timestamp));
  if (Number.isNaN(parsed)) {
    return false;
  }
  return parsed > Date.now();
}

async function logAuthEvent({
  eventType,
  actorUserId = null,
  targetUserId = null,
  ipAddress = '',
  userAgent = '',
  metadata = {},
}) {
  await run(
    `
    INSERT INTO auth_events (
      event_type, actor_user_id, target_user_id, ip_address, user_agent, metadata_json, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    `,
    [
      String(eventType || '').trim(),
      actorUserId,
      targetUserId,
      String(ipAddress || '').trim(),
      String(userAgent || '').trim(),
      JSON.stringify(metadata || {}),
      nowIso(),
    ],
  );
}

async function logGlobalAudit({
  actorUserId = null,
  actorName = '',
  actorRole = '',
  action,
  entityType,
  entityId = '',
  details = {},
  ipAddress = '',
}) {
  await run(
    `
    INSERT INTO global_audit_logs (
      actor_user_id, actor_name, actor_role, action, entity_type, entity_id, details_json, ip_address, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      actorUserId,
      actorName,
      actorRole,
      action,
      entityType,
      entityId,
      JSON.stringify(details || {}),
      ipAddress,
      nowIso(),
    ]
  );
}

// ---------------------------------------------------------------------------
// Track: rich, per-entity activity log (field-level create/update/delete feed)
// shown as the "Track" tab on each master and on a person's People profile.
// Written explicitly by the master CRUD handlers via trackCreate/Update/Delete.
// ---------------------------------------------------------------------------

// Human label per tracked entity type (table name -> singular noun).
const TRACK_ENTITY_LABELS = {
  items: 'Item',
  clients: 'Client',
  vendors: 'Vendor',
  units: 'Unit',
  machines: 'Machine',
  dies: 'Die',
  pipeline_templates: 'Pipeline',
  employees: 'Person',
  // These five wrote nothing at all until sittings needed them: a window that
  // made a group and a set showed an empty sitting, which reads as "nothing
  // happened" rather than "this is not recorded".
  departments: 'Department',
  sub_contractors: 'Sub-contractor',
  groups: 'Group',
  inventory_sets: 'Set',
  materials: 'Material',
};

// Columns never worth surfacing in a diff.
const TRACK_SKIP_FIELDS = new Set(['id', 'created_at', 'updated_at']);

function trackNormalizeValue(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'boolean') return v ? 'Yes' : 'No';
  return String(v);
}

// snake_case / camelCase column -> "Title Case" label.
function trackPrettyField(field) {
  return String(field)
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .trim();
}

// Field-level diff between two DB rows. Skips ids/timestamps and *_json blobs
// (variation trees etc.) so the feed stays readable.
function diffRows(before, after) {
  const changes = [];
  const keys = new Set([
    ...Object.keys(before || {}),
    ...Object.keys(after || {}),
  ]);
  for (const f of keys) {
    if (TRACK_SKIP_FIELDS.has(f) || f.endsWith('_json')) continue;
    const from = trackNormalizeValue(before ? before[f] : undefined);
    const to = trackNormalizeValue(after ? after[f] : undefined);
    if (from !== to) changes.push({ field: trackPrettyField(f), from, to });
  }
  return changes;
}

function trackLabelFor(row, entityType, entityId) {
  const name = row && (row.name || row.display_name || row.title);
  const noun = TRACK_ENTITY_LABELS[entityType] || 'Record';
  return name ? String(name) : `${noun} #${entityId}`;
}

/// Which sitting this request belongs to, or null.
///
/// A sitting is one opening of a window on the client — the Express bench mints
/// an id when it opens and clears it when it closes, and
/// `AuthenticatedHttpClient` stamps it on every non-GET while it is set.
/// Read inline off `req.headers`, the way `x-client-platform` is read in the
/// login handler; there is no middleware for custom headers and no allow-list
/// to add this to.
function sittingIdOf(req) {
  const raw = req && req.headers ? req.headers['x-paper-sitting'] : null;
  const trimmed = String(raw || '').trim();
  // Bounded: this lands in a column that a read endpoint groups by, so a
  // client sending something enormous should not be stored.
  return trimmed.length > 0 && trimmed.length <= 64 ? trimmed : null;
}

async function logEntityActivity({
  entityType,
  entityId,
  action,
  req = null,
  changes = null,
  details = {},
}) {
  try {
    await run(
      `INSERT INTO entity_activity_log
        (entity_type, entity_id, action, actor_user_id, actor_name, actor_role, changes_json, details_json, created_at, sitting_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        String(entityType || ''),
        String(entityId ?? ''),
        String(action || ''),
        req && req.user ? req.user.id : null,
        req && req.user ? req.user.name : '',
        req && req.user ? req.user.role : '',
        changes ? JSON.stringify(changes) : null,
        JSON.stringify(details || {}),
        nowIso(),
        // The whole sitting feature hangs off this one line. Every
        // trackCreate/trackUpdate/trackDelete call site already hands us `req`
        // for the actor, so reading the header here gives all of them sittings
        // without one of them being edited. A write made outside a window has
        // no header and lands NULL, which is the honest answer.
        sittingIdOf(req),
      ],
    );
  } catch (e) {
    console.error('[Track] log failed:', e.message);
  }
}

// Fire-and-forget convenience wrappers used by the master CRUD handlers.
function trackCreate(entityType, entityId, afterRow, req) {
  logEntityActivity({
    entityType,
    entityId,
    action: 'created',
    req,
    details: { label: trackLabelFor(afterRow, entityType, entityId) },
  });
}

// A link is a thing somebody did in a window, so it belongs in the sitting —
// but it is the one write with two subjects. Both get a row, each naming the
// other, so the Track tab on either record shows it; `pairKey` is what lets a
// sitting read collapse the two back into one line.
//
// Each side is `{ entityType, id, label }`, where entityType is the links
// catalog's own `table` (items, dies, inventory_sets, …) so these rows sit in
// the same feed as every other change to that record. Fire-and-forget like the
// wrappers above, and deliberately outside the link's own write: a link must
// never fail because its log line could not be written.
function trackLink(left, right, action, req) {
  // canonicalPair has already ordered the sides by type then id, so one pair
  // yields one key whichever end it was linked from.
  const pairKey = `${left.entityType}:${left.id}|${right.entityType}:${right.id}`;
  for (const [subject, other] of [[left, right], [right, left]]) {
    logEntityActivity({
      entityType: subject.entityType,
      entityId: subject.id,
      action,
      req,
      details: {
        label: subject.label || `${subject.entityType} #${subject.id}`,
        pairKey,
        otherType: other.entityType,
        otherId: String(other.id),
        // Snapshotted on purpose: the line still reads after the other record
        // is deleted, which is exactly when somebody goes looking.
        otherLabel: other.label || null,
      },
    });
  }
}

function trackUpdate(entityType, entityId, beforeRow, afterRow, req) {
  const changes = diffRows(beforeRow, afterRow);
  if (!changes.length) return; // nothing user-visible changed
  logEntityActivity({
    entityType,
    entityId,
    action: 'updated',
    req,
    changes,
    details: { label: trackLabelFor(afterRow, entityType, entityId) },
  });
}

function trackDelete(entityType, entityId, beforeRow, req) {
  logEntityActivity({
    entityType,
    entityId,
    action: 'deleted',
    req,
    details: { label: trackLabelFor(beforeRow, entityType, entityId) },
  });
}

function rowToEntityActivityDto(row) {
  let changes = [];
  let details = {};
  try {
    changes = row.changes_json ? JSON.parse(row.changes_json) : [];
  } catch (_) {}
  try {
    details = row.details_json ? JSON.parse(row.details_json) : {};
  } catch (_) {}
  return {
    id: row.id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    action: row.action,
    actorUserId: row.actor_user_id,
    actorName: row.actor_name || '',
    actorRole: row.actor_role || '',
    changes,
    details,
    createdAt: row.created_at,
    sittingId: row.sitting_id || null,
  };
}

/// The kind of device a request comes from: 'mobile' for the phone app (which
/// sends X-Client-Platform: mobile/ios/android), 'desktop' for everything else.
function clientPlatformOf(req) {
  const raw = String(req?.headers?.['x-client-platform'] || '').trim().toLowerCase();
  return raw === 'mobile' || raw === 'ios' || raw === 'android' ? 'mobile' : 'desktop';
}

async function createAuthSession({ user, req }) {
  // One session per user PER KIND OF DEVICE. Logging in on the phone used to
  // sign the same person out of the desktop, so the two could never be open
  // together — and the phone is where the desktop sends photos to be taken.
  // A second desktop login still ends the first; so does a second phone.
  const platform = clientPlatformOf(req);
  await revokeSessionsForUser(user.id, { reason: 'new_login_revoked_others', platform });
  const sessionId = `sess-${crypto.randomUUID()}`;
  const token = signJwt({ sub: user.id, role: user.role, sid: sessionId });
  const tokenHash = hashToken(token);
  const now = nowIso();
  await run(
    `
    INSERT INTO auth_sessions (
      id, user_id, token_hash, created_at, last_used_at, expires_at, revoked_at, revoked_reason, ip_address, user_agent, client_platform
    ) VALUES (?, ?, ?, ?, ?, ?, NULL, '', ?, ?, ?)
    `,
    [
      sessionId,
      user.id,
      tokenHash,
      now,
      now,
      secondsFromNow(JWT_TTL_SECONDS),
      getRequestIp(req),
      getRequestUserAgent(req),
      platform,
    ],
  );
  await run(
    `
    UPDATE users
    SET failed_login_attempts = 0, first_failed_login_at = NULL, lockout_until = NULL, last_login_at = ?, last_login_ip = ?, updated_at = ?
    WHERE id = ?
    `,
    [now, getRequestIp(req), now, user.id],
  );
  await logAuthEvent({
    eventType: 'login_success',
    actorUserId: user.id,
    targetUserId: user.id,
    ipAddress: getRequestIp(req),
    userAgent: getRequestUserAgent(req),
    metadata: { sessionId },
  });
  return { token, sessionId };
}

async function getActiveSession(sessionId, tokenHashValue) {
  return get(
    `
    SELECT *
    FROM auth_sessions
    WHERE id = ? AND token_hash = ? AND revoked_at IS NULL
      AND datetime(expires_at) > datetime('now')
    `,
    [sessionId, tokenHashValue],
  );
}

async function touchSession(sessionId) {
  await run('UPDATE auth_sessions SET last_used_at = ? WHERE id = ?', [nowIso(), sessionId]);
}

async function revokeSession(sessionId, reason) {
  await run(
    `
    UPDATE auth_sessions
    SET revoked_at = COALESCE(revoked_at, ?), revoked_reason = CASE WHEN revoked_reason = '' THEN ? ELSE revoked_reason END
    WHERE id = ?
    `,
    [nowIso(), String(reason || ''), sessionId],
  );
}

async function revokeSessionsForUser(userId, { exceptSessionId = null, reason = '', platform = null } = {}) {
  if (platform) {
    // A login's own kind of device only. Sessions from before the column were
    // all desktop logins in practice, hence the COALESCE.
    await run(
      `
      UPDATE auth_sessions
      SET revoked_at = COALESCE(revoked_at, ?), revoked_reason = CASE WHEN revoked_reason = '' THEN ? ELSE revoked_reason END
      WHERE user_id = ? AND revoked_at IS NULL AND COALESCE(client_platform, 'desktop') = ?
      `,
      [nowIso(), String(reason || ''), userId, platform],
    );
    return;
  }
  if (exceptSessionId) {
    await run(
      `
      UPDATE auth_sessions
      SET revoked_at = COALESCE(revoked_at, ?), revoked_reason = CASE WHEN revoked_reason = '' THEN ? ELSE revoked_reason END
      WHERE user_id = ? AND id != ? AND revoked_at IS NULL
      `,
      [nowIso(), String(reason || ''), userId, exceptSessionId],
    );
    return;
  }
  await run(
    `
    UPDATE auth_sessions
    SET revoked_at = COALESCE(revoked_at, ?), revoked_reason = CASE WHEN revoked_reason = '' THEN ? ELSE revoked_reason END
    WHERE user_id = ? AND revoked_at IS NULL
    `,
    [nowIso(), String(reason || ''), userId],
  );
}

async function registerLoginFailure({ user, email, req }) {
  const ipAddress = getRequestIp(req);
  const userAgent = getRequestUserAgent(req);
  if (!user) {
    await logAuthEvent({
      eventType: 'login_failure_unknown_user',
      ipAddress,
      userAgent,
      metadata: { email: normalizeEmail(email) },
    });
    return;
  }

  const now = nowIso();
  const firstFailedAt = user.first_failed_login_at;
  const withinWindow = isTimestampInFuture(
    firstFailedAt ? new Date(Date.parse(firstFailedAt) + LOGIN_WINDOW_MINUTES * 60 * 1000).toISOString() : null,
  );
  const nextAttempts = withinWindow ? Number(user.failed_login_attempts || 0) + 1 : 1;
  let lockoutUntil = null;
  if (nextAttempts >= LOGIN_MAX_ATTEMPTS) {
    lockoutUntil = minutesFromNow(LOGIN_LOCKOUT_MINUTES);
  }
  await run(
    `
    UPDATE users
    SET failed_login_attempts = ?, first_failed_login_at = ?, lockout_until = ?, updated_at = ?
    WHERE id = ?
    `,
    [
      nextAttempts,
      withinWindow ? firstFailedAt : now,
      lockoutUntil,
      now,
      user.id,
    ],
  );
  await logAuthEvent({
    eventType: 'login_failure',
    targetUserId: user.id,
    ipAddress,
    userAgent,
    metadata: { attempts: nextAttempts, lockoutUntil },
  });
}

function canManageUser(actorRole, targetRole) {
  if (actorRole === 'super_admin') {
    return true;
  }
  if (actorRole === 'admin') {
    return targetRole === 'user';
  }
  return false;
}

async function generateUniqueMobilePin() {
  for (let i = 0; i < 1000; i++) {
    const pin = Math.floor(1000 + Math.random() * 9000).toString();
    const existing = await get('SELECT id FROM users WHERE mobile_pin = ?', [pinHasher.hash(pin)]);
    if (!existing) {
      return pin;
    }
  }
  throw new Error('Unable to generate a unique 4-digit mobile PIN.');
}

// Derive a staff member's simple login code from an ISO date of birth: the
// DDMM (day + month), e.g. '1990-03-15' -> '1503'.
function deriveDobPin(dob) {
  const m = String(dob || '').trim().match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return null;
  return `${m[3]}${m[2]}`;
}

// Return `preferred` if that 4-digit code is free, else the next free code
// (wrapping through 0000-9999, skipping 0000 which is reserved for the super
// admin). Excludes a user so re-deriving that user's own code is a no-op.
async function nextFreeMobilePin(preferred, excludeUserId = null) {
  const isFree = async (pin) => {
    if (pin === '0000') return false;
    const row = await get(
      'SELECT id FROM users WHERE mobile_pin = ? AND (? IS NULL OR id != ?)',
      [pinHasher.hash(pin), excludeUserId, excludeUserId],
    );
    return !row;
  };
  const start = Number(preferred);
  if (Number.isFinite(start) && String(preferred).length === 4) {
    for (let i = 0; i < 10000; i++) {
      const candidate = String((start + i) % 10000).padStart(4, '0');
      if (await isFree(candidate)) return candidate;
    }
  }
  return generateUniqueMobilePin();
}

async function createUserAccount({
  name,
  email,
  password,
  role,
  createdByUserId = null,
  clientId = null,
}) {
  const normalizedEmail = normalizeEmail(email);
  const normalizedName = String(name || '').trim();
  const normalizedRole = String(role || '').trim();
  if (!normalizedName) {
    const error = new Error('name is required.');
    error.statusCode = 400;
    throw error;
  }
  if (!normalizedEmail) {
    const error = new Error('email is required.');
    error.statusCode = 400;
    throw error;
  }
  if (!USER_ROLES.has(normalizedRole)) {
    const error = new Error('role must be one of super_admin, admin, or user.');
    error.statusCode = 400;
    throw error;
  }
  const passwordError = validatePasswordPolicy(password, { email: normalizedEmail, role: normalizedRole });
  if (passwordError) {
    const error = new Error(passwordError);
    error.statusCode = 400;
    throw error;
  }
  const existing = await get('SELECT id FROM users WHERE email = ?', [normalizedEmail]);
  if (existing) {
    const error = new Error('A user with this email already exists.');
    error.statusCode = 409;
    throw error;
  }
  const now = new Date().toISOString();
  const mobilePin = await generateUniqueMobilePin();
  const result = await run(
    `
    INSERT INTO users (
      name, email, password_hash, role, is_active, created_by_user_id, created_at, updated_at, mobile_pin, client_id
    ) VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
    `,
    [
      normalizedName,
      normalizedEmail,
      hashPassword(password),
      normalizedRole,
      createdByUserId,
      now,
      now,
      pinHasher.hash(mobilePin),
      clientId,
    ],
  );
  const created = await get('SELECT * FROM users WHERE id = ?', [result.lastID]);
  // Shown once, in the answer to whoever made the account; never stored plain.
  return created ? { ...created, issued_mobile_pin: mobilePin } : created;
}

async function findActiveUserById(id) {
  return get('SELECT * FROM users WHERE id = ? AND is_active = 1', [id]);
}

async function safeUserDtoWithPermissions(row) {
  if (!row) {
    return null;
  }
  const permissionMap = await getEffectivePermissionMap(row.id, row.role);
  const activeSession = await get('SELECT ip_address, user_agent, last_used_at FROM auth_sessions WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ? ORDER BY last_used_at DESC LIMIT 1', [row.id, nowIso()]);
  return safeUserDto(row, permissionMap, activeSession);
}

async function bootstrapSuperAdminIfNeeded() {
  const countRow = await get('SELECT COUNT(*) AS count FROM users');
  if (Number(countRow?.count || 0) > 0) {
    return;
  }
  const email = String(process.env.PAPER_SUPER_ADMIN_EMAIL || '').trim();
  const password = String(process.env.PAPER_SUPER_ADMIN_PASSWORD || '').trim();

  // Explicit break-glass super admin (any environment) when both are provided.
  if (email && password) {
    const name = process.env.PAPER_SUPER_ADMIN_NAME || 'Super Admin';
    await createUserAccount({ name, email, password, role: 'super_admin' });
    console.log('[bootstrap] Break-glass super admin created from PAPER_SUPER_ADMIN_* env.');
    return;
  }

  // Managed client deployment (reports to the control plane) or explicitly told
  // to skip: NO baked-in god login. The deployment starts with no users and the
  // vendor provisions the first admin from the Falcon View. Break-glass is
  // always available by setting PAPER_SUPER_ADMIN_EMAIL + _PASSWORD.
  const isManaged =
    !!String(process.env.CONTROL_PLANE_URL || '').trim() ||
    parseBooleanEnv(process.env.PAPER_DISABLE_DEFAULT_SUPERADMIN, false);
  if (isManaged) {
    console.log(
      '[bootstrap] Managed deployment — no default super admin. Provision the first admin from the control plane (or set PAPER_SUPER_ADMIN_* for break-glass).',
    );
    return;
  }

  // Dev / standalone (no control plane): keep the convenient default so local
  // runs can sign in immediately.
  await createUserAccount({
    name: 'Super Admin',
    email: 'super@paper.local',
    password: 'Paper@12345',
    role: 'super_admin',
  });
  console.warn(
    'Bootstrapped default super admin: super@paper.local / Paper@12345 (DEV ONLY). Set PAPER_SUPER_ADMIN_* or CONTROL_PLANE_URL for managed deployments.',
  );
}

async function seedRolePermissions() {
  const now = nowIso();
  for (const role of Object.keys(DEFAULT_ROLE_PERMISSIONS)) {
    const defaults = DEFAULT_ROLE_PERMISSIONS[role] || {};
    for (const key of PERMISSION_KEYS) {
      const isAllowed = defaults[key] === true ? 1 : 0;
      await run(
        `
        INSERT OR IGNORE INTO role_permissions (role, permission_key, is_allowed, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        `,
        [role, key, isAllowed, now, now],
      );
    }
  }
}

async function seedPermissionTemplates() {
  const now = nowIso();
  for (const template of DEFAULT_PERMISSION_TEMPLATES) {
    await run(
      `
      INSERT OR IGNORE INTO permission_templates (name, description, is_system_default, created_at, updated_at)
      VALUES (?, ?, 1, ?, ?)
      `,
      [template.name, template.description, now, now],
    );
    const existing = await get('SELECT id FROM permission_templates WHERE name = ?', [template.name]);
    if (!existing) {
      continue;
    }
    const templateId = Number(existing.id);
    for (const key of Object.keys(template.permissions || {})) {
      if (!isKnownPermissionKey(key)) {
        continue;
      }
      const allowed = template.permissions[key] === true ? 1 : 0;
      await run(
        `
        INSERT OR IGNORE INTO permission_template_permissions (
          template_id, permission_key, is_allowed, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?)
        `,
        [templateId, key, allowed, now, now],
      );
    }
  }
}

function currentActor(req) {
  return req.user?.name || 'Demo Admin';
}

async function requireAuth(req, res, next) {
  const header = String(req.headers.authorization || '');
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    res.status(401).json({ success: false, error: 'Authentication required.' });
    return;
  }
  const token = match[1];
  const payload = verifyJwt(token);
  if (!payload?.sub || !payload?.sid) {
    res.status(401).json({ success: false, error: 'Invalid or expired token.' });
    return;
  }
  try {
    const session = await getActiveSession(String(payload.sid), hashToken(token));
    if (!session) {
      res.status(401).json({ success: false, error: 'Session is expired or revoked.' });
      return;
    }
    const user = await findActiveUserById(Number(payload.sub));
    if (!user) {
      res.status(401).json({ success: false, error: 'User is inactive or no longer exists.' });
      return;
    }
    const permissionMap = await getEffectivePermissionMap(user.id, user.role);
    await touchSession(session.id);
    req.user = safeUserDto(user, permissionMap);
    req.userPermissions = permissionMap;
    req.authSession = rowToAuthSessionDto(session);
    next();
  } catch (err) {
    console.error('[Auth] Verification failed:', err);
    res.status(401).json({ success: false, error: 'Authentication verification failed.' });
  }
}

function requireRoles(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      res.status(401).json({ success: false, error: 'Authentication required.' });
      return;
    }
    if (!roles.includes(req.user.role)) {
      res.status(403).json({ success: false, error: 'You do not have permission for this action.' });
      return;
    }
    next();
  };
}

function hasPermission(req, permissionKey) {
  if (req.user?.role === 'super_admin') {
    return true;
  }
  const key = normalizePermissionKey(permissionKey);
  if (req.userPermissions?.[key] === true) {
    return true;
  }
  if (req.userPermissions?.[key] === false) {
    return false;
  }
  const coarseFallback = FINE_KEY_TO_COARSE_MAP[key];
  if (coarseFallback && req.userPermissions?.[coarseFallback] === true) {
    return true;
  }
  return false;
}

function requirePermission(permissionKey) {
  const key = normalizePermissionKey(permissionKey);
  return (req, res, next) => {
    if (!req.user) {
      res.status(401).json({ success: false, error: 'Authentication required.' });
      return;
    }
    // Legacy config.read/config.write guards are now no-ops: per-module CRUD
    // enforcement happens centrally in requireApiModulePermission. Keeping this
    // pass-through avoids editing ~170 individual routes and double-gating.
    if (LEGACY_GUARD_PASSTHROUGH.has(key)) {
      next();
      return;
    }
    if (!isKnownPermissionKey(key)) {
      res.status(500).json({ success: false, error: `Unknown permission key: ${key}` });
      return;
    }
    if (!hasPermission(req, key)) {
      res.status(403).json({ success: false, error: 'You do not have permission for this action.' });
      return;
    }
    next();
  };
}

// Maps an /api request to its (module, op) for central per-module CRUD
// enforcement. `req.path` here is already stripped of the /api mount prefix
// (e.g. '/items/5'). Returns null to SKIP module enforcement — auth, account
// management, Track, generic asset/upload, and unknown paths keep their own
// guards / legacy write gate.
function moduleOpForRequest(req) {
  const path = req.path || '';
  const seg = path.split('/')[1] || '';
  const EXCLUDED = new Set([
    '', 'auth', 'me', 'users', 'admins', 'permissions', 'permission-templates',
    'audit', 'sessions', 'track', 'delete-requests', 'assets', 'upload',
    'delete-s3-object', 'favorites', 'sandbox-config', 'notifications', 'health',
    'record-options', 'dev',
    // A link spans two masters, so there is no one module to gate it as. Its
    // own guard asks about both sides — modules/links/routes.js.
    'links',
    // A variation tree's module is named by the entity type in the path, which
    // this map cannot express — modules/variations/routes.js gates it.
    'variations',
    // A photo request's module is its record's (part, company, die…); the
    // route asks for that record's photo right itself, like /assets.
    'photo-requests',
  ]);
  if (EXCLUDED.has(seg)) return null;
  // Employee account sub-actions stay capability-gated (create/link/unlink login).
  if (seg === 'employees' && /\/(create-login|link-login|unlink-login)/.test(path)) {
    return null;
  }
  // A part's photos are gated as its attachments, like /assets — the gallery's
  // Save is deletes and uploads (/assets) and then this, so all of it has to
  // ask the same right.
  if (/^\/items\/[^/]+\/photos\/?$/.test(path)) return null;
  // In-use reconciliation is gated by a dedicated capability, not challans.create.
  if (/^\/(challans|delivery-challans)\/[^/]+\/reconcile/.test(path)) {
    return { module: 'challans', op: 'reconcile', key: 'challans.reconcile' };
  }

  let module = null;
  if (['orders', 'order-items', 'order-po-uploads', 'order-po-documents'].includes(seg)) {
    module = 'orders';
  } else if (['inventory', 'materials', 'barcode'].includes(seg)) {
    module = 'inventory';
  } else if (seg === 'production' && /^\/production\/pipeline-templates/.test(path)) {
    module = 'pipelines'; // the pipeline designer is a master
  } else if (['production', 'production-runs', 'pipeline-runs', 'telemetry'].includes(seg)) {
    module = 'production';
  } else if (['items', 'groups', 'process-stages', 'item-sheet-properties', 'raw-materials'].includes(seg)) {
    // process-stages is the stage master a part's route is built from;
    // item-sheet-properties are the item sheet's own property columns (061);
    // raw-materials are the rivet (and later spring) forms.
    // Declared here deliberately: an unmapped segment returns null, which
    // skips the per-module CRUD check entirely.
    module = 'items';
  } else if (['clients', 'sub-contractors'].includes(seg)) {
    module = 'clients';
  } else if (seg === 'vendors') {
    module = 'vendors';
  } else if (seg === 'units' || seg === 'unit-groups') {
    module = 'units';
  } else if (seg === 'machines') {
    module = 'machines';
  } else if (['dies', 'die-makers'].includes(seg)) {
    // die-makers is the master behind a die's "made by". Declared here
    // deliberately: an unmapped segment returns null, which skips the
    // per-module CRUD check entirely rather than failing closed.
    module = 'dies';
  } else if (seg === 'jobs') {
    module = 'jobs';
  } else if (['challans', 'delivery-challans', 'invoices', 'reconciliation', 'challan-templates', 'reports', 'templates'].includes(seg)) {
    module = 'challans';
  } else if (['employees', 'departments'].includes(seg)) {
    module = 'people';
  } else if (['action-center', 'trash'].includes(seg)) {
    module = 'action_center';
  }
  // company-profile + any unmapped path -> null -> legacy write gate.
  if (!module) return null;

  const m = req.method;
  let op = 'read';
  if (m === 'POST') op = 'create';
  else if (m === 'PUT' || m === 'PATCH') op = 'update';
  else if (m === 'DELETE') op = 'delete';
  // Signing a download link for a file that already exists is a read, even
  // though the route is a POST (the id goes in the path, not a query string).
  if (op === 'create' && /\/read-url$/.test(path)) op = 'read';
  // Converting a value changes nothing; it is a POST only to carry a batch.
  if (op === 'create' && /^\/units\/convert-batch\/?$/.test(path)) op = 'read';
  // Adding a person to a client changes THAT client — its primary contact
  // and the phone and email it shows — so it is an update to the record, and
  // a per-record update grant covers it. As a create it let someone with only
  // clients.create rewrite any existing client's contact details.
  if (op === 'create' && /^\/clients\/[^/]+\/contacts\/?$/.test(path)) op = 'update';
  return { module, op, key: `${module}.${op}` };
}

// Central per-module CRUD gate. Runs for every /api request; enforces the
// module.op permission for mapped business paths, and marks the request so the
// legacy write gate doesn't double-check it.
// Modules that support per-record (row-level) grants, and how to list/label
// their records for the picker. entity_type == the module key.
const RECORD_OPTION_SOURCES = {
  items: { table: 'items', idCol: 'id', label: "COALESCE(NULLIF(TRIM(display_name), ''), name)" },
  clients: { table: 'clients', idCol: 'id', label: 'name' },
  vendors: { table: 'vendors', idCol: 'id', label: 'name' },
  units: { table: 'units', idCol: 'id', label: 'name' },
  machines: { table: 'machines', idCol: 'id', label: 'name' },
  dies: { table: 'dies', idCol: 'id', label: "COALESCE(NULLIF(TRIM(tool_code), ''), 'Die ' || id)" },
  people: { table: 'employees', idCol: 'id', label: 'name' },
  orders: { table: 'order_items', idCol: 'id', label: "COALESCE(NULLIF(TRIM(order_no), ''), 'Order ' || id)" },
  challans: { table: 'delivery_challans', idCol: 'id', label: "COALESCE(NULLIF(TRIM(challan_no), ''), 'Challan ' || id)" },
  inventory: { table: 'materials', idCol: 'barcode', label: "COALESCE(NULLIF(TRIM(name), ''), barcode)" },
  pipelines: { table: 'pipeline_templates', idCol: 'id', label: 'name' },
};
const RECORD_PERMISSION_OPS = new Set(['read', 'update', 'delete']);

// The record id targeted by a request. Usually the segment right after the
// module (/items/42 -> 42; /materials/BC-1 -> BC-1), but pipelines nest one
// deeper (/production/pipeline-templates/:id). null for collection/create.
function recordIdForRequest(req, module) {
  const parts = (req.path || '').split('/');
  if (module === 'pipelines') return parts[3] ? String(parts[3]) : null;
  const id = parts[2];
  return id ? String(id) : null;
}

async function hasRecordPermission(userId, entityType, entityId, op) {
  if (!userId || !entityId) return false;
  const row = await get(
    'SELECT 1 FROM user_record_permissions WHERE user_id = ? AND entity_type = ? AND entity_id = ? AND op = ? LIMIT 1',
    [userId, String(entityType), String(entityId), op],
  );
  return !!row;
}

async function requireApiModulePermission(req, res, next) {
  try {
    const mo = moduleOpForRequest(req);
    if (!mo) {
      next();
      return;
    }
    req._moduleGated = true;
    // What this request was let through for; the kernel desk reads it so an
    // operation needing the same key does not ask a second time.
    req.gateClearedKey = mo.key;
    if (hasPermission(req, mo.key)) {
      next();
      return;
    }
    // Per-record fallback: an id-scoped read/update/delete on a specific record
    // this user was granted individually, even without the module-level right.
    if (RECORD_PERMISSION_OPS.has(mo.op) && RECORD_OPTION_SOURCES[mo.module]) {
      const recordId = recordIdForRequest(req, mo.module);
      if (
        recordId &&
        (await hasRecordPermission(req.user.id, mo.module, recordId, mo.op))
      ) {
        next();
        return;
      }
    }
    res.status(403).json({
      success: false,
      error: `You do not have ${mo.op} access to the ${MODULE_LABELS[mo.module] || mo.module} module.`,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
}

function requireApiWritePermission(req, res, next) {
  // Per-module CRUD is already enforced by requireApiModulePermission for
  // mapped business paths; don't double-gate them with the legacy write check.
  if (req._moduleGated) {
    return next();
  }
  // Generic asset staging/management routes enforce their own entity-aware
  // guards (requireAssetEntityPermission / requireGenericUploadPermission);
  // admin-gating them here would block first-time uploads by regular users.
  if (req.path.startsWith('/assets/') || req.path.startsWith('/upload/')) {
    return next();
  }
  // A part's photos, the gallery's Save: gated as its attachments by the
  // route itself (modules/items/routes.js), like /assets.
  if (/^\/items\/[^/]+\/photos\/?$/.test(req.path)) {
    return next();
  }
  // A photo request checks the record's own photo right (the same key the
  // asset routes ask), and is owner-only; the admin write gate would stop the
  // floor staff it exists for.
  if (req.path === '/photo-requests' || req.path.startsWith('/photo-requests/')) {
    return next();
  }
  // Same for the link graph: modules/links/routes.js gates every write on
  // `update` for BOTH masters the link spans, which is a stricter question
  // than this gate can ask. Falling through to the admin check here would
  // mean nobody but an admin could attach a die to an item.
  if (req.path === '/links' || req.path.startsWith('/links/')) {
    return next();
  }
  // The dev marker's notes. The routes only exist outside production, and
  // gating them as an admin write would stop a developer using the tool on
  // their own machine for no gain.
  if (req.path.startsWith('/dev/marks')) {
    return next();
  }
  // Same for the variation tree: its guard reads the owning module out of the
  // path and asks for update on THAT, which this gate cannot do.
  if (req.path.startsWith('/variations/')) {
    return next();
  }

  if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') {
    next();
    return;
  }
  const allowedForAnyAuthenticatedUser =
    req.path === '/me/password' ||
    req.path === '/auth/logout' ||
    (req.path === '/delete-requests' && req.method === 'POST') ||
    (req.path.startsWith('/auth/sessions/') && req.method === 'DELETE');
  if (allowedForAnyAuthenticatedUser) {
    next();
    return;
  }
  if (req.user?.role === 'super_admin' || req.user?.role === 'admin') {
    next();
    return;
  }
  if (hasPermission(req, 'config.write') || hasPermission(req, 'inventory.update')) {
    next();
    return;
  }
  res.status(403).json({
    success: false,
    error: 'Users can request deletion, but cannot modify records directly.',
  });
}

// Entity-aware guards for the generic asset routes (/assets/*, /upload/*).
// These paths are excluded from the central module gate because their module
// depends on the request body or the stored asset row, not the path. The fine
// asset capabilities fall back to the coarse module right via
// FINE_KEY_TO_COARSE_MAP (e.g. items.asset.upload -> items.update).
const ASSET_ENTITY_PERMISSIONS = {
  item: { write: 'items.asset.upload', read: 'items.asset.list' },
  delivery_challan: { write: 'challans.asset.upload', read: 'challans.read' },
  machine: { write: 'machines.update', read: 'machines.read' },
  die: { write: 'dies.update', read: 'dies.read' },
  client: { write: 'clients.update', read: 'clients.read' },
  party_contact: { write: 'clients.update', read: 'clients.read' },
  // A contractor is filed under its client, so its documents are the client's.
  sub_contractor: { write: 'clients.update', read: 'clients.read' },
};

function requireAssetEntityPermission(op, resolveEntityType) {
  return async (req, res, next) => {
    try {
      const entityType = String((await resolveEntityType(req)) || '')
        .trim()
        .toLowerCase();
      const key = ASSET_ENTITY_PERMISSIONS[entityType]?.[op];
      // Unknown entity type or missing session/asset row: fall through so the
      // handler returns its own 400/404 instead of a misleading 403.
      if (!key || hasPermission(req, key)) {
        next();
        return;
      }
      res.status(403).json({
        success: false,
        error: 'You do not have permission to manage attachments for this record.',
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  };
}

function assetEntityTypeFromBody(req) {
  return req.body?.entityType;
}

async function assetEntityTypeFromUploadSession(req) {
  const row = await get(
    'SELECT entity_type FROM asset_upload_sessions WHERE id = ?',
    [String(req.body?.uploadSessionId || '')],
  );
  return row?.entity_type || null;
}

async function assetEntityTypeFromAssetId(req) {
  const row = await get('SELECT entity_type FROM uploaded_assets WHERE id = ?', [
    Number(req.params.id),
  ]);
  return row?.entity_type || null;
}

// /upload/generic stages files that have no owning record yet (photos picked
// while creating a new entry), so it cannot be gated per-entity. Any user who
// can create or update something may stage an upload; attaching the file to a
// record is still gated by that record's own create/update route.
const GENERIC_UPLOAD_PERMISSION_KEYS = PERMISSION_KEYS.filter((key) =>
  /\.(create|update|upload)$/.test(key),
);

function requireGenericUploadPermission(req, res, next) {
  if (GENERIC_UPLOAD_PERMISSION_KEYS.some((key) => hasPermission(req, key))) {
    next();
    return;
  }
  res.status(403).json({
    success: false,
    error: 'You do not have permission to upload files.',
  });
}

function closeDb() {
  return new Promise((resolve, reject) => {
    deleteDb.close(() => {
      db.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
  });
}

function parseJson(value, fallback) {
  if (!value) {
    return fallback;
  }
  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
}

function parseJsonOrArray(value, fallback = []) {
  if (Array.isArray(value)) {
    return value;
  }
  return parseJson(value, fallback);
}

function normalizeCustomVariationValues(value = {}) {
  const parsed = value && typeof value === 'object' && !Array.isArray(value)
    ? value
    : parseJson(value, {});
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return {};
  }
  const normalized = {};
  for (const [key, rawValue] of Object.entries(parsed)) {
    const trimmedKey = String(key || '').trim();
    const trimmedValue = String(rawValue ?? '').trim();
    if (trimmedKey && trimmedValue) {
      normalized[trimmedKey] = trimmedValue;
    }
  }
  return normalized;
}

function oneDayAgo(daysAgo = 0) {
  return new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000).toISOString();
}

// The units master (rows, DTOs, families, the conversion graph) lives in
// modules/units/master.js. Its functions keep their old names in this file,
// further down, because seeds, item code and the tests still call them.
const {
  createUnitsMaster,
  rowToUnitDto,
  rowToUnitGroupDto,
  normalizeUnitValue,
} = require('./modules/units/master');

// The trash (trashAndDelete, trashAndDeleteMany, list and restore) lives in
// modules/action_center. Every module that deletes a recoverable row calls the
// two functions below under the names they always had. The delete connection
// (deleteDb, runOnDelete) stays here: initDb, closeDb and the tests depend on it.
const trashService = createTrashService({
  get,
  all,
  run,
  runOnDelete,
  logChange,
  restoreEntityAssets,
});
const { trashAndDelete, trashAndDeleteMany } = trashService;

// Set when the links module mounts (far below). A deleted record's links in
// the generic graph have no foreign key to cascade through — nothing can
// declare one against a polymorphic pair — so the cascades call this by hand.
// null before the mount, so a seeder deleting during boot does not throw.
let purgeEntityLinks = null;
let purgeEntityVariations = null;
// Also from the links module, but these two are not cascade cleanup: they are
// how a legacy writer keeps a single-valued link (a set's group) and reads it
// back. Unlike the purges they throw when unmounted — a link write that
// silently did not happen is worse than a 500.
let setSoleEntityLink = null;
let resolveSoleEntityLinks = null;

function requireLinkWriter() {
  if (!setSoleEntityLink) throw new Error('Links module is not mounted yet.');
  return setSoleEntityLink;
}

function requireLinkResolver() {
  if (!resolveSoleEntityLinks) throw new Error('Links module is not mounted yet.');
  return resolveSoleEntityLinks;
}

let assetSweepScheduled = false;

// Items at function level. The logic that lived here until 2026-11-19 is in
// modules/items/ (variation-tree, property-keys, schema-props, developed-for,
// variations, dto, reads, save, deletes), assembled by createItemsService. The
// names below are the ones this file, its seeds and its exports have always
// used, so nothing that calls them changes.
const itemsService = require('./modules/items/service').createItemsService({
  get,
  all,
  run,
  logChange,
  parseJson,
  normalizeCustomVariationValues,
  trashAndDelete,
  markEntityAssetsDeleted,
  // Assigned when the links module mounts; read when called.
  purgeEntityLinks: () => purgeEntityLinks,
  purgeEntityVariations: () => purgeEntityVariations,
  // Inventory is asked at the kernel desk, for what items has declared; so
  // are clients, units, machines, dies, pipelines, orders and challans.
  inventory: require('./modules/inventory/client').inventoryClient(desk.as('items')),
  desk: desk.as('items'),
});
const {
  getGroupMaterialRowByGroupId,
  getItemPropertySchema,
  persistItemPropertySchema,
  getEffectiveSchema,
  normalizeDealContactIds,
  normalizeDevelopedFor,
  writeDealContacts,
  developedForDto,
  getItemVariationNodeRows,
  getItemVariationTree,
  resolveLeafSelectionFromDb,
  itemHoldsWholeItemStock,
  assertValidStockVariationLeaf,
  applyVariationStockDelta,
  resolveOrderVariationSelection,
  rowToGroupDto,
  rowToItemDto,
  rowsToItemDtos,
  getGroupRowById,
  getItemRowById,
  getItemsWithUsage,
  getItemUsageDetails,
  sanitizeNumericRange,
  normalizeMaterialTypeId,
  sanitizeNodes,
  findItemDuplicate,
  getGroupsWithUsage,
  getItemSelectionSnapshot,
  findGroupDuplicate,
  groupWouldCreateCycle,
  saveGroup,
  buildItemDisplayName,
  saveItem,
  saveItemOnce,
  ensureReconcilePrimaryGroup,
  ensureReconcileSubGroup,
  ensureReconcileItem,
  deleteItemWithCascade,
  deleteGroupWithCascade,
} = itemsService;
const {
  activeChildrenForNode,
  activeTopLevelVariationProperties,
  findVariationNodeById,
  activeValuePathForLeaf,
  activeValueSelectionForLeaf,
  variationPathLabelForNodeIds,
  buildVariationPathLabel,
} = require('./modules/items/variation-tree');
const { normalizePropertyKey, normalizeGroupPropertyDraft, normalizeDiscardedPropertyKeys } = require('./modules/items/property-keys');

/// A record going away takes its photos with it — marked, never erased
/// (erasing them orphaned the stored objects). Marked 'record_deleted', not
/// 'deleted': the record can come back from the trash, and its photos with
/// it, so the sweep leaves them while the trash still holds it. Which one was
/// shown is kept for that.
async function markEntityAssetsDeleted(entityType, entityId) {
  await run(
    `
    UPDATE uploaded_assets
    SET status = 'record_deleted', deleted_at = ?
    WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded'
    `,
    [new Date().toISOString(), entityType, Number(entityId)],
  );
}

/// The table a photo's record lives in, for the records whose photos go
/// with them ([markEntityAssetsDeleted]).
const ASSET_OWNER_TABLES = { item: 'items', group: 'groups' };

/// A record restored from the trash gets back the photos it went with.
async function restoreEntityAssets(tableName, recordId) {
  const entityType = Object.keys(ASSET_OWNER_TABLES).find(
    (type) => ASSET_OWNER_TABLES[type] === tableName,
  );
  if (!entityType) return;
  await run(
    `
    UPDATE uploaded_assets SET status = 'uploaded', deleted_at = NULL
    WHERE entity_type = ? AND entity_id = ? AND status = 'record_deleted'
    `,
    [entityType, Number(recordId)],
  );
  await syncRecordPhotoField(entityType, Number(recordId));
  announceAssetChanged(entityType, recordId);
}

function rowToAssetDto(row, readUrlPayload = null) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    entityType: row.entity_type || '',
    entityId: Number(row.entity_id || 0),
    fileName: row.file_name || '',
    contentType: row.content_type || '',
    sizeBytes: Number(row.size_bytes || 0),
    sha256: row.sha256 || '',
    objectKey: row.object_key || '',
    status: row.status || 'uploaded',
    isPrimary: Number(row.is_primary || 0) === 1,
    documentTitle: row.document_title ?? null,
    createdAt: row.created_at,
    uploadedAt: row.uploaded_at,
    readUrl: readUrlPayload?.readUrl || null,
    readUrlExpiresAt: readUrlPayload?.expiresAt || null,
    // What to SAVE on a record: the read URL above expires in minutes.
    viewUrl: row.object_key ? assetViewUrl(row.object_key) : null,
    position: row.position == null ? null : Number(row.position),
    // The small copy for lists; a photo from before thumbnails is its own.
    thumbUrl: assetViewUrl(row.thumb_key || row.object_key),
    width: row.width == null ? null : Number(row.width),
    height: row.height == null ? null : Number(row.height),
  };
}

async function rowToUploadedAssetDto(row, includeReadUrls = true) {
  if (!row) return null;
  // A presign failure (S3 unconfigured, stale mock rows) must not take down
  // the parent entity fetch; the asset just comes back without a readUrl.
  let payload = null;
  if (includeReadUrls) {
    try {
      payload = await assetReadUrlPayload(row.object_key);
    } catch (error) {
      console.warn(`Failed to presign read URL for asset ${row.object_key}: ${error.message}`);
    }
  }
  return rowToAssetDto(row, payload);
}

// Pipeline templates left for modules/pipelines. Production still shapes the
// templates it reads when it starts a run, so the DTO comes out of the service
// under the name it knows.
const pipelinesService = createPipelineService({ get, all, run, parseJson });
const { rowToTemplate } = pipelinesService;

// The freelancer job pool left for modules/jobs. Handing a job to a worker
// moves a set out of stock, which it asks inventory for; the employee lookup
// for a worker's card is asked of the people module. Production calls syncAssemblyJob and propagateAssemblyRejection.
const peoplePorts = createPeoplePorts({ get });
const jobsService = createJobsService({
  get,
  all,
  run,
  desk: desk.as('jobs'),
  // Inventory is asked at the kernel desk (see inventoryClient just below),
  // under the two names the jobs service has always used.
  inventory: {
    getMaterialRowByBarcode: (barcode) => inventoryForJobs.materials.rowByBarcode(barcode),
    applyInventoryMovementCore: (payload, options) =>
      inventoryForJobs.movements.applyCore(payload, options),
  },
});

// What each module is handed in place of inventory's ports: an object of the
// same shape that asks the kernel desk (modules/inventory/client.js). Being
// asked by name at call time, it needs no late binding, although inventory is
// built further down this file than its callers.
const { inventoryClient } = require('./modules/inventory/client');
const inventoryForProduction = inventoryClient(desk.as('production'));
const inventoryForChallans = inventoryClient(desk.as('challans'));
const inventoryForOrders = inventoryClient(desk.as('orders'));
const inventoryForJobs = inventoryClient(desk.as('jobs'));
const inventoryForActionCenter = inventoryClient(desk.as('action_center'));
// The same for challans (modules/challans/client.js) and items.
const { challansClient } = require('./modules/challans/client');
const { itemsClient } = require('./modules/items/client');
const { jobsClient } = require('./modules/jobs/client');
const itemsForProduction = itemsClient(desk.as('production'));
const itemsForChallans = itemsClient(desk.as('challans'));
const itemsForInventory = itemsClient(desk.as('inventory'));
const itemsForOrders = itemsClient(desk.as('orders'));
const itemsForActionCenter = itemsClient(desk.as('action_center'));

// Production left for modules/production. Its helpers keep their old names
// here because seeds, scenarios and the modules built further down still call
// them. Inventory is created later in this file, so it is looked up when used.
const lateBound = (resolve) => new Proxy({}, { get: (_target, key) => resolve()[key] });
const productionService = createProductionService({
  desk: desk.as('production'),
  all,
  get,
  // Inventory is asked at the kernel desk, for what production has declared.
  getMaterialRowByBarcode: (barcode) => inventoryForProduction.materials.rowByBarcode(barcode),
  inventoryPorts: inventoryForProduction,
  jobsService: jobsClient(desk.as('production')),
  parseJson,
  recordLedgerEvent,
  rowToMaterialDto: (...args) => rowToMaterialDto(...args),
  rowToTemplate,
  run,
  getItemSelectionSnapshot: (itemId, leaf) => itemsForProduction.selectionSnapshot(itemId, leaf),
  itemsPorts: itemsForProduction,
});
const {
  upsertStageReconciliation,
  backfillStageReconciliations,
  getMergedNodeMetrics,
  rowToRun,
  listCompletedProductionRuns,
  getProductionRunRowById,
  createRunFromTemplate,
  ensurePipelineRunRecord,
} = productionService;

function buildSeedTemplates() {
  return [
    {
      id: 'sheet-metal-flow',
      factoryId: '1',
      shopFloorId: '1',
      name: 'Sheet Metal Process',
      description:
        'Input Stage: Sheet metal goes in at this stage, then flows through blank cutting, piercing, bending, drilling, and packaging.',
      version: 1,
      status: 'active',
      stageLabels: [
        'Input Stage',
        'Blank Cutting',
        'Piercing',
        'Bending',
        'Drilling',
        'Packaging',
      ],
      laneLabels: ['Main'],
      nodes: [
        {
          id: 'sheet-metal-input',
          name: 'Sheet Metal Input',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 0,
          inputs: ['Sheet metal'],
          outputs: ['Sheet metal'],
          machine: 'Input Stage',
          durationHours: 0.25,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'sheet-metal-blank-cutting',
          name: 'Blank Cutting',
          processType: 'Cutting',
          stageIndex: 1,
          laneIndex: 0,
          inputs: ['Sheet metal'],
          outputs: ['Blank cut sheet'],
          machine: 'Blank Cutting',
          durationHours: 1,
          status: 'Ready',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'sheet-metal-piercing',
          name: 'Piercing',
          processType: 'Piercing',
          stageIndex: 2,
          laneIndex: 0,
          inputs: ['Blank cut sheet'],
          outputs: ['Pierced sheet'],
          machine: 'Handpress',
          durationHours: 0.5,
          status: 'Ready',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'sheet-metal-bending',
          name: 'Bending',
          processType: 'Bending',
          stageIndex: 3,
          laneIndex: 0,
          inputs: ['Pierced sheet'],
          outputs: ['Bent sheet'],
          machine: 'PP',
          durationHours: 0.75,
          status: 'Ready',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'sheet-metal-drilling',
          name: 'Drilling',
          processType: 'Drilling',
          stageIndex: 4,
          laneIndex: 0,
          inputs: ['Bent sheet'],
          outputs: ['Drilled sheet'],
          machine: 'Drill Machine',
          durationHours: 0.75,
          status: 'Ready',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'sheet-metal-packaging',
          name: 'Packaging',
          processType: 'Packaging',
          stageIndex: 5,
          laneIndex: 0,
          inputs: ['Drilled sheet'],
          outputs: ['Packed sheet metal'],
          machine: 'Packaging',
          durationHours: 0.5,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
      ],
      flows: [
        { id: 'sheet-metal-flow-1', fromNodeId: 'sheet-metal-input', toNodeId: 'sheet-metal-blank-cutting', materialName: 'Sheet metal', barcode: null, isSplit: false, isMerge: false },
        { id: 'sheet-metal-flow-2', fromNodeId: 'sheet-metal-blank-cutting', toNodeId: 'sheet-metal-piercing', materialName: 'Blank cut sheet', barcode: null, isSplit: false, isMerge: false },
        { id: 'sheet-metal-flow-3', fromNodeId: 'sheet-metal-piercing', toNodeId: 'sheet-metal-bending', materialName: 'Pierced sheet', barcode: null, isSplit: false, isMerge: false },
        { id: 'sheet-metal-flow-4', fromNodeId: 'sheet-metal-bending', toNodeId: 'sheet-metal-drilling', materialName: 'Bent sheet', barcode: null, isSplit: false, isMerge: false },
        { id: 'sheet-metal-flow-5', fromNodeId: 'sheet-metal-drilling', toNodeId: 'sheet-metal-packaging', materialName: 'Drilled sheet', barcode: null, isSplit: false, isMerge: false },
      ],
    },
    {
      id: 'dolly',
      factoryId: '1',
      shopFloorId: '1',
      name: 'Dolly Production',
      description:
        'Copper and steel lanes converge into a welding stage before final assembly handoff.',
      version: 1,
      status: 'active',
      stageLabels: [
        'Stage 1: Raw Input',
        'Stage 2: Prep',
        'Stage 3: Join',
        'Stage 4: Finish',
      ],
      laneLabels: ['Lane 1', 'Lane 2', 'Lane 3'],
      nodes: [
        {
          id: 'dolly-input-copper',
          name: 'Copper Roll Feed',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 0,
          inputs: ['Copper roll'],
          outputs: ['Blank copper'],
          machine: 'Rack A1',
          durationHours: 0.5,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'dolly-cut',
          name: 'Blank Cutting',
          processType: 'Cutting',
          stageIndex: 1,
          laneIndex: 0,
          inputs: ['Copper roll'],
          outputs: ['Cut copper'],
          machine: 'Cutter 04',
          durationHours: 1,
          status: 'Active',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'dolly-input-steel',
          name: 'Steel Sheet Feed',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 1,
          inputs: ['Steel sheet'],
          outputs: ['Drilled steel'],
          machine: 'Rack B2',
          durationHours: 0.5,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'dolly-drill',
          name: 'Drilling',
          processType: 'Machining',
          stageIndex: 1,
          laneIndex: 1,
          inputs: ['Steel sheet'],
          outputs: ['Drilled steel'],
          machine: 'Drill 02',
          durationHours: 1.5,
          status: 'Ready',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'dolly-weld',
          name: 'Welding',
          processType: 'Join',
          stageIndex: 2,
          laneIndex: 1,
          inputs: ['Cut copper', 'Drilled steel'],
          outputs: ['Frame body'],
          machine: 'Welder 01',
          durationHours: 2,
          status: 'Blocked',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'dolly-polish',
          name: 'Polishing',
          processType: 'Finish',
          stageIndex: 3,
          laneIndex: 1,
          inputs: ['Frame body'],
          outputs: ['Dolly frame'],
          machine: 'Polisher 01',
          durationHours: 1,
          status: 'Queued',
          isIntermediate: false,
          scannedInputs: [],
        },
      ],
      flows: [
        { id: 'flow-1', fromNodeId: 'dolly-input-copper', toNodeId: 'dolly-cut', materialName: 'Copper roll', barcode: null, isSplit: false, isMerge: false },
        { id: 'flow-2', fromNodeId: 'dolly-input-steel', toNodeId: 'dolly-drill', materialName: 'Steel sheet', barcode: null, isSplit: false, isMerge: false },
        { id: 'flow-3', fromNodeId: 'dolly-cut', toNodeId: 'dolly-weld', materialName: 'Cut copper', barcode: null, isSplit: false, isMerge: true },
        { id: 'flow-4', fromNodeId: 'dolly-drill', toNodeId: 'dolly-weld', materialName: 'Drilled steel', barcode: null, isSplit: false, isMerge: true },
        { id: 'flow-5', fromNodeId: 'dolly-weld', toNodeId: 'dolly-polish', materialName: 'Frame body', barcode: null, isSplit: false, isMerge: false },
      ],
    },
    {
      id: 'assembly',
      factoryId: '1',
      shopFloorId: '1',
      name: 'Assembly Mainline',
      description:
        'Three parallel sub-assemblies merge into a final assembly and packing handoff.',
      version: 1,
      status: 'active',
      stageLabels: ['Stage 1: Feed', 'Stage 2: Prep', 'Stage 3: Merge', 'Stage 4: Outbound'],
      laneLabels: ['Lane 1', 'Lane 2', 'Lane 3'],
      nodes: [
        {
          id: 'assembly-right',
          name: 'Right Side Panel',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 0,
          inputs: ['Right panel'],
          outputs: ['Ready right'],
          machine: 'Buffer A',
          durationHours: 0.25,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'assembly-left',
          name: 'Left Side Panel',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 1,
          inputs: ['Left panel'],
          outputs: ['Ready left'],
          machine: 'Buffer B',
          durationHours: 0.25,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'assembly-center',
          name: 'Center Body',
          processType: 'Input',
          stageIndex: 0,
          laneIndex: 2,
          inputs: ['Center body'],
          outputs: ['Ready center'],
          machine: 'Buffer C',
          durationHours: 0.25,
          status: 'Ready',
          isIntermediate: false,
          scannedInputs: [],
        },
        {
          id: 'assembly-fixture',
          name: 'Assembly Fixture',
          processType: 'Prep',
          stageIndex: 1,
          laneIndex: 1,
          inputs: ['Ready right', 'Ready left', 'Ready center'],
          outputs: ['Mounted body'],
          machine: 'Fixture 03',
          durationHours: 1.5,
          status: 'Active',
          isIntermediate: true,
          scannedInputs: [],
        },
        {
          id: 'assembly-pack',
          name: 'Packing',
          processType: 'Outbound',
          stageIndex: 3,
          laneIndex: 1,
          inputs: ['Mounted body'],
          outputs: ['Packed dolly'],
          machine: 'Packing 01',
          durationHours: 0.75,
          status: 'Queued',
          isIntermediate: false,
          scannedInputs: [],
        },
      ],
      flows: [
        { id: 'assembly-flow-1', fromNodeId: 'assembly-right', toNodeId: 'assembly-fixture', materialName: 'Ready right', barcode: null, isSplit: false, isMerge: true },
        { id: 'assembly-flow-2', fromNodeId: 'assembly-left', toNodeId: 'assembly-fixture', materialName: 'Ready left', barcode: null, isSplit: false, isMerge: true },
        { id: 'assembly-flow-3', fromNodeId: 'assembly-center', toNodeId: 'assembly-fixture', materialName: 'Ready center', barcode: null, isSplit: false, isMerge: true },
        { id: 'assembly-flow-4', fromNodeId: 'assembly-fixture', toNodeId: 'assembly-pack', materialName: 'Mounted body', barcode: null, isSplit: false, isMerge: false },
      ],
    },
  ];
}

// Repairs dangling `groups_old_migration` references left in other objects'
// schema (e.g. child-table foreign keys) when an older groups migration renamed
// the table. `groups_old_migration` is a migration-only temp name, so rewriting
// it back to `groups` anywhere it appears is always safe. Covers every object
// type, not just tables.
async function repairGroupsOldMigrationRefs() {
  try {
    const broken = await all(
      "SELECT name FROM sqlite_master WHERE sql LIKE '%groups_old_migration%' AND name != 'groups_old_migration'",
    );
    if (broken.length === 0) return;
    console.log(
      'Repairing dangling groups_old_migration references in:',
      broken.map((b) => b.name).join(', '),
    );
    await run('PRAGMA writable_schema = ON');
    await run(
      "UPDATE sqlite_master SET sql = replace(sql, 'groups_old_migration', 'groups') WHERE sql LIKE '%groups_old_migration%' AND name != 'groups_old_migration'",
    );
    await run('PRAGMA writable_schema = OFF');
    const { schema_version } = await get('PRAGMA schema_version');
    await run(`PRAGMA schema_version = ${schema_version + 1}`);
    console.log('Repaired groups_old_migration references.');
  } catch (err) {
    await run('PRAGMA writable_schema = OFF').catch(() => {});
    console.error('Failed to repair groups_old_migration references:', err);
  }
}

const SCHEMA_ORDER = [
  './modules/kernel/schema',
  './modules/units/schema',
  './modules/items/schema',
  './modules/clients/schema',
  './modules/vendors/schema',
  './modules/machines/schema',
  './modules/dies/schema',
  './modules/pipelines/schema',
  './modules/orders/schema',
  './modules/production/schema',
  './modules/inventory/schema',
  './modules/challans/schema',
  './modules/jobs/schema',
  './modules/action_center/schema',
  './modules/people/schema',
];

async function initDb() {

  await enableForeignKeys();

  // Heal any DB already broken by a prior rename-based groups migration.
  await repairGroupsOldMigrationRefs();

  // Cleanup legacy "Material Transform" labels
  try {
    const pipelineTemplatesTable = await get(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='pipeline_templates'",
    );
    if (pipelineTemplatesTable) {
      await run("UPDATE pipeline_templates SET stage_labels_json = replace(stage_labels_json, '\"Material Transform\"', '\"Process Stage\"')");
      await run("UPDATE pipeline_templates SET nodes_json = replace(nodes_json, '\"processType\":\"Material Transform\"', '\"processType\":\"Process Stage\"')");
    }
  } catch (err) {
    console.error('Failed to cleanup legacy Material Transform labels:', err);
  }

  // Migration: drop tables that still reference the old 'orders' table
  // (from the orders -> order_items refactor).  Must run BEFORE any
  // CREATE TABLE IF NOT EXISTS so those statements will re-create them
  // with the correct foreign keys pointing at order_items.
  try {
    const allTables = await all(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    const staleTables = [];
    for (const { name } of allTables) {
      const fks = await all(`PRAGMA foreign_key_list("${name}")`).catch(() => []);
      if (fks.some((fk) => fk.table === 'orders')) {
        staleTables.push(name);
      }
    }
    if (staleTables.length > 0) {
      // FK enforcement off so drop order doesn't matter (parents before children is fine)
      await run('PRAGMA foreign_keys = OFF');
      try {
        for (const name of staleTables) {
          await run(`DROP TABLE IF EXISTS "${name}"`);
          console.log(`Dropped stale table ${name} (referenced old 'orders' table)`);
        }
      } finally {
        await run('PRAGMA foreign_keys = ON');
      }
    }
  } catch (err) {
    console.error('Failed to drop tables referencing legacy orders table:', err);
  }
  await run('DROP TABLE IF EXISTS orders').catch(() => {});

  // Each module creates its own tables (stage 2d, 2026-11-19): the statements
  // that stood here, moved whole into modules/<name>/schema.js and run in this
  // order, the kernel's first. They run after the legacy tables that referenced
  // the old `orders` table are dropped above, as they always did. What follows
  // below is what still lives here: the rebuilds of tables whose shape changed
  // (groups, items, variation_stock, inventory_stock_positions, clients,
  // vendors, machines, pipeline_templates, piece_barcodes, the job tables),
  // their columns and indexes, the triggers, the backfills and the seeds.
  for (const schema of SCHEMA_ORDER) {
    await require(schema).createSchema({ run, all, get });
  }

  // Re-run the repair: heals any references this run's migration may have left
  // dangling (older DBs broken before the legacy_alter_table guard), so the
  // fix takes effect immediately instead of after the next restart.
  await repairGroupsOldMigrationRefs();

  // --- Column migrations for order_activity_log on pre-existing databases ---
  // The CREATE TABLE above is skipped if the table already exists. These
  // ensureColumnExists calls add any missing columns added in later versions.
  
  await migrateOrderActivityLogCompatibilityColumns();

  // Internal challans — free-text purpose (production consumption / transfers).
  // Reconciliation of an internal-use challan: JSON breakdown of each consumed
  // line settled across scrap/leftover/lost/rejection/finished-goods. Empty
  // until the mobile In-use reconciliation flow settles the challan.
  // Structured internal-challan subtype (e.g. 'vendor_return') — replaces
  // string-matching the free-text internal_purpose.
  // Vendor-return challans carry the scanned sheet tag codes so issuing can mark
  // those piece_barcodes returned (and reject a double return).
  // The reception a vendor return sends stock back from, when the return was
  // made by cancelling a partly used reception.
  await ensureDeliveryChallanItemNumericColumns();
  // Per-sheet weight breakdown for purchase intake: JSON array of numbers, one
  // per received sheet, summing to the line weight (total-in = total-out).
  await ensureInventorySetLineNullableLeafReference();

  // A set can now also be *produced* rather than defined: an assembly step
  // clips parts together and mints a temporary set into inventory, the same way
  // a run mints a temporary item. These columns carry where it came from so the
  // Sets tab can show its origin, and so re-reconciling a stage updates the set
  // it already made instead of minting another.

  await run(`
    UPDATE order_items
    SET updated_at = CASE
      WHEN TRIM(COALESCE(updated_at, '')) = '' THEN created_at
      ELSE updated_at
    END
  `);
  await run(`
    UPDATE order_items
    SET unit_id = (SELECT items.unit_id FROM items WHERE items.id = order_items.item_id)
    WHERE unit_id IS NULL
  `);
  await run(`
    UPDATE order_items
    SET unit_name = COALESCE((SELECT units.name FROM units WHERE units.id = order_items.unit_id), unit_name, 'Pieces')
    WHERE unit_id IS NOT NULL
      AND (TRIM(COALESCE(unit_name, '')) = '' OR TRIM(unit_name) = 'Pieces')
  `);
  await run(`
    UPDATE order_items
    SET unit_symbol = COALESCE((SELECT units.symbol FROM units WHERE units.id = order_items.unit_id), unit_symbol, unit_name, 'Pieces')
    WHERE unit_id IS NOT NULL
      AND (TRIM(COALESCE(unit_symbol, '')) = '' OR TRIM(unit_symbol) = 'Pieces')
  `);

  // Bootstrap parity with migrations/026-units-families.sql — fresh DBs (tests,
  // new deployments seeding before first boot) must match migrated DBs.
  // Bootstrap parity with migrations/051-units-contract-ladders.sql
  // Which set this line was expanded from, snapshotted at order time. Dead
  // labels, never a live reference: editing the set must not reach back and
  // change what was agreed. See saveOrder / _addLinesFromSet.
  // Bootstrap parity with migrations/027-stock-leaf-guards.sql: synthetic
  // negative variation ids (typed Gauge/Numeric selections) must never persist
  // as stock identity, no matter which future code path writes the row.
  for (const [table, guard] of [
    ['delivery_challan_items', 'NEW.variation_leaf_node_id < 0'],
    ['order_items', 'NEW.variation_leaf_node_id < 0'],
  ]) {
    await run(`
      CREATE TRIGGER IF NOT EXISTS trg_${table}_leaf_nonneg_ins
      BEFORE INSERT ON ${table}
      WHEN ${guard}
      BEGIN
        SELECT RAISE(ABORT, '${table}.variation_leaf_node_id must reference a real node (>= 0)');
      END
    `);
    await run(`
      CREATE TRIGGER IF NOT EXISTS trg_${table}_leaf_nonneg_upd
      BEFORE UPDATE OF variation_leaf_node_id ON ${table}
      WHEN ${guard}
      BEGIN
        SELECT RAISE(ABORT, '${table}.variation_leaf_node_id must reference a real node (>= 0)');
      END
    `);
  }
  // Leaf 0 is the stock of an item that has no variations: one figure for the
  // whole item. Only a negative leaf is nonsense. Which items may use 0 is
  // decided in assertValidStockVariationLeaf, which can read the item's tree; a
  // trigger cannot. The older trigger refused 0 as well, so it is replaced.
  await run('DROP TRIGGER IF EXISTS trg_variation_stock_leaf_positive_ins');
  await run(`
    CREATE TRIGGER IF NOT EXISTS trg_variation_stock_leaf_nonneg_ins
    BEFORE INSERT ON variation_stock
    WHEN NEW.variation_leaf_node_id < 0
    BEGIN
      SELECT RAISE(ABORT, 'variation_stock.variation_leaf_node_id must not be negative');
    END
  `);
  await backfillInventoryMovementQuantitySemantics();
  await run("UPDATE materials SET updated_at = created_at WHERE updated_at IS NULL");
  await seedRolePermissions();
  await seedPermissionTemplates();

  // Machine queue popup metadata: who scheduled the run and its batch weight.
  // Real machine↔run-node assignment (replaces name-matching the JSON override)
  // so a machine's pending queue is a first-class, indexable query.

  await backfillStageReconciliations();

  // Customer return / defect events — a sibling entity to orders (a completed
  // order can still have a return). Trigger for the backward QC lineage trace.

  if (SEED_DEMO_DATA_ON_BOOT) {
    await seedMaterialsIfEmpty();
  }
  // The unit families and their ladders (Pc / doz / gro, g / kg …) are the
  // units contract, not demo data. Behind the demo flag, a real database got
  // migration 051's family rows with no units linked to them, so every family
  // read back empty and no screen could offer dozens or gross. Idempotent.
  await seedUnitsIfEmpty();
  await backfillExpiringPhotoUrls();
  await bootstrapUnitsFromMaterials();
  await backfillMaterialUnitIds();
  if (SEED_DEMO_DATA_ON_BOOT) {
    await seedClientsIfEmpty();
    await seedCompanyProfileIfEmpty();
  }
  await ensurePrimaryGroupAndUnit();
  if (SEED_DEMO_DATA_ON_BOOT) {
    await seedGroupsIfEmpty();
    await seedItemsIfEmpty();
    await seedOrdersIfEmpty();
    await seedTemplatesIfEmpty();
    await ensureDemoDataset();
  }

  await run(`
    UPDATE groups 
    SET group_type = 'machine' 
    WHERE id IN (SELECT DISTINCT group_id FROM machines WHERE group_id IS NOT NULL)
  `);

  if (SEED_DEMO_DATA_ON_BOOT) {
    await seedMachinesAndDiesIfEmpty();
  }

  await bootstrapSuperAdminIfNeeded();
  // --- Constraint Migration (Triggers for existing tables) ---
    await run(`
      CREATE TRIGGER IF NOT EXISTS guard_item_variation_nodes_insert
      AFTER INSERT ON item_variation_nodes
      FOR EACH ROW
      BEGIN
        SELECT CASE
          WHEN NEW.id IS NOT NULL AND NEW.id <= 0 THEN RAISE(ABORT, 'item_variation_nodes.id must be positive')
          WHEN NEW.item_id IS NOT NULL AND NEW.item_id <= 0 THEN RAISE(ABORT, 'item_variation_nodes.item_id must be positive')
          WHEN NEW.parent_node_id IS NOT NULL AND NEW.parent_node_id <= 0 THEN RAISE(ABORT, 'item_variation_nodes.parent_node_id must be positive')
        END;
      END;
    `);
    await run(`
      CREATE TRIGGER IF NOT EXISTS guard_item_variation_nodes_update
      BEFORE UPDATE ON item_variation_nodes
      FOR EACH ROW
      BEGIN
        SELECT CASE
          WHEN NEW.id IS NOT NULL AND NEW.id <= 0 THEN RAISE(ABORT, 'item_variation_nodes.id must be positive')
          WHEN NEW.item_id IS NOT NULL AND NEW.item_id <= 0 THEN RAISE(ABORT, 'item_variation_nodes.item_id must be positive')
          WHEN NEW.parent_node_id IS NOT NULL AND NEW.parent_node_id <= 0 THEN RAISE(ABORT, 'item_variation_nodes.parent_node_id must be positive')
        END;
      END;
    `);
    // Replaced, not just created: these two refused leaf 0, which is now the
    // stock of an item with no variations.
    await run('DROP TRIGGER IF EXISTS guard_variation_stock_insert');
    await run('DROP TRIGGER IF EXISTS guard_variation_stock_update');
    await run(`
      CREATE TRIGGER IF NOT EXISTS guard_variation_stock_insert
      AFTER INSERT ON variation_stock
      FOR EACH ROW
      BEGIN
        SELECT CASE
          WHEN NEW.item_id IS NOT NULL AND NEW.item_id <= 0 THEN RAISE(ABORT, 'variation_stock.item_id must be positive')
          WHEN NEW.variation_leaf_node_id IS NOT NULL AND NEW.variation_leaf_node_id < 0 THEN RAISE(ABORT, 'variation_stock.variation_leaf_node_id must not be negative')
        END;
      END;
    `);
    await run(`
      CREATE TRIGGER IF NOT EXISTS guard_variation_stock_update
      BEFORE UPDATE ON variation_stock
      FOR EACH ROW
      BEGIN
        SELECT CASE
          WHEN NEW.item_id IS NOT NULL AND NEW.item_id <= 0 THEN RAISE(ABORT, 'variation_stock.item_id must be positive')
          WHEN NEW.variation_leaf_node_id IS NOT NULL AND NEW.variation_leaf_node_id < 0 THEN RAISE(ABORT, 'variation_stock.variation_leaf_node_id must not be negative')
        END;
      END;
    `);
    // The leaf is not a foreign key any more (0 names no node), so a deleted
    // leaf takes its stock rows with it here.
    await run(`
      CREATE TRIGGER IF NOT EXISTS trg_variation_stock_leaf_gone
      AFTER DELETE ON item_variation_nodes
      BEGIN
        DELETE FROM variation_stock WHERE variation_leaf_node_id = OLD.id;
      END
    `);
    await backfillWholeItemStock();

    await run(`
      CREATE TRIGGER IF NOT EXISTS guard_delivery_challan_items_insert
      AFTER INSERT ON delivery_challan_items
      FOR EACH ROW
      BEGIN
        SELECT CASE
          WHEN NEW.item_id IS NOT NULL AND NEW.item_id <= 0 THEN RAISE(ABORT, 'delivery_challan_items.item_id must be positive')
          WHEN NEW.variation_leaf_node_id < 0 THEN RAISE(ABORT, 'delivery_challan_items.variation_leaf_node_id must be non-negative')
        END;
      END;
    `);
    await run(`
      CREATE TRIGGER IF NOT EXISTS guard_delivery_challan_items_update
      BEFORE UPDATE ON delivery_challan_items
      FOR EACH ROW
      BEGIN
        SELECT CASE
          WHEN NEW.item_id IS NOT NULL AND NEW.item_id <= 0 THEN RAISE(ABORT, 'delivery_challan_items.item_id must be positive')
          WHEN NEW.variation_leaf_node_id < 0 THEN RAISE(ABORT, 'delivery_challan_items.variation_leaf_node_id must be non-negative')
        END;
      END;
    `);

  // Numbered migrations in backend/migrations/ run last, after the inline
  // schema above has created the tables they alter. Nothing ran them before
  // this, which is why payroll and the client portal existed only on
  // databases where someone had applied them by hand.
  await runPendingMigrations({ db, run, all });
  // The default Grade and Hardness columns, once their table (061) exists —
  // ensurePrimaryGroupAndUnit ran before it on a new database.
  await require('./modules/items/sheet-properties').ensureDefaultSheetProperties({ get, run });

  // Start the live push at the current head, so booting the server does not
  // replay the entire changelog at whoever happens to connect. A client that
  // was away catches up through its own `since` cursor instead, which is the
  // mechanism built for exactly that.
  try {
    const head = await get('SELECT MAX(id) AS maxId FROM changelog');
    lastEmittedChangeId = Number(head?.maxId || 0);
    // Boot is the natural moment: nothing is mid-catch-up, and it keeps the
    // table from growing without bound across a long-lived deployment.
    await pruneChangelog();
  } catch (_) {
    lastEmittedChangeId = 0;
  }

  // The push otherwise only drains when something calls logChange. Locally
  // that left seed scripts and hand edits unseen; in PRODUCTION it left every
  // route that relies on its triggers alone — dies, machines, die makers,
  // contacts, a part's group move or archive — unpushed until some unrelated
  // save happened to drain them, so an edit on the Dies screen never reached
  // a part open in another window. One indexed read a second covers them all.
  setInterval(drainChangelog, IS_PRODUCTION ? 1000 : 2000).unref();

  // Deleted photos' objects, a day on, and uploads never finished: what the
  // store would otherwise keep charging for.
  // Once per process, however often initDb runs (tests run it per case).
  if (!assetSweepScheduled) {
    assetSweepScheduled = true;
    const sweep = () =>
      sweepDeletedAssets().catch((error) =>
        console.warn(`[assets] sweep failed: ${error.message}`),
      );
    setTimeout(sweep, 30 * 1000).unref();
    setInterval(sweep, 3600 * 1000).unref();
  }

  // PINs stored plain before they were hashed are hashed now, once.
  const pinsHashed = await pinHasher.migrate({ all, run });
  if (pinsHashed) console.log(`Hashed ${pinsHashed} staff login PIN(s) that were stored as plain text.`);

  // Every changelog and derived trigger the migration files define, made sure
  // of on every boot (all IF NOT EXISTS). The migration runner applies a file
  // once, so a trigger added to one later reached an existing database only
  // after a Clear Data — the items → group count trigger (041) was the case.
  await restoreChangelogTriggers();

  dbReady = true;
}
async function ensurePrimaryGroupAndUnit() {
  let unit = await get('SELECT id FROM units WHERE name = "Primary Unit"');
  if (!unit) {
    await run("INSERT INTO units (name, symbol, notes, created_at, updated_at) VALUES ('Primary Unit', '-', 'Default unit for ungrouped items', datetime('now'), datetime('now'))");
    unit = await get('SELECT id FROM units WHERE name = "Primary Unit"');
  }
  let group = await get('SELECT id FROM groups WHERE name = "Primary Group" AND parent_group_id IS NULL');
  if (!group) {
    await run("INSERT INTO groups (name, parent_group_id, unit_id, created_at, updated_at) VALUES ('Primary Group', NULL, ?, datetime('now'), datetime('now'))", [unit.id]);
  }
  // Raw Materials and its default subgroups (Rivets, Springs). They are
  // looked up by system_key, so they come back the same after a wipe. The
  // unit ladder goes first: Clear Data and Factory Reset empty `units`, and
  // the subgroups are counted in Pieces. Both calls are idempotent.
  await seedStandardUnitFamilies({ run, get, all });
  const piece = await get("SELECT id FROM units WHERE LOWER(name) = 'piece' OR symbol = 'Pc' ORDER BY is_base DESC, id LIMIT 1");
  await ensureSystemGroups({ run, get }, { primary: unit.id, piece: piece?.id ?? unit.id });
  // Grade and Hardness on every item sheet (beside the built-in Alloy and
  // Thickness), back after a wipe like the default groups.
  await require('./modules/items/sheet-properties').ensureDefaultSheetProperties({ get, run });
  let scrapGroup = await get('SELECT id FROM groups WHERE name = "Scrap" AND parent_group_id IS NULL');
  if (!scrapGroup) {
    await run("INSERT INTO groups (name, parent_group_id, unit_id, created_at, updated_at) VALUES ('Scrap', NULL, ?, datetime('now'), datetime('now'))", [unit.id]);
  }
}

async function ensureDemoDataset(scenarioId = 'default') {
  await ensureDemoUnitsPresent(scenarioId);
  await seedStandardUnitFamilies({ run, get, all });
  await backfillMaterialUnitIds();
  await ensureDemoClientsPresent();
  await ensureDemoGroupsPresent(scenarioId);
  await ensureDemoItemsPresent(scenarioId);
  await ensureDemoOrdersPresent();
  await ensureDemoProductionRunsPresent();
  await ensureDemoMaterialsPresent();
  await backfillInventoryLedgerForMaterials({
    inferMissingPositions: SEED_DEMO_DATA_ON_BOOT,
  });
  await backfillMaterialUnitIds();
  await ensureDemoPipelineRunsPresent();
  await ensureDemoOrderRunLinks();
  await cleanupStaleUnlinkedPoDocuments();
  await ensureFullDemoSeedDataset();
}

function loadFullDemoSeedData() {
  if (!fs.existsSync(FULL_DEMO_SEED_PATH)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(FULL_DEMO_SEED_PATH, 'utf8'));
}

function seedDateTime(value, fallback = nowIso()) {
  if (!value) return fallback;
  const text = String(value);
  return text.includes('T') ? text : `${text}T09:00:00.000Z`;
}

function seedOrderStatus(value) {
  switch (String(value || '').trim()) {
    case 'draft':
      return 'draft';
    case 'completed':
      return 'completed';
    case 'in_production':
    case 'inProgress':
      return 'inProgress';
    case 'confirmed':
    default:
      return 'notStarted';
  }
}

function seedPipelineRunStatus(value) {
  switch (String(value || '').trim()) {
    case 'active':
    case 'in_production':
    case 'inProgress':
      return 'inProgress';
    case 'completed':
      return 'completed';
    default:
      return 'planned';
  }
}

async function ensureFullSeedUnit(unit, map) {
  const now = nowIso();
  const existing = await get(
    `
    SELECT * FROM units
    WHERE lower(name) = lower(?) OR lower(symbol) = lower(?)
    ORDER BY id
    LIMIT 1
    `,
    [unit.name, unit.symbol],
  );
  if (existing) {
    await run(
      `
      UPDATE units
      SET name = ?, symbol = ?, notes = ?, is_archived = 0, updated_at = ?
      WHERE id = ?
      `,
      [unit.name, unit.symbol, `Full demo seed: ${unit.category || 'unit'}`, now, existing.id],
    );
    map.set(unit.id, existing.id);
    return existing.id;
  }
  const result = await run(
    `
    INSERT INTO units (name, symbol, notes, is_archived, created_at, updated_at)
    VALUES (?, ?, ?, 0, ?, ?)
    `,
    [unit.name, unit.symbol, `Full demo seed: ${unit.category || 'unit'}`, now, now],
  );
  map.set(unit.id, result.lastID);
  return result.lastID;
}

async function ensureFullSeedGroup(name, groupType, unitId, cache) {
  const key = `${groupType}:${normalizeUnitValue(name)}`;
  if (cache.has(key)) {
    return cache.get(key);
  }
  const now = nowIso();
  const existing = await get(
    `
    SELECT id FROM groups
    WHERE lower(name) = lower(?) AND group_type = ?
    ORDER BY id
    LIMIT 1
    `,
    [name, groupType],
  );
  if (existing) {
    await run(
      'UPDATE groups SET unit_id = COALESCE(?, unit_id), is_archived = 0, updated_at = ? WHERE id = ?',
      [unitId || null, now, existing.id],
    );
    cache.set(key, existing.id);
    return existing.id;
  }
  const result = await run(
    `
    INSERT INTO groups (name, group_type, parent_group_id, unit_id, is_archived, created_at, updated_at)
    VALUES (?, ?, NULL, ?, 0, ?, ?)
    `,
    [name, groupType, unitId || null, now, now],
  );
  cache.set(key, result.lastID);
  return result.lastID;
}

async function ensureFullSeedClient(client, map) {
  const now = nowIso();
  const existing = await get('SELECT id FROM clients WHERE lower(name) = lower(?) LIMIT 1', [client.name]);
  const params = [
    client.name,
    client.id,
    client.gstin || '',
    client.billingAddress || client.shippingAddress || '',
    now,
  ];
  if (existing) {
    await run(
      `
      UPDATE clients
      SET name = ?, alias = ?, gst_number = ?, address = ?, is_archived = 0, updated_at = ?
      WHERE id = ?
      `,
      [...params, existing.id],
    );
    map.set(client.id, existing.id);
    return existing.id;
  }
  const result = await run(
    `
    INSERT INTO clients (name, alias, gst_number, address, is_archived, created_at, updated_at)
    VALUES (?, ?, ?, ?, 0, ?, ?)
    `,
    [client.name, client.id, client.gstin || '', client.billingAddress || client.shippingAddress || '', now, now],
  );
  map.set(client.id, result.lastID);
  return result.lastID;
}

async function ensureFullSeedVendor(vendor, map) {
  const now = nowIso();
  const existing = await get('SELECT id FROM vendors WHERE lower(name) = lower(?) LIMIT 1', [vendor.name]);
  if (existing) {
    await run(
      `
      UPDATE vendors
      SET name = ?, alias = ?, gst_number = ?, address = ?, contact_name = ?,
          phone = ?, email = ?, is_archived = 0, updated_at = ?
      WHERE id = ?
      `,
      [
        vendor.name,
        vendor.id,
        vendor.gstin || '',
        vendor.address || '',
        vendor.contactPerson || '',
        vendor.phone || '',
        vendor.email || '',
        now,
        existing.id,
      ],
    );
    map.set(vendor.id, existing.id);
    return existing.id;
  }
  const result = await run(
    `
    INSERT INTO vendors (
      name, alias, gst_number, address, contact_name, phone, email,
      is_archived, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
    `,
    [
      vendor.name,
      vendor.id,
      vendor.gstin || '',
      vendor.address || '',
      vendor.contactPerson || '',
      vendor.phone || '',
      vendor.email || '',
      now,
      now,
    ],
  );
  map.set(vendor.id, result.lastID);
  return result.lastID;
}

async function ensureFullSeedItem(item, unitMap, groupCache, itemMap) {
  const now = nowIso();
  const unitId = unitMap.get(item.unitId);
  const groupName = item.itemType === 'raw' ? 'Raw Materials' : 'Finished Goods';
  const groupId = await ensureFullSeedGroup(groupName, 'item', unitId, groupCache);
  const existing = await get(
    `
    SELECT id FROM items
    WHERE lower(name) = lower(?) OR lower(alias) = lower(?)
    ORDER BY id
    LIMIT 1
    `,
    [item.name, item.sku],
  );
  if (existing) {
    await run(
      `
      UPDATE items
      SET name = ?, alias = ?, display_name = ?, quantity = ?, group_id = ?,
          unit_id = ?, default_pipeline_id = ?, is_archived = 0, updated_at = ?
      WHERE id = ?
      `,
      [
        item.name,
        item.sku,
        item.name,
        Number(item.standardCost || 0),
        groupId,
        unitId,
        item.defaultPipelineId || null,
        now,
        existing.id,
      ],
    );
    itemMap.set(item.id, existing.id);
    return existing.id;
  }
  const result = await run(
    `
    INSERT INTO items (
      name, alias, display_name, quantity, group_id, unit_id,
      default_pipeline_id, is_archived, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
    `,
    [
      item.name,
      item.sku,
      item.name,
      Number(item.standardCost || 0),
      groupId,
      unitId,
      item.defaultPipelineId || null,
      now,
      now,
    ],
  );
  itemMap.set(item.id, result.lastID);
  return result.lastID;
}

async function ensureFullSeedUser(user, userMap) {
  const now = nowIso();
  const email = normalizeEmail(user.email);
  const role = user.role === 'admin' ? 'admin' : 'user';
  const existing = await get('SELECT id FROM users WHERE email = ?', [email]);
  let userId;
  if (existing) {
    await run(
      'UPDATE users SET name = ?, role = ?, is_active = ?, updated_at = ? WHERE id = ?',
      [user.name, role, user.status === 'active' ? 1 : 0, now, existing.id],
    );
    userId = existing.id;
  } else {
    const result = await run(
      `
      INSERT INTO users (
        name, email, password_hash, role, is_active, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        user.name,
        email,
        hashPassword('Paper@12345'),
        role,
        user.status === 'active' ? 1 : 0,
        now,
        now,
      ],
    );
    userId = result.lastID;
  }

  if (role === 'user') {
    const requested = new Set((user.permissions || []).filter((key) => PERMISSION_KEYS.includes(key)));
    if (user.role === 'production_operator') {
      requested.add('inventory.read');
      requested.add('config.read');
    }
    if (user.role === 'warehouse_staff') {
      requested.add('inventory.read');
      requested.add('inventory.create');
      requested.add('inventory.update');
      requested.add('config.read');
    }
    for (const key of requested) {
      await run(
        `
        INSERT INTO user_permission_overrides (
          user_id, permission_key, is_allowed, created_at, updated_at
        ) VALUES (?, ?, 1, ?, ?)
        ON CONFLICT(user_id, permission_key)
        DO UPDATE SET is_allowed = 1, updated_at = excluded.updated_at
        `,
        [userId, key, now, now],
      );
    }
  }
  userMap.set(user.id, userId);
  return userId;
}

async function ensureFullSeedMachine(machine, groupCache, machineMap) {
  const now = nowIso();
  const pieceUnit = await get('SELECT id FROM units WHERE lower(symbol) IN (\'pcs\', \'pieces\') ORDER BY id LIMIT 1');
  const groupId = await ensureFullSeedGroup(machine.machineGroup, 'machine', pieceUnit?.id || null, groupCache);
  const existing = await get('SELECT id FROM machines WHERE asset_id = ? LIMIT 1', [machine.barcode]);
  if (existing) {
    await run(
      `
      UPDATE machines
      SET name = ?, primary_photo_url = NULL, group_id = ?, make_model = ?,
          serial_number = ?, location = ?, status = ?, custom_properties = ?, updated_at = ?
      WHERE id = ?
      `,
      [
        machine.name,
        groupId,
        machine.machineGroup,
        machine.id,
        'Main Floor',
        machine.status || 'available',
        JSON.stringify([{ label: 'Hourly Rate', value: String(machine.hourlyRate || 0) }]),
        now,
        existing.id,
      ],
    );
    machineMap.set(machine.id, existing.id);
    return existing.id;
  }
  const result = await run(
    `
    INSERT INTO machines (
      name, asset_id, primary_photo_url, group_id, make_model, serial_number,
      location, installation_date, status, custom_properties, created_at, updated_at
    ) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      machine.name,
      machine.barcode,
      groupId,
      machine.machineGroup,
      machine.id,
      'Main Floor',
      '2025-04-01',
      machine.status || 'available',
      JSON.stringify([{ label: 'Hourly Rate', value: String(machine.hourlyRate || 0) }]),
      now,
      now,
    ],
  );
  machineMap.set(machine.id, result.lastID);
  return result.lastID;
}

async function ensureFullSeedDie(die, seed, machineMap, groupCache, dieMap) {
  const now = nowIso();
  const compatibleGroupIds = [];
  for (const machineId of die.compatibleMachineIds || []) {
    const machineSeed = (seed.machines || []).find((item) => item.id === machineId);
    if (machineSeed) {
      const machineRowId = machineMap.get(machineId);
      const machineRow = machineRowId ? await get('SELECT group_id FROM machines WHERE id = ?', [machineRowId]) : null;
      if (machineRow?.group_id && !compatibleGroupIds.includes(machineRow.group_id)) {
        compatibleGroupIds.push(machineRow.group_id);
      }
    }
  }
  const existing = await get('SELECT id FROM dies WHERE tool_code = ? LIMIT 1', [die.barcode]);
  const values = [
    die.barcode,
    JSON.stringify([die.name]),
    JSON.stringify([die.photoUrl || '']),
    die.notes || '',
    JSON.stringify(compatibleGroupIds),
    'Tool Room',
    1,
    Number(die.strokeCount || 0),
    Number(die.maintenanceDueAt || 0),
    JSON.stringify({ name: die.name }),
    'available',
    'company',
    now,
  ];
  if (existing) {
    await run(
      `
      UPDATE dies
      SET produced_part_numbers = ?, photo_urls = ?, operational_notes = ?,
          compatible_machine_group_ids = ?, storage_location = ?,
          number_of_cavities = ?, stroke_count = ?, max_strokes = ?,
          physical_specs = ?, status = ?, ownership = ?, updated_at = ?
      WHERE id = ?
      `,
      [...values.slice(1), existing.id],
    );
    dieMap.set(die.id, existing.id);
    return existing.id;
  }
  const result = await run(
    `
    INSERT INTO dies (
      tool_code, produced_part_numbers, photo_urls, operational_notes,
      compatible_machine_group_ids, storage_location, number_of_cavities,
      stroke_count, max_strokes, physical_specs, status, ownership,
      created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [...values, now],
  );
  dieMap.set(die.id, result.lastID);
  return result.lastID;
}

function fullSeedEndpointFor(itemSeed, itemMap, unitMap, seed) {
  if (!itemSeed) return null;
  const unitSeed = (seed.units || []).find((unit) => unit.id === itemSeed.unitId);
  return {
    itemId: itemMap.get(itemSeed.id) || 0,
    itemName: itemSeed.name,
    unitId: unitMap.get(itemSeed.unitId) || 0,
    unitName: unitSeed?.name || '',
    unitSymbol: unitSeed?.symbol || '',
  };
}

async function ensureFullSeedPipeline(pipeline, seed, itemMap, unitMap, templateMap) {
  const now = nowIso();
  const stageLabels = (pipeline.stages || []).map((stage) => stage.name);
  const nodes = (pipeline.stages || []).map((stage, index) => {
    const firstInput = stage.inputs?.[0];
    const firstOutput = stage.outputs?.[0];
    const inputSeed = firstInput ? seed.items.find((item) => item.id === firstInput.itemId) : null;
    const outputSeed = firstOutput ? seed.items.find((item) => item.id === firstOutput.itemId) : null;
    const machineSeed = seed.machines.find((item) => item.id === stage.machineId);
    const dieSeed = seed.dies.find((item) => item.id === stage.dieId);
    return {
      id: stage.id,
      name: stage.name,
      processType: index === 0 ? 'Input' : index === pipeline.stages.length - 1 ? 'Output' : 'Process',
      stageIndex: index,
      laneIndex: 0,
      inputs: (stage.inputs || []).map((input) => seed.items.find((item) => item.id === input.itemId)?.name || input.itemId),
      outputs: (stage.outputs || []).map((output) => seed.items.find((item) => item.id === output.itemId)?.name || output.itemId),
      machine: machineSeed?.name || '',
      dieId: dieSeed?.barcode || '',
      durationHours: Number(stage.expectedHours || 0),
      status: 'Ready',
      isIntermediate: index > 0 && index < pipeline.stages.length - 1,
      scannedInputs: [],
      inputItem: fullSeedEndpointFor(inputSeed, itemMap, unitMap, seed),
      outputItem: fullSeedEndpointFor(outputSeed, itemMap, unitMap, seed),
    };
  });
  const flows = nodes.slice(0, -1).map((node, index) => ({
    id: `${pipeline.id}-flow-${index + 1}`,
    fromNodeId: node.id,
    toNodeId: nodes[index + 1].id,
    materialName: node.outputs[0] || nodes[index + 1].inputs[0] || '',
    barcode: null,
    isSplit: false,
    isMerge: false,
  }));
  await run(
    `
    INSERT INTO pipeline_templates (
      id, factory_id, shop_floor_id, name, description, version, status,
      stage_labels_json, lane_labels_json, nodes_json, flows_json,
      intermediate_naming_convention, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id)
    DO UPDATE SET
      name = excluded.name,
      description = excluded.description,
      version = excluded.version,
      status = excluded.status,
      stage_labels_json = excluded.stage_labels_json,
      lane_labels_json = excluded.lane_labels_json,
      nodes_json = excluded.nodes_json,
      flows_json = excluded.flows_json,
      intermediate_naming_convention = excluded.intermediate_naming_convention,
      updated_at = excluded.updated_at
    `,
    [
      pipeline.id,
      'default',
      'floor-1',
      pipeline.name,
      `${pipeline.name} seeded from backend/demo_seed_full.json`,
      pipeline.version || 1,
      pipeline.status === 'active' ? 'published' : pipeline.status || 'draft',
      JSON.stringify(stageLabels),
      JSON.stringify(['Main']),
      JSON.stringify(nodes),
      JSON.stringify(flows),
      'stage-output',
      now,
      now,
    ],
  );
  templateMap.set(pipeline.id, pipeline.id);
}

async function ensureFullSeedOrder(order, seed, clientMap, itemMap, unitMap, orderMap, orderLineMap) {
  const now = nowIso();
  const clientId = clientMap.get(order.clientId);
  const clientSeed = seed.clients.find((client) => client.id === order.clientId);
  await run(
    `
    INSERT INTO order_headers (order_no, client_id, po_number, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(order_no)
    DO UPDATE SET client_id = excluded.client_id, po_number = excluded.po_number, updated_at = excluded.updated_at
    `,
    [order.orderNo, clientId, `PO-${order.orderNo}`, seedDateTime(order.orderDate, now), now],
  );
  orderMap.set(order.id, order.orderNo);
  for (const line of order.lineItems || []) {
    const itemId = itemMap.get(line.itemId);
    const unitId = unitMap.get(line.unitId);
    const itemSeed = seed.items.find((item) => item.id === line.itemId);
    const unitSeed = seed.units.find((unit) => unit.id === line.unitId);
    const existing = await get(
      'SELECT id FROM order_items WHERE order_no = ? AND item_id = ? AND variation_leaf_node_id = 0 LIMIT 1',
      [order.orderNo, itemId],
    );
    const values = [
      order.orderNo,
      clientId,
      clientSeed?.name || '',
      `PO-${order.orderNo}`,
      clientSeed?.id || '',
      itemId,
      itemSeed?.name || '',
      Number(line.quantity || 0),
      unitId,
      unitSeed?.name || '',
      unitSeed?.symbol || '',
      Number(line.price || 0),
      seedOrderStatus(order.status),
      seedDateTime(order.orderDate, now),
      now,
      order.orderDate || null,
      order.deliveryDate || null,
      Number(line.price || 0) * Number(line.quantity || 0),
    ];
    let rowId;
    if (existing) {
      await run(
        `
        UPDATE order_items
        SET client_id = ?, client_name = ?, po_number = ?, client_code = ?,
            item_id = ?, item_name = ?, quantity = ?, unit_id = ?, unit_name = ?,
            unit_symbol = ?, unit_price = ?, status = ?, updated_at = ?,
            start_date = ?, end_date = ?, taxable_value = ?
        WHERE id = ?
        `,
        [...values.slice(1, 13), now, order.orderDate || null, order.deliveryDate || null, values[17], existing.id],
      );
      rowId = existing.id;
    } else {
      const result = await run(
        `
        INSERT INTO order_items (
          order_no, client_id, client_name, po_number, client_code, item_id,
          item_name, quantity, unit_id, unit_name, unit_symbol, unit_price,
          status, created_at, updated_at, start_date, end_date, taxable_value
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `,
        values,
      );
      rowId = result.lastID;
    }
    orderLineMap.set(line.id, rowId);
  }
}

async function ensureFullSeedMaterial(stock, seed, itemMap, unitMap, vendorMap, materialMap) {
  const now = nowIso();
  const itemSeed = seed.items.find((item) => item.id === stock.itemId);
  const unitSeed = seed.units.find((unit) => unit.id === stock.unitId);
  const vendorSeed = seed.vendors.find((vendor) => vendor.id === stock.supplierId);
  const itemId = itemMap.get(stock.itemId);
  const unitId = unitMap.get(stock.unitId);
  await run(
    `
    INSERT INTO materials (
      barcode, name, type, grade, thickness, supplier, location, unit_id, unit,
      notes, group_mode, inheritance_enabled, created_at, kind, parent_barcode,
      number_of_children, linked_child_barcodes, scan_count, linked_item_id,
      display_stock, created_by, workflow_status, material_class,
      inventory_state, procurement_state, traceability_mode, on_hand_qty,
      reserved_qty, available_to_promise_qty, incoming_qty, linked_order_count,
      linked_pipeline_count, pending_alert_count, updated_at, last_scanned_at
    ) VALUES (?, ?, ?, '', '', ?, ?, ?, ?, ?, NULL, 0, ?, 'parent', NULL, 0, '[]', 0, ?, ?, 'seed', 'completed', ?, 'available', 'received', 'lot', ?, ?, ?, 0, 0, 0, 0, ?, ?)
    ON CONFLICT(barcode)
    DO UPDATE SET
      name = excluded.name,
      type = excluded.type,
      supplier = excluded.supplier,
      location = excluded.location,
      unit_id = excluded.unit_id,
      unit = excluded.unit,
      notes = excluded.notes,
      linked_item_id = excluded.linked_item_id,
      display_stock = excluded.display_stock,
      material_class = excluded.material_class,
      on_hand_qty = excluded.on_hand_qty,
      reserved_qty = excluded.reserved_qty,
      available_to_promise_qty = excluded.available_to_promise_qty,
      updated_at = excluded.updated_at,
      last_scanned_at = excluded.last_scanned_at
    `,
    [
      stock.barcode,
      itemSeed?.name || stock.id,
      itemSeed?.itemType === 'finished' ? 'Finished Goods' : 'Raw Material',
      vendorSeed?.name || '',
      stock.location || '',
      unitId || null,
      unitSeed?.symbol || '',
      `Full demo seed lot ${stock.lotNo || stock.id}`,
      seedDateTime(stock.lastMovementAt, now),
      itemId || null,
      `${Number(stock.onHand || 0)} ${unitSeed?.symbol || ''}`.trim(),
      itemSeed?.itemType === 'finished' ? 'finished_goods' : 'raw_material',
      Number(stock.onHand || 0),
      Number(stock.reserved || 0),
      Number(stock.availableToPromise ?? stock.onHand ?? 0),
      now,
      seedDateTime(stock.lastMovementAt, now),
    ],
  );
  const material = await getMaterialRowByBarcode(stock.barcode);
  if (material) {
    materialMap.set(stock.id, material);
  }
}

async function ensureFullSeedProductionRun(runSeed, seed, itemMap, unitMap, orderLineMap, pipelineRunMap, productionRunMap) {
  const now = nowIso();
  const orderLineId = orderLineMap.get(runSeed.orderLineItemId);
  const lineSeed = (seed.orders || [])
    .flatMap((order) => order.lineItems || [])
    .find((line) => line.id === runSeed.orderLineItemId);
  const itemId = itemMap.get(lineSeed?.itemId);
  const unitSeed = seed.units.find((unit) => unit.id === lineSeed?.unitId);
  const existingSnapshot = await get('SELECT id FROM production_runs WHERE run_code = ? LIMIT 1', [runSeed.id]);
  let productionRunId;
  const snapshotValues = [
    runSeed.id,
    runSeed.status === 'completed' ? 'completed' : seedPipelineRunStatus(runSeed.status),
    seedDateTime(runSeed.endedAt, null),
    itemId,
    0,
    '',
    Number(runSeed.goodYield || 0),
    unitSeed?.symbol || 'pcs',
    'FG',
    JSON.stringify({
      seedId: runSeed.id,
      pipelineId: runSeed.pipelineId,
      orderId: runSeed.orderId,
      stageActuals: runSeed.stageActuals || [],
    }),
    seedDateTime(runSeed.startedAt, now),
    now,
  ];
  if (existingSnapshot) {
    await run(
      `
      UPDATE production_runs
      SET status = ?, completed_at = ?, item_id = ?, variation_leaf_node_id = ?,
          variation_path_label = ?, output_quantity = ?, uom = ?, location = ?,
          source_metadata_json = ?, updated_at = ?
      WHERE id = ?
      `,
      [...snapshotValues.slice(1, 10), now, existingSnapshot.id],
    );
    productionRunId = existingSnapshot.id;
  } else if (itemId) {
    const result = await run(
      `
      INSERT INTO production_runs (
        run_code, status, completed_at, item_id, variation_leaf_node_id,
        variation_path_label, output_quantity, uom, location,
        source_metadata_json, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      snapshotValues,
    );
    productionRunId = result.lastID;
  }
  if (productionRunId) {
    productionRunMap.set(runSeed.id, productionRunId);
  }

  const pipelineSeed = seed.pipelines.find((pipeline) => pipeline.id === runSeed.pipelineId);
  const stageIds = (pipelineSeed?.stages || []).map((stage) => stage.id);
  const nodeStatuses = Object.fromEntries(stageIds.map((stageId) => [stageId, 'pending']));
  const actualDurationHoursByNode = {};
  const batchQuantityByNode = {};
  const machineOverrideByNode = {};
  const nodeMetrics = {};
  for (const actual of runSeed.stageActuals || []) {
    nodeStatuses[actual.stageId] = seedPipelineRunStatus(actual.status);
    actualDurationHoursByNode[actual.stageId] = Number(actual.actualHours || 0);
    batchQuantityByNode[actual.stageId] = Number(actual.goodQty || 0);
    const machineSeed = seed.machines.find((machine) => machine.id === actual.machineId);
    if (machineSeed) {
      machineOverrideByNode[actual.stageId] = machineSeed.name;
    }
    nodeMetrics[actual.stageId] = {
      goodYield: Number(actual.goodQty || 0),
      scrap: Number(actual.scrapQty || 0),
      actualHours: Number(actual.actualHours || 0),
    };
  }
  await run(
    `
    INSERT INTO pipeline_runs (
      id, template_id, template_version, name, status, overrides_json,
      node_status_json, scrap_routing, node_metrics_json, started_at,
      completed_at, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'inventory', ?, ?, ?, ?)
    ON CONFLICT(id)
    DO UPDATE SET
      template_id = excluded.template_id,
      template_version = excluded.template_version,
      name = excluded.name,
      status = excluded.status,
      overrides_json = excluded.overrides_json,
      node_status_json = excluded.node_status_json,
      scrap_routing = excluded.scrap_routing,
      node_metrics_json = excluded.node_metrics_json,
      started_at = excluded.started_at,
      completed_at = excluded.completed_at,
      created_at = excluded.created_at
    `,
    [
      runSeed.id,
      runSeed.pipelineId,
      pipelineSeed?.version || 1,
      `${pipelineSeed?.name || 'Production'} - ${runSeed.id}`,
      seedPipelineRunStatus(runSeed.status),
      JSON.stringify({ actualDurationHoursByNode, batchQuantityByNode, machineOverrideByNode }),
      JSON.stringify(nodeStatuses),
      JSON.stringify(nodeMetrics),
      seedDateTime(runSeed.startedAt, null),
      seedDateTime(runSeed.endedAt, null),
      seedDateTime(runSeed.startedAt, now),
    ],
  );
  await run('DELETE FROM order_pipeline_assignments WHERE pipeline_run_id = ?', [runSeed.id]);
  if (orderLineId) {
    await run(
      `
      INSERT INTO order_pipeline_assignments (order_item_id, pipeline_run_id, allocated_quantity, created_at)
      VALUES (?, ?, ?, ?)
      `,
      [orderLineId, runSeed.id, Number(runSeed.plannedQuantity || 0), now],
    );
  }
  await run('DELETE FROM run_barcode_inputs WHERE run_id = ?', [runSeed.id]);
  for (const assignment of runSeed.assignedStock || []) {
    const material = await getMaterialRowByBarcode(assignment.barcode);
    if (!material) continue;
    await run(
      `
      INSERT INTO run_barcode_inputs (
        id, run_id, node_id, barcode, material_id, material_payload_json, scanned_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        `${runSeed.id}-${assignment.stageId}-${assignment.barcode}`,
        runSeed.id,
        assignment.stageId,
        assignment.barcode,
        String(material.id),
        JSON.stringify({
          barcode: material.barcode,
          materialName: material.name,
          materialType: material.type,
          scanCount: material.scan_count || 0,
        }),
        seedDateTime(runSeed.startedAt, now),
      ],
    );
  }
  pipelineRunMap.set(runSeed.id, runSeed.id);
}

async function ensureFullSeedChallan(challan, seed, clientMap, vendorMap, itemMap, unitMap, orderLineMap, productionRunMap, challanMap) {
  const now = nowIso();
  const orderSeed = seed.orders.find((order) => order.id === challan.orderId);
  const firstOrderLine = orderSeed?.lineItems?.[0];
  const orderLineId = firstOrderLine ? orderLineMap.get(firstOrderLine.id) : null;
  const clientSeed = seed.clients.find((client) => client.id === challan.clientId);
  const vendorSeed = seed.vendors.find((vendor) => vendor.id === challan.vendorId);
  const existing = await get('SELECT id FROM delivery_challans WHERE challan_no = ? LIMIT 1', [challan.challanNo]);
  const values = [
    challan.type,
    orderLineId || null,
    orderSeed?.orderNo || '',
    challan.challanNo,
    challan.date,
    challan.type === 'delivery' ? clientSeed?.name || '' : vendorSeed?.name || '',
    challan.type === 'delivery' ? clientSeed?.gstin || '' : vendorSeed?.gstin || '',
    vendorMap.get(challan.vendorId) || null,
    vendorSeed?.name || '',
    vendorSeed?.gstin || '',
    clientMap.get(challan.clientId) || null,
    clientSeed?.name || '',
    clientSeed?.gstin || '',
    challan.purchaseOrderId || orderSeed?.orderNo || '',
    `Full seed ${challan.type} challan`,
    challan.type === 'delivery' ? 'outward' : 'job_work',
    challan.status || 'draft',
    challan.isPrinted ? 1 : 0,
    now,
  ];
  let challanId;
  if (existing) {
    await run(
      `
      UPDATE delivery_challans
      SET type = ?, order_id = ?, order_no = ?, date = ?, customer_name = ?,
          customer_gstin = ?, vendor_id = ?, vendor_name = ?, vendor_gstin = ?,
          material_owner_client_id = ?, material_owner_client_name = ?,
          material_owner_gstin = ?, source_reference = ?, notes = ?,
          purpose = ?, status = ?, used_in_report = ?, updated_at = ?
      WHERE id = ?
      `,
      [
        values[0], values[1], values[2], values[4], values[5], values[6],
        values[7], values[8], values[9], values[10], values[11], values[12],
        values[13], values[14], values[15], values[16], values[17], now,
        existing.id,
      ],
    );
    challanId = existing.id;
  } else {
    const result = await run(
      `
      INSERT INTO delivery_challans (
        type, order_id, order_no, challan_no, date, customer_name,
        customer_gstin, vendor_id, vendor_name, vendor_gstin,
        material_owner_client_id, material_owner_client_name,
        material_owner_gstin, source_reference, notes, purpose, status,
        used_in_report, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [...values, now],
    );
    challanId = result.lastID;
  }
  challanMap.set(challan.id, challanId);
  await run('DELETE FROM delivery_challan_items WHERE challan_id = ?', [challanId]);
  let lineNo = 1;
  for (const line of challan.lineItems || []) {
    const unitSeed = seed.units.find((unit) => unit.id === line.unitId);
    const itemSeed = seed.items.find((item) => item.id === line.itemId);
    const isWeight = normalizeUnitValue(unitSeed?.symbol || '') === 'kg';
    await run(
      `
      INSERT INTO delivery_challan_items (
        challan_id, order_item_id, production_run_id, item_id,
        variation_leaf_node_id, line_no, particulars, hsn_code, note,
        quantity_pcs, weight, created_at, updated_at
      ) VALUES (?, ?, ?, ?, 0, ?, ?, '', ?, ?, ?, ?, ?)
      `,
      [
        challanId,
        orderLineId || null,
        productionRunMap.get(challan.productionRunId) || null,
        itemMap.get(line.itemId) || null,
        lineNo,
        itemSeed?.name || line.itemId,
        challan.type === 'delivery' ? 'Dispatch from full demo seed' : 'Reception from full demo seed',
        isWeight ? 0 : Number(line.quantity || 0),
        isWeight ? Number(line.quantity || 0) : 0,
        now,
        now,
      ],
    );
    lineNo += 1;
  }
}

async function ensureFullSeedInventoryPositions(seed, unitMap, challanMap) {
  const now = nowIso();
  for (const stock of seed.inventory || []) {
    const material = await getMaterialRowByBarcode(stock.barcode);
    if (!material) continue;
    const unitSeed = seed.units.find((unit) => unit.id === stock.unitId);
    await run(
      `
      DELETE FROM inventory_stock_positions
      WHERE material_barcode = ? AND location_id = ? AND lot_code = ?
      `,
      [material.barcode, stock.location || 'MAIN', stock.lotNo || stock.id],
    );
    await run(
      `
      INSERT INTO inventory_stock_positions (
        material_barcode, location_id, lot_code, unit_id, on_hand_qty,
        reserved_qty, damaged_qty, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, 0, ?)
      `,
      [
        material.barcode,
        stock.location || 'MAIN',
        stock.lotNo || stock.id,
        unitMap.get(stock.unitId) || null,
        Number(stock.onHand || 0),
        Number(stock.reserved || 0),
        seedDateTime(stock.lastMovementAt, now),
      ],
    );
    await run(
      `
      INSERT OR REPLACE INTO inventory_movements (
        id, material_barcode, movement_type, qty, primary_qty, uom,
        from_location_id, to_location_id, reason_code, reference_type,
        reference_id, source_challan_id, source_challan_type,
        source_challan_line_id, reverses_movement_id, actor, lot_code,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, 'FULL_DEMO_SEED', ?, ?, ?, ?, NULL, NULL, ?, ?, ?)
      `,
      [
        `seed-${stock.id}`,
        material.barcode,
        stock.receivedChallanId ? 'receive' : 'adjust',
        Number(stock.onHand || 0),
        Number(stock.onHand || 0),
        unitSeed?.symbol || '',
        stock.location || 'MAIN',
        stock.receivedChallanId ? 'challan' : 'opening_balance',
        stock.receivedChallanId || stock.id,
        challanMap.get(stock.receivedChallanId) || null,
        stock.receivedChallanId ? 'reception' : null,
        'Full demo seed',
        stock.lotNo || stock.id,
        seedDateTime(stock.lastMovementAt, now),
      ],
    );
    await inventoryPorts.ledger.recomputeSummary(material.barcode);
  }
}

async function ensureFullDemoSeedDataset() {
  const seed = loadFullDemoSeedData();
  if (!seed) {
    return;
  }
  const unitMap = new Map();
  const clientMap = new Map();
  const vendorMap = new Map();
  const itemMap = new Map();
  const machineMap = new Map();
  const dieMap = new Map();
  const userMap = new Map();
  const templateMap = new Map();
  const orderMap = new Map();
  const orderLineMap = new Map();
  const materialMap = new Map();
  const pipelineRunMap = new Map();
  const productionRunMap = new Map();
  const challanMap = new Map();
  const groupCache = new Map();

  for (const unit of seed.units || []) {
    await ensureFullSeedUnit(unit, unitMap);
  }
  for (const client of seed.clients || []) {
    await ensureFullSeedClient(client, clientMap);
  }
  for (const vendor of seed.vendors || []) {
    await ensureFullSeedVendor(vendor, vendorMap);
  }
  for (const item of seed.items || []) {
    await ensureFullSeedItem(item, unitMap, groupCache, itemMap);
  }
  for (const machine of seed.machines || []) {
    await ensureFullSeedMachine(machine, groupCache, machineMap);
  }
  for (const die of seed.dies || []) {
    await ensureFullSeedDie(die, seed, machineMap, groupCache, dieMap);
  }
  for (const pipeline of seed.pipelines || []) {
    await ensureFullSeedPipeline(pipeline, seed, itemMap, unitMap, templateMap);
  }
  for (const user of seed.users || []) {
    await ensureFullSeedUser(user, userMap);
  }
  for (const order of seed.orders || []) {
    await ensureFullSeedOrder(order, seed, clientMap, itemMap, unitMap, orderMap, orderLineMap);
  }
  for (const stock of seed.inventory || []) {
    await ensureFullSeedMaterial(stock, seed, itemMap, unitMap, vendorMap, materialMap);
  }
  for (const runSeed of seed.productionRuns || []) {
    await ensureFullSeedProductionRun(
      runSeed,
      seed,
      itemMap,
      unitMap,
      orderLineMap,
      pipelineRunMap,
      productionRunMap,
    );
  }
  for (const challan of seed.challans || []) {
    await ensureFullSeedChallan(
      challan,
      seed,
      clientMap,
      vendorMap,
      itemMap,
      unitMap,
      orderLineMap,
      productionRunMap,
      challanMap,
    );
  }
  await ensureFullSeedInventoryPositions(seed, unitMap, challanMap);
  console.log(
    `Loaded full Paper demo seed: ${(seed.units || []).length} units, ${(seed.clients || []).length} clients, ${(seed.items || []).length} items, ${(seed.orders || []).length} orders, ${(seed.productionRuns || []).length} production runs, ${(seed.challans || []).length} challans.`,
  );
}

async function backfillInventoryLedgerForMaterials({
  inferMissingPositions = false,
} = {}) {
  const materials = await all('SELECT * FROM materials');
  for (const material of materials) {
    const positionCountRow = await get(
      'SELECT COUNT(*) AS count FROM inventory_stock_positions WHERE material_barcode = ?',
      [material.barcode],
    );
    const hasPosition = Number(positionCountRow?.count || 0) > 0;
    // Never infer stock for a material that has no movements or stock positions.
    // Inventory must remain document/movement driven.
    if (!hasPosition && inferMissingPositions) {
      // Legacy flag retained for compatibility, but intentionally no-op now.
    }
    await inventoryPorts.ledger.recomputeSummary(material.barcode);
  }
}

// The one in kernel/schema-kit.js, bound to this file's database helpers; the
// modules' schema.js files use the same.
function ensureColumnExists(tableName, columnName, definition) {
  return require('./kernel/schema-kit').ensureColumnExists({ run, all }, tableName, columnName, definition);
}

async function ensureDeliveryChallanItemNumericColumns() {
  const columns = await all('PRAGMA table_info(delivery_challan_items)');
  if (!columns.length) {
    return;
  }

  const quantityColumn = columns.find((column) => column.name === 'quantity_pcs');
  const weightColumn = columns.find((column) => column.name === 'weight');
  const hasProductionRunId = columns.some((column) => column.name === 'production_run_id');
  const hasVariationLeafNodeId = columns.some((column) => column.name === 'variation_leaf_node_id');
  const hasVariationPathLabel = columns.some((column) => column.name === 'variation_path_label');
  const hasVariationPathNodeIdsJson = columns.some((column) => column.name === 'variation_path_node_ids_json');
  const hasNote = columns.some((column) => column.name === 'note');
  const hasCustomVariationValuesJson = columns.some((column) => column.name === 'custom_variation_values_json');
  const normalizedType = (column) => String(column?.type || '').trim().toUpperCase();
  if (normalizedType(quantityColumn) === 'REAL' && normalizedType(weightColumn) === 'REAL') {
    return;
  }

  console.log('Migrating delivery_challan_items: converting quantity_pcs and weight to REAL');
  await run('BEGIN TRANSACTION');
  try {
    await run('ALTER TABLE delivery_challan_items RENAME TO delivery_challan_items_legacy');
    await run(`
      CREATE TABLE delivery_challan_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
        order_item_id INTEGER,
        production_run_id INTEGER,
        item_id INTEGER,
        variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
        line_no INTEGER NOT NULL DEFAULT 1,
        particulars TEXT NOT NULL DEFAULT '',
        hsn_code TEXT DEFAULT '',
        variation_path_label TEXT DEFAULT '',
        variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
        note TEXT DEFAULT '',
        custom_variation_values_json TEXT DEFAULT '{}',
        quantity_pcs REAL NOT NULL DEFAULT 0,
        weight REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    `);
    await run(`
      INSERT INTO delivery_challan_items (
        id, challan_id, order_item_id, production_run_id, item_id, variation_leaf_node_id, line_no, particulars, hsn_code,
        variation_path_label, variation_path_node_ids_json, note, custom_variation_values_json, quantity_pcs, weight, created_at, updated_at
      )
      SELECT
        id,
        challan_id,
        order_item_id,
        ${hasProductionRunId ? 'production_run_id' : 'NULL'},
        item_id,
        ${hasVariationLeafNodeId ? 'variation_leaf_node_id' : '0'},
        line_no,
        particulars,
        hsn_code,
        ${hasVariationPathLabel ? 'variation_path_label' : "''"},
        ${hasVariationPathNodeIdsJson ? 'variation_path_node_ids_json' : "'[]'"},
        ${hasNote ? 'note' : "''"},
        ${hasCustomVariationValuesJson ? 'custom_variation_values_json' : "'{}'"},
        CASE
          WHEN TRIM(COALESCE(quantity_pcs, '')) = '' THEN 0
          ELSE CAST(quantity_pcs AS REAL)
        END,
        CASE
          WHEN TRIM(COALESCE(weight, '')) = '' THEN 0
          ELSE CAST(weight AS REAL)
        END,
        created_at,
        updated_at
      FROM delivery_challan_items_legacy
    `);
    await run('DROP TABLE delivery_challan_items_legacy');
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function backfillInventoryMovementQuantitySemantics() {
  const columns = await all('PRAGMA table_info(inventory_movements)');
  if (!columns.length) {
    return;
  }

  const hasPrimaryQty = columns.some((column) => column.name === 'primary_qty');
  const hasUom = columns.some((column) => column.name === 'uom');
  if (!hasPrimaryQty || !hasUom) {
    return;
  }

  await run(
    `
    UPDATE inventory_movements
    SET primary_qty = COALESCE(primary_qty, qty)
    WHERE primary_qty IS NULL
    `,
  );
  await run(
    `
    UPDATE inventory_movements
    SET uom = COALESCE(NULLIF(TRIM(uom), ''), 'units')
    WHERE uom IS NULL OR TRIM(uom) = ''
    `,
  );
}

async function ensureInventorySetLineNullableLeafReference() {
  const columns = await all('PRAGMA table_info(inventory_set_lines)');
  if (!columns.length) {
    return;
  }
  const leafColumn = columns.find((column) => column.name === 'variation_leaf_node_id');
  const isNotNull = Number(leafColumn?.notnull || 0) === 1;
  if (!isNotNull) {
    return;
  }

  console.log('Migrating inventory_set_lines: allowing NULL variation_leaf_node_id for base items');
  await run('BEGIN TRANSACTION');
  try {
    await run('ALTER TABLE inventory_set_lines RENAME TO inventory_set_lines_legacy');
    await run(`
      CREATE TABLE inventory_set_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        set_id INTEGER NOT NULL REFERENCES inventory_sets(id) ON DELETE CASCADE,
        item_id INTEGER NOT NULL REFERENCES items(id),
        variation_leaf_node_id INTEGER REFERENCES item_variation_nodes(id),
        quantity INTEGER NOT NULL DEFAULT 1,
        position INTEGER NOT NULL DEFAULT 0,
        UNIQUE(set_id, item_id, variation_leaf_node_id)
      )
    `);
    await run(`
      INSERT INTO inventory_set_lines (
        id, set_id, item_id, variation_leaf_node_id, quantity, position
      )
      SELECT
        id,
        set_id,
        item_id,
        CASE
          WHEN variation_leaf_node_id = 0 THEN NULL
          ELSE variation_leaf_node_id
        END,
        quantity,
        position
      FROM inventory_set_lines_legacy
    `);
    await run('DROP TABLE inventory_set_lines_legacy');
    await run(
      'CREATE INDEX IF NOT EXISTS idx_inventory_set_lines_set_id ON inventory_set_lines(set_id)',
    );
    await run(
      'CREATE INDEX IF NOT EXISTS idx_inventory_set_lines_item_id ON inventory_set_lines(item_id)',
    );
    await run(
      'CREATE INDEX IF NOT EXISTS idx_inventory_set_lines_item_lookup ON inventory_set_lines(item_id, variation_leaf_node_id)',
    );
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function migrateOrderActivityLogCompatibilityColumns() {
  const columns = await all('PRAGMA table_info(order_activity_log)');
  const hasColumn = (name) => columns.some((column) => column.name === name);

  if (hasColumn('event_type') && hasColumn('activity_type')) {
    await run(`
      UPDATE order_activity_log
      SET activity_type = event_type
      WHERE TRIM(COALESCE(activity_type, '')) = ''
        AND TRIM(COALESCE(event_type, '')) != ''
    `);
  }

  if (hasColumn('metadata_json') && hasColumn('details_json')) {
    await run(`
      UPDATE order_activity_log
      SET details_json = metadata_json
      WHERE TRIM(COALESCE(details_json, '')) = ''
        AND TRIM(COALESCE(metadata_json, '')) != ''
    `);
  }
}

async function seedMaterialsIfEmpty() {
  // Intentionally left empty. The semantic demo inventory dataset is seeded
  // later via ensureDemoMaterialsPresent() after groups/items are available.
}

async function bootstrapUnitsFromMaterials() {
  const countRow = await get('SELECT COUNT(*) AS count FROM units');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const materialRows = await all(
    'SELECT DISTINCT unit FROM materials WHERE TRIM(COALESCE(unit, \'\')) != \'\'',
  );
  const now = new Date().toISOString();
  const seen = new Set();
  for (const row of materialRows) {
    const value = String(row.unit || '').trim();
    const normalized = normalizeUnitValue(value);
    if (!normalized || seen.has(normalized)) {
      continue;
    }
    seen.add(normalized);
    await run(
      `
      INSERT INTO units (name, symbol, unit_group_id, conversion_factor, conversion_base_unit_id, notes, is_archived, created_at, updated_at)
      VALUES (?, ?, NULL, 1, NULL, '', 0, ?, ?)
      `,
      [value, value, now, now],
    );
  }
}

async function seedUnitsIfEmpty() {
  await seedStandardUnitFamilies({ run, get, all });
}

async function findUnitByNameSymbol(name, symbol) {
  const rows = await getUnitsWithUsage();
  const normalizedName = normalizeUnitValue(name);
  const normalizedSymbol = normalizeUnitValue(symbol);
  return rows.find(
    (row) =>
      normalizeUnitValue(row.name) === normalizedName &&
      normalizeUnitValue(row.symbol) === normalizedSymbol,
  ) || null;
}

async function ensureUnitRecord({
  name,
  symbol,
  notes = '',
  isArchived = false,
}) {
  let row = await findUnitByNameSymbol(name, symbol);
  if (!row) {
    row = await saveUnit({ name, symbol, notes });
  }

  await run(
    'UPDATE units SET notes = ?, is_archived = ?, updated_at = ? WHERE id = ?',
    [notes, isArchived ? 1 : 0, new Date().toISOString(), row.id],
  );
  return getUnitRowById(row.id);
}

async function ensureDemoUnitsPresent() {
  const units = [
    { name: 'Piece', symbol: 'Pc', notes: 'Discrete finished goods and components.' },
    { name: 'Box', symbol: 'Box', notes: 'Packed kits and shipping cartons.' },
    { name: 'Carton', symbol: 'Ctn', notes: 'Shipping cartons.' },
    { name: 'Meter', symbol: 'm', notes: 'Length measurement.' },
    { name: 'Liter', symbol: 'L', notes: 'Volume measurement.' },
    { name: 'Kilogram', symbol: 'kg', notes: 'Weight measurement.' },
    { name: 'Gram', symbol: 'g', notes: 'Small weight measurement.' },
    { name: 'Archived Unit', symbol: 'Arc', notes: 'Archived test unit.', isArchived: true }
  ];

  for (const unit of units) {
    const createdUnit = await ensureUnitRecord(unit);
    if (unit.isArchived) {
      await run('UPDATE units SET is_archived = 1 WHERE id = ?', [createdUnit.id]);
    }
  }
}

async function backfillMaterialUnitIds() {
  const unitRows = await all('SELECT id, symbol FROM units');
  const unitMap = new Map();
  for (const row of unitRows) {
    const normalized = normalizeUnitValue(row.symbol);
    if (!normalized) {
      continue;
    }
    if (!unitMap.has(normalized)) {
      unitMap.set(normalized, []);
    }
    unitMap.get(normalized).push(row.id);
  }

  const materialRows = await all(
    'SELECT id, unit, unit_id FROM materials WHERE unit_id IS NULL AND TRIM(COALESCE(unit, \'\')) != \'\'',
  );
  for (const row of materialRows) {
    const matches = unitMap.get(normalizeUnitValue(row.unit)) || [];
    if (matches.length === 1) {
      await run('UPDATE materials SET unit_id = ? WHERE id = ?', [matches[0], row.id]);
    }
  }
}

async function seedMachinesAndDiesIfEmpty() {
  const machineCount = await get('SELECT COUNT(*) as count FROM machines');
  if (machineCount.count === 0) {
    await run(`
      INSERT INTO machines (name, asset_id, primary_photo_url, group_id, make_model, serial_number, location, installation_date, status, custom_properties, created_at, updated_at)
      VALUES (
        'Amada CNC Press Brake',
        'MAC-1001',
        'https://images.unsplash.com/photo-1565439390237-db561c2ba24e?auto=format&fit=crop&q=80',
        NULL,
        'Amada HDS-8025NT',
        'AMD-909283',
        'Press Shop A',
        '2022-05-10',
        'active',
        '[{"key": "Tonnage", "value": "80T"}, {"key": "Bed Length", "value": "2500mm"}]',
        datetime('now'),
        datetime('now')
      )
    `);
    await run(`
      INSERT INTO machines (name, asset_id, primary_photo_url, group_id, make_model, serial_number, location, installation_date, status, custom_properties, created_at, updated_at)
      VALUES (
        'Haas VF-2SS CNC Mill',
        'MAC-1002',
        'https://images.unsplash.com/photo-1610484557978-56961cf3d623?auto=format&fit=crop&q=80',
        NULL,
        'Haas VF-2SS',
        'HSS-10020',
        'CNC Line 2',
        '2023-01-15',
        'maintenance',
        '[{"key": "Spindle Speed", "value": "12000 RPM"}, {"key": "Axis", "value": "3-Axis"}]',
        datetime('now'),
        datetime('now')
      )
    `);
  }

  const dieCount = await get('SELECT COUNT(*) as count FROM dies');
  if (dieCount.count === 0) {
    await run(`
      INSERT INTO dies (tool_code, produced_part_numbers, photo_urls, operational_notes, compatible_machine_group_ids, storage_location, number_of_cavities, stroke_count, max_strokes, physical_specs, status, ownership, created_at, updated_at)
      VALUES (
        'TL-890-A',
        '["PART-4432", "PART-4433"]',
        '["https://images.unsplash.com/photo-1590494165264-1ebe3602eb80?auto=format&fit=crop&q=80", "https://images.unsplash.com/photo-1504917595217-d4dc5ebe6122?auto=format&fit=crop&q=80"]',
        'Requires heavy lubrication on the guide pins. Watch out for scrap buildup on the left exit chute.',
        '[]',
        'Rack B, Shelf 3',
        2,
        45000,
        100000,
        '{"Weight": "1250 kg", "Shut Height": "350 mm", "Dimensions": "800 x 600 x 400 mm"}',
        'ready',
        'inHouse',
        datetime('now'),
        datetime('now')
      )
    `);
    await run(`
      INSERT INTO dies (tool_code, produced_part_numbers, photo_urls, operational_notes, compatible_machine_group_ids, storage_location, number_of_cavities, stroke_count, max_strokes, physical_specs, status, ownership, created_at, updated_at)
      VALUES (
        'TL-102-B',
        '["PART-9901"]',
        '["https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?auto=format&fit=crop&q=80"]',
        'Customer owned. Handle with care. Clean thoroughly before returning to storage.',
        '[]',
        'Rack A, Shelf 1',
        1,
        98000,
        100000,
        '{"Weight": "2100 kg"}',
        'needsRepair',
        'customerOwned',
        datetime('now'),
        datetime('now')
      )
    `);
  }
}

async function seedTemplatesIfEmpty() {
  const templates = buildSeedTemplates();
  const insertSeedTemplate = async (template) => {
    const now = new Date().toISOString();
    await run(
      `
      INSERT INTO pipeline_templates (
        id, factory_id, shop_floor_id, name, description, version, status,
        stage_labels_json, lane_labels_json, nodes_json, flows_json,
        intermediate_naming_convention, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        template.id,
        template.factoryId || '',
        template.shopFloorId || '',
        template.name,
        template.description,
        template.version,
        template.status,
        JSON.stringify(template.stageLabels),
        JSON.stringify(template.laneLabels),
        JSON.stringify(template.nodes),
        JSON.stringify(template.flows),
        template.intermediateNamingConvention || '',
        now,
        now,
      ],
    );
  };

  const countRow = await get('SELECT COUNT(*) AS count FROM pipeline_templates');
  if ((countRow?.count || 0) > 0) {
    const sheetMetalTemplate = templates.find((template) => template.id === 'sheet-metal-flow');
    const existingSheetMetal = await get(
      'SELECT id FROM pipeline_templates WHERE id = ?',
      [sheetMetalTemplate.id],
    );
    if (!existingSheetMetal) {
      await insertSeedTemplate(sheetMetalTemplate);
    }
    return;
  }

  for (const template of templates) {
    await insertSeedTemplate(template);
  }
}

async function resolveUnitPayload(payload) {
  if (!payload.unitId) {
    return {
      unitId: null,
      unit: String(payload.unit || '').trim(),
    };
  }

  const unitRow = await get('SELECT * FROM units WHERE id = ?', [payload.unitId]);
  if (!unitRow) {
    throw new Error('Selected unit does not exist.');
  }

  return {
    unitId: unitRow.id,
    unit: unitRow.symbol || '',
  };
}

async function getItemVariationRows(itemId) {
  return all(
    `
    SELECT *
    FROM item_variations
    WHERE item_id = ?
    ORDER BY is_archived ASC, LOWER(display_name) ASC
    `,
    [itemId],
  );
}

/// Gives an item with no variations the stock figure it could not hold before.
/// Its materials already carry stock; the item's own row is made equal to what
/// they hold, per location. Runs at every boot and writes only when the item
/// has no whole-item row yet, so it does its work once.
async function backfillWholeItemStock() {
  const rows = await all(
    `SELECT m.linked_item_id AS item_id,
            COALESCE(NULLIF(TRIM(m.location), ''), 'MAIN') AS location_id,
            SUM(m.on_hand_qty) AS quantity
       FROM materials m
      WHERE m.linked_item_id IS NOT NULL
        AND COALESCE(m.linked_variation_leaf_node_id, 0) = 0
        AND COALESCE(m.on_hand_qty, 0) > 0
        AND COALESCE(m.inventory_state, '') != 'cancelled'
        AND NOT EXISTS (
          SELECT 1 FROM variation_stock v
           WHERE v.item_id = m.linked_item_id AND v.variation_leaf_node_id = 0)
      GROUP BY 1, 2`,
  );
  const now = new Date().toISOString();
  for (const row of rows) {
    if (!(await itemHoldsWholeItemStock(row.item_id))) continue;
    await run(
      `INSERT OR IGNORE INTO variation_stock (
         item_id, variation_leaf_node_id, quantity, location_id,
         variation_path_label, variation_path_node_ids_json, custom_variation_values_json, updated_at
       ) VALUES (?, 0, ?, ?, '', '[]', '{}', ?)`,
      [row.item_id, Number(row.quantity || 0), row.location_id, now],
    );
  }
  return rows.length;
}

async function getItemVariationDimensions(itemId) {
  return all(
    `
    SELECT *
    FROM item_variation_dimensions
    WHERE item_id = ?
    ORDER BY position ASC, LOWER(name) ASC
    `,
    [itemId],
  );
}

async function getVariationValues(variationId) {
  const rows = await all(
    `
    SELECT
      item_variation_values.dimension_id,
      item_variation_dimensions.name AS dimension_name,
      item_variation_values.value
    FROM item_variation_values
    JOIN item_variation_dimensions
      ON item_variation_dimensions.id = item_variation_values.dimension_id
    WHERE item_variation_values.variation_id = ?
    ORDER BY item_variation_dimensions.position ASC
    `,
    [variationId],
  );
  return rows.map((row) => ({
    dimensionId: row.dimension_id,
    dimensionName: row.dimension_name || '',
    value: row.value || '',
  }));
}

async function seedClientsIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM clients');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  await saveClient({
    name: 'Acme Packaging Pvt. Ltd.',
    alias: 'Acme',
    gstNumber: '27ABCDE1234F1Z5',
    address: 'MIDC Industrial Area, Pune, Maharashtra 411019',
  });
  await saveClient({
    name: 'Sunrise Retail LLP',
    alias: 'Sunrise',
    gstNumber: '24AAKCS9988M1Z2',
    address: 'Satellite Road, Ahmedabad, Gujarat 380015',
  });
  const archived = await saveClient({
    name: 'Legacy Trading Co.',
    alias: 'Legacy',
    address: 'Old Market Road, Indore, Madhya Pradesh 452001',
  });
  await run('UPDATE clients SET is_archived = 1, updated_at = ? WHERE id = ?', [
    new Date().toISOString(),
    archived.id,
  ]);
}

async function ensureClientRecord({
  name,
  alias = '',
  gstNumber = '',
  address = '',
  isArchived = false,
}) {
  const duplicate = await findClientDuplicate({ name, gstNumber });
  const client = duplicate || await saveClient({ name, alias, gstNumber, address });
  await run(
    `
    UPDATE clients
    SET name = ?, alias = ?, gst_number = ?, address = ?, is_archived = ?, updated_at = ?
    WHERE id = ?
    `,
    [name, alias, normalizeGstNumber(gstNumber), address, isArchived ? 1 : 0, new Date().toISOString(), client.id],
  );
  return getClientRowById(client.id);
}

async function ensureDemoClientsPresent() {
  const clients = [
    {
      name: 'Acme Packaging Pvt. Ltd.',
      alias: 'ACME',
      gstNumber: '27ABCDE1234F1Z5',
      address: 'MIDC Industrial Area, Pune, Maharashtra 411019',
    },
    {
      name: 'Sunrise Retail LLP',
      alias: 'SUN',
      gstNumber: '24AAKCS9988M1Z2',
      address: 'Satellite Road, Ahmedabad, Gujarat 380015',
    },
    {
      name: 'Northstar Pharma Packs',
      alias: 'NSP',
      gstNumber: '29AAACN4455J1Z7',
      address: 'Peenya Phase II, Bengaluru, Karnataka 560058',
    },
    {
      name: 'Orbit Consumer Goods',
      alias: 'ORB',
      gstNumber: '07AACCO7788L1Z1',
      address: 'Okhla Industrial Estate, New Delhi 110020',
    },
    {
      name: 'BluePeak Exports',
      alias: 'BPE',
      gstNumber: '19AAICB5634P1ZV',
      address: 'Salt Lake Sector V, Kolkata, West Bengal 700091',
    },
    {
      name: 'Legacy Trading Co.',
      alias: 'LEG',
      address: 'Old Market Road, Indore, Madhya Pradesh 452001',
      isArchived: true,
    },
  ];

  for (const client of clients) {
    await ensureClientRecord(client);
  }
}

// The vendor master left for modules/vendors; its delivery_challans reads go
// through the challans port. Destructured under the old names because challan,
// seed and test code still call them directly.
const challansPorts = createChallansPorts({
  get,
  all,
  // The challans service is built further down, so it is looked up when used.
  service: lateBound(() => challansService),
});
const vendorsService = createVendorService({
  get,
  all,
  run,
  logChange,
  challans: challansClient(desk.as('vendors')),
});
const {
  getVendorRowById,
  getVendorsWithUsage,
  findVendorDuplicate,
  saveVendor,
} = vendorsService;
// The client master left for modules/clients. Its usage counts and the identity
// lock read order_items, so they come through the orders port. Callers that
// still live here (orders, invoices, seeds, tests) get the functions under the
// names they know.
// The orders service (lines, the save, lifecycle, activity, PO documents) lives
// in modules/orders. It is built here, before the clients service, because the
// orders port hands saveOrder to the B2B portal at load. The client lookup it
// needs is defined just below, so it is reached through a function.
const ordersService = createOrdersService({
  runStatusSql: orderItemRunStatusSql,
  get,
  all,
  run,
  parseJson,
  resolveOrderVariationSelection: (selection) => itemsForOrders.resolveSelection(selection),
  desk: desk.as('orders'),
  normalizeUploadType,
  buildS3ObjectKey,
  presignS3Url,
  assertS3ObjectExists,
});
// Seeds, the challan and production code still in this file, the routes and the
// tests call these under the names they always had.
const {
  rowToOrderDto,
  rowToPoDocumentDto,
  cleanupStaleUnlinkedPoDocuments,
  getOrderRowById,
  getOrders,
  countOrders,
  createPoUploadIntent,
  completePoUpload,
  linkPoDocumentsToOrder,
  getPoDocumentsForOrder,
  createPoDocumentReadUrl,
  saveOrder,
  updateOrderLifecycle,
  getOrderActivity,
  getOrderStatusHistory,
} = ordersService;
const ordersPorts = createOrdersPorts({ get, all, run, saveOrder, desk: desk.as('orders') });
const clientsService = createClientService({ get, all, run, logChange, desk: desk.as('clients') });
const {
  rowToClientDto,
  getClientRowById,
  getClientsWithUsage,
  findClientDuplicate,
  saveClient,
} = clientsService;
// What names a party on delete: challans for a vendor; order lines and parts for
// a client. Each is asked at the kernel desk.
const partyDeleteBlockers = createPartyDeleteBlockers({
  get,
  challans: challansClient(desk.as('parties')),
  desk: desk.as('parties'),
  items: itemsClient(desk.as('parties')),
});

const DEFAULT_COMPANY_PROFILE = Object.freeze({
  companyName: 'Shree Ganesh Metal Works',
  mobile: '9324041030',
  businessDescription: 'Manufacturers of: FOUNTAIN PEN, BALL PEN & PEN PARTS',
  address:
    'Gala No. 1 Ground Floor, Vasundhara Udyog Bhavan, Behind KT Phase No. 1 Industrial Estate, Gaurai Pada, Vasai (East), Dist. Palghar - 401 208.',
  stateCode: '27',
  gstin: '27ABHPC1349L1ZN',
  logoUrl: '',
  signatureLabel: '',
});

async function seedCompanyProfileIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM company_profiles');
  if ((countRow?.count || 0) > 0) {
    return;
  }
  await saveCompanyProfile(DEFAULT_COMPANY_PROFILE);
}

function rowToCompanyProfileDto(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    company_name: row.company_name || '',
    mobile: row.mobile || '',
    business_description: row.business_description || '',
    address: row.address || '',
    state_code: row.state_code || '',
    gstin: row.gstin || '',
    logo_url: row.logo_url || '',
    signature_label: row.signature_label || '',
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
  };
}

async function getActiveCompanyProfile() {
  let row = await get(
    'SELECT * FROM company_profiles WHERE is_active = 1 ORDER BY id ASC LIMIT 1',
  );
  if (!row) {
    await seedCompanyProfileIfEmpty();
    row = await get(
      'SELECT * FROM company_profiles WHERE is_active = 1 ORDER BY id ASC LIMIT 1',
    );
  }
  return row;
}

async function saveCompanyProfile(input = {}) {
  const companyName = String(input.companyName ?? input.company_name ?? '').trim();
  if (!companyName) {
    const error = new Error('Company name is required.');
    error.statusCode = 400;
    throw error;
  }
  const mobile = String(input.mobile ?? '').trim();
  const businessDescription = String(
    input.businessDescription ?? input.business_description ?? '',
  ).trim();
  const address = String(input.address ?? '').trim();
  const stateCode = String(input.stateCode ?? input.state_code ?? '').trim();
  const gstin = String(input.gstin ?? '').trim();
  const logoUrl = String(input.logoUrl ?? input.logo_url ?? input.logoPath ?? input.logo_path ?? '').trim();
  const signatureLabel = String(
    input.signatureLabel ??
      input.signature_label ??
      input.authorizedSignatoryName ??
      input.authorized_signatory_name ??
      '',
  ).trim();
  const now = new Date().toISOString();
  const existing = await get(
    'SELECT * FROM company_profiles WHERE is_active = 1 ORDER BY id ASC LIMIT 1',
  );

  if (existing) {
    await run(
      `
      UPDATE company_profiles
      SET company_name = ?, mobile = ?, business_description = ?, address = ?,
          state_code = ?, gstin = ?, logo_url = ?, signature_label = ?, updated_at = ?
      WHERE id = ?
      `,
      [
        companyName,
        mobile,
        businessDescription,
        address,
        stateCode,
        gstin,
        logoUrl,
        signatureLabel,
        now,
        existing.id,
      ],
    );
    return get('SELECT * FROM company_profiles WHERE id = ?', [existing.id]);
  }

  const result = await run(
    `
    INSERT INTO company_profiles (
      company_name, mobile, business_description, address, state_code, gstin,
      logo_url, signature_label, is_active, created_at, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
    `,
    [
      companyName,
      mobile,
      businessDescription,
      address,
      stateCode,
      gstin,
      logoUrl,
      signatureLabel,
      now,
      now,
    ],
  );
  return get('SELECT * FROM company_profiles WHERE id = ?', [result.lastID]);
}

// 'internal' documents assets moving within the company (production
// consumption, transfers) — it needs neither a customer nor a vendor.
const CHALLAN_TYPES = new Set(['delivery', 'reception', 'internal']);

function parseJsonObject(value, fallback = null) {
  if (!value) {
    return fallback;
  }
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed
      : fallback;
  } catch (_) {
    return fallback;
  }
}

function normalizeChallanType(value, fallback = 'delivery') {
  const normalized = String(value || fallback).trim().toLowerCase();
  return CHALLAN_TYPES.has(normalized) ? normalized : fallback;
}

// Challan templates (the scanned form, its mapped boxes, the PDF) live in
// modules/challans/templates.js. The challan readers they print from are still
// defined in this file and are handed in by name.
const challanTemplateService = createChallanTemplateService({
  desk: desk.as('challans'),
  get,
  all,
  run,
  parseBooleanEnv,
  S3_UPLOAD_PREFIXES,
  normalizeChallanType,
  getDeliveryChallanOrderIds: (...args) => getDeliveryChallanOrderIds(...args),
  getOrderRowsByIds: (...args) => getOrderRowsByIds(...args),
  rowToDeliveryChallanDto: (...args) => rowToDeliveryChallanDto(...args),
  normalizeUploadType,
  getS3Prefix,
  buildS3ObjectKey,
  presignS3Url,
  assertS3ObjectExists,
  readS3ObjectBuffer,
  assetReadUrlPayload,
});
const {
  listChallanTemplates,
  saveChallanTemplate,
  deleteChallanTemplate,
  findActiveChallanTemplateForChallan,
  buildChallanTemplateSnapshot,
  buildTemplateTestChallanDto,
  generateChallanTemplatePdf,
  createChallanTemplateUploadIntent,
  completeChallanTemplateUpload,
} = challanTemplateService;
async function ensureDemoProductionRunsPresent() {
  const existing = await get('SELECT COUNT(*) AS count FROM production_runs');
  if (Number(existing?.count || 0) > 0) {
    return;
  }
  const orders = await getOrders();
  const seeds = orders
    .filter((order) => Number(order.item_id || 0) > 0)
    .slice(0, 6);
  if (seeds.length === 0) {
    return;
  }
  const now = new Date().toISOString();
  for (let index = 0; index < seeds.length; index += 1) {
    const order = seeds[index];
    await run(
      `
      INSERT INTO production_runs (
        run_code, status, completed_at, item_id, variation_leaf_node_id,
        variation_path_label, output_quantity, uom, location,
        source_metadata_json, created_at, updated_at
      ) VALUES (?, 'completed', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        `RUN-${String(index + 1).padStart(4, '0')}`,
        now,
        Number(order.item_id || 0),
        Number(order.variation_leaf_node_id || 0),
        String(order.variation_path_label || ''),
        Math.max(Number(order.quantity || 0), 1),
        'pcs',
        'Production Output',
        JSON.stringify({
          orderId: order.id,
          orderNo: order.order_no,
        }),
        now,
        now,
      ],
    );
  }
}

/// Creates the barcoded stock row a reception challan line brings into being.
///
/// Returns the barcode, or null when there is nothing to mint (a line with no
/// item, or a quantity of zero). The barcode is derived from the challan and
/// line so it is readable on a shop floor and stable for a given line, with a
/// numeric suffix only if that name is somehow already taken.
// Invoices live in modules/challans/invoices.js. The challan readers its PDF
// quotes from are still defined in this file and are handed in by name.
const invoiceService = createInvoiceService({
  get,
  all,
  run,
  desk: desk.as('challans'),
  rowToCompanyProfileDto,
  getActiveCompanyProfile,
  rowToDeliveryChallanDto: (...args) => rowToDeliveryChallanDto(...args),
  normalizeChallanDate: (...args) => normalizeChallanDate(...args),
  getDeliveryChallanRowById: (...args) => getDeliveryChallanRowById(...args),
});
const {
  listInvoices,
  getInvoiceDtoById,
  normalizePositiveNumber,
  createInvoice,
  generateInvoicePdf,
} = invoiceService;
// Challan reports (reconciliation, conversion overrides, waste audit, client
// statement, one order's reconciliation) live in modules/challans/reports.js.
const challanReportService = createChallanReportService({
  get,
  all,
  run,
  normalizeChallanType,
  normalizeReportGroupCode: (...args) => normalizeReportGroupCode(...args),
  effectiveReportGroupCodesForChallan: (...args) => effectiveReportGroupCodesForChallan(...args),
  listInvoices,
  normalizePositiveNumber,
  desk: desk.as('challans'),
});
const {
  listConversionOverrides,
  saveConversionOverride,
  listWasteAuditRows,
  buildReconciliationReport,
  buildClientStatementReport,
} = challanReportService;

const ALLOWED_ASSET_CONTENT_TYPES = new Set([
  'image/png',
  'image/jpeg',
  'image/webp',
]);

function normalizeUploadType(uploadType) {
  return String(uploadType || '').trim().toUpperCase();
}

function getS3Prefix(uploadType) {
  const normalizedUploadType = normalizeUploadType(uploadType);
  const prefix = S3_UPLOAD_PREFIXES[normalizedUploadType];
  if (!prefix) {
    const error = new Error('Unsupported upload type.');
    error.statusCode = 400;
    throw error;
  }
  return prefix;
}

function buildS3ObjectKey({
  uploadType,
  fileName,
  sha256,
  entityType = '',
  entityId = null,
}) {
  const prefix = getS3Prefix(uploadType);
  const uniqueStem = `${Date.now()}-${String(sha256 || '').slice(0, 12)}`;
  if (normalizeUploadType(uploadType) === 'ITEM_IMAGE') {
    return `${prefix}${entityType}-${entityId}/${uniqueStem}-${fileName}`;
  }
  return `${prefix}${uniqueStem}-${fileName}`;
}

function normalizeAssetFileName(fileName) {
  const baseName = path.basename(String(fileName || '').trim());
  return baseName
    .replace(/[^\w.\- ()]/g, '_')
    .replace(/_+/g, '_')
    .slice(0, 160) || 'asset-image';
}

function assertValidAssetUploadInput({
  uploadType,
  entityType,
  entityId,
  fileName,
  contentType,
  sizeBytes,
  sha256,
  isPrimary,
  documentTitle,
  thumbnail,
  width,
  height,
}) {
  if (documentTitle !== undefined && documentTitle !== null) {
    return assertValidDocumentUploadInput({
      entityType, entityId, fileName, contentType, sizeBytes, sha256, documentTitle,
    });
  }
  const normalizedEntityType = String(entityType || '').trim().toLowerCase();
  const normalizedEntityId = Number(entityId || 0);
  const normalizedUploadType = normalizeUploadType(uploadType);
  const normalizedContentType = String(contentType || '').toLowerCase().trim();
  const normalizedSize = Number(sizeBytes || 0);
  const normalizedSha = String(sha256 || '').toLowerCase().trim();
  const normalizedName = normalizeAssetFileName(fileName);

  const validUploadTypes = new Set([
    'ITEM_IMAGE',
    'MACHINE_IMAGE',
    'DIE_IMAGE',
    'PARTY_IMAGE',
    // A challan's photos (gate pass, signed copy). The dedicated challan upload
    // routes, the storage prefix, the owner check and the permission map all
    // knew about challans already; this list did not, so the upload could
    // never start.
    'DELIVERY_CHALLAN',
  ]);
  // A company's logo and a person's photo live in the same store as a part's,
  // so all of them are kept as object keys and signed when read — not as a
  // presigned URL saved on the record, which stops working in days.
  const validEntityTypes = new Set([
    'item',
    'machine',
    'die',
    'client',
    'party_contact',
    'delivery_challan',
  ]);

  if (!validUploadTypes.has(normalizedUploadType)) {
    const error = new Error('Invalid uploadType.');
    error.statusCode = 400;
    throw error;
  }
  if (!validEntityTypes.has(normalizedEntityType)) {
    const error = new Error('Entity type not supported.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isInteger(normalizedEntityId) || normalizedEntityId <= 0) {
    const error = new Error('A valid entity id is required.');
    error.statusCode = 400;
    throw error;
  }
  if (!ALLOWED_ASSET_CONTENT_TYPES.has(normalizedContentType)) {
    const error = new Error('Only PNG, JPG, JPEG, and WEBP images are allowed.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isFinite(normalizedSize) || normalizedSize <= 0) {
    const error = new Error('File size must be greater than zero.');
    error.statusCode = 400;
    throw error;
  }
  if (normalizedSize > 10 * 1024 * 1024) {
    const error = new Error('Item images must be 10 MB or smaller.');
    error.statusCode = 400;
    throw error;
  }
  if (!/^[a-f0-9]{64}$/.test(normalizedSha)) {
    const error = new Error('A valid SHA-256 file hash is required.');
    error.statusCode = 400;
    throw error;
  }

  return {
    uploadType: normalizedUploadType,
    entityType: normalizedEntityType,
    entityId: normalizedEntityId,
    fileName: normalizedName,
    contentType: normalizedContentType,
    sizeBytes: Math.round(normalizedSize),
    sha256: normalizedSha,
    isPrimary: Boolean(isPrimary),
    documentTitle: null,
    thumbnail: normalizeThumbnailInput(thumbnail),
    width: normalizePixels(width),
    height: normalizePixels(height),
  };
}

/// The small copy a client made of the photo, for lists and grids: a JPEG of
/// a few KB beside the photo. Absent from older clients, which upload the
/// photo alone.
function normalizeThumbnailInput(thumbnail) {
  if (thumbnail === undefined || thumbnail === null) return null;
  const sizeBytes = Number(thumbnail.sizeBytes || 0);
  const sha = String(thumbnail.sha256 || '').toLowerCase().trim();
  if (!Number.isFinite(sizeBytes) || sizeBytes <= 0 || sizeBytes > MAX_THUMBNAIL_BYTES) {
    const error = new Error('A thumbnail must be between 1 byte and 1 MB.');
    error.statusCode = 400;
    throw error;
  }
  if (!/^[a-f0-9]{64}$/.test(sha)) {
    const error = new Error('A valid SHA-256 thumbnail hash is required.');
    error.statusCode = 400;
    throw error;
  }
  return { sizeBytes: Math.round(sizeBytes), sha256: sha };
}

function normalizePixels(value) {
  const pixels = Number(value);
  return Number.isInteger(pixels) && pixels > 0 && pixels <= 100000 ? pixels : null;
}

const MAX_THUMBNAIL_BYTES = 1024 * 1024;

/// How many photos a part keeps: its views — front, side, a section, a
/// detail. The server holds the line, so no client can go past it.
const MAX_PART_PHOTOS = 5;

/// Photo objects never change (their keys carry the upload's time and hash),
/// so whatever fetched one may keep it.
const IMMUTABLE_CACHE_CONTROL = 'private, max-age=31536000, immutable';

/// The thumbnail's key, beside its photo: `items/item-7/1730-ab12…-patti.jpg`
/// → `items/item-7/thumbs/1730-ab12…-patti.jpg`.
function thumbnailKeyFor(objectKey) {
  const key = String(objectKey || '');
  const slash = key.lastIndexOf('/');
  const stem = key.slice(slash + 1).replace(/\.[^.]*$/, '');
  return `${key.slice(0, slash + 1)}thumbs/${stem}.jpg`;
}

/// The records that keep a gallery of photos, each up to [MAX_PART_PHOTOS]:
/// a part's views, and a die's (2026-11-24). Others keep one shown photo.
const GALLERY_ENTITY_TYPES = new Set(['item', 'die', 'machine']);

function photoLimitError(entityType = 'item') {
  const what = entityType === 'die' ? 'A die' : entityType === 'machine' ? 'A machine' : 'A part';
  const error = new Error(`${what} keeps up to ${MAX_PART_PHOTOS} photos — remove one first.`);
  error.statusCode = 409;
  error.code = 'photo_limit';
  return error;
}

async function countEntityPhotos(entityType, entityId) {
  const row = await get(
    `
    SELECT COUNT(*) AS count
    FROM uploaded_assets
    WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded'
      AND document_title IS NULL
    `,
    [entityType, Number(entityId)],
  );
  return Number(row?.count || 0);
}

/// Refuses a photo past a gallery's limit (a part's, a die's). Other
/// records keep one shown photo and are not counted.
async function assertRoomForPhoto(entityType, entityId) {
  if (!GALLERY_ENTITY_TYPES.has(entityType)) return;
  if ((await countEntityPhotos(entityType, entityId)) >= MAX_PART_PHOTOS) {
    throw photoLimitError(entityType);
  }
}

const DOCUMENT_ENTITY_TYPES = new Set(['client', 'sub_contractor']);
const MAX_DOCUMENT_BYTES = 25 * 1024 * 1024;
const MAX_DOCUMENT_TITLE = 120;

function normalizeDocumentTitle(value) {
  const title = String(value ?? '').replace(/\s+/g, ' ').trim();
  if (!title) {
    const error = new Error('Give the document a name.');
    error.statusCode = 400;
    throw error;
  }
  if (title.length > MAX_DOCUMENT_TITLE) {
    const error = new Error(`A document name is at most ${MAX_DOCUMENT_TITLE} characters.`);
    error.statusCode = 400;
    throw error;
  }
  return title;
}

/// A company's document: any kind of file, under a name the user gave it
/// (uploaded_assets.document_title). Never primary — it is not the company's picture.
function assertValidDocumentUploadInput({
  entityType,
  entityId,
  fileName,
  contentType,
  sizeBytes,
  sha256,
  documentTitle,
}) {
  const normalizedEntityType = String(entityType || '').trim().toLowerCase();
  const normalizedEntityId = Number(entityId || 0);
  const normalizedSize = Number(sizeBytes || 0);
  const normalizedSha = String(sha256 || '').toLowerCase().trim();
  // Whatever the file says it is; a missing type is stored as bytes.
  const normalizedContentType =
    String(contentType || '').toLowerCase().split(';')[0].trim() || 'application/octet-stream';

  if (!DOCUMENT_ENTITY_TYPES.has(normalizedEntityType)) {
    const error = new Error('Documents are kept for a client or a contractor.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isInteger(normalizedEntityId) || normalizedEntityId <= 0) {
    const error = new Error('A valid entity id is required.');
    error.statusCode = 400;
    throw error;
  }
  if (!/^[\w.+-]+\/[\w.+-]+$/.test(normalizedContentType)) {
    const error = new Error('The file type is not readable.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isFinite(normalizedSize) || normalizedSize <= 0) {
    const error = new Error('File size must be greater than zero.');
    error.statusCode = 400;
    throw error;
  }
  if (normalizedSize > MAX_DOCUMENT_BYTES) {
    const error = new Error('A document must be 25 MB or smaller.');
    error.statusCode = 400;
    throw error;
  }
  if (!/^[a-f0-9]{64}$/.test(normalizedSha)) {
    const error = new Error('A valid SHA-256 file hash is required.');
    error.statusCode = 400;
    throw error;
  }

  return {
    uploadType: 'PARTY_DOCUMENT',
    entityType: normalizedEntityType,
    entityId: normalizedEntityId,
    fileName: normalizeAssetFileName(fileName || 'document'),
    contentType: normalizedContentType,
    sizeBytes: Math.round(normalizedSize),
    sha256: normalizedSha,
    isPrimary: false,
    documentTitle: normalizeDocumentTitle(documentTitle),
  };
}

function getS3Config() {
  const endpoint = String(process.env.S3_ENDPOINT || '').trim().replace(/\/+$/, '');
  return {
    endpoint,
    region:
      String(process.env.PAPER_S3_REGION || process.env.S3_REGION || 'us-east-1').trim() ||
      'us-east-1',
    bucket: String(
      process.env.PAPER_S3_BUCKET_NAME || process.env.S3_BUCKET || '',
    ).trim(),
    forcePathStyle: parseBooleanEnv(
      process.env.S3_FORCE_PATH_STYLE,
      Boolean(endpoint),
    ),
  };
}

// --- local disk, when no S3 bucket is configured ---------------------------
//
// Uploads were S3-only: with no PAPER_S3_BUCKET_NAME every upload answered
// 503, so a workspace without a bucket could hold no photo at all. Without
// one, the same presign / verify / read calls are served from a folder on
// this machine. The URLs are signed (HMAC over method, key and expiry) so an
// <img> can load them without a login, exactly as it loads an S3 one.

const requestOrigin = new (require('node:async_hooks').AsyncLocalStorage)();

const LOCAL_UPLOAD_ROOT = path.resolve(
  process.env.PAPER_UPLOAD_DIR || path.join(__dirname, 'uploads'),
);

function usesLocalUploads() {
  return !getS3Config().bucket;
}

function localUploadBaseUrl() {
  const configured = String(process.env.PAPER_PUBLIC_URL || '').trim();
  return (configured || requestOrigin.getStore() || `http://localhost:${PORT}`)
    .replace(/\/+$/, '');
}

// --- permanent photo links ----------------------------------------------------
//
// A record's photo field (an item's photo, a client's logo, a machine's or a
// die's photo) held a presigned read URL, which stops working in minutes or
// days — so stored photos went blank on their own. It holds this instead: a
// link signed once for the object, never expiring, that answers with a fresh
// short-lived read URL each time it is opened. Every screen that shows the
// field keeps working unchanged.

function assetViewSignature(objectKey) {
  return crypto
    .createHmac('sha256', JWT_SECRET)
    .update(`asset-view\n${objectKey}`)
    .digest('hex');
}

function encodeObjectKey(objectKey) {
  return String(objectKey)
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
}

function assetViewUrl(objectKey) {
  if (!objectKey) return null;
  return `${localUploadBaseUrl()}/api/assets/view/${encodeObjectKey(objectKey)}?sig=${assetViewSignature(objectKey)}`;
}

function isAssetViewUrlFor(value, objectKey) {
  return (
    typeof value === 'string' &&
    value.includes(`/api/assets/view/${encodeObjectKey(objectKey)}?`)
  );
}

function isAssetViewUrl(value) {
  return typeof value === 'string' && value.includes('/api/assets/view/');
}

/**
 * Puts a record's primary photo onto the record's own photo field, so screens
 * that read the field (lists, cards, the item join) show what was uploaded.
 * [removedKey] is a photo just deleted, taken off the field. Never throws: a
 * stored photo is not undone by its record failing to note it.
 */
async function syncRecordPhotoField(entityType, entityId, removedKey = null) {
  try {
    const primary = await get(
      `
      SELECT object_key FROM uploaded_assets
      WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded' AND is_primary = 1
      ORDER BY id DESC LIMIT 1
      `,
      [entityType, Number(entityId)],
    );
    const url = primary ? assetViewUrl(primary.object_key) : null;
    const single = {
      item: ['items', 'photo_url'],
      client: ['clients', 'logo_url'],
      machine: ['machines', 'primary_photo_url'],
    }[entityType];
    if (single) {
      const [table, column] = single;
      const row = await get(`SELECT ${column} AS value FROM ${table} WHERE id = ?`, [
        Number(entityId),
      ]);
      if (!row) return;
      const next = url || (isAssetViewUrl(row.value) ? '' : row.value);
      if (next !== row.value) {
        await run(`UPDATE ${table} SET ${column} = ? WHERE id = ?`, [
          next,
          Number(entityId),
        ]);
      }
      return;
    }
    if (entityType === 'die') {
      const row = await get('SELECT photo_urls FROM dies WHERE id = ?', [Number(entityId)]);
      if (!row) return;
      let list;
      try {
        list = JSON.parse(row.photo_urls || '[]');
      } catch (_) {
        list = [];
      }
      if (!Array.isArray(list)) list = [];
      const primaryKey = primary?.object_key;
      const kept = list.filter(
        (value) =>
          typeof value === 'string' &&
          !(removedKey && isAssetViewUrlFor(value, removedKey)) &&
          !(primaryKey && isAssetViewUrlFor(value, primaryKey)),
      );
      const next = JSON.stringify(url ? [url, ...kept] : kept);
      if (next !== (row.photo_urls || '[]')) {
        await run('UPDATE dies SET photo_urls = ? WHERE id = ?', [next, Number(entityId)]);
      }
    }
  } catch (error) {
    console.warn('Could not note a photo on its record:', error.message);
  }
}

/**
 * Presigned S3 read URLs saved into photo fields before the permanent links
 * existed. They have long since expired; the object they name is still there,
 * so each becomes that object's permanent link. Run at boot, idempotent.
 */
async function backfillExpiringPhotoUrls() {
  const config = getS3Config();
  const keyOf = (value) => {
    if (typeof value !== 'string' || !value.includes('X-Amz-Signature')) return null;
    try {
      let pathname = decodeURIComponent(new URL(value).pathname).replace(/^\/+/, '');
      if (config.bucket && pathname.startsWith(`${config.bucket}/`)) {
        pathname = pathname.slice(config.bucket.length + 1);
      }
      return pathname || null;
    } catch (_) {
      return null;
    }
  };
  const columns = [
    ['items', 'photo_url'],
    ['clients', 'logo_url'],
    ['clients', 'photo_url'],
    ['vendors', 'logo_url'],
    ['vendors', 'photo_url'],
    ['machines', 'primary_photo_url'],
  ];
  for (const [table, column] of columns) {
    let rows;
    try {
      rows = await all(
        `SELECT id, ${column} AS value FROM ${table} WHERE ${column} LIKE '%X-Amz-Signature%'`,
      );
    } catch (_) {
      continue; // a table or column this database does not have
    }
    for (const row of rows) {
      const key = keyOf(row.value);
      if (key) {
        await run(`UPDATE ${table} SET ${column} = ? WHERE id = ?`, [assetViewUrl(key), row.id]);
      }
    }
  }
  try {
    const dies = await all("SELECT id, photo_urls FROM dies WHERE photo_urls LIKE '%X-Amz-Signature%'");
    for (const die of dies) {
      let list = [];
      try {
        list = JSON.parse(die.photo_urls || '[]');
      } catch (_) {
        continue;
      }
      if (!Array.isArray(list)) continue;
      const next = list.map((value) => {
        const key = keyOf(value);
        return key ? assetViewUrl(key) : value;
      });
      await run('UPDATE dies SET photo_urls = ? WHERE id = ?', [JSON.stringify(next), die.id]);
    }
  } catch (_) {
    // no dies table yet
  }
}

function localUploadSignature(method, objectKey, expires) {
  return crypto
    .createHmac('sha256', JWT_SECRET)
    .update(`local-upload\n${method}\n${objectKey}\n${expires}`)
    .digest('hex');
}

/** The file for [objectKey], refusing anything that climbs out of the root. */
function localUploadPath(objectKey) {
  const key = String(objectKey || '');
  const full = path.resolve(LOCAL_UPLOAD_ROOT, key);
  if (!key || key.includes('\0') || !full.startsWith(LOCAL_UPLOAD_ROOT + path.sep)) {
    const error = new Error('Invalid object key.');
    error.statusCode = 400;
    throw error;
  }
  return full;
}

function localUploadUrl(method, objectKey, expiresSeconds) {
  localUploadPath(objectKey);
  const expires = Math.floor(Date.now() / 1000) + Number(expiresSeconds || 300);
  const encodedKey = encodeObjectKey(objectKey);
  const signature = localUploadSignature(method, objectKey, expires);
  return `${localUploadBaseUrl()}/api/assets/local/${encodedKey}?exp=${expires}&sig=${signature}`;
}

/** Throws 403 unless [req] carries a live signature for [method] on [objectKey]. */
function assertLocalUploadSigned(req, method, objectKey) {
  const expires = Number(req.query?.exp || 0);
  const given = String(req.query?.sig || '');
  const wanted = localUploadSignature(method, objectKey, expires);
  const ok =
    Number.isFinite(expires) &&
    expires * 1000 >= Date.now() &&
    given.length === wanted.length &&
    crypto.timingSafeEqual(Buffer.from(given), Buffer.from(wanted));
  if (!ok) {
    const error = new Error('This upload link is not valid, or has expired.');
    error.statusCode = 403;
    throw error;
  }
}

function localObjectKeyFrom(req) {
  const raw = req.params?.key;
  const segments = Array.isArray(raw) ? raw : String(raw || '').split('/');
  return segments.map((segment) => decodeURIComponent(String(segment))).join('/');
}

function isDocumentObjectKey(objectKey) {
  return String(objectKey || '').startsWith(S3_UPLOAD_PREFIXES.PARTY_DOCUMENT);
}

const LOCAL_UPLOAD_CONTENT_TYPES = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
};

function assertS3Configured() {
  const config = getS3Config();
  if (!config.bucket) {
    const error = new Error(
      'S3 upload storage is not configured. Set PAPER_S3_BUCKET_NAME.',
    );
    error.statusCode = 503;
    throw error;
  }
  return config;
}

let cachedS3Client = null;
let cachedS3ClientConfigKey = '';

function getS3Client() {
  const config = assertS3Configured();
  const configKey = JSON.stringify({
    endpoint: config.endpoint || '',
    region: config.region,
    forcePathStyle: config.forcePathStyle,
  });
  if (cachedS3Client && cachedS3ClientConfigKey === configKey) {
    return cachedS3Client;
  }
  const clientConfig = {
    region: config.region,
  };
  if (config.endpoint) {
    clientConfig.endpoint = config.endpoint;
  }
  if (config.forcePathStyle) {
    clientConfig.forcePathStyle = true;
  }
  cachedS3Client = new S3Client(clientConfig);
  cachedS3ClientConfigKey = configKey;
  return cachedS3Client;
}

async function presignS3Url({
  method,
  objectKey,
  contentType = null,
  cacheControl = null,
  expiresSeconds = 900,
}) {
  if (usesLocalUploads() && (method === 'PUT' || method === 'GET')) {
    return localUploadUrl(method, objectKey, expiresSeconds);
  }
  const config = assertS3Configured();
  const client = getS3Client();
  let command;
  if (method === 'PUT') {
    command = new PutObjectCommand({
      Bucket: config.bucket,
      Key: objectKey,
      ...(contentType ? { ContentType: contentType } : {}),
      // Stored on the object, so a GET of it says the same.
      ...(cacheControl ? { CacheControl: cacheControl } : {}),
    });
  } else if (method === 'GET') {
    command = new GetObjectCommand({
      Bucket: config.bucket,
      Key: objectKey,
    });
  } else {
    throw new Error(`Unsupported S3 presign method: ${method}`);
  }
  return getSignedUrl(client, command, { expiresIn: expiresSeconds });
}

async function assertS3ObjectExists(objectKey) {
  if (String(process.env.S3_SKIP_OBJECT_VERIFY || '').toLowerCase() === 'true') {
    return;
  }
  if (usesLocalUploads()) {
    if (!fs.existsSync(localUploadPath(objectKey))) {
      const error = new Error('The uploaded file did not arrive.');
      error.statusCode = 400;
      throw error;
    }
    return;
  }
  const config = assertS3Configured();
  try {
    await getS3Client().send(
      new HeadObjectCommand({
        Bucket: config.bucket,
        Key: objectKey,
      }),
    );
  } catch (_) {
    const error = new Error('Uploaded S3 object could not be verified.');
    error.statusCode = 400;
    throw error;
  }
}

async function readS3ObjectBuffer(objectKey) {
  if (usesLocalUploads()) {
    return fs.promises.readFile(localUploadPath(objectKey));
  }
  const config = assertS3Configured();
  const result = await getS3Client().send(
    new GetObjectCommand({
      Bucket: config.bucket,
      Key: objectKey,
    }),
  );
  const chunks = [];
  for await (const chunk of result.Body) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

async function assertAssetEntityExists(entityType, entityId) {
  if (entityType === 'item') {
    const item = await getItemRowById(entityId);
    if (item) {
      return;
    }
  }
  if (entityType === 'machine') {
    const machine = await get('SELECT id FROM machines WHERE id = ?', [entityId]);
    if (machine) {
      return;
    }
  }
  if (entityType === 'die') {
    const die = await get('SELECT id FROM dies WHERE id = ?', [entityId]);
    if (die) {
      return;
    }
  }
  if (entityType === 'delivery_challan') {
    const challan = await get('SELECT id FROM delivery_challans WHERE id = ?', [entityId]);
    if (challan) {
      return;
    }
  }
  if (entityType === 'client') {
    const client = await get('SELECT id FROM clients WHERE id = ?', [entityId]);
    if (client) {
      return;
    }
  }
  if (entityType === 'party_contact') {
    const contact = await get('SELECT id FROM party_contacts WHERE id = ?', [entityId]);
    if (contact) {
      return;
    }
  }
  if (entityType === 'sub_contractor') {
    const contractor = await get('SELECT id FROM sub_contractors WHERE id = ?', [entityId]);
    if (contractor) {
      return;
    }
  }
  const error = new Error('Asset owner not found.');
  error.statusCode = 404;
  throw error;
}

async function assetReadUrlPayload(objectKey, expiresSeconds = 300) {
  return {
    readUrl: await presignS3Url({
      method: 'GET',
      objectKey,
      expiresSeconds,
    }),
    expiresAt: new Date(Date.now() + expiresSeconds * 1000).toISOString(),
  };
}

async function listAssetsForEntity(entityType, entityId, { includeReadUrls = true } = {}) {
  const normalizedEntityType = String(entityType || '').trim().toLowerCase();
  const normalizedEntityId = Number(entityId || 0);
  await assertAssetEntityExists(normalizedEntityType, normalizedEntityId);
  const rows = await all(
    `
    SELECT *
    FROM uploaded_assets
    WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded'
      AND document_title IS NULL
    ORDER BY is_primary DESC, datetime(uploaded_at) DESC, id DESC
    `,
    [normalizedEntityType, normalizedEntityId],
  );
  return Promise.all(
    rows.map(async (row) =>
      rowToAssetDto(
        row,
        includeReadUrls ? await assetReadUrlPayload(row.object_key) : null,
      ),
    ),
  );
}

async function createAssetUploadIntent(input) {
  const normalized = assertValidAssetUploadInput(input || {});
  await assertAssetEntityExists(normalized.entityType, normalized.entityId);

  const existing = await get(
    `
    SELECT *
    FROM uploaded_assets
    WHERE entity_type = ? AND entity_id = ? AND sha256 = ? AND status = 'uploaded'
      AND COALESCE(document_title, '') = ?
    `,
    // The same file under a second name is a second document; as a photo
    // and as a document it is one of each.
    [normalized.entityType, normalized.entityId, normalized.sha256, normalized.documentTitle || ''],
  );
  if (existing) {
    return {
      alreadyUploaded: true,
      asset: rowToAssetDto(
        existing,
        await assetReadUrlPayload(existing.object_key),
      ),
      upload: null,
    };
  }
  if (normalized.documentTitle == null) {
    await assertRoomForPhoto(normalized.entityType, normalized.entityId);
  }

  const objectKey = buildS3ObjectKey({
    uploadType: normalized.uploadType,
    fileName: normalized.fileName,
    sha256: normalized.sha256,
    entityType: normalized.entityType,
    entityId: normalized.entityId,
  });
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 15 * 60 * 1000).toISOString();
  const uploadSessionId = `asset-upload-${now.getTime()}-${crypto
    .randomBytes(8)
    .toString('hex')}`;
  const thumbKey = normalized.thumbnail ? thumbnailKeyFor(objectKey) : null;
  await run(
    `
    INSERT INTO asset_upload_sessions (
      id, entity_type, entity_id, file_name, content_type, size_bytes, sha256,
      object_key, status, is_primary, expires_at, created_at, document_title,
      thumb_key, width, height
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      uploadSessionId,
      normalized.entityType,
      normalized.entityId,
      normalized.fileName,
      normalized.contentType,
      normalized.sizeBytes,
      normalized.sha256,
      objectKey,
      normalized.isPrimary ? 1 : 0,
      expiresAt,
      now.toISOString(),
      normalized.documentTitle,
      thumbKey,
      normalized.width ?? null,
      normalized.height ?? null,
    ],
  );

  // A client that sends a thumbnail also sends the Cache-Control header the
  // URL is signed for; an older one (a phone not yet updated) sends only the
  // type, and a signature it cannot match would refuse its upload.
  const cacheControl = thumbKey ? IMMUTABLE_CACHE_CONTROL : null;
  const headersFor = (contentType) => ({
    'Content-Type': contentType,
    ...(cacheControl ? { 'Cache-Control': cacheControl } : {}),
  });
  return {
    alreadyUploaded: false,
    asset: null,
    upload: {
      uploadSessionId,
      objectKey,
      uploadUrl: await presignS3Url({
        method: 'PUT',
        objectKey,
        contentType: normalized.contentType,
        cacheControl,
        expiresSeconds: 900,
      }),
      expiresAt,
      headers: headersFor(normalized.contentType),
      thumbnail: thumbKey
        ? {
            objectKey: thumbKey,
            uploadUrl: await presignS3Url({
              method: 'PUT',
              objectKey: thumbKey,
              contentType: 'image/jpeg',
              cacheControl,
              expiresSeconds: 900,
            }),
            headers: headersFor('image/jpeg'),
          }
        : null,
    },
  };
}

async function completeAssetUpload({ uploadSessionId, objectKey }) {
  const session = await get('SELECT * FROM asset_upload_sessions WHERE id = ?', [
    uploadSessionId,
  ]);
  if (!session || session.object_key !== objectKey) {
    const error = new Error('Upload session not found.');
    error.statusCode = 404;
    throw error;
  }
  if (new Date(session.expires_at).getTime() < Date.now()) {
    const error = new Error('Upload session expired.');
    error.statusCode = 410;
    throw error;
  }
  await assertAssetEntityExists(session.entity_type, Number(session.entity_id));
  await assertS3ObjectExists(session.object_key);
  if (session.thumb_key) await assertS3ObjectExists(session.thumb_key);

  const documentTitle = session.document_title ?? null;
  // Two uploads begun side by side both passed the intent's count; the one
  // that finishes second is refused here, and the sweep takes its objects.
  if (documentTitle == null) {
    await assertRoomForPhoto(session.entity_type, Number(session.entity_id));
  }
  const primaryCount = await get(
    `
    SELECT COUNT(*) AS count
    FROM uploaded_assets
    WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded' AND is_primary = 1
    `,
    [session.entity_type, Number(session.entity_id)],
  );
  // A document is never the record's picture, however few photos it has.
  const shouldBePrimary =
    documentTitle == null &&
    (Number(session.is_primary || 0) === 1 || Number(primaryCount?.count || 0) === 0);
  const now = new Date().toISOString();

  await run('BEGIN TRANSACTION');
  try {
    if (shouldBePrimary) {
      await run(
        `
        UPDATE uploaded_assets
        SET is_primary = 0
        WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded'
        `,
        [session.entity_type, Number(session.entity_id)],
      );
    }
    // A photo goes after the record's others; a document has no place.
    // Photos from before positions are numbered first, in the order they are
    // shown, or a new one (MAX of nothing) would land in front of them.
    let last = null;
    if (documentTitle == null) {
      const photos = await orderedPhotoRows(session.entity_type, Number(session.entity_id));
      if (photos.some((row) => row.position == null)) {
        await renumberPhotos(photos.map((row) => row.id));
      }
      last = { position: photos.length };
    }
    await run(
      `
      INSERT OR IGNORE INTO uploaded_assets (
        entity_type, entity_id, file_name, content_type, size_bytes, sha256,
        object_key, status, is_primary, created_at, uploaded_at, document_title,
        position, thumb_key, width, height
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, 'uploaded', ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        session.entity_type,
        Number(session.entity_id),
        session.file_name,
        session.content_type,
        Number(session.size_bytes || 0),
        session.sha256,
        session.object_key,
        shouldBePrimary ? 1 : 0,
        session.created_at || now,
        now,
        documentTitle,
        last ? Number(last.position || 0) + 1 : null,
        session.thumb_key || null,
        session.width ?? null,
        session.height ?? null,
      ],
    );
    await run(
      "UPDATE asset_upload_sessions SET status = 'completed', completed_at = ? WHERE id = ?",
      [now, uploadSessionId],
    );
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }

  const asset = await get(
    'SELECT * FROM uploaded_assets WHERE object_key = ?',
    [session.object_key],
  );
  if (documentTitle == null) {
    await syncRecordPhotoField(session.entity_type, Number(session.entity_id));
  }
  announceAssetChanged(session.entity_type, session.entity_id);
  return rowToAssetDto(asset, await assetReadUrlPayload(asset.object_key));
}

/// Tells every open screen that a record's photos changed, so a slot showing
/// it re-reads. Without it a photo taken on the phone (or added on another
/// desktop) stayed invisible until the desktop's 4-minute photo cache ran out,
/// and a person's photo — which writes no record field — never announced at
/// all.
function announceAssetChanged(entityType, entityId) {
  changeEmitter.emit('custom-event', {
    event: 'asset_changed',
    data: { entityType: String(entityType || ''), entityId: Number(entityId || 0) },
  });
}

async function createAssetReadUrl(assetId) {
  const asset = await get(
    "SELECT * FROM uploaded_assets WHERE id = ? AND status = 'uploaded'",
    [Number(assetId || 0)],
  );
  if (!asset) {
    const error = new Error('Asset not found.');
    error.statusCode = 404;
    throw error;
  }
  const payload = await assetReadUrlPayload(asset.object_key);
  return {
    asset: rowToAssetDto(asset, payload),
    readUrl: payload.readUrl,
    expiresAt: payload.expiresAt,
  };
}

async function setPrimaryAsset(assetId) {
  const asset = await get(
    "SELECT * FROM uploaded_assets WHERE id = ? AND status = 'uploaded'",
    [Number(assetId || 0)],
  );
  if (!asset) {
    const error = new Error('Asset not found.');
    error.statusCode = 404;
    throw error;
  }
  if (asset.document_title != null) {
    const error = new Error('A document cannot be the record\'s photo.');
    error.statusCode = 400;
    throw error;
  }
  await run('BEGIN TRANSACTION');
  try {
    await run(
      `
      UPDATE uploaded_assets
      SET is_primary = 0
      WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded'
      `,
      [asset.entity_type, Number(asset.entity_id)],
    );
    await run('UPDATE uploaded_assets SET is_primary = 1 WHERE id = ?', [
      asset.id,
    ]);
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
  await syncRecordPhotoField(asset.entity_type, Number(asset.entity_id));
  announceAssetChanged(asset.entity_type, asset.entity_id);
  const updated = await get('SELECT * FROM uploaded_assets WHERE id = ?', [
    asset.id,
  ]);
  return rowToAssetDto(updated, await assetReadUrlPayload(updated.object_key));
}

async function deleteAsset(assetId) {
  const asset = await get(
    "SELECT * FROM uploaded_assets WHERE id = ? AND status = 'uploaded'",
    [Number(assetId || 0)],
  );
  if (!asset) {
    const error = new Error('Asset not found.');
    error.statusCode = 404;
    throw error;
  }
  // Marked, not erased: sweepDeletedAssets removes the stored objects a day
  // later, which leaves the day to put a photo back.
  await run(
    "UPDATE uploaded_assets SET status = 'deleted', deleted_at = ?, is_primary = 0 WHERE id = ?",
    [new Date().toISOString(), asset.id],
  );
  if (asset.document_title == null) {
    const photos = await orderedPhotoRows(asset.entity_type, Number(asset.entity_id));
    await renumberPhotos(photos.map((row) => row.id));
    // The first one left becomes the shown photo.
    if (Number(asset.is_primary || 0) === 1 && photos.length > 0) {
      await run('UPDATE uploaded_assets SET is_primary = 1 WHERE id = ?', [
        photos[0].id,
      ]);
    }
  }
  if (asset.document_title == null) {
    await syncRecordPhotoField(asset.entity_type, Number(asset.entity_id), asset.object_key);
  }
  announceAssetChanged(asset.entity_type, asset.entity_id);
}

/// A record's photos (not its documents) in their order: by position, then
/// those from before positions, newest first.
async function orderedPhotoRows(entityType, entityId) {
  return all(
    `
    SELECT *
    FROM uploaded_assets
    WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded'
      AND document_title IS NULL
    ORDER BY position IS NULL, position, is_primary DESC,
      datetime(uploaded_at) DESC, id DESC
    `,
    [entityType, Number(entityId)],
  );
}

async function renumberPhotos(ids) {
  for (const [index, id] of ids.entries()) {
    await run('UPDATE uploaded_assets SET position = ? WHERE id = ?', [index + 1, id]);
  }
}

function photoDto(row) {
  return {
    id: row.id,
    position: row.position == null ? null : Number(row.position),
    isPrimary: Number(row.is_primary || 0) === 1,
    sha256: row.sha256 || '',
    fileName: row.file_name || '',
    // Permanent links (each redirects to a fresh signed URL): the small copy
    // for grids and lists, the photo for the big view.
    thumbUrl: assetViewUrl(row.thumb_key || row.object_key),
    viewUrl: assetViewUrl(row.object_key),
    hasThumbnail: Boolean(row.thumb_key),
    width: row.width == null ? null : Number(row.width),
    height: row.height == null ? null : Number(row.height),
    uploadedAt: row.uploaded_at,
  };
}

/// A part's photos as one ordered array — what the gallery opens on.
async function listEntityPhotos(entityType, entityId) {
  await assertAssetEntityExists(entityType, Number(entityId));
  const rows = await orderedPhotoRows(entityType, Number(entityId));
  return rows.map(photoDto);
}

/// The gallery's Save: the photos' order and which one is shown, in one
/// transaction. [order] lists photo ids first to last; one it leaves out
/// keeps its place after them. [primaryId] absent leaves the shown one.
async function arrangeEntityPhotos(entityType, entityId, { order, primaryId } = {}) {
  await assertAssetEntityExists(entityType, Number(entityId));
  const rows = await orderedPhotoRows(entityType, Number(entityId));
  const known = new Set(rows.map((row) => row.id));
  const wanted = (Array.isArray(order) ? order : []).map((id) => Number(id));
  for (const id of wanted) {
    if (!known.has(id)) {
      const error = new Error(`Photo ${id} is not one of this record's photos.`);
      error.statusCode = 400;
      throw error;
    }
  }
  if (new Set(wanted).size !== wanted.length) {
    const error = new Error('A photo is listed twice.');
    error.statusCode = 400;
    throw error;
  }
  const primary = primaryId === undefined || primaryId === null ? null : Number(primaryId);
  if (primary != null && !known.has(primary)) {
    const error = new Error('The main photo has to be one of this record\'s photos.');
    error.statusCode = 400;
    throw error;
  }
  const ids = [...wanted, ...rows.map((row) => row.id).filter((id) => !wanted.includes(id))];
  await run('BEGIN TRANSACTION');
  try {
    await renumberPhotos(ids);
    if (primary != null) {
      await run(
        `
        UPDATE uploaded_assets SET is_primary = CASE WHEN id = ? THEN 1 ELSE 0 END
        WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded'
        `,
        [primary, entityType, Number(entityId)],
      );
    }
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
  await syncRecordPhotoField(entityType, Number(entityId));
  announceAssetChanged(entityType, entityId);
  return listEntityPhotos(entityType, entityId);
}

/// What a deleted photo still costs is its objects. Removes them — the photo
/// and its thumbnail — once the row has been deleted for [graceHours]; and
/// the objects of uploads begun and never finished, an hour after their link
/// expired. [now] is for tests.
async function sweepDeletedAssets({ now = new Date(), graceHours = 24 } = {}) {
  const cutoff = new Date(now.getTime() - graceHours * 3600 * 1000).toISOString();
  const swept = { assets: 0, sessions: 0, objects: 0, failed: 0 };
  const rows = await all(
    `
    SELECT id, object_key, thumb_key
    FROM uploaded_assets
    WHERE status = 'deleted' AND COALESCE(deleted_at, '') <> '' AND deleted_at <= ?
    LIMIT 500
    `,
    [cutoff],
  );
  // A record's photos, deleted with it, go only once the record is gone for
  // good: not live, and not in the trash it can be restored from.
  const orphaned = [];
  const withRecord = await all(
    `
    SELECT id, entity_type, entity_id, object_key, thumb_key
    FROM uploaded_assets
    WHERE status = 'record_deleted' AND COALESCE(deleted_at, '') <> '' AND deleted_at <= ?
    LIMIT 500
    `,
    [cutoff],
  );
  for (const row of withRecord) {
    const table = ASSET_OWNER_TABLES[row.entity_type];
    if (table) {
      const live = await get(`SELECT 1 FROM ${table} WHERE id = ? LIMIT 1`, [Number(row.entity_id)]);
      const trashed = await get(
        'SELECT 1 FROM deleted_records WHERE table_name = ? AND record_id = ? LIMIT 1',
        [table, Number(row.entity_id)],
      ).catch(() => null);
      if (live || trashed) continue;
    }
    orphaned.push(row);
  }
  for (const row of [...rows, ...orphaned]) {
    const ok = await deleteStoredObjects([row.object_key, row.thumb_key], swept);
    if (ok) {
      await run("UPDATE uploaded_assets SET status = 'purged' WHERE id = ?", [row.id]);
      swept.assets += 1;
    }
  }
  const stale = new Date(now.getTime() - 3600 * 1000).toISOString();
  const sessions = await all(
    `
    SELECT id, object_key, thumb_key
    FROM asset_upload_sessions
    WHERE status = 'pending' AND expires_at <= ?
    LIMIT 500
    `,
    [stale],
  );
  for (const session of sessions) {
    // A key a stored asset holds is that asset's, whatever the session says.
    const held = await get(
      "SELECT 1 FROM uploaded_assets WHERE object_key = ? AND status <> 'purged' LIMIT 1",
      [session.object_key],
    );
    const ok = held ? true : await deleteStoredObjects([session.object_key, session.thumb_key], swept);
    if (ok) {
      await run("UPDATE asset_upload_sessions SET status = 'expired' WHERE id = ?", [session.id]);
      swept.sessions += 1;
    }
  }
  return swept;
}

/// Deletes [keys] from wherever objects are stored. False when one could not
/// be removed (it is tried again on the next sweep); a key already gone is
/// not a failure.
async function deleteStoredObjects(keys, tally) {
  let ok = true;
  for (const key of keys.filter(Boolean)) {
    try {
      if (usesLocalUploads()) {
        await fs.promises.unlink(localUploadPath(key)).catch((error) => {
          if (error.code !== 'ENOENT') throw error;
        });
      } else {
        await getS3Client().send(
          new DeleteObjectCommand({ Bucket: assertS3Configured().bucket, Key: key }),
        );
      }
      tally.objects += 1;
    } catch (error) {
      tally.failed += 1;
      ok = false;
      console.warn(`[assets] could not delete ${key}: ${error.message}`);
    }
  }
  return ok;
}

/// A company's documents, newest first, each with a short-lived read URL.
async function listDocumentsForEntity(entityType, entityId) {
  const normalizedEntityType = String(entityType || '').trim().toLowerCase();
  const normalizedEntityId = Number(entityId || 0);
  if (!DOCUMENT_ENTITY_TYPES.has(normalizedEntityType)) {
    const error = new Error('Documents are kept for a client or a contractor.');
    error.statusCode = 400;
    throw error;
  }
  await assertAssetEntityExists(normalizedEntityType, normalizedEntityId);
  const rows = await all(
    `
    SELECT *
    FROM uploaded_assets
    WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded'
      AND document_title IS NOT NULL
    ORDER BY datetime(uploaded_at) DESC, id DESC
    `,
    [normalizedEntityType, normalizedEntityId],
  );
  return Promise.all(rows.map((row) => rowToUploadedAssetDto(row, true)));
}

async function renameDocument(assetId, title) {
  const asset = await get(
    "SELECT * FROM uploaded_assets WHERE id = ? AND status = 'uploaded'",
    [Number(assetId || 0)],
  );
  if (!asset || asset.document_title == null) {
    const error = new Error('Document not found.');
    error.statusCode = 404;
    throw error;
  }
  const next = normalizeDocumentTitle(title);
  await run('UPDATE uploaded_assets SET document_title = ? WHERE id = ?', [next, asset.id]);
  announceAssetChanged(asset.entity_type, asset.entity_id);
  return rowToAssetDto({ ...asset, document_title: next });
}

// --- photos the desktop asks the phone to take ------------------------------
// (migrations/062). The item sheet is bulk entry; a click on a photo slot files
// a request for the person who clicked, and their phone — logged in as them —
// takes it. The photo itself goes up through the ordinary asset routes; these
// only queue, describe and close the jobs.

const PHOTO_REQUEST_TYPES = ['item', 'client', 'party_contact', 'die', 'machine', 'sub_contractor'];

function photoRequestError(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function announcePhotoRequests(userId) {
  changeEmitter.emit('custom-event', {
    event: 'photo_requests_changed',
    data: { userId: Number(userId) },
    // Read by the event stream: only this user's own connections get it.
    userId: Number(userId),
  });
}

/// What the phone shows over the camera: what the record is and the few
/// facts that tell it apart on the floor. Built when asked, so never stale.
async function photoRequestDetails(entityType, entityId, documentTitle = null) {
  const lines = [];
  const add = (label, value) => {
    const text = value == null ? '' : String(value).trim();
    if (text) lines.push({ label, value: text });
  };
  if (entityType === 'item') {
    const row = await get('SELECT * FROM items WHERE id = ?', [entityId]);
    if (!row) return null;
    const path = [];
    let groupId = row.group_id;
    for (let depth = 0; groupId && depth < 6; depth += 1) {
      const group = await get('SELECT name, parent_group_id FROM groups WHERE id = ?', [groupId]);
      if (!group) break;
      path.unshift(group.name);
      groupId = group.parent_group_id;
    }
    add('Group', path.join(' › '));
    add('Part code', row.part_code);
    add('Part no', row.part_no);
    return { kind: 'Part', title: row.display_name || row.name, lines };
  }
  if (entityType === 'client') {
    const row = await get('SELECT * FROM clients WHERE id = ?', [entityId]);
    if (!row) return null;
    if (documentTitle != null) {
      add('Company', row.name);
      add('GST', row.gst_number);
      return { kind: 'Document', title: documentTitle, lines };
    }
    add('GST', row.gst_number);
    add('Address', row.address);
    return { kind: 'Company logo', title: row.name, lines };
  }
  if (entityType === 'sub_contractor') {
    const row = await get('SELECT * FROM sub_contractors WHERE id = ?', [entityId]);
    if (!row) return null;
    const client = await get('SELECT name FROM clients WHERE id = ?', [row.client_id]);
    add('Contractor', row.name);
    add('For', client?.name);
    add('GST', row.gst_number);
    if (documentTitle != null) {
      return { kind: 'Document', title: documentTitle, lines };
    }
    return { kind: 'Contractor photo', title: row.name, lines };
  }
  if (entityType === 'party_contact') {
    const row = await get('SELECT * FROM party_contacts WHERE id = ?', [entityId]);
    if (!row) return null;
    const company = row.party_type === 'client'
      ? await get('SELECT name FROM clients WHERE id = ?', [row.party_id])
      : null;
    add('Designation', row.designation);
    add('Company', company?.name);
    add('Phone', row.phone);
    return { kind: 'Person', title: row.name, lines };
  }
  if (entityType === 'die') {
    const row = await get('SELECT * FROM dies WHERE id = ?', [entityId]);
    if (!row) return null;
    const type = row.die_type_label
      || (row.die_type ? row.die_type.charAt(0).toUpperCase() + row.die_type.slice(1) : '');
    add('Type', type);
    add('Made by', row.made_by);
    add('Kept', [row.store_area, row.rack_no ? `Rack ${row.rack_no}` : ''].filter(Boolean).join(' · '));
    return { kind: 'Die', title: row.tool_code || `Die ${row.id}`, lines };
  }
  if (entityType === 'machine') {
    const row = await get('SELECT * FROM machines WHERE id = ?', [entityId]);
    if (!row) return null;
    add('Name', row.asset_id ? row.name : '');
    add('Make', row.machine_make);
    if (row.capacity_kind === 'free_hand') {
      add('Capacity', 'Free hand');
    } else if (row.capacity_kgf) {
      const tons = Number(row.capacity_kgf) / 1000;
      add('Capacity', `${Number.isInteger(tons) ? tons : tons.toFixed(2)} Ton`);
    }
    return { kind: 'Machine', title: row.asset_id || row.name || `Machine ${row.id}`, lines };
  }
  return null;
}

function photoRequestDto(row, details) {
  return {
    id: row.id,
    entityType: row.entity_type,
    entityId: row.entity_id,
    context: row.context || '',
    documentTitle: row.document_title ?? null,
    status: row.status,
    assetId: row.asset_id,
    createdAt: row.created_at,
    details,
  };
}

async function ownPhotoRequest(req) {
  const row = await get('SELECT * FROM photo_requests WHERE id = ?', [Number(req.params.id)]);
  // Someone else's request is reported as not there at all.
  if (!row || Number(row.user_id) !== Number(req.user?.id)) {
    throw photoRequestError('Photo request not found.', 404);
  }
  return row;
}

async function seedGroupsIfEmpty() {
  // Intentionally left empty. The richer demo hierarchy is created in
  // ensureDemoGroupsPresent().
}

async function ensureGroupRecord({
  name,
  parentGroupId = null,
  unitId,
  isArchived = false,
}) {
  const duplicate = await findGroupDuplicate({ name, parentGroupId });
  const group = duplicate || await saveGroup({ name, parentGroupId, unitId });
  // This raw UPDATE bypasses saveGroup, so it has to run the same cycle check
  // itself — otherwise a seed could write the one thing every ancestor walk
  // assumes cannot exist. On conflict keep the stored parent rather than
  // aborting a boot-time reseed.
  const wouldCycle = await groupWouldCreateCycle(group.id, parentGroupId);
  if (wouldCycle) {
    console.warn(
      `[groups] ensureGroupRecord skipped reparenting "${name}" (group ${group.id}) ` +
        `under ${parentGroupId}: it would create a parent cycle`,
    );
  }
  await run(
    `
    UPDATE groups
    SET name = ?, parent_group_id = ?, unit_id = ?, is_archived = ?, updated_at = ?
    WHERE id = ?
    `,
    [
      name,
      wouldCycle ? (group.parent_group_id ?? null) : parentGroupId,
      unitId,
      isArchived ? 1 : 0,
      new Date().toISOString(),
      group.id,
    ],
  );
  return getGroupRowById(group.id);
}

async function ensureDemoGroupsPresent() {
  const units = await getUnitsWithUsage();
  const bySymbol = new Map(
    units.map((unit) => [normalizeUnitValue(unit.symbol), unit]),
  );
  const pieceUnit = bySymbol.get('pc') || units[0];
  
  await ensureGroupRecord({
    name: 'Primary Group',
    unitId: pieceUnit.id,
  });
}

async function seedItemsIfEmpty() {
  // Intentionally left empty. The complete item demo set is created later in
  // ensureDemoItemsPresent().
}

async function ensureDemoItemsPresent(scenarioId = 'default') {
  const groups = await getGroupsWithUsage();
  const units = await getUnitsWithUsage();
  const groupByName = new Map(
    groups.map((group) => [normalizeUnitValue(group.name), group]),
  );
  const primaryGroup = groupByName.get(normalizeUnitValue('Primary Group')) || groups[0];
  const mfgGroup = groupByName.get(normalizeUnitValue('Manufacturing')) || groups[0];

  const unitByName = new Map(
    units.map((unit) => [normalizeUnitValue(unit.name), unit]),
  );
  const piecesUnit = unitByName.get(normalizeUnitValue('Piece')) || units[0];
  const boxUnit = unitByName.get(normalizeUnitValue('Box')) || units[0];
  const kgUnit = unitByName.get(normalizeUnitValue('Kilogram')) || units[0];

  if (scenarioId === 'manufacturing') {
    const rawMaterial = {
      baseItem: {
        name: 'Aluminum Billet',
        group_id: mfgGroup.id,
        hsn_code: '7601',
        is_active: 1,
      },
      variations: {
        'Initial State': [
          { name: 'Raw', code: 'RAW' },
        ],
        'Primary Process': [
          { name: 'None', code: 'NON' },
          { name: 'Milled', code: 'MLL' },
        ],
        'Finishing': [
          { name: 'None', code: 'NON' },
          { name: 'Anodized', code: 'ANO' },
        ],
      },
      unit_id: kgUnit.id,
    };
    
    const intermediate = {
      baseItem: {
        name: 'Copper Coil',
        group_id: mfgGroup.id,
        hsn_code: '7408',
        is_active: 1,
      },
      variations: {
        'State': [
          { name: 'Drawn', code: 'DRW' },
        ],
        'Treatment': [
          { name: 'Insulated', code: 'INS' },
          { name: 'Bare', code: 'BAR' },
        ]
      },
      unit_id: kgUnit.id,
    };
    
    const result = [];
    for (const data of [rawMaterial, intermediate]) {
      const dbItem = await seedScenarioItem(data);
      result.push(dbItem);
    }
    return result;
  }

  if (scenarioId === 'mobiles') {
    const mobileGroup = groupByName.get(normalizeUnitValue('Mobiles')) || primaryGroup;
    // One item exercising 5 top-level properties, each with 5 values.
    const smartphone = {
      baseItem: {
        name: 'Smartphone X',
        group_id: mobileGroup.id,
        hsn_code: '8517',
        is_active: 1,
      },
      variations: {
        'Color': [
          { name: 'Black', code: 'BLK' },
          { name: 'White', code: 'WHT' },
          { name: 'Blue', code: 'BLU' },
          { name: 'Green', code: 'GRN' },
          { name: 'Red', code: 'RED' },
        ],
        'Storage': [
          { name: '64GB', code: '064' },
          { name: '128GB', code: '128' },
          { name: '256GB', code: '256' },
          { name: '512GB', code: '512' },
          { name: '1TB', code: '1TB' },
        ],
        'RAM': [
          { name: '4GB', code: 'R04' },
          { name: '6GB', code: 'R06' },
          { name: '8GB', code: 'R08' },
          { name: '12GB', code: 'R12' },
          { name: '16GB', code: 'R16' },
        ],
        'Display': [
          { name: 'LCD', code: 'LCD' },
          { name: 'OLED', code: 'OLD' },
          { name: 'AMOLED', code: 'AMO' },
          { name: 'Retina', code: 'RET' },
          { name: 'ProMotion', code: 'PRO' },
        ],
        'Network': [
          { name: '4G', code: '4G' },
          { name: '5G', code: '5G' },
          { name: '5G Plus', code: '5GP' },
          { name: 'WiFi Only', code: 'WIF' },
          { name: 'Dual SIM', code: 'DUA' },
        ],
      },
      unit_id: piecesUnit.id,
    };

    const dbItem = await seedScenarioItem(smartphone);
    return [dbItem];
  }

  // default scenario
  const seedItems = [
    {
      baseItem: {
        name: 'Anchor Roma Classic Switch 10A 1-Way',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '1M', code: '1M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Classic Switch 20A 1-Way',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '1M', code: '1M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Classic Socket 10A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '2M', code: '2M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Classic Socket 20A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '2M', code: '2M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Penta Switch 10A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '1M', code: '1M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Penta Switch 20A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '1M', code: '1M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Penta Socket 10A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '2M', code: '2M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Anchor Roma Penta Socket 20A',
        group_id: primaryGroup.id,
        hsn_code: '8536',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
        'Module': [{name: '2M', code: '2M'}]
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
    {
      baseItem: {
        name: 'Polycab 1.5 sq mm FR PVC Wire (90m)',
        group_id: primaryGroup.id,
        hsn_code: '8544',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'Red', code: 'RD'}],
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 12 } ],
    },
    {
      baseItem: {
        name: 'Polycab 2.5 sq mm FR PVC Wire (90m)',
        group_id: primaryGroup.id,
        hsn_code: '8544',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'Red', code: 'RD'}],
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 12 } ],
    },
    {
      baseItem: {
        name: 'Orient Electric 1200mm Ceiling Fan',
        group_id: primaryGroup.id,
        hsn_code: '8414',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'Brown', code: 'BR'}],
      },
      unit_id: piecesUnit.id,
      conversions: [],
    },
    {
      baseItem: {
        name: 'Crompton Greaves 1200mm Ceiling Fan',
        group_id: primaryGroup.id,
        hsn_code: '8414',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'White', code: 'WH'}],
      },
      unit_id: piecesUnit.id,
      conversions: [],
    },
    {
      baseItem: {
        name: 'Philips 9W LED Bulb',
        group_id: primaryGroup.id,
        hsn_code: '8539',
        is_active: 1,
      },
      variations: {
        'Color': [{name: 'Cool Day Light', code: 'CDL'}],
      },
      unit_id: piecesUnit.id,
      conversions: [ { unit_id: boxUnit.id, multiplier: 10 } ],
    },
  ];

  const result = [];
  for (const data of seedItems) {
    const dbItem = await seedScenarioItem(data);
    result.push(dbItem);
  }
  return result;
}

async function seedScenarioItem(data) {
  let [existing] = await all('SELECT id FROM items WHERE name = ?', [
    data.baseItem.name,
  ]);
  
  let itemId;
  if (!existing) {
    const res = await run(
      `INSERT INTO items (name, display_name, group_id, unit_id, quantity, created_at, updated_at) 
       VALUES (?, ?, ?, ?, 0, datetime('now'), datetime('now'))`,
      [data.baseItem.name, data.baseItem.name, data.baseItem.group_id, data.unit_id],
    );
    itemId = res.lastID;
    
    // insert properties & values
    let order_index = 0;
    for (const [propName, values] of Object.entries(data.variations)) {
      const propRes = await run(
        `INSERT INTO item_variation_nodes 
         (item_id, parent_node_id, kind, name, input_type, position, is_archived, created_at, updated_at)
         VALUES (?, NULL, 'property', ?, 'Text', ?, 0, datetime('now'), datetime('now'))`,
         [itemId, propName, order_index]
      );
      const propId = propRes.lastID;
      
      let val_index = 0;
      for (const val of values) {
        await run(
          `INSERT INTO item_variation_nodes 
           (item_id, parent_node_id, kind, name, code, input_type, position, is_archived, created_at, updated_at)
           VALUES (?, ?, 'value', ?, ?, 'Text', ?, 0, datetime('now'), datetime('now'))`,
           [itemId, propId, val.name, val.code, val_index]
        );
        val_index++;
      }
      order_index++;
    }

    if (data.conversions) {
      for (const conv of data.conversions) {
        await run(
          `INSERT INTO item_unit_conversions (item_id, unit_id, factor_to_primary, created_at, updated_at) VALUES (?, ?, ?, datetime('now'), datetime('now'))`,
          [itemId, conv.unit_id, conv.multiplier],
        );
      }
    }
    await logChange('items', itemId, 'INSERT');
  } else {
    itemId = existing.id;
  }
  return getItemRowById(itemId);
}

// The real, working manufacturing inventory seed lives in
// ensureDemoInventoryPresent (defined near reseedDemoData). The earlier
// createOrGetMaterial/addInventory helpers here referenced a non-existent
// `inventory` table and stale column names, so they were removed.

function findLeafVariationNodes(nodes = [], currentPath = []) {
  const leaves = [];
  for (const node of nodes) {
    const nextPath = [...currentPath, node.id];
    if (node.kind === 'value' && (!node.children || node.children.length === 0)) {
      leaves.push({
        id: node.id,
        displayName: node.displayName || '',
        path: nextPath,
      });
      continue;
    }
    leaves.push(...findLeafVariationNodes(node.children || [], nextPath));
  }
  return leaves;
}

async function seedOrdersIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM order_items');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  await ensureMockOrdersPresent();
}

async function ensureMockOrdersPresent() {
  const existingOrders = await getOrders();
  const existingOrderNos = new Set(
    existingOrders.map((row) => String(row.order_no || '').trim().toLowerCase()),
  );

  const clientRows = await getClientsWithUsage();
  const itemRows = await getItemsWithUsage();
  const activeClients = clientRows
    .filter((row) => !row.is_archived)
    .map((row) => rowToClientDto(row));
  const activeItems = [];
  for (const row of itemRows) {
    if (row.is_archived) {
      continue;
    }
    activeItems.push(await rowToItemDto(row));
  }

  if (activeClients.length === 0 || activeItems.length === 0) {
    return;
  }

  const primaryClient = activeClients[0];
  const secondaryClient = activeClients[1] || activeClients[0];
  const primaryItem = activeItems[0];
  const secondaryItem = activeItems[1] || activeItems[0];
  const primaryLeaves = findLeafVariationNodes(primaryItem.variationTree || []);
  const secondaryLeaves = findLeafVariationNodes(secondaryItem.variationTree || []);
  const firstLeaf = primaryLeaves[0];
  const secondLeaf = primaryLeaves[1] || firstLeaf;
  const thirdLeaf = secondaryLeaves[0] || firstLeaf;

  if (!firstLeaf || !secondLeaf || !thirdLeaf) {
    return;
  }

  const mockOrders = [
    {
      orderNo: '123456',
      client: primaryClient,
      poNumber: 'PO-123456',
      clientCode: primaryClient.alias,
      item: primaryItem,
      leaf: firstLeaf,
      quantity: 1000,
      unitPrice: 18.5,
      totalInvoicedQty: 250,
      status: 'notStarted',
    },
    {
      orderNo: '123457',
      client: primaryClient,
      poNumber: 'PO-123457',
      clientCode: primaryClient.alias,
      item: primaryItem,
      leaf: secondLeaf,
      quantity: 1000,
      unitPrice: 21.75,
      totalInvoicedQty: 400,
      status: 'inProgress',
    },
    {
      orderNo: '123458',
      client: secondaryClient,
      poNumber: 'PO-123458',
      clientCode: secondaryClient.alias,
      item: secondaryItem,
      leaf: thirdLeaf,
      quantity: 1000,
      unitPrice: 9.25,
      totalInvoicedQty: 1000,
      status: 'completed',
    },
    {
      orderNo: '123459',
      client: secondaryClient,
      poNumber: 'PO-123459',
      clientCode: secondaryClient.alias,
      item: primaryItem,
      leaf: firstLeaf,
      quantity: 1000,
      unitPrice: 17.4,
      totalInvoicedQty: 125,
      status: 'delayed',
    },
  ];

  for (const order of mockOrders) {
    if (existingOrderNos.has(order.orderNo.toLowerCase())) {
      continue;
    }
    await saveOrder({
      orderNo: order.orderNo,
      clientId: order.client.id,
      clientName: order.client.name,
      poNumber: order.poNumber,
      clientCode: order.clientCode,
      itemId: order.item.id,
      itemName: order.item.displayName,
      variationLeafNodeId: order.leaf.id,
      variationPathLabel: order.leaf.displayName,
      variationPathNodeIds: order.leaf.path,
      quantity: order.quantity,
      unitPrice: order.unitPrice,
      totalInvoicedQty: order.totalInvoicedQty,
      status: order.status,
      startDate: '2026-04-10T00:00:00.000Z',
      endDate: '2026-05-15T00:00:00.000Z',
    });
  }
}

function findLeafByLabel(leaves, labelFragment) {
  const normalizedFragment = normalizeUnitValue(labelFragment);
  return (
    leaves.find((leaf) =>
      normalizeUnitValue(leaf.displayName).includes(normalizedFragment),
    ) || leaves[0]
  );
}

async function ensureDemoOrdersPresent() {
  await ensureMockOrdersPresent();

  const clients = (await getClientsWithUsage())
    .filter((row) => !row.is_archived)
    .map((row) => rowToClientDto(row));
  const items = [];
  for (const row of await getItemsWithUsage()) {
    if (!row.is_archived) {
      items.push(await rowToItemDto(row));
    }
  }

  if (clients.length < 3 || items.length < 3) {
    return;
  }

  const clientByAlias = new Map(clients.map((client) => [client.alias, client]));
  const itemByDisplayName = new Map(
    items.map((item) => [item.displayName, item]),
  );

  const bottleItem = itemByDisplayName.get('Bottle Carton - 100');
  const glueItem = itemByDisplayName.get('Glue Compound - 25');
  const capItem = itemByDisplayName.get('Flip-Top Cap - 500');
  const sleeveItem = itemByDisplayName.get('Printed Sleeve - 200');
  const acme = clientByAlias.get('ACME');
  const sunrise = clientByAlias.get('SUN');
  const northstar = clientByAlias.get('NSP');
  const orbit = clientByAlias.get('ORB');
  const bluepeak = clientByAlias.get('BPE');

  if (!bottleItem || !glueItem || !capItem || !sleeveItem) {
    return;
  }
  if (!acme || !sunrise || !northstar || !orbit || !bluepeak) {
    return;
  }

  const bottleLeaves = findLeafVariationNodes(bottleItem.variationTree || []);
  const glueLeaves = findLeafVariationNodes(glueItem.variationTree || []);
  const capLeaves = findLeafVariationNodes(capItem.variationTree || []);
  const sleeveLeaves = findLeafVariationNodes(sleeveItem.variationTree || []);

  const orderSeeds = [
    {
      orderNo: 'DEMO-2401',
      poNumber: 'PO-ACME-7781',
      client: acme,
      item: bottleItem,
      leaf: findLeafByLabel(bottleLeaves, 'Matte'),
      quantity: 1800,
      unitPrice: 24.5,
      totalInvoicedQty: 600,
      status: 'notStarted',
      startDate: '2026-04-12T00:00:00.000Z',
      endDate: '2026-04-21T00:00:00.000Z',
    },
    {
      orderNo: 'DEMO-2402',
      poNumber: 'PO-ACME-7782',
      client: acme,
      item: bottleItem,
      leaf: findLeafByLabel(bottleLeaves, 'Offset'),
      quantity: 3200,
      unitPrice: 27.25,
      totalInvoicedQty: 1200,
      status: 'inProgress',
      startDate: '2026-04-07T00:00:00.000Z',
      endDate: '2026-04-18T00:00:00.000Z',
    },
    {
      orderNo: 'DEMO-2403',
      poNumber: 'PO-SUN-9120',
      client: sunrise,
      item: capItem,
      leaf: findLeafByLabel(capLeaves, 'White'),
      quantity: 5000,
      unitPrice: 3.8,
      totalInvoicedQty: 5000,
      status: 'completed',
      startDate: '2026-03-28T00:00:00.000Z',
      endDate: '2026-04-03T00:00:00.000Z',
    },
    {
      orderNo: 'DEMO-2404',
      poNumber: 'PO-NSP-1148',
      client: northstar,
      item: glueItem,
      leaf: findLeafByLabel(glueLeaves, 'High'),
      quantity: 750,
      unitPrice: 112,
      totalInvoicedQty: 0,
      status: 'delayed',
      startDate: '2026-04-02T00:00:00.000Z',
      endDate: '2026-04-15T00:00:00.000Z',
    },
    {
      orderNo: 'DEMO-2405',
      poNumber: 'PO-ORB-3319',
      client: orbit,
      item: sleeveItem,
      leaf: findLeafByLabel(sleeveLeaves, 'Export'),
      quantity: 2200,
      unitPrice: 14.2,
      totalInvoicedQty: 350,
      status: 'inProgress',
      startDate: '2026-04-08T00:00:00.000Z',
      endDate: '2026-04-23T00:00:00.000Z',
    },
    {
      orderNo: 'DEMO-2406',
      poNumber: 'PO-BPE-4470',
      client: bluepeak,
      item: capItem,
      leaf: findLeafByLabel(capLeaves, '32 mm'),
      quantity: 4100,
      unitPrice: 4.15,
      totalInvoicedQty: 0,
      status: 'notStarted',
      startDate: '2026-04-16T00:00:00.000Z',
      endDate: '2026-04-28T00:00:00.000Z',
    },
  ];

  for (const order of orderSeeds) {
    await saveOrder({
      orderNo: order.orderNo,
      clientId: order.client.id,
      clientName: order.client.name,
      poNumber: order.poNumber,
      clientCode: order.client.alias,
      itemId: order.item.id,
      itemName: order.item.displayName,
      variationLeafNodeId: order.leaf.id,
      variationPathLabel: order.leaf.displayName,
      variationPathNodeIds: order.leaf.path,
      quantity: order.quantity,
      unitPrice: order.unitPrice,
      totalInvoicedQty: order.totalInvoicedQty,
      status: order.status,
      startDate: order.startDate,
      endDate: order.endDate,
    });
  }
}

// Units left for modules/units/master.js. How much a unit is used is no longer
// a subquery over other modules' tables: the master asks inventory, items and
// orders at the kernel desk and adds its own count. These are declarations, so
// they can be called from anywhere in this file regardless of where they sit.
const unitsMaster = createUnitsMaster({ get, all, run, desk: desk.as('units') });
function getUnitRowById(id) { return unitsMaster.getUnitRowById(id); }
function getUnitsWithUsage() { return unitsMaster.getUnitsWithUsage(); }
function saveUnit(input) { return unitsMaster.saveUnit(input); }

function areUnitsCompatible(groupUnitRow, itemUnitRow) {
  if (!groupUnitRow || !itemUnitRow) {
    return false;
  }
  if (groupUnitRow.id === itemUnitRow.id) {
    return true;
  }
  return (
    groupUnitRow.unit_group_id != null &&
    groupUnitRow.unit_group_id === itemUnitRow.unit_group_id
  );
}

async function getMaterialRowByBarcode(barcode) {
  const normalized = normalizeBarcode(barcode);
  const rows = await all('SELECT * FROM materials');
  return rows.find((item) => normalizeBarcode(item.barcode) === normalized) || null;
}

// The inventory module's service. What it needs from around it comes in by
// name: the entity links (which mount late), the photo DTO and the ledger,
// which are still defined here; items it asks at the kernel desk.
const inventoryService = createInventoryService({
  get,
  all,
  run,
  describeItem: (id) => itemsForInventory.describe(id),
  resolveLinks: (...args) => requireLinkResolver()(...args),
  writeLink: (...args) => requireLinkWriter()(...args),
  getPurgeEntityLinks: () => purgeEntityLinks,
  // Items is asked at the kernel desk (modules/items/client.js); the pure tree
  // walkers it needs are shared code, required by the service itself.
  items: itemsForInventory,
  rowToUploadedAssetDto,
  parseJson,
  resolveUnitPayload,
  // Asked of items at the kernel desk, under the names inventory has always
  // used for them.
  getGroupRowById: (id) => itemsForInventory.groups.rowById(id),
  getItemSelectionSnapshot: (itemId, leaf) => itemsForInventory.selectionSnapshot(itemId, leaf),
  saveGroup: (group) => itemsForInventory.groups.save(group),
  applyVariationStockDelta: (delta) => itemsForInventory.stock.applyDelta(delta),
  holdsWholeItemStock: (itemId) => itemsForInventory.stock.holdsWholeItemStock(itemId),
  normalizeChallanType,
  getMaterialRowByBarcode,
  recordLedgerEvent,
  // The stock overview reads four modules' data; each is asked for it.
  variationStockRows: () => itemsForInventory.variationStockRows(),
  desk: desk.as('inventory'),
  challans: challansClient(desk.as('inventory')),
});
// What other modules may ask of inventory.
const inventoryPorts = createInventoryPorts({ inventory: inventoryService, getMaterialRowByBarcode });
// The materials, governance and ledger functions moved with the service. Seeds,
// the production and challans code that still lives here, the items module's
// schema reads and the tests call them under the names they always had.
const {
  normalizeBarcode,
  rowToMaterialDto,
  createParentWithChildren,
  generateBarcodeFromItemSelection,
  generateStandaloneMaterialBarcode,
  ensureMaterialForItemSelection,
  getMaterialGroupGovernance,
  upsertInventoryStockPosition,
  applyInventoryMovementCore,
  applyInventoryMovement,
  updateMaterialGroupConfiguration,
  createChildMaterial,
  linkMaterialRecordToGroup,
  linkMaterialRecordToItem,
  unlinkMaterialRecord,
} = inventoryService;
// The challan core (read, save, issue, cancel, delete) lives in
// modules/challans/service.js. It is built here because it needs the inventory
// port, which exists from this point. The template, invoice and report services
// are built earlier and reach the challan readers through functions.
const challansService = createChallanService({
  get,
  all,
  run,
  logChange,
  parseJson,
  parseJsonOrArray,
  parseJsonObject,
  normalizeCustomVariationValues,
  rowToUploadedAssetDto,
  // The item's variation stock, asked of items at the kernel desk.
  itemStock: itemsForChallans.stock,
  desk: desk.as('challans'),
  rowToCompanyProfileDto,
  getActiveCompanyProfile,
  normalizeChallanType,
  buildChallanTemplateSnapshot,
  findActiveChallanTemplateForChallan,
  getItemSelectionSnapshot: (itemId, leaf) => itemsForChallans.selectionSnapshot(itemId, leaf),
  inventoryPorts: inventoryForChallans,
  recordLedgerEvent,
});
const {
  getDeliveryChallanOrderIds,
  normalizeReportGroupCode,
  effectiveReportGroupCodesForChallan,
  getOrderRowsByIds,
  rowToDeliveryChallanDto,
  generateChallanNumber,
  normalizeChallanDate,
  getDeliveryChallanRowById,
  listDeliveryChallans,
  saveDeliveryChallan,
  issueDeliveryChallan,
  cancelDeliveryChallan,
  deleteDraftDeliveryChallan,
} = challansService;

function firstActiveOrderableLeafIdFromTree(tree) {
  const walkProperty = (propertyNode) => {
    const valueNodes = activeChildrenForNode(propertyNode).filter(
      (node) => String(node.kind) === 'value',
    );
    for (const valueNode of valueNodes) {
      const childProperties = activeChildrenForNode(valueNode).filter(
        (node) => String(node.kind) === 'property',
      );
      if (childProperties.length === 0) {
        return Number(valueNode.id);
      }
      for (const childProperty of childProperties) {
        const found = walkProperty(childProperty);
        if (found) {
          return found;
        }
      }
    }
    return null;
  };

  for (const propertyNode of activeTopLevelVariationProperties(tree)) {
    const found = walkProperty(propertyNode);
    if (found) {
      return found;
    }
  }
  return null;
}

async function resolveMaterialSeedVariationLeafNodeId(itemId, explicitLeafNodeId = null) {
  const normalizedExplicitLeafId = Number(explicitLeafNodeId || 0);
  if (Number.isFinite(normalizedExplicitLeafId) && normalizedExplicitLeafId > 0) {
    return normalizedExplicitLeafId;
  }
  const tree = await getItemVariationTree(Number(itemId));
  if (activeTopLevelVariationProperties(tree).length === 0) {
    return null;
  }
  return firstActiveOrderableLeafIdFromTree(tree);
}

async function findParentMaterialByName(name) {
  return get(
    'SELECT * FROM materials WHERE kind = ? AND LOWER(TRIM(name)) = LOWER(TRIM(?)) LIMIT 1',
    ['parent', name],
  );
}

async function ensureParentMaterialRecord(seed) {
  let parent = await findParentMaterialByName(seed.name);
  if (!parent) {
    const created = await createParentWithChildren(seed);
    parent = await getMaterialRowByBarcode(created.barcode);
  }

  const now = new Date().toISOString();
  const resolvedUnit = await resolveUnitPayload(seed);
  const desiredChildren = Number(seed.numberOfChildren || 0);
  const existingChildren = await all(
    'SELECT * FROM materials WHERE parent_barcode = ? ORDER BY barcode ASC',
    [parent.barcode],
  );

  if (existingChildren.length < desiredChildren) {
    for (let index = existingChildren.length; index < desiredChildren; index += 1) {
      await createChildMaterial(parent.barcode, {
        name: `${seed.name} - Child ${index + 1}`,
        notes: seed.notes,
      });
    }
  }

  const childRows = await all(
    'SELECT * FROM materials WHERE parent_barcode = ? ORDER BY barcode ASC',
    [parent.barcode],
  );
  const linkedChildren = childRows.map((row) => row.barcode);

  await run(
    `
    UPDATE materials
    SET name = ?, type = ?, grade = ?, thickness = ?, supplier = ?, unit_id = ?, unit = ?, notes = ?,
        number_of_children = ?, linked_child_barcodes = ?, scan_count = ?
    WHERE id = ?
    `,
    [
      seed.name,
      seed.type,
      seed.grade || '',
      seed.thickness || '',
      seed.supplier || '',
      resolvedUnit.unitId,
      resolvedUnit.unit,
      seed.notes || '',
      linkedChildren.length,
      JSON.stringify(linkedChildren),
      Number(seed.scanCount || 0),
      parent.id,
    ],
  );

  for (let index = 0; index < childRows.length; index += 1) {
    const child = childRows[index];
    await run(
      `
      UPDATE materials
      SET name = ?, type = ?, grade = ?, thickness = ?, supplier = ?, unit_id = ?, unit = ?, notes = ?,
          scan_count = ?
      WHERE id = ?
      `,
      [
        `${seed.name} - Child ${index + 1}`,
        seed.type,
        seed.grade || '',
        seed.thickness || '',
        seed.supplier || '',
        resolvedUnit.unitId,
        resolvedUnit.unit,
        seed.notes || '',
        Array.isArray(seed.childScanCounts) ? Number(seed.childScanCounts[index] || 0) : 0,
        child.id,
      ],
    );
  }

  parent = await get('SELECT * FROM materials WHERE id = ?', [parent.id]);

  if (seed.linkGroupId) {
    parent = await linkMaterialRecordToGroup(parent.barcode, seed.linkGroupId);
  } else if (seed.linkItemId) {
    const variationLeafNodeId = await resolveMaterialSeedVariationLeafNodeId(
      seed.linkItemId,
      seed.linkVariationLeafNodeId,
    );
    parent = await linkMaterialRecordToItem(parent.barcode, seed.linkItemId, variationLeafNodeId);
  } else {
    parent = await unlinkMaterialRecord(parent.barcode);
  }

  await run('UPDATE materials SET created_at = ? WHERE id = ?', [seed.createdAt || now, parent.id]);
  for (let index = 0; index < childRows.length; index += 1) {
    await run('UPDATE materials SET created_at = ? WHERE id = ?', [seed.createdAt || now, childRows[index].id]);
  }

  return getMaterialRowByBarcode(parent.barcode);
}

async function ensureDemoMaterialsPresent() {
  const groups = await getGroupsWithUsage();
  const items = [];
  for (const row of await getItemsWithUsage()) {
    if (!row.is_archived) {
      items.push(await rowToItemDto(row));
    }
  }

  const groupByName = new Map(
    groups.map((group) => [normalizeUnitValue(group.name), group]),
  );
  const itemByDisplayName = new Map(
    items.map((item) => [normalizeUnitValue(item.displayName), item]),
  );

  const materials = [
    {
      name: 'Chemicals',
      type: 'Inventory Group',
      grade: 'Operational Root',
      thickness: '-',
      supplier: 'Central Store',
      unit: 'Kg',
      notes: 'Top-level inventory group for process chemicals.',
      numberOfChildren: 0,
      scanCount: 0,
      childScanCounts: [],
      createdAt: oneDayAgo(16),
      linkGroupId: groupByName.get('chemicals')?.id || null,
    },
    {
      name: 'Adhesives',
      type: 'Inventory Group',
      grade: 'Process Chemicals',
      thickness: '-',
      supplier: 'PolyBond Industries',
      unit: 'Kg',
      notes: 'Adhesive binders, hardeners, and bonding compounds.',
      numberOfChildren: 0,
      scanCount: 0,
      childScanCounts: [],
      createdAt: oneDayAgo(15),
      linkGroupId: groupByName.get('adhesives')?.id || null,
    },
    {
      name: 'Solvents',
      type: 'Inventory Group',
      grade: 'Process Chemicals',
      thickness: '-',
      supplier: 'CleanCore Labs',
      unit: 'Kg',
      notes: 'Cleaning and surface-preparation solvents.',
      numberOfChildren: 0,
      scanCount: 0,
      childScanCounts: [],
      createdAt: oneDayAgo(14),
      linkGroupId: groupByName.get('solvents')?.id || null,
    },
    {
      name: 'Inks',
      type: 'Inventory Group',
      grade: 'Process Chemicals',
      thickness: '-',
      supplier: 'ColorCraft Press',
      unit: 'Kg',
      notes: 'Press inks and color concentrates used in packaging runs.',
      numberOfChildren: 0,
      scanCount: 0,
      childScanCounts: [],
      createdAt: oneDayAgo(13),
      linkGroupId: groupByName.get('inks')?.id || null,
    },
    {
      name: 'Epoxy Resin Base Lot',
      type: 'Raw Material',
      grade: 'Standard',
      thickness: '-',
      supplier: 'PolyBond Industries',
      unit: 'Kg',
      notes: 'Primary resin feed for adhesive preparation.',
      numberOfChildren: 0,
      scanCount: 7,
      childScanCounts: [],
      createdAt: oneDayAgo(10),
      linkItemId:
          itemByDisplayName.get(normalizeUnitValue('Epoxy Resin Base - 25'))?.id || null,
    },
    {
      name: 'Hardener Compound Batch',
      type: 'Raw Material',
      grade: 'Fast Set',
      thickness: '-',
      supplier: 'PolyBond Industries',
      unit: 'Kg',
      notes: 'Hardener stock paired with epoxy resin jobs.',
      numberOfChildren: 0,
      scanCount: 4,
      childScanCounts: [],
      createdAt: oneDayAgo(8),
      linkItemId:
          itemByDisplayName.get(normalizeUnitValue('Hardener Compound - 5'))?.id || null,
    },
    {
      name: 'Isopropyl Cleaner Drum',
      type: 'Raw Material',
      grade: '99%',
      thickness: '-',
      supplier: 'CleanCore Labs',
      unit: 'Kg',
      notes: 'Cleaner used for cylinder, plate, and surface preparation.',
      numberOfChildren: 0,
      scanCount: 5,
      childScanCounts: [],
      createdAt: oneDayAgo(6),
      linkItemId:
          itemByDisplayName.get(normalizeUnitValue('Isopropyl Cleaner - 20'))?.id || null,
    },
    {
      name: 'Cyan Flexo Ink Barrel',
      type: 'Raw Material',
      grade: 'Process Cyan',
      thickness: '-',
      supplier: 'ColorCraft Press',
      unit: 'Kg',
      notes: 'Press cyan ink used on flexo export sleeve and carton jobs.',
      numberOfChildren: 0,
      scanCount: 6,
      childScanCounts: [],
      createdAt: oneDayAgo(5),
      linkItemId:
          itemByDisplayName.get(normalizeUnitValue('Cyan Flexo Ink - 15'))?.id || null,
    },
    {
      name: 'Kraft Paper Reel',
      type: 'Raw Material',
      grade: '150 GSM',
      thickness: '-',
      supplier: 'GreenFiber Mills',
      unit: 'Sheet',
      notes: 'Primary kraft stock staged for cutting and conversion runs.',
      numberOfChildren: 2,
      scanCount: 9,
      childScanCounts: [3, 2],
      createdAt: oneDayAgo(4),
      linkGroupId: groupByName.get('kraft')?.id || null,
    },
    {
      name: 'Shrink Film Reel',
      type: 'Raw Material',
      grade: 'Clear LD',
      thickness: '35 micron',
      supplier: 'PackFilm Co',
      unit: 'Roll',
      notes: 'Film reel for sleeve and packing runs.',
      numberOfChildren: 2,
      scanCount: 8,
      childScanCounts: [2, 1],
      createdAt: oneDayAgo(4),
      linkItemId:
          itemByDisplayName.get(normalizeUnitValue('Printed Sleeve - 200'))?.id || null,
    },
    {
      name: 'Steel Sheet Batch',
      type: 'Raw Material',
      grade: 'Utility',
      thickness: '1.2 mm',
      supplier: 'Metro Metals',
      unit: 'Pieces',
      notes: 'Sheet batch reserved for dolly demo production scans.',
      numberOfChildren: 2,
      scanCount: 5,
      childScanCounts: [1, 1],
      createdAt: oneDayAgo(3),
      linkGroupId: groupByName.get('packaging components')?.id || null,
    },
  ];

  for (const material of materials) {
    await ensureParentMaterialRecord(material);
  }
}

async function ensureDemoPipelineRunsPresent() {
  const kraft = await findParentMaterialByName('Kraft Paper Reel');
  const shrink = await findParentMaterialByName('Shrink Film Reel');
  const steel = await findParentMaterialByName('Steel Sheet Batch');
  if (!kraft || !shrink || !steel) {
    return;
  }

  await ensurePipelineRunRecord({
    id: 'demo-dolly-run-active',
    templateId: 'dolly',
    name: 'Dolly Morning Batch',
    status: 'inProgress',
    createdAt: oneDayAgo(2),
    startedAt: oneDayAgo(2),
    nodeStatuses: {
      'dolly-input-copper': 'completed',
      'dolly-cut': 'completed',
      'dolly-input-steel': 'completed',
      'dolly-drill': 'inProgress',
      'dolly-weld': 'blocked',
      'dolly-polish': 'pending',
    },
    overrides: {
      actualDurationHoursByNode: {
        'dolly-cut': 1.1,
        'dolly-drill': 1.8,
      },
      batchQuantityByNode: {
        'dolly-cut': 1800,
        'dolly-drill': 1800,
      },
      machineOverrideByNode: {
        'dolly-drill': 'Drill 02B',
      },
    },
    barcodeAssignments: [
      {
        id: 'demo-dolly-barcode-1',
        nodeId: 'dolly-input-copper',
        barcode: kraft.barcode,
        scannedAt: oneDayAgo(2),
      },
      {
        id: 'demo-dolly-barcode-2',
        nodeId: 'dolly-input-steel',
        barcode: steel.barcode,
        scannedAt: oneDayAgo(2),
      },
    ],
  });

  await ensurePipelineRunRecord({
    id: 'demo-assembly-run-packed',
    templateId: 'assembly',
    name: 'Assembly Export Lot',
    status: 'completed',
    createdAt: oneDayAgo(5),
    startedAt: oneDayAgo(5),
    completedAt: oneDayAgo(4),
    nodeStatuses: {
      'assembly-right': 'completed',
      'assembly-left': 'completed',
      'assembly-center': 'completed',
      'assembly-fixture': 'completed',
      'assembly-pack': 'completed',
    },
    overrides: {
      actualDurationHoursByNode: {
        'assembly-fixture': 1.3,
        'assembly-pack': 0.7,
      },
      batchQuantityByNode: {
        'assembly-fixture': 900,
        'assembly-pack': 900,
      },
      machineOverrideByNode: {},
    },
    barcodeAssignments: [
      {
        id: 'demo-assembly-barcode-1',
        nodeId: 'assembly-center',
        barcode: shrink.barcode,
        scannedAt: oneDayAgo(5),
      },
    ],
  });

  await ensurePipelineRunRecord({
    id: 'demo-dolly-run-queued',
    templateId: 'dolly',
    name: 'Dolly Evening Batch',
    status: 'planned',
    createdAt: oneDayAgo(1),
    nodeStatuses: {
      'dolly-input-copper': 'pending',
      'dolly-cut': 'pending',
      'dolly-input-steel': 'pending',
      'dolly-drill': 'pending',
      'dolly-weld': 'pending',
      'dolly-polish': 'pending',
    },
    overrides: {
      actualDurationHoursByNode: {},
      batchQuantityByNode: {
        'dolly-cut': 2400,
      },
      machineOverrideByNode: {},
    },
  });
}

// registerAccountsRoutesBeforeLogin: its routes are in modules/accounts/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const accountsBeforeLoginRouter = express.Router();
app.use(accountsBeforeLoginRouter);

// registerRealtimeRoutesBeforeLogin: its routes are in modules/realtime/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const realtimeBeforeLoginRouter = express.Router();
app.use(realtimeBeforeLoginRouter);
// GET /api/system/status and /api/system/metrics (kernel/system-routes.js),
// registered further down; each carries its own guard.
const systemBeforeLoginRouter = express.Router();
app.use(systemBeforeLoginRouter);

app.get('/api/delivery-challans/health', (_req, res) => {
  res.json({
    success: true,
    module: 'delivery-challans',
  });
});

// The local store's two doors. Before the login gate: the signature in the
// URL is the permission, as it is for a presigned S3 URL, and an <img> sends
// no bearer token.
app.put(
  '/api/assets/local/*key',
  express.raw({ type: () => true, limit: '26mb' }),
  async (req, res) => {
    try {
      const objectKey = localObjectKeyFrom(req);
      assertLocalUploadSigned(req, 'PUT', objectKey);
      const contentType = String(req.headers['content-type'] || '').toLowerCase();
      // A company's document may be any file (and up to 25 MB); everything
      // else in the store is a photo.
      const isDocument = isDocumentObjectKey(objectKey);
      if (!isDocument && !ALLOWED_ASSET_CONTENT_TYPES.has(contentType.split(';')[0].trim())) {
        res.status(415).json({ success: false, error: 'Only PNG, JPG and WEBP images can be stored.' });
        return;
      }
      if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
        res.status(400).json({ success: false, error: 'The file was empty.' });
        return;
      }
      if (req.body.length > (isDocument ? MAX_DOCUMENT_BYTES : 11 * 1024 * 1024)) {
        res.status(413).json({ success: false, error: 'The file is too large.' });
        return;
      }
      const target = localUploadPath(objectKey);
      await fs.promises.mkdir(path.dirname(target), { recursive: true });
      await fs.promises.writeFile(target, req.body);
      res.status(200).end();
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, error: error.message });
    }
  },
);

// registerAssetsRoutesBeforeLogin: its routes are in modules/assets/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const assetsBeforeLoginRouter = express.Router();
app.use(assetsBeforeLoginRouter);

app.use('/api', (req, res, next) => {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
  next();
});
app.use('/api', requireAuth);
app.use('/api', requireApiModulePermission);
app.use('/api', requireApiWritePermission);
// After the permission checks: a write refused for permission is not an
// operation, and must not take its idempotency key.
app.use('/api', idempotency.middleware);

app.use('/api', (req, res, next) => {
  if (['POST', 'PUT', 'DELETE', 'PATCH'].includes(req.method)) {
    const originalSend = res.send;
    res.send = function (body) {
      if (res.statusCode >= 200 && res.statusCode < 300 && req.user) {
        try {
          const parsed = JSON.parse(body);
          if (parsed && parsed.success === false) {
            // It failed logically even if HTTP status was 200, skip logging
          } else {
            let entityType = req.path.split('/')[1] || 'unknown';
            if (entityType === 'auth') {
              entityType = req.path.split('/')[2] || 'auth';
            }
            let action = req.method;
            
            // Do not block response, fire and forget
            logGlobalAudit({
              actorUserId: req.user.id,
              actorName: req.user.name,
              actorRole: req.user.role,
              action,
              entityType,
              details: { path: req.path, method: req.method },
              ipAddress: getRequestIp(req)
            }).catch(err => console.error('[Audit] Failed to log:', err));
          }
        } catch (e) {
          // If response body is not JSON, we still log it.
          let entityType = req.path.split('/')[1] || 'unknown';
          let action = req.method;
          logGlobalAudit({
            actorUserId: req.user.id,
            actorName: req.user.name,
            actorRole: req.user.role,
            action,
            entityType,
            details: { path: req.path, method: req.method },
            ipAddress: getRequestIp(req)
          }).catch(err => console.error('[Audit] Failed to log:', err));
        }
      }
      originalSend.call(this, body);
    };
  }
  next();
});

// registerAccountsRoutes: its routes are in modules/accounts/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const accountsRouter = express.Router();
app.use(accountsRouter);

// registerTrackRoutes: its routes are in modules/track/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const trackRouter = express.Router();
app.use(trackRouter);

// Sittings — what was done in one opening of one window.
//
// DECLARED BEFORE `/api/track/:entityType/:id`, which would otherwise match
// `/api/track/sittings` with entityType = 'sittings' and answer an empty list.
// The `actor` route above is ordered for the same reason.
//
// Both require `audit.read`, not the weaker `config.read` the per-record route
// below uses: a sitting shows everything a person did in a span of minutes,
// across every master, which is a wider view than one record's history.
// Who may see whose activity, in the one dialect this codebase already speaks.
//
// Lifted out of `/api/audit/global`, which has scoped its reads this way all
// along: super_admin sees everything, an admin sees their own plus anything a
// plain user did, everyone else sees only their own. A sitting is a wider view
// than one record's history — minutes of somebody's work across every master —
// so it is scoped like the audit feed rather than like the unscoped
// `/api/track/*` routes beside it.
//
// Returns SQL fragments to AND into a WHERE, plus the params they need.
function actorScopeFor(req, column = 'actor_user_id', roleColumn = 'actor_role') {
  if (req.user?.role === 'super_admin') return { sql: null, params: [] };
  if (req.user?.role === 'admin') {
    return {
      sql: `(${column} = ? OR ${roleColumn} = ?)`,
      params: [req.user.id, 'user'],
    };
  }
  return { sql: `${column} = ?`, params: [req.user?.id ?? null] };
}

// --- Named presets (admin-authored roles) ----------------------------------
function normalizeTemplatePermissionKeys(input) {
  const requested = Array.isArray(input)
    ? input
    : Object.entries(input || {})
        .filter(([, v]) => v === true)
        .map(([k]) => k);
  return [
    ...new Set(
      requested.map((k) => normalizePermissionKey(k)).filter(isKnownPermissionKey),
    ),
  ];
}

// A non-super_admin cannot bake a permission they lack into a preset.
function firstUngrantableKey(req, keys) {
  if (req.user.role === 'super_admin') return null;
  return keys.find((k) => req.userPermissions?.[k] !== true) || null;
}

// The machine master left for modules/machines. Its DTO is still called here
// by the production report and trace (they shape machines they have already
// read), so it comes out of the service under the name they know. Whether a
// live run holds a machine is asked of the production port.
const machinesService = createMachineService({ get, all, run, parseJson, desk: desk.as('machines') });
const { rowToMachineDto: machineRowToDto } = machinesService;
const productionPorts = createProductionPorts({ get, all, run });

// The die master left for modules/dies. Its DTO is still called here by the
// production report and trace, so it comes out of the service under the name
// they know. A die's client is an entity link, and the links module mounts late,
// so the link calls are wrapped: they look the function up when they run, and
// throw if it is not mounted yet, as requireLinkResolver/Writer always have.
const diesService = createDieService({
  get,
  all,
  run,
  parseJson,
  desk: desk.as('dies'),
  resolveLinks: (...args) => requireLinkResolver()(...args),
  writeLink: (...args) => requireLinkWriter()(...args),
});
const { rowToDieDto: dieRowToDto } = diesService;

// registerSearchRoutes: its routes are in modules/search/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const searchRouter = express.Router();
app.use(searchRouter);

// registerUnitMasterRoutes: its routes are in modules/units/master-routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const unitMasterRouter = express.Router();
app.use(unitMasterRouter);

// registerSettingsRoutes: its routes are in modules/settings/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const settingsRouter = express.Router();
app.use(settingsRouter);

function actorFromRequest(req) {
  return {
    id: req.user?.id || null,
    name: req.user?.name || 'System',
    role: req.user?.role || 'system',
  };
}

app.post(
  '/api/admin/reset-demo-data',
  requireRoles('super_admin', 'admin'),
  requirePermission('config.write'),
  async (req, res) => {
    try {
      const scenarioId = req.body?.scenarioId || 'default';
      await resetAndSeedDemoData(scenarioId);
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        error: error.message,
      });
    }
  },
);

// The nuke: deletes every row in every table, then re-bootstraps the super
// admin and the primary group/unit so the app can still be signed into.
// super_admin only, and the caller must echo the confirmation phrase — this is
// the one endpoint where an accidental or scripted POST is unrecoverable.
const FACTORY_RESET_CONFIRMATION = 'FACTORY RESET';
console.log('Registering /api/admin/factory-reset route...');
app.post(
  '/api/admin/factory-reset',
  requireRoles('super_admin'),
  async (req, res) => {
    try {
      if (String(req.body?.confirm || '').trim() !== FACTORY_RESET_CONFIRMATION) {
        const error = new Error(
          `Factory reset requires confirm: "${FACTORY_RESET_CONFIRMATION}".`,
        );
        error.statusCode = 400;
        throw error;
      }
      // Written to stdout, not the DB: entity_activity_log is one of the tables
      // this is about to delete, so the only durable record is the server log.
      console.warn(
        '[factory-reset] wiping all data — actor:',
        JSON.stringify({
          userId: req.user?.id ?? null,
          email: req.user?.email ?? null,
          role: req.user?.role ?? null,
          at: new Date().toISOString(),
          ip: req.ip,
        }),
      );
      await factoryResetData();
      console.warn('[factory-reset] complete');
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        error: error.message,
      });
    }
  },
);

console.log('Registering /api/admin/clear-data route...');
app.post(
  '/api/admin/clear-data',
  requireRoles('super_admin', 'admin'),
  requirePermission('config.write'),
  async (_req, res) => {
    try {
      await clearAllData();
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        error: error.message,
      });
    }
  },
);

app.post(
  '/api/admin/reseed-data',
  requireRoles('super_admin', 'admin'),
  requirePermission('config.write'),
  async (req, res) => {
    try {
      const scenarioId = req.body?.scenarioId || 'default';
      await reseedDemoData(scenarioId);
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({
        success: false,
        error: error.message,
      });
    }
  },
);

// Reconciliation settles the consumed WEIGHT (kg), so the reverted lots/items
// are measured in kilograms. Reuse an existing kg unit or create one.
// registerAssetsRoutes: its routes are in modules/assets/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const assetsRouter = express.Router();
app.use(assetsRouter);

// ---------------------------------------------------------------------------
// The universal resolver: one code in, everything we know about it out.
//
// This is what makes a single code space worth having. A scanner gun does not
// know whether it is pointed at a sheet, a challan, a machine or a person's
// badge, and it should not have to — the code carries its own type, so this
// dispatches on the code rather than searching every table in turn.
//
// The envelope is the same shape whatever resolved, so one screen renders all
// of them:
//
//   resolution  how it was found, and whether the check character verified
//   entity      what it is: type, id, title, subtitle
//   facts       the summary rows worth reading at a glance
//   custody     the ledger, oldest first — who touched it and when
//
// `resolution` is not decoration. A code found by falling back to a legacy
// column is a weaker answer than one that decoded and verified, and a screen
// that cannot tell them apart will present a guess as a fact.
// ---------------------------------------------------------------------------

const TITLES = {
  MAT: (row) => ({ title: row.name || row.barcode, subtitle: [row.type, row.grade].filter(Boolean).join(' · ') }),
  DC: (row) => ({ title: `Delivery ${row.challan_no}`, subtitle: row.customer_name || '' }),
  RC: (row) => ({ title: `Reception ${row.challan_no}`, subtitle: row.vendor_name || '' }),
  DCL: (row) => ({ title: row.particulars || `Line ${row.line_no}`, subtitle: `Challan line ${row.line_no}` }),
  ORD: (row) => ({ title: `Order ${row.order_no}`, subtitle: '' }),
  RUN: (row) => ({ title: row.name || row.id, subtitle: row.status || '' }),
  MFG: (row) => ({ title: row.run_code, subtitle: row.status || '' }),
  EMP: (row) => ({ title: row.name, subtitle: row.role || row.designation || '' }),
  DEP: (row) => ({ title: row.name, subtitle: row.description || '' }),
  PLN: (row) => ({ title: row.name, subtitle: row.description || '' }),
  CLI: (row) => ({ title: row.name, subtitle: row.gstin || row.city || '' }),
  VEN: (row) => ({ title: row.name, subtitle: row.gstin || row.city || '' }),
  MCH: (row) => ({ title: row.name, subtitle: row.asset_id || '' }),
  DIE: (row) => ({ title: row.name || row.tool_code, subtitle: row.tool_code || '' }),
  ITM: (row) => ({ title: row.display_name || row.name, subtitle: row.short_code || '' }),
  GRP: (row) => ({ title: row.name, subtitle: row.group_structure || '' }),
  MOV: (row) => ({ title: `${row.movement_type} ${row.qty}`, subtitle: row.material_barcode || '' }),
  LOC: (row) => ({ title: row.place || row.location_id, subtitle: 'Storage location' }),
  FLR: (row) => ({ title: row.place || row.location, subtitle: 'Shop floor' }),
};

/// Reads the row a decoded code names, honouring the type's own scoping — a DC
/// and an RC are the same table and are told apart by the challan's type, so
/// scanning a reception challan with a DC prefix must not quietly resolve.
async function loadSubject({ all }, type, id) {
  const spec = barcodes.TYPES[type];
  if (!spec) return null;

  // Places are matched by normalised value, not by key. A location is a
  // free-text string ('Cutting bay', 'Rack A1') and a code strips whitespace,
  // so 'Cutting bay' arrives as CUTTINGBAY and no column compare would ever
  // find it. Matching is done here rather than in SQL because SQLite's REPLACE
  // handles one character at a time and `barcodes.normalize` is the same
  // function that produced the code.
  if (spec.place) {
    const wanted = barcodes.normalize(id);
    if (!wanted) return null;
    const rows = await all(
      `SELECT DISTINCT ${spec.idColumn} AS value FROM ${spec.table}
       WHERE TRIM(COALESCE(${spec.idColumn}, '')) != ''`,
    );
    const match = rows.find((row) => barcodes.normalize(row.value) === wanted);
    // A synthetic row: the place has no record of its own, so it is represented
    // by the one thing that is true of it — its name, exactly as stored.
    return match ? { [spec.idColumn]: match.value, place: match.value } : null;
  }

  const where = spec.where ? ` AND ${spec.where}` : '';
  // Compared case-insensitively on purpose. Barcode symbologies are uppercase —
  // Code 39 has no lowercase at all — so an emitted code is uppercased, but
  // plenty of ids are not: a pipeline template is `sheet-metal-flow` and a run
  // is `demo-dolly-run-active`. Matching case-sensitively meant those codes
  // encoded and decoded perfectly and then resolved to nothing, which is the
  // most confusing failure available: the code looks right and finds nothing.
  const rows = await all(
    `SELECT * FROM ${spec.table} WHERE ${spec.idColumn} = ? COLLATE NOCASE${where} LIMIT 1`,
    [id],
  );
  return rows[0] || null;
}

/// The ledger for a subject, oldest first. This is the custody trail: what the
/// business tables cannot say because they are rewritten in place.
async function loadCustody({ all }, subjectBarcode) {
  try {
    return await all(
      `SELECT event_id, event_type, actor_barcode, actor_name, location_barcode,
              machine_barcode, die_barcode, parent_barcodes_json,
              child_barcodes_json, order_barcode, document_barcode,
              metrics_json, notes, created_at
       FROM barcode_ledger
       WHERE subject_barcode = ?
          OR parent_barcodes_json LIKE '%' || ? || '%'
          OR child_barcodes_json LIKE '%' || ? || '%'
          -- Places are reachable too. A location is never a subject, a parent
          -- or a child — a rack does not descend from anything — so without
          -- this a scanned rack resolves and then shows an empty history,
          -- which reads as "nothing ever happened here" rather than "this view
          -- cannot see it".
          OR location_barcode = ?
       ORDER BY created_at ASC, id ASC
       LIMIT 500`,
      [subjectBarcode, subjectBarcode, subjectBarcode, subjectBarcode],
    );
  } catch (_) {
    // A missing ledger is an empty history, not a failed scan.
    return [];
  }
}

/// Searches the codes that were already printed before this scheme existed.
/// Ordered and first-match-wins, so the most specific source answers.
async function resolveLegacy(ctx, code) {
  for (const source of barcodes.LEGACY_SOURCES) {
    const rows = await ctx.all(
      `SELECT * FROM ${source.table} WHERE ${source.column} = ? COLLATE NOCASE LIMIT 1`,
      [code],
    );
    if (rows[0]) {
      return { type: source.type, row: rows[0], via: 'legacy-code', column: source.column };
    }
  }
  return null;
}

async function resolveBarcode(ctx, rawCode) {
  const code = barcodes.normalize(rawCode);
  if (!code) {
    const error = new Error('A code is required.');
    error.statusCode = 400;
    throw error;
  }

  const decoded = barcodes.decode(code);
  let type = null;
  let row = null;
  let via = null;
  let checkValid = true;
  let hasCheck = false;

  if (decoded) {
    hasCheck = decoded.hasCheck;
    checkValid = decoded.checkValid;
    // A failed check is reported, not obeyed. The record it *would* have named
    // is still loaded so the screen can say "this scanned as X — is that what
    // you are holding?", which is far more use than a bare rejection.
    type = decoded.type;
    row = await loadSubject(ctx, decoded.type, decoded.id);
    via = row ? 'structured' : null;
  }

  if (!row) {
    const legacy = await resolveLegacy(ctx, code);
    if (legacy) {
      type = legacy.type;
      row = legacy.row;
      via = legacy.via;
    }
  }

  if (!row) {
    return {
      found: false,
      code,
      resolution: {
        via: null,
        // The distinction the old lookup could not make: a code shaped like
        // ours that names nothing is a different problem from a code that was
        // never ours, and they need different answers from the person holding
        // the scanner.
        looksLikeOurs: decoded != null,
        hasCheck,
        checkValid,
      },
      entity: null,
      facts: [],
      custody: [],
    };
  }

  const spec = barcodes.TYPES[type];
  const identity = (TITLES[type] || ((r) => ({ title: String(r.id ?? ''), subtitle: '' })))(row);
  const canonicalId = String(row[spec.idColumn] ?? '');
  const canonical = barcodes.encode(type, canonicalId);

  const facts = [];
  const push = (label, value) => {
    if (value === null || value === undefined || value === '') return;
    facts.push({ label, value: String(value) });
  };
  push('Type', spec.label);
  push('Status', row.status);
  push('Created', row.created_at);
  push('Updated', row.updated_at);
  if (row.is_archived != null) push('Archived', Number(row.is_archived) ? 'Yes' : 'No');

  // A place has no row of its own, so the only useful thing to say about it is
  // what is currently there. Scanning a rack to be told "this is a rack" would
  // be worse than not resolving at all.
  if (spec.place && type === 'LOC') {
    const held = await ctx.all(
      `SELECT COUNT(DISTINCT material_barcode) AS kinds,
              COALESCE(SUM(on_hand_qty), 0) AS total
       FROM inventory_stock_positions
       WHERE location_id = ? COLLATE NOCASE AND COALESCE(on_hand_qty, 0) > 0`,
      [canonicalId],
    );
    push('Distinct materials here', held[0]?.kinds ?? 0);
    push('Total on hand', held[0]?.total ?? 0);
    const recent = await ctx.all(
      `SELECT m.name, p.on_hand_qty
       FROM inventory_stock_positions p
       LEFT JOIN materials m ON m.barcode = p.material_barcode
       WHERE p.location_id = ? COLLATE NOCASE AND COALESCE(p.on_hand_qty, 0) > 0
       ORDER BY p.on_hand_qty DESC LIMIT 5`,
      [canonicalId],
    );
    for (const line of recent) {
      push(line.name || 'Material', line.on_hand_qty);
    }
  }

  if (spec.place && type === 'FLR') {
    const machines = await ctx.all(
      'SELECT name, status FROM machines WHERE location = ? COLLATE NOCASE ORDER BY name',
      [canonicalId],
    );
    push('Machines here', machines.length);
    for (const machine of machines.slice(0, 8)) {
      push(machine.name || 'Machine', machine.status || 'idle');
    }
  }

  return {
    found: true,
    code,
    resolution: {
      via,
      looksLikeOurs: decoded != null,
      hasCheck,
      checkValid,
      // What the label *should* say, so a screen can offer to reprint a legacy
      // code in the scheme rather than leaving it outside forever.
      canonical,
    },
    entity: {
      type,
      typeLabel: spec.label,
      id: canonicalId,
      title: identity.title || canonicalId,
      subtitle: identity.subtitle || '',
    },
    facts,
    custody: (await loadCustody(ctx, canonical || code)).map((event) => ({
      eventId: event.event_id,
      eventType: event.event_type,
      actor: event.actor_name || event.actor_barcode || '',
      actorBarcode: event.actor_barcode || null,
      locationBarcode: event.location_barcode || null,
      machineBarcode: event.machine_barcode || null,
      dieBarcode: event.die_barcode || null,
      parents: parseJsonOrArray(event.parent_barcodes_json, []),
      children: parseJsonOrArray(event.child_barcodes_json, []),
      orderBarcode: event.order_barcode || null,
      documentBarcode: event.document_barcode || null,
      metrics: parseJsonOrArray(event.metrics_json, {}),
      notes: event.notes || '',
      at: event.created_at,
    })),
  };
}

/// Appends one custody event. Never throws into the caller: a business action
/// must not fail because its audit trail could not be written, and a lost event
/// is recoverable where a refused dispatch is not.
async function recordLedgerEvent(input = {}) {
  try {
    const eventId = `evt-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    await run(
      `INSERT INTO barcode_ledger (
         event_id, subject_barcode, event_type, actor_barcode, actor_name,
         location_barcode, machine_barcode, die_barcode,
         parent_barcodes_json, child_barcodes_json,
         order_barcode, document_barcode, metrics_json, notes, created_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        eventId,
        barcodes.normalize(input.subjectBarcode || ''),
        String(input.eventType || 'UNKNOWN'),
        input.actorBarcode || null,
        String(input.actorName || ''),
        input.locationBarcode || null,
        input.machineBarcode || null,
        input.dieBarcode || null,
        JSON.stringify(input.parents || []),
        JSON.stringify(input.children || []),
        input.orderBarcode || null,
        input.documentBarcode || null,
        JSON.stringify(input.metrics || {}),
        String(input.notes || ''),
        new Date().toISOString(),
      ],
    );
    return eventId;
  } catch (_) {
    return null;
  }
}

// A client's or contractor's documents (uploaded_assets.document_title): named files of any
// kind, kept beside its photos but never one of them.
app.get(
  '/api/assets/documents',
  requireAssetEntityPermission('read', (req) => req.query?.entityType),
  async (req, res) => {
    try {
      const documents = await listDocumentsForEntity(req.query?.entityType, req.query?.entityId);
      res.json({ success: true, documents, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, documents: [], error: error.message });
    }
  },
);

async function closePhotoRequest(req, res, status, assetId = null) {
  try {
    const row = await ownPhotoRequest(req);
    if (row.status !== 'pending') {
      throw photoRequestError(`This photo request is already ${row.status}.`, 409);
    }
    await run('UPDATE photo_requests SET status = ?, asset_id = ?, updated_at = ? WHERE id = ?', [
      status,
      assetId,
      nowIso(),
      row.id,
    ]);
    announcePhotoRequests(row.user_id);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, error: error.message });
  }
}

app.use('/templates', requireAuth);
app.use('/templates', requireApiWritePermission);
app.use('/runs', requireAuth);
app.use('/runs', requireApiWritePermission);
app.use('/templates', (req, res, next) => {
  if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') {
    next();
    return;
  }
  if (!hasPermission(req, 'config.write')) {
    res.status(403).json({ success: false, error: 'You do not have permission for this action.' });
    return;
  }
  next();
});
app.use('/runs', (req, res, next) => {
  if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') {
    next();
    return;
  }
  if (!hasPermission(req, 'config.write')) {
    res.status(403).json({ success: false, error: 'You do not have permission for this action.' });
    return;
  }
  next();
});

Sentry.setupExpressErrorHandler(app);

app.use('/api', (error, req, res, _next) => {
  console.error(`[API ERROR] ${req.method} ${req.originalUrl}`, error);
  const message = error.message || 'Internal server error';
  res.status(error.statusCode || error.status || 500).json({
    success: false,
    message,
    error: message,
  });
});

// Tables a factory reset leaves alone. Everything else — accounts, items,
// stock, orders, audit — is gone.
const FACTORY_RESET_PRESERVED_TABLES = [
  // The migration ledger is schema state, not workspace data. Wiping it
  // re-runs every migration on the next boot, and 034's INSERT OR IGNORE
  // would quietly put back any default material the shop had deleted.
  'schema_migrations',
  // The material master is reference data, not workspace data: a density is
  // a property of steel, not of this shop's transactions. A shop that has
  // registered its own alloys should not have to retype them after a reset.
  'material_types',
];

async function factoryResetData() {
  await run('PRAGMA foreign_keys = OFF');
  await run('BEGIN TRANSACTION');
  try {
    const allTables = await all("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    for (const table of allTables) {
      if (FACTORY_RESET_PRESERVED_TABLES.includes(table.name)) continue;
      await run("DELETE FROM " + table.name + "");
    }
    await bootstrapSuperAdminIfNeeded();
    await ensurePrimaryGroupAndUnit();
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  } finally {
    await run('PRAGMA foreign_keys = ON').catch(() => {});
  }
}

async function clearAllData() {
  await run('PRAGMA foreign_keys = OFF');
  await run('BEGIN TRANSACTION');
  try {
    const allTables = await all("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    const preserveTables = [
      // The migration ledger is schema state, not workspace data. Wiping it
      // made every reset re-run all 29 migrations on the next boot.
      'schema_migrations',
      'users',
      'auth_sessions',
      'auth_events',
      'role_permissions',
      'user_permission_overrides',
      'permission_templates',
      'permission_template_permissions',
      'user_permission_templates',
      // Reference data, not workspace data: a density is a property of steel,
      // not of this shop's transactions. Wiping it left every sheet plan
      // unable to weigh itself until someone retyped the periodic table.
      'material_types',
      // Same kind of thing: which stages this factory HAS is a fact about the
      // factory, not a transaction in it. Shearing does not stop existing
      // because the workspace was cleared. It also could not come back on its
      // own — the seed lives in migration 052 and `schema_migrations` is
      // preserved two lines up, so a cleared stage master would have stayed
      // empty. The routes BUILT from these stages are workspace data and are
      // wiped with everything else.
      'process_stages'
    ];
    // The custody ledger is append-only, enforced by triggers, so an ordinary
    // DELETE is refused — which is the point of it, and which stops this loop
    // dead.
    //
    // A deliberate workspace reset is the one thing allowed past that, and the
    // exemption is written out here rather than hidden in a trigger condition:
    // wiping provenance takes explicitly removing its protection first, and
    // anyone reading this can see that is what happened. Leaving the rows
    // behind would be worse than removing them — provenance for records that no
    // longer exist is not history, it is a set of dangling claims.
    await run('DROP TRIGGER IF EXISTS barcode_ledger_no_update').catch(() => {});
    await run('DROP TRIGGER IF EXISTS barcode_ledger_no_delete').catch(() => {});

    // The changelog triggers come off too, for a different reason: they work.
    // Deleting every row of seventeen tables would otherwise write a changelog
    // entry per row — tens of thousands of them — describing the disappearance
    // of a workspace that is about to be replaced wholesale. Both families, or
    // the derived ones would keep firing against parents already gone.
    const liveChangelogTriggers = await all(
      `SELECT name FROM sqlite_master WHERE type = 'trigger'
         AND (name LIKE 'trg_changelog_%' OR name LIKE 'trg_derived_%')`,
    ).catch(() => []);
    for (const trigger of liveChangelogTriggers) {
      await run(`DROP TRIGGER IF EXISTS ${trigger.name}`).catch(() => {});
    }

    for (const table of allTables) {
      if (!preserveTables.includes(table.name)) {
        await run("DELETE FROM " + table.name + "");
      }
    }

    // Protection goes straight back on. A window where the ledger is writable
    // must not outlive the reset that opened it.
    await run(`
      CREATE TRIGGER IF NOT EXISTS barcode_ledger_no_update
      BEFORE UPDATE ON barcode_ledger
      BEGIN
        SELECT RAISE(ABORT, 'barcode_ledger is append-only: a custody record cannot be edited after the fact');
      END
    `).catch(() => {});
    await run(`
      CREATE TRIGGER IF NOT EXISTS barcode_ledger_no_delete
      BEFORE DELETE ON barcode_ledger
      BEGIN
        SELECT RAISE(ABORT, 'barcode_ledger is append-only: a custody record cannot be deleted');
      END
    `).catch(() => {});

    // Put the changelog triggers back. Protection that a reset removes and
    // does not restore quietly stops existing after the first reset — the
    // same reason the ledger's own triggers are recreated just above.
    await restoreChangelogTriggers();

    await ensurePrimaryGroupAndUnit();
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  } finally {
    await run('PRAGMA foreign_keys = ON').catch(() => {});
  }
}
// "Mobiles" demo scenario: a single item (Smartphone X) exercising 5 top-level
// variation properties, each with 5 values. Creates the Mobiles group, then
// delegates item creation to ensureDemoItemsPresent('mobiles'). Idempotent.
async function ensureDemoMobilesPresent(scenarioId = 'default') {
  if (scenarioId !== 'mobiles') {
    return;
  }

  const now = new Date().toISOString();

  // Mobiles are counted in pieces; ensure that unit exists and resolve it.
  const pieceUnit = await ensureUnitRecord({
    name: 'Piece',
    symbol: 'Pc',
    notes: 'Mobiles scenario',
  });

  const mobilesGroup = await ensureGroupRecord({
    name: 'Mobiles',
    unitId: pieceUnit.id,
  });

  // Create the item(s) via the shared definition (5 properties x 5 values).
  await ensureDemoItemsPresent('mobiles');

  // ensureDemoItemsPresent runs before the Mobiles group exists, so the item
  // lands in the fallback group with the fallback unit — pin both here.
  const item = await get(
    'SELECT id, group_id, unit_id FROM items WHERE name = ? ORDER BY id ASC LIMIT 1',
    ['Smartphone X'],
  );
  if (item && (item.group_id !== mobilesGroup.id || item.unit_id !== pieceUnit.id)) {
    await run('UPDATE items SET group_id = ?, unit_id = ?, updated_at = ? WHERE id = ?', [
      mobilesGroup.id,
      pieceUnit.id,
      now,
      item.id,
    ]);
  }
}

// Curated "Manufacturing Processes" demo scenario. Builds on the manufacturing
// items defined by ensureDemoItemsPresent('manufacturing') (Aluminum Billet,
// Copper Coil), then layers a coherent story on top: a Manufacturing group, a
// distinct material per processing-stage combination (e.g. RAW-MLL-ANO) each
// carrying real on-hand inventory, a dedicated pipeline template, an
// in-progress pipeline run, and a completed production run. Idempotent.
async function ensureDemoInventoryPresent(scenarioId = 'default') {
  if (scenarioId !== 'manufacturing') {
    return;
  }

  const now = new Date().toISOString();

  // Manufacturing measures in kilograms, but the base demo unit set has no
  // Kilogram unit, so ensure it exists first. ensureDemoItemsPresent then
  // resolves it (by name) when assigning the manufacturing items' unit.
  const kgUnit = await ensureUnitRecord({
    name: 'Kilogram',
    symbol: 'Kg',
    notes: 'Manufacturing scenario',
  });

  // 1. Dedicated manufacturing group so the seeded items land somewhere sensible.
  await ensureGroupRecord({ name: 'Manufacturing', unitId: kgUnit.id });

  // 2. Ensure the manufacturing items exist. ensureDemoDataset() only seeds the
  //    default scenario, so create the manufacturing items (Aluminum Billet,
  //    Copper Coil) here using the shared definitions.
  await ensureDemoItemsPresent('manufacturing');

  // Local helper: create (or fetch) a distinct material for one combination of
  // variation values on an item. We do our own exact match rather than call
  // ensureMaterialForItemSelection because that helper's final fallback returns
  // *any* material linked to the item, which would collapse every stage onto a
  // single material.
  const ensureCombinationMaterial = async (item, selections) => {
    const ordered = {};
    Object.keys(selections).sort().forEach((k) => { ordered[k] = selections[k]; });
    const customJson = JSON.stringify(ordered);

    const existing = await get(
      `SELECT * FROM materials
       WHERE linked_item_id = ?
         AND COALESCE(linked_variation_leaf_node_id, 0) = 0
         AND COALESCE(custom_variation_values_json, '') = ?
       ORDER BY id ASC LIMIT 1`,
      [item.id, customJson],
    );
    if (existing) {
      return existing;
    }

    const unit = item.unit_id ? await getUnitRowById(item.unit_id) : kgUnit;
    let barcode = await generateBarcodeFromItemSelection(item.id, selections);
    if (!barcode) {
      barcode = generateStandaloneMaterialBarcode();
    }
    if (await getMaterialRowByBarcode(barcode)) {
      barcode = `${barcode}-${item.id}`;
    }
    const baseName = item.display_name || item.name;
    const suffix = Object.values(ordered).join(' - ');
    const name = suffix ? `${baseName} - ${suffix}` : baseName;

    await run(
      `
      INSERT INTO materials (
        barcode, name, type, grade, thickness, supplier, location, unit_id, unit, notes,
        group_mode, inheritance_enabled, created_at, kind, parent_barcode, number_of_children,
        linked_child_barcodes, scan_count, linked_group_id, linked_item_id, linked_variation_leaf_node_id,
        custom_variation_values_json, display_stock, created_by, workflow_status, material_class, inventory_state, procurement_state,
        traceability_mode, on_hand_qty, reserved_qty, available_to_promise_qty, incoming_qty,
        linked_order_count, linked_pipeline_count, pending_alert_count, updated_at, last_scanned_at
      ) VALUES (?, ?, 'Item', '', '', '', '', ?, ?, '', NULL, 0, ?, 'standalone', NULL, 0, '[]', 0, NULL, ?, NULL, ?, ?, ?, 'notStarted', 'finished_good', 'available', 'not_ordered', 'bulk', 0, 0, 0, 0, 0, 0, 0, ?, NULL)
      `,
      [
        barcode,
        name,
        unit?.id || kgUnit.id,
        unit?.symbol || kgUnit.symbol || '',
        now,
        item.id,
        customJson,
        unit?.symbol ? `0 ${unit.symbol}` : '0',
        'Demo Seed',
        now,
      ],
    );
    return getMaterialRowByBarcode(barcode);
  };

  // Idempotent inventory: bring the MAIN/'' position to an absolute target so
  // re-seeding (without a reset) never double-counts.
  const setStageInventory = async (barcode, targetQty, unitId) => {
    const pos = await get(
      `SELECT on_hand_qty FROM inventory_stock_positions
       WHERE material_barcode = ? AND location_id = 'MAIN' AND lot_code = ''`,
      [barcode],
    );
    const current = pos ? Number(pos.on_hand_qty || 0) : 0;
    const delta = targetQty - current;
    if (delta !== 0) {
      await upsertInventoryStockPosition({
        materialBarcode: barcode,
        unitId,
        onHandDelta: delta,
        now,
      });
      await inventoryPorts.ledger.recomputeSummary(barcode, now);
    }
  };

  // 3. A distinct material with on-hand inventory for each processing stage.
  const stagePlan = {
    'Aluminum Billet': [
      { selections: { 'Initial State': 'Raw', 'Primary Process': 'None', 'Finishing': 'None' }, qty: 1000, label: 'Raw' },
      { selections: { 'Initial State': 'Raw', 'Primary Process': 'Milled', 'Finishing': 'None' }, qty: 600, label: 'Milled' },
      { selections: { 'Initial State': 'Raw', 'Primary Process': 'Milled', 'Finishing': 'Anodized' }, qty: 250, label: 'Anodized' },
    ],
    'Copper Coil': [
      { selections: { 'State': 'Drawn', 'Treatment': 'Insulated' }, qty: 800, label: 'Insulated' },
      { selections: { 'State': 'Drawn', 'Treatment': 'Bare' }, qty: 300, label: 'Bare' },
    ],
  };

  const materialsByItem = {};
  for (const [itemName, stages] of Object.entries(stagePlan)) {
    const itemRow = await get(
      'SELECT * FROM items WHERE name = ? ORDER BY id ASC LIMIT 1',
      [itemName],
    );
    if (!itemRow) {
      continue;
    }
    // Force kilograms. ensureDemoItemsPresent resolves the item's unit through
    // getUnitsWithUsage(), which doesn't surface the freshly-created Kilogram
    // unit, so the items land on the fallback (Box) — fix it directly here.
    if (itemRow.unit_id !== kgUnit.id) {
      await run('UPDATE items SET unit_id = ?, updated_at = ? WHERE id = ?', [
        kgUnit.id,
        now,
        itemRow.id,
      ]);
      itemRow.unit_id = kgUnit.id;
    }
    materialsByItem[itemName] = { item: itemRow, stages: [] };
    for (const stage of stages) {
      const material = await ensureCombinationMaterial(itemRow, stage.selections);
      if (!material?.barcode) {
        continue;
      }
      await setStageInventory(material.barcode, stage.qty, itemRow.unit_id || kgUnit.id);
      materialsByItem[itemName].stages.push({ material, stage });
    }
  }

  // 4. Dedicated pipeline template for the aluminum anodizing line.
  const mfgTemplate = {
    id: 'aluminum-anodize-line',
    factoryId: '1',
    shopFloorId: '1',
    name: 'Aluminum Anodizing Line',
    description:
      'Raw billet is milled, then anodized, then quality-checked before dispatch.',
    version: 1,
    status: 'active',
    stageLabels: ['Raw Input', 'Milling', 'Anodizing', 'Quality Check'],
    laneLabels: ['Main'],
    nodes: [
      { id: 'alu-input', name: 'Billet Intake', processType: 'Input', stageIndex: 0, laneIndex: 0, inputs: ['Aluminum Billet (RAW)'], outputs: ['Aluminum Billet (RAW)'], machine: 'Rack M1', durationHours: 0.5, status: 'Ready', isIntermediate: false, scannedInputs: [] },
      { id: 'alu-mill', name: 'CNC Milling', processType: 'Machining', stageIndex: 1, laneIndex: 0, inputs: ['Aluminum Billet (RAW)'], outputs: ['Milled Billet (MLL)'], machine: 'CNC 07', durationHours: 2, status: 'Active', isIntermediate: true, scannedInputs: [] },
      { id: 'alu-anodize', name: 'Anodizing Bath', processType: 'Finishing', stageIndex: 2, laneIndex: 0, inputs: ['Milled Billet (MLL)'], outputs: ['Anodized Billet (ANO)'], machine: 'Anodize Tank 02', durationHours: 3, status: 'Blocked', isIntermediate: true, scannedInputs: [] },
      { id: 'alu-qc', name: 'Quality Check', processType: 'Inspection', stageIndex: 3, laneIndex: 0, inputs: ['Anodized Billet (ANO)'], outputs: ['Finished Billet'], machine: 'QC Bench', durationHours: 0.5, status: 'Queued', isIntermediate: false, scannedInputs: [] },
    ],
    flows: [
      { id: 'alu-flow-1', fromNodeId: 'alu-input', toNodeId: 'alu-mill', materialName: 'Aluminum Billet (RAW)', barcode: null, isSplit: false, isMerge: false },
      { id: 'alu-flow-2', fromNodeId: 'alu-mill', toNodeId: 'alu-anodize', materialName: 'Milled Billet (MLL)', barcode: null, isSplit: false, isMerge: false },
      { id: 'alu-flow-3', fromNodeId: 'alu-anodize', toNodeId: 'alu-qc', materialName: 'Anodized Billet (ANO)', barcode: null, isSplit: false, isMerge: false },
    ],
  };

  const existingTemplate = await get(
    'SELECT id FROM pipeline_templates WHERE id = ?',
    [mfgTemplate.id],
  );
  if (!existingTemplate) {
    await run(
      `
      INSERT INTO pipeline_templates (
        id, factory_id, shop_floor_id, name, description, version, status,
        stage_labels_json, lane_labels_json, nodes_json, flows_json,
        intermediate_naming_convention, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        mfgTemplate.id,
        mfgTemplate.factoryId,
        mfgTemplate.shopFloorId,
        mfgTemplate.name,
        mfgTemplate.description,
        mfgTemplate.version,
        mfgTemplate.status,
        JSON.stringify(mfgTemplate.stageLabels),
        JSON.stringify(mfgTemplate.laneLabels),
        JSON.stringify(mfgTemplate.nodes),
        JSON.stringify(mfgTemplate.flows),
        '',
        now,
        now,
      ],
    );
  }

  // 5. In-progress pipeline run scanning the raw billet material at intake.
  const aluminum = materialsByItem['Aluminum Billet'];
  const rawBilletBarcode =
    aluminum?.stages.find((s) => s.stage.label === 'Raw')?.material?.barcode || null;

  await ensurePipelineRunRecord({
    id: 'demo-anodize-run-active',
    templateId: mfgTemplate.id,
    name: 'Anodize Line Morning Batch',
    status: 'inProgress',
    createdAt: oneDayAgo(1),
    startedAt: oneDayAgo(1),
    nodeStatuses: {
      'alu-input': 'completed',
      'alu-mill': 'inProgress',
      'alu-anodize': 'blocked',
      'alu-qc': 'pending',
    },
    overrides: {
      actualDurationHoursByNode: { 'alu-mill': 1.6 },
      batchQuantityByNode: { 'alu-input': 600, 'alu-mill': 600 },
      machineOverrideByNode: {},
    },
    barcodeAssignments: rawBilletBarcode
      ? [
          {
            id: 'demo-anodize-barcode-1',
            nodeId: 'alu-input',
            barcode: rawBilletBarcode,
            scannedAt: oneDayAgo(1),
          },
        ]
      : [],
  });

  // 6. Completed production run for the finished (anodized) output. The
  //    manufacturing items use parallel variation properties, so there is no
  //    single leaf node id; record 0 with a descriptive path label instead.
  const productionSeeds = [];
  if (aluminum) {
    const anodized = aluminum.stages.find((s) => s.stage.label === 'Anodized');
    if (anodized) {
      productionSeeds.push({
        runCode: 'MFG-0001',
        itemId: aluminum.item.id,
        leafNodeId: 0,
        pathLabel: 'Raw · Milled · Anodized',
        outputQuantity: anodized.stage.qty,
        completedAt: oneDayAgo(1),
      });
    }
  }
  for (const seed of productionSeeds) {
    const exists = await get(
      'SELECT id FROM production_runs WHERE run_code = ?',
      [seed.runCode],
    );
    if (exists) {
      continue;
    }
    await run(
      `
      INSERT INTO production_runs (
        run_code, status, completed_at, item_id, variation_leaf_node_id,
        variation_path_label, output_quantity, uom, location,
        source_metadata_json, created_at, updated_at
      ) VALUES (?, 'completed', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        seed.runCode,
        seed.completedAt,
        seed.itemId,
        seed.leafNodeId,
        seed.pathLabel,
        seed.outputQuantity,
        kgUnit.symbol || 'kg',
        'Anodizing Line',
        JSON.stringify({ scenario: 'manufacturing' }),
        now,
        now,
      ],
    );
  }
}

// Simulation scenarios (Settings → Demo Scenarios): compose a small, faithful
// dataset that demonstrates the two stock-consumption realities documented in
// Docs/SIMULATION_PLAYBOOK.md, using the real challan functions so stock actually
// moves and provenance is recorded. Idempotent (guarded by a marker challan) and
// non-destructive on its own — the Settings tiles run it after a reset.
//   scenario_a — Decoupled: bulk vendor stock-in (500), then two orders consume
//                50 + 100 from the shared aggregate pool → 350.
//   scenario_b — On-demand: a reception challan linked to a client order
//                (reception→order link), procuring specifically for that order.
async function ensureSimulationScenario(scenarioId) {
  const isA = scenarioId === 'scenario_a';
  const isB = scenarioId === 'scenario_b';
  if (!isA && !isB) return;

  const markerNo = isA ? 'SIM-A-RECEIVE' : 'SIM-B-RECEIVE';
  const already = await get(
    'SELECT id FROM delivery_challans WHERE challan_no = ? LIMIT 1',
    [markerNo],
  );
  if (already) return;

  // A valid stock-managed (item, leaf) to demo against — reuse one the base seed
  // already created so issuing succeeds.
  let stockRow = await get(`
    SELECT vs.item_id, vs.variation_leaf_node_id, i.name AS item_name
    FROM variation_stock vs JOIN items i ON i.id = vs.item_id
    WHERE vs.variation_leaf_node_id > 0 AND vs.item_id IS NOT NULL
    ORDER BY vs.id ASC LIMIT 1
  `);
  if (!stockRow) {
    stockRow = await get(`
      SELECT oi.item_id, oi.variation_leaf_node_id, i.name AS item_name
      FROM order_items oi JOIN items i ON i.id = oi.item_id
      WHERE oi.variation_leaf_node_id > 0 AND oi.item_id IS NOT NULL
      ORDER BY oi.id ASC LIMIT 1
    `);
  }
  if (!stockRow) return;
  const itemId = stockRow.item_id;
  const leafId = stockRow.variation_leaf_node_id;
  const itemName = stockRow.item_name || 'Sheet';

  const vendorName = isA ? 'Alpha Metals Co.' : 'Beta Alloys Ltd.';
  let vendorRow = await get('SELECT id FROM vendors WHERE name = ? LIMIT 1', [vendorName]);
  if (!vendorRow) {
    await saveVendor({ name: vendorName, address: 'Simulation vendor' });
    vendorRow = await get('SELECT id FROM vendors WHERE name = ? LIMIT 1', [vendorName]);
  }
  if (!vendorRow) return;
  const vendorId = vendorRow.id;
  const actor = { id: null, name: 'Scenario Seed', role: 'super_admin' };
  const today = new Date().toISOString().slice(0, 10);
  const line = (qty) => ({
    itemId,
    variationLeafNodeId: leafId,
    particulars: itemName,
    quantityPcs: String(qty),
    weight: '0',
    hsnCode: '',
    note: '',
  });

  if (isA) {
    const rc = await saveDeliveryChallan({
      type: 'reception',
      vendorId,
      challanNo: markerNo,
      date: today,
      location: 'MAIN',
      maintainStocks: true,
      items: [line(500)],
    }, actor, null);
    await issueDeliveryChallan(rc.id, actor, { recordCustody: false });
    for (const [no, qty] of [['SIM-A-USE-1', 50], ['SIM-A-USE-2', 100]]) {
      const uc = await saveDeliveryChallan({
        type: 'internal',
        internalPurpose: 'Decoupled consumption (simulation)',
        challanNo: no,
        date: today,
        location: 'MAIN',
        maintainStocks: true,
        items: [line(qty)],
      }, actor, null);
      await issueDeliveryChallan(uc.id, actor, { recordCustody: false });
    }
  } else {
    const order = await get('SELECT order_no FROM order_headers ORDER BY rowid ASC LIMIT 1');
    const orderNo = order?.order_no || '';
    const rc = await saveDeliveryChallan({
      type: 'reception',
      vendorId,
      orderNo,
      poNumber: 'PO-SIM-B',
      challanNo: markerNo,
      date: today,
      location: 'MAIN',
      maintainStocks: true,
      items: [line(120)],
    }, actor, null);
    await issueDeliveryChallan(rc.id, actor, { recordCustody: false });
  }
}

// scenario_c — Fulfilment: an order book where every state the Order Insights
// screen can show is actually present, so the two rows, the delivery
// checkpoint, the floor "made" figure and all four age filters have real data
// behind them rather than being taken on trust.
//
// Seven order lines for one client, all on the same stock-managed item:
//   C1  no run                                          → "Waiting on a pipeline"
//   C2  no run, raised 45 days ago                      → "Waiting" + Old
//   C3  run attached but never started                  → In production, empty bar
//   C4  running, terminal stage reports PIECES          → made bar drawn to scale
//   C5  running, terminal stage reports KILOGRAMS       → made figure, no bar
//   C6  running 20 days, nothing delivered              → Stalled
//   C7  completed and fully delivered                   → 100%
//
// C4 and C5 are the pair worth looking at: identical shape, different terminal
// unit. Pieces-on-pieces gets a proportional bar; kilograms-on-pieces states the
// quantity and deliberately draws no bar, because no conversion between them
// exists in the system.
async function ensureFulfilmentScenario(scenarioId) {
  if (scenarioId !== 'scenario_c') return;

  const markerNo = 'SIM-C-STOCK';
  const already = await get(
    'SELECT id FROM delivery_challans WHERE challan_no = ? LIMIT 1',
    [markerNo],
  );
  if (already) return;

  // Reuse a stock-managed (item, leaf) from the base dataset so the delivery
  // challans can actually issue — stock is not allowed to go negative.
  // Prefer an existing order line: it already names a valid (item, leaf, unit)
  // triple, and adopting its unit keeps the scenario in the dataset's own
  // vocabulary instead of inventing a parallel one. variation_stock is the
  // fallback for datasets seeded stock-first.
  let stockRow = await get(`
    SELECT oi.item_id, oi.variation_leaf_node_id, oi.unit_id, oi.unit_symbol,
           i.name AS item_name
    FROM order_items oi JOIN items i ON i.id = oi.item_id
    WHERE oi.variation_leaf_node_id > 0 AND oi.item_id IS NOT NULL
    ORDER BY oi.id ASC LIMIT 1
  `);
  if (!stockRow) {
    stockRow = await get(`
      SELECT vs.item_id, vs.variation_leaf_node_id, NULL AS unit_id,
             '' AS unit_symbol, i.name AS item_name
      FROM variation_stock vs JOIN items i ON i.id = vs.item_id
      WHERE vs.variation_leaf_node_id > 0 AND vs.item_id IS NOT NULL
      ORDER BY vs.id ASC LIMIT 1
    `);
  }
  if (!stockRow) return;
  const itemId = stockRow.item_id;
  const leafId = stockRow.variation_leaf_node_id;
  const itemName = stockRow.item_name || 'Sheet';

  const clientRow = await get('SELECT id, name FROM clients ORDER BY id ASC LIMIT 1');
  if (!clientRow) return;

  // The unit the order book already counts this item in.
  let orderUnitId = stockRow.unit_id || null;
  let orderUnitSymbol = String(stockRow.unit_symbol || '').trim();
  let orderUnitName = '';
  if (orderUnitId) {
    const unitRow = await get('SELECT id, name, symbol FROM units WHERE id = ?', [orderUnitId]);
    orderUnitName = unitRow?.name || '';
    orderUnitSymbol = unitRow?.symbol || orderUnitSymbol;
  }
  if (!orderUnitId || !orderUnitSymbol) {
    const fallbackUnit = await ensureUnitRecord({ name: 'Pieces', symbol: 'pcs' });
    if (!fallbackUnit) return;
    orderUnitId = fallbackUnit.id;
    orderUnitName = fallbackUnit.name || 'Pieces';
    orderUnitSymbol = fallbackUnit.symbol || 'pcs';
  }

  // A genuinely different unit for the mismatch case. If the order book already
  // counts in kilograms there is no mismatch to demonstrate, so the scenario
  // reaches for a second unit that is definitely not the ordered one.
  const weightUnit = orderUnitSymbol.toLowerCase() === 'kg'
    ? await ensureUnitRecord({ name: 'Metre', symbol: 'm' })
    : await ensureUnitRecord({ name: 'Kilogram', symbol: 'kg' });
  if (!weightUnit) return;

  const actor = { id: null, name: 'Scenario Seed', role: 'super_admin' };
  const now = new Date();
  const iso = (daysAgo) =>
    new Date(now.getTime() - daysAgo * 86400000).toISOString();
  const day = (daysAgo) => iso(daysAgo).slice(0, 10);

  // Two templates that differ only in what the terminal stage reports in. The
  // fulfilment endpoint reads the unit off outputItem.unitSymbol, which is the
  // only unit key the app itself ever writes onto a node.
  const buildTemplate = async (id, name, terminalUnitSymbol, terminalUnitId, terminalUnitName) => {
    const nodes = [
      {
        id: `${id}-in`,
        name: 'Material Input',
        processType: 'Input',
        stageIndex: 0,
        laneIndex: 0,
        inputs: [itemName],
        outputs: [itemName],
        machine: 'Input Stage',
        durationHours: 0.25,
        status: 'Ready',
        isIntermediate: false,
        scannedInputs: [],
      },
      {
        id: `${id}-cut`,
        name: 'Cutting',
        processType: 'Cutting',
        stageIndex: 1,
        laneIndex: 0,
        inputs: [itemName],
        outputs: [itemName],
        machine: 'Shear 01',
        durationHours: 1.5,
        status: 'Ready',
        isIntermediate: true,
        scannedInputs: [],
      },
      {
        id: `${id}-out`,
        name: 'Finishing & Output',
        processType: 'Output',
        stageIndex: 2,
        laneIndex: 0,
        inputs: [itemName],
        outputs: [itemName],
        machine: 'Finishing Bay',
        durationHours: 0.75,
        status: 'Ready',
        isIntermediate: false,
        scannedInputs: [],
        // The terminal stage declares its unit — this is what "made" is
        // labelled with, and what decides whether a proportional bar is safe.
        outputItem: {
          itemId,
          itemName,
          unitId: terminalUnitId,
          unitName: terminalUnitName,
          unitSymbol: terminalUnitSymbol,
        },
      },
    ];
    const flows = [
      {
        id: `${id}-f1`,
        fromNodeId: `${id}-in`,
        toNodeId: `${id}-cut`,
        materialName: itemName,
        barcode: null,
        isSplit: false,
        isMerge: false,
      },
      {
        id: `${id}-f2`,
        fromNodeId: `${id}-cut`,
        toNodeId: `${id}-out`,
        materialName: itemName,
        barcode: null,
        isSplit: false,
        isMerge: false,
      },
    ];
    await run(
      `INSERT INTO pipeline_templates (
         id, factory_id, shop_floor_id, name, description, version, status,
         stage_labels_json, lane_labels_json, nodes_json, flows_json,
         intermediate_naming_convention, created_at, updated_at
       ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET
         nodes_json = excluded.nodes_json,
         flows_json = excluded.flows_json,
         updated_at = excluded.updated_at`,
      [
        id, '', '', name, 'Fulfilment simulation line', 1, 'published',
        JSON.stringify(['Input', 'Cutting', 'Output']),
        JSON.stringify(['Line A']),
        JSON.stringify(nodes),
        JSON.stringify(flows),
        '', iso(60), iso(60),
      ],
    );
    return { id, nodes };
  };

  // matchTemplate's terminal stage reports in the ordered unit; mismatchTemplate's
  // reports in a different one. That difference is the whole point of the pair.
  const matchTemplate = await buildTemplate(
    'sim-c-line-match', `Simulation Line · ${orderUnitSymbol} Output`,
    orderUnitSymbol, orderUnitId, orderUnitName,
  );
  const mismatchTemplate = await buildTemplate(
    'sim-c-line-mismatch', `Simulation Line · ${weightUnit.symbol} Output`,
    weightUnit.symbol, weightUnit.id, weightUnit.name,
  );

  // Stock in enough to cover every delivery challan below.
  let vendorRow = await get(
    "SELECT id FROM vendors WHERE name = ? LIMIT 1", ['Gamma Steels Pvt Ltd'],
  );
  if (!vendorRow) {
    await saveVendor({ name: 'Gamma Steels Pvt Ltd', address: 'Simulation vendor' });
    vendorRow = await get(
      "SELECT id FROM vendors WHERE name = ? LIMIT 1", ['Gamma Steels Pvt Ltd'],
    );
  }
  if (!vendorRow) return;

  const stockIn = await saveDeliveryChallan({
    type: 'reception',
    vendorId: vendorRow.id,
    challanNo: markerNo,
    date: day(50),
    location: 'MAIN',
    maintainStocks: true,
    items: [{
      itemId,
      variationLeafNodeId: leafId,
      particulars: itemName,
      quantityPcs: '4000',
      weight: '0',
      hsnCode: '',
      note: '',
    }],
  }, actor, null);
  await issueDeliveryChallan(stockIn.id, actor, { recordCustody: false });

  const makeOrder = async ({ orderNo, quantity, daysAgo }) => {
    const saved = await saveOrder({
      orderNo,
      clientId: clientRow.id,
      clientName: clientRow.name || '',
      itemId,
      itemName,
      variationLeafNodeId: leafId,
      quantity,
      unitId: orderUnitId,
      unitName: orderUnitName,
      unitSymbol: orderUnitSymbol,
      unitPrice: 42,
      actor,
    });
    if (!saved) return null;
    // saveOrder stamps "now"; the age filters (Stalled after 14 days, Old after
    // 30) only mean something if the book actually spans time.
    await run('UPDATE order_items SET created_at = ? WHERE id = ?', [iso(daysAgo), saved.id]);
    await run('UPDATE order_headers SET created_at = ? WHERE order_no = ?', [iso(daysAgo), orderNo]);
    return saved;
  };

  const attachRun = async ({
    orderItemId, template, runId, status, startedDaysAgo, completedDaysAgo, quantity,
  }) => {
    const nodeStatuses = {};
    for (const node of template.nodes) {
      nodeStatuses[node.id] = status === 'completed'
        ? 'completed'
        : status === 'inProgress'
          ? (node.stageIndex === 2 ? 'inProgress' : 'completed')
          : 'pending';
    }
    await ensurePipelineRunRecord({
      id: runId,
      templateId: template.id,
      name: `Run ${runId}`,
      status,
      createdAt: iso(startedDaysAgo ?? 0),
      startedAt: startedDaysAgo == null ? null : iso(startedDaysAgo),
      completedAt: completedDaysAgo == null ? null : iso(completedDaysAgo),
      nodeStatuses,
      overrides: {
        actualDurationHoursByNode: {},
        batchQuantityByNode: {},
        machineOverrideByNode: {},
      },
      barcodeAssignments: [],
    });
    await run('DELETE FROM order_pipeline_assignments WHERE pipeline_run_id = ?', [runId]);
    await run(
      `INSERT INTO order_pipeline_assignments
         (order_item_id, pipeline_run_id, allocated_quantity, created_at)
       VALUES (?, ?, ?, ?)`,
      [orderItemId, runId, Number(quantity || 0), iso(startedDaysAgo ?? 0)],
    );
  };

  const reconcile = async (runId, template, { allotted, output, goodYield, scrap, daysAgo }) => {
    // Only the terminal stage is read for "made", but a floor that reported one
    // stage and not the others would not be a faithful demo.
    const terminal = template.nodes[template.nodes.length - 1];
    for (const node of template.nodes) {
      const isTerminal = node.id === terminal.id;
      await upsertStageReconciliation(runId, node.id, {
        allotted,
        output,
        remaining: 0,
        scrap: isTerminal ? scrap : 0,
        goodYield: isTerminal ? goodYield : output,
        actualHours: node.durationHours,
        inputTime: iso(daysAgo),
        outputTime: iso(daysAgo - 0.2),
      });
    }
  };

  const deliver = async ({ challanNo, orderItemId, quantity, daysAgo }) => {
    const dc = await saveDeliveryChallan({
      type: 'delivery',
      orderIds: [orderItemId],
      challanNo,
      date: day(daysAgo),
      location: 'MAIN',
      maintainStocks: true,
      items: [{
        orderItemId,
        itemId,
        variationLeafNodeId: leafId,
        particulars: itemName,
        quantityPcs: String(quantity),
        weight: '0',
        hsnCode: '',
        note: '',
        lineNo: 1,
      }],
    }, actor, null);
    await issueDeliveryChallan(dc.id, actor, { recordCustody: false });
  };

  // C1 — no pipeline, fresh.
  await makeOrder({ orderNo: 'SIM-C-1001', quantity: 500, daysAgo: 2 });

  // C2 — no pipeline, 45 days old → Old.
  await makeOrder({ orderNo: 'SIM-C-1002', quantity: 300, daysAgo: 45 });

  // C3 — run attached, never started.
  const c3 = await makeOrder({ orderNo: 'SIM-C-1003', quantity: 400, daysAgo: 3 });
  if (c3) {
    await attachRun({
      orderItemId: c3.id, template: matchTemplate, runId: 'sim-c-run-1003',
      status: 'planned', startedDaysAgo: null, completedDaysAgo: null, quantity: 400,
    });
  }

  // C4 — running; terminal stage reports PIECES, so made can be drawn to scale.
  const c4 = await makeOrder({ orderNo: 'SIM-C-1004', quantity: 1000, daysAgo: 10 });
  if (c4) {
    await attachRun({
      orderItemId: c4.id, template: matchTemplate, runId: 'sim-c-run-1004',
      status: 'inProgress', startedDaysAgo: 9, completedDaysAgo: null, quantity: 1000,
    });
    await reconcile('sim-c-run-1004', matchTemplate, {
      allotted: 1000, output: 655, goodYield: 620, scrap: 35, daysAgo: 4,
    });
    await deliver({
      challanNo: 'SIM-C-DEL-1004', orderItemId: c4.id, quantity: 250, daysAgo: 3,
    });
  }

  // C5 — running; terminal stage reports KILOGRAMS against a pieces order, so
  // the made figure is stated with its own unit and no bar is drawn.
  const c5 = await makeOrder({ orderNo: 'SIM-C-1005', quantity: 800, daysAgo: 12 });
  if (c5) {
    await attachRun({
      orderItemId: c5.id, template: mismatchTemplate, runId: 'sim-c-run-1005',
      status: 'inProgress', startedDaysAgo: 11, completedDaysAgo: null, quantity: 800,
    });
    await reconcile('sim-c-run-1005', mismatchTemplate, {
      allotted: 1500, output: 1300, goodYield: 1240, scrap: 60, daysAgo: 5,
    });
    await deliver({
      challanNo: 'SIM-C-DEL-1005', orderItemId: c5.id, quantity: 150, daysAgo: 2,
    });
  }

  // C6 — started 20 days ago, nothing delivered → Stalled.
  const c6 = await makeOrder({ orderNo: 'SIM-C-1006', quantity: 600, daysAgo: 20 });
  if (c6) {
    await attachRun({
      orderItemId: c6.id, template: matchTemplate, runId: 'sim-c-run-1006',
      status: 'inProgress', startedDaysAgo: 19, completedDaysAgo: null, quantity: 600,
    });
  }

  // C7 — completed and fully delivered.
  const c7 = await makeOrder({ orderNo: 'SIM-C-1007', quantity: 200, daysAgo: 25 });
  if (c7) {
    await attachRun({
      orderItemId: c7.id, template: matchTemplate, runId: 'sim-c-run-1007',
      status: 'completed', startedDaysAgo: 24, completedDaysAgo: 18, quantity: 200,
    });
    await reconcile('sim-c-run-1007', matchTemplate, {
      allotted: 210, output: 205, goodYield: 200, scrap: 5, daysAgo: 18,
    });
    await deliver({
      challanNo: 'SIM-C-DEL-1007', orderItemId: c7.id, quantity: 200, daysAgo: 17,
    });
  }
}

// The demo dataset seeds order lines with literal status strings ('inProgress',
// 'completed', 'delayed') and, separately, three pipeline runs that link to no
// order at all. That left screens disagreeing about whether a run was attached.
//
// Link them so what the runs say matches what the seed claims:
//   123456 notStarted → the queued run     (never started)
//   123457 inProgress → the active run     (started, not finished)
//   123458 completed  → the packed run     (finished)
//   123459 delayed    → left unlinked, as the example of an order with no route
//                       yet. (A run would not hide the chip: a line marked
//                       delayed shows delayed until its runs are all completed.)
async function ensureDemoOrderRunLinks() {
  const plan = [
    { orderNo: '123456', runId: 'demo-dolly-run-queued', metrics: null },
    {
      orderNo: '123457',
      runId: 'demo-dolly-run-active',
      metrics: { allotted: 1000, output: 700, goodYield: 680, scrap: 20 },
    },
    {
      orderNo: '123458',
      runId: 'demo-assembly-run-packed',
      metrics: { allotted: 1010, output: 1010, goodYield: 1000, scrap: 10 },
    },
  ];

  for (const entry of plan) {
    const orderLine = await get(
      `SELECT id, quantity, unit_id, unit_symbol, item_id, item_name
       FROM order_items WHERE order_no = ? ORDER BY id ASC LIMIT 1`,
      [entry.orderNo],
    );
    if (!orderLine) continue;
    // Per line, not per table: someone pressing Start on one order must not
    // stop the rest of the demo dataset from being linked on the next boot.
    const linked = await get(
      'SELECT id FROM order_pipeline_assignments WHERE order_item_id = ? LIMIT 1',
      [orderLine.id],
    );
    if (linked) continue;
    const runRow = await get(
      'SELECT id, template_id FROM pipeline_runs WHERE id = ?', [entry.runId],
    );
    if (!runRow) continue;

    await run(
      `INSERT INTO order_pipeline_assignments
         (order_item_id, pipeline_run_id, allocated_quantity, created_at)
       VALUES (?, ?, ?, ?)`,
      [orderLine.id, runRow.id, Number(orderLine.quantity || 0), new Date().toISOString()],
    );

    if (!entry.metrics) continue;

    // The terminal stage has to say what it makes and in which unit, or the
    // rollup has nothing to label "made" with and refuses to draw it.
    const templateRow = await get(
      'SELECT id, nodes_json FROM pipeline_templates WHERE id = ?', [runRow.template_id],
    );
    if (!templateRow) continue;
    const nodes = parseJson(templateRow.nodes_json, []);
    if (!Array.isArray(nodes) || nodes.length === 0) continue;
    const terminal = nodes
      .slice()
      .sort((a, b) => Number(b.stageIndex || 0) - Number(a.stageIndex || 0))[0];
    if (!terminal) continue;

    if (!terminal.outputItem) {
      const unitRow = orderLine.unit_id
        ? await get('SELECT id, name, symbol FROM units WHERE id = ?', [orderLine.unit_id])
        : null;
      terminal.outputItem = {
        itemId: orderLine.item_id,
        itemName: orderLine.item_name || '',
        unitId: orderLine.unit_id || null,
        unitName: unitRow?.name || '',
        unitSymbol: unitRow?.symbol || orderLine.unit_symbol || '',
      };
      await run(
        'UPDATE pipeline_templates SET nodes_json = ?, updated_at = ? WHERE id = ?',
        [JSON.stringify(nodes), new Date().toISOString(), templateRow.id],
      );
    }

    await upsertStageReconciliation(runRow.id, terminal.id, {
      allotted: entry.metrics.allotted,
      output: entry.metrics.output,
      remaining: 0,
      scrap: entry.metrics.scrap,
      goodYield: entry.metrics.goodYield,
      actualHours: Number(terminal.durationHours || 1),
    });
  }
}

const seedEstablishedYear = require('./modules/scenarios/established-year');
const { seedStandardUnitFamilies } = require('./modules/units/service');
const { ensureSystemGroups } = require('./modules/items/system-groups');
const { registerUnitRoutes } = require('./modules/units/routes');
const runPendingMigrations = require('./modules/kernel/migration-runner');

async function reseedDemoData(scenarioId = 'default') {
  await seedMaterialsIfEmpty();
  await seedUnitsIfEmpty();
  await bootstrapUnitsFromMaterials();
  await backfillMaterialUnitIds();
  await seedClientsIfEmpty();
  await seedGroupsIfEmpty(scenarioId);
  await seedItemsIfEmpty(scenarioId);
  await seedOrdersIfEmpty();
  await seedTemplatesIfEmpty();
  await seedCompanyProfileIfEmpty();
  await ensureDemoDataset(scenarioId);
  if (scenarioId === 'manufacturing') {
    await ensureDemoInventoryPresent(scenarioId);
  }
  if (scenarioId === 'mobiles') {
    await ensureDemoMobilesPresent(scenarioId);
  }
  if (scenarioId === 'established') {
    // A factory eleven months into using the software: staffed floor, ramping
    // order book, production history, closed payroll cycles. Seeded in FK
    // order — see modules/scenarios/established-year.js.
    await ensureDemoInventoryPresent('manufacturing');
    await seedEstablishedYear({ get, all, run });
  }
  if (
    scenarioId === 'scenario_a'
    || scenarioId === 'scenario_b'
    || scenarioId === 'scenario_c'
  ) {
    // Base items + stock come from the manufacturing dataset; then layer the
    // scenario-specific vendor/challan flow on top.
    await ensureDemoInventoryPresent('manufacturing');
    await ensureSimulationScenario(scenarioId);
    await ensureFulfilmentScenario(scenarioId);
  }
}

async function resetAndSeedDemoData(scenarioId = 'default') {
  await initDb();
  await clearAllData();
  await reseedDemoData(scenarioId);
  // Seeding wrote through the triggers. Skip past all of it rather than
  // narrating a rebuild to everyone who happens to be connected.
  await resyncChangelogCursor();
}

// The people master (departments, employees, their login links) left for
// modules/people. Nothing else in this file reads its DTOs. The two auth helpers
// keep a staff member's login code in step with their birth date.
const peopleService = createPeopleService({
  get,
  all,
  run,
  auth: { deriveDobPin, nextFreeMobilePin },
  desk: desk.as('people'),
});

// ==========================================
// PAYROLL APIs
// ==========================================

// registerPayrollRoutes: its routes are in modules/payroll/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const payrollRouter = express.Router();
app.use(payrollRouter);

// registerAssetsRoutesAfterErrorHandler: its routes are in modules/assets/routes.js and are registered into this
// router further down, where everything they use exists. The router holds
// their place in the matching order here.
const assetsAfterErrorHandlerRouter = express.Router();
app.use(assetsAfterErrorHandlerRouter);

const guardAlerts = [];

function validateContract(value, contract, path = "root", alerts = []) {
  if (value === undefined || value === null) {
    if (contract.required) alerts.push({ path, message: "Missing required field" });
    else if (!contract.nullable && value === null) alerts.push({ path, message: "Cannot be null" });
    return alerts;
  }

  if (contract.type === "string") {
    if (typeof value !== "string") alerts.push({ path, message: "Must be a string" });
    else {
      if (contract.nonEmpty && value.trim() === "") alerts.push({ path, message: "Cannot be empty" });
      if (contract.enum && !contract.enum.includes(value)) alerts.push({ path, message: "Must be one of: " + contract.enum.join(", ") });
    }
  } else if (contract.type === "number" || contract.type === "integer") {
    if (typeof value !== "number") alerts.push({ path, message: "Must be a number" });
    else {
      if (contract.type === "integer" && !Number.isInteger(value)) alerts.push({ path, message: "Must be an integer" });
      if (contract.min !== undefined && value < contract.min) alerts.push({ path, message: "Must be >= " + contract.min });
      if (contract.gt !== undefined && value <= contract.gt) alerts.push({ path, message: "Must be > " + contract.gt });
    }
  } else if (contract.type === "boolean") {
    if (typeof value !== "boolean") alerts.push({ path, message: "Must be a boolean" });
  } else if (contract.type === "array") {
    if (!Array.isArray(value)) alerts.push({ path, message: "Must be an array" });
    else if (contract.items) {
      const itemContract = typeof contract.items === "function" ? contract.items() : contract.items;
      value.forEach((item, index) => validateContract(item, itemContract, `${path}[${index}]`, alerts));
    }
  } else if (contract.type === "object" || contract.fields) {
    if (typeof value !== "object" || Array.isArray(value)) alerts.push({ path, message: "Must be an object" });
    else {
      if (contract.fields) {
        for (const [key, rules] of Object.entries(contract.fields)) {
          validateContract(value[key], rules, `${path}.${key}`, alerts);
        }
      }
    }
  }
  return alerts;
}

function guardContract(contract) {
  return (req, res, next) => {
    const alerts = validateContract(req.body, contract, contract.entity || "body");
    
    if (alerts.length > 0) {
      guardAlerts.push({
        route: req.method + " " + req.route.path,
        details: { problems: alerts }
      });
      return res.status(400).json({ success: false, error: "Contract violation", alerts });
    }
    next();
  };
}

app.get("/api/kernel/guard-alerts", (req, res) => {
  res.json({ success: true, alerts: guardAlerts });
});

const { createItemsPorts } = require('./modules/items/ports');
const itemsPorts = createItemsPorts({
  variationTree: getItemVariationTree,
  rowById: getItemRowById,
  resolveLeaf: resolveLeafSelectionFromDb,
  describe: async (id) => {
    const row = await get('SELECT * FROM items WHERE id = ?', [id]);
    return rowToItemDto ? await rowToItemDto(row) : row;
  },
  resolveSelection: resolveOrderVariationSelection,
  selectionSnapshot: getItemSelectionSnapshot,
  stockAssertLeaf: assertValidStockVariationLeaf,
  // The variation-stock write the port documents. It was wired to the barcode
  // ledger's movement function, which takes a different payload; nothing calls
  // this port yet, so the correction changes no behaviour.
  stockApplyDelta: applyVariationStockDelta,
  stockHoldsWholeItem: itemHoldsWholeItemStock,
  // It used to answer an empty list whatever the item, and jobs read the table
  // itself instead.
  bomLines: (itemId) => all('SELECT * FROM item_bom_lines WHERE item_id = ?', [itemId]),
  lookupByName: async (name) => {
    return await get('SELECT * FROM items WHERE name = ? COLLATE NOCASE', [name]);
  },
  deleteEntity: async (type, id, req) => {
    if (type === 'item') {
      return await deleteItemWithCascade(id, req);
    } else if (type === 'group') {
      return await deleteGroupWithCascade(id, req);
    }
    return await trashAndDelete(type + 's', id, req);
  },
  groupRowById: getGroupRowById,
  saveGroup,
  ensureReconcilePrimary: ensureReconcilePrimaryGroup,
  ensureReconcileSub: ensureReconcileSubGroup,
  ensureForReconcile: ensureReconcileItem,
  variationStockRows: () => all(`
    SELECT
      vs.id as stock_id,
      vs.item_id,
      vs.variation_leaf_node_id,
      vs.quantity,
      vs.location_id,
      vs.variation_path_label,
      vs.variation_path_node_ids_json,
      vs.custom_variation_values_json AS stock_custom_variation_values_json,
      vs.updated_at
    FROM variation_stock vs
    ORDER BY vs.item_id ASC, vs.variation_leaf_node_id ASC
  `),
  developedForCount: async (clientId) => {
    const row = await get(
      'SELECT COUNT(*) AS c FROM items WHERE developed_for_client_id = ?',
      [clientId],
    );
    return Number(row?.c || 0);
  },
});

const registerItemsModuleRoutes = require('./modules/items/routes');
// Items at function level. The work behind its four route sets is built here
// and published at the kernel desk; the routes ask the desk. What that work
// calls (saveItem, saveGroup, the variation tree, the usage reads) is still
// defined in this file and handed in by name.
desk.register('items', {
  operations: require('./modules/items/operations')({
    all,
    get,
    run,
    ports: itemsPorts,
    core: require('./modules/items/work').createItemsWork({
      desk: desk.as('items'),
      get,
      all,
      run,
      logChange,
      saveItem,
      saveGroup,
      rowToItemDto,
      rowsToItemDtos,
      rowToGroupDto,
      getItemsWithUsage,
      getGroupsWithUsage,
      getItemUsageDetails,
      getItemSetMembership: (...args) => inventoryPorts.sets.membershipForItem(...args),
      getItemRowById,
      getGroupRowById,
      getEffectiveSchema,
      getItemVariationTree,
      normalizePropertyKey,
      createAssetUploadIntent,
      completeAssetUpload,
      listAssetsForEntity,
      listEntityPhotos,
      arrangeEntityPhotos,
      MAX_PART_PHOTOS,
      itemsPorts,
        }),
    masterData: require('./modules/items/master-data').createMasterDataWork({
      get,
      all,
      run,
      logChange,
      desk: desk.as('items'),
    }),
    materialTypes: require('./modules/items/material-types').createMaterialTypeWork({ get, all, run, logChange }),
    sheetProperties: require('./modules/items/sheet-properties').createSheetPropertyWork({ get, all, run }),
    rivets: require('./modules/items/rivets').createRivetWork({
      get,
      all,
      run,
      desk: desk.as('items'),
      saveItem,
    }),
    springs: require('./modules/items/springs').createSpringWork({
      get,
      all,
      run,
      desk: desk.as('items'),
      saveItem,
    }),
    dieRawPlans: require('./modules/items/die-raw-plans').createDieRawPlanWork({
      get,
      all,
      run,
      desk: desk.as('items'),
    }),
  }),
});
registerItemsModuleRoutes({
  app,
  desk,
  requirePermission,
  requireAssetEntityPermission,
  cacheMasterData,
  guardContract,
  trackCreate,
  trackUpdate,
  trackDelete,
});

// The link graph between masters: item <-> die <-> machine and any other pair
// of declared masters, one row per link, readable from either end. Mounted
// after the item routes because it answers for them too (an item's dies still
// live in item_dies; see modules/links/catalog.js).
const registerLinksModuleRoutes = require('./modules/links/routes');
const linksModule = registerLinksModuleRoutes({
  app,
  get,
  all,
  run,
  desk: desk.as('links'),
  logChange,
  // logChange is replication, not an audit trail — it carries no actor and no
  // words. A link needed both to appear in a sitting, and this context was the
  // reason the module could not log: no track* helper was in it.
  trackLink,
  hasPermission,
  hasRecordPermission,
});
purgeEntityLinks = linksModule.purgeLinksFor;
setSoleEntityLink = linksModule.setSoleLink;
resolveSoleEntityLinks = linksModule.soleNeighboursOf;

// A property/value tree for masters other than items, versioned so that what
// was derived from a die can still be read against the die as it stood.
require('./modules/devtools/marks')({ app });

const registerVariationsModuleRoutes = require('./modules/variations/routes');
const variationsModule = registerVariationsModuleRoutes({
  app,
  get,
  all,
  run,
  hasPermission,
  hasRecordPermission,
});
purgeEntityVariations = variationsModule.purgeVariationsFor;

// An ordered list of process stages for a part — the canonical model from
// Docs/architecture/10-design-philosophy.md's worked example. Mounted after the
// item routes because it nests under /api/items/:id, and separate from
// pipeline_templates on purpose: a route is a flat ordered list belonging to a
// part, a pipeline is a node graph for a production run.
//
// The first module at function level: its work is published at the kernel desk
// (modules/process_routes/operations.js) and its routes only ask the desk, so
// they are handed neither the database nor the service.
desk.register('process_routes', {
  operations: require('./modules/process_routes/operations')({
    service: require('./modules/process_routes/service')({ get, all, run, desk: desk.as('process_routes') }),
  }),
  // A route is named after its part, its group and that group's parent.
  uses: ['items.rows.get', 'items.groups.row'],
});
require('./modules/process_routes/routes')({
  app,
  desk,
  requirePermission,
  trackCreate,
  trackUpdate,
});

// The vendor master. After the central /api gate like every module, so its
// routes are gated as the legacy ones were. `io` is declared further down this
// file, hence the getter.
desk.register('vendors', {
  operations: require('./modules/vendors/operations')({
    service: vendorsService,
    get,
    run,
    challans: challansClient(desk.as('vendors')),
    itemsPorts: itemsClient(desk.as('vendors')),
    partyDeleteBlockers,
    trashAndDelete,
  }),
});
registerVendorRoutes({
  app,
  desk,
  requirePermission,
  trackCreate,
  trackUpdate,
  trackDelete,
});

// The freelancer job pool. `run` is passed for the delete route's rollback.
desk.register('jobs', {
  operations: require('./modules/jobs/operations')({
    service: jobsService,
    run,
    work: require('./modules/jobs/work').createJobsWork({
      run,
      jobs: jobsService,
      desk: desk.as('jobs'),
      portalTokens: require('./modules/jobs/portal-tokens').createPortalTokens({ secret: JWT_SECRET }),
    }),
  }),
});
registerJobsRoutes({ app, desk, requirePermission });

// The machine master. purgeEntityLinks/Variations are late-bound (links and
// variations mount after this), hence the getters.
desk.register('machines', {
  operations: require('./modules/machines/operations')({
    service: machinesService,
    desk: desk.as('machines'),
    getPurgeEntityLinks: () => purgeEntityLinks,
    getPurgeEntityVariations: () => purgeEntityVariations,
  }),
});
registerMachineRoutes({
  app,
  desk,
  requirePermission,
  cacheMasterData,
  trackCreate,
  trackUpdate,
  trackDelete,
  listAssetsForEntity,
  createAssetUploadIntent,
  completeAssetUpload,
  listEntityPhotos,
  arrangeEntityPhotos,
});

// The die master. Same late-bound purges as machines.
desk.register('dies', {
  operations: require('./modules/dies/operations')({
    service: diesService,
    makers: require('./modules/dies/die-makers').createDieMakerService({ get, all, run }),
    desk: desk.as('dies'),
    getPurgeEntityLinks: () => purgeEntityLinks,
    getPurgeEntityVariations: () => purgeEntityVariations,
  }),
});
registerDieRoutes({
  app,
  desk,
  requirePermission,
  cacheMasterData,
  trackCreate,
  trackUpdate,
  trackDelete,
  listAssetsForEntity,
  createAssetUploadIntent,
  completeAssetUpload,
  listEntityPhotos,
  arrangeEntityPhotos,
});

// The client master and its sub-contractors, then the portal. `io` is declared
// further down this file, hence the getter.
const clientPortalService = require('./modules/clients/portal').createPortalService({
  get,
  all,
  run,
  desk: desk.as('clients'),
  hashPassword,
  verifyPassword,
});
desk.register('clients', {
  operations: require('./modules/clients/operations')({
    service: clientsService,
    contacts: partyContacts.createClientContactService({ get, all, run }),
    portal: clientPortalService,
    get,
    all,
    partyContacts,
    partyDeleteBlockers,
    trashAndDelete,
  }),
});
registerClientRoutes({
  app,
  desk,
  requirePermission,
  trackCreate,
  trackUpdate,
  trackDelete,
});
registerClientPortalRoutes({ app, desk });

// Departments, employees and the login links. The auth kernel is still defined
// in this file, so the pieces the login routes need are handed in by name.
desk.register('people', {
  operations: require('./modules/people/operations')({
    service: peopleService,
    ports: peoplePorts,
    trashAndDelete,
    trashAndDeleteMany,
    get,
    run,
    // The auth kernel, still defined in this file: making an account, its staff
    // login code, and the audit entry.
    auth: { createUserAccount, deriveDobPin, nextFreeMobilePin, logAuthEvent },
    desk: desk.as('people'),
  }),
});
registerPeopleRoutes({
  app,
  desk,
  requirePermission,
  requireRoles,
  trackCreate,
  trackUpdate,
  trackDelete,
  auth: { getRequestIp, getRequestUserAgent },
});

// Pipeline templates. The root /templates set is outside /api: its own auth and
// write guards are the app.use('/templates', ...) lines earlier in this file,
// which still run before these routes, exactly as before.
desk.register('pipelines', {
  operations: require('./modules/pipelines/operations')({
    service: pipelinesService,
    desk: desk.as('pipelines'),
  }),
});
registerPipelineRoutes({
  app,
  desk,
  requirePermission,
  trackCreate,
  trackUpdate,
  trackDelete,
});

// Inventory (sets so far). After the central /api gate, like every module.
desk.register('inventory', {
  operations: require('./modules/inventory/operations')({
    all,
    ports: inventoryPorts,
    work: require('./modules/inventory/work').createInventoryWork({
      get,
      run,
      all,
      currentActor,
      inventory: inventoryService,
      getMaterialRowByBarcode,
    }),
  }),
});
registerInventoryRoutes({
  app,
  desk,
  requirePermission,
  cacheMasterData,
  trackCreate,
  trackUpdate,
  trackDelete,
});

// The action center: trash, delete requests and the integrity scan. After the
// central /api gate, like every module; `trash` and `action-center` map to
// action_center there, `delete-requests` is excluded from it.
// What approving a delete request does, per kind of record. The raw deletes for
// vendor, machine, die and user are a known gap (no in-use check, no trash), kept
// as they were; see modules/action_center/delete-requests.js.
const deleteRequestService = createDeleteRequestService({
  get,
  all,
  run,
  parsePagination,
  deleters: {
    material: (id) => inventoryForActionCenter.materials.delete(id),
    item: (id, req) => itemsForActionCenter.delete('item', id, { user: req?.user || null }),
    asset: (id) => deleteAsset(id),
    group: (id, req) => itemsForActionCenter.delete('group', id, { user: req?.user || null }),
    vendor: (id) => desk.as('action_center').ask('vendors.rows.remove', { id }),
    inventory_set: (id) => inventoryForActionCenter.sets.deleteById(id),
    challan_template: (id) => desk.as('action_center').ask('challans.templates.remove', { id }),
    machine: (id) => desk.as('action_center').ask('machines.rows.remove', { id }),
    die: (id) => desk.as('action_center').ask('dies.rows.remove', { id }),
    // Accounts are the kernel's.
    user: (id) => run('DELETE FROM users WHERE id = ?', [id]),
  },
});
desk.register('action_center', {
  operations: require('./modules/action_center/operations')({
    run,
    work: require('./modules/action_center/work').createActionCenterWork({
      trash: trashService,
      deleteRequests: deleteRequestService,
    }),
  }),
});
registerActionCenterRoutes({ app, desk, requireAuth, requirePermission });

// The order lines' own routes. `io` is declared further down, hence the getter.
//
// Orders at function level: what the module offers is published at the kernel
// desk and its routes ask the desk. Registered here, not where the service is
// built, because deleting a line reaches production and inventory, which are
// built further down than orders is; nothing asks before the file has loaded.
desk.register('orders', {
  operations: require('./modules/orders/operations')({
    service: ordersService,
    ports: ordersPorts,
    lineWrites: require('./modules/orders/line-writes').createOrderLineWrites({
      get,
      all,
      run,
      orders: ordersService,
      inventoryPorts: inventoryForOrders,
      desk: desk.as('orders'),
    }),
  }),
});
registerOrderRoutes({
  app,
  all,
  desk,
  requirePermission,
  cacheMasterData,
  orders: ordersService,
});

// What has happened to an order: fulfilment, runs, production report, returns,
// trace. They read production's tables and shape rows with its helpers, which
// are still defined in this file.
registerOrderReportRoutes({
  app,
  get,
  all,
  run,
  requirePermission,
  parseJson,
  getMergedNodeMetrics,
  rowToRun,
  machineRowToDto: (...args) => machineRowToDto(...args),
  dieRowToDto: (...args) => dieRowToDto(...args),
  actorFromRequest,
  recordLedgerEvent,
  desk: desk.as('orders'),
});

// Challans at function level. The work behind its four route files is built
// here and published at the kernel desk; the routes ask the desk. `io` is
// created later, hence the getter. The scrap and leftover group and item
// helpers stay in this file: the items port points at them.
desk.register('challans', {
  operations: require('./modules/challans/operations')({
    all,
    run,
    ports: challansPorts,
    removeTemplate: (id) => deleteChallanTemplate(id),
    core: require('./modules/challans/work').createChallanWork({
      challanService: challansService,
      get,
      all,
      run,
          nowIso,
      rowToUploadedAssetDto,
      normalizeChallanType,
      createAssetUploadIntent,
      completeAssetUpload,
      inventoryPorts: inventoryForChallans,
      actorFromRequest,
      // Settled stock is filed under groups and items the items module makes.
      ensureReconcilePrimaryGroup: () => itemsForChallans.groups.ensureReconcilePrimary(),
      ensureReconcileSubGroup: (name, parentGroupId, unitId) =>
        itemsForChallans.groups.ensureReconcileSub(name, parentGroupId, unitId),
      ensureReconcileItem: (name, groupId, unitId, options) =>
        itemsForChallans.ensureForReconcile(name, groupId, unitId, options),
      desk: desk.as('challans'),
    }),
    template: require('./modules/challans/template-work').createChallanTemplateWork({
      templateService: challanTemplateService,
      parseBooleanEnv,
      parseJsonObject,
      getDeliveryChallanRowById,
    }),
    invoice: require('./modules/challans/invoice-work').createInvoiceWork({
      invoiceService,
      get,
      all,
      run,
      actorFromRequest,
      recordLedgerEvent,
    }),
    report: require('./modules/challans/report-work').createChallanReportWork({
      reportService: challanReportService,
    }),
  }),
});

// Challan templates. /scans and POST /test-print must stay ahead of /:id inside
// the module; see its header.
registerChallanTemplateRoutes({ app, desk, requirePermission });

// Invoices.
registerInvoiceRoutes({ app, desk, requirePermission });

// Challan reports.
registerChallanReportRoutes({ app, desk, requirePermission });

// The challan routes themselves.
registerChallanRoutes({ app, desk, requirePermission, cacheMasterData });

// Material types carry the one number that turns a sheet's volume into its
// weight. Named apart from `materials`, which is barcoded physical stock.
const {
  registerMaterialTypeRoutes,
} = require('./modules/items/material-types');
registerMaterialTypeRoutes({ app, desk, requirePermission });

// Master Data lives on the (variant, pipeline) pair — see modules/items/
// master-data.js for the resolution rule.
const { registerMasterDataRoutes } = require('./modules/items/master-data');
registerMasterDataRoutes({ app, desk, requirePermission });

// Units at function level. It asks inventory, items and orders how much a unit
// is used; inventory's operations are registered with its routes, above.
desk.register('units', {
  operations: require('./modules/units/operations')({
    master: unitsMaster,
    db: { run, get, all },
    trashAndDelete,
  }),
});
registerUnitRoutes(app, { desk, requirePermission, trackCreate });

// Production: runs, node status, stock on a run, scrap, completed output, a
// machine's queue and an item's pipeline history. See modules/production/routes.js.
desk.register('production', {
  operations: require('./modules/production/operations')({
    desk: desk.as('production'),
    ports: productionPorts,
    outputRow: (id) => productionService.getProductionRunRowById(id),
    work: require('./modules/production/work').createProductionWork({
      actorFromRequest,
      all,
      challansPorts: challansClient(desk.as('production')),
      get,
      getMaterialRowByBarcode: (barcode) => inventoryForProduction.materials.rowByBarcode(barcode),
      inventoryPorts: inventoryForProduction,
      itemsPorts: itemsForProduction,
      desk: desk.as('production'),
      parseJson,
      recordLedgerEvent,
      rowToTemplate,
      run,
      production: productionService,
    }),
  }),
});
registerProductionRoutes(app, { desk, requirePermission });

// The people at a client, nested under /api/clients so the clients module's
// gate and grants apply. See modules/parties/contacts.js.
partyContacts({
  app,
  desk,
  requirePermission,
  trackCreate,
  trackUpdate,
});

// Die makers — the master behind a die's "made by". Gated as `dies`, not as a
// module of its own: see modules/dies/die-makers.js.
const registerDieMakerRoutes = require('./modules/dies/die-makers');
registerDieMakerRoutes({
  app,
  desk,
  requirePermission,
  trackCreate,
  trackUpdate,
  trackDelete,
});

// The item sheet's property columns (061) — gated as `items`.
const registerItemSheetPropertyRoutes = require('./modules/items/sheet-properties');
registerItemSheetPropertyRoutes({ app, desk, requirePermission, trackCreate, trackUpdate, trackDelete });

// The rivet form (Docs/architecture/13-raw-material-forms.md) — gated as `items`.
require('./modules/items/rivets').registerRivetRoutes({ app, desk, requirePermission, trackCreate, trackUpdate, trackDelete });
// And the spring form, on the same engine (modules/items/raw-forms.js).
require('./modules/items/springs').registerSpringRoutes({ app, desk, requirePermission, trackCreate, trackUpdate, trackDelete });
// Raw material per die (modules/items/die-raw-plans.js).
require('./modules/items/die-raw-plans').registerDieRawPlanRoutes({ app, desk, requirePermission, trackCreate, trackUpdate, trackDelete });

// --- the routes outside the fifteen business modules ----------------------
//
// Each group is registered into the router that was mounted where its routes
// used to be (search for the router's name), so the order requests are matched
// in has not changed. They are filled in here because this is the first point
// where everything they are handed exists.
const {
  registerAccountsRoutesBeforeLogin,
  registerAccountsRoutes,
} = require('./modules/accounts/routes.js');
const {
  registerRealtimeRoutesBeforeLogin,
} = require('./modules/realtime/routes.js');
const {
  registerAssetsRoutesBeforeLogin,
  registerAssetsRoutes,
  registerAssetsRoutesAfterErrorHandler,
} = require('./modules/assets/routes.js');
const {
  registerTrackRoutes,
} = require('./modules/track/routes.js');
const {
  registerSearchRoutes,
} = require('./modules/search/routes.js');
const {
  registerUnitMasterRoutes,
} = require('./modules/units/master-routes.js');
const {
  registerSettingsRoutes,
} = require('./modules/settings/routes.js');
const {
  registerPayrollRoutes,
} = require('./modules/payroll/routes.js');

registerAccountsRoutesBeforeLogin(accountsBeforeLoginRouter, {
  createAuthSession,
  get,
  getEffectivePermissionMap,
  getRequestIp,
  getRequestUserAgent,
  isTimestampInFuture,
  logAuthEvent,
  normalizeEmail,
  registerLoginFailure,
  safeUserDto,
  verifyPassword,
  hashPin: pinHasher.hash,
  // B59: a wrong PIN waits PAPER_PIN_TARPIT_MS (1 s); more than 15 wrong or
  // pending PIN attempts a minute from one address get 429 for a minute.
  pinThrottle: require('./kernel/pin-throttle').createPinThrottle({
    delayMs: Number(process.env.PAPER_PIN_TARPIT_MS ?? 1000),
  }),
});
registerAccountsRoutes(accountsRouter, {
  hashPin: pinHasher.hash,
  generateUniqueMobilePin,
  RECORD_OPTION_SOURCES,
  desk: desk.as('accounts'),
  RECORD_PERMISSION_OPS,
  USER_ROLES,
  all,
  canManageUser,
  createEmptyPermissionMap,
  createUserAccount,
  firstUngrantableKey,
  get,
  getAssignedPermissionTemplates,
  getRequestIp,
  getRequestUserAgent,
  getRolePermissionMap,
  getTemplatePermissionMapForUser,
  getUserPermissionSnapshot,
  hashPassword,
  isKnownPermissionKey,
  logAuthEvent,
  normalizeNullableDate,
  normalizePermissionKey,
  normalizeTemplatePermissionKeys,
  nowIso,
  parseBooleanFlag,
  parsePagination,
  permissionDescriptors,
  requireAuth,
  requirePermission,
  requireRoles,
  revokeSession,
  revokeSessionsForUser,
  rowToAuthEventDto,
  rowToAuthSessionDto,
  run,
  safeUserDtoWithPermissions,
  toCsv,
  validatePasswordPolicy,
  verifyPassword,
  serverDir: __dirname,
});
require('./kernel/system-routes').registerSystemRoutesBeforeLogin(systemBeforeLoginRouter, {
  get,
  requireAuth,
  telemetry: serverTelemetry,
  backups: serverBackups,
  backupEveryHours: BACKUP_EVERY_HOURS,
  dbPath: DB_PATH,
  release: RELEASE_INFO,
  serverVersion: process.env.APP_VERSION || require('./package.json').version,
  environment: process.env.PAPER_ENV || (IS_PRODUCTION ? 'production' : 'development'),
});
registerRealtimeRoutesBeforeLogin(realtimeBeforeLoginRouter, {
  all,
  changeEmitter,
  get,
  requireAuth,
});
registerAssetsRoutesBeforeLogin(assetsBeforeLoginRouter, {
  ALLOWED_ASSET_CONTENT_TYPES,
  IMMUTABLE_CACHE_CONTROL,
  LOCAL_UPLOAD_CONTENT_TYPES,
  assertLocalUploadSigned,
  assetViewSignature,
  get,
  localObjectKeyFrom,
  localUploadPath,
  presignS3Url,
});
registerAssetsRoutes(assetsRouter, {
  ASSET_ENTITY_PERMISSIONS,
  DOCUMENT_ENTITY_TYPES,
  PHOTO_REQUEST_TYPES,
  all,
  announcePhotoRequests,
  assertAssetEntityExists,
  assertRoomForPhoto,
  assetEntityTypeFromAssetId,
  assetEntityTypeFromBody,
  assetEntityTypeFromUploadSession,
  assetReadUrlPayload,
  assetViewUrl,
  closePhotoRequest,
  completeAssetUpload,
  createAssetReadUrl,
  createAssetUploadIntent,
  deleteAsset,
  get,
  hasPermission,
  normalizeAssetFileName,
  normalizeDocumentTitle,
  nowIso,
  photoRequestDetails,
  photoRequestDto,
  photoRequestError,
  presignS3Url,
  renameDocument,
  requireAssetEntityPermission,
  requireGenericUploadPermission,
  run,
  setPrimaryAsset,
});
registerAssetsRoutesAfterErrorHandler(assetsAfterErrorHandlerRouter, {
  DeleteObjectCommand,
  assertS3Configured,
  getS3Client,
  requirePermission,
  run,
});
registerTrackRoutes(trackRouter, {
  actorScopeFor,
  all,
  get,
  hasPermission,
  requirePermission,
  rowToEntityActivityDto,
});
registerSearchRoutes(searchRouter, {
  all,
  get,
  desk: desk.as('search'),
  itemsPorts: itemsClient(desk.as('search')),
  requirePermission,
  resolveBarcode,
  run,
});
registerUnitMasterRoutes(unitMasterRouter, {
  cacheMasterData,
  desk,
  requirePermission,
  trackCreate,
  trackDelete,
  trackUpdate,
});
registerSettingsRoutes(settingsRouter, {
  all,
  getActiveCompanyProfile,
  requirePermission,
  rowToCompanyProfileDto,
  run,
  saveCompanyProfile,
});
registerPayrollRoutes(payrollRouter, {
  all,
  get,
  requirePermission,
  run,
});

const { computeTerritory } = require("./kernel/territory");
app.get("/api/kernel/territory", async (req, res) => {
  try {
    const result = await computeTerritory({
      app,
      allRows: all,
      runtime: {
        // Calls served at the kernel desk, per operation.
        ...Object.fromEntries(
          Object.entries(desk.stats()).map(([name, operationCalls]) => [name, { operationCalls }]),
        ),
        items: {
          portCalls: itemsPorts.stats(),
          ...(desk.stats().items ? { operationCalls: desk.stats().items } : {}),
        }
      }
    });
    res.json({ success: true, territory: result });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

let bonjour = null;

function startServer() {
  console.log(`Booting Paper backend on port ${PORT} using ${DB_PATH}`);
  return new Promise((resolve, reject) => {
    
    const server = app.listen(PORT, '0.0.0.0', async () => {
      console.log(`Paper backend listening on port ${PORT}`);
      
      // Initialize Bonjour mDNS
      try {
        bonjour = new Bonjour();
        bonjour.publish({ name: 'Paper Local Server', type: 'papererp', protocol: 'tcp', port: PORT });
        console.log('mDNS service _papererp._tcp published.');
      } catch (e) {
        console.warn('Failed to publish mDNS service:', e);
      }

      try {
        console.log('Running migrations...');
        await runMigrations();
        console.log('Initializing database schema...');
        await initDb();
        // Operations cut off by the last stop cannot be known to have landed.
        await idempotency.recover();
        setInterval(() => idempotency.prune().catch(() => {}), 60 * 60 * 1000).unref();
        // SQLite profiling and a timed PASSIVE wal_checkpoint every few
        // minutes (kernel/telemetry.js).
        startServerTelemetry();
        serverBackups.schedule(BACKUP_EVERY_HOURS * 60 * 60 * 1000);
        // Portal passwords stored as plain text by older versions are hashed
        // before the server takes a request.
        const rehashed = await clientPortalService.hashStoredPlainPasswords();
        if (rehashed) console.log(`Hashed ${rehashed} portal password(s) that were stored as plain text.`);
        dbReady = true;
        console.log('Database schema ready.');
        console.log(`Paper backend running on port ${PORT} using ${DB_PATH}`);
        startTelemetryEmitter();
      } catch (error) {
        dbInitError = error;
        console.error('Failed to initialize backend database/migrations:', error);
      }
      resolve(server);
    });
    server.on('error', reject);
  });
}

// ============================================================================
// Control-plane telemetry emitter (OPT-IN, disclosed benchmarking).
// Pushes a periodic snapshot — business KPIs + user roster — to the vendor
// Falcon View control plane. Disabled unless CONTROL_PLANE_URL + DEPLOYMENT_KEY
// are set, so it never runs for a client who has not agreed. See
// control-plane/README.md.
// ============================================================================
const CONTROL_PLANE_URL = process.env.CONTROL_PLANE_URL || '';
const TELEMETRY_INTERVAL_MS = Number(process.env.TELEMETRY_INTERVAL_MS || 3600000);
// Resolved once the emitter starts (see getOrCreateDeploymentIdentity).
let DEPLOYMENT_ID = '';
let DEPLOYMENT_KEY = '';
let DEPLOYMENT_NAME = '';

// Zero-friction enrollment: the deployment generates and persists its own id +
// key on first run (a small file beside the data volume), so onboarding a
// client only needs CONTROL_PLANE_URL — no per-client key to hand off or manage.
// Explicit DEPLOYMENT_* env vars still win if the vendor wants to pin them.
function getOrCreateDeploymentIdentity() {
  let id = String(process.env.DEPLOYMENT_ID || '').trim();
  let key = String(process.env.DEPLOYMENT_KEY || '').trim();
  let name = String(process.env.DEPLOYMENT_NAME || '').trim();
  if (id && key) return { id, key, name: name || id };
  const identityPath = path.join(path.dirname(DB_PATH), 'deployment-identity.json');
  try {
    if (fs.existsSync(identityPath)) {
      const saved = JSON.parse(fs.readFileSync(identityPath, 'utf8'));
      id = id || saved.id || '';
      key = key || saved.key || '';
      name = name || saved.name || '';
    }
  } catch (_) { /* fall through and regenerate */ }
  if (!key) key = 'dk_' + crypto.randomBytes(16).toString('hex');
  if (!id) id = 'dep_' + crypto.randomBytes(6).toString('hex');
  if (!name) name = id;
  try {
    fs.writeFileSync(identityPath, JSON.stringify({ id, key, name }, null, 2));
  } catch (_) { /* non-fatal; will regenerate next boot */ }
  return { id, key, name };
}

async function telemetryCount(sql, params = []) {
  try {
    const row = await get(sql, params);
    return Number((row && Object.values(row)[0]) || 0);
  } catch (_) {
    return 0;
  }
}

async function computeTelemetrySnapshot() {
  const metrics = {
    orders: await telemetryCount('SELECT COUNT(*) c FROM order_headers'),
    ordersOpen: await telemetryCount("SELECT COUNT(DISTINCT order_no) c FROM order_items WHERE COALESCE(status,'') != 'completed'"),
    challans: await telemetryCount('SELECT COUNT(*) c FROM delivery_challans'),
    items: await telemetryCount('SELECT COUNT(*) c FROM items WHERE COALESCE(is_archived,0)=0'),
    inventoryOnHand: Math.round(await telemetryCount('SELECT COALESCE(SUM(on_hand_qty),0) c FROM materials')),
    productionRuns: await telemetryCount('SELECT COUNT(*) c FROM production_runs'),
    clients: await telemetryCount('SELECT COUNT(*) c FROM clients'),
    activeUsers: await telemetryCount('SELECT COUNT(*) c FROM users WHERE is_active=1'),
  };
  let users = [];
  try {
    const rows = await all('SELECT id, name, email, role, is_active FROM users');
    for (const u of rows) {
      let lastLogin = '';
      try {
        const s = await get('SELECT MAX(created_at) t FROM auth_sessions WHERE user_id = ?', [u.id]);
        lastLogin = s && s.t ? s.t : '';
      } catch (_) { /* auth_sessions may be absent */ }
      users.push({
        id: u.id, name: u.name, email: u.email, role: u.role,
        isActive: Number(u.is_active) !== 0, lastLogin,
      });
    }
  } catch (_) { users = []; }
  // How the software is being used, as against how much of it there is.
  //
  // The counts above say how big a deployment is. They cannot answer the
  // question that decides what to build next: which parts of this do people
  // actually touch, and where are they working around it rather than with it.
  //
  // Everything here is derived from records the app already writes for its own
  // audit trail — no new tracking, no per-click instrumentation. Aggregates
  // only: which modules were touched and how often, never what was typed.
  const usage = { moduleActivity: [], adoption: {}, workarounds: {} };
  try {
    // Which modules see real activity, over the last month. A module absent
    // from this list is one nobody is using — the most useful thing to know
    // before spending a week improving it.
    usage.moduleActivity = (await all(
      `SELECT entity_type AS module, COUNT(*) AS actions,
              COUNT(DISTINCT actor_user_id) AS people,
              MAX(created_at) AS lastAt
       FROM entity_activity_log
       WHERE created_at >= datetime('now', '-30 day')
       GROUP BY entity_type
       ORDER BY actions DESC`,
    )) || [];

    // Whether the parts that only pay off when they are filled in are being
    // filled in. A low number is not misuse — it is usually the software
    // asking for something at a moment the user cannot supply it.
    usage.adoption = {
      itemsWithVariations: await telemetryCount(
        `SELECT COUNT(DISTINCT item_id) c FROM item_variation_nodes
         WHERE COALESCE(is_archived,0)=0`,
      ),
      itemsTotal: await telemetryCount(
        'SELECT COUNT(*) c FROM items WHERE COALESCE(is_archived,0)=0',
      ),
      ordersWithPipeline: await telemetryCount(
        'SELECT COUNT(DISTINCT order_item_id) c FROM order_pipeline_assignments',
      ),
      runsWithStockAssigned: await telemetryCount(
        'SELECT COUNT(DISTINCT run_id) c FROM run_barcode_inputs',
      ),
      runsTotal: await telemetryCount('SELECT COUNT(*) c FROM pipeline_runs'),
      deliveriesLinkedToOrder: await telemetryCount(
        `SELECT COUNT(*) c FROM delivery_challans
         WHERE type='delivery' AND COALESCE(order_no,'') <> ''`,
      ),
      deliveriesTotal: await telemetryCount(
        "SELECT COUNT(*) c FROM delivery_challans WHERE type='delivery'",
      ),
    };

    // Where the shape of the software and the shape of the work disagree.
    // These are the interesting numbers: each one is a place someone did the
    // job anyway, around what was designed. Read them as questions, not faults.
    usage.workarounds = {
      // Stock created straight in inventory rather than received on a challan:
      // material that exists but cannot be traced to where it came from.
      materialsWithoutReceipt: await telemetryCount(
        `SELECT COUNT(*) c FROM materials
         WHERE COALESCE(is_archived,0)=0 AND source_challan_id IS NULL`,
      ),
      // Consumption that cannot name the receipt it came from — the same gap,
      // seen from the production end.
      consumptionWithoutSource: await telemetryCount(
        'SELECT COUNT(*) c FROM run_barcode_inputs WHERE challan_item_id IS NULL',
      ),
      // Items filed nowhere in particular.
      itemsUngrouped: await telemetryCount(
        `SELECT COUNT(*) c FROM items i
         WHERE COALESCE(i.is_archived,0)=0
           AND NOT EXISTS (SELECT 1 FROM groups g WHERE g.id = i.group_id)`,
      ),
      // Challans that never got issued: started and abandoned, which usually
      // means the form asked for something the user did not have.
      challansLeftDraft: await telemetryCount(
        "SELECT COUNT(*) c FROM delivery_challans WHERE status='draft'",
      ),
    };
  } catch (_) {
    // Telemetry must never be the reason a deployment misbehaves.
  }

  return {
    deploymentId: DEPLOYMENT_ID,
    deploymentName: DEPLOYMENT_NAME,
    appVersion: process.env.APP_VERSION || '',
    release: process.env.PAPER_RELEASE || null,
    environment: process.env.PAPER_ENV || null,
    capturedAt: new Date().toISOString(),
    metrics,
    usage,
    users,
  };
}

function postTelemetryJson(urlStr, headers, bodyObj) {
  return new Promise((resolve, reject) => {
    try {
      const u = new URL(urlStr);
      const lib = u.protocol === 'https:' ? require('https') : require('http');
      const data = Buffer.from(JSON.stringify(bodyObj));
      const request = lib.request(
        {
          hostname: u.hostname,
          port: u.port || (u.protocol === 'https:' ? 443 : 80),
          path: u.pathname + u.search,
          method: 'POST',
          headers: { 'content-type': 'application/json', 'content-length': data.length, ...headers },
        },
        (r) => { r.resume(); r.on('end', () => resolve(r.statusCode)); },
      );
      request.on('error', reject);
      request.setTimeout(15000, () => request.destroy(new Error('telemetry push timeout')));
      request.write(data);
      request.end();
    } catch (e) { reject(e); }
  });
}

async function pushTelemetryOnce() {
  if (!CONTROL_PLANE_URL || !DEPLOYMENT_KEY) return;
  try {
    const snapshot = await computeTelemetrySnapshot();
    const status = await postTelemetryJson(
      CONTROL_PLANE_URL.replace(/\/$/, '') + '/api/ingest',
      { 'x-deployment-key': DEPLOYMENT_KEY },
      snapshot,
    );
    console.log('[telemetry] snapshot pushed to control plane (status ' + status + ')');
  } catch (e) {
    console.warn('[telemetry] push failed:', e.message);
  }
}

// Generic request helper (GET/POST) to the control plane.
function controlPlaneRequest(method, urlStr, headers, bodyObj) {
  return new Promise((resolve, reject) => {
    try {
      const u = new URL(urlStr);
      const lib = u.protocol === 'https:' ? require('https') : require('http');
      const data = bodyObj ? Buffer.from(JSON.stringify(bodyObj)) : null;
      const h = { ...headers };
      if (data) { h['content-type'] = 'application/json'; h['content-length'] = data.length; }
      const request = lib.request(
        {
          hostname: u.hostname,
          port: u.port || (u.protocol === 'https:' ? 443 : 80),
          path: u.pathname + u.search,
          method,
          headers: h,
        },
        (r) => {
          let raw = '';
          r.on('data', (c) => { raw += c; });
          r.on('end', () => resolve({ status: r.statusCode, body: raw }));
        },
      );
      request.on('error', reject);
      request.setTimeout(15000, () => request.destroy(new Error('control plane request timeout')));
      if (data) request.write(data);
      request.end();
    } catch (e) { reject(e); }
  });
}

// Pull vendor-issued commands from the control plane and apply them. Today the
// only command is create_admin — the vendor provisions an admin login from the
// Falcon View; the client applies it here (no inbound connection to the client).
async function pullAndApplyControlCommands() {
  if (!CONTROL_PLANE_URL || !DEPLOYMENT_KEY) return;
  const base = CONTROL_PLANE_URL.replace(/\/$/, '');
  try {
    const res = await controlPlaneRequest('GET', base + '/api/commands', { 'x-deployment-key': DEPLOYMENT_KEY });
    if (res.status !== 200) return;
    let payload = {};
    try { payload = JSON.parse(res.body); } catch (_) { return; }
    const commands = Array.isArray(payload.commands) ? payload.commands : [];
    for (const cmd of commands) {
      let status = 'done';
      let result = '';
      try {
        if (cmd.type === 'create_admin') {
          const p = cmd.payload || {};
          const email = normalizeEmail(p.email || '');
          const existing = await get('SELECT id FROM users WHERE email = ?', [email]);
          if (existing) {
            result = 'admin already exists';
          } else {
            const user = await createUserAccount({
              name: p.name || email,
              email,
              password: p.password,
              role: 'admin',
            });
            result = 'admin created id=' + user.id;
          }
        } else {
          status = 'failed';
          result = 'unsupported command type: ' + cmd.type;
        }
      } catch (e) {
        status = 'failed';
        result = String((e && e.message) || e).slice(0, 300);
      }
      await controlPlaneRequest(
        'POST',
        base + '/api/commands/' + encodeURIComponent(cmd.id) + '/ack',
        { 'x-deployment-key': DEPLOYMENT_KEY },
        { status, result },
      ).catch(() => {});
    }
    if (commands.length) {
      console.log('[control] applied ' + commands.length + ' command(s) from control plane');
    }
  } catch (e) {
    console.warn('[control] command pull failed:', e.message);
  }
}

function startTelemetryEmitter() {
  if (!CONTROL_PLANE_URL) {
    console.log('[telemetry] disabled — set CONTROL_PLANE_URL to enable disclosed benchmarking + control-plane provisioning.');
    return;
  }
  const identity = getOrCreateDeploymentIdentity();
  DEPLOYMENT_ID = identity.id;
  DEPLOYMENT_KEY = identity.key;
  DEPLOYMENT_NAME = identity.name;
  console.log('[telemetry] deployment id ' + DEPLOYMENT_ID + ' (self-enrolled)');
  const cmdMs = Number(process.env.COMMAND_POLL_MS || 60000);
  setTimeout(() => { pushTelemetryOnce(); pullAndApplyControlCommands(); }, 10000);
  setInterval(() => { pushTelemetryOnce(); }, TELEMETRY_INTERVAL_MS);
  setInterval(() => { pullAndApplyControlCommands(); }, cmdMs);
  console.log('[telemetry] emitter enabled -> ' + CONTROL_PLANE_URL
    + ' (telemetry every ' + Math.round(TELEMETRY_INTERVAL_MS / 60000) + 'm, commands every '
    + Math.round(cmdMs / 1000) + 's)');
}

if (require.main === module) {
  startServer().catch((error) => {
    console.error('Failed to initialize backend:', error);
    process.exit(1);
  });
}

// ── API 404 catch-all: must come AFTER all real routes, BEFORE error handler ──
// Any /api/* path that fell through all routes gets a JSON 404 (never HTML).
app.use('/api', (req, res) => {
  console.warn(`[API 404] ${req.method} ${req.originalUrl}`);
  const message = `API route not found: ${req.method} ${req.originalUrl}`;
  res.status(404).json({
    success: false,
    message,
    error: message,
  });
});

app.use((error, req, res, _next) => {
  console.error(`Request failed: ${req.method} ${req.originalUrl}`, error);
  const message = IS_PRODUCTION ? 'Request failed.' : error.message;
  res.status(error.statusCode || 500).json({
    success: false,
    message,
    error: message,
  });
});

module.exports = {
  serverBackups,
  serverTelemetry,
  startServerTelemetry,
  stopServerTelemetry,
  desk,
  idempotency,
  rowToDeliveryChallanDto,
  rowsToItemDtos,
  resyncChangelogCursor,
  drainChangelog,
  pruneChangelog,
  changeEmitter,
  applyInventoryMovement,
  // Exported so the fleet snapshot can be asserted rather than trusted.
  computeTelemetrySnapshot,
  buildTemplateTestChallanDto,
  completeAssetUpload,
  completePoUpload,
  createAssetUploadIntent,
  createParentWithChildren,
  createPoUploadIntent,
  ensureMaterialForItemSelection,
  getClientsWithUsage,
  getEffectiveSchema,
  getGroupsWithUsage,
  getItemPropertySchema,
  getItemsWithUsage,
  getMaterialGroupGovernance,
  getMaterialRowByBarcode,
  getOrderActivity,
  getOrders,
  getOrderStatusHistory,
  getPoDocumentsForOrder,
  getUnitsWithUsage,
  linkMaterialRecordToGroup,
  linkMaterialRecordToItem,
  linkPoDocumentsToOrder,
  listAssetsForEntity,
  listChallanTemplates,
  listCompletedProductionRuns,
  resetAndSeedDemoData,
  resolveOrderVariationSelection,
  rowToClientDto,
  rowToItemDto,
  rowToOrderDto,
  rowToPoDocumentDto,
  saveChallanTemplate,
  unlinkMaterialRecord,
  updateMaterialGroupConfiguration,
  updateOrderLifecycle,
  app,
  initDb,
  startServer,
  closeDb,
  all,
  get,
  run,
  backfillStageReconciliations,
  saveUnit,
  saveClient,
  saveGroup,
  saveItem,
  saveOrder,
  saveCompanyProfile,
  saveVendor,
  getActiveCompanyProfile,
  saveDeliveryChallan,
  issueDeliveryChallan,
  cancelDeliveryChallan,
  deleteDraftDeliveryChallan,
  listDeliveryChallans,
  listInvoices,
  createInvoice,
  getInvoiceDtoById,
  generateInvoicePdf,
  listConversionOverrides,
  saveConversionOverride,
  buildReconciliationReport,
  buildClientStatementReport,
  listWasteAuditRows,
  listChallanTemplates,
  listCompletedProductionRuns,
  saveChallanTemplate,
  deleteChallanTemplate,
  createChallanTemplateUploadIntent,
  completeChallanTemplateUpload,
  buildTemplateTestChallanDto,
  generateChallanTemplatePdf,
  createPoUploadIntent,
  completePoUpload,
  createAssetUploadIntent,
  completeAssetUpload,
  listAssetsForEntity,
  listEntityPhotos,
  arrangeEntityPhotos,
  sweepDeletedAssets,
  thumbnailKeyFor,
  createAssetReadUrl,
  setPrimaryAsset,
  deleteAsset,
  linkPoDocumentsToOrder,
  getPoDocumentsForOrder,
  createPoDocumentReadUrl,
  ensureMockOrdersPresent,
  ensureDemoDataset,
  ensureDemoInventoryPresent,
  ensureDemoMobilesPresent,
  resetAndSeedDemoData,
  getOrderActivity,
  getOrders,
  countOrders,
  getUnitsWithUsage,
  getGroupsWithUsage,
  getClientsWithUsage,
  getVendorsWithUsage,
  getItemsWithUsage,
  createParentWithChildren,
  getMaterialRowByBarcode,
  getEffectiveSchema,
  getItemPropertySchema,
  applyInventoryMovement,
  ensureMaterialForItemSelection,
  linkMaterialRecordToGroup,
  linkMaterialRecordToItem,
  unlinkMaterialRecord,
  getMaterialGroupGovernance,
  updateMaterialGroupConfiguration,
  rowToClientDto,
  rowToVendorDto,
  rowToOrderDto,
  rowToPoDocumentDto,
  rowToItemDto,
  resolveOrderVariationSelection,
};
