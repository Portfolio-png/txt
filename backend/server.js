require('dotenv').config();
const express = require('express');
const { Server } = require('socket.io');
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
const PORT = Number(process.env.PORT || 18080);
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'paper.db');
const FULL_DEMO_SEED_PATH = path.join(__dirname, 'demo_seed_full.json');
const IS_PRODUCTION = process.env.NODE_ENV === 'production';
const SEED_DEMO_DATA_ON_BOOT = parseBooleanEnv(
  process.env.PAPER_SEED_DEMO_DATA_ON_BOOT,
  false,
);
const JWT_SECRET = resolveJwtSecret();
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

async function logChange(tableName, recordId, eventType) {
  try {
    const result = await new Promise((resolve, reject) => {
      db.run(
        `INSERT INTO changelog (table_name, record_id, event_type, timestamp) VALUES (?, ?, ?, datetime('now'))`,
        [tableName, recordId, eventType],
        function (err) {
          if (err) reject(err);
          else resolve(this);
        }
      );
    });
    // Emit event for SSE stream
    changeEmitter.emit('table-change', {
      id: result.lastID,
      table: tableName,
      recordId: recordId,
      eventType: eventType
    });
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
const CAPABILITY_PERMISSION_KEYS = Object.keys(CAPABILITY_DESCRIPTORS);

const PERMISSION_KEYS = [
  ...MODULE_PERMISSION_KEYS,
  ...CAPABILITY_PERMISSION_KEYS,
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
app.use(cors(buildCorsOptions()));
app.use(express.json());
app.use('/public', express.static(path.join(__dirname, 'public')));

app.get('/health', (_req, res) => {
  res.json({
    success: true,
    status: dbReady ? 'ok' : 'starting',
    port: PORT,
    dbPath: IS_PRODUCTION ? null : DB_PATH,
    dbReady,
    dbInitError: dbInitError?.message ?? null,
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

function run(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function onRun(error) {
      if (error) {
        reject(error);
        return;
      }
      resolve(this);
    });
  });
}

// Runs a statement on the dedicated FK-off delete connection.
function runOnDelete(sql, params = []) {
  return new Promise((resolve, reject) => {
    deleteDb.run(sql, params, function onRun(error) {
      if (error) {
        reject(error);
        return;
      }
      resolve(this);
    });
  });
}

function get(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (error, row) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(row);
    });
  });
}

function all(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (error, rows) => {
      if (error) {
        reject(error);
        return;
      }
      resolve(rows);
    });
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
  // Let a write wait for another connection's write lock instead of erroring.
  await run('PRAGMA busy_timeout = 5000');

  // Configure the dedicated delete connection: FK enforcement OFF for its whole
  // lifetime, and the same busy_timeout so it waits on the main connection's
  // write lock rather than throwing SQLITE_BUSY.
  await runOnDelete('PRAGMA foreign_keys = OFF');
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

function validatePasswordPolicy(password /* , { email, role } */) {
  // Password strength requirements intentionally removed: any non-empty
  // password is accepted (short/weak/4-digit codes are fine).
  if (String(password || '').length < 1) {
    return 'Enter a password.';
  }
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
    dto.mobilePin = row.mobile_pin;
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
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        (entity_type, entity_id, action, actor_user_id, actor_name, actor_role, changes_json, details_json, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
  };
}


async function createAuthSession({ user, req }) {
  await revokeSessionsForUser(user.id, { reason: 'new_login_revoked_others' });
  const sessionId = `sess-${crypto.randomUUID()}`;
  const token = signJwt({ sub: user.id, role: user.role, sid: sessionId });
  const tokenHash = hashToken(token);
  const now = nowIso();
  await run(
    `
    INSERT INTO auth_sessions (
      id, user_id, token_hash, created_at, last_used_at, expires_at, revoked_at, revoked_reason, ip_address, user_agent
    ) VALUES (?, ?, ?, ?, ?, ?, NULL, '', ?, ?)
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

async function revokeSessionsForUser(userId, { exceptSessionId = null, reason = '' } = {}) {
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
    const existing = await get('SELECT id FROM users WHERE mobile_pin = ?', [pin]);
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
      [pin, excludeUserId, excludeUserId],
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
      mobilePin,
      clientId,
    ],
  );
  return get('SELECT * FROM users WHERE id = ?', [result.lastID]);
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

async function getDeleteRequestById(id) {
  return get(
    `
    SELECT
      dr.*,
      requester.name AS requested_by_name,
      reviewer.name AS reviewed_by_name
    FROM delete_requests dr
    LEFT JOIN users requester ON requester.id = dr.requested_by_user_id
    LEFT JOIN users reviewer ON reviewer.id = dr.reviewed_by_user_id
    WHERE dr.id = ?
    `,
    [id],
  );
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
  // Bypass auth for local development sandbox sync, replays, and dashboard APIs
  if (req.path.startsWith('/sandbox-sync') ||
      req.path.startsWith('/session-replay') ||
      req.path.startsWith('/sandbox-dashboard') ||
      req.path.startsWith('/activation') ||
      req.path.startsWith('/build') ||
      req.path.startsWith('/config')) {
    return next();
  }

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
  return req.userPermissions?.[key] === true;
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
    'record-options',
  ]);
  if (EXCLUDED.has(seg)) return null;
  // Employee account sub-actions stay capability-gated (create/link/unlink login).
  if (seg === 'employees' && /\/(create-login|link-login|unlink-login)/.test(path)) {
    return null;
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
  } else if (['items', 'groups'].includes(seg)) {
    module = 'items';
  } else if (['clients', 'sub-contractors'].includes(seg)) {
    module = 'clients';
  } else if (seg === 'vendors') {
    module = 'vendors';
  } else if (seg === 'units') {
    module = 'units';
  } else if (seg === 'machines') {
    module = 'machines';
  } else if (seg === 'dies') {
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
  // Bypass write check for local development sandbox sync, replays, and dashboard configs
  if (req.path.startsWith('/sandbox-sync') ||
      req.path.startsWith('/session-replay') ||
      req.path.startsWith('/sandbox-dashboard') ||
      req.path.startsWith('/activation') ||
      req.path.startsWith('/build') ||
      req.path.startsWith('/config')) {
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

function normalizeBarcode(value = '') {
  return String(value)
    .replace(/\s+/g, '')
    .replace(/[^\x20-\x7E]/g, '')
    .trim()
    .toUpperCase();
}

function generateParentBarcode() {
  const suffix = 1000 + Math.floor(Math.random() * 9000);
  return `PAR-${Date.now()}-${suffix}`;
}

function generateChildBarcode(parentBarcode, index) {
  const parts = parentBarcode.split('-');
  const suffix = parts.length > 0 ? parts[parts.length - 1] : parentBarcode;
  return `CHD-${suffix}-${String(index).padStart(2, '0')}`;
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

function normalizeUnitValue(value = '') {
  return String(value).trim().replace(/\s+/g, ' ').toLowerCase();
}

function rowToMaterialDto(row) {
  if (!row) {
    return null;
  }

  const unitLabel = String(row.unit || '').trim();
  const displayStock = String(row.display_stock || '').trim() ||
    (unitLabel
      ? `${Number(row.on_hand_qty || 0)} ${unitLabel}`
      : `${Number(row.on_hand_qty || 0)}`);

  return {
    id: row.id,
    barcode: row.barcode,
    name: row.name,
    type: row.type,
    grade: row.grade || '',
    thickness: row.thickness || '',
    supplier: row.supplier || '',
    location: row.location || '',
    unitId: row.unit_id || null,
    unit: row.unit || '',
    notes: row.notes || '',
    groupMode: row.group_mode || null,
    inheritanceEnabled: Number(row.inheritance_enabled || 0) === 1,
    isParent: row.kind === 'parent',
    parentBarcode: row.parent_barcode || null,
    numberOfChildren: row.number_of_children || 0,
    linkedChildBarcodes: parseJson(row.linked_child_barcodes, []),
    scanCount: row.scan_count || 0,
    createdAt: row.created_at,
    linkedGroupId: row.linked_group_id || null,
    linkedItemId: row.linked_item_id || null,
    linkedVariationLeafNodeId: row.linked_variation_leaf_node_id || null,
    displayStock,
    createdBy: row.created_by || 'Demo Admin',
    workflowStatus: row.workflow_status || 'notStarted',
    materialClass: row.material_class || 'raw_material',
    inventoryState: row.inventory_state || 'available',
    procurementState: row.procurement_state || 'not_ordered',
    traceabilityMode: row.traceability_mode || 'bulk',
    onHand: Number(row.on_hand_qty || 0),
    reserved: Number(row.reserved_qty || 0),
    availableToPromise: Number(row.available_to_promise_qty || 0),
    incoming: Number(row.incoming_qty || 0),
    linkedOrderCount: Number(row.linked_order_count || 0),
    linkedPipelineCount: Number(row.linked_pipeline_count || 0),
    pendingAlertCount: Number(row.pending_alert_count || 0),
    updatedAt: row.updated_at || row.created_at,
    lastScannedAt: row.last_scanned_at || null,
  };
}

function rowToMaterialActivityDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    barcode: row.barcode || '',
    type: row.event_type || '',
    label: row.event_label || '',
    description: row.event_description || '',
    actor: row.actor || '',
    createdAt: row.created_at,
  };
}

function rowToUnitDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    symbol: row.symbol || '',
    notes: row.notes || '',
    unitGroupId: row.unit_group_id || null,
    unitGroupName: row.unit_group_name || null,
    conversionFactor: Number(row.conversion_factor || 1),
    conversionBaseUnitId: row.conversion_base_unit_id || null,
    conversionBaseUnitName: row.conversion_base_unit_name || null,
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

// Moves a single row into the deleted_records trash table, then hard-deletes it.
// Notes:
//  - The DELETE runs on the dedicated FK-off connection (deleteDb) so a
//    referenced master (e.g. a client still used by orders) can be removed; the
//    resulting dangling reference is what the Action Center surfaces. Because
//    FK-off lives on its own connection, it never affects concurrent requests.
//  - If the DELETE fails we roll back the trash row so no orphan is left behind.
//  - A DELETE change is logged so SSE/changelog clients live-refresh uniformly.
async function trashAndDelete(tableName, recordId, req) {
  const deletedBy = req?.user?.name || 'System';

  // Fetch the row
  const row = await get(`SELECT * FROM ${tableName} WHERE id = ?`, [recordId]);
  if (!row) return;

  // Insert into trash
  const trash = await run(
    `INSERT INTO deleted_records (table_name, record_id, data_json, deleted_at, deleted_by)
     VALUES (?, ?, ?, ?, ?)`,
    [tableName, recordId, JSON.stringify(row), new Date().toISOString(), deletedBy]
  );

  // Delete via the dedicated FK-off connection (see deleteDb).
  try {
    await runOnDelete(`DELETE FROM ${tableName} WHERE id = ?`, [recordId]);
  } catch (err) {
    // Compensate so a failed delete never strands an unrecoverable trash row.
    await run('DELETE FROM deleted_records WHERE id = ?', [trash.lastID]).catch(() => {});
    throw err;
  }

  await logChange(tableName, recordId, 'DELETE');
}

async function trashAndDeleteMany(tableName, recordIds, req) {
  if (!recordIds || recordIds.length === 0) return;
  const deletedBy = req?.user?.name || 'System';
  const now = new Date().toISOString();
  // Chunk to stay well under SQLite's default 999 bound-variable limit so a
  // parent with a very large child set (e.g. 1000+ variation nodes) still deletes.
  const CHUNK = 400;

  for (let i = 0; i < recordIds.length; i += CHUNK) {
    const chunk = recordIds.slice(i, i + CHUNK);
    const placeholders = chunk.map(() => '?').join(',');
    const rows = await all(`SELECT * FROM ${tableName} WHERE id IN (${placeholders})`, chunk);
    if (rows.length === 0) continue;

    const trashIds = [];
    for (const row of rows) {
      const trash = await run(
        `INSERT INTO deleted_records (table_name, record_id, data_json, deleted_at, deleted_by)
         VALUES (?, ?, ?, ?, ?)`,
        [tableName, row.id, JSON.stringify(row), now, deletedBy]
      );
      trashIds.push(trash.lastID);
    }

    try {
      await runOnDelete(`DELETE FROM ${tableName} WHERE id IN (${placeholders})`, chunk);
    } catch (err) {
      const trashPlaceholders = trashIds.map(() => '?').join(',');
      await run(`DELETE FROM deleted_records WHERE id IN (${trashPlaceholders})`, trashIds).catch(() => {});
      throw err;
    }

    for (const row of rows) {
      await logChange(tableName, row.id, 'DELETE');
    }
  }
}

function rowToGroupDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    groupType: row.group_type || 'item',
    groupStructure: row.group_structure || 'hierarchical',
    description: row.description || '',
    parentGroupId: row.parent_group_id || null,
    unitId: row.unit_id || null,
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function rowToInventorySetDto(row, lines = []) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    name: row.name || '',
    totalItemCount: Number(row.total_item_count || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    lines,
  };
}

function rowToClientDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    alias: row.alias || '',
    gstNumber: row.gst_number || '',
    address: row.address || '',
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function rowToVendorDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    alias: row.alias || '',
    gstNumber: row.gst_number || '',
    address: row.address || '',
    contactName: row.contact_name || '',
    phone: row.phone || '',
    email: row.email || '',
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function rowToOrderDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    orderNo: row.order_no || '',
    clientId: row.client_id || 0,
    subContractorId: row.sub_contractor_id || null,
    clientName: row.client_name || '',
    poNumber: row.po_number || '',
    clientCode: row.client_code || '',
    itemId: row.item_id || 0,
    itemName: row.item_name || '',
    variationLeafNodeId: row.variation_leaf_node_id || 0,
    variationPathLabel: row.variation_path_label || '',
    variationPathNodeIds: parseJson(row.variation_path_node_ids_json, []),
    customVariationValues: parseJson(row.custom_variation_values_json, {}),
    quantity: Number(row.quantity || 0),
    unitId: row.unit_id || null,
    unitName: row.unit_name || '',
    unitSymbol: row.unit_symbol || '',
    unitPrice: Number(row.unit_price || 0),
    totalInvoicedQty: Number(row.total_invoiced_qty || 0),
    totalDeliveredQty: Number(row.total_delivered_qty || 0),
    status: row.status || 'notStarted',
    createdAt: row.created_at,
    startDate: row.start_date,
    endDate: row.end_date,
    hsnCode: row.hsn_code || '',
    taxableValue: Number(row.taxable_value || 0),
    cgstRate: Number(row.cgst_rate || 0),
    sgstRate: Number(row.sgst_rate || 0),
    cgstAmount: Number(row.cgst_amount || 0),
    sgstAmount: Number(row.sgst_amount || 0),
  };
}

function rowToPoDocumentDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    fileName: row.file_name || '',
    contentType: row.content_type || '',
    sizeBytes: Number(row.size_bytes || 0),
    sha256: row.sha256 || '',
    objectKey: row.object_key || '',
    status: row.status || 'uploaded',
    createdAt: row.created_at,
    uploadedAt: row.uploaded_at,
    linkedAt: row.linked_at || null,
  };
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
    createdAt: row.created_at,
    uploadedAt: row.uploaded_at,
    readUrl: readUrlPayload?.readUrl || null,
    readUrlExpiresAt: readUrlPayload?.expiresAt || null,
  };
}

async function rowToUploadedAssetDto(row, includeReadUrls = true) {
  if (!row) return null;
  const payload = includeReadUrls ? await assetReadUrlPayload(row.object_key) : null;
  return rowToAssetDto(row, payload);
}

function rowToOrderActivityDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    orderId: row.order_id || 0,
    activityType: row.activity_type || row.event_type || '',
    actorUserId: row.actor_user_id || null,
    actorName: row.actor_name || '',
    actorRole: row.actor_role || '',
    source: row.source || '',
    details: parseJson(row.details_json || row.metadata_json, null),
    createdAt: row.created_at,
  };
}

function rowToOrderStatusHistoryDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    orderId: row.order_id || 0,
    previousStatus: row.previous_status || null,
    newStatus: row.new_status || '',
    changedByUserId: row.changed_by_user_id || null,
    changedAt: row.changed_at,
  };
}

async function rowToItemDto(row) {
  if (!row) {
    return null;
  }

  const unitConversionRows = await all(
    `
    SELECT
      item_unit_conversions.unit_id,
      item_unit_conversions.factor_to_primary,
      units.name AS unit_name,
      units.symbol AS unit_symbol
    FROM item_unit_conversions
    INNER JOIN units ON units.id = item_unit_conversions.unit_id
    WHERE item_unit_conversions.item_id = ?
    ORDER BY LOWER(units.name) ASC, LOWER(units.symbol) ASC
    `,
    [row.id],
  );
  const propertySchema = await getItemPropertySchema(row.id);
  // Enhancement 2.3 — combination groups this item additionally belongs to
  // (distinct from its primary hierarchical group_id). Empty for most items.
  const combinationGroupRows = await all(
    `
    SELECT group_item_memberships.group_id
    FROM group_item_memberships
    INNER JOIN groups ON groups.id = group_item_memberships.group_id
    WHERE group_item_memberships.item_id = ?
      AND groups.group_structure = 'combination'
      AND groups.is_archived = 0
    ORDER BY group_item_memberships.sort_order ASC
    `,
    [row.id],
  );

  return {
    id: row.id,
    name: row.name || '',
    alias: row.alias || '',
    shortCode: row.short_code || '',
    displayName: row.display_name || '',
    quantity: Number(row.quantity || 0),
    groupId: row.group_id || null,
    unitId: row.unit_id || null,
    unitConversions: unitConversionRows.map((entry) => ({
      unitId: entry.unit_id || 0,
      unitName: entry.unit_name || '',
      unitSymbol: entry.unit_symbol || '',
      factorToPrimary: Number(entry.factor_to_primary || 1),
    })),
    namingFormat: (() => {
      try {
        return row.naming_format ? JSON.parse(row.naming_format) : [];
      } catch (e) {
        return [];
      }
    })(),
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    variationTree: await getItemVariationTree(row.id),
    propertySchema,
    baseItemId: row.base_item_id || null,
    combinationGroupIds: combinationGroupRows.map((entry) => entry.group_id),
    photoUrl: row.photo_url || null,
    availableForPurchase: Boolean(row.available_for_purchase),
  };
}

function rowToTemplate(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    factoryId: row.factory_id || '',
    shopFloorId: row.shop_floor_id || '',
    name: row.name,
    description: row.description || '',
    version: row.version || 1,
    status: row.status || 'draft',
    stageLabels: parseJson(row.stage_labels_json, []),
    laneLabels: parseJson(row.lane_labels_json, []),
    nodes: parseJson(row.nodes_json, []),
    flows: parseJson(row.flows_json, []),
    intermediateNamingConvention: row.intermediate_naming_convention || '',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

// Metric key (API/blob) → stage_reconciliations column. One row per run+node;
// the API keeps exposing these as `nodeMetrics` so the app needs no changes.
const STAGE_RECON_COLUMNS = {
  allotted: 'allotted',
  output: 'output',
  remaining: 'leftover',
  scrap: 'scrap',
  goodYield: 'good_yield',
  actualHours: 'actual_hours',
  scrapItemId: 'scrap_item_id',
  scrapItem: 'scrap_item_name',
  leftoverAction: 'leftover_action',
  inputTime: 'input_time',
  outputTime: 'output_time',
};

async function upsertStageReconciliation(runId, nodeId, metrics) {
  const cols = [];
  const vals = [];
  for (const [key, col] of Object.entries(STAGE_RECON_COLUMNS)) {
    if (metrics[key] !== undefined) {
      cols.push(col);
      vals.push(metrics[key]);
    }
  }
  if (!cols.length) return;
  await run(
    `INSERT INTO stage_reconciliations (run_id, node_id, ${cols.join(', ')}, updated_at)
     VALUES (?, ?, ${cols.map(() => '?').join(', ')}, datetime('now'))
     ON CONFLICT(run_id, node_id) DO UPDATE SET
       ${cols.map((c) => `${c} = excluded.${c}`).join(', ')},
       updated_at = excluded.updated_at`,
    [runId, nodeId, ...vals],
  );
}

// One-time copy of legacy pipeline_runs.node_metrics_json into the table so
// reports can query reconciliation data with plain SQL. INSERT OR IGNORE keeps
// rows already written through the endpoint authoritative; idempotent per boot.
async function backfillStageReconciliations() {
  const rows = await all(
    `SELECT id, node_metrics_json FROM pipeline_runs
     WHERE node_metrics_json IS NOT NULL AND node_metrics_json NOT IN ('', '{}')`,
  );
  for (const row of rows) {
    const nodeMetrics = parseJson(row.node_metrics_json, {});
    for (const [nodeId, metrics] of Object.entries(nodeMetrics)) {
      const cols = [];
      const vals = [];
      for (const [key, col] of Object.entries(STAGE_RECON_COLUMNS)) {
        if (metrics[key] !== undefined) {
          cols.push(col);
          vals.push(metrics[key]);
        }
      }
      if (!cols.length) continue;
      await run(
        `INSERT OR IGNORE INTO stage_reconciliations (run_id, node_id, ${cols.join(', ')}, updated_at)
         VALUES (?, ?, ${cols.map(() => '?').join(', ')}, datetime('now'))`,
        [row.id, nodeId, ...vals],
      );
    }
  }
}

// nodeMetrics for a pipeline_runs row: stage_reconciliations is the source of
// truth; the legacy blob sits underneath so pre-migration and demo-seeded runs
// still render.
async function getMergedNodeMetrics(row) {
  const nodeMetrics = parseJson(row.node_metrics_json, {});
  const reconRows = await all(
    'SELECT * FROM stage_reconciliations WHERE run_id = ?',
    [row.id],
  );
  for (const recon of reconRows) {
    const merged = { ...(nodeMetrics[recon.node_id] || {}) };
    for (const [key, col] of Object.entries(STAGE_RECON_COLUMNS)) {
      if (recon[col] !== null && recon[col] !== undefined) {
        merged[key] = recon[col];
      }
    }
    nodeMetrics[recon.node_id] = merged;
  }
  return nodeMetrics;
}

async function rowToRun(row) {
  if (!row) {
    return null;
  }

  const barcodeRows = await all(
    'SELECT node_id, barcode, material_payload_json FROM run_barcode_inputs WHERE run_id = ? ORDER BY scanned_at DESC',
    [row.id],
  );

  const attachedBarcodeInputs = {};
  for (const barcodeRow of barcodeRows) {
    if (!attachedBarcodeInputs[barcodeRow.node_id]) {
      attachedBarcodeInputs[barcodeRow.node_id] = [];
    }
    attachedBarcodeInputs[barcodeRow.node_id].push(
      parseJson(barcodeRow.material_payload_json, {}),
    );
  }

  const orderAssignment = await get(`
    SELECT h.order_no, c.name as client_name, opa.order_item_id
    FROM order_pipeline_assignments opa
    JOIN order_items i ON opa.order_item_id = i.id
    JOIN order_headers h ON i.order_no = h.order_no
    LEFT JOIN clients c ON h.client_id = c.id
    WHERE opa.pipeline_run_id = ?
    LIMIT 1
  `, [row.id]);

  const nodeMetrics = await getMergedNodeMetrics(row);

  return {
    id: row.id,
    templateId: row.template_id,
    templateVersion: row.template_version,
    name: row.name || '',
    status: row.status || 'planned',
    overrides: parseJson(row.overrides_json, {}),
    nodeStatuses: parseJson(row.node_status_json, {}),
    scrapRouting: row.scrap_routing || 'inventory',
    nodeMetrics,
    batches: parseJson(row.batches_json, []),
    attachedBarcodeInputs,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    createdAt: row.created_at,
    orderNo: orderAssignment?.order_no || null,
    clientName: orderAssignment?.client_name || null,
    orderItemId: orderAssignment?.order_item_id || null,
  };
}

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
      status: 'published',
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
      name: 'Dolly Production',
      description:
        'Copper and steel lanes converge into a welding stage before final assembly handoff.',
      version: 1,
      status: 'published',
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
      name: 'Assembly Mainline',
      description:
        'Three parallel sub-assemblies merge into a final assembly and packing handoff.',
      version: 1,
      status: 'published',
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


  // Migration for clients and vendors
  try { await run("ALTER TABLE clients ADD COLUMN logo_url TEXT DEFAULT ''"); } catch(e){}
  try { await run("ALTER TABLE clients ADD COLUMN photo_url TEXT DEFAULT ''"); } catch(e){}
  try { await run("ALTER TABLE vendors ADD COLUMN logo_url TEXT DEFAULT ''"); } catch(e){}
  try { await run("ALTER TABLE vendors ADD COLUMN photo_url TEXT DEFAULT ''"); } catch(e){}
  try { await run("ALTER TABLE items ADD COLUMN default_pipeline_id TEXT DEFAULT NULL"); } catch(e){}
  try { await run("ALTER TABLE items ADD COLUMN base_item_id INTEGER REFERENCES items(id) ON DELETE CASCADE"); } catch(e){}

  // Migration for groups table to remove unit_id NOT NULL constraint
  try {
    // 1. Recover from a half-migrated state if a previous run crashed
    const tables = await all("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('groups', 'groups_old_migration')");
    const hasGroups = tables.some(t => t.name === 'groups');
    const hasOldGroups = tables.some(t => t.name === 'groups_old_migration');

    if (hasOldGroups) {
      if (hasGroups) {
        // The migration finished creating 'groups' but crashed before dropping 'groups_old_migration'
        await run('DROP TABLE groups_old_migration');
        console.log('Cleaned up lingering groups_old_migration table from previous run.');
      } else {
        // The migration renamed 'groups' to 'groups_old_migration' but crashed before creating the new 'groups'
        await run('ALTER TABLE groups_old_migration RENAME TO groups');
        console.log('Recovered groups table from an interrupted migration run.');
      }
    }

    // 2. Perform the actual migration
    const tableInfo = await all("PRAGMA table_info(groups)");
    const unitIdCol = tableInfo.find(c => c.name === 'unit_id');
    if (unitIdCol && unitIdCol.notnull === 1) {
      console.log('Migrating groups table to remove NOT NULL constraint on unit_id...');
      await run('PRAGMA foreign_keys = OFF');
      // legacy_alter_table = ON stops the RENAME from rewriting other tables'
      // FK references to `groups` into `groups_old_migration` (which would
      // dangle once the temp table is dropped).
      await run('PRAGMA legacy_alter_table = ON');
      await run('BEGIN TRANSACTION');
      await run('ALTER TABLE groups RENAME TO groups_old_migration');
      await run(`
        CREATE TABLE groups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          group_type TEXT NOT NULL DEFAULT 'item',
          parent_group_id INTEGER REFERENCES groups(id),
          unit_id INTEGER REFERENCES units(id),
          is_archived INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      `);
      await run('INSERT INTO groups (id, name, parent_group_id, unit_id, is_archived, created_at, updated_at) SELECT id, name, parent_group_id, unit_id, is_archived, created_at, updated_at FROM groups_old_migration');
      await run('DROP TABLE groups_old_migration');
      await run('COMMIT');
      await run('PRAGMA legacy_alter_table = OFF');
      await run('PRAGMA foreign_keys = ON');
      console.log('Successfully migrated groups table.');
    }
  } catch (err) {
    await run('ROLLBACK').catch(() => {});
    await run('PRAGMA legacy_alter_table = OFF').catch(() => {});
    await run('PRAGMA foreign_keys = ON');
    console.error('Migration failed:', err);
  }

  // Re-run the repair: heals any references this run's migration may have left
  // dangling (older DBs broken before the legacy_alter_table guard), so the
  // fix takes effect immediately instead of after the next restart.
  await repairGroupsOldMigrationRefs();

  await run(`
    CREATE TABLE IF NOT EXISTS materials (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      barcode TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      grade TEXT,
      thickness TEXT,
      supplier TEXT,
      location TEXT,
      unit_id INTEGER,
      unit TEXT,
      notes TEXT,
      group_mode TEXT,
      inheritance_enabled INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      kind TEXT NOT NULL,
      parent_barcode TEXT,
      number_of_children INTEGER NOT NULL DEFAULT 0,
      linked_child_barcodes TEXT,
      scan_count INTEGER NOT NULL DEFAULT 0,
      linked_group_id INTEGER REFERENCES groups(id),
      linked_item_id INTEGER REFERENCES items(id),
      linked_variation_leaf_node_id INTEGER REFERENCES item_variation_nodes(id),
      custom_variation_values_json TEXT DEFAULT '{}',
      display_stock TEXT DEFAULT '',
      created_by TEXT DEFAULT '',
      workflow_status TEXT DEFAULT 'notStarted',
      material_class TEXT DEFAULT 'raw_material',
      inventory_state TEXT DEFAULT 'available',
      procurement_state TEXT DEFAULT 'not_ordered',
      traceability_mode TEXT DEFAULT 'bulk',
      on_hand_qty REAL NOT NULL DEFAULT 0,
      reserved_qty REAL NOT NULL DEFAULT 0,
      available_to_promise_qty REAL NOT NULL DEFAULT 0,
      incoming_qty REAL NOT NULL DEFAULT 0,
      linked_order_count INTEGER NOT NULL DEFAULT 0,
      linked_pipeline_count INTEGER NOT NULL DEFAULT 0,
      pending_alert_count INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT,
      last_scanned_at TEXT
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS scan_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      barcode TEXT NOT NULL,
      scanned_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS material_activity (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      barcode TEXT NOT NULL,
      event_type TEXT NOT NULL,
      event_label TEXT NOT NULL,
      event_description TEXT DEFAULT '',
      actor TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      failed_login_attempts INTEGER NOT NULL DEFAULT 0,
      first_failed_login_at TEXT,
      lockout_until TEXT,
      last_login_at TEXT,
      last_login_ip TEXT DEFAULT '',
      created_by_user_id INTEGER REFERENCES users(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS auth_sessions (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id),
      token_hash TEXT NOT NULL,
      created_at TEXT NOT NULL,
      last_used_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      revoked_at TEXT,
      revoked_reason TEXT DEFAULT '',
      ip_address TEXT DEFAULT '',
      user_agent TEXT DEFAULT ''
    )
  `);

  await run('CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions(user_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_auth_sessions_revoked ON auth_sessions(revoked_at)');

  await run(`
    CREATE TABLE IF NOT EXISTS delete_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      entity_label TEXT DEFAULT '',
      reason TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending',
      requested_by_user_id INTEGER NOT NULL REFERENCES users(id),
      reviewed_by_user_id INTEGER REFERENCES users(id),
      reviewed_at TEXT,
      created_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS auth_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_type TEXT NOT NULL,
      actor_user_id INTEGER REFERENCES users(id),
      target_user_id INTEGER REFERENCES users(id),
      ip_address TEXT DEFAULT '',
      user_agent TEXT DEFAULT '',
      metadata_json TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_auth_events_created ON auth_events(created_at)');
  await run('CREATE INDEX IF NOT EXISTS idx_auth_events_target ON auth_events(target_user_id)');
  await run(`
    CREATE TABLE IF NOT EXISTS role_permissions (
      role TEXT NOT NULL,
      permission_key TEXT NOT NULL,
      is_allowed INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(role, permission_key)
    )
  `);
  await run(`
    CREATE TABLE IF NOT EXISTS user_permission_overrides (
      user_id INTEGER NOT NULL REFERENCES users(id),
      permission_key TEXT NOT NULL,
      is_allowed INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(user_id, permission_key)
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_user_permission_overrides_user ON user_permission_overrides(user_id)');
  await run(`
    CREATE TABLE IF NOT EXISTS permission_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT DEFAULT '',
      is_system_default INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);
  await run(`
    CREATE TABLE IF NOT EXISTS permission_template_permissions (
      template_id INTEGER NOT NULL REFERENCES permission_templates(id),
      permission_key TEXT NOT NULL,
      is_allowed INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(template_id, permission_key)
    )
  `);
  await run(`
    CREATE TABLE IF NOT EXISTS user_permission_templates (
      user_id INTEGER NOT NULL REFERENCES users(id),
      template_id INTEGER NOT NULL REFERENCES permission_templates(id),
      created_at TEXT NOT NULL,
      PRIMARY KEY(user_id, template_id)
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_user_permission_templates_user ON user_permission_templates(user_id)');

  await run(`
    CREATE TABLE IF NOT EXISTS material_group_item_links (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL REFERENCES materials(id),
      item_id INTEGER NOT NULL REFERENCES items(id),
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(material_id, item_id)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS material_group_properties (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL REFERENCES materials(id),
      property_key TEXT NOT NULL,
      display_name TEXT NOT NULL,
      input_type TEXT NOT NULL DEFAULT 'Text',
      mandatory INTEGER NOT NULL DEFAULT 0,
      source_type TEXT NOT NULL DEFAULT 'manual',
      source_item_ids_json TEXT NOT NULL DEFAULT '[]',
      state TEXT NOT NULL DEFAULT 'active',
      override_locked INTEGER NOT NULL DEFAULT 0,
      has_type_conflict INTEGER NOT NULL DEFAULT 0,
      coverage_count INTEGER NOT NULL DEFAULT 0,
      selected_item_count_at_resolution INTEGER NOT NULL DEFAULT 0,
      resolution_source TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(material_id, property_key)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS material_group_units (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL REFERENCES materials(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      state TEXT NOT NULL DEFAULT 'active',
      is_primary INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(material_id, unit_id)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS material_group_preferences (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL REFERENCES materials(id),
      common_only_mode INTEGER NOT NULL DEFAULT 1,
      show_partial_matches INTEGER NOT NULL DEFAULT 1,
      discarded_property_keys_json TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(material_id)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS variation_stock (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      variation_leaf_node_id INTEGER NOT NULL REFERENCES item_variation_nodes(id) ON DELETE CASCADE,
      quantity REAL NOT NULL DEFAULT 0 CHECK (quantity >= 0),
      location_id TEXT DEFAULT 'MAIN',
      variation_path_label TEXT DEFAULT '',
      variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
      custom_variation_values_json TEXT DEFAULT '{}',
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(item_id, variation_leaf_node_id, location_id)
    );
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS inventory_stock_positions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_barcode TEXT NOT NULL,
      location_id TEXT NOT NULL DEFAULT 'MAIN',
      lot_code TEXT NOT NULL DEFAULT '',
      unit_id INTEGER,
      on_hand_qty REAL NOT NULL DEFAULT 0,
      reserved_qty REAL NOT NULL DEFAULT 0,
      damaged_qty REAL NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      UNIQUE(material_barcode, location_id, lot_code)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS inventory_movements (
      id TEXT PRIMARY KEY,
      material_barcode TEXT NOT NULL,
      movement_type TEXT NOT NULL,
      qty REAL NOT NULL,
      primary_qty REAL,
      uom TEXT,
      from_location_id TEXT,
      to_location_id TEXT,
      item_id INTEGER,
      variation_leaf_node_id INTEGER,
      reason_code TEXT,
      reference_type TEXT,
      reference_id TEXT,
      source_challan_id INTEGER,
      source_challan_type TEXT,
      source_challan_line_id INTEGER,
      reverses_movement_id TEXT,
      actor TEXT DEFAULT '',
      lot_code TEXT DEFAULT '',
      created_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS inventory_reservations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_barcode TEXT NOT NULL,
      reference_type TEXT NOT NULL,
      reference_id TEXT NOT NULL,
      reserved_qty REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS inventory_alerts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_barcode TEXT NOT NULL,
      alert_type TEXT NOT NULL,
      severity TEXT NOT NULL DEFAULT 'warning',
      message TEXT NOT NULL DEFAULT '',
      is_open INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS unit_groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS units (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      symbol TEXT NOT NULL,
      unit_group_id INTEGER REFERENCES unit_groups(id),
      conversion_factor REAL NOT NULL DEFAULT 1,
      conversion_base_unit_id INTEGER REFERENCES units(id),
      notes TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      logo_url TEXT DEFAULT '',
      photo_url TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      group_type TEXT NOT NULL DEFAULT 'item',
      group_structure TEXT NOT NULL DEFAULT 'hierarchical',
      description TEXT NOT NULL DEFAULT '',
      parent_group_id INTEGER REFERENCES groups(id),
      unit_id INTEGER REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS group_item_memberships (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(group_id, item_id)
    );
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_group_item_memberships_group ON group_item_memberships(group_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_group_item_memberships_item ON group_item_memberships(item_id)');

  await run(`
    CREATE TABLE IF NOT EXISTS clients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      gst_number TEXT DEFAULT '',
      address TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS vendors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      gst_number TEXT DEFAULT '',
      address TEXT DEFAULT '',
      contact_name TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      email TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS departments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT DEFAULT '',
      photo_url TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      department_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      role TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      aadhar_number TEXT DEFAULT '',
      aadhar_photo_url TEXT DEFAULT '',
      pan_number TEXT DEFAULT '',
      pan_photo_url TEXT DEFAULT '',
      address TEXT DEFAULT '',
      employee_photo_url TEXT DEFAULT '',
      employment_type TEXT DEFAULT 'in-house',
      status TEXT DEFAULT 'active',
      barcode_id TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (department_id) REFERENCES departments (id) ON DELETE CASCADE
    )
  `);

  try {
    await run(`ALTER TABLE employees ADD COLUMN aadhar_number TEXT DEFAULT ''`);
    await run(`ALTER TABLE employees ADD COLUMN aadhar_photo_url TEXT DEFAULT ''`);
    await run(`ALTER TABLE employees ADD COLUMN pan_number TEXT DEFAULT ''`);
    await run(`ALTER TABLE employees ADD COLUMN pan_photo_url TEXT DEFAULT ''`);
    await run(`ALTER TABLE employees ADD COLUMN address TEXT DEFAULT ''`);
    await run(`ALTER TABLE employees ADD COLUMN employee_photo_url TEXT DEFAULT ''`);
  } catch (e) {
    // Columns might already exist
  }

  await run(`
    CREATE TABLE IF NOT EXISTS freelancer_job_batches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      freelancer_id INTEGER REFERENCES employees(id),
      batch_number TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'assigned',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS freelancer_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id INTEGER REFERENCES freelancer_job_batches(id) ON DELETE SET NULL,
      item_id INTEGER REFERENCES items(id),
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      quantity INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'pending',
      payout_balance REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  try { await run("ALTER TABLE freelancer_jobs ADD COLUMN batch_id INTEGER REFERENCES freelancer_job_batches(id) ON DELETE SET NULL"); } catch(e){}
  try { await run("ALTER TABLE freelancer_jobs ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1"); } catch(e){}


  await run(`
    CREATE TABLE IF NOT EXISTS freelancer_job_tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_id INTEGER NOT NULL REFERENCES freelancer_jobs(id) ON DELETE CASCADE,
      item_id INTEGER NOT NULL REFERENCES items(id),
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      required_quantity REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS company_profiles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_name TEXT NOT NULL,
      mobile TEXT DEFAULT '',
      business_description TEXT DEFAULT '',
      address TEXT DEFAULT '',
      state_code TEXT DEFAULT '',
      gstin TEXT DEFAULT '',
      logo_url TEXT DEFAULT '',
      signature_label TEXT DEFAULT '',
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      short_code TEXT DEFAULT '',
      display_name TEXT NOT NULL,
      quantity REAL NOT NULL DEFAULT 0,
      group_id INTEGER NOT NULL REFERENCES groups(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      default_pipeline_id TEXT DEFAULT NULL,
      base_item_id INTEGER REFERENCES items(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS user_favorite_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      variation_path_label TEXT NOT NULL DEFAULT '',
      variation_path_node_ids TEXT NOT NULL DEFAULT '[]',
      custom_variation_values TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL,
      UNIQUE(user_id, item_id, variation_leaf_node_id)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_unit_conversions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id),
      factor_to_primary REAL NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, unit_id)
    )
  `);

  await run(
    'CREATE INDEX IF NOT EXISTS idx_item_unit_conversions_item_id ON item_unit_conversions(item_id)',
  );

  await run(`
    CREATE TABLE IF NOT EXISTS item_property_schema (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      property_key TEXT NOT NULL,
      display_name TEXT NOT NULL,
      input_type TEXT NOT NULL DEFAULT 'Text',
      mandatory INTEGER NOT NULL DEFAULT 0,
      unit_id INTEGER,
      unit_symbol TEXT,
      unit_label TEXT,
      source_type TEXT NOT NULL DEFAULT 'manual',
      source_group_id INTEGER,
      source_group_name TEXT,
      source_item_ids_json TEXT NOT NULL DEFAULT '[]',
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, property_key)
    )
  `);

  await run(
    'CREATE INDEX IF NOT EXISTS idx_item_property_schema_item_id ON item_property_schema(item_id)',
  );

  await run(`
    CREATE TABLE IF NOT EXISTS item_bom_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      material_barcode TEXT NOT NULL,
      material_name TEXT DEFAULT '',
      quantity_per_unit REAL NOT NULL DEFAULT 1,
      wastage_percent REAL NOT NULL DEFAULT 0,
      unit_id INTEGER REFERENCES units(id),
      unit_symbol TEXT DEFAULT '',
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, material_barcode)
    )
  `);

  await run(
    'CREATE INDEX IF NOT EXISTS idx_item_bom_lines_item_id ON item_bom_lines(item_id, sort_order ASC, id ASC)',
  );

  await run(`
    CREATE TABLE IF NOT EXISTS inventory_sets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS inventory_set_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      set_id INTEGER NOT NULL REFERENCES inventory_sets(id) ON DELETE CASCADE,
      item_id INTEGER NOT NULL REFERENCES items(id),
      variation_leaf_node_id INTEGER REFERENCES item_variation_nodes(id),
      quantity INTEGER NOT NULL DEFAULT 1,
      position INTEGER NOT NULL DEFAULT 0,
      UNIQUE(set_id, item_id, variation_leaf_node_id)
    )
  `);
  await run(
    'CREATE INDEX IF NOT EXISTS idx_inventory_set_lines_set_id ON inventory_set_lines(set_id)',
  );
  await run(
    'CREATE INDEX IF NOT EXISTS idx_inventory_set_lines_item_id ON inventory_set_lines(item_id)',
  );

  await run(`
    CREATE TABLE IF NOT EXISTS search_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER REFERENCES users(id),
      query TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  `);
  await run(
    'CREATE INDEX IF NOT EXISTS idx_search_history_user_id ON search_history(user_id)',
  );
  await run(`
    CREATE TABLE IF NOT EXISTS search_clicks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER REFERENCES users(id),
      query TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      entity_label TEXT,
      created_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL DEFAULT 'delivery',
      order_id INTEGER REFERENCES order_items(id),
      order_no TEXT DEFAULT '',
      challan_no TEXT NOT NULL UNIQUE,
      date TEXT NOT NULL,
      location TEXT DEFAULT 'MAIN',
      customer_name TEXT NOT NULL DEFAULT '',
      customer_gstin TEXT DEFAULT '',
      vendor_id INTEGER REFERENCES vendors(id),
      vendor_name TEXT DEFAULT '',
      vendor_gstin TEXT DEFAULT '',
      material_owner_client_id INTEGER REFERENCES clients(id),
      material_owner_client_name TEXT DEFAULT '',
      material_owner_gstin TEXT DEFAULT '',
      source_reference TEXT DEFAULT '',
      company_profile_snapshot TEXT,
      template_snapshot_json TEXT,
      notes TEXT DEFAULT '',
      maintain_stocks INTEGER NOT NULL DEFAULT 1,
      used_in_report INTEGER NOT NULL DEFAULT 0,
      purpose TEXT NOT NULL DEFAULT 'trading',
      status TEXT NOT NULL DEFAULT 'draft',
      created_by INTEGER REFERENCES users(id),
      updated_by INTEGER REFERENCES users(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challan_items (
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
      custom_variation_values_json TEXT DEFAULT '{}',
      note TEXT DEFAULT '',
      quantity_pcs REAL NOT NULL DEFAULT 0,
      weight REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challan_order_items (
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      order_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (challan_id, order_id)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS report_groups (
      code TEXT PRIMARY KEY,
      label TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challan_report_groups (
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      report_group_code TEXT NOT NULL REFERENCES report_groups(code) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (challan_id, report_group_code)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challan_activity_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      activity_type TEXT NOT NULL,
      actor_user_id INTEGER,
      actor_name TEXT,
      actor_role TEXT,
      details_json TEXT,
      created_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS challan_template_upload_sessions (
      id TEXT PRIMARY KEY,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL,
      upload_type TEXT NOT NULL DEFAULT 'CHALLAN_TEMPLATE_BACKGROUND',
      object_key TEXT NOT NULL,
      canvas_width INTEGER NOT NULL DEFAULT 0,
      canvas_height INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      completed_at TEXT
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS challan_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      party_type TEXT NOT NULL,
      party_id INTEGER NOT NULL,
      challan_type TEXT NOT NULL,
      background_object_key TEXT NOT NULL,
      canvas_width INTEGER NOT NULL,
      canvas_height INTEGER NOT NULL,
      rotation_degrees REAL NOT NULL DEFAULT 0,
      global_offset_x_mm REAL NOT NULL DEFAULT 0,
      global_offset_y_mm REAL NOT NULL DEFAULT 0,
      stock_size TEXT NOT NULL DEFAULT 'A4',
      paper_size TEXT NOT NULL DEFAULT 'A4',
      n_up_layout INTEGER NOT NULL DEFAULT 1,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS challan_template_mappings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      template_id INTEGER NOT NULL REFERENCES challan_templates(id) ON DELETE CASCADE,
      field_type TEXT NOT NULL DEFAULT 'DYNAMIC',
      field_key TEXT NOT NULL,
      field_value TEXT NOT NULL DEFAULT '',
      asset_object_key TEXT NOT NULL DEFAULT '',
      asset_width_px INTEGER NOT NULL DEFAULT 0,
      asset_height_px INTEGER NOT NULL DEFAULT 0,
      width_mm REAL NOT NULL DEFAULT 80,
      height_mm REAL NOT NULL DEFAULT 12,
      image_width_mm REAL NOT NULL DEFAULT 35,
      image_height_mm REAL NOT NULL DEFAULT 20,
      lock_aspect_ratio INTEGER NOT NULL DEFAULT 1,
      x_mm REAL NOT NULL DEFAULT 0,
      y_mm REAL NOT NULL DEFAULT 0,
      x_percent REAL NOT NULL,
      y_percent REAL NOT NULL,
      font_size REAL NOT NULL DEFAULT 10,
      font_weight TEXT NOT NULL DEFAULT 'normal',
      alignment TEXT NOT NULL DEFAULT 'left',
      text_color TEXT NOT NULL DEFAULT 'black',
      letter_spacing REAL NOT NULL DEFAULT 0,
      max_chars INTEGER NOT NULL DEFAULT 0,
      max_width_mm REAL NOT NULL DEFAULT 80,
      min_font_size REAL NOT NULL DEFAULT 6,
      min_rows INTEGER NOT NULL DEFAULT 0,
      max_rows INTEGER NOT NULL DEFAULT 0,
      table_height_mm REAL NOT NULL DEFAULT 60,
      row_height_mm REAL NOT NULL DEFAULT 6,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(template_id, field_key)
    )
  `);

  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challans_status ON delivery_challans(status)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challans_date ON delivery_challans(date)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_items_challan_id ON delivery_challan_items(challan_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_orders_challan_id ON delivery_challan_order_items(challan_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_orders_order_id ON delivery_challan_order_items(order_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_report_groups_challan_id ON delivery_challan_report_groups(challan_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_report_groups_code ON delivery_challan_report_groups(report_group_code)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_activity_challan_id_created_at ON delivery_challan_activity_log(challan_id, created_at)');
  await run('CREATE INDEX IF NOT EXISTS idx_challan_template_upload_sessions_sha256 ON challan_template_upload_sessions(sha256)');
  await run('CREATE INDEX IF NOT EXISTS idx_challan_templates_party ON challan_templates(party_type, party_id, challan_type, is_active)');
  await run('CREATE INDEX IF NOT EXISTS idx_challan_template_mappings_template_id ON challan_template_mappings(template_id)');

  await run(`
    CREATE TABLE IF NOT EXISTS invoice_headers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_no TEXT NOT NULL UNIQUE,
      client_id INTEGER REFERENCES clients(id),
      client_name TEXT NOT NULL DEFAULT '',
      gstin TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'draft',
      invoice_date TEXT NOT NULL,
      total_quantity REAL NOT NULL DEFAULT 0,
      taxable_value REAL NOT NULL DEFAULT 0,
      cgst_amount REAL NOT NULL DEFAULT 0,
      sgst_amount REAL NOT NULL DEFAULT 0,
      total_amount REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);
  await run(`
    CREATE TABLE IF NOT EXISTS invoice_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL REFERENCES invoice_headers(id) ON DELETE CASCADE,
      order_id INTEGER,
      challan_id INTEGER REFERENCES delivery_challans(id),
      challan_item_id INTEGER REFERENCES delivery_challan_items(id),
      item_id INTEGER,
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      item_name TEXT NOT NULL DEFAULT '',
      hsn_code TEXT DEFAULT '',
      quantity REAL NOT NULL DEFAULT 0,
      unit_price REAL NOT NULL DEFAULT 0,
      taxable_value REAL NOT NULL DEFAULT 0,
      cgst_rate REAL NOT NULL DEFAULT 0,
      sgst_rate REAL NOT NULL DEFAULT 0,
      cgst_amount REAL NOT NULL DEFAULT 0,
      sgst_amount REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);
  await run(`
    CREATE TABLE IF NOT EXISTS reconciliation_conversion_overrides (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL,
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      conversion_ratio REAL NOT NULL DEFAULT 1,
      from_unit TEXT NOT NULL DEFAULT 'kg',
      to_unit_label TEXT NOT NULL DEFAULT 'units',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, variation_leaf_node_id)
    )
  `);
  await run(`
    CREATE TABLE IF NOT EXISTS reconciliation_waste_audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id INTEGER,
      client_name TEXT NOT NULL DEFAULT '',
      item_id INTEGER,
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      item_name TEXT NOT NULL DEFAULT '',
      challan_id INTEGER REFERENCES delivery_challans(id),
      challan_no TEXT DEFAULT '',
      input_weight_kg REAL NOT NULL DEFAULT 0,
      shipped_weight_kg REAL NOT NULL DEFAULT 0,
      waste_weight_kg REAL NOT NULL DEFAULT 0,
      waste_percentage REAL NOT NULL DEFAULT 0,
      source TEXT NOT NULL DEFAULT 'report_snapshot',
      created_at TEXT NOT NULL
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_invoice_lines_invoice_id ON invoice_lines(invoice_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_invoice_lines_challan_item ON invoice_lines(challan_item_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_invoice_lines_order_id ON invoice_lines(order_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_reconciliation_conversion_item ON reconciliation_conversion_overrides(item_id, variation_leaf_node_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_reconciliation_waste_client_item ON reconciliation_waste_audit(client_id, item_id, variation_leaf_node_id)');

  await run(`
    CREATE TABLE IF NOT EXISTS production_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_code TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'completed',
      completed_at TEXT,
      item_id INTEGER NOT NULL REFERENCES items(id),
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      variation_path_label TEXT DEFAULT '',
      output_quantity REAL NOT NULL DEFAULT 0,
      uom TEXT DEFAULT 'pcs',
      location TEXT DEFAULT '',
      source_metadata_json TEXT DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_production_runs_status ON production_runs(status, completed_at)');
  await run('CREATE INDEX IF NOT EXISTS idx_production_runs_item ON production_runs(item_id, variation_leaf_node_id)');

  await run(`
    CREATE TABLE IF NOT EXISTS deleted_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      record_id INTEGER NOT NULL,
      data_json TEXT NOT NULL,
      deleted_at TEXT NOT NULL,
      deleted_by TEXT
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS sub_contractors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS order_headers (
      order_no TEXT PRIMARY KEY,
      client_id INTEGER NOT NULL REFERENCES clients(id),
      sub_contractor_id INTEGER REFERENCES sub_contractors(id),
      po_number TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT ''
    )
  `);



  await run(`
    CREATE TABLE IF NOT EXISTS order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_no TEXT NOT NULL REFERENCES order_headers(order_no),
      client_id INTEGER NOT NULL REFERENCES clients(id),
      sub_contractor_id INTEGER REFERENCES sub_contractors(id),
      client_name TEXT NOT NULL DEFAULT '',
      po_number TEXT DEFAULT '',
      client_code TEXT DEFAULT '',
      item_id INTEGER NOT NULL REFERENCES items(id),
      item_name TEXT NOT NULL DEFAULT '',
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      variation_path_label TEXT DEFAULT '',
      variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
      custom_variation_values_json TEXT DEFAULT '{}',
      quantity INTEGER NOT NULL DEFAULT 0,
      unit_id INTEGER REFERENCES units(id),
      unit_name TEXT NOT NULL DEFAULT 'Pieces',
      unit_symbol TEXT NOT NULL DEFAULT 'Pieces',
      unit_price REAL NOT NULL DEFAULT 0,
      total_invoiced_qty REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'notStarted',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT '',
      start_date TEXT,
      end_date TEXT,
      hsn_code TEXT DEFAULT '',
      taxable_value REAL DEFAULT 0,
      cgst_rate REAL DEFAULT 0,
      sgst_rate REAL DEFAULT 0,
      cgst_amount REAL DEFAULT 0,
      sgst_amount REAL DEFAULT 0
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS po_documents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL UNIQUE,
      object_key TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'uploaded',
      created_at TEXT NOT NULL,
      uploaded_at TEXT
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS po_upload_sessions (
      id TEXT PRIMARY KEY,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL,
      object_key TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      completed_at TEXT
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS order_po_documents (
      order_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
      document_id INTEGER NOT NULL REFERENCES po_documents(id) ON DELETE CASCADE,
      linked_at TEXT NOT NULL,
      PRIMARY KEY (order_id, document_id)
    )
  `);

  await run(
    'CREATE INDEX IF NOT EXISTS idx_order_po_documents_order_id ON order_po_documents(order_id)',
  );
  await run(
    'CREATE INDEX IF NOT EXISTS idx_po_upload_sessions_sha256 ON po_upload_sessions(sha256)',
  );

  await run(`
    CREATE TABLE IF NOT EXISTS uploaded_assets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id INTEGER NOT NULL,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL,
      object_key TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'uploaded',
      is_primary INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      uploaded_at TEXT
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS asset_upload_sessions (
      id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id INTEGER NOT NULL,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL,
      object_key TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      is_primary INTEGER NOT NULL DEFAULT 0,
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      completed_at TEXT
    )
  `);

  await run(
    'CREATE INDEX IF NOT EXISTS idx_uploaded_assets_entity ON uploaded_assets(entity_type, entity_id, status, is_primary)',
  );
  await run(
    'CREATE INDEX IF NOT EXISTS idx_asset_upload_sessions_entity ON asset_upload_sessions(entity_type, entity_id)',
  );

  await run(`
    CREATE TABLE IF NOT EXISTS order_material_requirements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
      item_id INTEGER,
      variation_leaf_node_id INTEGER,
      material_id INTEGER,
      material_barcode TEXT,
      material_name TEXT,
      required_qty REAL NOT NULL DEFAULT 0,
      allocated_qty REAL NOT NULL DEFAULT 0,
      consumed_qty REAL NOT NULL DEFAULT 0,
      shortage_qty REAL NOT NULL DEFAULT 0,
      unit_id INTEGER,
      unit_symbol TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS order_status_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
      previous_status TEXT,
      new_status TEXT NOT NULL,
      changed_by_user_id INTEGER,
      changed_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS order_activity_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
      activity_type TEXT NOT NULL,
      actor_user_id INTEGER,
      actor_name TEXT,
      actor_role TEXT,
      source TEXT,
      details_json TEXT,
      created_at TEXT NOT NULL
    )
  `);

  await run('CREATE INDEX IF NOT EXISTS idx_order_material_requirements_order_id ON order_material_requirements(order_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_order_material_requirements_material_barcode ON order_material_requirements(material_barcode)');
  await run('CREATE INDEX IF NOT EXISTS idx_order_status_history_order_id_changed_at ON order_status_history(order_id, changed_at)');
  await run('CREATE INDEX IF NOT EXISTS idx_order_activity_log_order_id_created_at ON order_activity_log(order_id, created_at)');

  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER REFERENCES orders(id),
      order_no TEXT DEFAULT '',
      challan_no TEXT NOT NULL UNIQUE,
      date TEXT NOT NULL,
      customer_name TEXT NOT NULL DEFAULT '',
      customer_gstin TEXT DEFAULT '',
      company_profile_snapshot TEXT,
      notes TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'draft',
      created_by INTEGER REFERENCES users(id),
      updated_by INTEGER REFERENCES users(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challan_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      order_item_id INTEGER,
      item_id INTEGER,
      line_no INTEGER NOT NULL DEFAULT 1,
      particulars TEXT NOT NULL DEFAULT '',
      hsn_code TEXT DEFAULT '',
      variation_path_label TEXT DEFAULT '',
      variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
      note TEXT DEFAULT '',
      custom_variation_values_json TEXT DEFAULT '{}',
      quantity_pcs TEXT DEFAULT '',
      weight TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challan_activity_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      activity_type TEXT NOT NULL,
      actor_user_id INTEGER,
      actor_name TEXT,
      actor_role TEXT,
      details_json TEXT,
      created_at TEXT NOT NULL
    )
  `);

  // Track: generic per-entity activity log powering the "Track" tab on masters
  // and a person's People profile. Written by trackCreate/Update/Delete.
  await run(`
    CREATE TABLE IF NOT EXISTS entity_activity_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      action TEXT NOT NULL,
      actor_user_id INTEGER,
      actor_name TEXT,
      actor_role TEXT,
      changes_json TEXT,
      details_json TEXT,
      created_at TEXT NOT NULL
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_entity_activity_log_entity ON entity_activity_log(entity_type, entity_id, created_at)');
  await run('CREATE INDEX IF NOT EXISTS idx_entity_activity_log_actor ON entity_activity_log(actor_user_id, created_at)');

  // Per-record (row-level) permission grants for an individual user.
  await run(`
    CREATE TABLE IF NOT EXISTS user_record_permissions (
      user_id INTEGER NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      op TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (user_id, entity_type, entity_id, op)
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_user_record_permissions_user ON user_record_permissions(user_id)');

  // --- Column migrations for order_activity_log on pre-existing databases ---
  // The CREATE TABLE above is skipped if the table already exists. These
  // ensureColumnExists calls add any missing columns added in later versions.
  await ensureColumnExists('order_activity_log', 'activity_type', "TEXT NOT NULL DEFAULT ''");
  await ensureColumnExists('order_activity_log', 'actor_user_id', 'INTEGER');
  await ensureColumnExists('order_activity_log', 'actor_name', 'TEXT');
  await ensureColumnExists('order_activity_log', 'actor_role', 'TEXT');
  await ensureColumnExists('order_activity_log', 'source', 'TEXT');
  await ensureColumnExists('order_activity_log', 'details_json', 'TEXT');
  await migrateOrderActivityLogCompatibilityColumns();

  await ensureColumnExists('groups', 'group_type', "TEXT NOT NULL DEFAULT 'item'");
  // Enhancement 2: combination groups (flat variant sets) + optional description.
  await ensureColumnExists('groups', 'group_structure', "TEXT NOT NULL DEFAULT 'hierarchical'");
  await ensureColumnExists('groups', 'description', "TEXT NOT NULL DEFAULT ''");

  await ensureColumnExists('items', 'photo_url', 'TEXT DEFAULT NULL');

  await ensureColumnExists('delivery_challans', 'order_id', 'INTEGER');
  await ensureColumnExists('delivery_challans', 'order_no', "TEXT DEFAULT ''");
  await ensureColumnExists('delivery_challans', 'type', "TEXT NOT NULL DEFAULT 'delivery'");
  await ensureColumnExists('delivery_challans', 'location', "TEXT DEFAULT 'MAIN'");
  await ensureColumnExists('delivery_challans', 'vendor_id', 'INTEGER');
  await ensureColumnExists('delivery_challans', 'vendor_name', "TEXT DEFAULT ''");
  await ensureColumnExists('delivery_challans', 'vendor_gstin', "TEXT DEFAULT ''");
  await ensureColumnExists('delivery_challans', 'material_owner_client_id', 'INTEGER');
  await ensureColumnExists('delivery_challans', 'material_owner_client_name', "TEXT DEFAULT ''");
  await ensureColumnExists('delivery_challans', 'material_owner_gstin', "TEXT DEFAULT ''");
  await ensureColumnExists('delivery_challans', 'source_reference', "TEXT DEFAULT ''");
  await ensureColumnExists('delivery_challans', 'template_snapshot_json', 'TEXT');
  await ensureColumnExists('delivery_challans', 'maintain_stocks', 'INTEGER NOT NULL DEFAULT 1');
  await ensureColumnExists('delivery_challans', 'used_in_report', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('delivery_challans', 'purpose', "TEXT NOT NULL DEFAULT 'trading'");
  // Internal challans — free-text purpose (production consumption / transfers).
  await ensureColumnExists('delivery_challans', 'internal_purpose', "TEXT NOT NULL DEFAULT ''");
  // Reconciliation of an internal-use challan: JSON breakdown of each consumed
  // line settled across scrap/leftover/lost/rejection/finished-goods. Empty
  // until the mobile In-use reconciliation flow settles the challan.
  await ensureColumnExists('delivery_challans', 'reconciliation_json', "TEXT NOT NULL DEFAULT ''");
  await ensureColumnExists('delivery_challan_items', 'order_item_id', 'INTEGER');
  await ensureColumnExists('delivery_challan_items', 'production_run_id', 'INTEGER');
  await ensureColumnExists('delivery_challan_items', 'item_id', 'INTEGER');
  await ensureColumnExists('delivery_challan_items', 'variation_leaf_node_id', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('delivery_challan_items', 'variation_path_label', "TEXT DEFAULT ''");
  await ensureColumnExists('delivery_challan_items', 'variation_path_node_ids_json', "TEXT NOT NULL DEFAULT '[]'");
  await ensureColumnExists('delivery_challan_items', 'note', "TEXT DEFAULT ''");
  await ensureDeliveryChallanItemNumericColumns();
  await ensureColumnExists('delivery_challan_items', 'production_run_id', 'INTEGER');
  await ensureColumnExists('delivery_challan_items', 'variation_leaf_node_id', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('delivery_challan_items', 'variation_path_label', "TEXT DEFAULT ''");
  await ensureColumnExists('delivery_challan_items', 'variation_path_node_ids_json', "TEXT NOT NULL DEFAULT '[]'");
  await ensureColumnExists('delivery_challan_items', 'note', "TEXT DEFAULT ''");
  await ensureColumnExists('delivery_challan_items', 'custom_variation_values_json', "TEXT DEFAULT '{}'");
  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challan_order_items (
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      order_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (challan_id, order_id)
    )
  `);
  await run(`
    CREATE TABLE IF NOT EXISTS report_groups (
      code TEXT PRIMARY KEY,
      label TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);
  await run(`
    CREATE TABLE IF NOT EXISTS delivery_challan_report_groups (
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      report_group_code TEXT NOT NULL REFERENCES report_groups(code) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (challan_id, report_group_code)
    )
  `);
  await ensureInventorySetLineNullableLeafReference();
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challans_order_id ON delivery_challans(order_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challans_vendor_id ON delivery_challans(vendor_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challans_material_owner ON delivery_challans(material_owner_client_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challans_type ON delivery_challans(type)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_items_challan_id ON delivery_challan_items(challan_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_orders_challan_id ON delivery_challan_order_items(challan_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_orders_order_id ON delivery_challan_order_items(order_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_report_groups_challan_id ON delivery_challan_report_groups(challan_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_delivery_challan_report_groups_code ON delivery_challan_report_groups(report_group_code)');
  await ensureColumnExists('challan_templates', 'rotation_degrees', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_templates', 'global_offset_x_mm', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_templates', 'global_offset_y_mm', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_templates', 'stock_size', "TEXT NOT NULL DEFAULT 'A4'");
  await ensureColumnExists('challan_templates', 'paper_size', "TEXT NOT NULL DEFAULT 'A4'");
  await ensureColumnExists('challan_templates', 'n_up_layout', 'INTEGER NOT NULL DEFAULT 1');
  await ensureColumnExists('challan_templates', 'is_active', 'INTEGER NOT NULL DEFAULT 1');
  await ensureColumnExists('challan_template_upload_sessions', 'upload_type', "TEXT NOT NULL DEFAULT 'CHALLAN_TEMPLATE_BACKGROUND'");
  await ensureColumnExists('challan_template_upload_sessions', 'canvas_width', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_template_upload_sessions', 'canvas_height', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_template_mappings', 'field_type', "TEXT NOT NULL DEFAULT 'DYNAMIC'");
  await ensureColumnExists('challan_template_mappings', 'field_value', "TEXT NOT NULL DEFAULT ''");
  await ensureColumnExists('challan_template_mappings', 'asset_object_key', "TEXT NOT NULL DEFAULT ''");
  await ensureColumnExists('challan_template_mappings', 'asset_width_px', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_template_mappings', 'asset_height_px', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_template_mappings', 'width_mm', 'REAL NOT NULL DEFAULT 80');
  await ensureColumnExists('challan_template_mappings', 'height_mm', 'REAL NOT NULL DEFAULT 12');
  await ensureColumnExists('challan_template_mappings', 'image_width_mm', 'REAL NOT NULL DEFAULT 35');
  await ensureColumnExists('challan_template_mappings', 'image_height_mm', 'REAL NOT NULL DEFAULT 20');
  await ensureColumnExists('challan_template_mappings', 'lock_aspect_ratio', 'INTEGER NOT NULL DEFAULT 1');
  await ensureColumnExists('challan_template_mappings', 'x_mm', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_template_mappings', 'y_mm', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_template_mappings', 'text_color', "TEXT NOT NULL DEFAULT 'black'");
  await ensureColumnExists('challan_template_mappings', 'max_width_mm', 'REAL NOT NULL DEFAULT 80');
  await ensureColumnExists('challan_template_mappings', 'min_font_size', 'REAL NOT NULL DEFAULT 6');
  await ensureColumnExists('challan_template_mappings', 'min_rows', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_template_mappings', 'max_rows', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('challan_template_mappings', 'table_height_mm', 'REAL NOT NULL DEFAULT 60');
  await run('CREATE INDEX IF NOT EXISTS idx_challan_templates_party ON challan_templates(party_type, party_id, challan_type, is_active)');
  await run('CREATE INDEX IF NOT EXISTS idx_challan_template_mappings_template_id ON challan_template_mappings(template_id)');

  // Foreign key indexes for production scaling on materials
  await run('CREATE INDEX IF NOT EXISTS idx_materials_linked_group_id ON materials(linked_group_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_materials_linked_item_id ON materials(linked_item_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_materials_parent_barcode ON materials(parent_barcode)');

  // Indexes for health dashboard and inventory status filtering
  await run('CREATE INDEX IF NOT EXISTS idx_materials_inventory_state ON materials(inventory_state)');
  await run('CREATE INDEX IF NOT EXISTS idx_materials_stock_quantities ON materials(on_hand_qty, available_to_promise_qty, reserved_qty)');
  await run('CREATE INDEX IF NOT EXISTS idx_inventory_movements_health_query ON inventory_movements(movement_type, created_at)');
  await run('CREATE INDEX IF NOT EXISTS idx_inventory_alerts_is_open ON inventory_alerts(is_open)');

  // Inventory Sets indexes
  await run('CREATE INDEX IF NOT EXISTS idx_inventory_sets_name ON inventory_sets(name)');
  await run('CREATE INDEX IF NOT EXISTS idx_inventory_set_lines_set_id ON inventory_set_lines(set_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_inventory_set_lines_item_lookup ON inventory_set_lines(item_id, variation_leaf_node_id)');

  await ensureColumnExists('order_items', 'updated_at', "TEXT NOT NULL DEFAULT ''");
  await ensureColumnExists('order_items', 'unit_id', 'INTEGER');
  await ensureColumnExists('order_items', 'unit_name', "TEXT NOT NULL DEFAULT 'Pieces'");
  await ensureColumnExists('order_items', 'unit_symbol', "TEXT NOT NULL DEFAULT 'Pieces'");
  await ensureColumnExists('order_items', 'unit_price', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('order_items', 'custom_variation_values_json', "TEXT DEFAULT '{}'");
  await ensureColumnExists(
    'order_items',
    'total_invoiced_qty',
    'REAL NOT NULL DEFAULT 0',
  );
  await ensureColumnExists('order_items', 'hsn_code', "TEXT DEFAULT ''");
  await ensureColumnExists('order_items', 'taxable_value', 'REAL DEFAULT 0');
  await ensureColumnExists('order_items', 'cgst_rate', 'REAL DEFAULT 0');
  await ensureColumnExists('order_items', 'sgst_rate', 'REAL DEFAULT 0');
  await ensureColumnExists('order_items', 'cgst_amount', 'REAL DEFAULT 0');
  await ensureColumnExists('order_items', 'sgst_amount', 'REAL DEFAULT 0');
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

  await run(`
    CREATE TABLE IF NOT EXISTS item_variations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      name TEXT NOT NULL DEFAULT '',
      alias TEXT DEFAULT '',
      display_name TEXT NOT NULL,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variation_dimensions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variation_values (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      variation_id INTEGER NOT NULL REFERENCES item_variations(id) ON DELETE CASCADE,
      dimension_id INTEGER NOT NULL REFERENCES item_variation_dimensions(id) ON DELETE CASCADE,
      value TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS item_variation_nodes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      parent_node_id INTEGER REFERENCES item_variation_nodes(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      code TEXT NOT NULL DEFAULT '',
      display_name TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await ensureColumnExists('items', 'quantity', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('items', 'naming_format', "TEXT NOT NULL DEFAULT ''");
  // Whether this item can be ordered as a purchase (reception) line on the
  // mobile Purchase-challan flow. Curated per item in the desktop item editor.
  await ensureColumnExists('items', 'available_for_purchase', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('item_unit_conversions', 'factor_to_primary', 'REAL NOT NULL DEFAULT 1');
  await ensureColumnExists('item_variations', 'alias', "TEXT DEFAULT ''");
  await ensureColumnExists('item_variations', 'display_name', "TEXT DEFAULT ''");
  await ensureColumnExists('item_variation_nodes', 'code', "TEXT NOT NULL DEFAULT ''");

  await ensureColumnExists('materials', 'unit_id', 'INTEGER');
  await ensureColumnExists('units', 'unit_group_id', 'INTEGER');
  await ensureColumnExists('units', 'conversion_factor', 'REAL NOT NULL DEFAULT 1');
  await ensureColumnExists('units', 'conversion_base_unit_id', 'INTEGER');
  await ensureColumnExists('materials', 'linked_group_id', 'INTEGER');
  await ensureColumnExists('materials', 'linked_item_id', 'INTEGER');
  await ensureColumnExists('materials', 'linked_variation_leaf_node_id', 'INTEGER');
  await ensureColumnExists('variation_stock', 'variation_path_label', "TEXT DEFAULT ''");
  await ensureColumnExists('variation_stock', 'variation_path_node_ids_json', "TEXT NOT NULL DEFAULT '[]'");
  await ensureColumnExists('variation_stock', 'custom_variation_values_json', "TEXT DEFAULT '{}'");
  await ensureColumnExists('groups', 'group_type', "TEXT NOT NULL DEFAULT 'item'");
  await run('CREATE INDEX IF NOT EXISTS idx_materials_item_variation_lookup ON materials(linked_item_id, linked_variation_leaf_node_id)');
  await ensureColumnExists('inventory_movements', 'primary_qty', 'REAL');
  await ensureColumnExists('inventory_movements', 'uom', 'TEXT');
  await ensureColumnExists('inventory_movements', 'item_id', 'INTEGER');
  await ensureColumnExists('inventory_movements', 'variation_leaf_node_id', 'INTEGER');
  await ensureColumnExists('inventory_movements', 'source_challan_id', 'INTEGER');
  await ensureColumnExists('inventory_movements', 'source_challan_type', 'TEXT');
  await ensureColumnExists('inventory_movements', 'source_challan_line_id', 'INTEGER');
  await ensureColumnExists('inventory_movements', 'reverses_movement_id', 'TEXT');
  await ensureColumnExists('inventory_movements', 'actor', "TEXT DEFAULT ''");
  await ensureColumnExists('inventory_movements', 'lot_code', "TEXT DEFAULT ''");
  await ensureColumnExists('inventory_stock_positions', 'location_id', "TEXT NOT NULL DEFAULT 'MAIN'");
  await ensureColumnExists('inventory_stock_positions', 'lot_code', "TEXT NOT NULL DEFAULT ''");
  await ensureColumnExists('inventory_stock_positions', 'unit_id', 'INTEGER');
  await ensureColumnExists('inventory_stock_positions', 'reserved_qty', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('inventory_stock_positions', 'damaged_qty', 'REAL NOT NULL DEFAULT 0');
  await backfillInventoryMovementQuantitySemantics();
  await run('CREATE INDEX IF NOT EXISTS idx_inventory_movements_source_challan ON inventory_movements(source_challan_id, source_challan_type)');
  await ensureColumnExists('materials', 'location', "TEXT DEFAULT ''");
  await ensureColumnExists('materials', 'group_mode', 'TEXT');
  await ensureColumnExists(
    'materials',
    'inheritance_enabled',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await ensureColumnExists('materials', 'display_stock', "TEXT DEFAULT ''");
  await ensureColumnExists('materials', 'created_by', "TEXT DEFAULT ''");
  await ensureColumnExists('materials', 'workflow_status', "TEXT DEFAULT 'notStarted'");
  await ensureColumnExists('materials', 'material_class', "TEXT DEFAULT 'raw_material'");
  await ensureColumnExists('materials', 'inventory_state', "TEXT DEFAULT 'available'");
  await ensureColumnExists('materials', 'procurement_state', "TEXT DEFAULT 'not_ordered'");
  await ensureColumnExists('materials', 'traceability_mode', "TEXT DEFAULT 'bulk'");
  await ensureColumnExists('materials', 'on_hand_qty', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('materials', 'reserved_qty', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('materials', 'available_to_promise_qty', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('materials', 'incoming_qty', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('materials', 'linked_order_count', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('materials', 'linked_pipeline_count', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('materials', 'pending_alert_count', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('materials', 'updated_at', 'TEXT');
  await ensureColumnExists('materials', 'last_scanned_at', 'TEXT');
  await ensureColumnExists(
    'material_group_properties',
    'coverage_count',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await ensureColumnExists(
    'material_group_properties',
    'selected_item_count_at_resolution',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await ensureColumnExists(
    'material_group_properties',
    'resolution_source',
    'TEXT',
  );
  await ensureColumnExists(
    'material_group_properties',
    'unit_id',
    'INTEGER',
  );
  await ensureColumnExists(
    'material_group_properties',
    'unit_symbol',
    'TEXT',
  );
  await ensureColumnExists(
    'material_group_properties',
    'unit_label',
    'TEXT',
  );
  await ensureColumnExists(
    'material_group_properties',
    'source_group_id',
    'INTEGER',
  );
  await ensureColumnExists(
    'material_group_properties',
    'source_group_name',
    'TEXT',
  );
  await ensureColumnExists(
    'material_group_preferences',
    'discarded_property_keys_json',
    "TEXT NOT NULL DEFAULT '[]'",
  );
  await ensureColumnExists('users', 'failed_login_attempts', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('users', 'first_failed_login_at', 'TEXT');
  await ensureColumnExists('users', 'lockout_until', 'TEXT');
  await ensureColumnExists('users', 'last_login_at', 'TEXT');
  await ensureColumnExists('users', 'last_login_ip', "TEXT DEFAULT ''");
  await ensureColumnExists('users', 'mobile_pin', "TEXT");
  await ensureColumnExists('users', 'client_id', "INTEGER REFERENCES clients(id)");
  await run('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_mobile_pin ON users(mobile_pin)');
  await ensureColumnExists('auth_sessions', 'ip_address', "TEXT DEFAULT ''");
  await ensureColumnExists('auth_sessions', 'user_agent', "TEXT DEFAULT ''");
  await ensureColumnExists('auth_sessions', 'revoked_reason', "TEXT DEFAULT ''");
  await ensureColumnExists('delete_requests', 'reviewed_note', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'alias', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'gst_number', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'address', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'contact_name', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'phone', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'email', "TEXT DEFAULT ''");
  await ensureColumnExists('vendors', 'is_archived', 'INTEGER NOT NULL DEFAULT 0');
  await run("UPDATE materials SET updated_at = created_at WHERE updated_at IS NULL");
  await seedRolePermissions();
  await seedPermissionTemplates();

  await run(`
    CREATE TABLE IF NOT EXISTS pipeline_templates (
      id TEXT PRIMARY KEY,
      factory_id TEXT DEFAULT '',
      shop_floor_id TEXT DEFAULT '',
      name TEXT NOT NULL,
      description TEXT DEFAULT '',
      version INTEGER NOT NULL DEFAULT 1,
      status TEXT DEFAULT 'draft',
      stage_labels_json TEXT NOT NULL,
      lane_labels_json TEXT NOT NULL,
      nodes_json TEXT NOT NULL,
      flows_json TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    )
  `);

  await ensureColumnExists('pipeline_templates', 'factory_id', "TEXT DEFAULT ''");
  await ensureColumnExists('pipeline_templates', 'shop_floor_id', "TEXT DEFAULT ''");
  await ensureColumnExists('pipeline_templates', 'intermediate_naming_convention', "TEXT DEFAULT ''");

  await run(`
    CREATE TABLE IF NOT EXISTS pipeline_runs (
      id TEXT PRIMARY KEY,
      template_id TEXT NOT NULL REFERENCES pipeline_templates(id),
      template_version INTEGER NOT NULL,
      name TEXT,
      status TEXT DEFAULT 'planned',
      overrides_json TEXT,
      node_status_json TEXT,
      started_at TEXT,
      completed_at TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    )
  `);

  await ensureColumnExists('pipeline_runs', 'scrap_routing', "TEXT DEFAULT 'inventory'");
  await ensureColumnExists('pipeline_runs', 'node_metrics_json', "TEXT DEFAULT '{}'");
  await ensureColumnExists('pipeline_runs', 'batches_json', "TEXT DEFAULT '[]'");

  await run(`
    CREATE TABLE IF NOT EXISTS stage_reconciliations (
      run_id TEXT NOT NULL REFERENCES pipeline_runs(id),
      node_id TEXT NOT NULL,
      allotted REAL,
      output REAL,
      leftover REAL,
      scrap REAL,
      good_yield REAL,
      actual_hours REAL,
      scrap_item_id INTEGER,
      scrap_item_name TEXT,
      leftover_action TEXT,
      input_time TEXT,
      output_time TEXT,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (run_id, node_id)
    )
  `);
  await backfillStageReconciliations();

  await run(`
    CREATE TABLE IF NOT EXISTS production_scrap (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pipeline_run_id TEXT NOT NULL REFERENCES pipeline_runs(id),
      node_id TEXT NOT NULL,
      order_no TEXT,
      material_barcode TEXT NOT NULL,
      scrap_qty REAL NOT NULL DEFAULT 0,
      logged_by TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    )
  `);


  await run(`
    CREATE TABLE IF NOT EXISTS run_barcode_inputs (
      id TEXT PRIMARY KEY,
      run_id TEXT NOT NULL REFERENCES pipeline_runs(id),
      node_id TEXT NOT NULL,
      barcode TEXT NOT NULL,
      material_id TEXT,
      material_payload_json TEXT NOT NULL,
      scanned_at TEXT DEFAULT (datetime('now'))
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS order_pipeline_assignments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_item_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
      pipeline_run_id TEXT NOT NULL REFERENCES pipeline_runs(id) ON DELETE CASCADE,
      allocated_quantity REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_order_pipeline_assignments_order_id ON order_pipeline_assignments(order_item_id)');
  await run('CREATE INDEX IF NOT EXISTS idx_order_pipeline_assignments_pipeline_run_id ON order_pipeline_assignments(pipeline_run_id)');

  await run(`
    CREATE TABLE IF NOT EXISTS procurement_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_number TEXT NOT NULL UNIQUE,
      supplier_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      expected_date TEXT,
      notes TEXT DEFAULT '',
      cancel_reason TEXT,
      created_by_user_id INTEGER REFERENCES users(id),
      created_by_name TEXT DEFAULT '',
      created_by_role TEXT DEFAULT '',
      raised_by_user_id INTEGER REFERENCES users(id),
      raised_by_name TEXT DEFAULT '',
      raised_by_role TEXT DEFAULT '',
      cancelled_by_user_id INTEGER REFERENCES users(id),
      cancelled_by_name TEXT DEFAULT '',
      cancelled_by_role TEXT DEFAULT '',
      closed_by_user_id INTEGER REFERENCES users(id),
      closed_by_name TEXT DEFAULT '',
      closed_by_role TEXT DEFAULT '',
      raised_at TEXT,
      cancelled_at TEXT,
      closed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS procurement_request_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      procurement_request_id INTEGER NOT NULL REFERENCES procurement_requests(id) ON DELETE CASCADE,
      material_barcode TEXT NOT NULL,
      material_name TEXT DEFAULT '',
      requested_qty REAL NOT NULL DEFAULT 0,
      received_qty REAL NOT NULL DEFAULT 0,
      pending_qty REAL NOT NULL DEFAULT 0,
      unit_id INTEGER REFERENCES units(id),
      unit_symbol TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'draft',
      custom_variation_values_json TEXT DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(procurement_request_id, material_barcode)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS procurement_request_line_sources (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      procurement_request_id INTEGER NOT NULL REFERENCES procurement_requests(id) ON DELETE CASCADE,
      procurement_request_line_id INTEGER NOT NULL REFERENCES procurement_request_lines(id) ON DELETE CASCADE,
      order_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
      requirement_id INTEGER NOT NULL REFERENCES order_material_requirements(id) ON DELETE CASCADE,
      material_barcode TEXT NOT NULL,
      linked_qty REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      UNIQUE(procurement_request_line_id, requirement_id)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS procurement_activity_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      procurement_request_id INTEGER NOT NULL REFERENCES procurement_requests(id) ON DELETE CASCADE,
      procurement_request_line_id INTEGER REFERENCES procurement_request_lines(id) ON DELETE CASCADE,
      event_type TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT DEFAULT '',
      actor_user_id INTEGER REFERENCES users(id),
      actor_name TEXT DEFAULT '',
      actor_role TEXT DEFAULT '',
      metadata_json TEXT DEFAULT '{}',
      source TEXT DEFAULT 'api',
      created_at TEXT NOT NULL
    )
  `);

  await run('CREATE INDEX IF NOT EXISTS idx_procurement_requests_status ON procurement_requests(status, updated_at DESC)');
  await run('CREATE INDEX IF NOT EXISTS idx_procurement_request_lines_request_id ON procurement_request_lines(procurement_request_id, id ASC)');
  await run('CREATE INDEX IF NOT EXISTS idx_procurement_line_sources_requirement_id ON procurement_request_line_sources(requirement_id, id ASC)');
  await run('CREATE INDEX IF NOT EXISTS idx_procurement_line_sources_request_id ON procurement_request_line_sources(procurement_request_id, id ASC)');
  await run('CREATE INDEX IF NOT EXISTS idx_procurement_activity_request_id ON procurement_activity_log(procurement_request_id, created_at DESC)');

  if (SEED_DEMO_DATA_ON_BOOT) {
    await seedMaterialsIfEmpty();
    await seedUnitsIfEmpty();
  }
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
    CREATE TABLE IF NOT EXISTS machines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      asset_id TEXT NOT NULL UNIQUE,
      primary_photo_url TEXT,
      group_id INTEGER REFERENCES groups(id),
      make_model TEXT,
      serial_number TEXT,
      location TEXT,
      installation_date TEXT,
      status TEXT NOT NULL,
      report_output_per_hour REAL,
      setup_minutes REAL,
      labor_count REAL,
      power_kw REAL,
      report_notes TEXT NOT NULL DEFAULT '',
      custom_properties TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    UPDATE groups 
    SET group_type = 'machine' 
    WHERE id IN (SELECT DISTINCT group_id FROM machines WHERE group_id IS NOT NULL)
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS dies (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tool_code TEXT NOT NULL UNIQUE,
      produced_part_numbers TEXT NOT NULL DEFAULT '[]',
      photo_urls TEXT NOT NULL DEFAULT '[]',
      operational_notes TEXT,
      compatible_machine_group_ids TEXT NOT NULL DEFAULT '[]',
      storage_location TEXT,
      number_of_cavities INTEGER,
      stroke_count INTEGER NOT NULL DEFAULT 0,
      max_strokes INTEGER NOT NULL DEFAULT 0,
      strokes_per_piece REAL,
      setup_minutes REAL,
      report_notes TEXT NOT NULL DEFAULT '',
      physical_specs TEXT NOT NULL DEFAULT '{}',
      status TEXT NOT NULL,
      ownership TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await ensureColumnExists('machines', 'report_output_per_hour', 'REAL');
  await ensureColumnExists('machines', 'setup_minutes', 'REAL');
  await ensureColumnExists('machines', 'labor_count', 'REAL');
  await ensureColumnExists('machines', 'power_kw', 'REAL');
  await ensureColumnExists('machines', 'report_notes', "TEXT NOT NULL DEFAULT ''");
  await ensureColumnExists('dies', 'strokes_per_piece', 'REAL');
  await ensureColumnExists('dies', 'setup_minutes', 'REAL');
  await ensureColumnExists('dies', 'report_notes', "TEXT NOT NULL DEFAULT ''");

  if (SEED_DEMO_DATA_ON_BOOT) {
    await seedMachinesAndDiesIfEmpty();
  }

  // Create Sandbox Control Plane Tables
  await run(`
    CREATE TABLE IF NOT EXISTS sandbox_client_configs (
      client_id TEXT PRIMARY KEY,
      config_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS sandbox_sync_states (
      client_id TEXT PRIMARY KEY,
      db_state TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS sandbox_replays (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id TEXT NOT NULL,
      session_id TEXT NOT NULL,
      events_json TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS sandbox_client_pins (
      client_id TEXT PRIMARY KEY,
      activation_pin TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS sandbox_activated_machines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id TEXT NOT NULL,
      machine_fingerprint TEXT NOT NULL,
      token TEXT NOT NULL,
      activated_at TEXT NOT NULL,
      UNIQUE(client_id, machine_fingerprint)
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS sandbox_client_users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id TEXT NOT NULL,
      user_email TEXT NOT NULL,
      role TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(client_id, user_email)
    )
  `);

  // Insert default client config if not exists
  const defaultConf = await get('SELECT client_id FROM sandbox_client_configs WHERE client_id = ?', ['default']);
  if (!defaultConf) {
    const initialConfig = {
      "modules": {
        "orders": true,
        "masters": true,
        "inventory": true,
        "production": true,
        "pm": true,
        "jobs": true,
        "delivery_challans": true
      },
      "orders": {
        "statusColors": {
          "pending": "#FFA500",
          "in_progress": "#1E90FF",
          "completed": "#32CD32"
        },
        "allowCustomActions": true
      },
      "update": {
        "channel": "stable",
        "latest_version": "1.0.0"
      }
    };
    await run(
      'INSERT INTO sandbox_client_configs (client_id, config_json, updated_at) VALUES (?, ?, datetime(\'now\'))',
      ['default', JSON.stringify(initialConfig)]
    );
  }

  await run(`
    CREATE TABLE IF NOT EXISTS piece_barcodes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      challan_item_id INTEGER NOT NULL REFERENCES delivery_challan_items(id) ON DELETE CASCADE,
      parent_code TEXT UNIQUE NOT NULL,
      child_code TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  `);
  await run('CREATE INDEX IF NOT EXISTS idx_piece_barcodes_parent_code ON piece_barcodes(parent_code)');
  await run('CREATE INDEX IF NOT EXISTS idx_piece_barcodes_child_code ON piece_barcodes(child_code)');
  await run('CREATE INDEX IF NOT EXISTS idx_piece_barcodes_challan_item_id ON piece_barcodes(challan_item_id)');

  await bootstrapSuperAdminIfNeeded();
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
  let rawMaterials = await get('SELECT id FROM groups WHERE name = "Raw Materials" AND parent_group_id IS NULL');
  if (!rawMaterials) {
    await run("INSERT INTO groups (name, parent_group_id, unit_id, created_at, updated_at) VALUES ('Raw Materials', NULL, ?, datetime('now'), datetime('now'))", [unit.id]);
  }
  let scrapGroup = await get('SELECT id FROM groups WHERE name = "Scrap" AND parent_group_id IS NULL');
  if (!scrapGroup) {
    await run("INSERT INTO groups (name, parent_group_id, unit_id, created_at, updated_at) VALUES ('Scrap', NULL, ?, datetime('now'), datetime('now'))", [unit.id]);
  }
}

async function ensureDemoDataset(scenarioId = 'default') {
  await ensureDemoUnitsPresent(scenarioId);
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
    await recomputeMaterialInventorySummary(material.barcode);
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
    await recomputeMaterialInventorySummary(material.barcode);
  }
}

async function cleanupStaleUnlinkedPoDocuments({
  olderThanHours = 24,
  now = new Date(),
} = {}) {
  const cutoff = new Date(now.getTime() - olderThanHours * 60 * 60 * 1000).toISOString();
  await run(
    `
    DELETE FROM po_upload_sessions
    WHERE status != 'completed'
      AND COALESCE(completed_at, expires_at, created_at) <= ?
    `,
    [cutoff],
  );
  await run(
    `
    DELETE FROM po_documents
    WHERE status = 'uploaded'
      AND COALESCE(uploaded_at, created_at) <= ?
      AND id NOT IN (SELECT document_id FROM order_po_documents)
    `,
    [cutoff],
  );
}

async function ensureColumnExists(tableName, columnName, definition) {
  const columns = await all(`PRAGMA table_info(${tableName})`);
  const hasColumn = columns.some((column) => column.name === columnName);
  if (!hasColumn) {
    console.log(`Migrating ${tableName}: adding ${columnName}`);
    await run(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${definition}`);
  }
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

function orderActivityTitle(activityType) {
  return String(activityType || '')
    .split('_')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ') || 'Order Activity';
}

// Cache order_activity_log column set once at startup to avoid repeated PRAGMA
// calls on every order save/lifecycle update (H-5 fix).
let _orderActivityLogColumns = null;
async function getOrderActivityLogColumns() {
  if (!_orderActivityLogColumns) {
    const columns = await all('PRAGMA table_info(order_activity_log)');
    _orderActivityLogColumns = new Set(columns.map((col) => col.name));
  }
  return _orderActivityLogColumns;
}

async function insertOrderActivityLog({
  orderId,
  activityType,
  actor = null,
  source = 'api',
  details = {},
  createdAt = new Date().toISOString(),
}) {
  const available = await getOrderActivityLogColumns();
  const detailsJson = JSON.stringify(details || {});
  const valuesByColumn = {
    order_id: orderId,
    activity_type: activityType,
    event_type: activityType,
    title: orderActivityTitle(activityType),
    description: '',
    actor_user_id: actor?.id || null,
    actor_name: actor?.name || 'System',
    actor_role: actor?.role || 'system',
    source: actor?.source || source || 'api',
    details_json: detailsJson,
    metadata_json: detailsJson,
    created_at: createdAt,
  };
  const insertColumns = Object.keys(valuesByColumn).filter((column) =>
    available.has(column),
  );
  const placeholders = insertColumns.map(() => '?').join(', ');
  await run(
    `
    INSERT INTO order_activity_log (${insertColumns.join(', ')})
    VALUES (${placeholders})
    `,
    insertColumns.map((column) => valuesByColumn[column]),
  );
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
  const countRow = await get('SELECT COUNT(*) AS count FROM units');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const now = new Date().toISOString();
  const units = [
    { name: 'Kilogram', symbol: 'Kg', notes: 'Mock seed' },
    { name: 'Sheet', symbol: 'Sheet', notes: 'Mock seed' },
    { name: 'Piece', symbol: 'Pieces', notes: 'Mock seed' },
    { name: 'Box', symbol: 'Box', notes: 'Mock seed' },
  ];

  for (const unit of units) {
    await run(
      `
      INSERT INTO units (name, symbol, unit_group_id, conversion_factor, conversion_base_unit_id, notes, is_archived, created_at, updated_at)
      VALUES (?, ?, NULL, 1, NULL, ?, 0, ?, ?)
      `,
      [unit.name, unit.symbol, unit.notes, now, now],
    );
  }
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
    {
      name: 'Piece',
      symbol: 'Pc',
      notes: 'Discrete finished goods and components.',
    },
    {
      name: 'Box',
      symbol: 'Box',
      notes: 'Packed kits and shipping cartons.',
    },
    {
      name: 'Carton',
      symbol: 'Ctn',
      notes: 'Shipping cartons.',
    }
  ];

  for (const unit of units) {
    await ensureUnitRecord(unit);
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

async function createParentWithChildren(payload) {
  const resolvedUnit = await resolveUnitPayload(payload);
  const actor = String(payload?.actor || '').trim() || 'Demo Admin';
  const normalizedGroupMode = String(payload.groupMode || '').trim() || null;
  const shouldCreateMasterGroup = (
    String(payload.type || '').trim() === 'Group' ||
    normalizedGroupMode === 'item_group_authoring' ||
    normalizedGroupMode === 'standalone_group' ||
    normalizedGroupMode === 'nested_group'
  );
  const parentBarcode = generateParentBarcode();
  const childBarcodes = Array.from(
    { length: Number(payload.numberOfChildren || 0) },
    (_, index) => generateChildBarcode(parentBarcode, index + 1),
  );
  const createdAt = new Date().toISOString();

  await run('BEGIN TRANSACTION');
  try {
    let linkedGroupId = null;
    if (shouldCreateMasterGroup && resolvedUnit.unitId) {
      const group = await saveGroup({
        name: payload.name,
        parentGroupId: payload.parentGroupId ?? null,
        unitId: resolvedUnit.unitId,
      });
      linkedGroupId = group.id;
    }
    const parentResult = await run(
      `
      INSERT INTO materials (
        barcode, name, type, grade, thickness, supplier, location, unit_id, unit, notes, group_mode, inheritance_enabled,
        created_at, kind, parent_barcode, number_of_children,
        linked_child_barcodes, scan_count, linked_group_id, linked_item_id,
        display_stock, created_by, workflow_status, updated_at, last_scanned_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'parent', NULL, ?, ?, 0, ?, NULL, ?, ?, ?, ?, NULL)
      `,
      [
        parentBarcode,
        payload.name,
        payload.type,
        payload.grade || '',
        payload.thickness || '',
        payload.supplier || '',
        String(payload.location || '').trim(),
        resolvedUnit.unitId,
        resolvedUnit.unit,
        payload.notes || '',
        normalizedGroupMode,
        payload.inheritanceEnabled ? 1 : 0,
        createdAt,
        Number(payload.numberOfChildren || 0),
        JSON.stringify(childBarcodes),
        linkedGroupId,
        resolvedUnit.unit ? `0 ${resolvedUnit.unit}` : '0',
        actor,
        'inProgress',
        createdAt,
      ],
    );

    for (let index = 0; index < childBarcodes.length; index += 1) {
      await run(
        `
        INSERT INTO materials (
          barcode, name, type, grade, thickness, supplier, location, unit_id, unit, notes, group_mode, inheritance_enabled,
          created_at, kind, parent_barcode, number_of_children,
          linked_child_barcodes, scan_count, linked_group_id, linked_item_id,
          display_stock, created_by, workflow_status, updated_at, last_scanned_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'child', ?, 0, ?, 0, NULL, NULL, ?, ?, ?, ?, NULL)
        `,
        [
          childBarcodes[index],
          `${payload.name} - Child ${index + 1}`,
          payload.type,
          payload.grade || '',
          payload.thickness || '',
          payload.supplier || '',
          String(payload.location || '').trim(),
          resolvedUnit.unitId,
          resolvedUnit.unit,
          payload.notes || '',
          normalizedGroupMode,
          payload.inheritanceEnabled ? 1 : 0,
          createdAt,
          parentBarcode,
          JSON.stringify([]),
          resolvedUnit.unit ? `0 ${resolvedUnit.unit}` : '0',
          actor,
          'notStarted',
          createdAt,
        ],
      );
      await logMaterialActivity({
        barcode: childBarcodes[index],
        type: 'created',
        label: 'Item created',
        description: `Inventory item ${payload.name} - Child ${index + 1} was created.`,
        actor,
        createdAt,
      });
    }

    await logMaterialActivity({
      barcode: parentBarcode,
      type: 'created',
      label: 'Group created',
      description: `Inventory group ${payload.name} was created.`,
      actor,
      createdAt,
    });

    await persistMaterialGroupGovernance(parentResult.lastID, payload, createdAt);
    await recomputeMaterialInventorySummary(parentBarcode, createdAt);
    for (const childBarcode of childBarcodes) {
      await recomputeMaterialInventorySummary(childBarcode, createdAt);
    }

    await run('COMMIT');
    const parentRow = await get('SELECT * FROM materials WHERE id = ?', [
      parentResult.lastID,
    ]);
    return rowToMaterialDto(parentRow);
  } catch (error) {
    await run('ROLLBACK');
    throw error;
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

async function getUnitRowById(id) {
  return get(
    `
    SELECT
      units.*,
      unit_groups.name AS unit_group_name,
      base_unit.name AS conversion_base_unit_name,
      (
        (SELECT COUNT(*) FROM materials WHERE materials.unit_id = units.id) +
        (SELECT COUNT(*) FROM groups WHERE groups.unit_id = units.id) +
        (SELECT COUNT(*) FROM items WHERE items.unit_id = units.id) +
        (SELECT COUNT(*) FROM item_unit_conversions WHERE item_unit_conversions.unit_id = units.id) +
        (SELECT COUNT(*) FROM order_items WHERE order_items.unit_id = units.id) +
        (SELECT COUNT(*) FROM units AS dependent_units WHERE dependent_units.conversion_base_unit_id = units.id) +
        (SELECT COUNT(*) FROM order_material_requirements WHERE order_material_requirements.unit_id = units.id)
      ) AS usage_count
    FROM units
    LEFT JOIN unit_groups ON unit_groups.id = units.unit_group_id
    LEFT JOIN units AS base_unit ON base_unit.id = units.conversion_base_unit_id
    WHERE units.id = ?
    `,
    [id],
  );
}

async function getGroupRowById(id) {
  return get(
    `
    SELECT
      groups.*,
      (
        (SELECT COUNT(*) FROM groups AS child_groups WHERE child_groups.parent_group_id = groups.id) +
        (SELECT COUNT(*) FROM items WHERE items.group_id = groups.id AND items.is_archived = 0) +
        (SELECT COUNT(*) FROM materials WHERE materials.linked_group_id = groups.id)
      ) AS usage_count
    FROM groups
    WHERE groups.id = ?
    `,
    [id],
  );
}

async function getClientRowById(id) {
  return get(
    `
    SELECT
      clients.*,
      (SELECT COUNT(*) FROM order_items WHERE order_items.client_id = clients.id) AS usage_count
    FROM clients
    WHERE clients.id = ?
    `,
    [id],
  );
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

async function getItemVariationNodeRows(itemId) {
  return all(
    `
    SELECT *
    FROM item_variation_nodes
    WHERE item_id = ? AND is_archived = 0
    ORDER BY parent_node_id ASC, position ASC, LOWER(name) ASC
    `,
    [itemId],
  );
}

async function getItemVariationTree(itemId) {
  const rows = await getItemVariationNodeRows(itemId);
  const rowMap = new Map();
  for (const row of rows) {
    rowMap.set(row.id, {
      id: row.id,
      itemId: row.item_id,
      parentNodeId: row.parent_node_id,
      kind: row.kind || 'property',
      name: row.name || '',
      code: row.code || '',
      displayName: row.display_name || '',
      position: row.position || 0,
      isArchived: Boolean(row.is_archived),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      children: [],
    });
  }

  const roots = [];
  for (const row of rows) {
    const node = rowMap.get(row.id);
    if (row.parent_node_id == null) {
      roots.push(node);
    } else {
      const parent = rowMap.get(row.parent_node_id);
      if (parent) {
        parent.children.push(node);
      }
    }
  }

  const sortNodes = (nodes) => {
    nodes.sort((a, b) => {
      if (a.position !== b.position) {
        return a.position - b.position;
      }
      return String(a.name || '').localeCompare(String(b.name || ''), undefined, {
        sensitivity: 'base',
      });
    });
    for (const node of nodes) {
      sortNodes(node.children);
    }
  };

  sortNodes(roots);
  return roots;
}

function activeChildrenForNode(node) {
  return (node.children || []).filter((child) => !child.isArchived);
}

function activeTopLevelVariationProperties(tree = []) {
  return (tree || []).filter(
    (node) => !node.isArchived && String(node.kind) === 'property',
  );
}

function findVariationNodeById(nodes = [], nodeId) {
  for (const node of nodes || []) {
    if (Number(node.id) === Number(nodeId)) {
      return node;
    }
    const found = findVariationNodeById(node.children || [], nodeId);
    if (found) {
      return found;
    }
  }
  return null;
}

function activeValuePathForLeaf(tree = [], leafNodeId) {
  const selection = activeValueSelectionForLeaf(tree, leafNodeId);
  return selection ? selection.nodeIds : null;
}

function activeValueSelectionForLeaf(tree = [], leafNodeId) {
  const walkProperty = (propertyNode, path) => {
    for (const valueNode of activeChildrenForNode(propertyNode).filter(
      (node) => String(node.kind) === 'value',
    )) {
      const nextPath = {
        nodeIds: [...path.nodeIds, Number(valueNode.id)],
        segments: [...path.segments, String(valueNode.name || '').trim()],
      };
      if (Number(valueNode.id) === Number(leafNodeId)) {
        const activeChildProperty = activeChildrenForNode(valueNode).find(
          (node) => String(node.kind) === 'property',
        );
        return activeChildProperty ? null : nextPath;
      }
      for (const childProperty of activeChildrenForNode(valueNode).filter(
        (node) => String(node.kind) === 'property',
      )) {
        const found = walkProperty(childProperty, nextPath);
        if (found) {
          return found;
        }
      }
    }
    return null;
  };

  for (const propertyNode of activeTopLevelVariationProperties(tree)) {
    const found = walkProperty(propertyNode, {
      nodeIds: [],
      segments: [],
    });
    if (found) {
      return found;
    }
  }
  return null;
}

function variationPathLabelForNodeIds(tree = [], pathNodeIds = []) {
  const segments = [];
  for (const nodeId of pathNodeIds) {
    const node = findVariationNodeById(tree, nodeId);
    if (!node || node.isArchived || String(node.kind) !== 'value') {
      continue;
    }
    const segment = String(node.name || '').trim();
    if (segment) {
      segments.push(segment);
    }
  }
  return buildVariationPathLabel(segments);
}

async function resolveLeafSelectionFromDb(leafNodeId) {
  const nodeIds = [];
  const segments = [];
  let currentId = leafNodeId;
  while (currentId) {
    const node = await get('SELECT id, parent_node_id, name, kind FROM item_variation_nodes WHERE id = ?', [currentId]);
    if (!node) {
      break;
    }
    if (node.kind === 'value') {
      nodeIds.unshift(node.id);
      segments.unshift(node.name);
    }
    currentId = node.parent_node_id;
  }
  if (nodeIds.length === 0 || nodeIds[nodeIds.length - 1] !== leafNodeId) {
    return null;
  }
  return {
    nodeIds,
    segments,
  };
}

async function assertValidStockVariationLeaf(itemId, variationLeafNodeId) {
  const normalizedItemId = Number(itemId || 0);
  const normalizedLeafNodeId = Number(variationLeafNodeId || 0);
  if (!normalizedItemId || !normalizedLeafNodeId) {
    const error = new Error('Stock-managed inventory lines must reference an item variation leaf.');
    error.statusCode = 400;
    throw error;
  }

  const row = await get(
    `
    SELECT leaf.id
    FROM item_variation_nodes leaf
    LEFT JOIN item_variation_nodes child
      ON child.parent_node_id = leaf.id
      AND child.is_archived = 0
    WHERE leaf.id = ?
      AND leaf.item_id = ?
      AND leaf.kind = 'value'
      AND leaf.is_archived = 0
    GROUP BY leaf.id
    HAVING COUNT(child.id) = 0
    `,
    [normalizedLeafNodeId, normalizedItemId],
  );
  if (!row) {
    const error = new Error('Stock-managed inventory lines must reference a valid item variation leaf.');
    error.statusCode = 400;
    throw error;
  }
}

async function applyVariationStockDelta({
  itemId,
  variationLeafNodeId,
  locationId = 'MAIN',
  variationPathLabel = '',
  variationPathNodeIds = [],
  customVariationValues = {},
  delta,
  now = new Date().toISOString(),
}) {
  const normalizedItemId = Number(itemId || 0);
  const normalizedLeafNodeId = Number(variationLeafNodeId || 0);
  const normalizedLocationId = String(locationId || '').trim() || 'MAIN';
  const normalizedDelta = Number(delta || 0);
  const normalizedVariationPathLabel = String(variationPathLabel || '').trim();
  const normalizedVariationPathNodeIds = Array.isArray(variationPathNodeIds)
    ? variationPathNodeIds.map((id) => Number(id)).filter((id) => Number.isFinite(id) && id > 0)
    : [];
  const normalizedCustomVariationValues = normalizeCustomVariationValues(customVariationValues || {});
  if (!Number.isFinite(normalizedDelta) || normalizedDelta === 0) {
    return;
  }

  await assertValidStockVariationLeaf(normalizedItemId, normalizedLeafNodeId);

  if (normalizedDelta < 0) {
    const currentStock = await get(
      `
      SELECT quantity
      FROM variation_stock
      WHERE item_id = ? AND variation_leaf_node_id = ? AND location_id = ?
      `,
      [normalizedItemId, normalizedLeafNodeId, normalizedLocationId],
    );
    const onHand = Number(currentStock?.quantity || 0);
    const nextQuantity = onHand + normalizedDelta;
    if (nextQuantity < -0.000001) {
      const error = new Error(
        `Insufficient stock for item id ${normalizedItemId}. On hand: ${onHand}, Required: ${Math.abs(normalizedDelta)}. Stock cannot go negative.`,
      );
      error.statusCode = 400;
      throw error;
    }
  }

  const insertedQuantity = normalizedDelta > 0 ? normalizedDelta : 0;
  await run(
    `
    INSERT INTO variation_stock (
      item_id, variation_leaf_node_id, quantity, location_id,
      variation_path_label, variation_path_node_ids_json, custom_variation_values_json, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(item_id, variation_leaf_node_id, location_id)
    DO UPDATE SET
      quantity = variation_stock.quantity + ?,
      variation_path_label = CASE
        WHEN TRIM(excluded.variation_path_label) <> '' THEN excluded.variation_path_label
        ELSE variation_stock.variation_path_label
      END,
      variation_path_node_ids_json = CASE
        WHEN excluded.variation_path_node_ids_json <> '[]' THEN excluded.variation_path_node_ids_json
        ELSE variation_stock.variation_path_node_ids_json
      END,
      custom_variation_values_json = CASE
        WHEN excluded.custom_variation_values_json <> '{}' THEN excluded.custom_variation_values_json
        ELSE variation_stock.custom_variation_values_json
      END,
      updated_at = excluded.updated_at
    `,
    [
      normalizedItemId,
      normalizedLeafNodeId,
      insertedQuantity,
      normalizedLocationId,
      normalizedVariationPathLabel,
      JSON.stringify(normalizedVariationPathNodeIds),
      JSON.stringify(normalizedCustomVariationValues),
      now,
      normalizedDelta,
    ],
  );
}

async function resolveOrderVariationSelection({
  itemId,
  variationLeafNodeId = 0,
  variationPathNodeIds = [],
  variationPathLabel = '',
  status = 'notStarted',
}) {
  const item = await getItemRowById(itemId);
  if (!item || item.is_archived) {
    const error = new Error('Selected item is not available.');
    error.statusCode = 400;
    throw error;
  }

  const tree = await getItemVariationTree(item.id);
  const hasActiveVariationProperties = activeTopLevelVariationProperties(tree).length > 0;
  const normalizedPathNodeIds = Array.isArray(variationPathNodeIds)
    ? variationPathNodeIds.map((id) => Number(id)).filter((id) => Number.isFinite(id) && id > 0)
    : [];
  let normalizedLeafId = Number(variationLeafNodeId || 0);

  if (!hasActiveVariationProperties) {
    return {
      item,
      variationLeafNodeId: 0,
      variationPathNodeIds: [],
      variationPathNodeIdsJson: '[]',
      variationPathLabel: '',
    };
  }

  if ((!Number.isFinite(normalizedLeafId) || normalizedLeafId <= 0) && normalizedPathNodeIds.length > 0) {
    normalizedLeafId = normalizedPathNodeIds[normalizedPathNodeIds.length - 1];
  }

  const isDraft = status === 'draft';
  if (!Number.isFinite(normalizedLeafId) || normalizedLeafId <= 0) {
    if (isDraft) {
      const draftPath = [...normalizedPathNodeIds];
      return {
        item,
        variationLeafNodeId: 0,
        variationPathNodeIds: draftPath,
        variationPathNodeIdsJson: JSON.stringify(draftPath),
        variationPathLabel: variationPathLabelForNodeIds(tree, draftPath),
      };
    }
    const error = new Error('Client, item, and variation values are required.');
    error.statusCode = 400;
    throw error;
  }

  let leafNode = findVariationNodeById(tree, normalizedLeafId);
  let leafSelection = activeValueSelectionForLeaf(tree, normalizedLeafId);

  if (!leafNode || leafNode.isArchived || !leafSelection) {
    const dbNode = await get('SELECT * FROM item_variation_nodes WHERE id = ? AND item_id = ?', [normalizedLeafId, item.id]);
    if (dbNode && dbNode.kind === 'value') {
      const selectionFromDb = await resolveLeafSelectionFromDb(normalizedLeafId);
      if (selectionFromDb) {
        leafNode = {
          id: dbNode.id,
          itemId: dbNode.item_id,
          parentNodeId: dbNode.parent_node_id,
          kind: dbNode.kind,
          name: dbNode.name,
          code: dbNode.code,
          displayName: dbNode.display_name,
          position: dbNode.position,
          isArchived: Boolean(dbNode.is_archived),
        };
        leafSelection = selectionFromDb;
      }
    }
  }

  if (
    !leafNode ||
    String(leafNode.kind) !== 'value' ||
    !leafSelection
  ) {
    const error = new Error('Selected variation leaf is not available for this item.');
    error.statusCode = 400;
    throw error;
  }
  return {
    item,
    variationLeafNodeId: normalizedLeafId,
    variationPathNodeIds: normalizedPathNodeIds.length > 0 ? normalizedPathNodeIds : leafSelection.nodeIds,
    variationPathNodeIdsJson: JSON.stringify(normalizedPathNodeIds.length > 0 ? normalizedPathNodeIds : leafSelection.nodeIds),
    variationPathLabel: variationPathLabel ? String(variationPathLabel).trim() : buildVariationPathLabel(leafSelection.segments),
  };
}

async function resolveOrderUnitSelection({ item, unitId = null }) {
  const itemUnitId = Number(item?.unit_id || 0);
  const requestedUnitId = Number(unitId || 0);
  const normalizedUnitId = requestedUnitId > 0 ? requestedUnitId : itemUnitId;
  if (!normalizedUnitId) {
    return {
      unitId: null,
      unitName: 'Pieces',
      unitSymbol: 'Pieces',
    };
  }

  const unit = await get('SELECT * FROM units WHERE id = ?', [
    normalizedUnitId,
  ]);
  if (!unit || unit.is_archived) {
    const error = new Error(
      'That unit is no longer active. Pick another unit or restore it in Masters → Units.',
    );
    error.statusCode = 400;
    throw error;
  }

  if (requestedUnitId > 0 && requestedUnitId !== itemUnitId) {
    const conversion = await get(
      `
      SELECT 1 AS ok
      FROM item_unit_conversions
      WHERE item_id = ? AND unit_id = ?
      LIMIT 1
      `,
      [item.id, requestedUnitId],
    );
    if (!conversion) {
      const error = new Error(
        'This item does not use that unit yet. Add the conversion in the order line, then save again.',
      );
      error.statusCode = 400;
      throw error;
    }
  }

  return {
    unitId: unit.id,
    unitName: unit.name || '',
    unitSymbol: unit.symbol || unit.name || '',
  };
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

async function getItemRowById(id) {
  return get(
    `
    SELECT
      items.*,
      pipeline_templates.name AS default_pipeline_name,
      (
        (SELECT COUNT(*) FROM order_items WHERE order_items.item_id = items.id) +
        (SELECT COUNT(*) FROM delivery_challan_items WHERE delivery_challan_items.item_id = items.id) +
        (SELECT COUNT(*) FROM order_material_requirements WHERE order_material_requirements.item_id = items.id) +
        (SELECT COUNT(*) FROM materials WHERE materials.linked_item_id = items.id) +
        (SELECT COUNT(*) FROM material_group_item_links WHERE material_group_item_links.item_id = items.id)
      ) AS usage_count
    FROM items
    LEFT JOIN pipeline_templates ON items.default_pipeline_id = pipeline_templates.id
    WHERE items.id = ?
    `,
    [id],
  );
}

async function getItemsWithUsage() {
  return all(`
    SELECT
      items.*,
      pipeline_templates.name AS default_pipeline_name,
      (
        (SELECT COUNT(*) FROM order_items WHERE order_items.item_id = items.id) +
        (SELECT COUNT(*) FROM delivery_challan_items WHERE delivery_challan_items.item_id = items.id) +
        (SELECT COUNT(*) FROM order_material_requirements WHERE order_material_requirements.item_id = items.id) +
        (SELECT COUNT(*) FROM materials WHERE materials.linked_item_id = items.id) +
        (SELECT COUNT(*) FROM material_group_item_links WHERE material_group_item_links.item_id = items.id)
      ) AS usage_count
    FROM items
    LEFT JOIN pipeline_templates ON items.default_pipeline_id = pipeline_templates.id
    ORDER BY items.is_archived ASC, LOWER(items.name) ASC
  `);
}

async function getItemUsageDetails(itemId) {
  const [
    orders,
    challans,
    bomRequirements,
    materials,
    groupLinks
  ] = await Promise.all([
    all(`SELECT id, order_no, client_name, status, created_at FROM order_items WHERE item_id = ? ORDER BY created_at DESC LIMIT 50`, [itemId]),
    all(`SELECT dci.id, dci.challan_id, dc.challan_no, dc.customer_name, dc.date, dc.status 
         FROM delivery_challan_items dci 
         JOIN delivery_challans dc ON dci.challan_id = dc.id 
         WHERE dci.item_id = ? ORDER BY dc.date DESC LIMIT 50`, [itemId]),
    all(`SELECT omr.id, omr.order_id, oi.order_no, oi.client_name 
         FROM order_material_requirements omr
         JOIN order_items oi ON omr.order_id = oi.id
         WHERE omr.item_id = ? ORDER BY omr.created_at DESC LIMIT 50`, [itemId]),
    all(`SELECT id, barcode, name, inventory_state FROM materials WHERE linked_item_id = ? ORDER BY created_at DESC LIMIT 50`, [itemId]),
    all(`SELECT mgil.id, m.barcode, m.name 
         FROM material_group_item_links mgil
         JOIN materials m ON mgil.material_id = m.id
         WHERE mgil.item_id = ? LIMIT 50`, [itemId])
  ]);

  const usage = [];
  
  orders.forEach(o => {
    usage.push({ type: 'order', id: String(o.id), title: `Order ${o.order_no}`, subtitle: o.client_name || '-', status: o.status, date: o.created_at });
  });

  challans.forEach(c => {
    usage.push({ type: 'delivery_challan', id: String(c.challan_id), title: `Challan ${c.challan_no}`, subtitle: c.customer_name || '-', status: c.status, date: c.date });
  });

  bomRequirements.forEach(b => {
    usage.push({ type: 'bom_requirement', id: String(b.id), title: `BOM for Order ${b.order_no}`, subtitle: b.client_name || '-', status: null, date: null });
  });

  materials.forEach(m => {
    usage.push({ type: 'material', id: String(m.id), title: `Material ${m.barcode}`, subtitle: m.name, status: m.inventory_state, date: null });
  });

  groupLinks.forEach(g => {
    usage.push({ type: 'group_link', id: String(g.id), title: `Group Link for ${g.barcode}`, subtitle: g.name, status: null, date: null });
  });

  return usage;
}

function sanitizeNodes(nodes, expectedKind, pathSegments = [], parentPropertyName = '', depth = 0) {
  if (depth > 10) {
    const error = new Error('Variation tree is too deep.');
    error.statusCode = 400;
    throw error;
  }
  const siblingNames = new Set();
  return (nodes || []).map((node, index) => {
    const trimmedName = String(node.name || '').trim();
    if (!trimmedName) {
      const error = new Error('Variation tree node names are required.');
      error.statusCode = 400;
      throw error;
    }
    const kind = String(node.kind || '');
    if (kind !== expectedKind) {
      const error = new Error(`Expected variation tree node of kind '${expectedKind}', but got '${kind}'.`);
      error.statusCode = 409;
      throw error;
    }
    const normalizedName = normalizeUnitValue(trimmedName);
    if (siblingNames.has(normalizedName)) {
      const error = new Error('Sibling variation nodes must have unique names.');
      error.statusCode = 409;
      throw error;
    }
    siblingNames.add(normalizedName);

    const nodeId = node.id || null;

    if (kind === 'property') {
      const hasPropertyChildren = (node.children || []).some(c => c.kind === 'property');
      const expectedChildKind = hasPropertyChildren ? 'property' : 'value';
      return {
        id: nodeId,
        kind,
        name: trimmedName,
        code: String(node.code || '').trim(),
        displayName: '',
        inputType: String(node.inputType || 'Text').trim() || 'Text',
        position: index,
        children: sanitizeNodes(node.children || [], expectedChildKind, pathSegments, trimmedName, depth + 1),
      };
    }

    const nextSegments = [...pathSegments, trimmedName];
    const children = sanitizeNodes(node.children || [], 'property', nextSegments, '', depth + 1);
    return {
      id: nodeId,
      kind,
      name: trimmedName,
      code: String(node.code || '').trim(),
      displayName:
        String(node.displayName || '').trim() || buildVariationPathLabel(nextSegments),
      position: index,
      children,
    };
  });
}

async function findItemDuplicate({ name, groupId, unitId, excludeId = null }) {
  const rows = await all('SELECT id, name, group_id, unit_id FROM items');
  const normalizedName = normalizeUnitValue(name);
  const normalizedGroupId = Number(groupId || 0);
  const normalizedUnitId = Number(unitId || 0);

  for (const row of rows) {
    if (excludeId != null && row.id === excludeId) {
      continue;
    }
    if (normalizeUnitValue(row.name) === normalizedName && Number(row.group_id || 0) === normalizedGroupId && Number(row.unit_id || 0) === normalizedUnitId) {
      return row;
    }
  }
  return null;
}

async function getGroupsWithUsage() {
  return all(`
    SELECT
      groups.*,
      (
        (SELECT COUNT(*) FROM groups AS child_groups WHERE child_groups.parent_group_id = groups.id) +
        (SELECT COUNT(*) FROM items WHERE items.group_id = groups.id AND items.is_archived = 0) +
        (SELECT COUNT(*) FROM materials WHERE materials.linked_group_id = groups.id)
      ) AS usage_count
    FROM groups
    ORDER BY groups.is_archived ASC, LOWER(groups.name) ASC
  `);
}

async function getClientsWithUsage() {
  return all(`
    SELECT
      clients.*,
      (SELECT COUNT(*) FROM order_items WHERE order_items.client_id = clients.id) AS usage_count
    FROM clients
    ORDER BY clients.is_archived ASC, LOWER(clients.name) ASC
  `);
}

function normalizePartyValue(value = '') {
  return String(value).trim().replace(/\s+/g, ' ').toLowerCase();
}

function normalizeGstNumber(value = '') {
  return String(value).trim().replace(/\s+/g, '').toUpperCase();
}

async function findClientDuplicate({ name, gstNumber = '', excludeId = null }) {
  const rows = await all('SELECT id, name, gst_number FROM clients');
  const normalizedName = normalizePartyValue(name);
  const normalizedGst = normalizeGstNumber(gstNumber);
  return rows.find((row) => {
    if (excludeId != null && row.id === excludeId) {
      return false;
    }
    if (normalizePartyValue(row.name) === normalizedName) {
      return true;
    }
    return normalizedGst && normalizeGstNumber(row.gst_number) === normalizedGst;
  }) || null;
}

async function saveClient({ name, alias = '', gstNumber = '', address = '', logoUrl = '', photoUrl = '', id = null }) {
  const trimmedName = String(name || '').trim();
  const trimmedAlias = String(alias || '').trim();
  const trimmedGstNumber = normalizeGstNumber(gstNumber);
  const trimmedAddress = String(address || '').trim();

  if (!trimmedName) {
    throw new Error('name is required.');
  }
  if (trimmedGstNumber && trimmedGstNumber.length !== 15) {
    const error = new Error('GST number must be 15 characters.');
    error.statusCode = 400;
    throw error;
  }

  const duplicate = await findClientDuplicate({
    name: trimmedName,
    gstNumber: trimmedGstNumber,
    excludeId: id,
  });
  if (duplicate) {
    const duplicateByName =
      normalizePartyValue(duplicate.name) === normalizePartyValue(trimmedName);
    const error = new Error(
      duplicateByName
        ? 'A client with the same name already exists.'
        : 'A client with the same GST number already exists.',
    );
    error.statusCode = 409;
    throw error;
  }

  const now = new Date().toISOString();
  if (id == null) {
    const result = await run(
      `
      INSERT INTO clients (name, alias, gst_number, address, is_archived, created_at, updated_at)
      VALUES (?, ?, ?, ?, 0, ?, ?)
      `,
      [trimmedName, trimmedAlias, trimmedGstNumber, trimmedAddress, now, now],
    );
    await logChange('clients', result.lastID, 'INSERT');
    return getClientRowById(result.lastID);
  }

  const existing = await getClientRowById(id);
  if (!existing) {
    const error = new Error('Client not found.');
    error.statusCode = 404;
    throw error;
  }
  if ((existing.usage_count || 0) > 0) {
    const lockedOrderUsage = Number(
      (
        await get(
          `
          SELECT COUNT(*) AS count
          FROM order_items
          WHERE client_id = ?
            AND status IN ('inProgress', 'completed', 'delayed')
          `,
          [id],
        )
      )?.count || 0,
    );
    const identityChanged =
      normalizePartyValue(existing.name) !== normalizePartyValue(trimmedName) ||
      normalizeGstNumber(existing.gst_number) !== trimmedGstNumber;
    if (identityChanged && lockedOrderUsage > 0) {
      const error = new Error('Used clients cannot change name or GST number.');
      error.statusCode = 409;
      throw error;
    }
  }

  await run(
    'UPDATE clients SET name = ?, alias = ?, gst_number = ?, address = ?, updated_at = ? WHERE id = ?',
    [trimmedName, trimmedAlias, trimmedGstNumber, trimmedAddress, now, id],
  );
  await logChange('clients', id, 'UPDATE');
  return getClientRowById(id);
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

async function getVendorRowById(id) {
  return get(
    `
    SELECT
      vendors.*,
      (SELECT COUNT(*) FROM delivery_challans WHERE delivery_challans.vendor_id = vendors.id) AS usage_count
    FROM vendors
    WHERE vendors.id = ?
    `,
    [id],
  );
}

async function getVendorsWithUsage() {
  return all(`
    SELECT
      vendors.*,
      (SELECT COUNT(*) FROM delivery_challans WHERE delivery_challans.vendor_id = vendors.id) AS usage_count
    FROM vendors
    ORDER BY vendors.is_archived ASC, LOWER(vendors.name) ASC, vendors.id ASC
  `);
}

async function findVendorDuplicate({ name, gstNumber = '', excludeId = null }) {
  const rows = await all('SELECT id, name, gst_number FROM vendors');
  const normalizedName = normalizePartyValue(name);
  const normalizedGst = normalizeGstNumber(gstNumber);
  return rows.find((row) => {
    if (excludeId != null && row.id === excludeId) {
      return false;
    }
    const sameName = normalizePartyValue(row.name) === normalizedName;
    const sameGst =
      normalizedGst &&
      normalizeGstNumber(row.gst_number || '') === normalizedGst;
    return sameName || Boolean(sameGst);
  }) || null;
}

async function saveVendor({
  name,
  alias = '',
  gstNumber = '',
  address = '',
  contactName = '',
  phone = '',
  email = '',
  id = null,
}) {
  const trimmedName = String(name || '').trim();
  const trimmedAlias = String(alias || '').trim();
  const trimmedAddress = String(address || '').trim();
  const trimmedContactName = String(contactName || '').trim();
  const trimmedPhone = String(phone || '').trim();
  const trimmedEmail = String(email || '').trim();
  const trimmedGstNumber = normalizeGstNumber(gstNumber);
  if (!trimmedName) {
    const error = new Error('Vendor name is required.');
    error.statusCode = 400;
    throw error;
  }

  const duplicate = await findVendorDuplicate({
    name: trimmedName,
    gstNumber: trimmedGstNumber,
    excludeId: id,
  });
  if (duplicate) {
    const error = new Error('A vendor with the same name or GST number already exists.');
    error.statusCode = 409;
    throw error;
  }

  const now = new Date().toISOString();
  if (id == null) {
    const result = await run(
      `
      INSERT INTO vendors (
        name, alias, gst_number, address, contact_name, phone, email, is_archived, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
      `,
      [
        trimmedName,
        trimmedAlias,
        trimmedGstNumber,
        trimmedAddress,
        trimmedContactName,
        trimmedPhone,
        trimmedEmail,
        now,
        now,
      ],
    );
    await logChange('vendors', result.lastID, 'INSERT');
    return getVendorRowById(result.lastID);
  }

  const existing = await getVendorRowById(id);
  if (!existing) {
    const error = new Error('Vendor not found.');
    error.statusCode = 404;
    throw error;
  }

  await run(
    `
    UPDATE vendors
    SET name = ?, alias = ?, gst_number = ?, address = ?, contact_name = ?, phone = ?, email = ?, updated_at = ?
    WHERE id = ?
    `,
    [
      trimmedName,
      trimmedAlias,
      trimmedGstNumber,
      trimmedAddress,
      trimmedContactName,
      trimmedPhone,
      trimmedEmail,
      now,
      id,
    ],
  );
  await logChange('vendors', id, 'UPDATE');
  return getVendorRowById(id);
}

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

const DELIVERY_CHALLAN_STATUSES = new Set(['draft', 'issued', 'cancelled']);
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

async function getDeliveryChallanItems(challanId) {
  const items = await all(
    `
    SELECT *
    FROM delivery_challan_items
    WHERE challan_id = ?
    ORDER BY line_no ASC, id ASC
    `,
    [challanId],
  );
  
  if (items.length > 0) {
    const itemIds = items.map(item => item.id);
    const barcodes = await all(
      `SELECT * FROM piece_barcodes WHERE challan_item_id IN (${itemIds.join(',')})`
    );
    
    for (const item of items) {
      item.piece_barcodes = barcodes.filter(b => b.challan_item_id === item.id).map(b => ({
        id: b.id,
        challanItemId: b.challan_item_id,
        parentCode: b.parent_code,
        childCode: b.child_code,
      }));
    }
  }
  return items;
}

async function getDeliveryChallanOrderIds(challanId) {
  const rows = await all(
    `
    SELECT order_id
    FROM delivery_challan_order_items
    WHERE challan_id = ?
    ORDER BY order_id ASC
    `,
    [challanId],
  );
  return rows
    .map((row) => Number(row.order_id || 0))
    .filter((value) => Number.isInteger(value) && value > 0);
}

function normalizeReportGroupCode(value) {
  return String(value || '')
    .trim()
    .toUpperCase()
    .replace(/\s+/g, '-')
    .replace(/[^A-Z0-9_-]/g, '');
}

function normalizeReportGroupCodes(values = []) {
  const candidates = Array.isArray(values) ? values : [];
  return [
    ...new Set(
      candidates
        .map(normalizeReportGroupCode)
        .filter(Boolean),
    ),
  ].sort();
}

function deriveReportGroupCodesFromOrderIds(orderIds = []) {
  const normalizedOrderIds = [
    ...new Set(
      orderIds
        .map((value) => Number(value || 0))
        .filter((value) => Number.isInteger(value) && value > 0),
    ),
  ].sort((a, b) => a - b);
  if (normalizedOrderIds.length === 0) {
    return [];
  }
  if (normalizedOrderIds.length === 1) {
    return [`ORD-${normalizedOrderIds[0]}`];
  }
  return [`ORDSET-${normalizedOrderIds.join('-')}`];
}

async function getDeliveryChallanReportGroupCodes(challanId) {
  const rows = await all(
    `
    SELECT report_group_code
    FROM delivery_challan_report_groups
    WHERE challan_id = ?
    ORDER BY report_group_code ASC
    `,
    [challanId],
  );
  return rows
    .map((row) => normalizeReportGroupCode(row.report_group_code))
    .filter(Boolean);
}

async function effectiveReportGroupCodesForChallan(row, orderIds = null) {
  const explicitCodes = await getDeliveryChallanReportGroupCodes(row.id);
  if (normalizeChallanType(row.type) !== 'delivery') {
    return explicitCodes;
  }
  const linkedOrderIds = orderIds || await getDeliveryChallanOrderIds(row.id);
  const fallbackOrderIds = linkedOrderIds.length > 0
    ? linkedOrderIds
    : [Number(row.order_id || 0)].filter((value) => value > 0);
  return [
    ...new Set([
      ...explicitCodes,
      ...deriveReportGroupCodesFromOrderIds(fallbackOrderIds),
    ]),
  ].sort();
}

async function replaceChallanReportGroups(challanId, codes = []) {
  const now = new Date().toISOString();
  const normalizedCodes = normalizeReportGroupCodes(codes);
  await run('DELETE FROM delivery_challan_report_groups WHERE challan_id = ?', [challanId]);
  for (const code of normalizedCodes) {
    await run(
      `
      INSERT INTO report_groups (code, label, created_at, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(code) DO UPDATE SET updated_at = excluded.updated_at
      `,
      [code, code, now, now],
    );
    await run(
      `
      INSERT OR IGNORE INTO delivery_challan_report_groups (
        challan_id, report_group_code, created_at
      ) VALUES (?, ?, ?)
      `,
      [challanId, code, now],
    );
  }
  return normalizedCodes;
}

async function getOrderRowsByIds(orderIds = []) {
  const normalizedOrderIds = [
    ...new Set(
      orderIds
        .map((value) => Number(value || 0))
        .filter((value) => Number.isInteger(value) && value > 0),
    ),
  ];
  if (normalizedOrderIds.length === 0) {
    return [];
  }
  const placeholders = normalizedOrderIds.map(() => '?').join(', ');
  return all(
    `
    SELECT o.*, c.gst_number AS client_gstin
    FROM order_items o
    LEFT JOIN clients c ON c.id = o.client_id
    WHERE o.id IN (${placeholders})
    ORDER BY datetime(o.created_at) DESC, o.id DESC
    `,
    normalizedOrderIds,
  );
}

function rowToDeliveryChallanItemDto(row) {
  const formatMeasure = (value) => {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? String(numeric) : '';
  };
  return {
    id: row.id,
    challan_id: row.challan_id,
    order_item_id: row.order_item_id || null,
    production_run_id: row.production_run_id || null,
    item_id: row.item_id || null,
    variation_leaf_node_id: Number(row.variation_leaf_node_id || 0),
    line_no: Number(row.line_no || 0),
    particulars: row.particulars || '',
    hsn_code: row.hsn_code || '',
    note: row.note || '',
    variation_path_label: row.variation_path_label || '',
    variation_path_node_ids: parseJson(row.variation_path_node_ids_json, []),
    custom_variation_values: parseJson(row.custom_variation_values_json, {}),
    quantity_pcs: formatMeasure(row.quantity_pcs),
    weight: formatMeasure(row.weight),
    piece_barcodes: row.piece_barcodes || [],
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
  };
}

function rowToChallanTemplateMappingDto(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    templateId: row.template_id,
    fieldType: row.field_type || 'DYNAMIC',
    fieldKey: row.field_key || '',
    fieldValue: row.field_value || '',
    assetObjectKey: row.asset_object_key || '',
    assetImageUrl: row.asset_image_url || null,
    assetWidthPx: Number(row.asset_width_px || 0),
    assetHeightPx: Number(row.asset_height_px || 0),
    widthMm: Number(
      row.width_mm ||
        (String(row.field_type || 'DYNAMIC').toUpperCase() === 'IMAGE'
          ? row.image_width_mm || 35
          : row.max_width_mm || 80),
    ),
    heightMm: Number(
      row.height_mm ||
        (String(row.field_type || 'DYNAMIC').toUpperCase() === 'IMAGE'
          ? row.image_height_mm || 20
          : 12),
    ),
    imageWidthMm: Number(row.image_width_mm || 35),
    imageHeightMm: Number(row.image_height_mm || 20),
    lockAspectRatio: Number(row.lock_aspect_ratio ?? 1) === 1,
    xMm: Number(row.x_mm || 0),
    yMm: Number(row.y_mm || 0),
    xPercent: Number(row.x_percent || 0),
    yPercent: Number(row.y_percent || 0),
    fontSize: Number(row.font_size || 10),
    fontWeight: row.font_weight || 'normal',
    alignment: row.alignment || 'left',
    textColor: row.text_color || 'black',
    letterSpacing: Number(row.letter_spacing || 0),
    maxChars: Number(row.max_chars || 0),
    maxWidthMm: Number(row.max_width_mm || 80),
    minFontSize: Number(row.min_font_size || 6),
    minRows: Number(row.min_rows || 0),
    maxRows: Number(row.max_rows || 0),
    tableHeightMm: Number(row.table_height_mm || 60),
    rowHeightMm: Number(row.row_height_mm || 6),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

async function rowToChallanTemplateDto(row, { includeMappings = true } = {}) {
  if (!row) {
    return null;
  }
  const mappings = includeMappings
    ? await all(
        `
        SELECT *
        FROM challan_template_mappings
        WHERE template_id = ?
        ORDER BY id ASC
        `,
        [row.id],
      )
    : [];
  let backgroundImageUrl = null;
  let backgroundImageUrlExpiresAt = null;
  if (row.background_object_key) {
    try {
      const payload = await assetReadUrlPayload(row.background_object_key);
      backgroundImageUrl = payload.readUrl;
      backgroundImageUrlExpiresAt = payload.expiresAt;
    } catch (_) {
      backgroundImageUrl = null;
      backgroundImageUrlExpiresAt = null;
    }
  }
  const mappedDtos = [];
  for (const mapping of mappings) {
    let assetImageUrl = null;
    if (mapping.asset_object_key) {
      try {
        const payload = await assetReadUrlPayload(mapping.asset_object_key);
        assetImageUrl = payload.readUrl;
      } catch (_) {
        assetImageUrl = null;
      }
    }
    mappedDtos.push(
      rowToChallanTemplateMappingDto({
        ...mapping,
        asset_image_url: assetImageUrl,
      }),
    );
  }
  return {
    id: row.id,
    name: row.name || '',
    partyType: row.party_type || '',
    partyId: Number(row.party_id || 0),
    challanType: normalizeChallanType(row.challan_type),
    backgroundObjectKey: row.background_object_key || '',
    backgroundImageUrl,
    backgroundImageUrlExpiresAt,
    canvasWidth: Number(row.canvas_width || 0),
    canvasHeight: Number(row.canvas_height || 0),
    rotationDegrees: Number(row.rotation_degrees || 0),
    globalOffsetXmm: Number(row.global_offset_x_mm || 0),
    globalOffsetYmm: Number(row.global_offset_y_mm || 0),
    stockSize: row.stock_size || row.paper_size || 'A4',
    paperSize: row.paper_size || 'A4',
    nUpLayout: Number(row.n_up_layout || 1),
    isActive: Number(row.is_active || 0) === 1,
    mappings: mappedDtos,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

async function rowToDeliveryChallanDto(row, { includeItems = true } = {}) {
  const items = includeItems ? await getDeliveryChallanItems(row.id) : [];
  let orderIds = await getDeliveryChallanOrderIds(row.id);
  if (orderIds.length === 0 && Number(row.order_id || 0) > 0) {
    orderIds = [Number(row.order_id || 0)];
  }
  const orderRows = await getOrderRowsByIds(orderIds);
  const orderNos = [
    ...new Set(
      orderRows
        .map((order) => String(order.order_no || '').trim())
      .filter(Boolean),
    ),
  ];
  const clientId = Number(orderRows[0]?.client_id || 0) || null;
  const reportGroupCodes = await effectiveReportGroupCodesForChallan(
    row,
    orderIds,
  );
  
  const assetRows = await all(
    "SELECT * FROM uploaded_assets WHERE entity_type = 'delivery_challan' AND entity_id = ? AND status = 'uploaded' ORDER BY created_at ASC",
    [row.id]
  );
  const assets = await Promise.all(assetRows.map(rowToUploadedAssetDto));

  return {
    id: row.id,
    type: normalizeChallanType(row.type),
    purpose: row.purpose || 'trading',
    challanPurpose: row.purpose || 'trading',
    challan_purpose: row.purpose || 'trading',
    // Free-text purpose for internal challans (empty for delivery/reception).
    internal_purpose: row.internal_purpose || '',
    internalPurpose: row.internal_purpose || '',
    // Per-line settlement breakdown once the challan has been reconciled
    // (scrap/leftover/lost/rejection/finished-goods); empty otherwise.
    reconciliation_json: row.reconciliation_json || '',
    reconciliationJson: row.reconciliation_json || '',
    order_id: row.order_id || null,
    order_ids: orderIds,
    report_group_codes: reportGroupCodes,
    reportGroupCodes: reportGroupCodes,
    order_no: row.order_no || '',
    order_nos: orderNos,
    client_id: clientId,
    challan_no: row.challan_no || '',
    date: row.date || '',
    location: row.location || '',
    customer_name: row.customer_name || '',
    customer_gstin: row.customer_gstin || '',
    vendor_id: row.vendor_id || null,
    vendor_name: row.vendor_name || '',
    vendor_gstin: row.vendor_gstin || '',
    material_owner_client_id: row.material_owner_client_id || null,
    material_owner_client_name: row.material_owner_client_name || '',
    material_owner_gstin: row.material_owner_gstin || '',
    source_reference: row.source_reference || '',
    company_profile_snapshot: parseJsonObject(row.company_profile_snapshot, null),
    notes: row.notes || '',
    maintain_stocks: Number(row.maintain_stocks ?? 1) !== 0,
    used_in_report: Number(row.used_in_report ?? 0) !== 0,
    usedInReport: Number(row.used_in_report ?? 0) !== 0,
    status: row.status || 'draft',
    created_by: row.created_by || null,
    updated_by: row.updated_by || null,
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
    items: items.map(rowToDeliveryChallanItemDto),
    items_count: Number(row.items_count || items.length || 0),
    assets: assets,
  };
}

async function generateChallanNumber(type = 'delivery') {
  const normalizedType = normalizeChallanType(type);
  const prefix = normalizedType === 'reception'
    ? 'RC'
    : (normalizedType === 'internal' ? 'IC' : 'DC');
  const row = await get(
    `
    SELECT challan_no
    FROM delivery_challans
    WHERE challan_no LIKE ?
    ORDER BY id DESC
    LIMIT 1
    `,
    [`${prefix}-%`],
  );
  const match = String(row?.challan_no || '').match(/(\d+)$/);
  const next = match ? Number(match[1]) + 1 : 1;
  return `${prefix}-${String(next).padStart(5, '0')}`;
}

async function challanNumberWarning(challanNo, type = 'delivery') {
  const normalized = String(challanNo || '').trim().toUpperCase();
  const prefix = normalizeChallanType(type) === 'reception' ? 'RC' : 'DC';
  const match = normalized.match(new RegExp(`^${prefix}-(\\d+)$`));
  if (!match) {
    return null;
  }
  const manualSequence = Number(match[1]);
  const next = await generateChallanNumber(type);
  const nextMatch = next.match(/(\d+)$/);
  const nextSequence = nextMatch ? Number(nextMatch[1]) : 0;
  if (manualSequence > 0 && nextSequence > 0 && manualSequence < nextSequence) {
    return {
      code: 'manual_sequence_overlap',
      message: `Manual challan number ${challanNo} is inside the generated ${prefix} sequence. Suggested next number: ${next}.`,
      suggestedChallanNo: next,
    };
  }
  return null;
}

function normalizeChallanDate(value) {
  const input = String(value || '').trim();
  if (!input) {
    return new Date().toISOString().slice(0, 10);
  }
  if (Number.isNaN(Date.parse(input))) {
    const error = new Error('Invalid challan date.');
    error.statusCode = 400;
    throw error;
  }
  return input.slice(0, 10);
}

function normalizeDeliveryChallanMeasure(value, fieldName) {
  const input = String(value ?? '').trim();
  if (!input) {
    return 0;
  }
  const numeric = Number(input);
  if (!Number.isFinite(numeric) || numeric < 0) {
    const error = new Error(`Invalid ${fieldName}.`);
    error.statusCode = 400;
    throw error;
  }
  return numeric;
}

function normalizeDeliveryChallanItems(items = []) {
  if (!Array.isArray(items)) {
    return [];
  }
  return items
    .map((item, index) => ({
      orderItemId: Number(item.orderItemId ?? item.order_item_id ?? 0) || null,
      productionRunId: Number(item.productionRunId ?? item.production_run_id ?? 0) || null,
      itemId: Number(item.itemId ?? item.item_id ?? 0) || null,
      variationLeafNodeId:
        Number(item.variationLeafNodeId ?? item.variation_leaf_node_id ?? 0) || 0,
      lineNo: Number(item.lineNo ?? item.line_no ?? index + 1) || index + 1,
      particulars: String(item.particulars || '').trim(),
      hsnCode: String(item.hsnCode ?? item.hsn_code ?? '').trim(),
      note: String(item.note ?? item.lineNote ?? item.line_note ?? '').trim(),
      variationPathLabel: String(
        item.variationPathLabel ?? item.variation_path_label ?? '',
      ).trim(),
      variationPathNodeIds: parseJsonOrArray(
        item.variationPathNodeIds ?? item.variation_path_node_ids ?? item.variation_path_node_ids_json,
        [],
      )
        .map((id) => Number(id))
        .filter((id) => Number.isFinite(id) && id > 0),
      customVariationValues: normalizeCustomVariationValues(
        item.customVariationValues ?? item.custom_variation_values ?? item.custom_variation_values_json ?? {},
      ),
      quantityPcs: String(item.quantityPcs ?? item.quantity_pcs ?? '').trim(),
      weight: String(item.weight || '').trim(),
    }))
    .filter(
      (item) =>
        item.particulars ||
        item.hsnCode ||
        item.note ||
        item.quantityPcs ||
        item.weight ||
        item.orderItemId ||
        item.productionRunId ||
        item.itemId,
    )
    .map((item, index) => ({ ...item, lineNo: index + 1 }));
}

async function getDeliveryChallanRowById(id) {
  return get('SELECT * FROM delivery_challans WHERE id = ?', [Number(id)]);
}

function normalizeTemplatePartyType(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'client' || normalized === 'vendor' || normalized === 'generic') {
    return normalized;
  }
  const error = new Error('Template party type must be client, vendor, or generic.');
  error.statusCode = 400;
  throw error;
}

function normalizeTemplateNumber(value, fallback, { min = null, max = null } = {}) {
  const numeric = Number(value ?? fallback);
  const normalized = Number.isFinite(numeric) ? numeric : fallback;
  if (min != null && normalized < min) {
    return min;
  }
  if (max != null && normalized > max) {
    return max;
  }
  return normalized;
}

function normalizeTemplateAlignment(value) {
  const normalized = String(value || 'left').trim().toLowerCase();
  return ['left', 'center', 'right'].includes(normalized) ? normalized : 'left';
}

function normalizeTemplateFieldType(value) {
  const normalized = String(value || 'DYNAMIC').trim().toUpperCase();
  if (normalized === 'STATIC' || normalized === 'IMAGE' || normalized === 'TABLE') {
    return normalized;
  }
  return 'DYNAMIC';
}

function normalizeTemplatePaperSize(value) {
  const normalized = String(value || 'A4').trim().toUpperCase();
  return ['A3', 'A4', 'A5', 'A6'].includes(normalized) ? normalized : 'A4';
}

function normalizeTemplateStockSize(value, fallback = 'A4') {
  const normalized = String(value || fallback).trim().toUpperCase();
  return ['A3', 'A4', 'A5', 'A6'].includes(normalized) ? normalized : fallback;
}

function normalizeTemplateNUpLayout(value) {
  const numeric = Math.round(Number(value || 1));
  return [1, 2, 4].includes(numeric) ? numeric : 1;
}

function normalizeTemplateTextColor(value) {
  const normalized = String(value || 'black').trim().toLowerCase();
  return ['black', 'blue', 'red'].includes(normalized) ? normalized : 'black';
}

function normalizeTemplateFieldKey(value) {
  return String(value || '')
    .trim()
    .replace(/[^\w.:-]/g, '_')
    .slice(0, 80);
}

function normalizeChallanTemplateMappings(mappings = []) {
  if (!Array.isArray(mappings)) {
    return [];
  }
  const seen = new Set();
  return mappings
    .map((mapping) => {
      const fieldType = normalizeTemplateFieldType(
        mapping?.fieldType ?? mapping?.field_type,
      );
      const fieldKey = normalizeTemplateFieldKey(
        mapping?.fieldKey ?? mapping?.field_key,
      );
      if (!fieldKey || seen.has(fieldKey)) {
        return null;
      }
      seen.add(fieldKey);
      return {
        fieldType,
        fieldKey,
        fieldValue: String(mapping?.fieldValue ?? mapping?.field_value ?? '')
          .trim()
          .slice(0, 1000),
        assetObjectKey: String(mapping?.assetObjectKey ?? mapping?.asset_object_key ?? '')
          .trim(),
        assetWidthPx: Math.max(
          0,
          Math.round(
            normalizeTemplateNumber(
              mapping?.assetWidthPx ?? mapping?.asset_width_px,
              0,
            ),
          ),
        ),
        assetHeightPx: Math.max(
          0,
          Math.round(
            normalizeTemplateNumber(
              mapping?.assetHeightPx ?? mapping?.asset_height_px,
              0,
            ),
          ),
        ),
        widthMm: normalizeTemplateNumber(
          mapping?.widthMm ??
            mapping?.width_mm ??
            (fieldType === 'IMAGE'
              ? mapping?.imageWidthMm ?? mapping?.image_width_mm
              : mapping?.maxWidthMm ?? mapping?.max_width_mm),
          fieldType === 'IMAGE' ? 35 : 80,
          { min: 2, max: 420 },
        ),
        heightMm: normalizeTemplateNumber(
          mapping?.heightMm ??
            mapping?.height_mm ??
            (fieldType === 'IMAGE'
              ? mapping?.imageHeightMm ?? mapping?.image_height_mm
              : 12),
          fieldType === 'IMAGE' ? 20 : 12,
          { min: 2, max: 420 },
        ),
        imageWidthMm: normalizeTemplateNumber(
          mapping?.imageWidthMm ?? mapping?.image_width_mm,
          35,
          { min: 2, max: 420 },
        ),
        imageHeightMm: normalizeTemplateNumber(
          mapping?.imageHeightMm ?? mapping?.image_height_mm,
          20,
          { min: 2, max: 420 },
        ),
        lockAspectRatio: parseBooleanEnv(
          mapping?.lockAspectRatio ?? mapping?.lock_aspect_ratio ?? true,
          true,
        ),
        xMm: normalizeTemplateNumber(
          mapping?.xMm ?? mapping?.x_mm,
          0,
          { min: 0, max: 420 },
        ),
        yMm: normalizeTemplateNumber(
          mapping?.yMm ?? mapping?.y_mm,
          0,
          { min: 0, max: 420 },
        ),
        xPercent: normalizeTemplateNumber(
          mapping?.xPercent ?? mapping?.x_percent,
          0,
          { min: 0, max: 1 },
        ),
        yPercent: normalizeTemplateNumber(
          mapping?.yPercent ?? mapping?.y_percent,
          0,
          { min: 0, max: 1 },
        ),
        fontSize: normalizeTemplateNumber(
          mapping?.fontSize ?? mapping?.font_size,
          10,
          { min: 6, max: 32 },
        ),
        fontWeight: String(
          mapping?.fontWeight ?? mapping?.font_weight ?? 'normal',
        )
          .trim()
          .toLowerCase() === 'bold'
          ? 'bold'
          : 'normal',
        alignment: normalizeTemplateAlignment(
          mapping?.alignment ?? mapping?.textAlign ?? mapping?.text_align,
        ),
        textColor: normalizeTemplateTextColor(
          mapping?.textColor ?? mapping?.text_color,
        ),
        letterSpacing: normalizeTemplateNumber(
          mapping?.letterSpacing ?? mapping?.letter_spacing,
          0,
          { min: -2, max: 6 },
        ),
        maxChars: Math.max(
          0,
          Math.round(
            normalizeTemplateNumber(
              mapping?.maxChars ?? mapping?.max_chars,
              0,
            ),
          ),
        ),
        maxWidthMm: normalizeTemplateNumber(
          mapping?.maxWidthMm ?? mapping?.max_width_mm,
          80,
          { min: 5, max: 210 },
        ),
        minFontSize: normalizeTemplateNumber(
          mapping?.minFontSize ?? mapping?.min_font_size,
          6,
          { min: 6, max: 32 },
        ),
        minRows: Math.max(
          0,
          Math.round(
            normalizeTemplateNumber(
              mapping?.minRows ?? mapping?.min_rows,
              0,
            ),
          ),
        ),
        maxRows: Math.max(
          0,
          Math.round(
            normalizeTemplateNumber(
              mapping?.maxRows ?? mapping?.max_rows,
              0,
            ),
          ),
        ),
        tableHeightMm: normalizeTemplateNumber(
          mapping?.tableHeightMm ?? mapping?.table_height_mm,
          60,
          { min: 5, max: 297 },
        ),
        rowHeightMm: normalizeTemplateNumber(
          mapping?.rowHeightMm ?? mapping?.row_height_mm,
          6,
          { min: 2, max: 20 },
        ),
      };
    })
    .filter(Boolean);
}

async function listChallanTemplates({
  partyType = '',
  partyId = null,
  challanType = '',
  activeOnly = false,
} = {}) {
  const where = [];
  const params = [];
  if (partyType) {
    where.push('party_type = ?');
    params.push(normalizeTemplatePartyType(partyType));
  }
  const normalizedPartyId = Number(partyId || 0);
  if (Number.isInteger(normalizedPartyId) && normalizedPartyId > 0) {
    where.push('party_id = ?');
    params.push(normalizedPartyId);
  }
  if (challanType) {
    where.push('challan_type = ?');
    params.push(normalizeChallanType(challanType));
  }
  if (activeOnly) {
    where.push('is_active = 1');
  }
  const rows = await all(
    `
    SELECT *
    FROM challan_templates
    ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
    ORDER BY is_active DESC, datetime(updated_at) DESC, id DESC
    `,
    params,
  );
  return Promise.all(rows.map((row) => rowToChallanTemplateDto(row)));
}

async function getChallanTemplateRowById(id) {
  return get('SELECT * FROM challan_templates WHERE id = ?', [Number(id)]);
}

async function saveChallanTemplate(input = {}, id = null) {
  const name = String(input.name || '').trim();
  const partyType = normalizeTemplatePartyType(
    input.partyType ?? input.party_type ?? 'generic',
  );
  const partyId = Number(input.partyId ?? input.party_id ?? 0);
  const challanType = normalizeChallanType(input.challanType ?? input.challan_type);
  const backgroundObjectKey = String(
    input.backgroundObjectKey ?? input.background_object_key ?? '',
  ).trim();
  const canvasWidth = Math.round(Number(input.canvasWidth ?? input.canvas_width ?? 0));
  const canvasHeight = Math.round(Number(input.canvasHeight ?? input.canvas_height ?? 0));
  const rotationDegrees = normalizeTemplateNumber(
    input.rotationDegrees ?? input.rotation_degrees,
    0,
    { min: -5, max: 5 },
  );
  const globalOffsetXmm = normalizeTemplateNumber(
    input.globalOffsetXmm ?? input.global_offset_x_mm,
    0,
    { min: -50, max: 50 },
  );
  const globalOffsetYmm = normalizeTemplateNumber(
    input.globalOffsetYmm ?? input.global_offset_y_mm,
    0,
    { min: -50, max: 50 },
  );
  const paperSize = normalizeTemplatePaperSize(
    input.paperSize ?? input.paper_size,
  );
  const stockSize = normalizeTemplateStockSize(
    input.stockSize ?? input.stock_size,
    paperSize,
  );
  const nUpLayout = normalizeTemplateNUpLayout(
    input.nUpLayout ?? input.n_up_layout,
  );
  const isActive = input.isActive ?? input.is_active ?? true;
  const mappings = normalizeChallanTemplateMappings(input.mappings || []);

  if (!name) {
    const error = new Error('Template name is required.');
    error.statusCode = 400;
    throw error;
  }
  if (
    partyType !== 'generic' &&
    (!Number.isInteger(partyId) || partyId <= 0)
  ) {
    const error = new Error('Template party is required.');
    error.statusCode = 400;
    throw error;
  }
  if (!backgroundObjectKey || !canvasWidth || !canvasHeight) {
    const error = new Error('Template background scan is required.');
    error.statusCode = 400;
    throw error;
  }
  validateTemplateSheetLayout({ stockSize, paperSize, nUpLayout });

  if (partyType !== 'generic') {
    const partyRow = partyType === 'client'
      ? await get('SELECT id FROM clients WHERE id = ? AND is_archived = 0', [partyId])
      : await get('SELECT id FROM vendors WHERE id = ? AND is_archived = 0', [partyId]);
    if (!partyRow) {
      const error = new Error('Template party does not exist or is archived.');
      error.statusCode = 400;
      throw error;
    }
  }

  const now = new Date().toISOString();
  await run('BEGIN TRANSACTION');
  try {
    let templateId = Number(id || 0);
    if (templateId > 0) {
      const existing = await getChallanTemplateRowById(templateId);
      if (!existing) {
        const error = new Error('Challan template not found.');
        error.statusCode = 404;
        throw error;
      }
      await run(
        `
        UPDATE challan_templates
        SET name = ?, party_type = ?, party_id = ?, challan_type = ?,
            background_object_key = ?, canvas_width = ?, canvas_height = ?,
            rotation_degrees = ?, global_offset_x_mm = ?, global_offset_y_mm = ?,
            stock_size = ?, paper_size = ?, n_up_layout = ?, is_active = ?, updated_at = ?
        WHERE id = ?
        `,
        [
          name,
          partyType,
          partyType === 'generic' ? 0 : partyId,
          challanType,
          backgroundObjectKey,
          canvasWidth,
          canvasHeight,
          rotationDegrees,
          globalOffsetXmm,
          globalOffsetYmm,
          stockSize,
          paperSize,
          nUpLayout,
          isActive ? 1 : 0,
          now,
          templateId,
        ],
      );
      await run('DELETE FROM challan_template_mappings WHERE template_id = ?', [
        templateId,
      ]);
    } else {
      const result = await run(
        `
        INSERT INTO challan_templates (
          name, party_type, party_id, challan_type, background_object_key,
          canvas_width, canvas_height, rotation_degrees, global_offset_x_mm,
          global_offset_y_mm, stock_size, paper_size, n_up_layout, is_active, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `,
        [
          name,
          partyType,
          partyType === 'generic' ? 0 : partyId,
          challanType,
          backgroundObjectKey,
          canvasWidth,
          canvasHeight,
          rotationDegrees,
          globalOffsetXmm,
          globalOffsetYmm,
          stockSize,
          paperSize,
          nUpLayout,
          isActive ? 1 : 0,
          now,
          now,
        ],
      );
      templateId = result.lastID;
    }

    if (isActive) {
      await run(
        `
        UPDATE challan_templates
        SET is_active = 0, updated_at = ?
        WHERE id != ? AND party_type = ? AND party_id = ? AND challan_type = ?
        `,
        [now, templateId, partyType, partyType === 'generic' ? 0 : partyId, challanType],
      );
    }

    for (const mapping of mappings) {
      if (mapping.fieldType === 'IMAGE' && !mapping.assetObjectKey) {
        const error = new Error('Image template mappings require an uploaded stamp asset.');
        error.statusCode = 400;
        throw error;
      }
      await run(
        `
        INSERT INTO challan_template_mappings (
          template_id, field_type, field_key, field_value, asset_object_key,
          asset_width_px, asset_height_px, width_mm, height_mm, image_width_mm, image_height_mm,
          lock_aspect_ratio, x_mm, y_mm, x_percent, y_percent, font_size, font_weight,
          alignment, text_color, letter_spacing, max_chars, max_width_mm,
          min_font_size, min_rows, max_rows, table_height_mm, row_height_mm,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `,
        [
          templateId,
          mapping.fieldType,
          mapping.fieldKey,
          mapping.fieldValue,
          mapping.assetObjectKey,
          mapping.assetWidthPx,
          mapping.assetHeightPx,
          mapping.widthMm,
          mapping.heightMm,
          mapping.imageWidthMm,
          mapping.imageHeightMm,
          mapping.lockAspectRatio ? 1 : 0,
          mapping.xMm,
          mapping.yMm,
          mapping.xPercent,
          mapping.yPercent,
          mapping.fontSize,
          mapping.fontWeight,
          mapping.alignment,
          mapping.textColor,
          mapping.letterSpacing,
          mapping.maxChars,
          mapping.maxWidthMm,
          mapping.minFontSize,
          mapping.minRows,
          mapping.maxRows,
          mapping.tableHeightMm,
          mapping.rowHeightMm,
          now,
          now,
        ],
      );
    }
    await run('COMMIT');
    return rowToChallanTemplateDto(await getChallanTemplateRowById(templateId));
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function deleteChallanTemplate(id) {
  const existing = await getChallanTemplateRowById(id);
  if (!existing) {
    const error = new Error('Challan template not found.');
    error.statusCode = 404;
    throw error;
  }
  await run('DELETE FROM challan_templates WHERE id = ?', [Number(id)]);
}

async function getTemplatePartyForChallan(challanRow) {
  const type = normalizeChallanType(challanRow?.type);
  if (type === 'reception') {
    const vendorId = Number(challanRow?.vendor_id || 0);
    return vendorId > 0 ? { partyType: 'vendor', partyId: vendorId } : null;
  }
  let orderIds = await getDeliveryChallanOrderIds(challanRow.id);
  if (orderIds.length === 0 && Number(challanRow.order_id || 0) > 0) {
    orderIds = [Number(challanRow.order_id || 0)];
  }
  const orders = await getOrderRowsByIds(orderIds);
  const clientId = Number(orders[0]?.client_id || 0);
  return clientId > 0 ? { partyType: 'client', partyId: clientId } : null;
}

async function findActiveChallanTemplateForChallan(challanRow) {
  const genericTemplate = await get(
    `
    SELECT *
    FROM challan_templates
    WHERE party_type = 'generic'
      AND party_id = 0
      AND challan_type = ?
      AND is_active = 1
    ORDER BY datetime(updated_at) DESC, id DESC
    LIMIT 1
    `,
    [normalizeChallanType(challanRow.type)],
  );
  if (genericTemplate) {
    return genericTemplate;
  }
  const party = await getTemplatePartyForChallan(challanRow);
  if (!party) {
    return null;
  }
  return get(
    `
    SELECT *
    FROM challan_templates
    WHERE party_type = ?
      AND party_id = ?
      AND challan_type = ?
      AND is_active = 1
    ORDER BY datetime(updated_at) DESC, id DESC
    LIMIT 1
    `,
    [party.partyType, party.partyId, normalizeChallanType(challanRow.type)],
  );
}

function truncateTemplateText(value, maxChars) {
  const text = String(value ?? '');
  const limit = Number(maxChars || 0);
  if (!Number.isInteger(limit) || limit <= 0 || text.length <= limit) {
    return text;
  }
  return text.slice(0, limit);
}

function challanTemplateScalarFields(challanDto) {
  const isReception = challanDto.type === 'reception';
  const items = Array.isArray(challanDto.items) ? challanDto.items : [];
  const totalPcs = items.reduce((sum, item) => sum + Number(item.quantity_pcs || 0), 0);
  const totalWeight = items.reduce((sum, item) => sum + Number(item.weight || 0), 0);
  const totalQty = totalPcs > 0
    ? `${totalPcs} pcs`
    : totalWeight > 0
    ? `${totalWeight} weight`
    : '0';
  const date = challanDto.date || '';
  const partyName = isReception
    ? challanDto.vendor_name || ''
    : challanDto.customer_name || '';
  const gstin = isReception
    ? challanDto.vendor_gstin || ''
    : challanDto.customer_gstin || '';
  return {
    challan_no: challanDto.challan_no || '',
    challanNo: challanDto.challan_no || '',
    date,
    challan_date: date,
    challanDate: date,
    party_name: partyName,
    partyName,
    client_name: partyName,
    clientName: partyName,
    customer_name: challanDto.customer_name || partyName,
    customerName: challanDto.customer_name || partyName,
    vendor_name: challanDto.vendor_name || partyName,
    vendorName: challanDto.vendor_name || partyName,
    gstin,
    gst_number: gstin,
    gstNumber: gstin,
    customer_gstin: challanDto.customer_gstin || gstin,
    customerGstin: challanDto.customer_gstin || gstin,
    vendor_gstin: challanDto.vendor_gstin || gstin,
    vendorGstin: challanDto.vendor_gstin || gstin,
    location: '',
    source_ref: isReception
      ? challanDto.source_reference || ''
      : (challanDto.order_nos || []).join(', ') || challanDto.order_no || '',
    sourceRef: isReception
      ? challanDto.source_reference || ''
      : (challanDto.order_nos || []).join(', ') || challanDto.order_no || '',
    total_qty: totalQty,
    totalQty,
    notes: challanDto.notes || '',
  };
}

function itemTableValueForField(fieldKey, item) {
  switch (fieldKey) {
    case 'item_particulars':
      return item.particulars || '';
    case 'hsn':
      return item.hsn_code || '';
    case 'qty_pcs':
      return item.quantity_pcs || '';
    case 'weight':
      return item.weight || '';
    case 'note':
      return item.note || '';
    default:
      return '';
  }
}

function pdfColorForTemplate(value) {
  switch (String(value || '').trim().toLowerCase()) {
    case 'blue':
      return '#1D4ED8';
    case 'red':
      return '#B91C1C';
    default:
      return 'black';
  }
}

function mmToPdfPoints(value) {
  return Number(value || 0) * 72 / 25.4;
}

function paperSizeMmForTemplate(value) {
  const normalized = normalizeTemplatePaperSize(value);
  if (normalized === 'A3') {
    return { widthMm: 297, heightMm: 420 };
  }
  if (normalized === 'A6') {
    return { widthMm: 105, heightMm: 148 };
  }
  if (normalized === 'A5') {
    return { widthMm: 148, heightMm: 210 };
  }
  return { widthMm: 210, heightMm: 297 };
}

function slotFramesForTemplate(paperSize, nUpLayout) {
  const page = paperSizeMmForTemplate(paperSize);
  if (Number(nUpLayout || 1) === 2) {
    return [
      { xMm: 0, yMm: 0, widthMm: page.widthMm, heightMm: page.heightMm / 2 },
      {
        xMm: 0,
        yMm: page.heightMm / 2,
        widthMm: page.widthMm,
        heightMm: page.heightMm / 2,
      },
    ];
  }
  if (Number(nUpLayout || 1) === 4) {
    return [
      { xMm: 0, yMm: 0, widthMm: page.widthMm / 2, heightMm: page.heightMm / 2 },
      {
        xMm: page.widthMm / 2,
        yMm: 0,
        widthMm: page.widthMm / 2,
        heightMm: page.heightMm / 2,
      },
      {
        xMm: 0,
        yMm: page.heightMm / 2,
        widthMm: page.widthMm / 2,
        heightMm: page.heightMm / 2,
      },
      {
        xMm: page.widthMm / 2,
        yMm: page.heightMm / 2,
        widthMm: page.widthMm / 2,
        heightMm: page.heightMm / 2,
      },
    ];
  }
  return [{ xMm: 0, yMm: 0, widthMm: page.widthMm, heightMm: page.heightMm }];
}

function resolveStockFrameForSlot(stockSize, slot) {
  const stock = paperSizeMmForTemplate(stockSize);
  if (stock.widthMm <= slot.widthMm && stock.heightMm <= slot.heightMm) {
    return {
      widthMm: stock.widthMm,
      heightMm: stock.heightMm,
      rotated: false,
    };
  }
  if (stock.heightMm <= slot.widthMm && stock.widthMm <= slot.heightMm) {
    return {
      widthMm: stock.heightMm,
      heightMm: stock.widthMm,
      rotated: true,
    };
  }
  return null;
}

function validateTemplateSheetLayout({ stockSize, paperSize, nUpLayout }) {
  const slots = slotFramesForTemplate(paperSize, nUpLayout);
  const resolved = resolveStockFrameForSlot(stockSize, slots[0]);
  if (!resolved) {
    const error = new Error(
      `Stock size ${stockSize} does not fit on ${paperSize} with ${nUpLayout}-up layout.`,
    );
    error.statusCode = 400;
    throw error;
  }
  return {
    page: paperSizeMmForTemplate(paperSize),
    slots,
    stockFrame: resolved,
  };
}

function layoutFramesForTemplate({ stockSize, paperSize, nUpLayout }) {
  const layout = validateTemplateSheetLayout({ stockSize, paperSize, nUpLayout });
  return {
    page: layout.page,
    frames: layout.slots.map((slot) => ({
      xMm: slot.xMm + (slot.widthMm - layout.stockFrame.widthMm) / 2,
      yMm: slot.yMm + (slot.heightMm - layout.stockFrame.heightMm) / 2,
      widthMm: layout.stockFrame.widthMm,
      heightMm: layout.stockFrame.heightMm,
    })),
    rotatedStock: layout.stockFrame.rotated,
    slots: layout.slots,
  };
}

function templateValue(source, camelKey, snakeKey, fallback = null) {
  if (!source) {
    return fallback;
  }
  if (source[camelKey] != null) {
    return source[camelKey];
  }
  if (source[snakeKey] != null) {
    return source[snakeKey];
  }
  return fallback;
}

function templateNumberValue(source, camelKey, snakeKey, fallback = 0) {
  const value = Number(templateValue(source, camelKey, snakeKey, fallback));
  return Number.isFinite(value) ? value : fallback;
}

async function buildChallanTemplateSnapshot(templateRow) {
  if (!templateRow) {
    return null;
  }
  const dto = await rowToChallanTemplateDto(templateRow);
  return {
    id: dto.id,
    name: dto.name,
    partyType: dto.partyType,
    partyId: dto.partyId,
    challanType: dto.challanType,
    backgroundObjectKey: dto.backgroundObjectKey,
    canvasWidth: dto.canvasWidth,
    canvasHeight: dto.canvasHeight,
    rotationDegrees: dto.rotationDegrees,
    globalOffsetXmm: dto.globalOffsetXmm,
    globalOffsetYmm: dto.globalOffsetYmm,
    stockSize: dto.stockSize,
    paperSize: dto.paperSize,
    nUpLayout: dto.nUpLayout,
    mappings: dto.mappings,
    snapshottedAt: new Date().toISOString(),
  };
}

function templateBoxWidthMm(mapping, frameWidthMm) {
  return normalizeTemplateNumber(
    templateValue(
      mapping,
      'widthMm',
      'width_mm',
      templateValue(mapping, 'fieldType', 'field_type', 'DYNAMIC') === 'IMAGE'
        ? templateNumberValue(mapping, 'imageWidthMm', 'image_width_mm', 35)
        : templateNumberValue(mapping, 'maxWidthMm', 'max_width_mm', 80),
    ),
    frameWidthMm,
    { min: 2, max: frameWidthMm },
  );
}

function templateBoxHeightMm(mapping, frameHeightMm) {
  return normalizeTemplateNumber(
    templateValue(
      mapping,
      'heightMm',
      'height_mm',
      templateValue(mapping, 'fieldType', 'field_type', 'DYNAMIC') === 'IMAGE'
        ? templateNumberValue(mapping, 'imageHeightMm', 'image_height_mm', 20)
        : 12,
    ),
    frameHeightMm,
    { min: 2, max: frameHeightMm },
  );
}

function templateCoordinateMm(mapping, axis, frameSizeMm) {
  const mmKey = axis === 'x' ? 'xMm' : 'yMm';
  const mmSnakeKey = axis === 'x' ? 'x_mm' : 'y_mm';
  const percentKey = axis === 'x' ? 'xPercent' : 'yPercent';
  const percentSnakeKey = axis === 'x' ? 'x_percent' : 'y_percent';
  const mmValue = templateNumberValue(mapping, mmKey, mmSnakeKey, 0);
  const percentValue = templateNumberValue(mapping, percentKey, percentSnakeKey, 0);
  if (mmValue > 0 || percentValue === 0) {
    return normalizeTemplateNumber(mmValue, 0, { min: 0, max: frameSizeMm });
  }
  return normalizeTemplateNumber(percentValue, 0, { min: 0, max: 1 }) * frameSizeMm;
}

function parseTemplateTableColumns(tableFrame, mappings = []) {
  const allowed = new Set(['item_particulars', 'hsn', 'qty_pcs', 'weight', 'note']);
  const defaultXByField = {
    item_particulars: 0,
    hsn: 72,
    qty_pcs: 102,
    weight: 124,
    note: 0,
  };
  const normalizeColumn = (column, index) => {
    if (typeof column === 'string') {
      const fieldKey = column.trim();
      if (!allowed.has(fieldKey)) {
        return null;
      }
      return {
        fieldKey,
        xMm: Number(defaultXByField[fieldKey] ?? index * 30),
      };
    }
    if (!column || typeof column !== 'object') {
      return null;
    }
    const fieldKey = String(column.fieldKey || column.field_key || '').trim();
    if (!allowed.has(fieldKey)) {
      return null;
    }
    return {
      fieldKey,
      xMm: normalizeTemplateNumber(column.xMm ?? column.x_mm, defaultXByField[fieldKey] ?? 0, {
        min: 0,
        max: 420,
      }),
    };
  };
  const raw = String(templateValue(tableFrame, 'fieldValue', 'field_value', '') || '').trim();
  let columns = [];
  if (raw) {
    try {
      const decoded = JSON.parse(raw);
      columns = Array.isArray(decoded?.columns)
        ? decoded.columns.map(normalizeColumn).filter(Boolean)
        : [];
    } catch (_) {}
  }
  if (!columns.length) {
    columns = mappings
      .map((mapping, index) =>
        normalizeColumn(
          String(templateValue(mapping, 'fieldKey', 'field_key', '') || '').trim(),
          index,
        ),
      )
      .filter(Boolean);
  }
  if (!columns.some((column) => column.fieldKey === 'item_particulars')) {
    columns.unshift({ fieldKey: 'item_particulars', xMm: 0 });
  }
  const seen = new Set();
  return columns.filter((column) => {
    if (seen.has(column.fieldKey)) {
      return false;
    }
    seen.add(column.fieldKey);
    return true;
  });
}

function templateTablePrintNotes(tableFrame) {
  const raw = String(templateValue(tableFrame, 'fieldValue', 'field_value', '') || '').trim();
  if (!raw) {
    return false;
  }
  try {
    const decoded = JSON.parse(raw);
    return decoded?.printNotes === true;
  } catch (_) {
    return false;
  }
}

function ensureCoreChallanFieldMappings(mappings = []) {
  const aliasesByCanonicalField = {
    date: new Set(['date', 'challan_date', 'challanDate']),
    party_name: new Set([
      'party_name',
      'partyName',
      'client_name',
      'clientName',
      'customer_name',
      'customerName',
      'vendor_name',
      'vendorName',
    ]),
    gstin: new Set([
      'gstin',
      'gst_number',
      'gstNumber',
      'customer_gstin',
      'customerGstin',
      'vendor_gstin',
      'vendorGstin',
    ]),
  };
  const existingKeys = new Set(
    mappings.map((mapping) =>
      String(templateValue(mapping, 'fieldKey', 'field_key', '') || '').trim(),
    ),
  );
  const hasAny = (aliases) => [...aliases].some((alias) => existingKeys.has(alias));
  const fallbackMappings = [
    {
      fieldType: 'DYNAMIC',
      fieldKey: 'date',
      xPercent: 0.62,
      yPercent: 0.08,
      widthMm: 46,
      heightMm: 12,
      fontSize: 10,
      fontWeight: 'normal',
      alignment: 'left',
      textColor: 'black',
    },
    {
      fieldType: 'DYNAMIC',
      fieldKey: 'party_name',
      xPercent: 0.08,
      yPercent: 0.18,
      widthMm: 150,
      heightMm: 14,
      fontSize: 10,
      fontWeight: 'normal',
      alignment: 'left',
      textColor: 'black',
    },
    {
      fieldType: 'DYNAMIC',
      fieldKey: 'gstin',
      xPercent: 0.08,
      yPercent: 0.25,
      widthMm: 150,
      heightMm: 12,
      fontSize: 10,
      fontWeight: 'normal',
      alignment: 'left',
      textColor: 'black',
    },
  ].filter((mapping) => !hasAny(aliasesByCanonicalField[mapping.fieldKey]));
  return [...mappings, ...fallbackMappings];
}

function drawTableBlock({
  doc,
  mapping,
  pageItems,
  xMm,
  yMm,
  widthMm,
  tableHeightMm,
  rowPitchMm,
  minRows,
  fontName,
  fontSize,
  minFontSize,
  textColor,
  letterSpacing,
  columns,
  displayId,
  printNotes,
}) {
  const normalizedColumns = (columns.length
    ? columns
    : [{ fieldKey: 'item_particulars', xMm: 0 }])
    .map((column) => ({
      fieldKey: column.fieldKey,
      xMm: normalizeTemplateNumber(column.xMm, 0, { min: 0, max: widthMm }),
    }));
  const sortedColumns = [...normalizedColumns].sort((left, right) => left.xMm - right.xMm);
  const noteColumn = normalizedColumns.find((column) => column.fieldKey === 'note');
  const printableColumns = normalizedColumns.filter((column) => column.fieldKey !== 'note');
  const rowHeight = mmToPdfPoints(rowPitchMm);
  const rowCount = Math.max(pageItems.length, minRows);
  const fitFontSize = Math.max(
    minFontSize,
    Math.min(fontSize, Math.max(minFontSize, rowPitchMm * 2.2)),
  );
  doc.font(fontName).fontSize(fitFontSize).fillColor(textColor);
  for (let rowIndex = 0; rowIndex < rowCount; rowIndex += 1) {
    const item = pageItems[rowIndex];
    const currentY = yMm + rowIndex * rowPitchMm;
    for (const column of printableColumns) {
      const fieldKey = column.fieldKey;
      const columnIndex = sortedColumns.findIndex((entry) => entry.fieldKey === fieldKey);
      const nextColumn = sortedColumns
        .slice(columnIndex + 1)
        .find((entry) => entry.fieldKey !== 'note');
      const columnWidthMm = Math.max(
        6,
        Math.min(
          widthMm - column.xMm,
          (nextColumn ? nextColumn.xMm : widthMm) - column.xMm,
        ),
      );
      const value = item
        ? truncateTemplateText(
            itemTableValueForField(fieldKey, item),
            templateNumberValue(mapping, 'maxChars', 'max_chars', 0),
          )
        : '';
      const align = fieldKey === 'item_particulars' ? 'left' : 'center';
      doc.text(
        value,
        mmToPdfPoints(xMm + column.xMm),
        mmToPdfPoints(currentY),
        {
          width: mmToPdfPoints(columnWidthMm),
          height: rowHeight,
          align,
          characterSpacing: letterSpacing,
          lineBreak: true,
        },
      );
    }
    const note = item ? String(item.note || '').trim() : '';
    if (printNotes && noteColumn && note) {
      const noteWidthMm = Math.max(12, widthMm - noteColumn.xMm);
      doc
        .font('Helvetica-Oblique')
        .fontSize(7)
        .fillColor('#4B5563')
        .text(
          truncateTemplateText(note, templateNumberValue(mapping, 'maxChars', 'max_chars', 0)),
          mmToPdfPoints(xMm + noteColumn.xMm),
          mmToPdfPoints(currentY + 4),
          {
            width: mmToPdfPoints(noteWidthMm),
            height: rowHeight / 2,
            align: 'left',
            characterSpacing: letterSpacing,
            lineBreak: true,
          },
        )
        .font(fontName)
        .fontSize(fitFontSize)
        .fillColor(textColor);
    }
  }
  if (displayId) {
    const idY = yMm + Math.min(tableHeightMm, rowCount * rowPitchMm + 2);
    doc
      .font('Helvetica')
      .fontSize(6)
      .fillColor('#6B7280')
      .text(displayId, mmToPdfPoints(xMm + 5), mmToPdfPoints(idY), {
        width: mmToPdfPoints(Math.max(20, widthMm - 5)),
        lineBreak: false,
      })
      .font(fontName)
      .fontSize(fitFontSize)
      .fillColor(textColor);
  }
}

function buildTemplateTestChallanDto(itemCount = 3) {
  const normalizedItemCount = Math.max(1, Math.min(200, Math.round(Number(itemCount) || 3)));
  const sampleCatalog = [
    {
      particulars: 'SAMPLE PRODUCT DESCRIPTION 101',
      hsnCode: '1234',
      quantityPcs: '9,999',
      weight: '120.50',
      note: 'Packed in export-grade bundles',
    },
    {
      particulars: 'SAMPLE PRODUCT DESCRIPTION 202 WITH LONGER WRAP TEXT',
      hsnCode: '5678',
      quantityPcs: '240',
      weight: '18.25',
      note: 'Check shade before dispatch',
    },
    {
      particulars: 'SAMPLE PRODUCT DESCRIPTION 303',
      hsnCode: '9101',
      quantityPcs: '75',
      weight: '8.00',
      note: 'Short supply accepted by party',
    },
    {
      particulars: 'SAMPLE PRODUCT DESCRIPTION 404 EXTRA LONG TEXT FOR ROW FIT CHECKING',
      hsnCode: '1112',
      quantityPcs: '1,250',
      weight: '42.75',
      note: 'Handle carefully',
    },
  ];
  const items = Array.from({ length: normalizedItemCount }, (_, index) => {
    const sample = sampleCatalog[index % sampleCatalog.length];
    return {
      particulars:
        normalizedItemCount <= sampleCatalog.length
          ? sample.particulars
          : `${sample.particulars} #${String(index + 1).padStart(2, '0')}`,
      hsn_code: sample.hsnCode,
      quantity_pcs: sample.quantityPcs,
      weight: sample.weight,
      note: sample.note,
    };
  });
  return {
    id: 0,
    type: 'delivery',
    order_id: null,
    order_ids: [],
    order_no: 'SAMPLE-ORDER-001',
    order_nos: ['SAMPLE-ORDER-001'],
    client_id: 0,
    challan_no: 'DC-TEST-0001',
    display_id: 'REF: 00000',
    date: 'DD/MM/YYYY',
    location: '',
    customer_name: 'John Doe',
    customer_gstin: '27ABCDE1234F1Z5',
    vendor_id: null,
    vendor_name: '',
    vendor_gstin: '',
    source_reference: 'TEST-PRINT',
    company_profile_snapshot: null,
    notes: 'Sample preview for block alignment.',
    status: 'draft',
    created_by: null,
    updated_by: null,
    created_at: null,
    updated_at: null,
    items,
  };
}

async function generateChallanTemplatePdf({
  challanRow,
  templateRow,
  templateSnapshot = null,
  mode = 'digital',
  challanDtoOverride = null,
}) {
  const normalizedMode = String(mode || 'digital').trim().toLowerCase() === 'overprint'
    ? 'overprint'
    : 'digital';
  const challanDto = challanDtoOverride || await rowToDeliveryChallanDto(challanRow);
  const templateSource = templateSnapshot || templateRow;
  const rawMappings = templateSnapshot
    ? (Array.isArray(templateSnapshot.mappings) ? templateSnapshot.mappings : [])
    : await all(
        `
        SELECT *
        FROM challan_template_mappings
        WHERE template_id = ?
        ORDER BY id ASC
        `,
        [templateRow.id],
      );
  const mappings = ensureCoreChallanFieldMappings(rawMappings);
  const paperSize = templateValue(templateSource, 'paperSize', 'paper_size', 'A4');
  const stockSize = templateValue(
    templateSource,
    'stockSize',
    'stock_size',
    paperSize,
  );
  const nUpLayout = normalizeTemplateNUpLayout(
    templateValue(templateSource, 'nUpLayout', 'n_up_layout', 1),
  );
  const layout = layoutFramesForTemplate({ stockSize, paperSize, nUpLayout });
  const pageSize = layout.page;
  const frames = layout.frames;
  const pageWidth = mmToPdfPoints(pageSize.widthMm);
  const pageHeight = mmToPdfPoints(pageSize.heightMm);
  const doc = new PDFDocument({
    size: [pageWidth, pageHeight],
    margin: 0,
    autoFirstPage: false,
  });
  const chunks = [];
  doc.on('data', (chunk) => chunks.push(chunk));
  const finished = new Promise((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });

  const fields = challanTemplateScalarFields(challanDto);
  const items = Array.isArray(challanDto.items) ? challanDto.items : [];
  const displayId = `REF: ${String(challanDto.id || challanRow?.id || 0).padStart(5, '0')}`;
  const tableFrame = mappings.find(
    (mapping) => String(templateValue(mapping, 'fieldKey', 'field_key', '')) === 'item_particulars',
  );
  const tableFields = new Set(['item_particulars', 'hsn', 'qty_pcs', 'weight', 'note']);
  const tableColumns = parseTemplateTableColumns(tableFrame, mappings);
  const tablePrintNotes = templateTablePrintNotes(tableFrame);
  const frameRowPitchMm = templateNumberValue(tableFrame, 'rowHeightMm', 'row_height_mm', 6);
  const frameTableHeightMm = templateNumberValue(tableFrame, 'tableHeightMm', 'table_height_mm', 60);
  const frameMinRows = Math.max(
    0,
    Math.round(templateNumberValue(tableFrame, 'minRows', 'min_rows', 0)),
  );
  const explicitMaxRows = Math.max(
    0,
    Math.round(templateNumberValue(tableFrame, 'maxRows', 'max_rows', 0)),
  );
  const computedRows = frameRowPitchMm > 0
    ? Math.max(1, Math.floor(frameTableHeightMm / frameRowPitchMm))
    : Math.max(1, explicitMaxRows || items.length || 1);
  const rowsPerPage = explicitMaxRows > 0 ? Math.min(explicitMaxRows, computedRows) : computedRows;
  const pageCount = Math.max(1, Math.ceil(Math.max(items.length, frameMinRows, 1) / rowsPerPage));

  const drawCutGuides = () => {
    if (layout.slots.length <= 1) {
      return;
    }
    doc.save();
    doc.dash(4, { space: 4 });
    doc.lineWidth(0.7).strokeColor('#8B5CF6').opacity(0.35);
    if (nUpLayout === 2) {
      const y = mmToPdfPoints(layout.slots[1].yMm);
      doc.moveTo(0, y).lineTo(pageWidth, y).stroke();
    } else if (nUpLayout === 4) {
      const x = mmToPdfPoints(layout.slots[1].xMm);
      const y = mmToPdfPoints(layout.slots[2].yMm);
      doc.moveTo(x, 0).lineTo(x, pageHeight).stroke();
      doc.moveTo(0, y).lineTo(pageWidth, y).stroke();
    }
    doc.undash();
    doc.restore();
  };

  const drawSingleChallan = async (pageItems, frame) => {
    const backgroundKey = templateValue(
      templateSource,
      'backgroundObjectKey',
      'background_object_key',
      '',
    );
    if (normalizedMode === 'digital' && backgroundKey) {
      try {
        const background = await readS3ObjectBuffer(backgroundKey);
        doc.save();
        doc.opacity(0.3);
        doc.image(background, mmToPdfPoints(frame.xMm), mmToPdfPoints(frame.yMm), {
          width: mmToPdfPoints(frame.widthMm),
          height: mmToPdfPoints(frame.heightMm),
        });
        doc.restore();
      } catch (_) {}
    }

    for (const mapping of mappings) {
      const fieldKey = String(templateValue(mapping, 'fieldKey', 'field_key', ''));
      const fieldType = String(templateValue(mapping, 'fieldType', 'field_type', 'DYNAMIC')).toUpperCase();
      const xMm =
        frame.xMm +
        templateCoordinateMm(mapping, 'x', frame.widthMm) +
        templateNumberValue(templateSource, 'globalOffsetXmm', 'global_offset_x_mm', 0);
      const yMm =
        frame.yMm +
        templateCoordinateMm(mapping, 'y', frame.heightMm) +
        templateNumberValue(templateSource, 'globalOffsetYmm', 'global_offset_y_mm', 0);
      const widthMm = templateBoxWidthMm(mapping, frame.widthMm);
      const heightMm = templateBoxHeightMm(mapping, frame.heightMm);
      if (fieldKey === 'item_particulars' || fieldType === 'TABLE') {
        const fontSize = templateNumberValue(mapping, 'fontSize', 'font_size', 10);
        const minFontSize = templateNumberValue(mapping, 'minFontSize', 'min_font_size', 6);
        const fontName = String(templateValue(mapping, 'fontWeight', 'font_weight', '')).toLowerCase() === 'bold'
          ? 'Helvetica-Bold'
          : 'Helvetica';
        drawTableBlock({
          doc,
          mapping,
          pageItems,
          xMm,
          yMm,
          widthMm,
          tableHeightMm: templateNumberValue(mapping, 'tableHeightMm', 'table_height_mm', frameTableHeightMm),
          rowPitchMm: templateNumberValue(mapping, 'rowHeightMm', 'row_height_mm', frameRowPitchMm),
          minRows: frameMinRows,
          fontName,
          fontSize,
          minFontSize,
          textColor: pdfColorForTemplate(templateValue(mapping, 'textColor', 'text_color', 'black')),
          letterSpacing: templateNumberValue(mapping, 'letterSpacing', 'letter_spacing', 0),
          columns: tableColumns,
          displayId,
          printNotes: tablePrintNotes,
        });
        continue;
      }
      if (tableFields.has(fieldKey)) {
        continue;
      }
      if (fieldType === 'IMAGE') {
        const objectKey = String(templateValue(mapping, 'assetObjectKey', 'asset_object_key', '') || '');
        if (!objectKey) {
          continue;
        }
        try {
          const asset = await readS3ObjectBuffer(objectKey);
          doc.image(asset, mmToPdfPoints(xMm), mmToPdfPoints(yMm), {
            width: mmToPdfPoints(widthMm),
            height: mmToPdfPoints(heightMm),
          });
        } catch (_) {}
        continue;
      }

      const fontSize = templateNumberValue(mapping, 'fontSize', 'font_size', 10);
      const minFontSize = templateNumberValue(mapping, 'minFontSize', 'min_font_size', 6);
      const fontName = String(templateValue(mapping, 'fontWeight', 'font_weight', '')).toLowerCase() === 'bold'
        ? 'Helvetica-Bold'
        : 'Helvetica';
      const alignment = templateValue(mapping, 'alignment', 'alignment', 'left');
      const align = ['left', 'center', 'right'].includes(alignment) ? alignment : 'left';
      const rowPitchMm = templateNumberValue(mapping, 'rowHeightMm', 'row_height_mm', frameRowPitchMm);
      const fitFontSize = tableFields.has(fieldKey)
        ? Math.max(minFontSize, Math.min(fontSize, Math.max(minFontSize, rowPitchMm * 2.2)))
        : fontSize;
      const textOptions = {
        width: mmToPdfPoints(widthMm),
        height: mmToPdfPoints(heightMm),
        align,
        characterSpacing: templateNumberValue(mapping, 'letterSpacing', 'letter_spacing', 0),
        lineBreak: true,
      };
      doc.font(fontName).fontSize(fitFontSize).fillColor(
        pdfColorForTemplate(templateValue(mapping, 'textColor', 'text_color', 'black')),
      );
      const text = fieldType === 'STATIC'
        ? templateValue(mapping, 'fieldValue', 'field_value', '') || ''
        : fields[fieldKey] || '';
      doc.text(
        truncateTemplateText(text, templateNumberValue(mapping, 'maxChars', 'max_chars', 0)),
        mmToPdfPoints(xMm),
        mmToPdfPoints(yMm),
        textOptions,
      );
    }
  };

  for (let pageIndex = 0; pageIndex < pageCount; pageIndex += 1) {
    doc.addPage({ size: [pageWidth, pageHeight], margin: 0 });
    const pageItems = items.slice(pageIndex * rowsPerPage, pageIndex * rowsPerPage + rowsPerPage);
    for (const frame of frames) {
      await drawSingleChallan(pageItems, frame);
    }
    drawCutGuides();
  }
  doc.end();
  return finished;
}

async function listDeliveryChallans({
  status,
  type,
  search,
  dateFrom,
  dateTo,
  orderId,
  vendorId,
  itemId,
  variationLeafNodeId,
} = {}) {
  const where = [];
  const params = [];
  const normalizedType = type ? normalizeChallanType(type, '') : '';
  if (normalizedType) {
    where.push('dc.type = ?');
    params.push(normalizedType);
  }
  // Item filter — only challans whose lines reference this item. Combines with
  // every other filter via AND.
  const normalizedItemId = Number(itemId || 0);
  const normalizedVariationLeafNodeId = Number(variationLeafNodeId || 0);
  if (
    (Number.isInteger(normalizedItemId) && normalizedItemId > 0) ||
    (Number.isInteger(normalizedVariationLeafNodeId) &&
      normalizedVariationLeafNodeId > 0)
  ) {
    const lineFilters = [];
    if (Number.isInteger(normalizedItemId) && normalizedItemId > 0) {
      lineFilters.push('dci_item.item_id = ?');
      params.push(normalizedItemId);
    }
    if (
      Number.isInteger(normalizedVariationLeafNodeId) &&
      normalizedVariationLeafNodeId > 0
    ) {
      lineFilters.push('dci_item.variation_leaf_node_id = ?');
      params.push(normalizedVariationLeafNodeId);
    }
    where.push(`
      EXISTS (
        SELECT 1
        FROM delivery_challan_items dci_item
        WHERE dci_item.challan_id = dc.id
          AND ${lineFilters.join(' AND ')}
      )
    `);
  }
  const normalizedOrderId = Number(orderId || 0);
  if (Number.isInteger(normalizedOrderId) && normalizedOrderId > 0) {
    where.push(`
      (
        dc.order_id = ?
        OR EXISTS (
          SELECT 1
          FROM delivery_challan_order_items dco
          WHERE dco.challan_id = dc.id
            AND dco.order_id = ?
        )
      )
    `);
    params.push(normalizedOrderId);
    params.push(normalizedOrderId);
  }
  const normalizedVendorId = Number(vendorId || 0);
  if (Number.isInteger(normalizedVendorId) && normalizedVendorId > 0) {
    where.push('dc.vendor_id = ?');
    params.push(normalizedVendorId);
  }
  if (status && DELIVERY_CHALLAN_STATUSES.has(status)) {
    where.push('dc.status = ?');
    params.push(status);
  }
  const normalizedSearch = String(search || '').trim().toLowerCase();
  if (normalizedSearch) {
    where.push(`
      (
        LOWER(dc.challan_no) LIKE ?
        OR LOWER(dc.order_no) LIKE ?
        OR LOWER(dc.customer_name) LIKE ?
        OR LOWER(dc.vendor_name) LIKE ?
        OR LOWER(dc.source_reference) LIKE ?
      )
    `);
    params.push(
      `%${normalizedSearch}%`,
      `%${normalizedSearch}%`,
      `%${normalizedSearch}%`,
      `%${normalizedSearch}%`,
      `%${normalizedSearch}%`,
    );
  }
  if (dateFrom) {
    where.push('date(dc.date) >= date(?)');
    params.push(String(dateFrom).slice(0, 10));
  }
  if (dateTo) {
    where.push('date(dc.date) <= date(?)');
    params.push(String(dateTo).slice(0, 10));
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const rows = await all(
    `
    SELECT dc.*, COUNT(dci.id) AS items_count
    FROM delivery_challans dc
    LEFT JOIN delivery_challan_items dci ON dci.challan_id = dc.id
    ${whereSql}
    GROUP BY dc.id
    ORDER BY date(dc.date) DESC, dc.id DESC
    `,
    params,
  );
  return Promise.all(rows.map((row) => rowToDeliveryChallanDto(row)));
}

async function getOrderForDeliveryChallan(orderId) {
  const order = await get(
    `
    SELECT o.*, c.gst_number AS client_gstin
    FROM order_items o
    LEFT JOIN clients c ON c.id = o.client_id
    WHERE o.id = ?
    `,
    [Number(orderId)],
  );
  if (!order) {
    const error = new Error('Order not found.');
    error.statusCode = 404;
    throw error;
  }
  return order;
}

function normalizeDeliveryChallanOrderIds(input = {}, existing = null) {
  const candidates = Array.isArray(input.orderIds)
    ? input.orderIds
    : Array.isArray(input.order_ids)
    ? input.order_ids
    : [];
  const normalized = [
    ...new Set(
      candidates
        .map((value) => Number(value || 0))
        .filter((value) => Number.isInteger(value) && value > 0),
    ),
  ];
  const legacyOrderId = Number(
    input.orderId ?? input.order_id ?? existing?.order_id ?? 0,
  );
  if (normalized.length === 0 && Number.isInteger(legacyOrderId) && legacyOrderId > 0) {
    return [legacyOrderId];
  }
  return normalized;
}

async function getOrdersForDeliveryChallan(orderIds) {
  const orders = await getOrderRowsByIds(orderIds);
  if (orders.length !== orderIds.length) {
    const error = new Error('One or more selected orders could not be found.');
    error.statusCode = 404;
    throw error;
  }
  const uniqueClientIds = [...new Set(orders.map((order) => Number(order.client_id || 0)))];
  if (uniqueClientIds.length !== 1) {
    const error = new Error('Delivery challans can only include orders from the same client.');
    error.statusCode = 400;
    throw error;
  }
  return orders;
}

function orderItemSnapshotFromOrder(order) {
  const variationLabel = String(order.variation_path_label || '').trim();
  const itemName = String(order.item_name || '').trim();
  return {
    orderItemId: Number(order.id),
    itemId: order.item_id || null,
    variationLeafNodeId: Number(order.variation_leaf_node_id || 0),
    variationPathLabel: variationLabel,
    particulars: variationLabel ? `${itemName} - ${variationLabel}` : itemName,
    hsnCode: '',
  };
}

async function getVendorForChallan(vendorId) {
  const vendor = await getVendorRowById(Number(vendorId));
  if (!vendor || vendor.is_archived) {
    const error = new Error('Select an active vendor before saving reception challan.');
    error.statusCode = 400;
    throw error;
  }
  return vendor;
}

async function getItemSelectionSnapshot(itemId, variationLeafNodeId) {
  const selection = await resolveOrderVariationSelection({
    itemId,
    variationLeafNodeId,
    variationPathNodeIds: [],
    status: 'notStarted',
  });
  return {
    item: selection.item,
    itemId: selection.item.id,
    variationLeafNodeId: selection.variationLeafNodeId,
    variationPathLabel: selection.variationPathLabel,
    variationPathNodeIds: selection.variationPathNodeIds || [],
    particulars: selection.variationPathLabel
      ? `${selection.item.display_name || selection.item.name} - ${selection.variationPathLabel}`
      : (selection.item.display_name || selection.item.name || ''),
  };
}

function rowToProductionRunDto(row) {
  if (!row) {
    return null;
  }
  return {
    id: Number(row.id || 0),
    runCode: row.run_code || '',
    status: row.status || '',
    completedAt: row.completed_at || null,
    itemId: Number(row.item_id || 0),
    itemName: row.item_name || '',
    variationLeafNodeId: Number(row.variation_leaf_node_id || 0),
    variationPathLabel: row.variation_path_label || '',
    outputQuantity: Number(row.output_quantity || 0),
    uom: row.uom || 'pcs',
    location: row.location || '',
  };
}

async function listCompletedProductionRuns({ search = '', limit = 25 } = {}) {
  const normalizedSearch = String(search || '').trim().toLowerCase();
  const params = [];
  let searchSql = '';
  if (normalizedSearch) {
    searchSql = `
      AND (
        LOWER(pr.run_code) LIKE ?
        OR LOWER(i.display_name) LIKE ?
        OR LOWER(i.name) LIKE ?
        OR LOWER(pr.variation_path_label) LIKE ?
      )
    `;
    params.push(
      `%${normalizedSearch}%`,
      `%${normalizedSearch}%`,
      `%${normalizedSearch}%`,
      `%${normalizedSearch}%`,
    );
  }
  params.push(Math.min(Math.max(Number(limit || 25), 1), 100));
  const rows = await all(
    `
    SELECT pr.*, COALESCE(i.display_name, i.name, '') AS item_name
    FROM production_runs pr
    INNER JOIN items i ON i.id = pr.item_id
    WHERE pr.status = 'completed'
      AND COALESCE(i.is_archived, 0) = 0
      ${searchSql}
    ORDER BY datetime(pr.completed_at) DESC, pr.id DESC
    LIMIT ?
    `,
    params,
  );
  return rows.map(rowToProductionRunDto);
}

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

async function getProductionRunRowById(id) {
  return get(
    `
    SELECT pr.*, COALESCE(i.display_name, i.name, '') AS item_name
    FROM production_runs pr
    INNER JOIN items i ON i.id = pr.item_id
    WHERE pr.id = ?
    `,
    [Number(id || 0)],
  );
}

async function validateProductionRunForChallanLine(runId, item) {
  if (!runId) {
    return null;
  }
  const run = await getProductionRunRowById(runId);
  if (!run || run.status !== 'completed') {
    const error = new Error('Selected production run is not completed or no longer exists.');
    error.statusCode = 400;
    throw error;
  }
  if (Number(run.item_id || 0) !== Number(item.itemId || 0)) {
    const error = new Error('Selected production run item does not match the challan line item.');
    error.statusCode = 400;
    throw error;
  }
  if (Number(run.variation_leaf_node_id || 0) !== Number(item.variationLeafNodeId || 0)) {
    const error = new Error('Selected production run variation does not match the challan line variation.');
    error.statusCode = 400;
    throw error;
  }
  return run;
}

async function findMaterialByItemSelection(itemId, variationLeafNodeId, customVariationValues = null) {
  let customJson = null;
  if (customVariationValues && Object.keys(customVariationValues).length > 0) {
    const ordered = {};
    Object.keys(customVariationValues).sort().forEach(k => ordered[k] = customVariationValues[k]);
    customJson = JSON.stringify(ordered);
  }

  if (Number(variationLeafNodeId || 0) > 0 || customJson) {
    const exact = await get(
      `
      SELECT *
      FROM materials
      WHERE linked_item_id = ?
        AND COALESCE(linked_variation_leaf_node_id, 0) = ?
        AND COALESCE(custom_variation_values_json, '') = COALESCE(?, '')
      ORDER BY id ASC
      LIMIT 1
      `,
      [itemId, Number(variationLeafNodeId || 0), customJson],
    );
    if (exact) {
      return exact;
    }
  }
  const base = await get(
    `
    SELECT *
    FROM materials
    WHERE linked_item_id = ?
      AND COALESCE(linked_variation_leaf_node_id, 0) = 0
      AND COALESCE(custom_variation_values_json, '') = ''
    ORDER BY id ASC
    LIMIT 1
    `,
    [itemId],
  );
  if (base) {
    return base;
  }
  return get(
    `
    SELECT *
    FROM materials
    WHERE linked_item_id = ?
    ORDER BY id ASC
    LIMIT 1
    `,
    [itemId],
  );
}

async function generateBarcodeFromItemSelection(itemId, customVariationValues) {
  if (!customVariationValues || Object.keys(customVariationValues).length === 0) return null;
  const codes = [];
  for (const [propName, valName] of Object.entries(customVariationValues)) {
    const row = await get(`
      SELECT v.code, p.position
      FROM item_variation_nodes v
      JOIN item_variation_nodes p ON v.parent_node_id = p.id
      WHERE v.item_id = ? AND p.name = ? AND (v.name = ? OR v.display_name = ?)
    `, [itemId, propName, valName, valName]);
    if (row && row.code) {
      codes.push({ code: row.code, position: row.position });
    }
  }
  if (codes.length === 0) return null;
  codes.sort((a, b) => a.position - b.position);
  return codes.map(c => c.code).join('-');
}

function generateStandaloneMaterialBarcode() {
  return `MAT-${Date.now()}-${Math.floor(Math.random() * 100000)
    .toString()
    .padStart(5, '0')}`;
}

async function ensureMaterialForItemSelection({ itemId, variationLeafNodeId = 0, customVariationValues = null, actor = null }) {
  const existing = await findMaterialByItemSelection(itemId, variationLeafNodeId, customVariationValues);
  if (existing) {
    return existing;
  }
  const snapshot = await getItemSelectionSnapshot(itemId, variationLeafNodeId);
  const unit = snapshot.item.unit_id ? await getUnitRowById(snapshot.item.unit_id) : null;
  const now = new Date().toISOString();
  
  // Generate barcode from variation codes if possible
  let barcode = await generateBarcodeFromItemSelection(itemId, customVariationValues);
  if (!barcode) {
    barcode = generateStandaloneMaterialBarcode();
  } else {
    // Ensure uniqueness across the system by checking if it exists
    const existingBarcode = await getMaterialRowByBarcode(barcode);
    if (existingBarcode) {
      // If it exists but wasn't caught by findMaterialByItemSelection, it might be a collision.
      // We'll append a short random string to guarantee uniqueness.
      barcode = `${barcode}-${Math.floor(Math.random() * 1000).toString().padStart(3, '0')}`;
    }
  }

  // Custom variation values (e.g. {color: "Copper"}) distinguish materials that
  // share an item + leaf node. Persist them (canonical key order, matching
  // findMaterialByItemSelection) and fold the values into the name so each
  // variation gets its own card instead of piling onto the base material.
  let customJson = null;
  let name = snapshot.particulars || snapshot.item.display_name || snapshot.item.name;
  if (customVariationValues && Object.keys(customVariationValues).length > 0) {
    const ordered = {};
    Object.keys(customVariationValues).sort().forEach((k) => { ordered[k] = customVariationValues[k]; });
    customJson = JSON.stringify(ordered);
    const suffix = Object.values(ordered).join(' - ');
    if (suffix && !name.includes(suffix)) {
      name = `${name} - ${suffix}`;
    }
  }

  await run(
    `
    INSERT INTO materials (
      barcode, name, type, grade, thickness, supplier, location, unit_id, unit, notes,
      group_mode, inheritance_enabled, created_at, kind, parent_barcode, number_of_children,
      linked_child_barcodes, scan_count, linked_group_id, linked_item_id, linked_variation_leaf_node_id,
      custom_variation_values_json, display_stock, created_by, workflow_status, material_class, inventory_state, procurement_state,
      traceability_mode, on_hand_qty, reserved_qty, available_to_promise_qty, incoming_qty,
      linked_order_count, linked_pipeline_count, pending_alert_count, updated_at, last_scanned_at
    ) VALUES (?, ?, 'Item', '', '', '', '', ?, ?, '', NULL, 0, ?, 'standalone', NULL, 0, '[]', 0, NULL, ?, ?, ?, ?, ?, 'notStarted', 'finished_good', 'available', 'not_ordered', 'bulk', 0, 0, 0, 0, 0, 0, 0, ?, NULL)
    `,
    [
      barcode,
      name,
      unit?.id || snapshot.item.unit_id || null,
      unit?.symbol || '',
      now,
      snapshot.item.id,
      snapshot.variationLeafNodeId > 0 ? snapshot.variationLeafNodeId : null,
      customJson,
      unit?.symbol ? `0 ${unit.symbol}` : '0',
      actor?.name || actor || 'System',
      now,
    ],
  );
  return getMaterialRowByBarcode(barcode);
}

async function logDeliveryChallanActivity(challanId, activityType, actor, details = {}) {
  await run(
    `
    INSERT INTO delivery_challan_activity_log (
      challan_id, activity_type, actor_user_id, actor_name, actor_role, details_json, created_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?)
    `,
    [
      challanId,
      activityType,
      actor?.id || null,
      actor?.name || 'System',
      actor?.role || 'system',
      JSON.stringify(details || {}),
      new Date().toISOString(),
    ],
  );
}

function assertCanChangeIssuedChallanNo(req, existing, nextChallanNo) {
  if (existing.status !== 'issued' || existing.challan_no === nextChallanNo) {
    return;
  }
  if (req.user?.role === 'super_admin' || req.user?.role === 'admin') {
    return;
  }
  const error = new Error('Issued challan numbers can only be changed by an admin.');
  error.statusCode = 403;
  throw error;
}

async function saveDeliveryChallan(input = {}, actor = null, req = null) {
  const id = Number(input.id || 0);
  const existing = id ? await getDeliveryChallanRowById(id) : null;
  if (id && !existing) {
    const error = new Error('Delivery challan not found.');
    error.statusCode = 404;
    throw error;
  }
  if (existing && existing.status !== 'draft') {
    const error = new Error('Only draft challans can be edited.');
    error.statusCode = 400;
    throw error;
  }

  const challanType = normalizeChallanType(
    input.type ?? input.challanType ?? input.challan_type ?? existing?.type ?? 'delivery',
  );
  const orderIds = challanType === 'delivery'
    ? normalizeDeliveryChallanOrderIds(input, existing)
    : [];
  const vendorId = Number(input.vendorId ?? input.vendor_id ?? existing?.vendor_id ?? 0);
  const maintainStocksInput = input.maintainStocks ?? input.maintain_stocks;
  const maintainStocks = maintainStocksInput === undefined
    ? Number(existing?.maintain_stocks ?? 1) !== 0
    : !(
      maintainStocksInput === false ||
      Number(maintainStocksInput) === 0
    );
  const location = String(input.location ?? existing?.location ?? '').trim() || 'MAIN';
  const sourceReference = String(
    input.sourceReference ?? input.source_reference ?? existing?.source_reference ?? '',
  ).trim();
  let orders = [];
  let firstOrder = null;
  let orderSnapshotsById = new Map();
  let vendor = null;
  if (challanType === 'delivery') {
    if (maintainStocks && orderIds.length == 0) {
      const error = new Error('Select at least one order before saving delivery challan.');
      error.statusCode = 400;
      throw error;
    }
    if (orderIds.length > 0) {
      orders = await getOrdersForDeliveryChallan(orderIds);
      firstOrder = orders[0] || null;
      orderSnapshotsById = new Map(
        orders.map((order) => [Number(order.id), orderItemSnapshotFromOrder(order)]),
      );
    }
  } else if (challanType === 'internal') {
    // Internal movements (production consumption / transfers) belong to no
    // external party, so neither an order nor a vendor is required. A vendor
    // may still be linked optionally if the caller supplies one.
    if (Number.isInteger(vendorId) && vendorId > 0) {
      vendor = await getVendorForChallan(vendorId);
    }
  } else {
    if (maintainStocks && (!Number.isInteger(vendorId) || vendorId <= 0)) {
      const error = new Error('Select a vendor before saving reception challan.');
      error.statusCode = 400;
      throw error;
    }
    if (Number.isInteger(vendorId) && vendorId > 0) {
      vendor = await getVendorForChallan(vendorId);
    }
  }
  const requestedChallanNo = String(
    input.challanNo ?? input.challan_no ?? '',
  ).trim();
  const challanNo = requestedChallanNo || await generateChallanNumber(challanType);
  const duplicate = await get(
    'SELECT id FROM delivery_challans WHERE LOWER(TRIM(challan_no)) = LOWER(TRIM(?)) AND id != ?',
    [challanNo, id || 0],
  );
  if (duplicate) {
    const error = new Error(`Challan number [${challanNo}] is already in use.`);
    error.statusCode = 409;
    throw error;
  }

  const date = normalizeChallanDate(input.date ?? existing?.date);
  const inputPurpose = String(
    input.purpose ?? input.challanPurpose ?? input.challan_purpose ?? existing?.purpose ?? 'trading',
  ).trim();
  const purpose = ['trading', 'manufacturing', 'jobWork'].includes(inputPurpose)
    ? inputPurpose
    : (inputPurpose === 'job_work' ? 'jobWork' : 'trading');
  // Free-text purpose for internal challans (kept separate from the enum
  // `purpose` above so delivery/reception behaviour is untouched).
  const internalPurpose = String(
    input.internalPurpose ?? input.internal_purpose ?? existing?.internal_purpose ?? '',
  ).trim();
  const customerName = challanType === 'delivery'
    ? (maintainStocks
      ? String(firstOrder?.client_name || '').trim()
      : String(input.customerName ?? input.customer_name ?? existing?.customer_name ?? '').trim())
    : '';
  const customerGstin = challanType === 'delivery'
    ? (maintainStocks
      ? String(firstOrder?.client_gstin || '').trim()
      : String(input.customerGstin ?? input.customer_gstin ?? existing?.customer_gstin ?? '').trim())
    : '';
  const materialOwnerClientId = challanType === 'reception'
    ? Number(
      input.materialOwnerClientId ??
      input.material_owner_client_id ??
      existing?.material_owner_client_id ??
      0,
    )
    : 0;
  const materialOwnerClientName = challanType === 'reception'
    ? String(
      input.materialOwnerClientName ??
      input.material_owner_client_name ??
      existing?.material_owner_client_name ??
      '',
    ).trim()
    : '';
  const materialOwnerGstin = challanType === 'reception'
    ? String(
      input.materialOwnerGstin ??
      input.material_owner_gstin ??
      existing?.material_owner_gstin ??
      '',
    ).trim()
    : '';
  const vendorName = challanType === 'reception'
    ? (maintainStocks
      ? String(vendor?.name || '').trim()
      : String(input.vendorName ?? input.vendor_name ?? input.customerName ?? input.customer_name ?? existing?.vendor_name ?? '').trim())
    : '';
  const vendorGstin = challanType === 'reception'
    ? (maintainStocks
      ? String(vendor?.gst_number || '').trim()
      : String(input.vendorGstin ?? input.vendor_gstin ?? input.customerGstin ?? input.customer_gstin ?? existing?.vendor_gstin ?? '').trim())
    : '';
  const orderNo = challanType === 'delivery'
    ? [...new Set(orders.map((order) => String(order.order_no || '').trim()).filter(Boolean))].join(', ')
    : '';
  const notes = String(input.notes ?? existing?.notes ?? '').trim();
  const persistedOrderId = challanType === 'delivery' && maintainStocks ? (orderIds[0] || null) : null;
  const persistedVendorId = challanType === 'reception' && maintainStocks && vendor ? vendor.id : null;
  const normalizedItems = normalizeDeliveryChallanItems(input.items || []);
  const items = [];
  for (const item of normalizedItems) {
    if (!maintainStocks) {
      items.push({
        ...item,
        orderItemId: null,
        productionRunId: null,
        itemId: null,
        variationLeafNodeId: 0,
        particulars: item.particulars,
        variationPathLabel: item.variationPathLabel,
        hsnCode: item.hsnCode,
      });
    } else if (challanType === 'delivery') {
      if (item.productionRunId) {
        const snapshot = await getItemSelectionSnapshot(item.itemId, item.variationLeafNodeId);
        const run = await validateProductionRunForChallanLine(item.productionRunId, {
          itemId: snapshot.itemId,
          variationLeafNodeId: snapshot.variationLeafNodeId,
        });
        items.push({
          ...item,
          orderItemId: item.orderItemId || null,
          productionRunId: run.id,
          itemId: snapshot.itemId,
          variationLeafNodeId: snapshot.variationLeafNodeId,
          particulars: item.particulars || snapshot.particulars,
          variationPathLabel: item.variationPathLabel || snapshot.variationPathLabel,
          variationPathNodeIds: item.variationPathNodeIds?.length
            ? item.variationPathNodeIds
            : snapshot.variationPathNodeIds,
          hsnCode: item.hsnCode,
        });
        continue;
      }
      const orderItemId = Number(item.orderItemId || 0);
      if (!Number.isInteger(orderItemId) || orderItemId <= 0) {
        const error = new Error('Each delivery challan row must reference one of the selected order_items.');
        error.statusCode = 400;
        throw error;
      }
      const selectedOrder = orders.find((order) => Number(order.id) === orderItemId);
      if (!selectedOrder) {
        const error = new Error('Selected challan item does not belong to the selected order.');
        error.statusCode = 400;
        throw error;
      }
      const orderSnapshot = orderSnapshotsById.get(orderItemId);
      const itemId = item.itemId || selectedOrder.item_id || null;
      if (itemId && Number(itemId) !== Number(selectedOrder.item_id || 0)) {
        const error = new Error('Selected challan item does not match the selected order item.');
        error.statusCode = 400;
        throw error;
      }
      const requestedVariationLeafNodeId = Number(item.variationLeafNodeId || 0);
      const orderVariationLeafNodeId = Number(
        orderSnapshot?.variationLeafNodeId || 0,
      );
      if (
        requestedVariationLeafNodeId > 0 &&
        requestedVariationLeafNodeId !== orderVariationLeafNodeId
      ) {
        const error = new Error('Selected challan variation does not match the selected order item.');
        error.statusCode = 400;
        throw error;
      }
      items.push({
        ...item,
        orderItemId,
        productionRunId: null,
        itemId,
        variationLeafNodeId: orderVariationLeafNodeId,
        particulars: orderSnapshot?.particulars || item.particulars,
        variationPathLabel: orderSnapshot?.variationPathLabel || item.variationPathLabel,
        variationPathNodeIds: orderSnapshot?.variationPathNodeIds || item.variationPathNodeIds || [],
        customVariationValues: orderSnapshot?.customVariationValues || item.customVariationValues || {},
        hsnCode: orderSnapshot?.hsnCode || item.hsnCode,
      });
    } else {
      if (!Number.isInteger(item.itemId) || item.itemId <= 0) {
        const error = new Error('Each reception challan row must select an item.');
        error.statusCode = 400;
        throw error;
      }
      const snapshot = await getItemSelectionSnapshot(item.itemId, item.variationLeafNodeId);
      items.push({
        ...item,
        orderItemId: null,
        itemId: snapshot.itemId,
        variationLeafNodeId: snapshot.variationLeafNodeId,
        particulars: item.particulars || snapshot.particulars,
        variationPathLabel: item.variationPathLabel || snapshot.variationPathLabel,
        variationPathNodeIds: item.variationPathNodeIds?.length
          ? item.variationPathNodeIds
          : snapshot.variationPathNodeIds,
        hsnCode: item.hsnCode,
      });
    }
  }
  const now = new Date().toISOString();

  await run('BEGIN TRANSACTION');
  try {
    let challanId = id;
    if (existing) {
      await run(
        `
        UPDATE delivery_challans
        SET type = ?, order_id = ?, order_no = ?, challan_no = ?, date = ?, location = ?,
            customer_name = ?, customer_gstin = ?, vendor_id = ?, vendor_name = ?, vendor_gstin = ?,
            material_owner_client_id = ?, material_owner_client_name = ?, material_owner_gstin = ?,
            source_reference = ?, notes = ?, maintain_stocks = ?, purpose = ?, internal_purpose = ?, updated_by = ?, updated_at = ?
        WHERE id = ?
        `,
        [
          challanType,
          persistedOrderId,
          orderNo,
          challanNo,
          date,
          location,
          customerName,
          customerGstin,
          persistedVendorId,
          vendorName,
          vendorGstin,
          materialOwnerClientId > 0 ? materialOwnerClientId : null,
          materialOwnerClientName,
          materialOwnerGstin,
          sourceReference,
          notes,
          maintainStocks ? 1 : 0,
          purpose,
          internalPurpose,
          actor?.id || null,
          now,
          challanId,
        ],
      );
      await run('DELETE FROM delivery_challan_items WHERE challan_id = ?', [challanId]);
      await run('DELETE FROM delivery_challan_order_items WHERE challan_id = ?', [challanId]);
    } else {
      const result = await run(
        `
        INSERT INTO delivery_challans (
          type, order_id, order_no, challan_no, date, location, customer_name, customer_gstin,
          vendor_id, vendor_name, vendor_gstin, material_owner_client_id, material_owner_client_name,
          material_owner_gstin, source_reference, notes, status,
          maintain_stocks, purpose, internal_purpose, created_by, updated_by, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'draft', ?, ?, ?, ?, ?, ?, ?)
        `,
        [
          challanType,
          persistedOrderId,
          orderNo,
          challanNo,
          date,
          location,
          customerName,
          customerGstin,
          persistedVendorId,
          vendorName,
          vendorGstin,
          materialOwnerClientId > 0 ? materialOwnerClientId : null,
          materialOwnerClientName,
          materialOwnerGstin,
          sourceReference,
          notes,
          maintainStocks ? 1 : 0,
          purpose,
          internalPurpose,
          actor?.id || null,
          actor?.id || null,
          now,
          now,
        ],
      );
      challanId = result.lastID;
    }

    if (challanType === 'delivery' && maintainStocks) {
      for (const orderId of orderIds) {
        await run(
          `
          INSERT INTO delivery_challan_order_items (challan_id, order_id, created_at)
          VALUES (?, ?, ?)
          `,
          [challanId, orderId, now],
        );
      }
    }

    const reportGroupInputProvided =
      Object.prototype.hasOwnProperty.call(input, 'reportGroupCodes') ||
      Object.prototype.hasOwnProperty.call(input, 'report_group_codes');
    let reportGroupCodes = [];
    if (challanType === 'delivery') {
      reportGroupCodes = deriveReportGroupCodesFromOrderIds(orderIds);
    } else if (reportGroupInputProvided) {
      reportGroupCodes = normalizeReportGroupCodes(
        input.reportGroupCodes ?? input.report_group_codes ?? [],
      );
    } else if (existing) {
      reportGroupCodes = await getDeliveryChallanReportGroupCodes(challanId);
    }
    await replaceChallanReportGroups(challanId, reportGroupCodes);

    const genericAssets = input.genericAssets ?? [];
    if (Array.isArray(genericAssets) && genericAssets.length > 0) {
      for (const asset of genericAssets) {
        if (!asset.objectKey || !asset.fileName || !asset.contentType) continue;
        await run(
          `
          INSERT OR IGNORE INTO uploaded_assets (
            entity_type, entity_id, file_name, content_type, size_bytes, sha256,
            object_key, status, is_primary, created_at, uploaded_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 'uploaded', 0, ?, ?)
          `,
          [
            'delivery_challan',
            challanId,
            asset.fileName,
            asset.contentType,
            asset.sizeBytes || 0,
            asset.sha256 || '',
            asset.objectKey,
            now,
            now,
          ]
        );
      }
    }

    for (const item of items) {
      const itemResult = await run(
        `
        INSERT INTO delivery_challan_items (
          challan_id, order_item_id, production_run_id, item_id, variation_leaf_node_id,
          line_no, particulars, hsn_code, variation_path_label, variation_path_node_ids_json,
          note, quantity_pcs, weight, custom_variation_values_json, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `,
        [
          challanId,
          item.orderItemId,
          item.productionRunId || null,
          item.itemId,
          item.variationLeafNodeId || 0,
          item.lineNo,
          item.particulars,
          item.hsnCode,
          item.variationPathLabel || '',
          JSON.stringify(item.variationPathNodeIds || []),
          item.note,
          normalizeDeliveryChallanMeasure(item.quantityPcs, 'challan quantity'),
          normalizeDeliveryChallanMeasure(item.weight, 'challan weight'),
          JSON.stringify(item.customVariationValues || {}),
          now,
          now,
        ],
      );
      
      const newChallanItemId = itemResult.lastID;
      
      const pieceBarcodes = item.pieceBarcodes || item.piece_barcodes || [];
      for (const pb of pieceBarcodes) {
        if (pb.parentCode && pb.childCode) {
          await run(
            `INSERT INTO piece_barcodes (challan_item_id, parent_code, child_code, created_at) VALUES (?, ?, ?, ?)`,
            [newChallanItemId, pb.parentCode, pb.childCode, now]
          );
        }
      }
    }

    await logDeliveryChallanActivity(challanId, existing ? 'challan_edited' : 'challan_created', actor, {
      challanNo,
      type: challanType,
      itemCount: items.length,
    });
    const saved = await getDeliveryChallanRowById(challanId);
    await logChange('delivery_challans', challanId, existing ? 'UPDATE' : 'INSERT');
    await run('COMMIT');
    return saved;
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function issueDeliveryChallan(id, actor = null) {
  const existing = await getDeliveryChallanRowById(id);
  if (!existing) {
    const error = new Error('Delivery challan not found.');
    error.statusCode = 404;
    throw error;
  }
  if (existing.status === 'cancelled') {
    const error = new Error('Cancelled challans cannot be issued.');
    error.statusCode = 400;
    throw error;
  }

  const maintainStocks = Number(existing.maintain_stocks ?? 1) !== 0;
  if (maintainStocks && normalizeChallanType(existing.type) === 'delivery') {
    const orderIds = await getDeliveryChallanOrderIds(id);
    if (orderIds.length === 0 && !existing.order_id) {
      const error = new Error('Select at least one order before issuing challan.');
      error.statusCode = 400;
      throw error;
    }
  }
  if (maintainStocks && normalizeChallanType(existing.type) === 'delivery' && !String(existing.customer_name || '').trim()) {
    const error = new Error('Customer name is required before issuing challan.');
    error.statusCode = 400;
    throw error;
  }
  if (maintainStocks && normalizeChallanType(existing.type) === 'reception' && !existing.vendor_id) {
    const error = new Error('Vendor is required before issuing reception challan.');
    error.statusCode = 400;
    throw error;
  }
  const items = await getDeliveryChallanItems(id);
  if (items.length === 0) {
    const error = new Error('Add at least one line item before issuing challan.');
    error.statusCode = 400;
    throw error;
  }
  for (const item of items) {
    if (maintainStocks && !item.order_item_id && !item.item_id) {
      const error = new Error('Each challan item must reference an order item.');
      error.statusCode = 400;
      throw error;
    }
    if (!maintainStocks && !String(item.particulars || '').trim()) {
      const error = new Error('Enter item text and Qty / Pcs or Weight for each challan item before issuing.');
      error.statusCode = 400;
      throw error;
    }
    const quantity = Number(item.quantity_pcs);
    const weight = Number(item.weight);
    const hasQuantity = Number.isFinite(quantity) && quantity > 0;
    const hasWeight = Number.isFinite(weight) && weight > 0;
    if (!hasQuantity && !hasWeight) {
      const error = new Error('Enter Qty / Pcs or Weight for each challan item before issuing.');
      error.statusCode = 400;
      throw error;
    }
    if (maintainStocks && normalizeChallanType(existing.type) === 'delivery' && item.production_run_id) {
      await validateProductionRunForChallanLine(item.production_run_id, {
        itemId: item.item_id,
        variationLeafNodeId: item.variation_leaf_node_id,
      });
    }
  }
  const profile = rowToCompanyProfileDto(await getActiveCompanyProfile());
  const activeTemplate = await findActiveChallanTemplateForChallan(existing);
  const templateSnapshot = activeTemplate
    ? await buildChallanTemplateSnapshot(activeTemplate)
    : null;
  const now = new Date().toISOString();
  await run('BEGIN TRANSACTION');
  try {
    if (maintainStocks) for (const item of items) {
      const quantity = Number(item.quantity_pcs);
      const weight = Number(item.weight);
      const movementQty = Number.isFinite(quantity) && quantity > 0 ? quantity : weight;
      const movementUom = Number.isFinite(quantity) && quantity > 0 ? 'pcs' : 'weight';

      const itemId = Number(item.item_id || 0);
      const leafNodeId = Number(item.variation_leaf_node_id || 0);
      const locationId = String(existing.location || '').trim() || 'MAIN';
      const isReception = normalizeChallanType(existing.type) === 'reception';
      const movementType = isReception ? 'receive' : 'issue';
      const movementId = `mov-${Date.now()}-${Math.floor(Math.random() * 1000)}`;

      if (itemId === 0) {
        const error = new Error('Each challan item must reference an item.');
        error.statusCode = 400;
        throw error;
      }
      await assertValidStockVariationLeaf(itemId, leafNodeId);

      await run(
        `
        INSERT INTO inventory_movements (
          id, material_barcode, movement_type, qty, primary_qty, uom,
          to_location_id, reason_code, reference_type, reference_id,
          source_challan_id, source_challan_type, source_challan_line_id,
          actor, lot_code, created_at, item_id, variation_leaf_node_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `,
        [
          movementId,
          '-', // legacy barcode
          movementType,
          movementQty,
          movementQty,
          movementUom,
          locationId,
          isReception ? 'reception_challan_issue' : 'delivery_challan_issue',
          'challan',
          String(existing.id),
          existing.id,
          normalizeChallanType(existing.type),
          item.id,
          actor?.name || 'System',
          '-',
          now,
          itemId,
          leafNodeId
        ]
      );

      const delta = isReception ? movementQty : -movementQty;
      await applyVariationStockDelta({
        itemId,
        variationLeafNodeId: leafNodeId,
        locationId,
        variationPathLabel: item.variation_path_label || item.variationPathLabel || item.particulars || '',
        variationPathNodeIds: parseJsonOrArray(
          item.variation_path_node_ids_json ?? item.variationPathNodeIds,
          [],
        ),
        customVariationValues: parseJsonOrArray(
          item.custom_variation_values_json ?? item.customVariationValues,
          {},
        ),
        delta,
        now,
      });
    }
    await run(
      `
      UPDATE delivery_challans
      SET status = 'issued', company_profile_snapshot = ?, template_snapshot_json = ?,
          updated_by = ?, updated_at = ?
      WHERE id = ?
      `,
      [
        JSON.stringify(profile),
        templateSnapshot ? JSON.stringify(templateSnapshot) : null,
        actor?.id || null,
        now,
        id,
      ],
    );
    await logChange('delivery_challans', id, 'UPDATE');
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
  await logDeliveryChallanActivity(id, 'challan_issued', actor, {
    challanNo: existing.challan_no,
    type: normalizeChallanType(existing.type),
    companyProfileId: profile?.id || null,
  });
  return getDeliveryChallanRowById(id);
}

async function cancelDeliveryChallan(id, actor = null) {
  const existing = await getDeliveryChallanRowById(id);
  if (!existing) {
    const error = new Error('Delivery challan not found.');
    error.statusCode = 404;
    throw error;
  }
  if (existing.status === 'cancelled') {
    return existing;
  }
  const now = new Date().toISOString();
  await run('BEGIN TRANSACTION');
  try {
    if (existing.status === 'issued') {
      const movementRows = await all(
        `
        SELECT *
        FROM inventory_movements
        WHERE source_challan_id = ? AND source_challan_type = ?
        ORDER BY created_at ASC, id ASC
        `,
        [existing.id, normalizeChallanType(existing.type)],
      );
      for (const movement of movementRows) {
        const reverseType = movement.movement_type === 'receive' ? 'issue' : 'receive';
        const movementId = `mov-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
        const qty = Number(movement.qty || 0);

        if (movement.item_id === 0 || !movement.item_id) {
          continue; // Skip legacy barcode-based movements or handle gracefully
        }

        const stockLocation = movement.to_location_id || existing.location || 'MAIN';
        await assertValidStockVariationLeaf(movement.item_id, movement.variation_leaf_node_id);

        await run(
          `
          INSERT INTO inventory_movements (
            id, material_barcode, movement_type, qty, primary_qty, uom,
            to_location_id, reason_code, reference_type, reference_id,
            source_challan_id, source_challan_type, source_challan_line_id,
            reverses_movement_id, actor, lot_code, created_at, item_id, variation_leaf_node_id
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `,
          [
            movementId,
            movement.material_barcode || '-',
            reverseType,
            qty,
            Number(movement.primary_qty || movement.qty || 0),
            String(movement.uom || '').trim() || 'units',
            stockLocation,
            'challan_cancel_reversal',
            'challan-cancellation',
            String(existing.id),
            existing.id,
            normalizeChallanType(existing.type),
            movement.source_challan_line_id || null,
            movement.id,
            actor?.name || 'System',
            movement.lot_code || movement.material_barcode || '-',
            now,
            movement.item_id,
            movement.variation_leaf_node_id
          ]
        );

        const delta = reverseType === 'receive' ? qty : -qty;
        await applyVariationStockDelta({
          itemId: movement.item_id,
          variationLeafNodeId: movement.variation_leaf_node_id,
          locationId: stockLocation,
          delta,
          now,
        });
      }
    }
    await run(
      "UPDATE delivery_challans SET status = 'cancelled', updated_by = ?, updated_at = ? WHERE id = ?",
      [actor?.id || null, now, id],
    );
    await logChange('delivery_challans', id, 'UPDATE');
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
  await logDeliveryChallanActivity(id, 'challan_cancelled', actor, {
    challanNo: existing.challan_no,
    type: normalizeChallanType(existing.type),
    previousStatus: existing.status,
  });
  return getDeliveryChallanRowById(id);
}

async function deleteDraftDeliveryChallan(id, actor = null) {
  const existing = await getDeliveryChallanRowById(id);
  if (!existing) {
    const error = new Error('Challan not found.');
    error.statusCode = 404;
    throw error;
  }
  if (existing.status !== 'draft' && existing.type !== 'reception') {
    const error = new Error('Only draft challans can be deleted.');
    error.statusCode = 400;
    throw error;
  }
  await run('BEGIN TRANSACTION');
  try {
    // Issued challans moved stock (reception = receive, delivery = issue); reverse
    // it before deleting so on_hand_qty stays correct, same as cancellation does.
    if (existing.status === 'issued') {
      const movementRows = await all(
        `
        SELECT *
        FROM inventory_movements
        WHERE source_challan_id = ? AND source_challan_type = ?
        ORDER BY created_at ASC, id ASC
        `,
        [existing.id, normalizeChallanType(existing.type)],
      );
      for (const movement of movementRows) {
        const reverseType = movement.movement_type === 'receive' ? 'issue' : 'receive';
        await applyInventoryMovementCore(
          {
            barcode: movement.material_barcode,
            movementType: reverseType,
            qty: Number(movement.qty || 0),
            primaryQty: Number(movement.primary_qty || movement.qty || 0),
            uom: String(movement.uom || '').trim() || 'units',
            toLocationId: movement.to_location_id || existing.location || 'MAIN',
            fromLocationId: movement.from_location_id || null,
            reasonCode: 'challan_delete_reversal',
            referenceType: 'challan-deletion',
            referenceId: String(existing.id),
            sourceChallanId: existing.id,
            sourceChallanType: normalizeChallanType(existing.type),
            sourceChallanLineId: movement.source_challan_line_id || null,
            reversesMovementId: movement.id,
            actor,
            lotCode: movement.lot_code || movement.material_barcode,
          },
          { useTransaction: false },
        );
      }
    }
    await run('UPDATE invoice_lines SET challan_id = NULL, challan_item_id = NULL WHERE challan_id = ?', [id]);
    await run('UPDATE reconciliation_waste_audit SET challan_id = NULL WHERE challan_id = ?', [id]);
    // Explicitly clean up child tables (handles cases where ON DELETE CASCADE may not fire)
    await run('DELETE FROM delivery_challan_activity_log WHERE challan_id = ?', [id]);
    await run('DELETE FROM delivery_challan_report_groups WHERE challan_id = ?', [id]);
    await run('DELETE FROM delivery_challan_order_items WHERE challan_id = ?', [id]);
    await run('DELETE FROM delivery_challan_items WHERE challan_id = ?', [id]);
    await run('DELETE FROM delivery_challans WHERE id = ?', [id]);
    await logChange('delivery_challans', id, 'DELETE');
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
  // No post-delete activity log: delivery_challan_activity_log.challan_id has an
  // ON DELETE CASCADE FK, so logging the deletion after the challan is gone fails
  // with a FOREIGN KEY violation (and the row would be cascade-deleted anyway).
}

function rowToInvoiceLineDto(row) {
  return {
    id: Number(row.id || 0),
    invoiceId: Number(row.invoice_id || 0),
    orderId: row.order_id || null,
    challanId: row.challan_id || null,
    challanItemId: row.challan_item_id || null,
    itemId: row.item_id || null,
    variationLeafNodeId: Number(row.variation_leaf_node_id || 0),
    itemName: row.item_name || '',
    hsnCode: row.hsn_code || '',
    quantity: Number(row.quantity || 0),
    unitPrice: Number(row.unit_price || 0),
    taxableValue: Number(row.taxable_value || 0),
    cgstRate: Number(row.cgst_rate || 0),
    sgstRate: Number(row.sgst_rate || 0),
    cgstAmount: Number(row.cgst_amount || 0),
    sgstAmount: Number(row.sgst_amount || 0),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

async function rowToInvoiceHeaderDto(row, { includeLines = true } = {}) {
  const lines = includeLines
    ? await all(
        `
        SELECT *
        FROM invoice_lines
        WHERE invoice_id = ?
        ORDER BY id ASC
        `,
        [row.id],
      )
    : [];
  return {
    id: Number(row.id || 0),
    invoiceNo: row.invoice_no || '',
    clientId: row.client_id || null,
    clientName: row.client_name || '',
    gstin: row.gstin || '',
    status: row.status || 'draft',
    invoiceDate: row.invoice_date || '',
    totalQuantity: Number(row.total_quantity || 0),
    taxableValue: Number(row.taxable_value || 0),
    cgstAmount: Number(row.cgst_amount || 0),
    sgstAmount: Number(row.sgst_amount || 0),
    totalAmount: Number(row.total_amount || 0),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    lines: lines.map(rowToInvoiceLineDto),
  };
}

function rowToConversionOverrideDto(row) {
  return {
    id: Number(row.id || 0),
    itemId: Number(row.item_id || 0),
    variationLeafNodeId: Number(row.variation_leaf_node_id || 0),
    conversionRatio: Number(row.conversion_ratio || 1) || 1,
    fromUnit: row.from_unit || 'kg',
    toUnitLabel: row.to_unit_label || 'units',
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
  };
}

function rowToWasteAuditDto(row) {
  return {
    id: Number(row.id || 0),
    auditTime: row.created_at || null,
    clientId: row.client_id || null,
    clientName: row.client_name || '',
    itemId: row.item_id || null,
    variationLeafNodeId: Number(row.variation_leaf_node_id || 0),
    itemName: row.item_name || '',
    challanId: row.challan_id || null,
    challanNo: row.challan_no || '',
    inputWeightKg: Number(row.input_weight_kg || 0),
    shippedWeightKg: Number(row.shipped_weight_kg || 0),
    wasteWeightKg: Number(row.waste_weight_kg || 0),
    wastePercentage: Number(row.waste_percentage || 0),
    source: row.source || 'report_snapshot',
  };
}

async function listInvoices({ includeLines = true } = {}) {
  const rows = await all(
    `
    SELECT *
    FROM invoice_headers
    ORDER BY date(invoice_date) DESC, id DESC
    `,
  );
  return Promise.all(rows.map((row) => rowToInvoiceHeaderDto(row, { includeLines })));
}

async function getInvoiceDtoById(id) {
  const row = await get('SELECT * FROM invoice_headers WHERE id = ?', [Number(id)]);
  if (!row) {
    return null;
  }
  return rowToInvoiceHeaderDto(row);
}

async function generateInvoiceNumber() {
  const row = await get(
    `
    SELECT invoice_no
    FROM invoice_headers
    WHERE invoice_no LIKE 'INV-%'
    ORDER BY id DESC
    LIMIT 1
    `,
  );
  const match = String(row?.invoice_no || '').match(/(\d+)$/);
  const next = match ? Number(match[1]) + 1 : 1;
  return `INV-${String(next).padStart(5, '0')}`;
}

function normalizePositiveNumber(value, fieldName, { allowZero = false } = {}) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || (!allowZero && number === 0)) {
    const error = new Error(`${fieldName} must be ${allowZero ? 'zero or positive' : 'positive'}.`);
    error.statusCode = 400;
    throw error;
  }
  return number;
}

async function createInvoice(input = {}) {
  const linesInput = Array.isArray(input.lines) ? input.lines : [];
  if (linesInput.length === 0) {
    const error = new Error('Add at least one invoice line.');
    error.statusCode = 400;
    throw error;
  }
  const invoiceNo = String(input.invoiceNo ?? input.invoice_no ?? '').trim() || await generateInvoiceNumber();
  const duplicate = await get(
    'SELECT id FROM invoice_headers WHERE LOWER(TRIM(invoice_no)) = LOWER(TRIM(?))',
    [invoiceNo],
  );
  if (duplicate) {
    const error = new Error(`Invoice number [${invoiceNo}] is already in use.`);
    error.statusCode = 409;
    throw error;
  }
  const now = new Date().toISOString();
  const invoiceDate = normalizeChallanDate(input.invoiceDate ?? input.invoice_date ?? now);
  const normalizedLines = [];
  for (const rawLine of linesInput) {
    const quantity = normalizePositiveNumber(rawLine.quantity ?? rawLine.qty, 'Invoice quantity');
    const unitPrice = normalizePositiveNumber(rawLine.unitPrice ?? rawLine.unit_price ?? 0, 'Unit price', { allowZero: true });
    const cgstRate = normalizePositiveNumber(rawLine.cgstRate ?? rawLine.cgst_rate ?? 0, 'CGST rate', { allowZero: true });
    const sgstRate = normalizePositiveNumber(rawLine.sgstRate ?? rawLine.sgst_rate ?? 0, 'SGST rate', { allowZero: true });
    const taxableValue = quantity * unitPrice;
    normalizedLines.push({
      orderId: Number(rawLine.orderId ?? rawLine.order_id ?? 0) || null,
      challanId: Number(rawLine.challanId ?? rawLine.challan_id ?? 0) || null,
      challanItemId: Number(rawLine.challanItemId ?? rawLine.challan_item_id ?? 0) || null,
      itemId: Number(rawLine.itemId ?? rawLine.item_id ?? 0) || null,
      variationLeafNodeId: Number(rawLine.variationLeafNodeId ?? rawLine.variation_leaf_node_id ?? 0) || 0,
      itemName: String(rawLine.itemName ?? rawLine.item_name ?? '').trim(),
      hsnCode: String(rawLine.hsnCode ?? rawLine.hsn_code ?? '').trim(),
      quantity,
      unitPrice,
      taxableValue,
      cgstRate,
      sgstRate,
      cgstAmount: taxableValue * cgstRate / 100,
      sgstAmount: taxableValue * sgstRate / 100,
    });
  }
  const totalQuantity = normalizedLines.reduce((sum, line) => sum + line.quantity, 0);
  const taxableValue = normalizedLines.reduce((sum, line) => sum + line.taxableValue, 0);
  const cgstAmount = normalizedLines.reduce((sum, line) => sum + line.cgstAmount, 0);
  const sgstAmount = normalizedLines.reduce((sum, line) => sum + line.sgstAmount, 0);
  await run('BEGIN TRANSACTION');
  try {
    const result = await run(
      `
      INSERT INTO invoice_headers (
        invoice_no, client_id, client_name, gstin, status, invoice_date,
        total_quantity, taxable_value, cgst_amount, sgst_amount, total_amount,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        invoiceNo,
        Number(input.clientId ?? input.client_id ?? 0) || null,
        String(input.clientName ?? input.client_name ?? '').trim(),
        String(input.gstin ?? input.customerGstin ?? input.customer_gstin ?? '').trim(),
        String(input.status || 'draft').trim() || 'draft',
        invoiceDate,
        totalQuantity,
        taxableValue,
        cgstAmount,
        sgstAmount,
        taxableValue + cgstAmount + sgstAmount,
        now,
        now,
      ],
    );
    for (const line of normalizedLines) {
      await run(
        `
        INSERT INTO invoice_lines (
          invoice_id, order_id, challan_id, challan_item_id, item_id, variation_leaf_node_id,
          item_name, hsn_code, quantity, unit_price, taxable_value, cgst_rate, sgst_rate,
          cgst_amount, sgst_amount, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `,
        [
          result.lastID,
          line.orderId,
          line.challanId,
          line.challanItemId,
          line.itemId,
          line.variationLeafNodeId,
          line.itemName,
          line.hsnCode,
          line.quantity,
          line.unitPrice,
          line.taxableValue,
          line.cgstRate,
          line.sgstRate,
          line.cgstAmount,
          line.sgstAmount,
          now,
          now,
        ],
      );
    }
    await run('COMMIT');
    return getInvoiceDtoById(result.lastID);
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

function numberToIndianWords(num) {
  if (num === null || num === undefined || isNaN(num)) return '';
  const absoluteNum = Math.abs(num);
  const rupees = Math.floor(absoluteNum);
  const paise = Math.round((absoluteNum - rupees) * 100);

  const ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
    'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'
  ];

  const tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
  ];

  function convertLessThanThousand(n) {
    if (n === 0) return '';
    let temp = '';
    if (n >= 100) {
      temp += ones[Math.floor(n / 100)] + ' Hundred ';
      n %= 100;
    }
    if (n >= 20) {
      temp += tens[Math.floor(n / 10)] + ' ';
      n %= 10;
    }
    if (n > 0) {
      temp += ones[n] + ' ';
    }
    return temp.trim();
  }

  function convertToWords(n) {
    if (n === 0) return 'Zero';
    let word = '';
    
    // Crores (1,00,00,000)
    if (n >= 10000000) {
      word += convertLessThanThousand(Math.floor(n / 10000000)) + ' Crore ';
      n %= 10000000;
    }
    // Lakhs (1,00,000)
    if (n >= 100000) {
      word += convertLessThanThousand(Math.floor(n / 100000)) + ' Lakh ';
      n %= 100000;
    }
    // Thousands (1,000)
    if (n >= 1000) {
      word += convertLessThanThousand(Math.floor(n / 1000)) + ' Thousand ';
      n %= 1000;
    }
    // Remaining
    if (n > 0) {
      word += convertLessThanThousand(n);
    }
    return word.trim();
  }

  let result = 'Rupees ' + convertToWords(rupees);
  if (paise > 0) {
    result += ' and Paise ' + convertToWords(paise);
  }
  result += ' Only';
  return result;
}

async function generateInvoicePdf(invoiceId) {
  const invoice = await getInvoiceDtoById(invoiceId);
  if (!invoice) {
    const error = new Error('Invoice not found.');
    error.statusCode = 404;
    throw error;
  }

  const companyProfileRow = await getActiveCompanyProfile();
  const companyProfile = companyProfileRow ? rowToCompanyProfileDto(companyProfileRow) : null;

  let clientAddress = '';
  if (invoice.clientId) {
    const client = await getClientRowById(invoice.clientId);
    if (client) {
      clientAddress = client.address || '';
    }
  }

  function formatDate(dateStr) {
    if (!dateStr) return '';
    try {
      const d = new Date(dateStr);
      if (isNaN(d.getTime())) return dateStr;
      const day = String(d.getDate()).padStart(2, '0');
      const month = String(d.getMonth() + 1).padStart(2, '0');
      const year = d.getFullYear();
      return `${day}/${month}/${year}`;
    } catch (e) {
      return dateStr;
    }
  }

  const doc = new PDFDocument({ size: 'A4', margin: 30 });
  const chunks = [];
  doc.on('data', (chunk) => chunks.push(chunk));
  const finished = new Promise((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });

  // Render Page 1 - TAX INVOICE
  // Draw border for page 1
  doc.rect(30, 30, 535.28, 781.89).stroke('#CCCCCC');

  // Supplier info (Left)
  doc.font('Helvetica-Bold').fontSize(14).fillColor('#0F172A')
     .text(companyProfile?.company_name || 'SUPPLIER COMPANY', 35, 35, { width: 280 });
  doc.font('Helvetica').fontSize(9).fillColor('#334155')
     .text(companyProfile?.address || '', 35, 55, { width: 280 })
     .text(`Mobile: ${companyProfile?.mobile || ''}`, 35, 95, { width: 280 })
     .text(`GSTIN: ${companyProfile?.gstin || ''}`, 35, 110, { width: 280 })
     .text(`State Code: ${companyProfile?.state_code || ''}`, 35, 125, { width: 280 });

  // Right side: Invoice Title and Invoice info
  doc.font('Helvetica-Bold').fontSize(18).fillColor('#0F172A')
     .text('TAX INVOICE', 320, 35, { width: 240, align: 'right' });

  doc.font('Helvetica-Bold').fontSize(10).fillColor('#334155')
     .text(`Invoice No: `, 320, 65, { width: 100, align: 'left' })
     .font('Helvetica').text(invoice.invoiceNo, 420, 65, { width: 140, align: 'right' });

  doc.font('Helvetica-Bold')
     .text(`Invoice Date: `, 320, 80, { width: 100, align: 'left' })
     .font('Helvetica').text(formatDate(invoice.invoiceDate), 420, 80, { width: 140, align: 'right' });

  doc.font('Helvetica-Bold')
     .text(`Status: `, 320, 95, { width: 100, align: 'left' })
     .font('Helvetica').text(invoice.status.toUpperCase(), 420, 95, { width: 140, align: 'right' });

  // Horizontal line
  doc.moveTo(30, 145).lineTo(565.28, 145).stroke('#CCCCCC');

  // Billed To & Shipped To
  doc.font('Helvetica-Bold').fontSize(10).fillColor('#0F172A')
     .text('BILLED TO (BUYER):', 35, 155, { width: 250 });
  doc.font('Helvetica-Bold').fontSize(11).fillColor('#334155')
     .text(invoice.clientName, 35, 170, { width: 250 });
  doc.font('Helvetica').fontSize(9)
     .text(clientAddress, 35, 185, { width: 250 });
  doc.font('Helvetica-Bold')
     .text(`GSTIN: `, 35, 220, { width: 50, align: 'left' })
     .font('Helvetica').text(invoice.gstin || 'N/A', 85, 220, { width: 200 });

  doc.font('Helvetica-Bold').fontSize(10).fillColor('#0F172A')
     .text('SHIPPED TO:', 320, 155, { width: 240 });
  doc.font('Helvetica-Bold').fontSize(11).fillColor('#334155')
     .text(invoice.clientName, 320, 170, { width: 240 });
  doc.font('Helvetica').fontSize(9)
     .text(clientAddress, 320, 185, { width: 240 });
  doc.font('Helvetica-Bold')
     .text(`State Code: `, 320, 220, { width: 100, align: 'left' })
     .font('Helvetica').text(invoice.gstin ? invoice.gstin.substring(0, 2) : 'N/A', 420, 220, { width: 140, align: 'right' });

  // Table header
  const tableHeaderY = 235;
  const tableHeaderHeight = 25;
  doc.rect(30, tableHeaderY, 535.28, tableHeaderHeight).fill('#F1F5F9');
  doc.fillColor('#0F172A');

  const columns = [
    { label: 'Sl', width: 25, align: 'center' },
    { label: 'Description of Goods', width: 140, align: 'left' },
    { label: 'HSN', width: 50, align: 'center' },
    { label: 'Qty', width: 40, align: 'right' },
    { label: 'Rate', width: 50, align: 'right' },
    { label: 'Taxable Val', width: 60, align: 'right' },
    { label: 'CGST', width: 55, align: 'right' },
    { label: 'SGST', width: 55, align: 'right' },
    { label: 'Total', width: 60, align: 'right' }
  ];

  let colX = [];
  let currentX = 30;
  for (let i = 0; i < columns.length; i++) {
    colX.push(currentX);
    currentX += columns[i].width;
  }

  columns.forEach((col, idx) => {
    doc.font('Helvetica-Bold').fontSize(8);
    doc.text(col.label, colX[idx] + 2, tableHeaderY + 8, { width: col.width - 4, align: col.align });
  });

  doc.moveTo(30, tableHeaderY + tableHeaderHeight).lineTo(565.28, tableHeaderY + tableHeaderHeight).stroke('#CCCCCC');

  let currentY = tableHeaderY + tableHeaderHeight;
  let sl = 1;
  for (const line of invoice.lines) {
    const itemDesc = line.itemName;
    const descHeight = doc.heightOfString(itemDesc, { width: 140 - 4, fontSize: 8 });
    const rowHeight = Math.max(25, descHeight + 8);

    doc.font('Helvetica').fontSize(8).fillColor('#334155');
    
    // Sl No
    doc.text(String(sl++), colX[0] + 2, currentY + 6, { width: columns[0].width - 4, align: 'center' });
    // Particulars
    doc.font('Helvetica-Bold').text(itemDesc, colX[1] + 2, currentY + 6, { width: columns[1].width - 4, align: 'left' });
    // HSN
    doc.font('Helvetica').text(line.hsnCode || 'N/A', colX[2] + 2, currentY + 6, { width: columns[2].width - 4, align: 'center' });
    // Qty
    doc.text(Number(line.quantity).toFixed(2), colX[3] + 2, currentY + 6, { width: columns[3].width - 4, align: 'right' });
    // Rate
    doc.text(Number(line.unitPrice).toFixed(2), colX[4] + 2, currentY + 6, { width: columns[4].width - 4, align: 'right' });
    // Taxable Value
    doc.text(Number(line.taxableValue).toFixed(2), colX[5] + 2, currentY + 6, { width: columns[5].width - 4, align: 'right' });
    // CGST
    const cgstText = `${line.cgstRate}%\n${Number(line.cgstAmount).toFixed(2)}`;
    doc.text(cgstText, colX[6] + 2, currentY + 4, { width: columns[6].width - 4, align: 'right' });
    // SGST
    const sgstText = `${line.sgstRate}%\n${Number(line.sgstAmount).toFixed(2)}`;
    doc.text(sgstText, colX[7] + 2, currentY + 4, { width: columns[7].width - 4, align: 'right' });
    // Total
    const lineTotal = line.taxableValue + line.cgstAmount + line.sgstAmount;
    doc.text(Number(lineTotal).toFixed(2), colX[8] + 2, currentY + 6, { width: columns[8].width - 4, align: 'right' });

    currentY += rowHeight;
    doc.moveTo(30, currentY).lineTo(565.28, currentY).stroke('#E2E8F0');
  }

  // Draw vertical borders for table
  for (let i = 1; i < colX.length; i++) {
    doc.moveTo(colX[i], tableHeaderY).lineTo(colX[i], currentY).stroke('#E2E8F0');
  }

  // Totals Box
  let summaryY = currentY + 10;
  doc.rect(30, summaryY, 535.28, 60).stroke('#CCCCCC');

  doc.font('Helvetica-Bold').fontSize(8).fillColor('#0F172A')
     .text('Total Amount in Words:', 35, summaryY + 8, { width: 300 });
  const words = numberToIndianWords(invoice.totalAmount);
  doc.font('Helvetica-Oblique').fontSize(9).fillColor('#334155')
     .text(words, 35, summaryY + 20, { width: 300 });

  const rightLabelsX = 350;
  const rightValuesX = 460;
  const labelWidth = 110;
  const valueWidth = 100;

  doc.font('Helvetica-Bold').fontSize(8).fillColor('#0F172A');
  doc.text('Total Taxable Value:', rightLabelsX, summaryY + 8, { width: labelWidth, align: 'left' });
  doc.text('Total CGST Amount:', rightLabelsX, summaryY + 20, { width: labelWidth, align: 'left' });
  doc.text('Total SGST Amount:', rightLabelsX, summaryY + 32, { width: labelWidth, align: 'left' });
  doc.text('Total Amount (GST Inc):', rightLabelsX, summaryY + 45, { width: labelWidth, align: 'left' });

  doc.font('Helvetica').fontSize(8).fillColor('#334155');
  doc.text(Number(invoice.taxableValue).toFixed(2), rightValuesX, summaryY + 8, { width: valueWidth, align: 'right' });
  doc.text(Number(invoice.cgstAmount).toFixed(2), rightValuesX, summaryY + 20, { width: valueWidth, align: 'right' });
  doc.text(Number(invoice.sgstAmount).toFixed(2), rightValuesX, summaryY + 32, { width: valueWidth, align: 'right' });

  doc.font('Helvetica-Bold').fontSize(10).fillColor('#0F172A');
  doc.text(Number(invoice.totalAmount).toFixed(2), rightValuesX, summaryY + 44, { width: valueWidth, align: 'right' });

  // GST Breakdown table
  const gstGroups = {};
  for (const line of invoice.lines) {
    const hsn = line.hsnCode || 'N/A';
    if (!gstGroups[hsn]) {
      gstGroups[hsn] = {
        hsn,
        taxableValue: 0,
        cgstRate: line.cgstRate,
        cgstAmount: 0,
        sgstRate: line.sgstRate,
        sgstAmount: 0,
        totalTax: 0
      };
    }
    gstGroups[hsn].taxableValue += line.taxableValue;
    gstGroups[hsn].cgstAmount += line.cgstAmount;
    gstGroups[hsn].sgstAmount += line.sgstAmount;
    gstGroups[hsn].totalTax += line.cgstAmount + line.sgstAmount;
  }

  let breakdownY = summaryY + 80;
  doc.font('Helvetica-Bold').fontSize(9).fillColor('#0F172A')
     .text('GST Tax Breakdown Table:', 30, breakdownY);

  breakdownY += 15;
  const gstCols = [
    { label: 'HSN/SAC', width: 85, align: 'center' },
    { label: 'Taxable Val', width: 90, align: 'right' },
    { label: 'CGST Rate', width: 65, align: 'right' },
    { label: 'CGST Amt', width: 80, align: 'right' },
    { label: 'SGST Rate', width: 65, align: 'right' },
    { label: 'SGST Amt', width: 80, align: 'right' },
    { label: 'Total Tax', width: 70, align: 'right' }
  ];

  let gstColX = [];
  let gstCurrentX = 30;
  for (let i = 0; i < gstCols.length; i++) {
    gstColX.push(gstCurrentX);
    gstCurrentX += gstCols[i].width;
  }

  doc.rect(30, breakdownY, 535.28, 20).fill('#F8FAFC');
  doc.fillColor('#0F172A').stroke('#CCCCCC');

  gstCols.forEach((col, idx) => {
    doc.font('Helvetica-Bold').fontSize(8);
    doc.text(col.label, gstColX[idx] + 2, breakdownY + 6, { width: col.width - 4, align: col.align });
  });

  let gstRowY = breakdownY + 20;
  Object.values(gstGroups).forEach((group) => {
    doc.rect(30, gstRowY, 535.28, 20).stroke('#CCCCCC');
    doc.font('Helvetica').fontSize(8).fillColor('#334155');
    
    doc.text(group.hsn, gstColX[0] + 2, gstRowY + 6, { width: gstCols[0].width - 4, align: 'center' });
    doc.text(Number(group.taxableValue).toFixed(2), gstColX[1] + 2, gstRowY + 6, { width: gstCols[1].width - 4, align: 'right' });
    doc.text(`${group.cgstRate}%`, gstColX[2] + 2, gstRowY + 6, { width: gstCols[2].width - 4, align: 'right' });
    doc.text(Number(group.cgstAmount).toFixed(2), gstColX[3] + 2, gstRowY + 6, { width: gstCols[3].width - 4, align: 'right' });
    doc.text(`${group.sgstRate}%`, gstColX[4] + 2, gstRowY + 6, { width: gstCols[4].width - 4, align: 'right' });
    doc.text(Number(group.sgstAmount).toFixed(2), gstColX[5] + 2, gstRowY + 6, { width: gstCols[5].width - 4, align: 'right' });
    doc.text(Number(group.totalTax).toFixed(2), gstColX[6] + 2, gstRowY + 6, { width: gstCols[6].width - 4, align: 'right' });
    
    for (let i = 1; i < gstColX.length; i++) {
      doc.moveTo(gstColX[i], gstRowY).lineTo(gstColX[i], gstRowY + 20).stroke('#E2E8F0');
    }
    
    gstRowY += 20;
  });

  // Footer and Signature
  const signatureY = 720;
  doc.moveTo(30, signatureY).lineTo(565.28, signatureY).stroke('#E2E8F0');

  doc.font('Helvetica-Bold').fontSize(8).fillColor('#0F172A')
     .text('Declaration & Terms:', 35, signatureY + 8);
  doc.font('Helvetica').fontSize(7).fillColor('#64748B')
     .text('1. Interest @ 18% p.a. will be charged if payment is not made within due date.\n2. Goods once sold will not be taken back or exchanged.\n3. Subject to jurisdiction of local courts.', 35, signatureY + 20, { width: 250 });

  doc.font('Helvetica-Bold').fontSize(8).fillColor('#0F172A')
     .text(`For ${companyProfile?.company_name || 'SUPPLIER COMPANY'}`, 350, signatureY + 8, { width: 210, align: 'right' });

  doc.font('Helvetica-Oblique').fontSize(8).fillColor('#64748B')
     .text('Authorized Signatory', 350, signatureY + 65, { width: 210, align: 'right' });

  // Pages 2+: Referenced Delivery Challans
  const uniqueChallanIds = [...new Set(invoice.lines.map(line => line.challanId).filter(Boolean))];
  for (const challanId of uniqueChallanIds) {
    const challanRow = await getDeliveryChallanRowById(challanId);
    if (!challanRow) continue;
    const challanDto = await rowToDeliveryChallanDto(challanRow);
    
    doc.addPage({ size: 'A4', margin: 30 });
    
    // Draw border
    doc.rect(30, 30, 535.28, 781.89).stroke('#CCCCCC');
    
    // Supplier Info
    doc.font('Helvetica-Bold').fontSize(12).fillColor('#0F172A')
       .text(companyProfile?.company_name || 'SUPPLIER COMPANY', 35, 35, { width: 280 });
    doc.font('Helvetica').fontSize(8).fillColor('#334155')
       .text(companyProfile?.address || '', 35, 50, { width: 280 })
       .text(`Mobile: ${companyProfile?.mobile || ''}`, 35, 80, { width: 280 })
       .text(`GSTIN: ${companyProfile?.gstin || ''}`, 35, 92, { width: 280 });

    // Challan Heading
    doc.font('Helvetica-Bold').fontSize(14).fillColor('#0F172A')
       .text('DELIVERY CHALLAN', 320, 35, { width: 240, align: 'right' });
    doc.font('Helvetica-Oblique').fontSize(8).fillColor('#64748B')
       .text('(PROOF OF DELIVERY - NO COMMERCIAL VALUE)', 320, 50, { width: 240, align: 'right' });
    
    doc.font('Helvetica-Bold').fontSize(9).fillColor('#334155')
       .text('Challan No: ', 320, 75, { width: 100, align: 'left' })
       .font('Helvetica').text(challanDto.challan_no, 420, 75, { width: 140, align: 'right' });
    doc.font('Helvetica-Bold')
       .text('Challan Date: ', 320, 88, { width: 100, align: 'left' })
       .font('Helvetica').text(formatDate(challanDto.date), 420, 88, { width: 140, align: 'right' });
    doc.font('Helvetica-Bold')
       .text('Order/Ref No: ', 320, 101, { width: 100, align: 'left' })
       .font('Helvetica').text(challanDto.order_no || 'N/A', 420, 101, { width: 140, align: 'right' });

    doc.moveTo(30, 125).lineTo(565.28, 125).stroke('#CCCCCC');

    // Customer Info
    doc.font('Helvetica-Bold').fontSize(9).fillColor('#0F172A')
       .text('DELIVERED TO (CONSIGNEE):', 35, 135, { width: 250 });
    doc.font('Helvetica-Bold').fontSize(10).fillColor('#334155')
       .text(challanDto.customer_name, 35, 148, { width: 250 });
    doc.font('Helvetica').fontSize(8)
       .text(clientAddress || '', 35, 160, { width: 250 });
    doc.font('Helvetica-Bold')
       .text(`GSTIN: `, 35, 195, { width: 50, align: 'left' })
       .font('Helvetica').text(challanDto.customer_gstin || 'N/A', 85, 195, { width: 200 });

    // Dispatch Details
    doc.font('Helvetica-Bold').fontSize(9).fillColor('#0F172A')
       .text('DISPATCH DETAILS:', 320, 135, { width: 240 });
    doc.font('Helvetica').fontSize(8).fillColor('#334155')
       .text(`Notes: ${challanDto.notes || 'N/A'}`, 320, 148, { width: 240, height: 40 });

    doc.moveTo(30, 210).lineTo(565.28, 210).stroke('#CCCCCC');

    // Challan Items Table
    const challanTableY = 210;
    const challanHeaderH = 20;
    doc.rect(30, challanTableY, 535.28, challanHeaderH).fill('#F8FAFC');
    doc.fillColor('#0F172A');
    
    const challanCols = [
      { label: 'Sl No', width: 40, align: 'center' },
      { label: 'Particulars / Description of Goods', width: 295, align: 'left' },
      { label: 'HSN Code', width: 80, align: 'center' },
      { label: 'Qty (Pcs)', width: 60, align: 'right' },
      { label: 'Weight (Kg)', width: 60, align: 'right' }
    ];
    let challanColX = [];
    let currentChallanX = 30;
    for (let i = 0; i < challanCols.length; i++) {
      challanColX.push(currentChallanX);
      currentChallanX += challanCols[i].width;
    }

    challanCols.forEach((col, idx) => {
      doc.font('Helvetica-Bold').fontSize(8);
      doc.text(col.label, challanColX[idx] + 4, challanTableY + 6, { width: col.width - 8, align: col.align });
    });
    doc.moveTo(30, challanTableY + challanHeaderH).lineTo(565.28, challanTableY + challanHeaderH).stroke('#CCCCCC');

    let itemY = challanTableY + challanHeaderH;
    let rowSl = 1;
    for (const item of challanDto.items) {
      const itemDesc = item.particulars || 'Item';
      const note = item.note ? `\nNote: ${item.note}` : '';
      const fullText = itemDesc + note;
      const descHeight = doc.heightOfString(fullText, { width: 295 - 8, fontSize: 8 });
      const rowHeight = Math.max(20, descHeight + 6);
      
      doc.font('Helvetica').fontSize(8).fillColor('#334155');
      doc.text(String(rowSl++), challanColX[0] + 4, itemY + 6, { width: challanCols[0].width - 8, align: 'center' });
      doc.font('Helvetica-Bold').text(itemDesc, challanColX[1] + 4, itemY + 6, { width: challanCols[1].width - 8, align: 'left' });
      if (item.note) {
        doc.font('Helvetica-Oblique').fontSize(7.5).fillColor('#64748B').text(item.note, challanColX[1] + 4, itemY + 16, { width: challanCols[1].width - 8, align: 'left' });
      }
      doc.font('Helvetica').fontSize(8).fillColor('#334155');
      doc.text(item.hsn_code || 'N/A', challanColX[2] + 4, itemY + 6, { width: challanCols[2].width - 8, align: 'center' });
      doc.text(Number(item.quantity_pcs).toFixed(2), challanColX[3] + 4, itemY + 6, { width: challanCols[3].width - 8, align: 'right' });
      doc.text(Number(item.weight).toFixed(2), challanColX[4] + 4, itemY + 6, { width: challanCols[4].width - 8, align: 'right' });
      
      itemY += rowHeight;
      doc.moveTo(30, itemY).lineTo(565.28, itemY).stroke('#E2E8F0');
    }

    for (let i = 1; i < challanColX.length; i++) {
      doc.moveTo(challanColX[i], challanTableY).lineTo(challanColX[i], itemY).stroke('#E2E8F0');
    }

    const footerY = 720;
    doc.moveTo(30, footerY).lineTo(565.28, footerY).stroke('#E2E8F0');
    
    doc.font('Helvetica-Bold').fontSize(8).fillColor('#0F172A')
       .text("Receiver's Signature & Stamp:", 35, footerY + 10);
    doc.font('Helvetica-Oblique').fontSize(7.5).fillColor('#64748B')
       .text('(Sign below upon receipt of goods)', 35, footerY + 20)
       .text('Date: ____/____/________', 35, footerY + 50);

    doc.font('Helvetica-Bold').fontSize(8).fillColor('#0F172A')
       .text(`For ${companyProfile?.company_name || 'SUPPLIER COMPANY'}`, 350, footerY + 10, { width: 210, align: 'right' });
    doc.font('Helvetica-Oblique').fontSize(7.5).fillColor('#64748B')
       .text('Authorised Signatory / Despatched By', 350, footerY + 55, { width: 210, align: 'right' });
  }

  doc.end();
  return finished;
}

async function listConversionOverrides() {
  const rows = await all(
    `
    SELECT *
    FROM reconciliation_conversion_overrides
    ORDER BY updated_at DESC, id DESC
    `,
  );
  return rows.map(rowToConversionOverrideDto);
}

async function saveConversionOverride(input = {}) {
  const itemId = Number(input.itemId ?? input.item_id ?? 0);
  if (!Number.isInteger(itemId) || itemId <= 0) {
    const error = new Error('itemId is required for conversion override.');
    error.statusCode = 400;
    throw error;
  }
  const variationLeafNodeId = Number(input.variationLeafNodeId ?? input.variation_leaf_node_id ?? 0) || 0;
  const conversionRatio = normalizePositiveNumber(
    input.conversionRatio ?? input.conversion_ratio ?? 1,
    'Conversion ratio',
  );
  const fromUnit = String(input.fromUnit ?? input.from_unit ?? 'kg').trim() || 'kg';
  const toUnitLabel = String(input.toUnitLabel ?? input.to_unit_label ?? 'units').trim() || 'units';
  const now = new Date().toISOString();
  await run(
    `
    INSERT INTO reconciliation_conversion_overrides (
      item_id, variation_leaf_node_id, conversion_ratio, from_unit, to_unit_label, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(item_id, variation_leaf_node_id)
    DO UPDATE SET
      conversion_ratio = excluded.conversion_ratio,
      from_unit = excluded.from_unit,
      to_unit_label = excluded.to_unit_label,
      updated_at = excluded.updated_at
    `,
    [itemId, variationLeafNodeId, conversionRatio, fromUnit, toUnitLabel, now, now],
  );
  const row = await get(
    `
    SELECT *
    FROM reconciliation_conversion_overrides
    WHERE item_id = ? AND variation_leaf_node_id = ?
    `,
    [itemId, variationLeafNodeId],
  );
  return rowToConversionOverrideDto(row);
}

async function listWasteAuditRows() {
  const rows = await all(
    `
    SELECT *
    FROM reconciliation_waste_audit
    ORDER BY datetime(created_at) DESC, id DESC
    `,
  );
  return rows.map(rowToWasteAuditDto);
}

function conversionKey(itemId, variationLeafNodeId) {
  return `${Number(itemId || 0)}:${Number(variationLeafNodeId || 0)}`;
}

function safeRatio(value) {
  const ratio = Number(value);
  return Number.isFinite(ratio) && ratio > 0 ? ratio : 1;
}

function lineMeasureToWeightKg(line, ratio) {
  const weight = Number(line.weight || 0);
  if (Number.isFinite(weight) && weight > 0) {
    return weight;
  }
  const qty = Number(line.quantity_pcs || 0);
  return Number.isFinite(qty) && qty > 0 ? qty / safeRatio(ratio) : 0;
}

function lineMeasureToUnits(line, ratio) {
  const qty = Number(line.quantity_pcs || 0);
  if (Number.isFinite(qty) && qty > 0) {
    return qty;
  }
  const weight = Number(line.weight || 0);
  return Number.isFinite(weight) && weight > 0 ? weight * safeRatio(ratio) : 0;
}

function roundMetric(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number * 1000) / 1000 : 0;
}

async function buildReconciliationReport() {
  const overrides = await listConversionOverrides();
  const overrideMap = new Map(
    overrides.map((override) => [
      conversionKey(override.itemId, override.variationLeafNodeId),
      override,
    ]),
  );
  const invoices = await listInvoices();
  const invoiceLines = invoices.flatMap((invoice) =>
    invoice.lines.map((line) => ({ ...line, invoice })),
  );
  const invoiceLinesByChallanItem = new Map();
  for (const line of invoiceLines) {
    if (!line.challanItemId) {
      continue;
    }
    const existing = invoiceLinesByChallanItem.get(line.challanItemId) || [];
    existing.push(line);
    invoiceLinesByChallanItem.set(line.challanItemId, existing);
  }

  const issuedChallans = await all(
    `
    SELECT *
    FROM delivery_challans
    WHERE status = 'issued'
    ORDER BY date(date) ASC, id ASC
    `,
  );
  const challanItems = await all(
    `
    SELECT dci.*, dc.type, dc.challan_no, dc.customer_name, dc.customer_gstin,
           dc.material_owner_client_id, dc.material_owner_client_name, dc.material_owner_gstin,
           dc.maintain_stocks, dc.date, dc.order_id,
           o.client_id AS delivery_client_id,
           o.client_name AS delivery_client_name,
           o.unit_price AS order_unit_price,
           o.total_invoiced_qty AS order_total_invoiced_qty
    FROM delivery_challan_items dci
    JOIN delivery_challans dc ON dc.id = dci.challan_id
    LEFT JOIN order_items o ON o.id = dci.order_item_id
    WHERE dc.status = 'issued'
    ORDER BY date(dc.date) ASC, dc.id ASC, dci.line_no ASC, dci.id ASC
    `,
  );

  const inputByClientItem = new Map();
  for (const row of challanItems) {
    if (normalizeChallanType(row.type) !== 'reception') {
      continue;
    }
    const ownerClientId = Number(row.material_owner_client_id || 0);
    if (!ownerClientId) {
      continue;
    }
    const override = overrideMap.get(conversionKey(row.item_id, row.variation_leaf_node_id));
    const ratio = safeRatio(override?.conversionRatio);
    const key = `${ownerClientId}:${conversionKey(row.item_id, row.variation_leaf_node_id)}`;
    const existing = inputByClientItem.get(key) || {
      clientId: ownerClientId,
      clientName: row.material_owner_client_name || '',
      itemId: row.item_id || null,
      variationLeafNodeId: Number(row.variation_leaf_node_id || 0),
      itemName: row.particulars || '',
      inputWeightKg: 0,
    };
    existing.inputWeightKg += lineMeasureToWeightKg(row, ratio);
    inputByClientItem.set(key, existing);
  }

  const shippedByClientItem = new Map();
  const auditorRows = [];
  for (const row of challanItems) {
    if (normalizeChallanType(row.type) !== 'delivery') {
      continue;
    }
    const clientId = Number(row.delivery_client_id || 0) || null;
    const effectiveClientName = String(row.delivery_client_name || row.customer_name || 'Unlinked party').trim() || 'Unlinked party';
    const override = overrideMap.get(conversionKey(row.item_id, row.variation_leaf_node_id));
    const ratio = safeRatio(override?.conversionRatio);
    const dispatchedWeightKg = lineMeasureToWeightKg(row, ratio);
    const convertedUnits = lineMeasureToUnits(row, ratio);
    const linkedInvoiceLines = invoiceLinesByChallanItem.get(Number(row.id)) || [];
    const invoicedQuantity = linkedInvoiceLines.reduce((sum, line) => sum + Number(line.quantity || 0), 0);
    const cgst = linkedInvoiceLines.reduce((sum, line) => sum + Number(line.cgstAmount || 0), 0);
    const sgst = linkedInvoiceLines.reduce((sum, line) => sum + Number(line.sgstAmount || 0), 0);
    const cgstRate = linkedInvoiceLines.find((line) => Number(line.cgstRate || 0) > 0)?.cgstRate || 0;
    const sgstRate = linkedInvoiceLines.find((line) => Number(line.sgstRate || 0) > 0)?.sgstRate || 0;
    const gstin = linkedInvoiceLines.find((line) => String(line.invoice?.gstin || '').trim())?.invoice?.gstin ||
      row.customer_gstin ||
      '';
    const clientItemKey = `${clientId || 0}:${conversionKey(row.item_id, row.variation_leaf_node_id)}`;
    const shippedExisting = shippedByClientItem.get(clientItemKey) || {
      clientId,
      clientName: effectiveClientName,
      itemId: row.item_id || null,
      variationLeafNodeId: Number(row.variation_leaf_node_id || 0),
      itemName: row.particulars || '',
      shippedWeightKg: 0,
      deliveredUnits: 0,
      lastChallanId: row.challan_id,
      lastChallanNo: row.challan_no || '',
    };
    shippedExisting.shippedWeightKg += dispatchedWeightKg;
    shippedExisting.deliveredUnits += convertedUnits;
    shippedExisting.lastChallanId = row.challan_id;
    shippedExisting.lastChallanNo = row.challan_no || '';
    shippedByClientItem.set(clientItemKey, shippedExisting);
    const inputKey = `${clientId || 0}:${conversionKey(row.item_id, row.variation_leaf_node_id)}`;
    const input = inputByClientItem.get(inputKey);
    const inputWeightKg = input?.inputWeightKg || 0;
    const wasteWeightKg = Math.max(inputWeightKg - shippedExisting.shippedWeightKg, 0);
    const wastePercentage = inputWeightKg > 0 ? wasteWeightKg / inputWeightKg * 100 : 0;
    const denominator = Math.max(Math.abs(convertedUnits), 1);
    const variance = Math.abs(convertedUnits - invoicedQuantity) / denominator;
    const isDirectPrint = Number(row.maintain_stocks ?? 1) === 0 || !row.order_item_id;
    const invoiceableQuantity = Math.max(convertedUnits - invoicedQuantity, 0);
    const unitPrice = Number(row.order_unit_price || 0);
    const status = isDirectPrint
      ? 'Unlinked / Direct Print'
      : invoicedQuantity <= 0
        ? 'Unbilled / In Transit'
        : variance <= 0.02
          ? 'Auto Reconciled'
          : 'Attention Required';
    auditorRows.push({
      challanId: Number(row.challan_id || 0),
      challanItemId: Number(row.id || 0),
      orderId: Number(row.order_item_id || 0) || null,
      dcNumber: row.challan_no || '',
      challanDate: row.date || null,
      clientId,
      clientName: effectiveClientName,
      itemId: row.item_id || null,
      variationLeafNodeId: Number(row.variation_leaf_node_id || 0),
      itemName: row.particulars || '',
      hsnCode: row.hsn_code || '',
      totalDispatchedWeightKg: roundMetric(dispatchedWeightKg),
      convertedUnits: roundMetric(convertedUnits),
      invoicedQuantity: roundMetric(invoicedQuantity),
      invoiceableQuantity: roundMetric(invoiceableQuantity),
      unitPrice: roundMetric(unitPrice),
      financialExposure: roundMetric(invoiceableQuantity * unitPrice),
      gstin,
      cgst: roundMetric(cgst),
      sgst: roundMetric(sgst),
      cgstRate: roundMetric(cgstRate),
      sgstRate: roundMetric(sgstRate),
      wastePercentage: roundMetric(wastePercentage),
      conversionRatio: roundMetric(ratio),
      toUnitLabel: override?.toUnitLabel || 'units',
      variancePercent: roundMetric(variance * 100),
      status,
      unlinkedReason: isDirectPrint
        ? (Number(row.maintain_stocks ?? 1) === 0
          ? 'Document-only challan line does not carry an inventory/order reference.'
          : 'Line is not linked to an order item.')
        : '',
      isAttentionRequired: status === 'Attention Required',
      isDirectPrint,
      isUnbilled: invoicedQuantity < convertedUnits,
      invoiceLineIds: linkedInvoiceLines.map((line) => line.id),
      linkedInvoices: linkedInvoiceLines.map((line) => ({
        id: line.invoice?.id || line.invoiceId,
        invoiceNo: line.invoice?.invoiceNo || '',
        status: line.invoice?.status || '',
        invoiceDate: line.invoice?.invoiceDate || null,
      })),
    });
  }

  const clientRows = [];
  for (const [key, input] of inputByClientItem.entries()) {
    const shipped = shippedByClientItem.get(key) || {
      shippedWeightKg: 0,
      deliveredUnits: 0,
    };
    const balance = input.inputWeightKg - shipped.shippedWeightKg;
    clientRows.push({
      clientId: input.clientId || null,
      clientName: input.clientName || 'Client supplied material',
      itemId: input.itemId,
      variationLeafNodeId: input.variationLeafNodeId,
      itemName: input.itemName,
      materialReceivedInputKg: roundMetric(input.inputWeightKg),
      totalFinishedUnitsDelivered: roundMetric(shipped.deliveredUnits || 0),
      netBalanceMaterialRemainingKg: roundMetric(balance),
      status: balance < -0.001
        ? 'Over Dispatched'
        : balance > 0.001
          ? 'Material Remaining'
          : 'Balanced',
    });
  }

  const now = new Date().toISOString();
  await run('BEGIN TRANSACTION');
  try {
    await run("DELETE FROM reconciliation_waste_audit WHERE source = 'report_snapshot'");
    for (const shipped of shippedByClientItem.values()) {
      const inputKey = `${shipped.clientId || 0}:${conversionKey(shipped.itemId, shipped.variationLeafNodeId)}`;
      const input = inputByClientItem.get(inputKey);
      const inputWeightKg = input?.inputWeightKg || 0;
      const wasteWeightKg = Math.max(inputWeightKg - shipped.shippedWeightKg, 0);
      const wastePercentage = inputWeightKg > 0 ? wasteWeightKg / inputWeightKg * 100 : 0;
      await run(
        `
        INSERT INTO reconciliation_waste_audit (
          client_id, client_name, item_id, variation_leaf_node_id, item_name,
          challan_id, challan_no, input_weight_kg, shipped_weight_kg,
          waste_weight_kg, waste_percentage, source, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'report_snapshot', ?)
        `,
        [
          shipped.clientId,
          shipped.clientName,
          shipped.itemId,
          shipped.variationLeafNodeId,
          shipped.itemName,
          shipped.lastChallanId,
          shipped.lastChallanNo,
          inputWeightKg,
          shipped.shippedWeightKg,
          wasteWeightKg,
          wastePercentage,
          now,
        ],
      );
    }
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
  const wasteAuditRows = await listWasteAuditRows();
  return {
    internalAuditor: auditorRows,
    clientStatement: clientRows,
    misc: wasteAuditRows,
    conversionOverrides: overrides,
    generatedAt: now,
  };
}

async function buildClientStatementReport(input = {}) {
  const requestedReportGroupCode = normalizeReportGroupCode(
    input.reportGroupCode ?? input.report_group_code ?? '',
  );
  const challanIds = Array.isArray(input.challanIds)
    ? input.challanIds
    : Array.isArray(input.challan_ids)
      ? input.challan_ids
      : [];
  const requestedChallanNos = [
    ...new Set(
      challanIds
        .map((value) => String(value || '').trim())
        .filter(Boolean),
    ),
  ];
  if (requestedChallanNos.length === 0) {
    const error = new Error('At least one challan number is required.');
    error.statusCode = 400;
    throw error;
  }

  const receptionChallanIds = Array.isArray(input.receptionChallanIds)
    ? input.receptionChallanIds
    : Array.isArray(input.reception_challan_ids)
      ? input.reception_challan_ids
      : [];
  const requestedReceptionNos = [
    ...new Set(
      receptionChallanIds
        .map((value) => String(value || '').trim())
        .filter(Boolean),
    ),
  ];

  if (requestedReceptionNos.length === 0) {
    const error = new Error('At least one reception challan is required to generate the statement report.');
    error.statusCode = 400;
    throw error;
  }

  const placeholders = requestedChallanNos.map(() => '?').join(', ');
  const challans = await all(
    `
    SELECT *
    FROM delivery_challans
    WHERE challan_no IN (${placeholders})
    `,
    requestedChallanNos,
  );
  const foundNos = new Set(challans.map((row) => String(row.challan_no || '').trim()));
  const missingNos = requestedChallanNos.filter((challanNo) => !foundNos.has(challanNo));
  if (missingNos.length > 0) {
    const error = new Error(`Unknown challan number(s): ${missingNos.join(', ')}.`);
    error.statusCode = 400;
    throw error;
  }
  const invalidNos = challans
    .filter((row) => normalizeChallanType(row.type) !== 'delivery' || row.status !== 'issued')
    .map((row) => row.challan_no);
  if (invalidNos.length > 0) {
    const error = new Error(`Only issued delivery challans can be exported. Invalid: ${invalidNos.join(', ')}.`);
    error.statusCode = 400;
    throw error;
  }

  if (requestedReportGroupCode) {
    const mismatched = [];
    for (const row of challans) {
      const codes = await effectiveReportGroupCodesForChallan(row);
      if (!codes.includes(requestedReportGroupCode)) {
        mismatched.push(row.challan_no);
      }
    }
    if (mismatched.length > 0) {
      const error = new Error(
        `Delivery challans outside report group ${requestedReportGroupCode}: ${mismatched.join(', ')}.`,
      );
      error.statusCode = 400;
      throw error;
    }
  }

  const receptionPlaceholders = requestedReceptionNos.map(() => '?').join(', ');
  const receptionChallans = await all(
    `
    SELECT *
    FROM delivery_challans
    WHERE challan_no IN (${receptionPlaceholders})
    `,
    requestedReceptionNos,
  );
  const foundReceptionNos = new Set(receptionChallans.map((row) => String(row.challan_no || '').trim()));
  const missingReceptionNos = requestedReceptionNos.filter((challanNo) => !foundReceptionNos.has(challanNo));
  if (missingReceptionNos.length > 0) {
    const error = new Error(`Unknown reception challan number(s): ${missingReceptionNos.join(', ')}.`);
    error.statusCode = 400;
    throw error;
  }
  const invalidReceptionNos = receptionChallans
    .filter((row) => normalizeChallanType(row.type) !== 'reception' || row.status !== 'issued')
    .map((row) => row.challan_no);
  if (invalidReceptionNos.length > 0) {
    const error = new Error(`Only issued reception challans can be used. Invalid: ${invalidReceptionNos.join(', ')}.`);
    error.statusCode = 400;
    throw error;
  }

  if (requestedReportGroupCode) {
    const mismatched = [];
    for (const row of receptionChallans) {
      const codes = await effectiveReportGroupCodesForChallan(row);
      if (!codes.includes(requestedReportGroupCode)) {
        mismatched.push(row.challan_no);
      }
    }
    if (mismatched.length > 0) {
      const error = new Error(
        `Reception challans outside report group ${requestedReportGroupCode}: ${mismatched.join(', ')}.`,
      );
      error.statusCode = 400;
      throw error;
    }
  }

  const rows = await all(
    `
    SELECT dc.date, dc.challan_no, dc.customer_name, dc.order_no,
           dci.particulars, dci.note, dci.quantity_pcs, dci.weight
    FROM delivery_challans dc
    JOIN delivery_challan_items dci ON dci.challan_id = dc.id
    WHERE dc.challan_no IN (${placeholders})
      AND dc.type = 'delivery'
      AND dc.status = 'issued'
    ORDER BY date(dc.date) ASC, dc.id ASC, dci.line_no ASC, dci.id ASC
    `,
    requestedChallanNos,
  );
  const reportRows = rows.map((row) => ({
    date: row.date || null,
    challanNo: row.challan_no || '',
    clientName: row.customer_name || '',
    orderNo: row.order_no || '',
    itemName: row.particulars || '',
    note: row.note || '',
    quantityPcs: roundMetric(Number(row.quantity_pcs || 0)),
    weight: roundMetric(Number(row.weight || 0)),
  }));

  const receptionRows = await all(
    `
    SELECT dc.date, dc.challan_no, dc.customer_name,
           dci.particulars, dci.quantity_pcs, dci.weight
    FROM delivery_challans dc
    JOIN delivery_challan_items dci ON dci.challan_id = dc.id
    WHERE dc.challan_no IN (${receptionPlaceholders})
      AND dc.type = 'reception'
      AND dc.status = 'issued'
    ORDER BY date(dc.date) ASC, dc.id ASC, dci.line_no ASC, dci.id ASC
    `,
    requestedReceptionNos,
  );

  const bins = receptionRows.map((r, index) => ({
    id: index,
    challanNo: r.challan_no || '',
    date: r.date || null,
    size: r.particulars || '',
    capacity: Number(r.weight || 0),
    allocatedWeight: 0,
    deliveries: []
  }));

  // Group delivery items by delivery challan
  const deliveryChallansMap = new Map();
  for (const item of reportRows) {
    if (!deliveryChallansMap.has(item.challanNo)) {
      deliveryChallansMap.set(item.challanNo, {
        challanNo: item.challanNo,
        date: item.date,
        items: []
      });
    }
    deliveryChallansMap.get(item.challanNo).items.push(item);
  }
  const deliveryChallansList = Array.from(deliveryChallansMap.values());
  for (const dc of deliveryChallansList) {
    dc.totalWeight = dc.items.reduce((sum, item) => sum + item.weight, 0);
  }

  // Perform First-Fit allocation
  for (const dc of deliveryChallansList) {
    let allocated = false;
    for (const bin of bins) {
      if (bin.allocatedWeight + dc.totalWeight <= bin.capacity + 0.0001) {
        bin.deliveries.push(...dc.items);
        bin.allocatedWeight += dc.totalWeight;
        allocated = true;
        break;
      }
    }
    if (!allocated) {
      if (bins.length > 0) {
        // Fallback: over-allocate to the first available reception challan
        bins[0].deliveries.push(...dc.items);
        bins[0].allocatedWeight += dc.totalWeight;
      } else {
        const error = new Error(`No reception challans available to cover delivery challan ${dc.challanNo}.`);
        error.statusCode = 400;
        throw error;
      }
    }
  }

  const receptionGroups = bins.map((bin) => {
    const less = Math.max(0, bin.capacity - bin.allocatedWeight);
    return {
      receptionChallanNo: bin.challanNo,
      receptionDate: bin.date,
      receptionSize: bin.size,
      receptionWeight: roundMetric(bin.capacity),
      lessWeight: roundMetric(less),
      totalWeight: roundMetric(bin.capacity),
      deliveries: bin.deliveries.map(d => ({
        date: d.date,
        challanNo: d.challanNo,
        particulars: d.itemName,
        note: d.note,
        weight: roundMetric(d.weight),
        quantityPcs: roundMetric(d.quantityPcs)
      }))
    };
  });

  const summary = reportRows.reduce(
    (acc, row) => {
      acc.totalQuantityPcs += Number(row.quantityPcs || 0);
      acc.totalWeight += Number(row.weight || 0);
      return acc;
    },
    {
      challanCount: requestedChallanNos.length,
      totalQuantityPcs: 0,
      totalWeight: 0,
    },
  );
  summary.totalQuantityPcs = roundMetric(summary.totalQuantityPcs);
  summary.totalWeight = roundMetric(summary.totalWeight);

  const generatedAt = new Date().toISOString();
  const allChallanNosToUpdate = [...requestedChallanNos, ...requestedReceptionNos];
  const updatePlaceholders = allChallanNosToUpdate.map(() => '?').join(', ');
  await run(
    `
    UPDATE delivery_challans
    SET used_in_report = 1, updated_at = ?
    WHERE challan_no IN (${updatePlaceholders})
    `,
    [generatedAt, ...allChallanNosToUpdate],
  );

  return {
    rows: reportRows,
    summary,
    generatedAt,
    receptionGroups,
  };
}

async function getOrderRowById(id) {
  return get(`
    SELECT o.*,
      (SELECT SUM(dci.quantity_pcs) 
       FROM delivery_challan_items dci 
       JOIN delivery_challans dc ON dci.challan_id = dc.id 
       WHERE dci.order_item_id = o.id AND dc.status != 'cancelled') as total_delivered_qty,
      COALESCE(
        (SELECT 
          CASE 
            WHEN COUNT(opa.id) = 0 THEN NULL
            WHEN SUM(CASE WHEN pr.status = 'completed' THEN 1 ELSE 0 END) = COUNT(opa.id) THEN 'completed'
            WHEN SUM(CASE WHEN pr.started_at IS NOT NULL THEN 1 ELSE 0 END) > 0 THEN 'inProgress'
            ELSE 'notStarted'
          END
         FROM order_pipeline_assignments opa
         JOIN pipeline_runs pr ON opa.pipeline_run_id = pr.id
         WHERE opa.order_item_id = o.id
        ), o.status
      ) AS status
    FROM order_items o 
    WHERE o.id = ?
  `, [id]);
}

async function getOrders() {
  return all(`
    SELECT o.*,
      (SELECT SUM(dci.quantity_pcs) 
       FROM delivery_challan_items dci 
       JOIN delivery_challans dc ON dci.challan_id = dc.id 
       WHERE dci.order_item_id = o.id AND dc.status != 'cancelled') as total_delivered_qty,
      COALESCE(
        (SELECT 
          CASE 
            WHEN COUNT(opa.id) = 0 THEN NULL
            WHEN SUM(CASE WHEN pr.status = 'completed' THEN 1 ELSE 0 END) = COUNT(opa.id) THEN 'completed'
            WHEN SUM(CASE WHEN pr.started_at IS NOT NULL THEN 1 ELSE 0 END) > 0 THEN 'inProgress'
            ELSE 'notStarted'
          END
         FROM order_pipeline_assignments opa
         JOIN pipeline_runs pr ON opa.pipeline_run_id = pr.id
         WHERE opa.order_item_id = o.id
        ), o.status
      ) AS status
    FROM order_items o 
    ORDER BY datetime(o.created_at) DESC, o.id DESC
  `);
}

const ALLOWED_PO_CONTENT_TYPES = new Set([
  'application/pdf',
  'image/png',
  'image/jpeg',
]);

const ALLOWED_ASSET_CONTENT_TYPES = new Set([
  'image/png',
  'image/jpeg',
  'image/webp',
]);

const ALLOWED_CHALLAN_TEMPLATE_CONTENT_TYPES = new Set([
  'image/png',
  'image/jpeg',
]);

function normalizePoFileName(fileName) {
  const baseName = path.basename(String(fileName || '').trim());
  return baseName
    .replace(/[^\w.\- ()]/g, '_')
    .replace(/_+/g, '_')
    .slice(0, 160) || 'purchase-order';
}

function normalizeChallanTemplateFileName(fileName) {
  const baseName = path.basename(String(fileName || '').trim());
  return baseName
    .replace(/[^\w.\- ()]/g, '_')
    .replace(/_+/g, '_')
    .slice(0, 160) || 'challan-template';
}

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

function assertValidPoUploadInput({
  uploadType,
  fileName,
  contentType,
  sizeBytes,
  sha256,
}) {
  const normalizedUploadType = normalizeUploadType(uploadType);
  const normalizedContentType = String(contentType || '').toLowerCase().trim();
  const normalizedSize = Number(sizeBytes || 0);
  const normalizedSha = String(sha256 || '').toLowerCase().trim();
  const normalizedName = normalizePoFileName(fileName);

  if (normalizedUploadType !== 'ORDER_PO') {
    const error = new Error('PO uploads must declare uploadType = ORDER_PO.');
    error.statusCode = 400;
    throw error;
  }
  if (!ALLOWED_PO_CONTENT_TYPES.has(normalizedContentType)) {
    const error = new Error('Only PDF, PNG, JPG, and JPEG purchase order files are allowed.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isFinite(normalizedSize) || normalizedSize <= 0) {
    const error = new Error('File size must be greater than zero.');
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
    fileName: normalizedName,
    contentType: normalizedContentType,
    sizeBytes: Math.round(normalizedSize),
    sha256: normalizedSha,
  };
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
}) {
  const normalizedEntityType = String(entityType || '').trim().toLowerCase();
  const normalizedEntityId = Number(entityId || 0);
  const normalizedUploadType = normalizeUploadType(uploadType);
  const normalizedContentType = String(contentType || '').toLowerCase().trim();
  const normalizedSize = Number(sizeBytes || 0);
  const normalizedSha = String(sha256 || '').toLowerCase().trim();
  const normalizedName = normalizeAssetFileName(fileName);

  const validUploadTypes = new Set(['ITEM_IMAGE', 'MACHINE_IMAGE', 'DIE_IMAGE']);
  const validEntityTypes = new Set(['item', 'machine', 'die']);

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
  };
}

function assertValidChallanTemplateUploadInput({
  uploadType,
  fileName,
  contentType,
  sizeBytes,
  sha256,
}) {
  const normalizedUploadType = normalizeUploadType(uploadType);
  const normalizedContentType = String(contentType || '').toLowerCase().trim();
  const normalizedSize = Number(sizeBytes || 0);
  const normalizedSha = String(sha256 || '').toLowerCase().trim();
  const normalizedName = normalizeChallanTemplateFileName(fileName);

  if (
    normalizedUploadType !== 'CHALLAN_TEMPLATE_BACKGROUND' &&
    normalizedUploadType !== 'CHALLAN_TEMPLATE_STAMP'
  ) {
    const error = new Error(
      'Challan template uploads must declare a supported challan template upload type.',
    );
    error.statusCode = 400;
    throw error;
  }
  if (
    normalizedUploadType === 'CHALLAN_TEMPLATE_STAMP' &&
    normalizedContentType !== 'image/png'
  ) {
    const error = new Error('Challan stamps and signatures must be transparent PNG files.');
    error.statusCode = 400;
    throw error;
  }
  if (
    normalizedUploadType === 'CHALLAN_TEMPLATE_BACKGROUND' &&
    !ALLOWED_CHALLAN_TEMPLATE_CONTENT_TYPES.has(normalizedContentType)
  ) {
    const error = new Error('Only PNG, JPG, and JPEG template scans are allowed.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isFinite(normalizedSize) || normalizedSize <= 0) {
    const error = new Error('File size must be greater than zero.');
    error.statusCode = 400;
    throw error;
  }
  if (normalizedSize > 15 * 1024 * 1024) {
    const error = new Error('Challan template scans must be 15 MB or smaller.');
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
    fileName: normalizedName,
    contentType: normalizedContentType,
    sizeBytes: Math.round(normalizedSize),
    sha256: normalizedSha,
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
  expiresSeconds = 900,
}) {
  const config = assertS3Configured();
  const client = getS3Client();
  let command;
  if (method === 'PUT') {
    command = new PutObjectCommand({
      Bucket: config.bucket,
      Key: objectKey,
      ...(contentType ? { ContentType: contentType } : {}),
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

async function createPoUploadIntent(input) {
  await cleanupStaleUnlinkedPoDocuments();
  const normalized = assertValidPoUploadInput(input || {});
  const existing = await get(
    "SELECT * FROM po_documents WHERE sha256 = ? AND status = 'uploaded'",
    [normalized.sha256],
  );
  if (existing) {
    return {
      alreadyUploaded: true,
      document: rowToPoDocumentDto(existing),
      upload: null,
    };
  }

  const objectKey = buildS3ObjectKey({
    uploadType: normalized.uploadType,
    fileName: normalized.fileName,
    sha256: normalized.sha256,
  });
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 15 * 60 * 1000).toISOString();
  const uploadSessionId = `po-upload-${now.getTime()}-${crypto
    .randomBytes(8)
    .toString('hex')}`;
  await run(
    `
    INSERT INTO po_upload_sessions (
      id, file_name, content_type, size_bytes, sha256, object_key, status, expires_at, created_at
    )
    VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)
    `,
    [
      uploadSessionId,
      normalized.fileName,
      normalized.contentType,
      normalized.sizeBytes,
      normalized.sha256,
      objectKey,
      expiresAt,
      now.toISOString(),
    ],
  );

  return {
    alreadyUploaded: false,
    document: null,
    upload: {
      uploadSessionId,
      objectKey,
      uploadUrl: await presignS3Url({
        method: 'PUT',
        objectKey,
        contentType: normalized.contentType,
        expiresSeconds: 900,
      }),
      expiresAt,
      headers: {
        'Content-Type': normalized.contentType,
      },
    },
  };
}

async function completePoUpload({ uploadSessionId, objectKey }) {
  const session = await get('SELECT * FROM po_upload_sessions WHERE id = ?', [
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
  await assertS3ObjectExists(session.object_key);

  const now = new Date().toISOString();
  await run(
    `
    INSERT OR IGNORE INTO po_documents (
      file_name, content_type, size_bytes, sha256, object_key, status, created_at, uploaded_at
    )
    VALUES (?, ?, ?, ?, ?, 'uploaded', ?, ?)
    `,
    [
      session.file_name,
      session.content_type,
      Number(session.size_bytes || 0),
      session.sha256,
      session.object_key,
      session.created_at || now,
      now,
    ],
  );
  await run(
    "UPDATE po_upload_sessions SET status = 'completed', completed_at = ? WHERE id = ?",
    [now, uploadSessionId],
  );
  const document = await get('SELECT * FROM po_documents WHERE sha256 = ?', [
    session.sha256,
  ]);
  return rowToPoDocumentDto(document);
}

async function createChallanTemplateUploadIntent(input) {
  const normalized = assertValidChallanTemplateUploadInput(input || {});
  if (normalized.uploadType === 'CHALLAN_TEMPLATE_BACKGROUND') {
    const reusable = await findReusableChallanTemplateUpload(normalized);
    if (reusable) {
      const scan = await rowToChallanTemplateScanDto(reusable);
      if (scan.canvasWidth > 0 && scan.canvasHeight > 0) {
        return {
          uploadSessionId: '',
          objectKey: scan.objectKey,
          uploadUrl: '',
          expiresAt: null,
          headers: {},
          reused: true,
          canvasWidth: scan.canvasWidth,
          canvasHeight: scan.canvasHeight,
          fileName: scan.fileName,
          contentType: scan.contentType,
          sizeBytes: scan.sizeBytes,
          sha256: scan.sha256,
        };
      }
    }
  }
  const objectKey = buildS3ObjectKey({
    uploadType: normalized.uploadType,
    fileName: normalized.fileName,
    sha256: normalized.sha256,
  });
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 15 * 60 * 1000).toISOString();
  const uploadSessionId = `challan-template-upload-${now.getTime()}-${crypto
    .randomBytes(8)
    .toString('hex')}`;
  await run(
    `
    INSERT INTO challan_template_upload_sessions (
      id, file_name, content_type, size_bytes, sha256, upload_type, object_key, status, expires_at, created_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
    `,
    [
      uploadSessionId,
      normalized.fileName,
      normalized.contentType,
      normalized.sizeBytes,
      normalized.sha256,
      normalized.uploadType,
      objectKey,
      expiresAt,
      now.toISOString(),
    ],
  );

  return {
    uploadSessionId,
    objectKey,
    uploadUrl: await presignS3Url({
      method: 'PUT',
      objectKey,
      contentType: normalized.contentType,
      expiresSeconds: 900,
    }),
    expiresAt,
    headers: {
      'Content-Type': normalized.contentType,
    },
    reused: false,
    canvasWidth: 0,
    canvasHeight: 0,
  };
}

async function findReusableChallanTemplateUpload(normalized) {
  const prefix = getS3Prefix(normalized.uploadType);
  return get(
    `
    SELECT *
    FROM challan_template_upload_sessions
    WHERE status = 'completed'
      AND sha256 = ?
      AND object_key LIKE ?
    ORDER BY datetime(completed_at) DESC, id DESC
    LIMIT 1
    `,
    [normalized.sha256, `${prefix}%`],
  );
}

async function ensureChallanTemplateScanDimensions(row) {
  const canvasWidth = Number(row.canvas_width || 0);
  const canvasHeight = Number(row.canvas_height || 0);
  if (canvasWidth > 0 && canvasHeight > 0) {
    return { canvasWidth, canvasHeight };
  }
  try {
    const buffer = await readS3ObjectBuffer(row.object_key);
    const dimensions = imageSize(buffer);
    const width = Number(dimensions.width || 0);
    const height = Number(dimensions.height || 0);
    if (width > 0 && height > 0) {
      await run(
        'UPDATE challan_template_upload_sessions SET canvas_width = ?, canvas_height = ? WHERE id = ?',
        [width, height, row.id],
      );
      return { canvasWidth: width, canvasHeight: height };
    }
  } catch (_) {}
  return { canvasWidth: 0, canvasHeight: 0 };
}

async function rowToChallanTemplateScanDto(row) {
  const dimensions = await ensureChallanTemplateScanDimensions(row);
  let imageUrl = null;
  try {
    imageUrl = (await assetReadUrlPayload(row.object_key)).readUrl;
  } catch (_) {
    imageUrl = null;
  }
  return {
    uploadSessionId: row.id || '',
    objectKey: row.object_key || '',
    fileName: row.file_name || '',
    contentType: row.content_type || '',
    sizeBytes: Number(row.size_bytes || 0),
    sha256: row.sha256 || '',
    canvasWidth: dimensions.canvasWidth,
    canvasHeight: dimensions.canvasHeight,
    imageUrl,
    uploadedAt: row.completed_at || row.created_at || null,
  };
}

async function listChallanTemplateScans({ limit = 24 } = {}) {
  const safeLimit = Math.max(1, Math.min(100, Math.round(Number(limit) || 24)));
  const prefix = S3_UPLOAD_PREFIXES.CHALLAN_TEMPLATE_BACKGROUND;
  const rows = await all(
    `
    SELECT *
    FROM challan_template_upload_sessions
    WHERE status = 'completed'
      AND object_key LIKE ?
    ORDER BY datetime(completed_at) DESC, id DESC
    LIMIT ?
    `,
    [`${prefix}%`, safeLimit],
  );
  return Promise.all(rows.map((row) => rowToChallanTemplateScanDto(row)));
}

async function completeChallanTemplateUpload({ uploadSessionId, objectKey }) {
  const session = await get(
    'SELECT * FROM challan_template_upload_sessions WHERE id = ?',
    [uploadSessionId],
  );
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
  await assertS3ObjectExists(session.object_key);
  const buffer = await readS3ObjectBuffer(session.object_key);
  const dimensions = imageSize(buffer);
  if (!dimensions.width || !dimensions.height) {
    const error = new Error('Uploaded template scan dimensions could not be read.');
    error.statusCode = 400;
    throw error;
  }
  const now = new Date().toISOString();
  await run(
    "UPDATE challan_template_upload_sessions SET status = 'completed', completed_at = ?, canvas_width = ?, canvas_height = ? WHERE id = ?",
    [now, Number(dimensions.width || 0), Number(dimensions.height || 0), uploadSessionId],
  );
  return {
    uploadSessionId,
    objectKey: session.object_key,
    fileName: session.file_name,
    contentType: session.content_type,
    sizeBytes: Number(session.size_bytes || 0),
    canvasWidth: Number(dimensions.width || 0),
    canvasHeight: Number(dimensions.height || 0),
    uploadedAt: now,
  };
}

async function linkPoDocumentsToOrder(orderId, documentIds = []) {
  const uniqueIds = [...new Set((Array.isArray(documentIds) ? documentIds : []).map(Number))]
    .filter((id) => Number.isInteger(id) && id > 0);
  if (uniqueIds.length === 0) {
    return { linked: [], newlyLinkedIds: [] };
  }
  const now = new Date().toISOString();
  const linked = [];
  const newlyLinkedIds = [];
  for (const documentId of uniqueIds) {
    const document = await get(
      "SELECT * FROM po_documents WHERE id = ? AND status = 'uploaded'",
      [documentId],
    );
    if (!document) {
      const error = new Error('One or more PO documents were not uploaded.');
      error.statusCode = 400;
      throw error;
    }
    const result = await run(
      'INSERT OR IGNORE INTO order_po_documents (order_id, document_id, linked_at) VALUES (?, ?, ?)',
      [orderId, documentId, now],
    );
    if (result.changes > 0) {
      newlyLinkedIds.push(documentId);
    }
    linked.push(rowToPoDocumentDto(document));
  }
  return { linked, newlyLinkedIds };
}

async function assertPoDocumentsUploaded(documentIds = []) {
  const uniqueIds = [...new Set((Array.isArray(documentIds) ? documentIds : []).map(Number))]
    .filter((id) => Number.isInteger(id) && id > 0);
  if (uniqueIds.length === 0) {
    return;
  }
  for (const documentId of uniqueIds) {
    const document = await get(
      "SELECT id FROM po_documents WHERE id = ? AND status = 'uploaded'",
      [documentId],
    );
    if (!document) {
      const error = new Error('One or more PO documents were not uploaded.');
      error.statusCode = 400;
      throw error;
    }
  }
}

async function getPoDocumentsForOrder(orderId) {
  const rows = await all(
    `
    SELECT d.*, od.linked_at
    FROM po_documents d
    INNER JOIN order_po_documents od ON od.document_id = d.id
    WHERE od.order_id = ?
    ORDER BY datetime(od.linked_at) DESC, d.id DESC
    `,
    [orderId],
  );
  return rows.map(rowToPoDocumentDto);
}

async function createPoDocumentReadUrl(documentId) {
  const document = await get(
    "SELECT * FROM po_documents WHERE id = ? AND status = 'uploaded'",
    [documentId],
  );
  if (!document) {
    const error = new Error('PO document not found.');
    error.statusCode = 404;
    throw error;
  }
  return {
    document: rowToPoDocumentDto(document),
    readUrl: await presignS3Url({
      method: 'GET',
      objectKey: document.object_key,
      expiresSeconds: 300,
    }),
    expiresAt: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
  };
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
    `,
    [normalized.entityType, normalized.entityId, normalized.sha256],
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
  await run(
    `
    INSERT INTO asset_upload_sessions (
      id, entity_type, entity_id, file_name, content_type, size_bytes, sha256,
      object_key, status, is_primary, expires_at, created_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)
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
    ],
  );

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
        expiresSeconds: 900,
      }),
      expiresAt,
      headers: {
        'Content-Type': normalized.contentType,
      },
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

  const primaryCount = await get(
    `
    SELECT COUNT(*) AS count
    FROM uploaded_assets
    WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded' AND is_primary = 1
    `,
    [session.entity_type, Number(session.entity_id)],
  );
  const shouldBePrimary =
    Number(session.is_primary || 0) === 1 || Number(primaryCount?.count || 0) === 0;
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
    await run(
      `
      INSERT OR IGNORE INTO uploaded_assets (
        entity_type, entity_id, file_name, content_type, size_bytes, sha256,
        object_key, status, is_primary, created_at, uploaded_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, 'uploaded', ?, ?, ?)
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
  return rowToAssetDto(asset, await assetReadUrlPayload(asset.object_key));
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
  await run('UPDATE uploaded_assets SET status = ? WHERE id = ?', [
    'deleted',
    asset.id,
  ]);
  if (Number(asset.is_primary || 0) === 1) {
    const replacement = await get(
      `
      SELECT *
      FROM uploaded_assets
      WHERE entity_type = ? AND entity_id = ? AND status = 'uploaded'
      ORDER BY datetime(uploaded_at) DESC, id DESC
      LIMIT 1
      `,
      [asset.entity_type, Number(asset.entity_id)],
    );
    if (replacement) {
      await run('UPDATE uploaded_assets SET is_primary = 1 WHERE id = ?', [
        replacement.id,
      ]);
    }
  }
}

function normalizeMaterialRequirementNumber(value, fieldName) {
  if (value == null || value === '') {
    return 0;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    const error = new Error(`Invalid material requirement ${fieldName}.`);
    error.statusCode = 400;
    throw error;
  }
  return parsed;
}

function normalizeOptionalDate(value, fieldName) {
  if (value == null || value === '') {
    return null;
  }
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) {
    const error = new Error(`Invalid ${fieldName}.`);
    error.statusCode = 400;
    throw error;
  }
  // M-2 fix: always store as ISO date-only (YYYY-MM-DD) so merge-match
  // comparisons using SQLite 'IS' work consistently regardless of how the
  // date was originally supplied (full ISO string vs date-only string).
  return new Date(parsed).toISOString().slice(0, 10);
}

async function saveOrder({
  orderNo,
  clientId,
  subContractorId = null,
  clientName = '',
  poNumber = '',
  clientCode = '',
  itemId,
  itemName = '',
  variationLeafNodeId = 0,
  variationPathLabel = '',
  variationPathNodeIds = [],
  customVariationValues = {},
  quantity,
  unitId = null,
  unitName = '',
  unitSymbol = '',
  unitPrice = 0,
  totalInvoicedQty,
  status = 'notStarted',
  startDate = null,
  endDate = null,
  poDocumentIds = [],
  materialRequirements = [],
  actor = null,
} = {}, { returnMeta = false } = {}) {
  const trimmedOrderNo = String(orderNo || '').trim();
  const normalizedClientId = Number(clientId);
  let normalizedSubContractorId = null;
  if (subContractorId) {
    normalizedSubContractorId = Number(subContractorId);
  }
  const normalizedItemId = Number(itemId);
  const normalizedQuantity = Number(quantity || 0);
  const normalizedUnitPrice = Number(unitPrice || 0);
  const hasInvoicedQtyInput =
    totalInvoicedQty !== undefined && totalInvoicedQty !== null;
  const normalizedTotalInvoicedQty = Number(totalInvoicedQty || 0);
  const normalizedStartDate = normalizeOptionalDate(startDate, 'start date');
  const normalizedEndDate = normalizeOptionalDate(endDate, 'end date');
  const trimmedPoNumber = String(poNumber || '').trim();
  let trimmedClientName = String(clientName || '').trim();
  let trimmedClientCode = String(clientCode || '').trim();
  let trimmedItemName = String(itemName || '').trim();
  const allowedStatuses = new Set([
    'draft',
    'notStarted',
    'inProgress',
    'completed',
    'delayed',
  ]);
  const normalizedStatus = allowedStatuses.has(status) ? status : 'notStarted';

  if (!trimmedOrderNo) {
    const error = new Error('Order number is required.');
    error.statusCode = 400;
    throw error;
  }
  if (!normalizedClientId || !normalizedItemId) {
    const error = new Error('Client and item are required.');
    error.statusCode = 400;
    throw error;
  }
  const client = await getClientRowById(normalizedClientId);
  if (!client || client.is_archived) {
    const error = new Error('Selected client is not available.');
    error.statusCode = 400;
    throw error;
  }
  if (normalizedSubContractorId) {
    const subContractor = await get('SELECT client_id FROM sub_contractors WHERE id = ?', [normalizedSubContractorId]);
    if (!subContractor) {
      const error = new Error('Selected sub-contractor is not available.');
      error.statusCode = 400;
      throw error;
    }
    if (subContractor.client_id !== normalizedClientId) {
      const error = new Error('Selected sub-contractor does not belong to the selected client.');
      error.statusCode = 400;
      throw error;
    }
  }
  if (!Number.isFinite(normalizedQuantity) || normalizedQuantity <= 0) {
    const error = new Error('Quantity must be greater than zero.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isInteger(normalizedQuantity)) {
    const error = new Error('Quantity must be a whole number.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isFinite(normalizedUnitPrice) || normalizedUnitPrice < 0) {
    const error = new Error('Unit price cannot be negative.');
    error.statusCode = 400;
    throw error;
  }
  if (
    hasInvoicedQtyInput &&
    (!Number.isFinite(normalizedTotalInvoicedQty) ||
      normalizedTotalInvoicedQty < 0)
  ) {
    const error = new Error('Total invoiced quantity cannot be negative.');
    error.statusCode = 400;
    throw error;
  }
  const variationSelection = await resolveOrderVariationSelection({
    itemId: normalizedItemId,
    variationLeafNodeId,
    variationPathNodeIds,
    variationPathLabel,
    status: normalizedStatus,
  });
  const unitSelection = await resolveOrderUnitSelection({
    item: variationSelection.item,
    unitId,
  });

  if (!trimmedClientName && client) {
    trimmedClientName = String(client.name || '').trim();
  }
  if (!trimmedClientCode && client) {
    trimmedClientCode = String(client.alias || '').trim();
  }
  if (!trimmedItemName && variationSelection && variationSelection.item) {
    trimmedItemName = String(variationSelection.item.name || '').trim();
  }
  const normalizedUnitName =
    unitSelection.unitName || String(unitName || '').trim() || 'Pieces';
  const normalizedUnitSymbol =
    unitSelection.unitSymbol || String(unitSymbol || '').trim() || normalizedUnitName;
  const normalizedLeafId = variationSelection.variationLeafNodeId;
  const normalizedVariationPathJson = variationSelection.variationPathNodeIdsJson;
  const canonicalVariationPathLabel = variationSelection.variationPathLabel;
  const normalizedCustomVariationValuesJson = JSON.stringify(customVariationValues || {});
  await assertPoDocumentsUploaded(poDocumentIds);

  const now = new Date().toISOString();
  await run('BEGIN TRANSACTION');
  try {
    const existing = await get(
      `
      SELECT * FROM order_items
      WHERE LOWER(TRIM(order_no)) = LOWER(TRIM(?))
        AND client_id = ?
        AND item_id = ?
        AND variation_leaf_node_id = ?
        AND variation_path_node_ids_json = ?
        AND unit_id IS ?
        AND LOWER(TRIM(po_number)) = LOWER(TRIM(?))
        AND start_date IS ?
        AND end_date IS ?
      `,
      [
        trimmedOrderNo,
        normalizedClientId,
        normalizedItemId,
        normalizedLeafId,
        normalizedVariationPathJson,
        unitSelection.unitId,
        trimmedPoNumber,
        normalizedStartDate,
        normalizedEndDate,
      ],
    );

    let orderId;
    let merged = false;
    let quantityBefore = 0;
    let finalStatus = normalizedStatus;
    if (existing) {
      merged = true;
      quantityBefore = Number(existing.quantity || 0);
      const newTotalQty = quantityBefore + normalizedQuantity;
      const currentInvoiced = hasInvoicedQtyInput 
        ? normalizedTotalInvoicedQty 
        : Number(existing.total_invoiced_qty || 0);
        
      if (currentInvoiced > newTotalQty) {
        const error = new Error(`Cannot merge: Invoiced quantity (${currentInvoiced}) exceeds new requested quantity (${newTotalQty}).`);
        error.statusCode = 400;
        throw error;
      }

      // C-1 fix: never downgrade an order's status during a quantity-merge.
      // The lifecycle priority order is: draft < notStarted < inProgress < delayed < completed.
      // Merging additional quantity should not reset a running/completed order.
      const STATUS_RANK = { draft: 0, notStarted: 1, inProgress: 2, delayed: 2, completed: 3 };
      const existingRank = STATUS_RANK[existing.status] ?? 1;
      const incomingRank = STATUS_RANK[normalizedStatus] ?? 1;
      const mergedStatus = incomingRank > existingRank ? normalizedStatus : existing.status;
      finalStatus = mergedStatus;
      await run(
        `
        UPDATE order_items
        SET quantity = ?,
            client_name = ?,
            client_code = ?,
            item_name = ?,
            variation_path_label = ?,
            variation_path_node_ids_json = ?,
            unit_id = ?,
            unit_name = ?,
            unit_symbol = ?,
            unit_price = ?,
            total_invoiced_qty = ?,
            status = ?,
            start_date = ?,
            end_date = ?,
            custom_variation_values_json = ?,
            sub_contractor_id = ?,
            updated_at = ?
        WHERE id = ?
        `,
        [
          newTotalQty,
          trimmedClientName,
          trimmedClientCode,
          trimmedItemName,
          canonicalVariationPathLabel,
          normalizedVariationPathJson,
          unitSelection.unitId,
          normalizedUnitName,
          normalizedUnitSymbol,
          normalizedUnitPrice > 0 ? normalizedUnitPrice : Number(existing.unit_price || 0),
          hasInvoicedQtyInput
            ? normalizedTotalInvoicedQty
            : Number(existing.total_invoiced_qty || 0),
          mergedStatus,
          normalizedStartDate,
          normalizedEndDate,
          normalizedCustomVariationValuesJson,
          normalizedSubContractorId,
          now,
          existing.id,
        ],
      );
      if (existing.status !== mergedStatus) {
        await run(`
          INSERT INTO order_status_history (
            order_id, previous_status, new_status, changed_by_user_id, changed_at
          ) VALUES (?, ?, ?, ?, ?)
        `, [
          existing.id,
          existing.status,
          mergedStatus,
          actor?.id || null,
          now,
        ]);
      }
      orderId = existing.id;
    } else {
      await run(
        `
        INSERT INTO order_headers (order_no, client_id, po_number, sub_contractor_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(order_no) DO NOTHING
        `,
        [trimmedOrderNo, normalizedClientId, trimmedPoNumber, normalizedSubContractorId, now, now]
      );
      
      // Update order headers for existing orders to ensure sub_contractor_id is correctly set
      await run(
        `UPDATE order_headers SET sub_contractor_id = ?, updated_at = ? WHERE order_no = ?`,
        [normalizedSubContractorId, now, trimmedOrderNo]
      );
      
      const result = await run(
        `
        INSERT INTO order_items (
          order_no, client_id, client_name, po_number, client_code, item_id, item_name,
          variation_leaf_node_id, variation_path_label, variation_path_node_ids_json, quantity,
          unit_id, unit_name, unit_symbol, unit_price, total_invoiced_qty, status,
          custom_variation_values_json, sub_contractor_id,
          created_at, updated_at, start_date, end_date
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `,
        [
          trimmedOrderNo,
          normalizedClientId,
          trimmedClientName,
          trimmedPoNumber,
          trimmedClientCode,
          normalizedItemId,
          trimmedItemName,
          normalizedLeafId,
          canonicalVariationPathLabel,
          normalizedVariationPathJson,
          normalizedQuantity,
          unitSelection.unitId,
          normalizedUnitName,
          normalizedUnitSymbol,
          normalizedUnitPrice,
          hasInvoicedQtyInput ? normalizedTotalInvoicedQty : 0,
          normalizedStatus,
          normalizedCustomVariationValuesJson,
          normalizedSubContractorId,
          now,
          now,
          normalizedStartDate,
          normalizedEndDate,
        ],
      );
      orderId = result.lastID;
    }

    const { newlyLinkedIds } = await linkPoDocumentsToOrder(orderId, poDocumentIds);
    const normalizedMaterialRequirements = Array.isArray(materialRequirements)
      ? materialRequirements
      : [];
    if (normalizedMaterialRequirements.length > 0) {
      await run('DELETE FROM order_material_requirements WHERE order_id = ?', [
        orderId,
      ]);
    }
    for (const req of normalizedMaterialRequirements) {
      await run(`
        INSERT INTO order_material_requirements (
          order_id, item_id, material_barcode,
          material_name, required_qty, allocated_qty, consumed_qty, shortage_qty,
          unit_id, unit_symbol, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `, [
        orderId,
        req.itemId || null,
        String(req.materialBarcode || '').trim(),
        String(req.materialName || '').trim(),
        normalizeMaterialRequirementNumber(req.requiredQty, 'required quantity'),
        normalizeMaterialRequirementNumber(req.allocatedQty, 'allocated quantity'),
        normalizeMaterialRequirementNumber(req.consumedQty, 'consumed quantity'),
        normalizeMaterialRequirementNumber(req.shortageQty, 'shortage quantity'),
        req.unitId || null,
        String(req.unitSymbol || '').trim(),
        req.status || 'pending',
        now,
        now
      ]);
    }

    const activityType = existing ? 'order_updated' : 'order_created';
    await insertOrderActivityLog({
      orderId,
      activityType,
      actor,
      details: {
        merged,
        previousQuantity: quantityBefore,
        quantityAfter: quantityBefore + normalizedQuantity,
        status: finalStatus,
        quantity: normalizedQuantity,
        newlyLinkedDocs: newlyLinkedIds.length,
        requirementsCount: normalizedMaterialRequirements.length,
      },
      createdAt: now,
    });

    if (newlyLinkedIds.length > 0) {
      await insertOrderActivityLog({
        orderId,
        activityType: 'po_documents_linked',
        actor,
        details: { documentIds: newlyLinkedIds },
        createdAt: now,
      });
    }

    const saved = await getOrderRowById(orderId);
    await run('COMMIT');
    if (returnMeta) {
      return {
        orderRow: saved,
        merged,
        quantityBefore,
        quantityAdded: normalizedQuantity,
        quantityAfter: quantityBefore + normalizedQuantity,
      };
    }
    return saved;
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

// C-4 fix: valid lifecycle transitions. 'completed' is terminal and can only
// be changed by an admin (checked in the route layer via requirePermission).
// Keys are current status → Set of statuses the order is allowed to move to.
const ORDER_LIFECYCLE_TRANSITIONS = {
  draft:      new Set(['notStarted', 'inProgress']),
  notStarted: new Set(['draft', 'inProgress', 'delayed']),
  inProgress: new Set(['notStarted', 'completed', 'delayed']),
  delayed:    new Set(['inProgress', 'completed', 'notStarted']),
  completed:  new Set(['inProgress', 'delayed']), // admin-only reversal handled below
};

async function updateOrderLifecycle({
  id,
  status = null,
  startDate = null,
  endDate = null,
  actor = null,
}) {
  const existing = await getOrderRowById(id);
  if (!existing) {
    const error = new Error('Order not found.');
    error.statusCode = 404;
    throw error;
  }
  
  const normalizedStartDate = normalizeOptionalDate(startDate, 'start date');
  const normalizedEndDate = normalizeOptionalDate(endDate, 'end date');
  const now = new Date().toISOString();

  let targetStatus = existing.status;
  let statusChanged = false;
  if (status && status !== existing.status) {
    const isAdmin = actor?.role === 'admin';
    if (existing.status === 'completed' && !isAdmin) {
      const error = new Error(`Only admins can reverse completed orders.`);
      error.statusCode = 403;
      throw error;
    }
    const allowed = ORDER_LIFECYCLE_TRANSITIONS[existing.status];
    if (!allowed || !allowed.has(status)) {
      if (!isAdmin) {
        const error = new Error(`Invalid lifecycle transition from ${existing.status} to ${status}.`);
        error.statusCode = 400;
        throw error;
      }
    }
    targetStatus = status;
    statusChanged = true;
  }

  await run('BEGIN TRANSACTION');
  try {
    await run(
      'UPDATE order_items SET status = ?, start_date = ?, end_date = ?, updated_at = ? WHERE id = ?',
      [targetStatus, normalizedStartDate, normalizedEndDate, now, id],
    );

    if (statusChanged) {
      await run(
        'INSERT INTO order_status_history (order_id, previous_status, new_status, changed_by_user_id, changed_at) VALUES (?, ?, ?, ?, ?)',
        [id, existing.status, targetStatus, actor?.id || null, now],
      );
    }

    await insertOrderActivityLog({
      orderId: id,
      activityType: 'lifecycle_updated',
      actor,
      details: {
        status: targetStatus,
        startDate: normalizedStartDate,
        endDate: normalizedEndDate,
      },
      createdAt: now,
    });

    const updated = await getOrderRowById(id);
    await run('COMMIT');
    return updated;
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function getOrderActivity(orderId) {
  const order = await getOrderRowById(orderId);
  if (!order) {
    const error = new Error('Order not found.');
    error.statusCode = 404;
    throw error;
  }
  return all(
    'SELECT * FROM order_activity_log WHERE order_id = ? ORDER BY datetime(created_at) ASC, id ASC',
    [orderId],
  );
}

async function getOrderStatusHistory(orderId) {
  const order = await getOrderRowById(orderId);
  if (!order) {
    const error = new Error('Order not found.');
    error.statusCode = 404;
    throw error;
  }
  return all(
    'SELECT * FROM order_status_history WHERE order_id = ? ORDER BY datetime(changed_at) ASC, id ASC',
    [orderId],
  );
}

async function findGroupDuplicate({ name, parentGroupId = null, excludeId = null }) {
  const rows = await all('SELECT id, name, parent_group_id FROM groups');
  const normalizedName = normalizeUnitValue(name);
  return rows.find((row) => {
    if (excludeId != null && row.id === excludeId) {
      return false;
    }
    return (
      normalizeUnitValue(row.name) === normalizedName &&
      (row.parent_group_id || null) === (parentGroupId || null)
    );
  }) || null;
}

async function getActiveChildGroups(parentGroupId) {
  return all(
    'SELECT * FROM groups WHERE parent_group_id = ? AND is_archived = 0',
    [parentGroupId],
  );
}

async function groupWouldCreateCycle(groupId, parentGroupId) {
  let currentId = parentGroupId;
  while (currentId != null) {
    if (currentId === groupId) {
      return true;
    }
    const row = await get('SELECT parent_group_id FROM groups WHERE id = ?', [currentId]);
    currentId = row?.parent_group_id || null;
  }
  return false;
}

async function saveGroup({
  name,
  parentGroupId = null,
  unitId,
  id = null,
  groupType = 'item',
  groupStructure = 'hierarchical',
  description = '',
}) {
  const trimmedName = String(name || '').trim();
  const normalizedStructure =
    String(groupStructure || 'hierarchical').toLowerCase() === 'combination'
      ? 'combination'
      : 'hierarchical';
  const isCombination = normalizedStructure === 'combination';
  const trimmedDescription = String(description || '').trim();
  // Combination groups are flat: they never have a parent and never auto-attach
  // to the Primary Group, and their unit is optional (members carry their own).
  let normalizedParentId =
    isCombination || parentGroupId == null ? null : Number(parentGroupId);
  let normalizedUnitId = unitId ? Number(unitId) : null;

  if (
    !isCombination &&
    normalizedParentId == null &&
    trimmedName !== 'Primary Group' &&
    trimmedName !== 'Raw material' &&
    trimmedName !== 'Scrap'
  ) {
    const pg = await get('SELECT id FROM groups WHERE name = "Primary Group" AND parent_group_id IS NULL AND group_type = ?', [groupType]);
    if (pg) {
      normalizedParentId = pg.id;
    }
  }

  if (!trimmedName) {
    throw new Error('name is required.');
  }
  if (!isCombination && groupType !== 'machine' && !normalizedUnitId) {
    throw new Error('unitId is required for non-machine hierarchical groups.');
  }

  if (normalizedUnitId) {
    const unitRow = await get('SELECT * FROM units WHERE id = ?', [normalizedUnitId]);
    if (!unitRow || unitRow.is_archived) {
      const error = new Error('Selected unit does not exist or is archived.');
      error.statusCode = 400;
      throw error;
    }
  }

  if (id != null && normalizedParentId === id) {
    const error = new Error('A group cannot be its own parent.');
    error.statusCode = 409;
    throw error;
  }

  if (normalizedParentId != null) {
    const parentRow = await get('SELECT * FROM groups WHERE id = ?', [normalizedParentId]);
    if (!parentRow || parentRow.is_archived) {
      const error = new Error('Selected parent group is not available.');
      error.statusCode = 400;
      throw error;
    }
    if (id != null && await groupWouldCreateCycle(id, normalizedParentId)) {
      const error = new Error('A group cannot move under its own descendant.');
      error.statusCode = 409;
      throw error;
    }
  }

  const duplicate = await findGroupDuplicate({
    name: trimmedName,
    parentGroupId: normalizedParentId,
    excludeId: id,
  });
  if (duplicate) {
    const error = new Error('A group with the same name already exists here.');
    error.statusCode = 409;
    throw error;
  }

  const now = new Date().toISOString();
  if (id == null) {
    const result = await run(
      `
      INSERT INTO groups (name, group_type, group_structure, description, parent_group_id, unit_id, is_archived, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
      `,
      [trimmedName, groupType, normalizedStructure, trimmedDescription, normalizedParentId, normalizedUnitId, now, now],
    );
    return getGroupRowById(result.lastID);
  }

  const existing = await getGroupRowById(id);
  if (!existing) {
    const error = new Error('Group not found.');
    error.statusCode = 404;
    throw error;
  }
  const blockingUsage = await get(
    `
    SELECT
      (SELECT COUNT(*) FROM groups AS child_groups WHERE child_groups.parent_group_id = ? AND child_groups.is_archived = 0) AS active_child_count,
      (SELECT COUNT(*) FROM items WHERE items.group_id = ? AND items.is_archived = 0) AS active_item_count
    `,
    [id, id],
  );
  if (
    Number(blockingUsage?.active_child_count || 0) > 0 ||
    Number(blockingUsage?.active_item_count || 0) > 0
  ) {
    const error = new Error('Used groups cannot be edited.');
    error.statusCode = 409;
    throw error;
  }

  await run(
    'UPDATE groups SET name = ?, group_type = ?, group_structure = ?, description = ?, parent_group_id = ?, unit_id = ?, updated_at = ? WHERE id = ?',
    [trimmedName, groupType, normalizedStructure, trimmedDescription, normalizedParentId, normalizedUnitId, now, id],
  );
  return getGroupRowById(id);
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
  await run(
    `
    UPDATE groups
    SET name = ?, parent_group_id = ?, unit_id = ?, is_archived = ?, updated_at = ?
    WHERE id = ?
    `,
    [name, parentGroupId, unitId, isArchived ? 1 : 0, new Date().toISOString(), group.id],
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

function buildItemDisplayName(name, alias, quantity) {
  const parts = [String(name || '').trim(), String(alias || '').trim()].filter(Boolean);
  return parts.join(' / ');
}

function buildVariationPathLabel(segments = []) {
  return segments
    .map((entry) => String(entry || '').trim())
    .filter(Boolean)
    .join(' | ');
}

async function saveItem({
  name,
  alias = '',
  displayName = '',
  quantity = 0,
  groupId,
  unitId,
  unitConversions = [],
  namingFormat = [],
  variationTree = [],
  defaultPipelineId = null,
  baseItemId = null,
  photoUrl = null,
  availableForPurchase,
  id = null,
}) {
  const trimmedName = String(name || '').trim();
  const trimmedAlias = String(alias || '').trim();
  const serializedNamingFormat = JSON.stringify(Array.isArray(namingFormat) ? namingFormat : []);
  const quantityNumber = Number(quantity ?? 0);
  const normalizedQuantity = Number.isFinite(quantityNumber) ? quantityNumber : 0;
  const trimmedDisplayName =
    String(displayName || '').trim() || buildItemDisplayName(name, alias, normalizedQuantity);
  const normalizedGroupId = Number(groupId);
  const normalizedUnitId = Number(unitId);
  const normalizedBaseItemId = baseItemId ? Number(baseItemId) : null;

  if (
    !trimmedName ||
    !normalizedGroupId ||
    !normalizedUnitId ||
    !trimmedDisplayName
  ) {
    throw new Error('name, displayName, groupId, and unitId are required.');
  }

  const groupRow = await get('SELECT * FROM groups WHERE id = ?', [normalizedGroupId]);
  if (!groupRow || groupRow.is_archived) {
    const error = new Error('Selected group does not exist or is archived.');
    error.statusCode = 400;
    throw error;
  }

  const unitRow = await get('SELECT * FROM units WHERE id = ?', [normalizedUnitId]);
  if (!unitRow || unitRow.is_archived) {
    const error = new Error('Selected unit does not exist or is archived.');
    error.statusCode = 400;
    throw error;
  }

  const normalizedUnitConversions = [];
  const seenConversionUnits = new Set();
  for (const entry of Array.isArray(unitConversions) ? unitConversions : []) {
    const secondaryUnitId = Number(entry?.unitId);
    const factorToPrimary = Number(entry?.factorToPrimary);

    if (!secondaryUnitId || !Number.isFinite(factorToPrimary) || factorToPrimary <= 0) {
      const error = new Error('Secondary unit conversions must include a valid unit and a factor greater than 0.');
      error.statusCode = 400;
      throw error;
    }
    if (secondaryUnitId === normalizedUnitId) {
      continue;
    }
    if (seenConversionUnits.has(secondaryUnitId)) {
      const error = new Error('Each secondary unit can only be added once.');
      error.statusCode = 409;
      throw error;
    }

    const secondaryUnitRow = await get('SELECT * FROM units WHERE id = ?', [secondaryUnitId]);
    if (!secondaryUnitRow || secondaryUnitRow.is_archived) {
      const error = new Error('Secondary unit does not exist or is archived.');
      error.statusCode = 400;
      throw error;
    }

    seenConversionUnits.add(secondaryUnitId);
    normalizedUnitConversions.push({
      unitId: secondaryUnitId,
      factorToPrimary,
    });
  }

  const duplicate = await findItemDuplicate({
    name: trimmedName,
    groupId: normalizedGroupId,
    unitId: normalizedUnitId,
    excludeId: id,
  });
  if (duplicate) {
    const error = new Error('An item with the same name already exists.');
    error.statusCode = 409;
    throw error;
  }



  const sanitizedTree = sanitizeNodes(variationTree, 'property');
  const comparableTree = (nodes = []) =>
    (nodes || [])
      .map((node) => ({
        id: node.id || null,
        kind: node.kind,
        name: String(node.name || '').trim(),
        displayName: String(node.displayName || '').trim(),
        // H-1 fix: include 'code' so that renaming a variation node's barcode/
        // naming code on a used item is correctly treated as a structural change.
        code: String(node.code || '').trim(),
        inputType: String(node.inputType || 'Text').trim() || 'Text',

        children: comparableTree(node.children || []),
      }))
      .sort((a, b) => a.name.localeCompare(b.name));

  const now = new Date().toISOString();
  await run('BEGIN TRANSACTION');
  try {
    let itemId = id;
    let structuralChangeDetected = false;
    if (id == null) {
      const result = await run(
        `
        INSERT INTO items (
          name, alias, display_name, quantity, group_id, unit_id, naming_format, is_archived, default_pipeline_id, base_item_id, photo_url, available_for_purchase, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?)
        `,
        [
          trimmedName,
          trimmedAlias,
          trimmedDisplayName,
          normalizedQuantity,
          normalizedGroupId,
          normalizedUnitId,
          serializedNamingFormat,
          defaultPipelineId || null,
          normalizedBaseItemId,
          photoUrl || null,
          availableForPurchase ? 1 : 0,
          now,
          now,
        ],
      );
      itemId = result.lastID;
    } else {
      const existing = await getItemRowById(id);
      if (!existing) {
        const error = new Error('Item not found.');
        error.statusCode = 404;
        throw error;
      }
      if ((existing.usage_count || 0) > 0) {
        const existingTree = await getItemVariationTree(id);
        structuralChangeDetected =
          Number(existing.group_id || 0) !== normalizedGroupId ||
          Number(existing.unit_id || 0) !== normalizedUnitId ||
          JSON.stringify(comparableTree(existingTree)) !==
            JSON.stringify(comparableTree(sanitizedTree));
      }
      await run(
        `
        UPDATE items
        SET name = ?, alias = ?, display_name = ?, quantity = ?, group_id = ?, unit_id = ?, naming_format = ?, default_pipeline_id = ?, base_item_id = ?, photo_url = ?, available_for_purchase = ?, updated_at = ?
        WHERE id = ?
        `,
        [
          trimmedName,
          trimmedAlias,
          trimmedDisplayName,
          normalizedQuantity,
          normalizedGroupId,
          normalizedUnitId,
          serializedNamingFormat,
          defaultPipelineId || null,
          normalizedBaseItemId,
          photoUrl || null,
          // Preserve the existing flag when the caller didn't send it (e.g. an
          // internal re-seed via ensureItemRecord) instead of resetting to 0.
          availableForPurchase !== undefined
            ? (availableForPurchase ? 1 : 0)
            : (existing.available_for_purchase ? 1 : 0),
          now,
          id,
        ],
      );
    }

    if (structuralChangeDetected) {
      await run(
        'UPDATE item_variation_nodes SET is_archived = 1, updated_at = ? WHERE item_id = ? AND is_archived = 0',
        [now, itemId]
      );
    }

    const existingNodesRows = structuralChangeDetected
      ? []
      : await all('SELECT id FROM item_variation_nodes WHERE item_id = ? AND is_archived = 0', [itemId]);
    const existingNodeIds = new Set(existingNodesRows.map(row => row.id));
    const processedNodeIds = new Set();

    const upsertNodes = async (nodes, parentNodeId = null) => {
      for (const node of nodes) {
        let nodeId = node.id;

        if (nodeId && existingNodeIds.has(nodeId)) {
          await run(
            `
            UPDATE item_variation_nodes
            SET parent_node_id = ?, name = ?, code = ?, display_name = ?, position = ?, updated_at = ?
            WHERE id = ?
            `,
            [
              parentNodeId,
              node.name,
              node.code || '',
              node.displayName,
              node.position,
              now,
              nodeId,
            ]
          );
        } else {
          const result = await run(
            `
            INSERT INTO item_variation_nodes (
              item_id, parent_node_id, kind, name, code, display_name, position,
              is_archived, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
            `,
            [
              itemId,
              parentNodeId,
              node.kind,
              node.name,
              node.code || '',
              node.displayName,
              node.position,
              now,
              now,
            ],
          );
          nodeId = result.lastID;
        }
        processedNodeIds.add(nodeId);

        await upsertNodes(node.children || [], nodeId);
      }
    };

    await upsertNodes(sanitizedTree);

    for (const oldId of existingNodeIds) {
      if (!processedNodeIds.has(oldId)) {
        await run('UPDATE item_variation_nodes SET is_archived = 1, updated_at = ? WHERE id = ?', [now, oldId]);
      }
    }

    await run('DELETE FROM item_unit_conversions WHERE item_id = ?', [itemId]);
    for (const conversion of normalizedUnitConversions) {
      await run(
        `
        INSERT INTO item_unit_conversions (
          item_id,
          unit_id,
          factor_to_primary,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?)
        `,
        [
          itemId,
          conversion.unitId,
          conversion.factorToPrimary,
          now,
          now,
        ],
      );
    }

    const existingPropertySchema = await getItemPropertySchema(itemId);
    const effectiveSchema = await getEffectiveSchema(normalizedGroupId);
    const topLevelPropertiesByKey = new Map(
      sanitizedTree
        .filter((node) => node.kind === 'property')
        .map((node) => [
          normalizePropertyKey(node.name),
          node,
        ])
        .filter(([key]) => Boolean(key)),
    );
    for (const draft of effectiveSchema.propertyDrafts || []) {
      if (!draft?.mandatory) {
        continue;
      }
      const propertyKey = normalizePropertyKey(draft.propertyKey || draft.name);
      if (!propertyKey) {
        continue;
      }
      const propertyNode = topLevelPropertiesByKey.get(propertyKey);
      const hasDirectValueChild =
        propertyNode &&
        Array.isArray(propertyNode.children) &&
        propertyNode.children.some(
          (child) => child.kind === 'value' && String(child.name || '').trim(),
        );
      if (!hasDirectValueChild) {
        const error = new Error(
          `Provide at least one value for required property "${draft.name}".`,
        );
        error.statusCode = 400;
        throw error;
      }
    }
    await persistItemPropertySchema(
      itemId,
      mergeItemPropertySchema({
        variationTree: sanitizedTree,
        effectiveDrafts: effectiveSchema.propertyDrafts,
        existingSchema: existingPropertySchema,
      }),
      now,
    );

    await logChange('items', itemId, id == null ? 'INSERT' : 'UPDATE');
    await run('COMMIT');
    return getItemRowById(itemId);
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function seedItemsIfEmpty() {
  // Intentionally left empty. The complete item demo set is created later in
  // ensureDemoItemsPresent().
}

async function findItemByDisplayName(displayName) {
  const rows = await getItemsWithUsage();
  return rows.find(
    (row) => normalizeUnitValue(row.display_name) === normalizeUnitValue(displayName),
  ) || null;
}

async function ensureItemRecord({
  name,
  alias = '',
  displayName,
  quantity,
  groupId,
  unitId,
  variationTree,
  isArchived = false,
  matchDisplayNames = [],
}) {
  let existing = await findItemByDisplayName(displayName);
  for (const candidate of matchDisplayNames) {
    if (existing) {
      break;
    }
    existing = await findItemByDisplayName(candidate);
  }

  const item = existing
    ? await saveItem({
        id: existing.id,
        name,
        alias,
        displayName,
        quantity,
        groupId,
        unitId,
        variationTree,
      })
    : await saveItem({
        name,
        alias,
        displayName,
        quantity,
        groupId,
        unitId,
        variationTree,
      });

  if (!existing) {
    if (isArchived) {
      const now = new Date().toISOString();
      await run('UPDATE items SET is_archived = 1, updated_at = ? WHERE id = ?', [now, item.id]);
      await run('UPDATE item_variation_nodes SET is_archived = 1, updated_at = ? WHERE item_id = ?', [now, item.id]);
      await logChange('items', item.id, 'UPDATE');
    }
    return getItemRowById(item.id);
  }

  if (Boolean(existing.is_archived) !== isArchived) {
    const now = new Date().toISOString();
    await run('UPDATE items SET is_archived = ?, updated_at = ? WHERE id = ?', [isArchived ? 1 : 0, now, existing.id]);
    await run('UPDATE item_variation_nodes SET is_archived = ?, updated_at = ? WHERE item_id = ?', [isArchived ? 1 : 0, now, existing.id]);
    await logChange('items', existing.id, 'UPDATE');
  }
  return getItemRowById(existing.id);
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
         (item_id, parent_node_id, kind, name, position, is_archived, created_at, updated_at)
         VALUES (?, NULL, 'property', ?, ?, 0, datetime('now'), datetime('now'))`,
         [itemId, propName, order_index]
      );
      const propId = propRes.lastID;
      
      let val_index = 0;
      for (const val of values) {
        await run(
          `INSERT INTO item_variation_nodes 
           (item_id, parent_node_id, kind, name, code, position, is_archived, created_at, updated_at)
           VALUES (?, ?, 'value', ?, ?, ?, 0, datetime('now'), datetime('now'))`,
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

async function getUnitsWithUsage() {
  return all(`
    SELECT
      units.*,
      unit_groups.name AS unit_group_name,
      base_unit.name AS conversion_base_unit_name,
      (
        (SELECT COUNT(*) FROM materials WHERE materials.unit_id = units.id) +
        (SELECT COUNT(*) FROM groups WHERE groups.unit_id = units.id) +
        (SELECT COUNT(*) FROM items WHERE items.unit_id = units.id) +
        (SELECT COUNT(*) FROM item_unit_conversions WHERE item_unit_conversions.unit_id = units.id) +
        (SELECT COUNT(*) FROM order_items WHERE order_items.unit_id = units.id) +
        (SELECT COUNT(*) FROM units AS dependent_units WHERE dependent_units.conversion_base_unit_id = units.id) +
        (SELECT COUNT(*) FROM order_material_requirements WHERE order_material_requirements.unit_id = units.id)
      ) AS usage_count
    FROM units
    LEFT JOIN unit_groups ON unit_groups.id = units.unit_group_id
    LEFT JOIN units AS base_unit ON base_unit.id = units.conversion_base_unit_id
    ORDER BY units.is_archived ASC, LOWER(COALESCE(unit_groups.name, '')) ASC, LOWER(units.name) ASC, LOWER(units.symbol) ASC
  `);
}

async function findUnitDuplicate({ name, symbol, excludeId = null }) {
  const rows = await all('SELECT id, name, symbol FROM units');
  const normalizedName = normalizeUnitValue(name);
  const normalizedSymbol = normalizeUnitValue(symbol);
  return rows.find((row) => {
    if (excludeId != null && row.id === excludeId) {
      return false;
    }
    return (
      normalizeUnitValue(row.name) === normalizedName &&
      normalizeUnitValue(row.symbol) === normalizedSymbol
    );
  }) || null;
}

async function saveUnit({
  name,
  symbol,
  notes = '',
  unitGroupName = '',
  conversionFactor = 1,
  id = null,
}) {
  const trimmedName = String(name || '').trim();
  const trimmedSymbol = String(symbol || '').trim();
  const trimmedNotes = String(notes || '').trim();
  const resolvedUnitGroupId = await resolveUnitGroupId(unitGroupName);
  const resolvedConversion = await resolveUnitConversion({
    unitGroupId: resolvedUnitGroupId,
    conversionFactor,
    excludeId: id,
  });
  if (!trimmedName || !trimmedSymbol) {
    throw new Error('name and symbol are required.');
  }

  const duplicate = await findUnitDuplicate({
    name: trimmedName,
    symbol: trimmedSymbol,
    excludeId: id,
  });
  if (duplicate) {
    const error = new Error('A unit with the same name and symbol already exists.');
    error.statusCode = 409;
    throw error;
  }

  const now = new Date().toISOString();
  if (id == null) {
    const result = await run(
      `
      INSERT INTO units (name, symbol, unit_group_id, conversion_factor, conversion_base_unit_id, notes, is_archived, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
      `,
      [
        trimmedName,
        trimmedSymbol,
        resolvedUnitGroupId,
        resolvedConversion.conversionFactor,
        resolvedConversion.conversionBaseUnitId,
        trimmedNotes,
        now,
        now,
      ],
    );
    return getUnitRowById(result.lastID);
  }

  const existing = await getUnitRowById(id);
  if (!existing) {
    const error = new Error('Unit not found.');
    error.statusCode = 404;
    throw error;
  }
  if ((existing.usage_count || 0) > 0) {
    const detailsChanged =
      normalizeUnitValue(existing.name) !== normalizeUnitValue(trimmedName) ||
      normalizeUnitValue(existing.symbol) !== normalizeUnitValue(trimmedSymbol) ||
      (existing.unit_group_id || null) !== (resolvedUnitGroupId || null) ||
      Number(existing.conversion_factor || 1) !== Number(resolvedConversion.conversionFactor || 1) ||
      (existing.conversion_base_unit_id || null) !== (resolvedConversion.conversionBaseUnitId || null);
    if (detailsChanged) {
      const error = new Error('Used units cannot change identity or conversion details.');
      error.statusCode = 409;
      throw error;
    }
  }

  await run(
    'UPDATE units SET name = ?, symbol = ?, unit_group_id = ?, conversion_factor = ?, conversion_base_unit_id = ?, notes = ?, updated_at = ? WHERE id = ?',
    [
      trimmedName,
      trimmedSymbol,
      resolvedUnitGroupId,
      resolvedConversion.conversionFactor,
      resolvedConversion.conversionBaseUnitId,
      trimmedNotes,
      now,
      id,
    ],
  );
  return getUnitRowById(id);
}

async function getUnitGroupRowByName(name) {
  const normalized = normalizeUnitValue(name);
  if (!normalized) {
    return null;
  }
  const rows = await all('SELECT * FROM unit_groups');
  return rows.find((row) => normalizeUnitValue(row.name) === normalized) || null;
}

async function resolveUnitGroupId(unitGroupName) {
  const trimmed = String(unitGroupName || '').trim();
  if (!trimmed) {
    return null;
  }
  const existing = await getUnitGroupRowByName(trimmed);
  if (existing) {
    return existing.id;
  }
  const now = new Date().toISOString();
  const result = await run(
    'INSERT INTO unit_groups (name, created_at, updated_at) VALUES (?, ?, ?)',
    [trimmed, now, now],
  );
  return result.lastID;
}

async function resolveUnitConversion({
  unitGroupId,
  conversionFactor,
  excludeId = null,
}) {
  if (!unitGroupId) {
    return { conversionFactor: 1, conversionBaseUnitId: null };
  }
  const rows = await all(
    `
    SELECT * FROM units
    WHERE unit_group_id = ?
    ${excludeId != null ? 'AND id != ?' : ''}
    ORDER BY conversion_base_unit_id ASC, id ASC
    `,
    excludeId != null ? [unitGroupId, excludeId] : [unitGroupId],
  );
  const baseUnit = rows.find((row) => row.conversion_base_unit_id == null) || null;
  if (!baseUnit) {
    return { conversionFactor: 1, conversionBaseUnitId: null };
  }
  const normalizedFactor = Number(conversionFactor);
  if (!normalizedFactor || normalizedFactor <= 0) {
    const error = new Error('conversionFactor must be greater than 0 for grouped units.');
    error.statusCode = 400;
    throw error;
  }
  return {
    conversionFactor: normalizedFactor,
    conversionBaseUnitId: baseUnit.id,
  };
}

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

async function getGroupMaterialRowByGroupId(groupId) {
  const normalizedGroupId = Number(groupId);
  if (!Number.isInteger(normalizedGroupId) || normalizedGroupId <= 0) {
    return null;
  }
  return get(
    `
    SELECT *
    FROM materials
    WHERE linked_group_id = ?
    ORDER BY id ASC
    LIMIT 1
    `,
    [normalizedGroupId],
  );
}

function normalizePropertyKey(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeGroupPropertyDraft(rawDraft) {
  const name = String(rawDraft?.name || '').trim();
  if (!name) {
    return null;
  }
  const propertyKey =
    String(rawDraft?.propertyKey || '').trim() || normalizePropertyKey(name);
  const inputType = String(rawDraft?.inputType || 'Text').trim() || 'Text';
  const sourceType = ['inherited_item', 'inherited_group', 'manual'].includes(rawDraft?.sourceType)
    ? rawDraft.sourceType
    : 'manual';
  const state = ['active', 'unlinked', 'overridden'].includes(rawDraft?.state)
    ? rawDraft.state
    : 'active';
  const overrideLocked = Boolean(rawDraft?.overrideLocked);
  const hasTypeConflict = Boolean(rawDraft?.hasTypeConflict);
  const mandatory = Boolean(rawDraft?.mandatory);
  const unitId = Number(rawDraft?.unitId);
  const unitSymbol = String(rawDraft?.unitSymbol || '').trim() || null;
  const unitLabel = String(rawDraft?.unitLabel || '').trim() || null;
  const sourceGroupId = Number(rawDraft?.sourceGroupId);
  const sourceGroupName = String(rawDraft?.sourceGroupName || '').trim() || null;
  const coverageCount = Number(rawDraft?.coverageCount || 0);
  const selectedItemCountAtResolution = Number(
    rawDraft?.selectedItemCountAtResolution || 0,
  );
  const resolutionSource = String(rawDraft?.resolutionSource || '').trim() || null;
  const sources = Array.isArray(rawDraft?.sources) ? rawDraft.sources : [];
  const sourceItemIds = sources
    .map((source) => Number(source?.itemId))
    .filter((id) => Number.isInteger(id) && id > 0);

  return {
    propertyKey,
    displayName: name,
    inputType,
    sourceType,
    state,
    mandatory,
    unitId: Number.isInteger(unitId) && unitId > 0 ? unitId : null,
    unitSymbol,
    unitLabel,
    sourceGroupId: Number.isInteger(sourceGroupId) && sourceGroupId > 0 ? sourceGroupId : null,
    sourceGroupName,
    overrideLocked,
    hasTypeConflict,
    coverageCount: Number.isFinite(coverageCount) ? Math.max(0, Math.trunc(coverageCount)) : 0,
    selectedItemCountAtResolution: Number.isFinite(selectedItemCountAtResolution)
      ? Math.max(0, Math.trunc(selectedItemCountAtResolution))
      : 0,
    resolutionSource,
    sourceItemIds: [...new Set(sourceItemIds)],
  };
}

function normalizeDiscardedPropertyKeys(rawKeys) {
  if (!Array.isArray(rawKeys)) {
    return [];
  }
  const keys = [];
  const seen = new Set();
  for (const rawKey of rawKeys) {
    const propertyKey = normalizePropertyKey(rawKey);
    if (!propertyKey || seen.has(propertyKey)) {
      continue;
    }
    seen.add(propertyKey);
    keys.push(propertyKey);
  }
  return keys;
}

async function getItemPropertySchema(itemId) {
  const normalizedItemId = Number(itemId);
  if (!Number.isInteger(normalizedItemId) || normalizedItemId <= 0) {
    return [];
  }
  const rows = await all(
    `
    SELECT *
    FROM item_property_schema
    WHERE item_id = ?
    ORDER BY sort_order ASC, id ASC
    `,
    [normalizedItemId],
  );
  return rows.map((row) => ({
    propertyKey: row.property_key || '',
    displayName: row.display_name || '',
    inputType: row.input_type || 'Text',
    mandatory: Number(row.mandatory || 0) === 1,
    unitId: row.unit_id ? Number(row.unit_id) : null,
    unitSymbol: row.unit_symbol || null,
    unitLabel: row.unit_label || null,
    sourceType: row.source_type || 'manual',
    sourceGroupId: row.source_group_id ? Number(row.source_group_id) : null,
    sourceGroupName: row.source_group_name || null,
    sourceItemIds: parseJson(row.source_item_ids_json, [])
      .map((entry) => Number(entry))
      .filter((entry) => Number.isInteger(entry) && entry > 0),
    sortOrder: Number(row.sort_order || 0),
  }));
}

function normalizePropertyKey(value = '') {
  return normalizeUnitValue(String(value || '').trim());
}

function collectTopLevelPropertySchemaFromTree(
  variationTree = [],
  {
    existingByKey = new Map(),
    fallbackByKey = new Map(),
  } = {},
) {
  const drafts = [];
  const seen = new Set();
  let sortOrder = 0;
  for (const node of Array.isArray(variationTree) ? variationTree : []) {
    if (!node || String(node.kind) !== 'property') {
      continue;
    }
    const displayName = String(node.name || '').trim();
    if (!displayName) {
      continue;
    }
    const propertyKey = normalizePropertyKey(displayName);
    if (!propertyKey || seen.has(propertyKey)) {
      continue;
    }
    seen.add(propertyKey);
    const existing = existingByKey.get(propertyKey);
    const fallback = fallbackByKey.get(propertyKey);
    drafts.push({
      propertyKey,
      displayName,
      inputType: node.inputType || existing?.inputType || fallback?.inputType || 'Text',
      mandatory: existing?.mandatory ?? fallback?.mandatory ?? false,
      unitId: existing?.unitId ?? fallback?.unitId ?? null,
      unitSymbol: existing?.unitSymbol ?? fallback?.unitSymbol ?? null,
      unitLabel: existing?.unitLabel ?? fallback?.unitLabel ?? null,
      sourceType: existing?.sourceType || fallback?.sourceType || 'manual',
      sourceGroupId: existing?.sourceGroupId ?? fallback?.sourceGroupId ?? null,
      sourceGroupName: existing?.sourceGroupName ?? fallback?.sourceGroupName ?? null,
      sourceItemIds: Array.isArray(existing?.sourceItemIds)
        ? existing.sourceItemIds
        : (Array.isArray(fallback?.sourceItemIds) ? fallback.sourceItemIds : []),
      sortOrder: sortOrder++,
    });
  }
  return drafts;
}

function mergeItemPropertySchema({
  variationTree = [],
  effectiveDrafts = [],
  existingSchema = [],
} = {}) {
  const existingByKey = new Map(
    (Array.isArray(existingSchema) ? existingSchema : [])
      .map((entry) => [normalizePropertyKey(entry.propertyKey || entry.displayName), entry])
      .filter(([key]) => Boolean(key)),
  );
  const effectiveByKey = new Map(
    (Array.isArray(effectiveDrafts) ? effectiveDrafts : [])
      .map((draft) => {
        const propertyKey = normalizePropertyKey(draft.propertyKey || draft.name);
        return [
          propertyKey,
          {
            propertyKey,
            displayName: draft.name,
            inputType: draft.inputType,
            mandatory: draft.mandatory,
            unitId: draft.unitId ?? null,
            unitSymbol: draft.unitSymbol ?? null,
            unitLabel: draft.unitLabel ?? null,
            sourceType: draft.sourceType || 'manual',
            sourceGroupId: draft.sourceGroupId ?? null,
            sourceGroupName: draft.sourceGroupName ?? null,
            sourceItemIds: Array.isArray(draft.sources)
              ? draft.sources
                  .map((source) => Number(source.itemId))
                  .filter((sourceId) => Number.isInteger(sourceId) && sourceId > 0)
              : [],
            sortOrder: 0,
          },
        ];
      })
      .filter(([key]) => Boolean(key)),
  );

  const merged = collectTopLevelPropertySchemaFromTree(variationTree, {
    existingByKey,
    fallbackByKey: effectiveByKey,
  });
  const seen = new Set(merged.map((entry) => entry.propertyKey));
  let sortOrder = merged.length;
  for (const draft of Array.isArray(effectiveDrafts) ? effectiveDrafts : []) {
    const propertyKey = normalizePropertyKey(draft.propertyKey || draft.name);
    if (!propertyKey || seen.has(propertyKey)) {
      continue;
    }
    seen.add(propertyKey);
    merged.push({
      propertyKey,
      displayName: draft.name,
      inputType: draft.inputType,
      mandatory: draft.mandatory,
      unitId: draft.unitId ?? null,
      unitSymbol: draft.unitSymbol ?? null,
      unitLabel: draft.unitLabel ?? null,
      sourceType: draft.sourceType || 'manual',
      sourceGroupId: draft.sourceGroupId ?? null,
      sourceGroupName: draft.sourceGroupName ?? null,
      sourceItemIds: Array.isArray(draft.sources)
        ? draft.sources
            .map((source) => Number(source.itemId))
            .filter((sourceId) => Number.isInteger(sourceId) && sourceId > 0)
        : [],
      sortOrder: sortOrder++,
    });
  }
  return merged;
}

async function persistItemPropertySchema(itemId, propertySchema, now = new Date().toISOString()) {
  await run('DELETE FROM item_property_schema WHERE item_id = ?', [itemId]);
  const seen = new Set();
  const normalizedEntries = (Array.isArray(propertySchema) ? propertySchema : [])
    .map((entry) => ({
      propertyKey: normalizePropertyKey(entry?.propertyKey || entry?.displayName || ''),
      displayName: String(entry?.displayName || '').trim(),
      inputType: String(entry?.inputType || 'Text').trim() || 'Text',
      mandatory: Boolean(entry?.mandatory),
      unitId: Number(entry?.unitId),
      unitSymbol: String(entry?.unitSymbol || '').trim() || null,
      unitLabel: String(entry?.unitLabel || '').trim() || null,
      sourceType: ['inherited_item', 'inherited_group', 'manual'].includes(entry?.sourceType)
        ? entry.sourceType
        : 'manual',
      sourceGroupId: Number(entry?.sourceGroupId),
      sourceGroupName: String(entry?.sourceGroupName || '').trim() || null,
      sourceItemIds: [...new Set(
        (Array.isArray(entry?.sourceItemIds) ? entry.sourceItemIds : [])
          .map((id) => Number(id))
          .filter((id) => Number.isInteger(id) && id > 0),
      )],
      sortOrder: Number(entry?.sortOrder || 0),
    }))
    .filter((entry) => entry.propertyKey && entry.displayName)
    .filter((entry) => {
      if (seen.has(entry.propertyKey)) {
        return false;
      }
      seen.add(entry.propertyKey);
      return true;
    });

  for (let index = 0; index < normalizedEntries.length; index += 1) {
    const entry = normalizedEntries[index];
    await run(
      `
      INSERT INTO item_property_schema (
        item_id, property_key, display_name, input_type, mandatory,
        unit_id, unit_symbol, unit_label, source_type, source_group_id,
        source_group_name, source_item_ids_json, sort_order, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        itemId,
        entry.propertyKey,
        entry.displayName,
        entry.inputType,
        entry.mandatory ? 1 : 0,
        Number.isInteger(entry.unitId) && entry.unitId > 0 ? entry.unitId : null,
        entry.unitSymbol,
        entry.unitLabel,
        entry.sourceType,
        Number.isInteger(entry.sourceGroupId) && entry.sourceGroupId > 0
          ? entry.sourceGroupId
          : null,
        entry.sourceGroupName,
        JSON.stringify(entry.sourceItemIds),
        Number.isFinite(entry.sortOrder) ? entry.sortOrder : index,
        now,
        now,
      ],
    );
  }
}

async function getEffectiveSchema(groupId) {
  const normalizedGroupId = Number(groupId);
  if (!Number.isInteger(normalizedGroupId) || normalizedGroupId <= 0) {
    const error = new Error('Valid groupId is required.');
    error.statusCode = 400;
    throw error;
  }

  const lineageRows = [];
  let cursor = await getGroupRowById(normalizedGroupId);
  if (!cursor) {
    const error = new Error('Group not found.');
    error.statusCode = 404;
    throw error;
  }
  while (cursor) {
    lineageRows.unshift(cursor);
    cursor = cursor.parent_group_id
      ? await getGroupRowById(Number(cursor.parent_group_id))
      : null;
  }

  const mergedByKey = new Map();
  const discardedPropertyKeys = new Set();

  for (const groupRow of lineageRows) {
    const materialRow = await getGroupMaterialRowByGroupId(groupRow.id);
    if (!materialRow) {
      continue;
    }
    const governance = await getMaterialGroupGovernance(materialRow.id);
    for (const discardedKey of governance.discardedPropertyKeys || []) {
      discardedPropertyKeys.add(normalizePropertyKey(discardedKey));
      mergedByKey.delete(normalizePropertyKey(discardedKey));
    }
    for (const rawDraft of governance.propertyDrafts || []) {
      const draft = normalizeGroupPropertyDraft(rawDraft);
      if (!draft) {
        continue;
      }
      const propertyKey = draft.propertyKey;
      if (discardedPropertyKeys.has(propertyKey)) {
        continue;
      }
      mergedByKey.set(propertyKey, {
        name: draft.displayName,
        propertyKey,
        inputType: draft.inputType,
        mandatory: draft.mandatory,
        sourceType: draft.sourceType === 'manual' ? 'inherited_group' : draft.sourceType,
        state: draft.state,
        unitId: draft.unitId,
        unitSymbol: draft.unitSymbol,
        unitLabel: draft.unitLabel,
        sourceGroupId: draft.sourceGroupId || groupRow.id,
        sourceGroupName: draft.sourceGroupName || groupRow.name || '',
        overrideLocked: draft.overrideLocked,
        hasTypeConflict: draft.hasTypeConflict,
        coverageCount: draft.coverageCount,
        selectedItemCountAtResolution: draft.selectedItemCountAtResolution,
        resolutionSource: draft.resolutionSource,
        sources: (Array.isArray(rawDraft.sources) ? rawDraft.sources : []).map((source) => ({
          itemId: Number(source.itemId),
          itemName: source.itemName || null,
        })),
      });
    }
  }

  return {
    groupId: normalizedGroupId,
    propertyDrafts: [...mergedByKey.values()],
    discardedPropertyKeys: [...discardedPropertyKeys],
    lineageGroupIds: lineageRows.map((row) => Number(row.id)),
    lineageGroupNames: lineageRows.map((row) => row.name || ''),
  };
}

function mergeInventorySetLines(lines = []) {
  const merged = new Map();
  for (const [index, rawLine] of (Array.isArray(lines) ? lines : []).entries()) {
    const itemId = Number(rawLine?.itemId || 0);
    const variationLeafNodeId = Number(rawLine?.variationLeafNodeId || 0);
    const quantity = Math.trunc(Number(rawLine?.quantity || 0));
    const position = Number.isFinite(Number(rawLine?.position))
      ? Number(rawLine.position)
      : index;
    if (!Number.isInteger(itemId) || itemId <= 0) {
      const error = new Error(`Set line ${index + 1} requires a valid item.`);
      error.statusCode = 400;
      throw error;
    }
    if (!Number.isInteger(variationLeafNodeId) || variationLeafNodeId < 0) {
      const error = new Error(`Set line ${index + 1} requires a valid variation path.`);
      error.statusCode = 400;
      throw error;
    }
    if (!Number.isInteger(quantity) || quantity <= 0) {
      const error = new Error(`Set line ${index + 1} requires quantity greater than 0.`);
      error.statusCode = 400;
      throw error;
    }
    const key = `${itemId}:${variationLeafNodeId}`;
    const existing = merged.get(key);
    merged.set(key, {
      itemId,
      variationLeafNodeId,
      quantity: (existing?.quantity || 0) + quantity,
      position: existing?.position ?? position,
    });
  }
  return [...merged.values()].sort((a, b) => a.position - b.position);
}

async function getInventorySetLineDtos(setId) {
  const rows = await all(
    `
    SELECT
      lines.*,
      items.name AS item_name,
      items.display_name AS item_display_name
    FROM inventory_set_lines lines
    INNER JOIN items ON items.id = lines.item_id
    WHERE lines.set_id = ?
    ORDER BY lines.position ASC, lines.id ASC
    `,
    [setId],
  );
  const lines = [];
  for (const row of rows) {
    const itemTree = await getItemVariationTree(Number(row.item_id));
    const selection = activeValueSelectionForLeaf(
      itemTree,
      Number(row.variation_leaf_node_id),
    );
    lines.push({
      id: row.id,
      itemId: Number(row.item_id || 0),
      variationLeafNodeId: Number(row.variation_leaf_node_id || 0),
      quantity: Number(row.quantity || 0),
      position: Number(row.position || 0),
      itemName: row.item_name || '',
      itemDisplayName: row.item_display_name || row.item_name || '',
      variationPathLabel: selection ? buildVariationPathLabel(selection.segments) : 'Base item',
      variationPathNodeIds: selection?.nodeIds || [],
    });
  }
  return lines;
}

async function getInventorySetById(setId) {
  const row = await get(
    `
    SELECT
      inventory_sets.*,
      COALESCE((
        SELECT SUM(quantity)
        FROM inventory_set_lines
        WHERE inventory_set_lines.set_id = inventory_sets.id
      ), 0) AS total_item_count
    FROM inventory_sets
    WHERE inventory_sets.id = ?
    `,
    [setId],
  );
  if (!row) {
    return null;
  }
  return rowToInventorySetDto(row, await getInventorySetLineDtos(row.id));
}

async function getInventorySets() {
  const rows = await all(
    `
    SELECT
      inventory_sets.*,
      COALESCE((
        SELECT SUM(quantity)
        FROM inventory_set_lines
        WHERE inventory_set_lines.set_id = inventory_sets.id
      ), 0) AS total_item_count
    FROM inventory_sets
    ORDER BY LOWER(inventory_sets.name) ASC, inventory_sets.id ASC
    `,
  );
  const sets = [];
  for (const row of rows) {
    sets.push(await getInventorySetById(row.id));
  }
  return sets.filter(Boolean);
}

async function validateInventorySetLine(line) {
  const itemId = Number(line.itemId || 0);
  const variationLeafNodeId = Number(line.variationLeafNodeId || 0);
  const quantity = Math.trunc(Number(line.quantity || 0));
  if (!Number.isInteger(itemId) || itemId <= 0) {
    const error = new Error('Each set line requires a valid item.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isInteger(variationLeafNodeId) || variationLeafNodeId < 0) {
    const error = new Error('Each set line requires a valid variation path.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isInteger(quantity) || quantity <= 0) {
    const error = new Error('Each set line requires quantity greater than 0.');
    error.statusCode = 400;
    throw error;
  }
  const item = await getItemRowById(itemId);
  if (!item || item.is_archived) {
    const error = new Error('Selected item is not available.');
    error.statusCode = 400;
    throw error;
  }
  const itemTree = await getItemVariationTree(itemId);
  const hasOrderableLeaves = activeTopLevelVariationProperties(itemTree).some((propertyNode) =>
    activeChildrenForNode(propertyNode).some((child) => String(child.kind) === 'value'),
  );
  if (variationLeafNodeId === 0) {
    if (hasOrderableLeaves) {
      const error = new Error('Each set line requires a valid variation path.');
      error.statusCode = 400;
      throw error;
    }
    return {
      itemId,
      variationLeafNodeId: 0,
      quantity,
      position: Number(line.position || 0),
    };
  }
  const leafNode = await get(
    `
    SELECT id, item_id, kind, is_archived
    FROM item_variation_nodes
    WHERE id = ?
    `,
    [variationLeafNodeId],
  );
  if (
    !leafNode ||
    Number(leafNode.item_id) !== itemId ||
    String(leafNode.kind || '') !== 'value' ||
    Number(leafNode.is_archived || 0) === 1
  ) {
    const error = new Error('Selected variation path is not valid for this item.');
    error.statusCode = 400;
    throw error;
  }
  const selection = activeValueSelectionForLeaf(
    itemTree,
    variationLeafNodeId,
  );
  if (!selection) {
    const error = new Error('Selected variation path is incomplete for this item.');
    error.statusCode = 400;
    throw error;
  }
  return {
    itemId,
    variationLeafNodeId,
    quantity,
    position: Number(line.position || 0),
  };
}

async function saveInventorySet(payload = {}) {
  const id = payload.id == null ? null : Number(payload.id);
  const name = String(payload.name || '').trim();
  if (!name) {
    const error = new Error('Set name is required.');
    error.statusCode = 400;
    throw error;
  }
  const mergedLines = mergeInventorySetLines(payload.lines || []);
  if (mergedLines.length === 0) {
    const error = new Error('Add at least one item to the set.');
    error.statusCode = 400;
    throw error;
  }
  const validatedLines = [];
  for (const [index, line] of mergedLines.entries()) {
    validatedLines.push(
      await validateInventorySetLine({
        ...line,
        position: index,
      }),
    );
  }
  const now = new Date().toISOString();
  await run('BEGIN');
  try {
    let setId = id;
    if (setId == null) {
      const result = await run(
        'INSERT INTO inventory_sets (name, created_at, updated_at) VALUES (?, ?, ?)',
        [name, now, now],
      );
      setId = result.lastID;
    } else {
      const existing = await get(
        'SELECT id FROM inventory_sets WHERE id = ?',
        [setId],
      );
      if (!existing) {
        const error = new Error('Set not found.');
        error.statusCode = 404;
        throw error;
      }
      await run(
        'UPDATE inventory_sets SET name = ?, updated_at = ? WHERE id = ?',
        [name, now, setId],
      );
      await run('DELETE FROM inventory_set_lines WHERE set_id = ?', [setId]);
    }
    for (const line of validatedLines) {
      await run(
        `
        INSERT INTO inventory_set_lines (
          set_id, item_id, variation_leaf_node_id, quantity, position
        ) VALUES (?, ?, ?, ?, ?)
        `,
        [
          setId,
          line.itemId,
          line.variationLeafNodeId === 0 ? null : line.variationLeafNodeId,
          line.quantity,
          line.position,
        ],
      );
    }
    await run('COMMIT');
    return getInventorySetById(setId);
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function deleteInventorySet(setId) {
  const normalizedSetId = Number(setId);
  if (!Number.isInteger(normalizedSetId) || normalizedSetId <= 0) {
    const error = new Error('Valid set id is required.');
    error.statusCode = 400;
    throw error;
  }
  await run('DELETE FROM inventory_sets WHERE id = ?', [normalizedSetId]);
}

function normalizeGroupUnitGovernance(rawUnit) {
  const unitId = Number(rawUnit?.unitId);
  if (!Number.isInteger(unitId) || unitId <= 0) {
    return null;
  }
  const state = String(rawUnit?.state || 'active').trim().toLowerCase() === 'detached'
    ? 'detached'
    : 'active';
  return {
    unitId,
    state,
    isPrimary: Boolean(rawUnit?.isPrimary),
  };
}

function normalizeGroupUiPreferences(rawPreferences) {
  return {
    commonOnlyMode: rawPreferences?.commonOnlyMode !== false,
    showPartialMatches: rawPreferences?.showPartialMatches !== false,
  };
}

async function persistMaterialGroupGovernance(materialId, payload, now = new Date().toISOString()) {
  const selectedItemIds = Array.isArray(payload?.selectedItemIds)
    ? [...new Set(
      payload.selectedItemIds
        .map((id) => Number(id))
        .filter((id) => Number.isInteger(id) && id > 0),
    )]
    : [];
  const draftsInput = Array.isArray(payload?.propertyDrafts) ? payload.propertyDrafts : [];
  const unitGovernanceInput = Array.isArray(payload?.unitGovernance)
    ? payload.unitGovernance
    : [];
  const unitGovernance = unitGovernanceInput
    .map(normalizeGroupUnitGovernance)
    .filter(Boolean);
  const preferences = normalizeGroupUiPreferences(payload?.uiPreferences || {});
  const discardedPropertyKeys = normalizeDiscardedPropertyKeys(
    payload?.discardedPropertyKeys,
  );
  const drafts = draftsInput
    .map(normalizeGroupPropertyDraft)
    .filter(Boolean);
  const dedupedDraftsByKey = new Map();
  for (const draft of drafts) {
    if (!dedupedDraftsByKey.has(draft.propertyKey)) {
      dedupedDraftsByKey.set(draft.propertyKey, draft);
    }
  }
  const dedupedDrafts = [...dedupedDraftsByKey.values()];

  await run('DELETE FROM material_group_item_links WHERE material_id = ?', [materialId]);
  await run('DELETE FROM material_group_properties WHERE material_id = ?', [materialId]);
  await run('DELETE FROM material_group_units WHERE material_id = ?', [materialId]);
  await run('DELETE FROM material_group_preferences WHERE material_id = ?', [materialId]);

  for (let index = 0; index < selectedItemIds.length; index += 1) {
    await run(
      `
      INSERT INTO material_group_item_links (material_id, item_id, sort_order, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      `,
      [materialId, selectedItemIds[index], index, now, now],
    );
  }

  for (const draft of dedupedDrafts) {
    await run(
      `
      INSERT INTO material_group_properties (
        material_id, property_key, display_name, input_type, mandatory,
        source_type, source_item_ids_json, state, override_locked, has_type_conflict,
        coverage_count, selected_item_count_at_resolution, resolution_source,
        unit_id, unit_symbol, unit_label, source_group_id, source_group_name,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        materialId,
        draft.propertyKey,
        draft.displayName,
        draft.inputType,
        draft.mandatory ? 1 : 0,
        draft.sourceType,
        JSON.stringify(draft.sourceItemIds),
        draft.state,
        draft.overrideLocked ? 1 : 0,
        draft.hasTypeConflict ? 1 : 0,
        draft.coverageCount,
        draft.selectedItemCountAtResolution,
        draft.resolutionSource,
        draft.unitId,
        draft.unitSymbol,
        draft.unitLabel,
        draft.sourceGroupId,
        draft.sourceGroupName,
        now,
        now,
      ],
    );
  }

  for (const unitRow of unitGovernance) {
    await run(
      `
      INSERT INTO material_group_units (
        material_id, unit_id, state, is_primary, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      `,
      [
        materialId,
        unitRow.unitId,
        unitRow.state,
        unitRow.isPrimary ? 1 : 0,
        now,
        now,
      ],
    );
  }

  await run(
    `
    INSERT INTO material_group_preferences (
      material_id, common_only_mode, show_partial_matches, discarded_property_keys_json, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?)
    `,
    [
      materialId,
      preferences.commonOnlyMode ? 1 : 0,
      preferences.showPartialMatches ? 1 : 0,
      JSON.stringify(discardedPropertyKeys),
      now,
      now,
    ],
  );
}

async function getMaterialGroupGovernance(materialId) {
  const itemLinks = await all(
    `
    SELECT link.item_id, link.sort_order, item.display_name, item.name
    FROM material_group_item_links AS link
    LEFT JOIN items AS item ON item.id = link.item_id
    WHERE link.material_id = ?
    ORDER BY link.sort_order ASC, link.id ASC
    `,
    [materialId],
  );

  const properties = await all(
    `
    SELECT *
    FROM material_group_properties
    WHERE material_id = ?
    ORDER BY id ASC
    `,
    [materialId],
  );
  const units = await all(
    `
    SELECT *
    FROM material_group_units
    WHERE material_id = ?
    ORDER BY is_primary DESC, id ASC
    `,
    [materialId],
  );
  const preferencesRow = await get(
    `
    SELECT *
    FROM material_group_preferences
    WHERE material_id = ?
    LIMIT 1
    `,
    [materialId],
  );

  const selectedItemIds = itemLinks.map((row) => Number(row.item_id)).filter(Boolean);
  const selectedItems = itemLinks.map((row) => ({
    itemId: Number(row.item_id),
    itemName: row.display_name || row.name || `Item #${row.item_id}`,
    sortOrder: Number(row.sort_order || 0),
  }));
  const propertyDrafts = properties.map((row) => {
    const sourceItemIds = parseJson(row.source_item_ids_json, [])
      .map((id) => Number(id))
      .filter((id) => Number.isInteger(id) && id > 0);
    const sourceNameById = new Map(selectedItems.map((item) => [item.itemId, item.itemName]));
    const sources = sourceItemIds.map((itemId) => ({
      itemId,
      itemName: sourceNameById.get(itemId) || null,
    }));
    return {
      propertyKey: row.property_key || '',
      name: row.display_name || '',
      inputType: row.input_type || 'Text',
      mandatory: Number(row.mandatory || 0) === 1,
      sourceType: row.source_type || 'manual',
      state: row.state || 'active',
      unitId: row.unit_id ? Number(row.unit_id) : null,
      unitSymbol: row.unit_symbol || null,
      unitLabel: row.unit_label || null,
      sourceGroupId: row.source_group_id ? Number(row.source_group_id) : null,
      sourceGroupName: row.source_group_name || null,
      overrideLocked: Number(row.override_locked || 0) === 1,
      hasTypeConflict: Number(row.has_type_conflict || 0) === 1,
      coverageCount: Number(row.coverage_count || 0),
      selectedItemCountAtResolution: Number(row.selected_item_count_at_resolution || 0),
      resolutionSource: row.resolution_source || null,
      sources,
    };
  });
  const unitGovernance = units.map((row) => ({
    unitId: Number(row.unit_id),
    state: row.state === 'detached' ? 'detached' : 'active',
    isPrimary: Number(row.is_primary || 0) === 1,
  }));
  const uiPreferences = {
    commonOnlyMode: Number(preferencesRow?.common_only_mode ?? 1) === 1,
    showPartialMatches: Number(preferencesRow?.show_partial_matches ?? 1) === 1,
  };
  const discardedPropertyKeys = normalizeDiscardedPropertyKeys(
    parseJson(preferencesRow?.discarded_property_keys_json, []),
  );

  return {
    selectedItemIds,
    selectedItems,
    propertyDrafts,
    unitGovernance,
    uiPreferences,
    discardedPropertyKeys,
  };
}

async function incrementMaterialScanCount(barcode) {
  const row = await getMaterialRowByBarcode(barcode);
  if (!row) {
    return null;
  }
  const now = new Date().toISOString();
  await run('INSERT INTO scan_history (barcode, scanned_at) VALUES (?, ?)', [
    row.barcode,
    now,
  ]);
  await run(
    'UPDATE materials SET scan_count = scan_count + 1, updated_at = ?, last_scanned_at = ? WHERE id = ?',
    [now, now, row.id],
  );
  await logMaterialActivity({
    barcode: row.barcode,
    type: 'scan',
    label: 'Material scanned',
    description: `Scan trace updated to ${Number(row.scan_count || 0) + 1} total scans.`,
    actor: 'Scanner',
    createdAt: now,
  });
  return get('SELECT * FROM materials WHERE id = ?', [row.id]);
}

async function getMaterialActivity(barcode) {
  const material = await getMaterialRowByBarcode(barcode);
  if (!material) {
    return [];
  }
  return all(
    `
    SELECT *
    FROM material_activity
    WHERE barcode = ?
    ORDER BY datetime(created_at) DESC, id DESC
    `,
    [material.barcode],
  );
}

function normalizeMovementType(value = '') {
  const allowed = new Set([
    'receive',
    'issue',
    'transfer',
    'adjust',
    'reserve',
    'release',
    'consume',
    'split',
    'merge',
  ]);
  const normalized = String(value || '').trim().toLowerCase();
  return allowed.has(normalized) ? normalized : 'adjust';
}

function normalizeActorLabel(actor, fallback = 'System') {
  if (actor && typeof actor === 'object') {
    const name = String(actor.name || '').trim();
    if (name) {
      return name;
    }
  }
  const text = String(actor || '').trim();
  return text || fallback;
}

async function getInventoryStockPosition(materialBarcode, locationId, lotCode) {
  return get(
    `
    SELECT *
    FROM inventory_stock_positions
    WHERE material_barcode = ? AND location_id = ? AND lot_code = ?
    LIMIT 1
    `,
    [materialBarcode, locationId, lotCode],
  );
}

async function assertInventoryQuantityAvailable({
  materialBarcode,
  locationId,
  lotCode,
  qty,
  column = 'on_hand_qty',
  label = 'stock',
}) {
  const position = await getInventoryStockPosition(materialBarcode, locationId, lotCode);
  const available = Number(position?.[column] || 0);
  if (qty > available) {
    const error = new Error(`Insufficient ${label}. Available: ${available}, requested: ${qty}.`);
    error.statusCode = 409;
    throw error;
  }
}

function normalizeMaterialClassFromType(type = '') {
  const value = String(type || '').trim().toLowerCase();
  if (value.includes('packaging')) {
    return 'packaging';
  }
  if (value.includes('finished')) {
    return 'finished_good';
  }
  if (value.includes('wip') || value.includes('semi')) {
    return 'wip';
  }
  if (value.includes('chemical') || value.includes('consumable')) {
    return 'consumable';
  }
  return 'raw_material';
}

async function upsertInventoryStockPosition({
  materialBarcode,
  locationId = 'MAIN',
  lotCode = '',
  unitId = null,
  onHandDelta = 0,
  reservedDelta = 0,
  damagedDelta = 0,
  now = new Date().toISOString(),
}) {
  const normalizedLocation = String(locationId || 'MAIN').trim() || 'MAIN';
  const normalizedLot = String(lotCode || '').trim();
  const existing = await get(
    `
    SELECT *
    FROM inventory_stock_positions
    WHERE material_barcode = ? AND location_id = ? AND lot_code = ?
    LIMIT 1
    `,
    [materialBarcode, normalizedLocation, normalizedLot],
  );

  if (!existing) {
    const nextOnHand = Number(onHandDelta || 0);
    const nextReserved = Number(reservedDelta || 0);
    const nextDamaged = Number(damagedDelta || 0);
    if (nextOnHand < 0 || nextReserved < 0 || nextDamaged < 0) {
      const error = new Error('Movement would result in negative stock.');
      error.statusCode = 422;
      throw error;
    }
    await run(
      `
      INSERT INTO inventory_stock_positions (
        material_barcode, location_id, lot_code, unit_id,
        on_hand_qty, reserved_qty, damaged_qty, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        materialBarcode,
        normalizedLocation,
        normalizedLot,
        unitId,
        nextOnHand,
        nextReserved,
        nextDamaged,
        now,
      ],
    );
    return;
  }

  const nextOnHand = Number(existing.on_hand_qty || 0) + Number(onHandDelta || 0);
  const nextReserved = Number(existing.reserved_qty || 0) + Number(reservedDelta || 0);
  const nextDamaged = Number(existing.damaged_qty || 0) + Number(damagedDelta || 0);
  if (nextOnHand < 0 || nextReserved < 0 || nextDamaged < 0) {
    const error = new Error('Movement would result in negative stock.');
    error.statusCode = 422;
    throw error;
  }
  await run(
    `
    UPDATE inventory_stock_positions
    SET unit_id = COALESCE(?, unit_id),
        on_hand_qty = ?,
        reserved_qty = ?,
        damaged_qty = ?,
        updated_at = ?
    WHERE id = ?
    `,
    [unitId, nextOnHand, nextReserved, nextDamaged, now, existing.id],
  );
}

async function recomputeMaterialInventorySummary(materialBarcode, now = new Date().toISOString()) {
  const material = await getMaterialRowByBarcode(materialBarcode);
  if (!material) {
    return null;
  }

  const stockRows = await all(
    'SELECT * FROM inventory_stock_positions WHERE material_barcode = ?',
    [material.barcode],
  );
  const reservationRows = await all(
    "SELECT * FROM inventory_reservations WHERE material_barcode = ? AND status = 'active'",
    [material.barcode],
  );
  const openAlerts = await all(
    'SELECT * FROM inventory_alerts WHERE material_barcode = ? AND is_open = 1',
    [material.barcode],
  );

  const onHand = stockRows.reduce((sum, row) => sum + Number(row.on_hand_qty || 0), 0);
  const reservedFromPositions = stockRows.reduce(
    (sum, row) => sum + Number(row.reserved_qty || 0),
    0,
  );
  const reservedFromReservations = reservationRows.reduce(
    (sum, row) => sum + Number(row.reserved_qty || 0),
    0,
  );
  const reserved = Math.max(reservedFromPositions, reservedFromReservations);
  const availableToPromise = onHand - reserved;
  const linkedOrderCount = material.linked_item_id
    ? Number(
        (
          await get(
            'SELECT COUNT(*) AS count FROM order_items WHERE item_id = ?',
            [material.linked_item_id],
          )
        )?.count || 0,
      )
    : 0;
  const linkedPipelineCount = Number(
    (
      await get(
        'SELECT COUNT(*) AS count FROM run_barcode_inputs WHERE barcode = ?',
        [material.barcode],
      )
    )?.count || 0,
  );
  const pendingAlertCount = openAlerts.length;
  const materialClass = normalizeMaterialClassFromType(material.type);
  const inventoryState = pendingAlertCount > 0 ? 'reserved' : 'available';
  const procurementState = onHand > 0 ? 'received_complete' : 'ordered';
  const traceabilityMode = materialClass === 'raw_material' ? 'lot_tracked' : 'bulk';

  await run(
    `
    UPDATE materials
    SET on_hand_qty = ?,
        reserved_qty = ?,
        available_to_promise_qty = ?,
        display_stock = ?,
        material_class = ?,
        inventory_state = ?,
        procurement_state = ?,
        traceability_mode = ?,
        linked_order_count = ?,
        linked_pipeline_count = ?,
        pending_alert_count = ?,
        updated_at = ?
    WHERE id = ?
    `,
    [
      onHand,
      reserved,
      availableToPromise,
      String(material.unit || '').trim()
        ? `${Number(onHand)} ${String(material.unit || '').trim()}`
        : `${Number(onHand)}`,
      materialClass,
      inventoryState,
      procurementState,
      traceabilityMode,
      linkedOrderCount,
      linkedPipelineCount,
      pendingAlertCount,
      now,
      material.id,
    ],
  );

  const lowStockThreshold = 100;
  const hasLowStock = onHand > 0 && availableToPromise <= lowStockThreshold;
  const existingLowStockAlert = openAlerts.find((alert) => alert.alert_type === 'low_stock');
  if (hasLowStock && !existingLowStockAlert) {
    await run(
      `
      INSERT INTO inventory_alerts (
        material_barcode, alert_type, severity, message, is_open, created_at, updated_at
      ) VALUES (?, 'low_stock', 'warning', ?, 1, ?, ?)
      `,
      [
        material.barcode,
        `Available stock is low (${availableToPromise.toFixed(2)}).`,
        now,
        now,
      ],
    );
  } else if (!hasLowStock && existingLowStockAlert) {
    await run(
      'UPDATE inventory_alerts SET is_open = 0, updated_at = ? WHERE id = ?',
      [now, existingLowStockAlert.id],
    );
  }

  return getMaterialRowByBarcode(material.barcode);
}

async function getMaterialControlTowerDetail(barcode) {
  const material = await getMaterialRowByBarcode(barcode);
  if (!material) {
    return null;
  }
  const refreshed = (await recomputeMaterialInventorySummary(material.barcode)) || material;
  const stockRows = await all(
    `
    SELECT *
    FROM inventory_stock_positions
    WHERE material_barcode = ?
    ORDER BY datetime(updated_at) DESC, id DESC
    `,
    [material.barcode],
  );
  const movementRows = await all(
    `
    SELECT *
    FROM inventory_movements
    WHERE material_barcode = ?
    ORDER BY datetime(created_at) DESC
    LIMIT 20
    `,
    [material.barcode],
  );
  const challanIds = [
    ...new Set(
      movementRows
        .map((row) => Number(row.source_challan_id || 0))
        .filter((id) => Number.isFinite(id) && id > 0),
    ),
  ];
  const challanById = new Map();
  if (challanIds.length > 0) {
    const placeholders = challanIds.map(() => '?').join(', ');
    const challanRows = await all(
      `
      SELECT id, challan_no, type
      FROM delivery_challans
      WHERE id IN (${placeholders})
      `,
      challanIds,
    );
    for (const row of challanRows) {
      challanById.set(Number(row.id), row);
    }
  }
  const reservationRows = await all(
    `
    SELECT *
    FROM inventory_reservations
    WHERE material_barcode = ?
    ORDER BY datetime(updated_at) DESC, id DESC
    `,
    [material.barcode],
  );
  const alertRows = await all(
    `
    SELECT *
    FROM inventory_alerts
    WHERE material_barcode = ?
    ORDER BY is_open DESC, datetime(updated_at) DESC, id DESC
    `,
    [material.barcode],
  );
  const linkedOrderDemand = refreshed.linked_item_id
    ? Number(
        (
          await get('SELECT COALESCE(SUM(quantity), 0) AS qty FROM order_items WHERE item_id = ?', [
            refreshed.linked_item_id,
          ])
        )?.qty || 0,
      )
    : 0;
  const linkedPipelineDemand = Number(
    (
      await get(
        'SELECT COUNT(*) AS count FROM run_barcode_inputs WHERE barcode = ?',
        [material.barcode],
      )
    )?.count || 0,
  );

  const activePipelineInput = await get(
    'SELECT run_id, node_id FROM run_barcode_inputs WHERE barcode = ? ORDER BY scanned_at DESC LIMIT 1',
    [material.barcode]
  );
  
  let activePipelineRun = null;
  if (activePipelineInput) {
    const runId = activePipelineInput.run_id;
    const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [runId]);
    if (runRow) {
       const orderRows = await all('SELECT order_item_id FROM order_pipeline_assignments WHERE pipeline_run_id = ?', [runId]);
       const orderIds = orderRows.map(r => r.order_item_id);
       
       const template = await get('SELECT nodes_json, stage_labels_json FROM pipeline_templates WHERE id = ?', [runRow.template_id]);
       const nodes = template ? parseJson(template.nodes_json, []) : [];
       const stageLabels = template ? parseJson(template.stage_labels_json, []) : [];
       const node = nodes.find(n => n.id === activePipelineInput.node_id);
       
       let machine = null;
       if (node?.machineId) {
          const m = await get('SELECT name, primary_photo_url FROM machines WHERE asset_id = ? OR name = ?', [node.machineId, node.machineId]);
          if (m) machine = { name: m.name, photoUrls: m.primary_photo_url ? [m.primary_photo_url] : [] };
       }
       
       let die = null;
       if (node?.dieId) {
          const d = await get('SELECT tool_code, photo_urls FROM dies WHERE tool_code = ?', [node.dieId]);
          if (d) die = { toolCode: d.tool_code, photoUrls: parseJson(d.photo_urls, []) };
       }
       
       const stages = await all('SELECT * FROM stage_reconciliations WHERE run_id = ?', [runId]);
       
       activePipelineRun = {
         id: runRow.id,
         name: runRow.name || runRow.id,
         status: runRow.status,
         machine,
         die,
         orderIds,
         currentNodeId: activePipelineInput.node_id,
         stages: stages.map(s => ({
            nodeId: s.node_id,
            producedQty: s.produced_qty || 0,
            expectedQty: s.expected_qty || 0,
            rejectedQty: s.rejected_qty || 0
         })),
         nodes,
         stageLabels
       };
    }
  }

  return {
    material: rowToMaterialDto(refreshed),
    activePipelineRun,
    stockPositions: stockRows.map((row) => ({
      locationId: row.location_id || 'MAIN',
      locationName: row.location_id || 'Main Warehouse',
      lotCode: row.lot_code || '',
      unitId: row.unit_id || null,
      onHandQty: Number(row.on_hand_qty || 0),
      reservedQty: Number(row.reserved_qty || 0),
      damagedQty: Number(row.damaged_qty || 0),
      updatedAt: row.updated_at,
    })),
    movements: movementRows.map((row) => ({
      id: String(row.id || ''),
      materialBarcode: row.material_barcode || '',
      movementType: row.movement_type || 'adjust',
      qty: Number(row.qty || 0),
      primaryQty: Number(row.primary_qty || row.qty || 0),
      uom: String(row.uom || '').trim(),
      fromLocationId: row.from_location_id || null,
      toLocationId: row.to_location_id || null,
      reasonCode: row.reason_code || null,
      referenceType: row.reference_type || null,
      referenceId: row.reference_id || null,
      sourceChallanId: row.source_challan_id == null ? null : Number(row.source_challan_id || 0),
      sourceChallanType: row.source_challan_type || null,
      sourceChallanLineId: row.source_challan_line_id == null ? null : Number(row.source_challan_line_id || 0),
      reversesMovementId: row.reverses_movement_id || null,
      sourceLabel: (() => {
        const linkedChallan = challanById.get(Number(row.source_challan_id || 0));
        if (linkedChallan) {
          const typeLabel = normalizeChallanType(linkedChallan.type) === 'reception' ? 'Reception' : 'Delivery';
          if (row.reverses_movement_id || row.reference_type === 'challan-cancellation') {
            return `Cancellation of ${typeLabel} Challan ${linkedChallan.challan_no || `#${linkedChallan.id}`}`;
          }
          return `${typeLabel} Challan ${linkedChallan.challan_no || `#${linkedChallan.id}`}`;
        }
        const referenceType = String(row.reference_type || '').trim();
        const referenceId = String(row.reference_id || '').trim();
        if (referenceType && referenceId) {
          return `${referenceType} ${referenceId}`;
        }
        if (referenceType) {
          return referenceType;
        }
        return null;
      })(),
      actor: row.actor || '',
      createdAt: row.created_at,
    })),
    reservations: reservationRows.map((row) => ({
      referenceType: row.reference_type || '',
      referenceId: row.reference_id || '',
      reservedQty: Number(row.reserved_qty || 0),
      status: row.status || 'active',
    })),
    alerts: alertRows.map((row) => ({
      alertType: row.alert_type || '',
      severity: row.severity || 'warning',
      message: row.message || '',
      isOpen: Number(row.is_open || 0) === 1,
    })),
    linkedOrderDemand,
    linkedPipelineDemand,
    pendingAlertsCount: Number(refreshed.pending_alert_count || 0),
  };
}

async function getInventoryHealthSummary() {
  const lowStockCount = Number(
    (
      await get(
        'SELECT COUNT(*) AS count FROM materials WHERE on_hand_qty > 0 AND available_to_promise_qty <= 100',
      )
    )?.count || 0,
  );
  const reservedRiskCount = Number(
    (
      await get(
        'SELECT COUNT(*) AS count FROM materials WHERE reserved_qty > on_hand_qty AND reserved_qty > 0',
      )
    )?.count || 0,
  );
  const incomingTodayCount = Number(
    (
      await get(
        "SELECT COUNT(*) AS count FROM inventory_movements WHERE movement_type = 'receive' AND created_at >= ?",
        [new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()],
      )
    )?.count || 0,
  );
  const qualityHoldCount = Number(
    (
      await get("SELECT COUNT(*) AS count FROM materials WHERE inventory_state = 'quality_hold'")
    )?.count || 0,
  );
  const pendingReconciliationCount = Number(
    (
      await get('SELECT COUNT(*) AS count FROM inventory_alerts WHERE is_open = 1')
    )?.count || 0,
  );

  return {
    lowStockCount,
    reservedRiskCount,
    incomingTodayCount,
    qualityHoldCount,
    unitMismatchCount: pendingReconciliationCount,
    pendingReconciliationCount,
  };
}

async function applyInventoryMovementCore(payload, { useTransaction = true } = {}) {
  const barcode = normalizeBarcode(payload?.barcode || '');
  const movementType = normalizeMovementType(payload?.movementType || 'adjust');
  const qty = Number(payload?.qty || 0);
  if (!barcode || !Number.isFinite(qty) || qty <= 0) {
    const error = new Error('barcode, movementType, and qty (> 0) are required.');
    error.statusCode = 400;
    throw error;
  }

  const material = await getMaterialRowByBarcode(barcode);
  if (!material) {
    const error = new Error('Material not found.');
    error.statusCode = 404;
    throw error;
  }

  const now = new Date().toISOString();
  const movementId = `mov-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  const fromLocationId = String(payload?.fromLocationId || '').trim() || null;
  const defaultLocationId = String(material.location || '').trim() || 'MAIN';
  const explicitLot = String(payload?.lotCode || '').trim();
  let toLocationId = String(payload?.toLocationId || '').trim() || defaultLocationId;
  let lotCode = explicitLot || barcode;

  // Issuing/consuming without a caller-specified lot used to target a phantom
  // lot==barcode bucket that's almost always empty — real stock sits under its
  // receiving lot code. Draw from the position that actually holds stock so the
  // assignable quantity matches what inventory shows.
  // ponytail: picks the single fullest lot; add FIFO multi-lot consume only if a
  // single request ever needs to span more than one lot.
  if (!explicitLot && (movementType === 'issue' || movementType === 'consume')) {
    const stockedPosition = await get(
      `
      SELECT location_id, lot_code
      FROM inventory_stock_positions
      WHERE material_barcode = ? AND on_hand_qty > 0
      ORDER BY on_hand_qty DESC
      LIMIT 1
      `,
      [barcode],
    );
    if (stockedPosition) {
      toLocationId = stockedPosition.location_id;
      lotCode = stockedPosition.lot_code;
    }
  }
  const actor = normalizeActorLabel(payload?.actor, 'Demo Admin');
  const sourceChallanId = payload?.sourceChallanId == null
    ? null
    : Number(payload.sourceChallanId || 0) || null;
  const sourceChallanType = payload?.sourceChallanType == null
    ? null
    : normalizeChallanType(payload.sourceChallanType, '');
  const sourceChallanLineId = payload?.sourceChallanLineId == null
    ? null
    : Number(payload.sourceChallanLineId || 0) || null;
  const reversesMovementId = String(payload?.reversesMovementId || '').trim() || null;
  const referenceType = String(payload?.referenceType || '').trim() || null;
  const referenceId = String(payload?.referenceId || '').trim() || null;
  const primaryQty = Number(payload?.primaryQty || qty);
  const uom = String(payload?.uom || '').trim() || String(material.unit || '').trim() || 'units';
  const linkedStockItemId = Number(material.linked_item_id || 0) || null;
  const linkedStockLeafNodeId = Number(material.linked_variation_leaf_node_id || 0) || null;
  const hasChallanProvenance =
    sourceChallanId != null &&
    !!sourceChallanType &&
    sourceChallanLineId != null;
  const hasManualProvenance = !!referenceType && !!referenceId;

  if (movementType === 'transfer' && !fromLocationId) {
    const error = new Error('fromLocationId is required for transfer movements.');
    error.statusCode = 400;
    throw error;
  }
  if (movementType === 'receive' && !hasChallanProvenance && !hasManualProvenance) {
    const error = new Error('Receive movements require challan provenance or a manual reference.');
    error.statusCode = 400;
    throw error;
  }

  if (useTransaction) {
    await run('BEGIN TRANSACTION');
  }
  try {
    if (movementType === 'receive') {
      await upsertInventoryStockPosition({
        materialBarcode: material.barcode,
        locationId: toLocationId,
        lotCode,
        unitId: material.unit_id || null,
        onHandDelta: qty,
        now,
      });
    } else if (movementType === 'transfer') {
      await assertInventoryQuantityAvailable({
        materialBarcode: material.barcode,
        locationId: fromLocationId,
        lotCode,
        qty,
      });
      await upsertInventoryStockPosition({
        materialBarcode: material.barcode,
        locationId: fromLocationId,
        lotCode,
        unitId: material.unit_id || null,
        onHandDelta: -qty,
        now,
      });
      await upsertInventoryStockPosition({
        materialBarcode: material.barcode,
        locationId: toLocationId,
        lotCode,
        unitId: material.unit_id || null,
        onHandDelta: qty,
        now,
      });
    } else if (movementType === 'reserve') {
      await upsertInventoryStockPosition({
        materialBarcode: material.barcode,
        locationId: toLocationId,
        lotCode,
        unitId: material.unit_id || null,
        reservedDelta: qty,
        now,
      });
      await run(
        `
        INSERT INTO inventory_reservations (
          material_barcode, reference_type, reference_id, reserved_qty, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, 'active', ?, ?)
        `,
        [
          material.barcode,
          String(payload?.referenceType || 'manual').trim() || 'manual',
          String(payload?.referenceId || movementId).trim() || movementId,
          qty,
          now,
          now,
        ],
      );
    } else if (movementType === 'release') {
      await assertInventoryQuantityAvailable({
        materialBarcode: material.barcode,
        locationId: toLocationId,
        lotCode,
        qty,
        column: 'reserved_qty',
        label: 'reserved stock',
      });
      await upsertInventoryStockPosition({
        materialBarcode: material.barcode,
        locationId: toLocationId,
        lotCode,
        unitId: material.unit_id || null,
        reservedDelta: -qty,
        now,
      });
      const activeReservation = await get(
        `
        SELECT *
        FROM inventory_reservations
        WHERE material_barcode = ? AND status = 'active'
        ORDER BY datetime(updated_at) DESC, id DESC
        LIMIT 1
        `,
        [material.barcode],
      );
      if (activeReservation) {
        const nextQty = Math.max(0, Number(activeReservation.reserved_qty || 0) - qty);
        await run(
          `
          UPDATE inventory_reservations
          SET reserved_qty = ?, status = ?, updated_at = ?
          WHERE id = ?
          `,
          [nextQty, nextQty <= 0 ? 'released' : 'active', now, activeReservation.id],
        );
      }
    } else {
      if (movementType === 'issue' || movementType === 'consume') {
        await assertInventoryQuantityAvailable({
          materialBarcode: material.barcode,
          locationId: toLocationId,
          lotCode,
          qty,
        });
      }
      const onHandDelta = movementType === 'issue' || movementType === 'consume'
        ? -qty
        : qty;
      await upsertInventoryStockPosition({
        materialBarcode: material.barcode,
        locationId: toLocationId,
        lotCode,
        unitId: material.unit_id || null,
        onHandDelta,
        now,
      });
    }

    await run(
      `
      INSERT INTO inventory_movements (
        id, material_barcode, movement_type, qty, primary_qty, uom, from_location_id, to_location_id,
        reason_code, reference_type, reference_id, source_challan_id, source_challan_type,
        source_challan_line_id, reverses_movement_id, actor, lot_code, created_at,
        item_id, variation_leaf_node_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        movementId,
        material.barcode,
        movementType,
        qty,
        primaryQty,
        uom,
        fromLocationId,
        toLocationId,
        String(payload?.reasonCode || '').trim() || null,
        referenceType,
        referenceId,
        sourceChallanId,
        sourceChallanType || null,
        sourceChallanLineId,
        reversesMovementId,
        actor,
        lotCode,
        now,
        linkedStockItemId,
        linkedStockLeafNodeId,
      ],
    );

    await recomputeMaterialInventorySummary(material.barcode, now);

    if (linkedStockItemId != null && linkedStockLeafNodeId != null) {
      if (movementType === 'receive' || (movementType === 'adjust' && qty > 0)) {
        await applyVariationStockDelta({
          itemId: linkedStockItemId,
          variationLeafNodeId: linkedStockLeafNodeId,
          locationId: toLocationId || 'MAIN',
          delta: qty,
          now,
        });
      } else if (movementType === 'issue' || movementType === 'consume') {
        await applyVariationStockDelta({
          itemId: linkedStockItemId,
          variationLeafNodeId: linkedStockLeafNodeId,
          locationId: toLocationId || 'MAIN',
          delta: -qty,
          now,
        });
      } else if (movementType === 'transfer') {
        await applyVariationStockDelta({
          itemId: linkedStockItemId,
          variationLeafNodeId: linkedStockLeafNodeId,
          locationId: fromLocationId || 'MAIN',
          delta: -qty,
          now,
        });
        await applyVariationStockDelta({
          itemId: linkedStockItemId,
          variationLeafNodeId: linkedStockLeafNodeId,
          locationId: toLocationId || 'MAIN',
          delta: qty,
          now,
        });
      }
    }

    await logMaterialActivity({
      barcode: material.barcode,
      type: movementType,
      label: 'Inventory movement posted',
      description: `${movementType} ${primaryQty.toFixed(2)} ${uom}.`,
      actor,
      createdAt: now,
    });
    if (useTransaction) {
      await run('COMMIT');
    }
  } catch (error) {
    if (useTransaction) {
      await run('ROLLBACK');
    }
    throw error;
  }

  return getMaterialControlTowerDetail(material.barcode);
}

async function applyInventoryMovement(payload) {
  return applyInventoryMovementCore(payload, { useTransaction: true });
}

async function updateMaterialGroupConfiguration(barcode, payload) {
  const material = await getMaterialRowByBarcode(barcode);
  if (!material) {
    throw new Error('Material not found.');
  }
  const now = new Date().toISOString();
  await run(
    'UPDATE materials SET group_mode = ?, inheritance_enabled = ?, updated_at = ? WHERE id = ?',
    [
      String(payload.groupMode ?? material.group_mode ?? '').trim() || null,
      payload.inheritanceEnabled == null
        ? Number(material.inheritance_enabled || 0)
        : (payload.inheritanceEnabled ? 1 : 0),
      now,
      material.id,
    ],
  );
  await persistMaterialGroupGovernance(material.id, payload, now);
  await logMaterialActivity({
    barcode: material.barcode,
    type: 'governanceUpdated',
    label: 'Inheritance governance updated',
    description: 'Group property inheritance configuration was updated.',
    actor: material.created_by || 'Demo Admin',
    createdAt: now,
  });
  return get('SELECT * FROM materials WHERE id = ?', [material.id]);
}

async function logMaterialActivity({
  barcode,
  type,
  label,
  description = '',
  actor = '',
  createdAt = new Date().toISOString(),
}) {
  await run(
    `
    INSERT INTO material_activity (
      barcode, event_type, event_label, event_description, actor, created_at
    ) VALUES (?, ?, ?, ?, ?, ?)
    `,
    [barcode, type, label, description, actor, createdAt],
  );
}

async function createChildMaterial(parentBarcode, payload) {
  const parent = await getMaterialRowByBarcode(parentBarcode);
  if (!parent || parent.kind !== 'parent') {
    throw new Error('Parent material not found.');
  }
  const actor = String(payload?.actor || '').trim() || parent.created_by || 'Demo Admin';

  const nextIndex = Number(parent.number_of_children || 0) + 1;
  const childBarcode = generateChildBarcode(parent.barcode, nextIndex);
  const createdAt = new Date().toISOString();
  const childDisplayStock = String(parent.unit || '').trim()
    ? `0 ${String(parent.unit || '').trim()}`
    : '0';

  await run(
    `
    INSERT INTO materials (
      barcode, name, type, grade, thickness, supplier, location, unit_id, unit, notes, group_mode, inheritance_enabled,
      created_at, kind, parent_barcode, number_of_children, linked_child_barcodes,
      scan_count, linked_group_id, linked_item_id, display_stock, created_by,
      workflow_status, updated_at, last_scanned_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'child', ?, 0, '[]', 0, NULL, NULL, ?, ?, ?, ?, NULL)
    `,
    [
      childBarcode,
      String(payload.name || '').trim(),
      parent.type || '',
      parent.grade || '',
      parent.thickness || '',
      parent.supplier || '',
      parent.location || '',
      parent.unit_id || null,
      parent.unit || '',
      String(payload.notes || '').trim(),
      parent.group_mode || null,
      Number(parent.inheritance_enabled || 0),
      createdAt,
      parent.barcode,
      childDisplayStock,
      actor,
      'notStarted',
      createdAt,
    ],
  );

  const linkedChildren = parseJson(parent.linked_child_barcodes, []);
  linkedChildren.push(childBarcode);
  await run(
    'UPDATE materials SET number_of_children = ?, linked_child_barcodes = ?, updated_at = ? WHERE id = ?',
    [linkedChildren.length, JSON.stringify(linkedChildren), createdAt, parent.id],
  );

  await logMaterialActivity({
    barcode: childBarcode,
    type: 'created',
    label: 'Sub-group created',
    description: `Created under parent ${parent.name || parent.barcode}.`,
    actor,
    createdAt,
  });
  await recomputeMaterialInventorySummary(childBarcode, createdAt);
  await recomputeMaterialInventorySummary(parent.barcode, createdAt);

  return getMaterialRowByBarcode(childBarcode);
}

async function updateMaterialRecord(barcode, payload) {
  const existing = await getMaterialRowByBarcode(barcode);
  if (!existing) {
    throw new Error('Material not found.');
  }

  const resolvedUnit = await resolveUnitPayload(payload);
  const now = new Date().toISOString();
  const actor = String(payload?.actor || '').trim() || existing.created_by || 'Demo Admin';
  const existingDisplayStock = String(existing.display_stock || '').trim();
  const nextDisplayStock = existingDisplayStock || (
    resolvedUnit.unit
      ? `${Number(existing.on_hand_qty || 0)} ${resolvedUnit.unit}`
      : `${Number(existing.on_hand_qty || 0)}`
  );
  await run(
    `
    UPDATE materials
    SET name = ?, type = ?, grade = ?, thickness = ?, supplier = ?, location = ?, unit_id = ?, unit = ?, notes = ?, group_mode = ?, inheritance_enabled = ?, display_stock = ?, updated_at = ?
    WHERE id = ?
    `,
    [
      String(payload.name || '').trim(),
      String(payload.type || '').trim(),
      String(payload.grade || '').trim(),
      String(payload.thickness || '').trim(),
      String(payload.supplier || '').trim(),
      String(payload.location || '').trim(),
      resolvedUnit.unitId,
      resolvedUnit.unit,
      String(payload.notes || '').trim(),
      String(payload.groupMode ?? existing.group_mode ?? '').trim() || null,
      payload.inheritanceEnabled == null
        ? Number(existing.inheritance_enabled || 0)
        : (payload.inheritanceEnabled ? 1 : 0),
      nextDisplayStock,
      now,
      existing.id,
    ],
  );
  await logMaterialActivity({
    barcode: existing.barcode,
    type: 'updated',
    label: 'Record updated',
    description: 'Material details were edited.',
    actor,
    createdAt: now,
  });
  await recomputeMaterialInventorySummary(existing.barcode, now);
  return get('SELECT * FROM materials WHERE id = ?', [existing.id]);
}

async function deleteMaterialRecord(barcode) {
  const existing = await getMaterialRowByBarcode(barcode);
  if (!existing) {
    throw new Error('Material not found.');
  }

  if (existing.kind === 'parent') {
    const childRows = await all('SELECT barcode FROM materials WHERE parent_barcode = ?', [
      existing.barcode,
    ]);
    for (const child of childRows) {
      await run('DELETE FROM scan_history WHERE barcode = ?', [child.barcode]);
      await run('DELETE FROM material_activity WHERE barcode = ?', [child.barcode]);
    }
    await run('DELETE FROM materials WHERE parent_barcode = ?', [existing.barcode]);
  } else if (existing.parent_barcode) {
    const parent = await getMaterialRowByBarcode(existing.parent_barcode);
    if (parent) {
      const linkedChildren = parseJson(parent.linked_child_barcodes, []).filter(
        (childBarcode) => childBarcode !== existing.barcode,
      );
      await run(
        'UPDATE materials SET number_of_children = ?, linked_child_barcodes = ? WHERE id = ?',
        [linkedChildren.length, JSON.stringify(linkedChildren), parent.id],
      );
    }
  }

  await run('DELETE FROM scan_history WHERE barcode = ?', [existing.barcode]);
  await run('DELETE FROM material_activity WHERE barcode = ?', [existing.barcode]);
  await run('DELETE FROM material_group_item_links WHERE material_id = ?', [existing.id]);
  await run('DELETE FROM material_group_properties WHERE material_id = ?', [existing.id]);
  await run('DELETE FROM material_group_units WHERE material_id = ?', [existing.id]);
  await run('DELETE FROM material_group_preferences WHERE material_id = ?', [existing.id]);
  await run('DELETE FROM inventory_stock_positions WHERE material_barcode = ?', [existing.barcode]);
  await run('DELETE FROM inventory_movements WHERE material_barcode = ?', [existing.barcode]);
  await run('DELETE FROM inventory_reservations WHERE material_barcode = ?', [existing.barcode]);
  await run('DELETE FROM inventory_alerts WHERE material_barcode = ?', [existing.barcode]);
  await run('DELETE FROM materials WHERE id = ?', [existing.id]);
}

async function linkMaterialRecordToGroup(barcode, groupId) {
  const existing = await getMaterialRowByBarcode(barcode);
  if (!existing) {
    throw new Error('Material not found.');
  }
  const group = await getGroupRowById(Number(groupId));
  if (!group || group.is_archived) {
    throw new Error('Selected group is not available.');
  }
  await run(
    'UPDATE materials SET linked_group_id = ?, linked_item_id = NULL, linked_variation_leaf_node_id = NULL, updated_at = ? WHERE id = ?',
    [group.id, new Date().toISOString(), existing.id],
  );
  await logMaterialActivity({
    barcode: existing.barcode,
    type: 'linked',
    label: 'Inheritance linked',
    description: `Linked to group ${group.name || group.id}.`,
    actor: existing.created_by || 'Demo Admin',
  });
  return get('SELECT * FROM materials WHERE id = ?', [existing.id]);
}

async function linkMaterialRecordToItem(barcode, itemId, variationLeafNodeId = null) {
  const existing = await getMaterialRowByBarcode(barcode);
  if (!existing) {
    throw new Error('Material not found.');
  }
  const item = await getItemRowById(Number(itemId));
  if (!item || item.is_archived) {
    throw new Error('Selected item is not available.');
  }
  const tree = await getItemVariationTree(item.id);
  const hasActiveVariationProperties = activeTopLevelVariationProperties(tree).length > 0;
  const normalizedLeafId = variationLeafNodeId == null ? null : Number(variationLeafNodeId);
  if (hasActiveVariationProperties) {
    const leafPath = activeValuePathForLeaf(tree, normalizedLeafId);
    const leafNode = findVariationNodeById(tree, normalizedLeafId);
    if (
      !Number.isFinite(normalizedLeafId) ||
      normalizedLeafId <= 0 ||
      !leafNode ||
      leafNode.isArchived ||
      String(leafNode.kind) !== 'value' ||
      !leafPath
    ) {
      const error = new Error('Select an orderable variation leaf before linking this item.');
      error.statusCode = 400;
      throw error;
    }
  } else if (normalizedLeafId != null && normalizedLeafId > 0) {
    const error = new Error('Simple items cannot be linked to a variation leaf.');
    error.statusCode = 400;
    throw error;
  }
  await run(
    'UPDATE materials SET linked_group_id = NULL, linked_item_id = ?, linked_variation_leaf_node_id = ?, updated_at = ? WHERE id = ?',
    [item.id, hasActiveVariationProperties ? normalizedLeafId : null, new Date().toISOString(), existing.id],
  );
  await logMaterialActivity({
    barcode: existing.barcode,
    type: 'linked',
    label: 'Inheritance linked',
    description: `Linked to item ${item.display_name || item.name || item.id}${hasActiveVariationProperties ? ' (Variation ' + normalizedLeafId + ')' : ''}.`,
    actor: existing.created_by || 'Demo Admin',
  });
  return get('SELECT * FROM materials WHERE id = ?', [existing.id]);
}

async function unlinkMaterialRecord(barcode) {
  const existing = await getMaterialRowByBarcode(barcode);
  if (!existing) {
    throw new Error('Material not found.');
  }
  await run(
    'UPDATE materials SET linked_group_id = NULL, linked_item_id = NULL, linked_variation_leaf_node_id = NULL, updated_at = ? WHERE id = ?',
    [new Date().toISOString(), existing.id],
  );
  await logMaterialActivity({
    barcode: existing.barcode,
    type: 'unlinked',
    label: 'Inheritance removed',
    description: 'Removed inheritance link.',
    actor: existing.created_by || 'Demo Admin',
  });
  return get('SELECT * FROM materials WHERE id = ?', [existing.id]);
}

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

async function createRunFromTemplate(templateId, name, orderNo, orderItemId, scrapRouting = 'inventory') {
  const templateRow = await get(
    'SELECT * FROM pipeline_templates WHERE id = ?',
    [templateId],
  );
  if (!templateRow) {
    return null;
  }
  const template = rowToTemplate(templateRow);
  const now = new Date().toISOString();
  const runId = `run-${Date.now()}`;
  const nodeStatuses = Object.fromEntries(
    template.nodes.map((node) => [node.id, 'pending']),
  );

  await run(
    `
    INSERT INTO pipeline_runs (
      id, template_id, template_version, name, status, overrides_json,
      node_status_json, scrap_routing, node_metrics_json, started_at, completed_at, created_at
    ) VALUES (?, ?, ?, ?, 'planned', ?, ?, ?, '{}', NULL, NULL, ?)
    `,
    [
      runId,
      template.id,
      template.version,
      name || `Run ${new Date(now).toLocaleDateString('en-IN')} - ${Date.now()}`,
      JSON.stringify({
        actualDurationHoursByNode: {},
        batchQuantityByNode: {},
        machineOverrideByNode: {},
      }),
      JSON.stringify(nodeStatuses),
      scrapRouting,
      now,
    ],
  );

  if (orderItemId) {
    await run(
      'INSERT INTO order_pipeline_assignments (order_item_id, pipeline_run_id) VALUES (?, ?)',
      [orderItemId, runId]
    );
  } else if (orderNo) {
    const orderItems = await all(
      'SELECT id FROM order_items WHERE order_no = ?',
      [orderNo]
    );
    for (const item of orderItems) {
      await run(
        'INSERT INTO order_pipeline_assignments (order_item_id, pipeline_run_id) VALUES (?, ?)',
        [item.id, runId]
      );
    }
  }

  const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [runId]);
  return rowToRun(runRow);
}

async function ensurePipelineRunRecord({
  id,
  templateId,
  name,
  status,
  createdAt,
  startedAt = null,
  completedAt = null,
  nodeStatuses,
  overrides,
  barcodeAssignments = [],
}) {
  const templateRow = await get('SELECT * FROM pipeline_templates WHERE id = ?', [
    templateId,
  ]);
  if (!templateRow) {
    return null;
  }

  const template = rowToTemplate(templateRow);
  const existing = await get('SELECT * FROM pipeline_runs WHERE id = ?', [id]);
  const resolvedNodeStatuses =
    nodeStatuses ||
    Object.fromEntries(template.nodes.map((node) => [node.id, 'pending']));
  const resolvedOverrides =
    overrides || {
      actualDurationHoursByNode: {},
      batchQuantityByNode: {},
      machineOverrideByNode: {},
    };

  if (!existing) {
    await run(
      `
      INSERT INTO pipeline_runs (
        id, template_id, template_version, name, status, overrides_json,
        node_status_json, started_at, completed_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        id,
        templateId,
        template.version,
        name,
        status,
        JSON.stringify(resolvedOverrides),
        JSON.stringify(resolvedNodeStatuses),
        startedAt,
        completedAt,
        createdAt,
      ],
    );
  } else {
    await run(
      `
      UPDATE pipeline_runs
      SET template_id = ?, template_version = ?, name = ?, status = ?, overrides_json = ?,
          node_status_json = ?, started_at = ?, completed_at = ?, created_at = ?
      WHERE id = ?
      `,
      [
        templateId,
        template.version,
        name,
        status,
        JSON.stringify(resolvedOverrides),
        JSON.stringify(resolvedNodeStatuses),
        startedAt,
        completedAt,
        createdAt,
        id,
      ],
    );
  }

  await run('DELETE FROM run_barcode_inputs WHERE run_id = ?', [id]);
  for (const assignment of barcodeAssignments) {
    const materialRow = await getMaterialRowByBarcode(assignment.barcode);
    if (!materialRow) {
      continue;
    }
    await run(
      `
      INSERT INTO run_barcode_inputs (
        id, run_id, node_id, barcode, material_id, material_payload_json, scanned_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        assignment.id,
        id,
        assignment.nodeId,
        materialRow.barcode,
        String(materialRow.id || ''),
        JSON.stringify({
          barcode: materialRow.barcode,
          materialName: materialRow.name,
          materialType: materialRow.type,
          scanCount: materialRow.scan_count || 0,
        }),
        assignment.scannedAt || createdAt,
      ],
    );
  }

  const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [id]);
  return rowToRun(runRow);
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

app.post('/api/auth/login', async (req, res) => {
  try {
    const email = normalizeEmail(req.body?.email);
    const password = String(req.body?.password || '');
    const pin = String(req.body?.pin || '').trim();

    let user;
    if (pin && pin.length === 4) {
      // Code login: match the user's assigned 4-digit code. (No hardcoded
      // master PIN — that was a backdoor into the super admin account.)
      user = await get('SELECT * FROM users WHERE mobile_pin = ?', [pin]);
    } else {
      user = await get('SELECT * FROM users WHERE email = ?', [email]);
    }

    if (user && isTimestampInFuture(user.lockout_until)) {
      await logAuthEvent({
        eventType: 'login_blocked_lockout',
        targetUserId: user.id,
        ipAddress: getRequestIp(req),
        userAgent: getRequestUserAgent(req),
        metadata: { lockoutUntil: user.lockout_until },
      });
      res.status(423).json({ success: false, user: null, token: null, error: 'Account is temporarily locked. Try again later.' });
      return;
    }

    if (pin && pin.length === 4) {
      if (!user || Number(user.is_active || 0) !== 1) {
        await registerLoginFailure({ user, email: 'pin-login', req });
        res.status(401).json({ success: false, user: null, token: null, error: 'Invalid PIN.' });
        return;
      }
    } else {
      if (!user || Number(user.is_active || 0) !== 1 || !verifyPassword(password, user.password_hash)) {
        await registerLoginFailure({ user, email, req });
        res.status(401).json({ success: false, user: null, token: null, error: 'Invalid email or password.' });
        return;
      }
    }
    const permissionMap = await getEffectivePermissionMap(user.id, user.role);

    const clientPlatform = (req.headers['x-client-platform'] || '').toLowerCase();
    const isMobile = clientPlatform === 'mobile' || clientPlatform === 'ios' || clientPlatform === 'android';
    
    if (isMobile) {
      if (permissionMap['login.mobile'] !== true && user.role !== 'super_admin') {
        res.status(403).json({ success: false, user: null, token: null, error: 'Mobile login is disabled for this account.' });
        return;
      }
    } else {
      if (permissionMap['login.desktop'] !== true && user.role !== 'super_admin') {
        res.status(403).json({ success: false, user: null, token: null, error: 'Desktop login is disabled for this account.' });
        return;
      }
    }

    const safeUser = safeUserDto(user, permissionMap);
    const { token } = await createAuthSession({ user, req });
    res.json({ success: true, user: safeUser, token, error: null });
  } catch (error) {
    res.status(500).json({ success: false, user: null, token: null, error: error.message });
  }
});
// ---------------------------------------------------------
// Railway Track Real-time Events (SSE)
// ---------------------------------------------------------
// Any authenticated user may receive the realtime change stream. It carries only
// {table_name, record_id, event_type} (ids, no row data); the actual fetch each
// event triggers is separately permission-checked. Gating this behind
// config.read wrongly starved non-admin users of live updates.
app.get('/api/events', requireAuth, async (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  // Tell nginx / reverse proxies NOT to buffer this stream. Without this, small
  // change events pile up in the proxy's buffer and reach the client only when
  // it fills or the heartbeat flushes it — so live updates arrive in laggy
  // bursts. Pairs with `proxy_buffering off` in deploy/nginx.paper.conf.
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders();
  // Disable Nagle so each small SSE frame goes out on the wire immediately.
  req.socket?.setNoDelay(true);

  // Flush per-write when a flush() is available (e.g. behind compression);
  // harmless no-op otherwise.
  const flush = () => {
    if (typeof res.flush === 'function') res.flush();
  };

  let sinceId = Number(req.query.since);
  if (!Number.isFinite(sinceId) || sinceId < 0) {
    sinceId = null;
  }

  try {
    // Only replay when the client already holds a real position (since > 0),
    // i.e. it received live events and then reconnected. A fresh client sends
    // since=0 and just syncs to head — it does a full initial load on its own,
    // so replaying the entire changelog history would be a needless burst of
    // refetches on every app launch.
    if (sinceId !== null && sinceId > 0) {
      // Catch up on events missed while disconnected. This MUST use the same
      // framing as the live `listener` below (an `event: table-change` line and
      // table_name/record_id/event_type keys) — otherwise the client silently
      // drops every replayed event and never recovers changes made during the
      // reconnect gap. LIMIT guards against an unbounded replay for a very stale
      // client; the closing `lastChangeId` still advances it to head.
      const rows = await all('SELECT id, table_name, record_id, event_type FROM changelog WHERE id > ? ORDER BY id ASC LIMIT 1000', [sinceId]);
      for (const row of rows) {
        res.write(`id: ${row.id}\n`);
        res.write(`event: table-change\n`);
        res.write(`data: ${JSON.stringify({ table_name: row.table_name, record_id: row.record_id, event_type: row.event_type })}\n\n`);
      }
    }
    // Always tell the client the current head so it can anchor its position
    // (used on first connect, and after a capped catch-up).
    const row = await get('SELECT MAX(id) as maxId FROM changelog');
    const maxId = row?.maxId || 0;
    res.write(`data: ${JSON.stringify({ lastChangeId: maxId })}\n\n`);
    flush();
  } catch (err) {
    console.error('[SSE] Failed to fetch changelog:', err);
  }

  const listener = (event) => {
    res.write(`id: ${event.id}\n`);
    res.write(`event: table-change\n`);
    res.write(`data: ${JSON.stringify({ table_name: event.table, record_id: event.recordId, event_type: event.eventType })}\n\n`);
    flush();
  };

  const customEventListener = (payload) => {
    res.write(`event: custom-event\n`);
    res.write(`data: ${JSON.stringify(payload)}\n\n`);
    flush();
  };

  changeEmitter.on('table-change', listener);
  changeEmitter.on('custom-event', customEventListener);

  // Heartbeat to keep the connection (and any idle proxy) alive.
  const heartbeat = setInterval(() => {
    res.write(': heartbeat\n\n');
    flush();
  }, 15000);

  req.on('close', () => {
    changeEmitter.off('table-change', listener);
    changeEmitter.off('custom-event', customEventListener);
    clearInterval(heartbeat);
  });
});

app.get('/api/delivery-challans/health', (_req, res) => {
  res.json({
    success: true,
    module: 'delivery-challans',
  });
});

app.use('/api', (req, res, next) => {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
  next();
});
app.use('/api', requireAuth);
app.use('/api', requireApiModulePermission);
app.use('/api', requireApiWritePermission);

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


app.get('/api/auth/me', async (req, res) => {
  res.json({ success: true, user: req.user, error: null });
});

app.post('/api/auth/logout', async (req, res) => {
  try {
    await revokeSession(req.authSession.id, 'logout');
    await logAuthEvent({
      eventType: 'logout',
      actorUserId: req.user.id,
      targetUserId: req.user.id,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { sessionId: req.authSession.id },
    });
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/auth/sessions', async (req, res) => {
  try {
    const rows = await all(
      `
      SELECT *
      FROM auth_sessions
      WHERE user_id = ?
      ORDER BY datetime(created_at) DESC
      LIMIT 50
      `,
      [req.user.id],
    );
    res.json({ success: true, sessions: rows.map(rowToAuthSessionDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, sessions: [], error: error.message });
  }
});

app.delete('/api/auth/sessions/:id', async (req, res) => {
  try {
    const sessionId = String(req.params.id || '').trim();
    const existing = await get('SELECT * FROM auth_sessions WHERE id = ? AND user_id = ?', [
      sessionId,
      req.user.id,
    ]);
    if (!existing) {
      res.status(404).json({ success: false, error: 'Session not found.' });
      return;
    }
    await revokeSession(sessionId, 'user_revoked');
    await logAuthEvent({
      eventType: 'session_revoked',
      actorUserId: req.user.id,
      targetUserId: req.user.id,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { sessionId },
    });
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/users/:id/sessions', requirePermission('sessions.manage'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      res.status(404).json({ success: false, sessions: [], error: 'User not found.' });
      return;
    }
    if (!canManageUser(req.user.role, target.role) && targetId !== req.user.id) {
      res.status(403).json({ success: false, sessions: [], error: 'You do not have permission to view this user sessions.' });
      return;
    }
    const rows = await all(
      `
      SELECT *
      FROM auth_sessions
      WHERE user_id = ?
      ORDER BY datetime(created_at) DESC
      LIMIT 100
      `,
      [targetId],
    );
    res.json({ success: true, sessions: rows.map(rowToAuthSessionDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, sessions: [], error: error.message });
  }
});

app.post('/api/users/:id/sessions/revoke', requirePermission('sessions.manage'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      res.status(404).json({ success: false, error: 'User not found.' });
      return;
    }
    if (!canManageUser(req.user.role, target.role) && targetId !== req.user.id) {
      res.status(403).json({ success: false, error: 'You do not have permission to revoke this user sessions.' });
      return;
    }
    await revokeSessionsForUser(targetId, {
      exceptSessionId: targetId === req.user.id ? req.authSession.id : null,
      reason: 'admin_revoked',
    });
    await logAuthEvent({
      eventType: 'user_sessions_revoked',
      actorUserId: req.user.id,
      targetUserId: targetId,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
    });
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/audit/global', requirePermission('audit.read'), async (req, res) => {
  try {
    const params = [];
    const whereClauses = [];
    const entityType = String(req.query.entityType || '').trim();
    const action = String(req.query.action || '').trim();
    const limit = Math.min(Math.max(Number(req.query.limit) || 100, 1), 1000);
    const offset = Math.max(Number(req.query.offset) || 0, 0);

    if (entityType) {
      whereClauses.push('g.entity_type = ?');
      params.push(entityType);
    }
    if (action) {
      whereClauses.push('g.action = ?');
      params.push(action);
    }

    if (req.user.role === 'admin') {
      whereClauses.push('(g.actor_user_id = ? OR g.actor_role = ?)');
      params.push(req.user.id, 'user');
    } else if (req.user.role !== 'super_admin') {
      whereClauses.push('g.actor_user_id = ?');
      params.push(req.user.id);
    }

    const whereSql = whereClauses.length > 0 ? 'WHERE ' + whereClauses.join(' AND ') : '';

    const countRow = await get(
      `SELECT COUNT(*) as c FROM global_audit_logs g ${whereSql}`,
      params
    );
    const total = countRow ? countRow.c : 0;

    const rows = await all(
      `
      SELECT 
        g.id, g.actor_user_id, g.actor_name, g.actor_role, 
        g.action, g.entity_type, g.entity_id, g.details_json, 
        g.ip_address, g.created_at
      FROM global_audit_logs g
      ${whereSql}
      ORDER BY g.created_at DESC
      LIMIT ? OFFSET ?
      `,
      [...params, limit, offset]
    );

    const logs = rows.map((r) => ({
      id: r.id,
      actorUserId: r.actor_user_id,
      actorName: r.actor_name,
      actorRole: r.actor_role,
      action: r.action,
      entityType: r.entity_type,
      entityId: r.entity_id,
      details: JSON.parse(r.details_json || '{}'),
      ipAddress: r.ip_address,
      createdAt: r.created_at,
    }));

    res.json({ success: true, data: logs, total, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --- Track: per-entity + per-person activity feeds --------------------------
// Per-person "overall" track — everything this user changed, newest first.
// Defined before the generic /:entityType route so "actor" isn't swallowed.
app.get('/api/track/actor/:userId', requirePermission('audit.read'), async (req, res) => {
  try {
    const userId = Number(req.params.userId);
    const limit = Math.min(Number(req.query.limit) || 200, 500);
    const rows = await all(
      `SELECT * FROM entity_activity_log
       WHERE actor_user_id = ?
       ORDER BY created_at DESC, id DESC
       LIMIT ?`,
      [userId, limit],
    );
    res.json({
      success: true,
      events: rows.map(rowToEntityActivityDto),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, events: [], error: error.message });
  }
});

// Per-record track — the "Track" tab on a master (Item, Vendor, Client, ...).
app.get('/api/track/:entityType/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const entityType = String(req.params.entityType || '');
    const entityId = String(req.params.id || '');
    const limit = Math.min(Number(req.query.limit) || 200, 500);
    const rows = await all(
      `SELECT * FROM entity_activity_log
       WHERE entity_type = ? AND entity_id = ?
       ORDER BY created_at DESC, id DESC
       LIMIT ?`,
      [entityType, entityId, limit],
    );
    res.json({
      success: true,
      events: rows.map(rowToEntityActivityDto),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, events: [], error: error.message });
  }
});

app.get('/api/auth/events', requirePermission('audit.read'), async (req, res) => {
  try {
    const params = [];
    const whereClauses = [];
    const eventType = String(req.query.eventType || '').trim();
    const targetUserId = Number(req.query.targetUserId || 0);
    const actorUserId = Number(req.query.actorUserId || 0);
    const from = normalizeNullableDate(req.query.from);
    const to = normalizeNullableDate(req.query.to);
    const { limit, offset } = parsePagination(req.query, {
      defaultLimit: 50,
      maxLimit: 200,
    });
    if (eventType) {
      whereClauses.push('ae.event_type = ?');
      params.push(eventType);
    }
    if (targetUserId > 0) {
      whereClauses.push('ae.target_user_id = ?');
      params.push(targetUserId);
    }
    if (actorUserId > 0) {
      whereClauses.push('ae.actor_user_id = ?');
      params.push(actorUserId);
    }
    if (from) {
      whereClauses.push('datetime(ae.created_at) >= datetime(?)');
      params.push(from);
    }
    if (to) {
      whereClauses.push('datetime(ae.created_at) <= datetime(?)');
      params.push(to);
    }
    if (req.user.role === 'admin') {
      whereClauses.push(`(
        ae.actor_user_id = ? OR ae.target_user_id = ?
        OR actor.role = 'user' OR target.role = 'user'
      )`);
      params.push(req.user.id, req.user.id);
    }
    const whereSql = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';
    const countRow = await get(
      `
      SELECT COUNT(*) AS count
      FROM auth_events ae
      LEFT JOIN users actor ON actor.id = ae.actor_user_id
      LEFT JOIN users target ON target.id = ae.target_user_id
      ${whereSql}
      `,
      params,
    );
    const total = Number(countRow?.count || 0);
    const rows = await all(
      `
      SELECT
        ae.*,
        actor.name AS actor_user_name,
        actor.role AS actor_role,
        target.name AS target_user_name,
        target.role AS target_role
      FROM auth_events ae
      LEFT JOIN users actor ON actor.id = ae.actor_user_id
      LEFT JOIN users target ON target.id = ae.target_user_id
      ${whereSql}
      ORDER BY datetime(ae.created_at) DESC
      LIMIT ? OFFSET ?
      `,
      [...params, limit, offset],
    );
    res.json({
      success: true,
      events: rows.map(rowToAuthEventDto),
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + rows.length < total,
      },
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, events: [], error: error.message });
  }
});

app.get('/api/auth/events/export', requirePermission('audit.read'), async (req, res) => {
  try {
    const rows = await all(
      `
      SELECT
        ae.*,
        actor.name AS actor_user_name,
        target.name AS target_user_name
      FROM auth_events ae
      LEFT JOIN users actor ON actor.id = ae.actor_user_id
      LEFT JOIN users target ON target.id = ae.target_user_id
      ORDER BY datetime(ae.created_at) DESC
      LIMIT 5000
      `,
    );
    const csv = toCsv(
      [
        'id',
        'created_at',
        'event_type',
        'actor_user_id',
        'actor_user_name',
        'target_user_id',
        'target_user_name',
        'ip_address',
        'user_agent',
        'metadata_json',
      ],
      rows.map((row) => [
        row.id,
        row.created_at,
        row.event_type,
        row.actor_user_id ?? '',
        row.actor_user_name || '',
        row.target_user_id ?? '',
        row.target_user_name || '',
        row.ip_address || '',
        row.user_agent || '',
        row.metadata_json || '{}',
      ]),
    );
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="auth-events-${new Date().toISOString().slice(0, 10)}.csv"`,
    );
    res.status(200).send(csv);
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.patch('/api/me/password', async (req, res) => {
  try {
    const currentPassword = String(req.body?.currentPassword || '');
    const nextPassword = String(req.body?.newPassword || '');
    const user = await get('SELECT * FROM users WHERE id = ?', [req.user.id]);
    if (!user || !verifyPassword(currentPassword, user.password_hash)) {
      res.status(401).json({ success: false, error: 'Current password is incorrect.' });
      return;
    }
    const passwordError = validatePasswordPolicy(nextPassword, { email: user.email, role: user.role });
    if (passwordError) {
      res.status(400).json({ success: false, error: passwordError });
      return;
    }
    await run('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?', [
      hashPassword(nextPassword),
      new Date().toISOString(),
      req.user.id,
    ]);
    await revokeSessionsForUser(req.user.id, {
      exceptSessionId: req.authSession.id,
      reason: 'password_changed',
    });
    await logAuthEvent({
      eventType: 'password_changed',
      actorUserId: req.user.id,
      targetUserId: req.user.id,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
    });
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/users', requirePermission('users.read'), async (req, res) => {
  try {
    const params = [];
    const whereClauses = [];
    const queryText = String(req.query.query || '').trim().toLowerCase();
    const role = String(req.query.role || '').trim();
    const isActiveRaw = String(req.query.isActive || '').trim().toLowerCase();
    if (queryText) {
      whereClauses.push('(LOWER(users.name) LIKE ? OR LOWER(email) LIKE ?)');
      params.push(`%${queryText}%`, `%${queryText}%`);
    }
    if (USER_ROLES.has(role)) {
      whereClauses.push('users.role = ?');
      params.push(role);
    }
    if (isActiveRaw === 'true' || isActiveRaw === 'false') {
      whereClauses.push('users.is_active = ?');
      params.push(isActiveRaw === 'true' ? 1 : 0);
    }
    if (req.user.role === 'admin') {
      whereClauses.push('(users.role = ? OR users.id = ?)');
      params.push('user', req.user.id);
    }
    const whereSql = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';
    const { limit, offset } = parsePagination(req.query, { defaultLimit: 25, maxLimit: 100 });
    const countRow = await get(`SELECT COUNT(*) AS count FROM users ${whereSql}`, params);
    const total = Number(countRow?.count || 0);
    const rows = await all(
      `
      SELECT users.*, clients.name as client_name
      FROM users
      LEFT JOIN clients ON users.client_id = clients.id
      ${whereSql}
      ORDER BY users.role ASC, users.name ASC
      LIMIT ? OFFSET ?
      `,
      [...params, limit, offset],
    );
    const users = [];
    for (const row of rows) {
      users.push(await safeUserDtoWithPermissions(row));
    }
    res.json({
      success: true,
      users,
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + users.length < total,
      },
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, users: [], error: error.message });
  }
});

app.get('/api/permissions', requirePermission('users.manage_permissions'), async (_req, res) => {
  res.json({
    success: true,
    permissions: permissionDescriptors(),
    error: null,
  });
});

app.get('/api/permission-templates', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const queryText = String(req.query.query || '').trim().toLowerCase();
    const params = [];
    let whereSql = '';
    if (queryText) {
      whereSql = 'WHERE LOWER(name) LIKE ? OR LOWER(description) LIKE ?';
      params.push(`%${queryText}%`, `%${queryText}%`);
    }
    const rows = await all(
      `
      SELECT *
      FROM permission_templates
      ${whereSql}
      ORDER BY name ASC
      `,
      params,
    );
    const templates = [];
    for (const row of rows) {
      const permissionRows = await all(
        `
        SELECT permission_key, is_allowed
        FROM permission_template_permissions
        WHERE template_id = ?
        ORDER BY permission_key ASC
        `,
        [row.id],
      );
      templates.push({
        id: row.id,
        name: row.name || '',
        description: row.description || '',
        isSystemDefault: Number(row.is_system_default || 0) === 1,
        permissions: permissionRows
          .filter((item) => Number(item.is_allowed || 0) === 1)
          .map((item) => String(item.permission_key || '').trim())
          .filter(Boolean),
      });
    }
    res.json({ success: true, templates, error: null });
  } catch (error) {
    res.status(500).json({ success: false, templates: [], error: error.message });
  }
});

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

app.post('/api/permission-templates', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const name = String(req.body?.name || '').trim();
    if (!name) return res.status(400).json({ success: false, error: 'A name is required.' });
    const description = String(req.body?.description || '').trim();
    const keys = normalizeTemplatePermissionKeys(req.body?.permissions);
    const lacking = firstUngrantableKey(req, keys);
    if (lacking) {
      return res.status(403).json({ success: false, error: `You cannot grant a permission you do not have (${lacking}).` });
    }
    const existing = await get('SELECT id FROM permission_templates WHERE LOWER(name) = LOWER(?)', [name]);
    if (existing) return res.status(409).json({ success: false, error: 'A preset with that name already exists.' });
    const now = nowIso();
    const info = await run(
      'INSERT INTO permission_templates (name, description, is_system_default, created_at, updated_at) VALUES (?, ?, 0, ?, ?)',
      [name, description, now, now],
    );
    const templateId = info.lastID;
    for (const key of keys) {
      await run(
        'INSERT INTO permission_template_permissions (template_id, permission_key, is_allowed, created_at, updated_at) VALUES (?, ?, 1, ?, ?)',
        [templateId, key, now, now],
      );
    }
    res.status(201).json({ success: true, id: templateId, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.patch('/api/permission-templates/:id', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const tpl = await get('SELECT * FROM permission_templates WHERE id = ?', [id]);
    if (!tpl) return res.status(404).json({ success: false, error: 'Preset not found.' });
    if (Number(tpl.is_system_default || 0) === 1) {
      return res.status(403).json({ success: false, error: 'Built-in presets cannot be edited.' });
    }
    const now = nowIso();
    const name = req.body?.name !== undefined ? String(req.body.name).trim() : tpl.name;
    if (!name) return res.status(400).json({ success: false, error: 'A name is required.' });
    const description = req.body?.description !== undefined ? String(req.body.description).trim() : tpl.description;
    await run('UPDATE permission_templates SET name = ?, description = ?, updated_at = ? WHERE id = ?', [name, description, now, id]);
    if (req.body?.permissions !== undefined) {
      const keys = normalizeTemplatePermissionKeys(req.body.permissions);
      const lacking = firstUngrantableKey(req, keys);
      if (lacking) {
        return res.status(403).json({ success: false, error: `You cannot grant a permission you do not have (${lacking}).` });
      }
      await run('DELETE FROM permission_template_permissions WHERE template_id = ?', [id]);
      for (const key of keys) {
        await run(
          'INSERT INTO permission_template_permissions (template_id, permission_key, is_allowed, created_at, updated_at) VALUES (?, ?, 1, ?, ?)',
          [id, key, now, now],
        );
      }
    }
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/permission-templates/:id', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const tpl = await get('SELECT * FROM permission_templates WHERE id = ?', [id]);
    if (!tpl) return res.status(404).json({ success: false, error: 'Preset not found.' });
    if (Number(tpl.is_system_default || 0) === 1) {
      return res.status(403).json({ success: false, error: 'Built-in presets cannot be deleted.' });
    }
    await run('DELETE FROM permission_template_permissions WHERE template_id = ?', [id]);
    await run('DELETE FROM user_permission_templates WHERE template_id = ?', [id]);
    await run('DELETE FROM permission_templates WHERE id = ?', [id]);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/users/:id/permission-templates', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      res.status(404).json({ success: false, templates: [], error: 'User not found.' });
      return;
    }
    if (!canManageUser(req.user.role, target.role)) {
      res.status(403).json({ success: false, templates: [], error: 'You do not have permission to manage this user.' });
      return;
    }
    const assignedRows = await getAssignedPermissionTemplates(targetId);
    const assignedTemplateIds = assignedRows.map((row) => Number(row.id));
    res.json({
      success: true,
      assignedTemplateIds,
      assignedTemplates: assignedRows.map((row) => ({
        id: row.id,
        name: row.name || '',
        description: row.description || '',
      })),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, templates: [], error: error.message });
  }
});

app.patch('/api/users/:id/permission-templates', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      res.status(404).json({ success: false, error: 'User not found.' });
      return;
    }
    if (!canManageUser(req.user.role, target.role)) {
      res.status(403).json({ success: false, error: 'You do not have permission to manage this user.' });
      return;
    }
    if (target.role === 'super_admin') {
      res.status(403).json({ success: false, error: 'Super admin templates cannot be edited.' });
      return;
    }
    const templateIds = Array.isArray(req.body?.templateIds)
      ? [...new Set(req.body.templateIds.map((value) => Number(value)).filter((value) => value > 0))]
      : null;
    if (!templateIds) {
      res.status(400).json({ success: false, error: 'templateIds array is required.' });
      return;
    }
    if (templateIds.length > 0) {
      const placeholders = templateIds.map(() => '?').join(', ');
      const templateRows = await all(
        `
        SELECT DISTINCT pt.id, ptp.permission_key, ptp.is_allowed
        FROM permission_templates pt
        LEFT JOIN permission_template_permissions ptp ON ptp.template_id = pt.id
        WHERE pt.id IN (${placeholders})
        `,
        templateIds,
      );
      const foundTemplateIds = new Set(templateRows.map((row) => Number(row.id)));
      if (foundTemplateIds.size !== templateIds.length) {
        res.status(400).json({ success: false, error: 'One or more templates were not found.' });
        return;
      }
      if (req.user.role !== 'super_admin') {
        for (const row of templateRows) {
          const key = normalizePermissionKey(row.permission_key);
          if (!key || Number(row.is_allowed || 0) !== 1) {
            continue;
          }
          if (req.userPermissions?.[key] !== true) {
            res.status(403).json({
              success: false,
              error: `You cannot assign template permissions you do not have: ${key}`,
            });
            return;
          }
        }
      }
    }
    await run('DELETE FROM user_permission_templates WHERE user_id = ?', [targetId]);
    const now = nowIso();
    for (const templateId of templateIds) {
      await run(
        `
        INSERT INTO user_permission_templates (user_id, template_id, created_at)
        VALUES (?, ?, ?)
        `,
        [targetId, templateId, now],
      );
    }
    await logAuthEvent({
      eventType: 'permission_templates_updated',
      actorUserId: req.user.id,
      targetUserId: targetId,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { templateIds },
    });
    res.json({ success: true, templateIds, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/users/:id/permissions', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      res.status(404).json({ success: false, permissions: [], error: 'User not found.' });
      return;
    }
    if (!canManageUser(req.user.role, target.role)) {
      res.status(403).json({ success: false, permissions: [], error: 'You do not have permission to manage this user.' });
      return;
    }
    const permissions = await getUserPermissionSnapshot(target);
    const assignedTemplates = await getAssignedPermissionTemplates(targetId);
    res.json({
      success: true,
      permissions,
      assignedTemplates: assignedTemplates.map((row) => ({
        id: row.id,
        name: row.name || '',
        description: row.description || '',
      })),
      role: target.role,
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, permissions: [], error: error.message });
  }
});

// --- Per-record (row-level) grants for a single user -----------------------
app.get('/api/users/:id/record-permissions', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) return res.status(404).json({ success: false, records: [], error: 'User not found.' });
    if (!canManageUser(req.user.role, target.role)) {
      return res.status(403).json({ success: false, records: [], error: 'You do not have permission to manage this user.' });
    }
    const rows = await all(
      'SELECT entity_type, entity_id, op FROM user_record_permissions WHERE user_id = ? ORDER BY entity_type, entity_id',
      [targetId],
    );
    const records = [];
    for (const r of rows) {
      const src = RECORD_OPTION_SOURCES[r.entity_type];
      let label = `#${r.entity_id}`;
      if (src) {
        try {
          const row = await get(`SELECT ${src.label} AS label FROM ${src.table} WHERE ${src.idCol || 'id'} = ?`, [r.entity_id]);
          if (row && row.label) label = row.label;
        } catch (_) {}
      }
      records.push({ entityType: r.entity_type, entityId: String(r.entity_id), op: r.op, label });
    }
    res.json({ success: true, records, error: null });
  } catch (error) {
    res.status(500).json({ success: false, records: [], error: error.message });
  }
});

app.put('/api/users/:id/record-permissions', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) return res.status(404).json({ success: false, error: 'User not found.' });
    if (!canManageUser(req.user.role, target.role)) {
      return res.status(403).json({ success: false, error: 'You do not have permission to manage this user.' });
    }
    const requested = Array.isArray(req.body?.records) ? req.body.records : [];
    const clean = [];
    for (const r of requested) {
      const entityType = String(r?.entityType || '').trim();
      const entityId = String(r?.entityId ?? '').trim();
      const op = String(r?.op || '').trim();
      if (!RECORD_OPTION_SOURCES[entityType] || !RECORD_PERMISSION_OPS.has(op) || !entityId) continue;
      if (req.user.role !== 'super_admin' && req.userPermissions?.[`${entityType}.${op}`] !== true) {
        return res.status(403).json({ success: false, error: `You cannot grant ${op} on ${entityType} that you do not have yourself.` });
      }
      clean.push({ entityType, entityId, op });
    }
    const now = nowIso();
    await run('DELETE FROM user_record_permissions WHERE user_id = ?', [targetId]);
    for (const r of clean) {
      await run(
        'INSERT OR IGNORE INTO user_record_permissions (user_id, entity_type, entity_id, op, created_at) VALUES (?, ?, ?, ?, ?)',
        [targetId, r.entityType, r.entityId, r.op, now],
      );
    }
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Searchable record list for the per-record picker (id + label per module).
app.get('/api/record-options/:entityType', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const src = RECORD_OPTION_SOURCES[String(req.params.entityType)];
    if (!src) return res.json({ success: true, options: [], error: null });
    const q = String(req.query.query || '').trim().toLowerCase();
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const params = [];
    let where = '';
    if (q) {
      where = `WHERE LOWER(${src.label}) LIKE ?`;
      params.push(`%${q}%`);
    }
    params.push(limit);
    const rows = await all(
      `SELECT ${src.idCol || 'id'} AS id, ${src.label} AS label FROM ${src.table} ${where} ORDER BY label LIMIT ?`,
      params,
    );
    res.json({
      success: true,
      options: rows.map((r) => ({ id: String(r.id), label: r.label || `#${r.id}` })),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, options: [], error: error.message });
  }
});

app.patch('/api/users/:id/permissions', requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      res.status(404).json({ success: false, permissions: [], error: 'User not found.' });
      return;
    }
    if (!canManageUser(req.user.role, target.role)) {
      res.status(403).json({ success: false, permissions: [], error: 'You do not have permission to manage this user.' });
      return;
    }
    if (target.role === 'super_admin') {
      res.status(403).json({ success: false, permissions: [], error: 'Super admin permissions cannot be edited.' });
      return;
    }

    const patchItems = Array.isArray(req.body?.overrides) ? req.body.overrides : null;
    if (!patchItems) {
      res.status(400).json({ success: false, permissions: [], error: 'overrides array is required.' });
      return;
    }

    const actorCanGrant = req.userPermissions || createEmptyPermissionMap();
    const targetRoleDefaults = await getRolePermissionMap(target.role);
    const targetTemplateDefaults = await getTemplatePermissionMapForUser(targetId);
    const now = nowIso();
    for (const item of patchItems) {
      const key = normalizePermissionKey(item?.key);
      if (!isKnownPermissionKey(key)) {
        res.status(400).json({ success: false, permissions: [], error: `Unknown permission key: ${key}` });
        return;
      }
      const allowed = parseBooleanFlag(item?.allowed);
      if (req.user.role !== 'super_admin' && allowed && actorCanGrant[key] !== true) {
        res.status(403).json({ success: false, permissions: [], error: `You cannot grant permission you do not have: ${key}` });
        return;
      }
      const baselineAllowed =
        targetRoleDefaults[key] === true || targetTemplateDefaults[key] === true;
      if (allowed === baselineAllowed) {
        await run(
          'DELETE FROM user_permission_overrides WHERE user_id = ? AND permission_key = ?',
          [targetId, key],
        );
      } else {
        await run(
          `
          INSERT INTO user_permission_overrides (user_id, permission_key, is_allowed, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(user_id, permission_key)
          DO UPDATE SET is_allowed = excluded.is_allowed, updated_at = excluded.updated_at
          `,
          [targetId, key, allowed ? 1 : 0, now, now],
        );
      }
    }

    await logAuthEvent({
      eventType: 'permissions_updated',
      actorUserId: req.user.id,
      targetUserId: targetId,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { updatedKeys: patchItems.map((item) => normalizePermissionKey(item?.key)).filter(Boolean) },
    });

    const refreshedTarget = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    const permissions = await getUserPermissionSnapshot(refreshedTarget);
    res.json({ success: true, permissions, role: refreshedTarget.role, error: null });
  } catch (error) {
    res.status(500).json({ success: false, permissions: [], error: error.message });
  }
});

app.post('/api/admins', requireRoles('super_admin'), requirePermission('users.create_admin'), async (req, res) => {
  try {
    const user = await createUserAccount({
      name: req.body?.name,
      email: req.body?.email,
      password: req.body?.password,
      role: 'admin',
      createdByUserId: req.user.id,
    });
    await logAuthEvent({
      eventType: 'user_created',
      actorUserId: req.user.id,
      targetUserId: user.id,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { role: 'admin' },
    });
    res.status(201).json({ success: true, user: await safeUserDtoWithPermissions(user), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, user: null, error: error.message });
  }
});

app.post('/api/users', requireRoles('super_admin', 'admin'), requirePermission('users.create_user'), async (req, res) => {
  try {
    const user = await createUserAccount({
      name: req.body?.name,
      email: req.body?.email,
      password: req.body?.password,
      role: 'user',
      createdByUserId: req.user.id,
    });
    await logAuthEvent({
      eventType: 'user_created',
      actorUserId: req.user.id,
      targetUserId: user.id,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { role: 'user' },
    });
    res.status(201).json({ success: true, user: await safeUserDtoWithPermissions(user), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, user: null, error: error.message });
  }
});

app.delete('/api/users/:id', requireRoles('super_admin', 'admin'), requirePermission('users.manage_permissions'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const override = req.query.override === 'true';
    if (!override) {
       return res.status(400).json({ success: false, error: 'User deletion requires override flag for compliance reasons.' });
    }
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      return res.status(404).json({ success: false, error: 'User not found' });
    }
    if (targetId === req.user.id) {
      return res.status(400).json({ success: false, error: 'You cannot delete your own account.' });
    }
    if (!canManageUser(req.user.role, target.role)) {
      return res.status(403).json({ success: false, error: 'You can only delete accounts below your own role level.' });
    }

    const fs = require('fs');
    const path = require('path');
    const backupDir = path.join(__dirname, 'backups');
    if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir);
    fs.writeFileSync(path.join(backupDir, `user_${targetId}_backup.json`), JSON.stringify(target, null, 2));

    await run('BEGIN TRANSACTION');
    try {
      await run('DELETE FROM auth_sessions WHERE user_id = ?', [targetId]);
      await run('DELETE FROM user_permission_overrides WHERE user_id = ?', [targetId]);
      await run('DELETE FROM user_permission_templates WHERE user_id = ?', [targetId]);
      await run('UPDATE auth_events SET actor_user_id = NULL WHERE actor_user_id = ?', [targetId]);
      await run('UPDATE auth_events SET target_user_id = NULL WHERE target_user_id = ?', [targetId]);
      await run('UPDATE global_audit_logs SET actor_user_id = NULL WHERE actor_user_id = ?', [targetId]);
      await run('UPDATE delete_requests SET reviewed_by_user_id = NULL WHERE reviewed_by_user_id = ?', [targetId]);
      await run('DELETE FROM delete_requests WHERE requested_by_user_id = ?', [targetId]);
      await run('UPDATE users SET created_by_user_id = NULL WHERE created_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_requests SET created_by_user_id = NULL WHERE created_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_requests SET raised_by_user_id = NULL WHERE raised_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_requests SET cancelled_by_user_id = NULL WHERE cancelled_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_requests SET closed_by_user_id = NULL WHERE closed_by_user_id = ?', [targetId]);
      await run('UPDATE procurement_activity_log SET actor_user_id = NULL WHERE actor_user_id = ?', [targetId]);
      await run('UPDATE delivery_challans SET created_by = NULL WHERE created_by = ?', [targetId]);
      await run('UPDATE delivery_challans SET updated_by = NULL WHERE updated_by = ?', [targetId]);
      await run('DELETE FROM search_history WHERE user_id = ?', [targetId]);
      await run('DELETE FROM search_clicks WHERE user_id = ?', [targetId]);
      
      await run('DELETE FROM users WHERE id = ?', [targetId]);
      await run('COMMIT');
    } catch (e) {
      await run('ROLLBACK');
      throw e;
    }
    
    await logAuthEvent({
      eventType: 'user_deleted',
      actorUserId: req.user.id,
      targetUserId: targetId,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { note: 'compliance override delete with backup' },
    });
    
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.patch('/api/users/:id/password', requirePermission('users.reset_password'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      res.status(404).json({ success: false, error: 'User not found.' });
      return;
    }
    if (!canManageUser(req.user.role, target.role)) {
      res.status(403).json({ success: false, error: 'You can only reset passwords for accounts below your own role level.' });
      return;
    }
    const newPassword = String(req.body?.newPassword || req.body?.password || '');
    const passwordError = validatePasswordPolicy(newPassword, { email: target.email, role: target.role });
    if (passwordError) {
      res.status(400).json({ success: false, error: passwordError });
      return;
    }
    await run('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?', [
      hashPassword(newPassword),
      new Date().toISOString(),
      targetId,
    ]);
    await revokeSessionsForUser(targetId, { reason: 'password_reset' });
    await logAuthEvent({
      eventType: 'password_reset',
      actorUserId: req.user.id,
      targetUserId: targetId,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
    });
    res.json({
      success: true,
      user: await safeUserDtoWithPermissions(await get('SELECT * FROM users WHERE id = ?', [targetId])),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.patch('/api/users/:id/status', requirePermission('users.update_status'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      res.status(404).json({ success: false, user: null, error: 'User not found.' });
      return;
    }
    if (targetId === req.user.id) {
      res.status(400).json({ success: false, user: null, error: 'You cannot deactivate your own account.' });
      return;
    }
    if (!canManageUser(req.user.role, target.role)) {
      res.status(403).json({ success: false, user: null, error: 'You can only update accounts below your own role level.' });
      return;
    }
    await run('UPDATE users SET is_active = ?, updated_at = ? WHERE id = ?', [
      req.body?.isActive === false ? 0 : 1,
      new Date().toISOString(),
      targetId,
    ]);
    const isActive = req.body?.isActive === false ? false : true;
    if (!isActive) {
      await revokeSessionsForUser(targetId, { reason: 'user_deactivated' });
    }
    await logAuthEvent({
      eventType: isActive ? 'user_activated' : 'user_deactivated',
      actorUserId: req.user.id,
      targetUserId: targetId,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
    });
    res.json({
      success: true,
      user: await safeUserDtoWithPermissions(await get('SELECT * FROM users WHERE id = ?', [targetId])),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, user: null, error: error.message });
  }
});

app.get('/api/delete-requests', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const status = String(req.query.status || '').trim();
    const whereClauses = [];
    const params = [];
    if (status && ['pending', 'approved', 'rejected'].includes(status)) {
      whereClauses.push('status = ?');
      params.push(status);
    }
    const whereSql = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';
    const { limit, offset } = parsePagination(req.query, { defaultLimit: 50, maxLimit: 100 });
    const countRow = await get(`SELECT COUNT(*) as count FROM delete_requests ${whereSql}`, params);
    const total = Number(countRow?.count || 0);
    const rows = await all(`SELECT * FROM delete_requests ${whereSql} ORDER BY created_at DESC LIMIT ? OFFSET ?`, [...params, limit, offset]);

    res.json({
      success: true,
      requests: rows.map(r => ({
        id: r.id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        entityLabel: r.entity_label,
        reason: r.reason,
        status: r.status,
        requestedByUserId: r.requested_by_user_id,
        reviewedByUserId: r.reviewed_by_user_id,
        reviewedAt: r.reviewed_at,
        reviewedNote: r.reviewed_note,
        createdAt: r.created_at
      })),
      total
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/delete-requests', requireAuth, async (req, res) => {
  try {
    const { entityType, entityId, entityLabel, reason } = req.body;
    if (!entityType || !entityId) {
       return res.status(400).json({ success: false, error: 'entityType and entityId are required.' });
    }
    const insertResult = await run(
      `INSERT INTO delete_requests (entity_type, entity_id, entity_label, reason, status, requested_by_user_id, created_at) VALUES (?, ?, ?, ?, 'pending', ?, ?)`,
      [entityType, entityId, entityLabel || '', reason || '', req.user.id, new Date().toISOString()]
    );
    const r = await get(`SELECT * FROM delete_requests WHERE id = ?`, [insertResult.lastID]);
    res.status(201).json({
      success: true,
      request: {
        id: r.id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        entityLabel: r.entity_label,
        reason: r.reason,
        status: r.status,
        requestedByUserId: r.requested_by_user_id,
        reviewedByUserId: r.reviewed_by_user_id,
        reviewedAt: r.reviewed_at,
        reviewedNote: r.reviewed_note,
        createdAt: r.created_at
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/delete-requests/:id/approve', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const reqRow = await get('SELECT * FROM delete_requests WHERE id = ?', [id]);
    if (!reqRow) return res.status(404).json({ success: false, error: 'Not found' });
    if (reqRow.status !== 'pending') return res.status(400).json({ success: false, error: 'Request is not pending.' });

    if (reqRow.entity_type === 'material') {
      await deleteMaterialRecord(reqRow.entity_id);
    } else if (reqRow.entity_type === 'item') {
      await run('DELETE FROM items WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'asset') {
      await deleteAsset(reqRow.entity_id);
    } else if (reqRow.entity_type === 'group') {
      await run('DELETE FROM groups WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'vendor') {
      await run('DELETE FROM vendors WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'inventory_set') {
      await deleteInventorySet(reqRow.entity_id);
    } else if (reqRow.entity_type === 'challan_template') {
      await deleteChallanTemplate(reqRow.entity_id);
    } else if (reqRow.entity_type === 'machine') {
      await run('DELETE FROM machines WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'die') {
      await run('DELETE FROM dies WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'user') {
      await run('DELETE FROM users WHERE id = ?', [reqRow.entity_id]);
    }

    const note = req.body?.note || '';
    const now = new Date().toISOString();
    await run(
      `UPDATE delete_requests SET status = 'approved', reviewed_by_user_id = ?, reviewed_at = ?, reviewed_note = ? WHERE id = ?`,
      [req.user.id, now, note, id]
    );
    const r = await get('SELECT * FROM delete_requests WHERE id = ?', [id]);

    res.json({
      success: true,
      request: {
        id: r.id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        entityLabel: r.entity_label,
        reason: r.reason,
        status: r.status,
        requestedByUserId: r.requested_by_user_id,
        reviewedByUserId: r.reviewed_by_user_id,
        reviewedAt: r.reviewed_at,
        reviewedNote: r.reviewed_note,
        createdAt: r.created_at
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/delete-requests/:id/reject', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const reqRow = await get('SELECT * FROM delete_requests WHERE id = ?', [id]);
    if (!reqRow) return res.status(404).json({ success: false, error: 'Not found' });
    if (reqRow.status !== 'pending') return res.status(400).json({ success: false, error: 'Request is not pending.' });

    const note = req.body?.note || '';
    const now = new Date().toISOString();
    await run(
      `UPDATE delete_requests SET status = 'rejected', reviewed_by_user_id = ?, reviewed_at = ?, reviewed_note = ? WHERE id = ?`,
      [req.user.id, now, note, id]
    );
    const r = await get('SELECT * FROM delete_requests WHERE id = ?', [id]);

    res.json({
      success: true,
      request: {
        id: r.id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        entityLabel: r.entity_label,
        reason: r.reason,
        status: r.status,
        requestedByUserId: r.requested_by_user_id,
        reviewedByUserId: r.reviewed_by_user_id,
        reviewedAt: r.reviewed_at,
        reviewedNote: r.reviewed_note,
        createdAt: r.created_at
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/delete-requests/export', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const rows = await all(`SELECT * FROM delete_requests ORDER BY created_at DESC`);
    const csvHeader = 'id,entityType,entityId,entityLabel,status,createdAt,reviewedAt\n';
    const csvBody = rows.map(r => `${r.id},${r.entity_type},${r.entity_id},${r.entity_label},${r.status},${r.created_at},${r.reviewed_at || ''}`).join('\n');
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="delete_requests_export.csv"');
    res.send(csvHeader + csvBody);
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

function machineRowToDto(r) {
  return {
    id: String(r.id),
    name: r.name,
    assetId: r.asset_id,
    primaryPhotoUrl: r.primary_photo_url,
    groupId: r.group_id,
    makeModel: r.make_model,
    serialNumber: r.serial_number,
    location: r.location,
    installationDate: r.installation_date ? new Date(r.installation_date).toISOString() : null,
    status: r.status,
    reportOutputPerHour: r.report_output_per_hour,
    setupMinutes: r.setup_minutes,
    laborCount: r.labor_count,
    powerKw: r.power_kw,
    reportNotes: r.report_notes || '',
    customProperties: JSON.parse(r.custom_properties || '[]'),
    createdAt: new Date(r.created_at).toISOString(),
    updatedAt: new Date(r.updated_at).toISOString(),
  };
}

function dieRowToDto(r) {
  return {
    id: String(r.id),
    toolCode: r.tool_code,
    producedPartNumbers: JSON.parse(r.produced_part_numbers || '[]'),
    photoUrls: JSON.parse(r.photo_urls || '[]'),
    operationalNotes: r.operational_notes,
    compatibleMachineGroupIds: JSON.parse(r.compatible_machine_group_ids || '[]'),
    storageLocation: r.storage_location,
    numberOfCavities: r.number_of_cavities,
    strokeCount: r.stroke_count,
    maxStrokes: r.max_strokes,
    strokesPerPiece: r.strokes_per_piece,
    setupMinutes: r.setup_minutes,
    reportNotes: r.report_notes || '',
    physicalSpecs: JSON.parse(r.physical_specs || '{}'),
    status: r.status,
    ownership: r.ownership,
    createdAt: new Date(r.created_at).toISOString(),
    updatedAt: new Date(r.updated_at).toISOString(),
  };
}

// Machines CRUD Endpoints
app.get('/api/machines', requirePermission('config.read'), async (req, res) => {
  try {
    const rows = await all('SELECT * FROM machines ORDER BY created_at DESC');
    const machines = rows.map(machineRowToDto);
    res.json({ success: true, machines, error: null });
  } catch (error) {
    res.status(500).json({ success: false, machines: [], error: error.message });
  }
});

app.get('/api/machines/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const r = await get('SELECT * FROM machines WHERE id = ?', [req.params.id]);
    if (!r) {
      return res.status(404).json({ success: false, machine: null, error: 'Machine not found' });
    }
    const machine = machineRowToDto(r);
    res.json({ success: true, machine, error: null });
  } catch (error) {
    res.status(500).json({ success: false, machine: null, error: error.message });
  }
});

app.post('/api/machines', requirePermission('config.write'), async (req, res) => {
  try {
    const {
      id,
      name,
      assetId,
      primaryPhotoUrl,
      groupId,
      makeModel,
      serialNumber,
      location,
      installationDate,
      status,
      reportOutputPerHour,
      setupMinutes,
      laborCount,
      powerKw,
      reportNotes,
      customProperties,
    } = req.body || {};
    const now = new Date().toISOString();
    let finalAssetId = assetId;
    if (!finalAssetId || finalAssetId.trim() === '') {
      finalAssetId = `MACH-${Date.now()}`;
    }
    let resultId = id;
    let beforeRow = null;
    const isUpdate = id && id.trim() !== '' && !id.startsWith('temp_') && isNaN(Number(id)) === false;
    if (isUpdate) {
      // Update
      beforeRow = await get('SELECT * FROM machines WHERE id = ?', [Number(id)]);
      await run(
        `UPDATE machines SET name = ?, asset_id = ?, primary_photo_url = ?, group_id = ?, make_model = ?, serial_number = ?, location = ?, installation_date = ?, status = ?, report_output_per_hour = ?, setup_minutes = ?, labor_count = ?, power_kw = ?, report_notes = ?, custom_properties = ?, updated_at = ? WHERE id = ?`,
        [name, finalAssetId, primaryPhotoUrl, groupId, makeModel, serialNumber, location, installationDate, status, reportOutputPerHour ?? null, setupMinutes ?? null, laborCount ?? null, powerKw ?? null, reportNotes || '', JSON.stringify(customProperties || []), now, Number(id)]
      );
    } else {
      // Create
      const info = await run(
        `INSERT INTO machines (name, asset_id, primary_photo_url, group_id, make_model, serial_number, location, installation_date, status, report_output_per_hour, setup_minutes, labor_count, power_kw, report_notes, custom_properties, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [name, finalAssetId, primaryPhotoUrl, groupId, makeModel, serialNumber, location, installationDate, status, reportOutputPerHour ?? null, setupMinutes ?? null, laborCount ?? null, powerKw ?? null, reportNotes || '', JSON.stringify(customProperties || []), now, now]
      );
      resultId = String(info.lastID);
    }
    const r = await get('SELECT * FROM machines WHERE id = ?', [resultId]);
    const machine = machineRowToDto(r);
    if (isUpdate) {
      trackUpdate('machines', resultId, beforeRow, r, req);
    } else {
      trackCreate('machines', resultId, r, req);
    }
    res.json({ success: true, machine, error: null });
  } catch (error) {
    res.status(500).json({ success: false, machine: null, error: error.message });
  }
});

app.delete('/api/machines/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = req.params.id;
    const activeRuns = await all("SELECT overrides_json FROM pipeline_runs WHERE status IN ('planned', 'in_progress', 'paused')");
    for (const run of activeRuns) {
      if (run.overrides_json && run.overrides_json.includes(`"${id}"`)) {
        // Double check by parsing
        const overrides = JSON.parse(run.overrides_json);
        if (overrides.machineOverrideByNode && Object.values(overrides.machineOverrideByNode).includes(id)) {
           return res.status(400).json({ success: false, error: 'Cannot delete machine: assigned to an active pipeline run.' });
        }
      }
    }
    const before = await get('SELECT * FROM machines WHERE id = ?', [id]);
    await run('DELETE FROM machines WHERE id = ?', [id]);
    trackDelete('machines', id, before, req);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Machines Assets
app.get('/api/machines/:id/assets', requirePermission('config.read'), async (req, res) => {
  try {
    const assets = await listAssetsForEntity('machine', Number(req.params.id));
    res.json({ success: true, assets, error: null });
  } catch (error) {
    res.status(500).json({ success: false, assets: [], error: error.message });
  }
});

app.post('/api/machines/:id/assets/upload-intent', requirePermission('config.write'), async (req, res) => {
  try {
    const entityId = Number(req.params.id);
    const intent = await createAssetUploadIntent({
      ...(req.body || {}),
      entityType: 'machine',
      entityId,
    });
    res.status(intent.alreadyUploaded ? 200 : 201).json({ success: true, intent, error: null });
  } catch (error) {
    res.status(500).json({ success: false, intent: null, error: error.message });
  }
});

app.post('/api/machines/:id/assets/upload-complete', requirePermission('config.write'), async (req, res) => {
  try {
    const asset = await completeAssetUpload(req.body || {});
    res.json({ success: true, asset, error: null });
  } catch (error) {
    res.status(500).json({ success: false, asset: null, error: error.message });
  }
});

// Dies CRUD Endpoints
app.get('/api/dies', requirePermission('config.read'), async (req, res) => {
  try {
    const rows = await all('SELECT * FROM dies ORDER BY created_at DESC');
    const dies = rows.map(dieRowToDto);
    res.json({ success: true, dies, error: null });
  } catch (error) {
    res.status(500).json({ success: false, dies: [], error: error.message });
  }
});

app.get('/api/dies/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const r = await get('SELECT * FROM dies WHERE id = ?', [req.params.id]);
    if (!r) {
      return res.status(404).json({ success: false, die: null, error: 'Die not found' });
    }
    const die = dieRowToDto(r);
    res.json({ success: true, die, error: null });
  } catch (error) {
    res.status(500).json({ success: false, die: null, error: error.message });
  }
});

app.post('/api/dies', requirePermission('config.write'), async (req, res) => {
  try {
    const {
      id,
      toolCode,
      producedPartNumbers,
      photoUrls,
      operationalNotes,
      compatibleMachineGroupIds,
      storageLocation,
      numberOfCavities,
      strokeCount,
      maxStrokes,
      strokesPerPiece,
      setupMinutes,
      reportNotes,
      physicalSpecs,
      status,
      ownership,
    } = req.body || {};
    const now = new Date().toISOString();
    let finalToolCode = toolCode;
    if (!finalToolCode || finalToolCode.trim() === '') {
      finalToolCode = `DIE-${Date.now()}`;
    }
    let resultId = id;
    let beforeRow = null;
    const isUpdate = id && id.trim() !== '' && !id.startsWith('temp_') && isNaN(Number(id)) === false;
    if (isUpdate) {
      // Update
      beforeRow = await get('SELECT * FROM dies WHERE id = ?', [Number(id)]);
      await run(
        `UPDATE dies SET tool_code = ?, produced_part_numbers = ?, photo_urls = ?, operational_notes = ?, compatible_machine_group_ids = ?, storage_location = ?, number_of_cavities = ?, stroke_count = ?, max_strokes = ?, strokes_per_piece = ?, setup_minutes = ?, report_notes = ?, physical_specs = ?, status = ?, ownership = ?, updated_at = ? WHERE id = ?`,
        [finalToolCode, JSON.stringify(producedPartNumbers || []), JSON.stringify(photoUrls || []), operationalNotes, JSON.stringify(compatibleMachineGroupIds || []), storageLocation, numberOfCavities, strokeCount || 0, maxStrokes || 0, strokesPerPiece ?? null, setupMinutes ?? null, reportNotes || '', JSON.stringify(physicalSpecs || {}), status, ownership, now, Number(id)]
      );
    } else {
      // Create
      const info = await run(
        `INSERT INTO dies (tool_code, produced_part_numbers, photo_urls, operational_notes, compatible_machine_group_ids, storage_location, number_of_cavities, stroke_count, max_strokes, strokes_per_piece, setup_minutes, report_notes, physical_specs, status, ownership, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [finalToolCode, JSON.stringify(producedPartNumbers || []), JSON.stringify(photoUrls || []), operationalNotes, JSON.stringify(compatibleMachineGroupIds || []), storageLocation, numberOfCavities, strokeCount || 0, maxStrokes || 0, strokesPerPiece ?? null, setupMinutes ?? null, reportNotes || '', JSON.stringify(physicalSpecs || {}), status, ownership, now, now]
      );
      resultId = String(info.lastID);
    }
    const r = await get('SELECT * FROM dies WHERE id = ?', [resultId]);
    const die = dieRowToDto(r);
    if (isUpdate) {
      trackUpdate('dies', resultId, beforeRow, r, req);
    } else {
      trackCreate('dies', resultId, r, req);
    }
    res.json({ success: true, die, error: null });
  } catch (error) {
    res.status(500).json({ success: false, die: null, error: error.message });
  }
});

app.delete('/api/dies/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = req.params.id;
    const activeRuns = await all("SELECT overrides_json FROM pipeline_runs WHERE status IN ('planned', 'in_progress', 'paused')");
    for (const run of activeRuns) {
      if (run.overrides_json && run.overrides_json.includes(`"${id}"`)) {
        const overrides = JSON.parse(run.overrides_json);
        if (overrides.dieOverrideByNode && Object.values(overrides.dieOverrideByNode).includes(id)) {
           return res.status(400).json({ success: false, error: 'Cannot delete die: assigned to an active pipeline run.' });
        }
      }
    }
    const before = await get('SELECT * FROM dies WHERE id = ?', [id]);
    await run('DELETE FROM dies WHERE id = ?', [id]);
    trackDelete('dies', id, before, req);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Dies Assets
app.get('/api/dies/:id/assets', requirePermission('config.read'), async (req, res) => {
  try {
    const assets = await listAssetsForEntity('die', Number(req.params.id));
    res.json({ success: true, assets, error: null });
  } catch (error) {
    res.status(500).json({ success: false, assets: [], error: error.message });
  }
});

app.post('/api/dies/:id/assets/upload-intent', requirePermission('config.write'), async (req, res) => {
  try {
    const entityId = Number(req.params.id);
    const intent = await createAssetUploadIntent({
      ...(req.body || {}),
      entityType: 'die',
      entityId,
    });
    res.status(intent.alreadyUploaded ? 200 : 201).json({ success: true, intent, error: null });
  } catch (error) {
    res.status(500).json({ success: false, intent: null, error: error.message });
  }
});

app.post('/api/dies/:id/assets/upload-complete', requirePermission('config.write'), async (req, res) => {
  try {
    const asset = await completeAssetUpload(req.body || {});
    res.json({ success: true, asset, error: null });
  } catch (error) {
    res.status(500).json({ success: false, asset: null, error: error.message });
  }
});

function mergeCustomVariationValueJsonRows(rows) {
  const valuesByKey = new Map();
  for (const row of rows || []) {
    const parsed = parseJson(row.custom_variation_values_json, {});
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      continue;
    }
    for (const [key, rawValue] of Object.entries(parsed)) {
      const value = String(rawValue || '').trim();
      if (!key || !value) {
        continue;
      }
      if (!valuesByKey.has(key)) {
        valuesByKey.set(key, []);
      }
      const values = valuesByKey.get(key);
      if (!values.includes(value)) {
        values.push(value);
      }
    }
  }
  const merged = {};
  for (const [key, values] of valuesByKey.entries()) {
    if (values.length > 0) {
      merged[key] = values.join(' / ');
    }
  }
  return merged;
}

app.get('/api/inventory/stock', requirePermission('inventory.read'), async (req, res) => {
  try {
    const rows = await all(`
      SELECT
        vs.id as stock_id,
        vs.item_id,
        vs.variation_leaf_node_id,
        vs.quantity,
        vs.location_id,
        vs.variation_path_label,
        vs.variation_path_node_ids_json,
        vs.custom_variation_values_json AS stock_custom_variation_values_json,
        vs.updated_at,
        i.name as item_name,
        i.unit_id,
        i.naming_format
      FROM variation_stock vs
      JOIN items i ON vs.item_id = i.id
      ORDER BY vs.item_id ASC, vs.variation_leaf_node_id ASC
    `);
    const stock = [];
    for (const row of rows) {
      const selection = await resolveLeafSelectionFromDb(row.variation_leaf_node_id);
      const storedPathNodeIds = parseJson(row.variation_path_node_ids_json, []);
      const effectivePathNodeIds = storedPathNodeIds.length > 0
        ? storedPathNodeIds
        : (selection?.nodeIds || []);
      const customVariationRows = await all(
        `
        SELECT ? AS custom_variation_values_json
        UNION ALL
        SELECT custom_variation_values_json
        FROM materials
        WHERE linked_item_id = ?
          AND COALESCE(linked_variation_leaf_node_id, 0) = ?
          AND TRIM(COALESCE(custom_variation_values_json, '')) NOT IN ('', '{}')
        UNION ALL
        SELECT custom_variation_values_json
        FROM order_items
        WHERE item_id = ?
          AND COALESCE(variation_leaf_node_id, 0) = ?
          AND TRIM(COALESCE(custom_variation_values_json, '')) NOT IN ('', '{}')
        UNION ALL
        SELECT custom_variation_values_json
        FROM delivery_challan_items
        WHERE item_id = ?
          AND COALESCE(variation_leaf_node_id, 0) = ?
          AND TRIM(COALESCE(custom_variation_values_json, '')) NOT IN ('', '{}')
        `,
        [
          row.stock_custom_variation_values_json || '{}',
          row.item_id,
          row.variation_leaf_node_id,
          row.item_id,
          row.variation_leaf_node_id,
          row.item_id,
          row.variation_leaf_node_id,
        ],
      );
      stock.push({
        ...row,
        custom_variation_values: mergeCustomVariationValueJsonRows(customVariationRows),
        variation_path_label: row.variation_path_label || '',
        variation_path_node_ids: effectivePathNodeIds,
        variation_path: effectivePathNodeIds.map((nodeId, index) => ({
          node_id: nodeId,
          value: selection?.nodeIds?.includes(nodeId)
            ? (selection?.segments?.[selection.nodeIds.indexOf(nodeId)] || '')
            : '',
        })),
      });
    }
    res.json({ success: true, stock });
  } catch (error) {
    res.status(500).json({ success: false, stock: [], error: error.message });
  }
});

app.get('/api/search', requirePermission('inventory.read'), async (req, res) => {
  try {
    const q = (req.query.q || '').trim();
    if (!q) {
      return res.json({ success: true, results: [] });
    }
    
    const tokens = q.split(/\s+/).filter(Boolean);
    const itemConditions = tokens.map(() => '(i.name LIKE ? OR i.display_name LIKE ? OR i.alias LIKE ? OR v.variation_path_label LIKE ?)').join(' AND ');
    const itemParams = tokens.flatMap(t => {
      const l = `%${t}%`;
      return [l, l, l, l];
    });
    
    const items = await all(
      `SELECT i.id, i.name, i.display_name, i.quantity as base_quantity, g.name as category_name,
              v.variation_leaf_node_id, v.variation_path_label, v.quantity as var_quantity,
              i.naming_format
       FROM items i
       LEFT JOIN groups g ON i.group_id = g.id
       LEFT JOIN variation_stock v ON i.id = v.item_id
       WHERE ${itemConditions || '1=1'}
       LIMIT 50`,
      itemParams
    );
    
    const materialConditions = tokens.map(() => '(name LIKE ? OR barcode LIKE ? OR supplier LIKE ?)').join(' AND ');
    const materialParams = tokens.flatMap(t => {
      const l = `%${t}%`;
      return [l, l, l];
    });

    const materials = await all(
      `SELECT barcode, name, type, on_hand_qty 
       FROM materials 
       WHERE ${materialConditions || '1=1'} 
       LIMIT 50`,
      materialParams
    );

    const clicks = await all(
      `SELECT entity_type, entity_id, COUNT(*) as click_count 
       FROM search_clicks 
       WHERE user_id = ? 
       GROUP BY entity_type, entity_id`,
      [req.user.id]
    );
    const clickMap = {};
    for (const c of clicks) {
      clickMap[`${c.entity_type}_${c.entity_id}`] = c.click_count;
    }

    // Fetch configurations for items
    const itemConfigs = {};
    const itemIds = [...new Set(items.map(i => i.id))];
    if (itemIds.length > 0) {
      const qs = itemIds.map(() => '?').join(',');
      const props = await all(`SELECT item_id, property_key, display_name FROM item_property_schema WHERE item_id IN (${qs}) ORDER BY sort_order ASC`, itemIds);
      const allNodes = await all(`SELECT id, item_id, parent_node_id, name, display_name FROM item_variation_nodes WHERE item_id IN (${qs}) AND is_archived = 0 ORDER BY position ASC`, itemIds);
      const stockRows = await all(`SELECT item_id, custom_variation_values_json, variation_path_node_ids_json FROM variation_stock WHERE item_id IN (${qs})`, itemIds);
      
      const nodeMap = {};
      allNodes.forEach(n => nodeMap[n.id] = n);
      
      const schemaMap = {};
      props.forEach(p => {
        if (!schemaMap[p.item_id]) schemaMap[p.item_id] = {};
        schemaMap[p.item_id][p.property_key] = p.display_name;
      });

      const configsMap = {};
      for (const id of itemIds) {
        configsMap[id] = new Map();
      }

      // Initialize with base configs to preserve order
      allNodes.forEach(n => {
        if (!n.parent_node_id) {
          configsMap[n.item_id].set(n.display_name || n.name, new Set());
        }
      });
      props.forEach(p => {
        configsMap[p.item_id].set(p.display_name, new Set());
      });

      for (const row of stockRows) {
        const itemId = row.item_id;
        
        try {
          const pathIds = row.variation_path_node_ids_json ? JSON.parse(row.variation_path_node_ids_json) : [];
          for (const id of pathIds) {
            let curr = nodeMap[id];
            let value = curr ? (curr.display_name || curr.name) : null;
            let rootName = null;
            while (curr) {
              if (!curr.parent_node_id) {
                rootName = curr.display_name || curr.name;
                break;
              }
              curr = nodeMap[curr.parent_node_id];
            }
            if (rootName && value) {
              if (!configsMap[itemId].has(rootName)) configsMap[itemId].set(rootName, new Set());
              configsMap[itemId].get(rootName).add(value);
            }
          }
        } catch(e) {}
        
        try {
          if (row.custom_variation_values_json) {
            const customVals = typeof row.custom_variation_values_json === 'string' ? JSON.parse(row.custom_variation_values_json) : row.custom_variation_values_json;
            if (customVals && typeof customVals === 'object' && !Array.isArray(customVals)) {
              for (const [key, val] of Object.entries(customVals)) {
                if (!val) continue;
                const dispName = schemaMap[itemId]?.[key] || key;
                if (!configsMap[itemId].has(dispName)) configsMap[itemId].set(dispName, new Set());
                configsMap[itemId].get(dispName).add(String(val));
              }
            }
          }
        } catch(e) {}
      }
      
      for (const itemId of itemIds) {
        const arr = [];
        for (const [k, vSet] of configsMap[itemId].entries()) {
          arr.push({
            name: k,
            values: Array.from(vSet)
          });
        }
        itemConfigs[itemId] = arr;
      }
    }

    const results = [
      ...items.map(item => {
        const id = String(item.id);
        const isVariation = item.variation_leaf_node_id != null;
        let label = item.display_name || item.name;
        if (isVariation && item.variation_path_label) {
          label = `${label} - ${item.variation_path_label}`;
        }
        
        const qty = isVariation ? (item.var_quantity || 0) : (item.base_quantity || 0);
        
        return {
          type: 'item',
          id: isVariation ? `${id}_${item.variation_leaf_node_id}` : id,
          label: label,
          subLabel: `Item #${item.id} • Stock: ${qty}`,
          metadata: {
            stock: qty,
            category: item.category_name || 'Item',
            baseItemId: id,
            variationId: item.variation_leaf_node_id,
            configurations: itemConfigs[item.id] || [],
          },
          score: clickMap[`item_${id}`] || 0
        };
      }),
      ...materials.map(mat => {
        return {
          type: 'material',
          id: mat.barcode,
          label: mat.name,
          subLabel: `Material (${mat.type}) • Stock: ${mat.on_hand_qty || 0}`,
          metadata: {
            stock: mat.on_hand_qty,
            category: mat.type || 'Material',
          },
          score: clickMap[`material_${mat.barcode}`] || 0
        };
      })
    ];
    
    results.sort((a, b) => b.score - a.score);
    
    res.json({ success: true, results });
  } catch (error) {
    res.status(500).json({ success: false, results: [], error: error.message });
  }
});

app.get('/api/search/history', requirePermission('inventory.read'), async (req, res) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.json({ success: true, history: [] });
    }
    const history = await all(
      'SELECT query, MAX(created_at) as last_searched FROM search_history WHERE user_id = ? GROUP BY query ORDER BY last_searched DESC LIMIT 10',
      [userId]
    );
    res.json({ success: true, history: history.map(h => h.query) });
  } catch (error) {
    res.status(500).json({ success: false, history: [], error: error.message });
  }
});

app.post('/api/search/history', requirePermission('inventory.read'), async (req, res) => {
  try {
    const userId = req.user?.id;
    const { query } = req.body;
    if (userId && query) {
      await run(
        'INSERT INTO search_history (user_id, query, created_at) VALUES (?, ?, ?)',
        [userId, String(query).trim(), new Date().toISOString()]
      );
    }
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/search/clicks', requirePermission('inventory.read'), async (req, res) => {
  try {
    const userId = req.user?.id;
    const { query, entityType, entityId, entityLabel } = req.body;
    if (userId && entityType && entityId) {
      await run(
        'INSERT INTO search_clicks (user_id, query, entity_type, entity_id, entity_label, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [userId, query || '', entityType, String(entityId), entityLabel || '', new Date().toISOString()]
      );
    }
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/materials', requirePermission('inventory.read'), async (req, res) => {
  try {
    const rows = await all(
      'SELECT * FROM materials ORDER BY kind ASC, created_at DESC, barcode ASC',
    );
    res.json({ success: true, materials: rows.map(rowToMaterialDto) });
  } catch (error) {
    res.status(500).json({ success: false, materials: [], error: error.message });
  }
});

app.get('/api/inventory/health', requirePermission('inventory.read'), async (_req, res) => {
  try {
    const health = await getInventoryHealthSummary();
    res.json({ success: true, health, error: null });
  } catch (error) {
    res.status(500).json({
      success: false,
      health: null,
      error: error.message,
    });
  }
});

app.get('/api/materials/:barcode', requirePermission('inventory.read'), async (req, res) => {
  try {
    const row = await getMaterialRowByBarcode(req.params.barcode);
    if (!row) {
      res.status(404).json({
        success: false,
        material: null,
        error: `No material found for barcode ${req.params.barcode}.`,
      });
      return;
    }
    const groupConfiguration = await getMaterialGroupGovernance(row.id);
    res.json({
      success: true,
      material: rowToMaterialDto(row),
      groupConfiguration,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, material: null, error: error.message });
  }
});

app.get('/api/materials/:barcode/detail', requirePermission('inventory.read'), async (req, res) => {
  try {
    const detail = await getMaterialControlTowerDetail(req.params.barcode);
    if (!detail) {
      res.status(404).json({
        success: false,
        material: null,
        error: `No material found for barcode ${req.params.barcode}.`,
      });
      return;
    }
    const row = await getMaterialRowByBarcode(req.params.barcode);
    const groupConfiguration = row
      ? await getMaterialGroupGovernance(row.id)
      : { selectedItemIds: [], selectedItems: [], propertyDrafts: [] };
    res.json({
      success: true,
      ...detail,
      groupConfiguration,
      error: null,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      material: null,
      error: error.message,
    });
  }
});

app.get('/api/units', requirePermission('config.read'), async (req, res) => {
  try {
    const rows = await getUnitsWithUsage();
    res.json({ success: true, units: rows.map(rowToUnitDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, units: [], error: error.message });
  }
});

app.post('/api/units', requirePermission('config.write'), async (req, res) => {
  try {
    const unit = await saveUnit(req.body || {});
    trackCreate('units', unit.id, unit, req);
    res.status(201).json({ success: true, unit: rowToUnitDto(unit), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      unit: null,
      error: error.message,
    });
  }
});

app.patch('/api/units/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const before = await get('SELECT * FROM units WHERE id = ?', [id]);
    const unit = await saveUnit({
      ...(req.body || {}),
      id,
    });
    const after = await get('SELECT * FROM units WHERE id = ?', [id]);
    trackUpdate('units', id, before, after, req);
    res.json({ success: true, unit: rowToUnitDto(unit), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      unit: null,
      error: error.message,
    });
  }
});

app.get('/api/favorites', async (req, res) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ success: false, error: 'Unauthorized' });
    }
    const rows = await all(
      'SELECT item_id, variation_leaf_node_id, variation_path_label, variation_path_node_ids, custom_variation_values FROM user_favorite_items WHERE user_id = ?',
      [userId]
    );
    res.json({
      success: true,
      favorites: rows.map(r => ({
        itemId: r.item_id,
        variationLeafNodeId: r.variation_leaf_node_id,
        variationPathLabel: r.variation_path_label,
        variationPathNodeIds: JSON.parse(r.variation_path_node_ids),
        customVariationValues: JSON.parse(r.custom_variation_values),
      })),
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/favorites', async (req, res) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ success: false, error: 'Unauthorized' });
    }
    const {
      itemId,
      variationLeafNodeId = 0,
      variationPathLabel = '',
      variationPathNodeIds = [],
      customVariationValues = {}
    } = req.body;

    if (!itemId) {
      return res.status(400).json({ success: false, error: 'itemId is required' });
    }

    await run(
      `INSERT INTO user_favorite_items (
        user_id, item_id, variation_leaf_node_id, variation_path_label, variation_path_node_ids, custom_variation_values, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT DO NOTHING`,
      [
        userId,
        itemId,
        variationLeafNodeId,
        variationPathLabel,
        JSON.stringify(variationPathNodeIds),
        JSON.stringify(customVariationValues)
      ]
    );
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/favorites/:itemId/:variationLeafNodeId', async (req, res) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ success: false, error: 'Unauthorized' });
    }
    const itemId = Number(req.params.itemId);
    const variationLeafNodeId = Number(req.params.variationLeafNodeId);

    await run(
      'DELETE FROM user_favorite_items WHERE user_id = ? AND item_id = ? AND variation_leaf_node_id = ?',
      [userId, itemId, variationLeafNodeId]
    );
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/units/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const before = await get('SELECT * FROM units WHERE id = ?', [id]);
    await trashAndDelete('units', id, req);
    trackDelete('units', id, before, req);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/groups', requirePermission('config.read'), async (req, res) => {
  try {
    const rows = await getGroupsWithUsage();
    res.json({ success: true, groups: rows.map(rowToGroupDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, groups: [], error: error.message });
  }
});

app.get('/api/clients', requirePermission('config.read'), async (req, res) => {
  try {
    const rows = await getClientsWithUsage();
    res.json({ success: true, clients: rows.map(rowToClientDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, clients: [], error: error.message });
  }
});

app.get('/api/clients/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const row = await get(`
      SELECT
        clients.*,
        (SELECT COUNT(*) FROM order_items WHERE order_items.client_id = clients.id) AS usage_count
      FROM clients
      WHERE id = ?
    `, [req.params.id]);
    if (!row) {
      return res.status(404).json({ success: false, client: null, error: 'Not found' });
    }
    res.json({ success: true, client: rowToClientDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, client: null, error: error.message });
  }
});

// --- SUB-CONTRACTORS ENDPOINTS ---

function rowToSubContractorDto(row) {
  if (!row) return null;
  return {
    id: row.id,
    clientId: row.client_id,
    name: row.name,
    phone: row.phone,
    email: row.email,
    notes: row.notes,
    gstNumber: row.gst_number,
    address: row.address,
    photoUrl: row.photo_url,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    clientName: row.client_name,
  };
}

app.get('/api/sub-contractors', requirePermission('config.read'), async (req, res) => {
  try {
    const rows = await get('SELECT name FROM sqlite_master WHERE type=\'table\' AND name=\'sub_contractors\'');
    if (!rows) {
      return res.json({ success: true, subContractors: [], error: null });
    }
    const dataRows = await all(`
      SELECT s.*, c.name as client_name 
      FROM sub_contractors s
      LEFT JOIN clients c ON s.client_id = c.id
      ORDER BY s.name ASC
    `);
    res.json({ success: true, subContractors: dataRows.map(rowToSubContractorDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, subContractors: [], error: error.message });
  }
});

app.get('/api/clients/:clientId/sub-contractors', requirePermission('config.read'), async (req, res) => {
  try {
    const clientId = Number(req.params.clientId);
    const rows = await get('SELECT name FROM sqlite_master WHERE type=\'table\' AND name=\'sub_contractors\'');
    if (!rows) {
      return res.json({ success: true, subContractors: [], error: null });
    }
    const dataRows = await all('SELECT * FROM sub_contractors WHERE client_id = ? ORDER BY name ASC', [clientId]);
    res.json({ success: true, subContractors: dataRows.map(rowToSubContractorDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, subContractors: [], error: error.message });
  }
});

app.post('/api/clients/:clientId/sub-contractors', requirePermission('config.write'), async (req, res) => {
  try {
    const clientId = Number(req.params.clientId);
    const { name, phone, email, notes, gstNumber, address, photoUrl } = req.body || {};
    
    if (!name || !String(name).trim()) {
      return res.status(400).json({ success: false, error: 'Name is required' });
    }
    
    const now = new Date().toISOString();
    const result = await run(
      `INSERT INTO sub_contractors (client_id, name, phone, email, notes, gst_number, address, photo_url, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [clientId, String(name).trim(), phone || '', email || '', notes || '', gstNumber || '', address || '', photoUrl || '', now, now]
    );
    
    const row = await get('SELECT * FROM sub_contractors WHERE id = ?', [result.lastID]);
    res.status(201).json({ success: true, subContractor: rowToSubContractorDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, subContractor: null, error: error.message });
  }
});

app.put('/api/sub-contractors/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { name, phone, email, notes, gstNumber, address, photoUrl } = req.body || {};
    
    if (!name || !String(name).trim()) {
      return res.status(400).json({ success: false, error: 'Name is required' });
    }
    
    const now = new Date().toISOString();
    await run(
      `UPDATE sub_contractors 
       SET name = ?, phone = ?, email = ?, notes = ?, gst_number = ?, address = ?, photo_url = ?, updated_at = ?
       WHERE id = ?`,
      [String(name).trim(), phone || '', email || '', notes || '', gstNumber || '', address || '', photoUrl || '', now, id]
    );
    
    const row = await get('SELECT * FROM sub_contractors WHERE id = ?', [id]);
    if (!row) {
      return res.status(404).json({ success: false, error: 'Not found' });
    }
    res.json({ success: true, subContractor: rowToSubContractorDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, subContractor: null, error: error.message });
  }
});

app.delete('/api/sub-contractors/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    await run('DELETE FROM sub_contractors WHERE id = ?', [id]);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

function actorFromRequest(req) {
  return {
    id: req.user?.id || null,
    name: req.user?.name || 'System',
    role: req.user?.role || 'system',
  };
}

app.get('/api/company-profile', requirePermission('config.read'), async (_req, res) => {
  try {
    const profile = await getActiveCompanyProfile();
    res.json({ success: true, data: rowToCompanyProfileDto(profile), error: null });
  } catch (error) {
    res.status(500).json({ success: false, data: null, error: error.message });
  }
});

app.put('/api/company-profile', requirePermission('config.write'), async (req, res) => {
  try {
    const profile = await saveCompanyProfile(req.body || {});
    res.json({ success: true, data: rowToCompanyProfileDto(profile), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      error: error.message,
    });
  }
});

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

// Personal data reset: any signed-in user (including staff) can wipe THEIR OWN
// account-scoped data — favorites and search history — without touching shared
// business records. Admins use /api/admin/clear-data for a full workspace wipe.
app.post('/api/me/clear-data', requireAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    await run('BEGIN TRANSACTION');
    try {
      await run('DELETE FROM user_favorite_items WHERE user_id = ?', [userId]);
      await run('DELETE FROM search_history WHERE user_id = ?', [userId]);
      await run('DELETE FROM search_clicks WHERE user_id = ?', [userId]);
      await run('COMMIT');
    } catch (inner) {
      await run('ROLLBACK');
      throw inner;
    }
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, error: error.message });
  }
});

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

const handleListChallans = async (req, res) => {
  try {
    const challans = await listDeliveryChallans({
      type: String(req.query.type || '').trim(),
      status: String(req.query.status || '').trim(),
      search: String(req.query.search || '').trim(),
      dateFrom: String(req.query.date_from || req.query.dateFrom || '').trim(),
      dateTo: String(req.query.date_to || req.query.dateTo || '').trim(),
      orderId: req.query.order_id || req.query.orderId,
      vendorId: req.query.vendor_id || req.query.vendorId,
      itemId: req.query.item_id || req.query.itemId,
      variationLeafNodeId:
        req.query.variation_leaf_node_id || req.query.variationLeafNodeId,
    });
    res.json({ success: true, data: challans, error: null });
  } catch (error) {
    res.status(500).json({ success: false, data: [], message: error.message, error: error.message });
  }
};

app.get('/api/challans', requirePermission('config.read'), handleListChallans);
app.get('/api/delivery-challans', requirePermission('config.read'), handleListChallans);

const handleCreateChallan = async (req, res) => {
  try {
    const challan = await saveDeliveryChallan(req.body || {}, actorFromRequest(req), req);
    const warning = await challanNumberWarning(
      req.body?.challanNo ?? req.body?.challan_no,
      challan.type,
    );
    const challanDto = await rowToDeliveryChallanDto(challan);
    if (io) {
      io.emit('challan_generated_ok', challanDto);
    }
    res.status(201).json({
      success: true,
      data: challanDto,
      warnings: warning ? [warning] : [],
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
};

app.post('/api/challans', requirePermission('config.write'), handleCreateChallan);
app.post('/api/delivery-challans', requirePermission('config.write'), handleCreateChallan);

app.get('/api/orders/:orderId/delivery-challans', requirePermission('config.read'), async (req, res) => {
  try {
    const orderId = Number(req.params.orderId);
    if (!Number.isInteger(orderId) || orderId <= 0) {
      res.status(400).json({
        success: false,
        data: [],
        message: 'Invalid order id.',
        error: 'Invalid order id.',
      });
      return;
    }
    const challans = await listDeliveryChallans({ orderId, type: 'delivery' });
    res.json({ success: true, data: challans, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: [],
      message: error.message,
      error: error.message,
    });
  }
});

const handleGetChallan = async (req, res) => {
  try {
    const challan = await getDeliveryChallanRowById(Number(req.params.id));
    if (!challan) {
      res.status(404).json({
        success: false,
        data: null,
        message: 'Challan not found.',
        error: 'Challan not found.',
      });
      return;
    }
    res.json({ success: true, data: await rowToDeliveryChallanDto(challan), error: null });
  } catch (error) {
    res.status(500).json({ success: false, data: null, message: error.message, error: error.message });
  }
};

app.get('/api/challans/:id', requirePermission('config.read'), handleGetChallan);
app.get('/api/delivery-challans/:id', requirePermission('config.read'), handleGetChallan);

const handleUpdateChallan = async (req, res) => {
  try {
    const challan = await saveDeliveryChallan(
      { ...(req.body || {}), id: Number(req.params.id) },
      actorFromRequest(req),
      req,
    );
    const warning = await challanNumberWarning(
      req.body?.challanNo ?? req.body?.challan_no,
      challan.type,
    );
    res.json({
      success: true,
      data: await rowToDeliveryChallanDto(challan),
      warnings: warning ? [warning] : [],
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
};

app.put('/api/challans/:id', requirePermission('config.write'), handleUpdateChallan);
app.put('/api/delivery-challans/:id', requirePermission('config.write'), handleUpdateChallan);

const handleIssueChallan = async (req, res) => {
  try {
    const challan = await issueDeliveryChallan(Number(req.params.id), actorFromRequest(req));
    res.json({ success: true, data: await rowToDeliveryChallanDto(challan), error: null });
    
    // Emit item_updated for each item affected if stock was modified
    if (io && challan && Number(challan.maintain_stocks || 1) !== 0) {
      const items = await all('SELECT item_id FROM delivery_challan_items WHERE challan_id = ?', [challan.id]);
      const uniqueItemIds = new Set(items.map(i => i.item_id).filter(id => Number.isFinite(id) && id > 0));
      for (const itemId of uniqueItemIds) {
        io.emit('item_updated', { id: itemId });
      }
    }
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
};

app.post('/api/challans/:id/issue', requirePermission('config.write'), handleIssueChallan);
app.post('/api/delivery-challans/:id/issue', requirePermission('config.write'), handleIssueChallan);

// ── INTERNAL-USE CHALLAN RECONCILIATION ──
// Settle a consumed internal-use challan: every line's taken quantity is split
// across five buckets (scrap / leftover / lost / rejection / finished goods),
// each bucket reverted back into inventory as a named item + lot under the
// Primary Group's matching sub-group, then the challan is marked completed and
// (once all of an order's use challans are reconciled) the order is completed.
//
// This mirrors the pipeline-run scrap/leftover mechanic (see /api/production-scrap
// and PUT /runs/:id/node-metrics): create a `materials` lot linked to a reused
// group + item, then apply a `receive` inventory movement. Groups/items are
// reused when they already exist; items are named "<bucket>_<itemName>_<date>".
const RECONCILE_BUCKETS = [
  { key: 'scrap', prefix: 'scrap', group: 'Scrap' },
  { key: 'leftover', prefix: 'leftover', group: 'Leftover' },
  { key: 'lost', prefix: 'lost', group: 'Lost' },
  { key: 'rejection', prefix: 'rejection', group: 'Rejection' },
  { key: 'finishedGoods', prefix: 'finished_goods', group: 'Finished Goods' },
];

async function ensureReconcilePrimaryGroup() {
  let primary = await get(
    `SELECT id, unit_id FROM groups WHERE lower(name) = 'primary group' AND parent_group_id IS NULL ORDER BY id LIMIT 1`,
  );
  if (primary) return primary;
  const fallbackUnit = await get('SELECT id FROM units ORDER BY id LIMIT 1');
  const now = nowIso();
  const res = await run(
    `INSERT INTO groups (name, group_type, group_structure, description, parent_group_id, unit_id, is_archived, created_at, updated_at)
     VALUES ('Primary Group', 'item', 'hierarchical', 'Root item group', NULL, ?, 0, ?, ?)`,
    [fallbackUnit?.id || null, now, now],
  );
  return { id: res.lastID, unit_id: fallbackUnit?.id || null };
}

async function ensureReconcileSubGroup(name, parentGroupId, unitId) {
  const existing = await get(
    `SELECT id FROM groups WHERE lower(name) = lower(?) AND parent_group_id = ? AND group_type = 'item' ORDER BY id LIMIT 1`,
    [name, parentGroupId],
  );
  if (existing) return existing.id;
  const now = nowIso();
  const res = await run(
    `INSERT INTO groups (name, group_type, group_structure, description, parent_group_id, unit_id, is_archived, created_at, updated_at)
     VALUES (?, 'item', 'hierarchical', 'Internal-use reconciliation returns', ?, ?, 0, ?, ?)`,
    [name, parentGroupId, unitId, now, now],
  );
  return res.lastID;
}

async function ensureReconcileItem(name, groupId, unitId) {
  const existing = await get(
    `SELECT id FROM items WHERE lower(name) = lower(?) AND group_id = ? ORDER BY id LIMIT 1`,
    [name, groupId],
  );
  if (existing) return existing.id;
  const now = nowIso();
  const res = await run(
    `INSERT INTO items (name, alias, short_code, display_name, quantity, group_id, unit_id, is_archived, created_at, updated_at)
     VALUES (?, '', '', ?, 0, ?, ?, 0, ?, ?)`,
    [name, name, groupId, unitId, now, now],
  );
  return res.lastID;
}

// Reconciliation settles the consumed WEIGHT (kg), so the reverted lots/items
// are measured in kilograms. Reuse an existing kg unit or create one.
async function ensureKgUnit() {
  const existing = await get(
    `SELECT id FROM units WHERE lower(symbol) = 'kg' OR lower(name) IN ('kg', 'kilogram', 'kilograms') ORDER BY id LIMIT 1`,
  );
  if (existing) return existing.id;
  const now = nowIso();
  const res = await run(
    `INSERT INTO units (name, symbol, notes, is_archived, created_at, updated_at)
     VALUES ('Kilogram', 'kg', 'Reconciliation weight unit', 0, ?, ?)`,
    [now, now],
  );
  return res.lastID;
}

// Best-effort order completion: the reconcile has already committed, so a
// blocked lifecycle transition must not fail the request. Steps a draft/
// notStarted line up through inProgress so it can reach the terminal completed.
async function completeOrderItemBestEffort(orderItemId, actor) {
  try {
    const order = await getOrderRowById(orderItemId);
    if (!order || order.status === 'completed') return false;
    if (order.status === 'draft' || order.status === 'notStarted') {
      await updateOrderLifecycle({ id: orderItemId, status: 'inProgress', actor });
    }
    await updateOrderLifecycle({ id: orderItemId, status: 'completed', actor });
    return true;
  } catch (error) {
    console.error(`[reconcile] order ${orderItemId} completion skipped: ${error.message}`);
    return false;
  }
}

// The order number a use challan was consumed for. saveDeliveryChallan does not
// persist order linkage for internal challans, so the reliable reference is the
// "Consumption for order <orderNo>" text the Use editor writes into
// internal_purpose. Real order-id linkage (if any) is preferred when present.
async function resolveReconcileOrderNo(challanRow) {
  let orderIds = await getDeliveryChallanOrderIds(challanRow.id);
  if (orderIds.length === 0 && Number(challanRow.order_id || 0) > 0) {
    orderIds = [Number(challanRow.order_id)];
  }
  if (orderIds.length > 0) {
    const rows = await getOrderRowsByIds(orderIds);
    const no = rows.map((r) => String(r.order_no || '').trim()).find(Boolean);
    if (no) return no;
  }
  if (String(challanRow.order_no || '').trim()) {
    return String(challanRow.order_no).trim();
  }
  const match = String(challanRow.internal_purpose || '').match(
    /consumption for order\s+(.+)$/i,
  );
  return match ? match[1].trim() : '';
}

// How many OTHER internal-use challans for the same order are still awaiting
// reconciliation (issued, same "Consumption for order …" reference). Zero means
// this reconcile was the last one, so the order can be marked completed.
async function pendingUseChallanCountForOrderNo(internalPurpose, excludeChallanId) {
  const row = await get(
    `SELECT COUNT(*) AS c FROM delivery_challans
     WHERE type = 'internal' AND status = 'issued' AND id <> ?
       AND lower(internal_purpose) = lower(?)`,
    [excludeChallanId, internalPurpose],
  );
  return Number(row?.c || 0);
}

const handleReconcileChallan = async (req, res) => {
  const challanId = Number(req.params.id);
  try {
    if (!Number.isInteger(challanId) || challanId <= 0) {
      const error = new Error('Invalid challan id.');
      error.statusCode = 400;
      throw error;
    }
    const challan = await getDeliveryChallanRowById(challanId);
    if (!challan) {
      const error = new Error('Challan not found.');
      error.statusCode = 404;
      throw error;
    }
    if (normalizeChallanType(challan.type) !== 'internal') {
      const error = new Error('Only internal-use challans can be settled.');
      error.statusCode = 400;
      throw error;
    }
    if (challan.status === 'completed' || String(challan.reconciliation_json || '').trim()) {
      const error = new Error('This challan has already been settled.');
      error.statusCode = 409;
      throw error;
    }

    const items = await getDeliveryChallanItems(challanId);
    if (items.length === 0) {
      const error = new Error('This challan has no lines to settle.');
      error.statusCode = 400;
      throw error;
    }

    // Index the client's per-line splits by the challan line id they settle.
    const requestLines = Array.isArray(req.body?.lines) ? req.body.lines : [];
    const splitByLineId = new Map();
    for (const line of requestLines) {
      const lineId = Number(line?.challanItemId || line?.id || 0);
      if (Number.isInteger(lineId) && lineId > 0) splitByLineId.set(lineId, line);
    }

    // Validate every line balances exactly before mutating anything.
    const plan = [];
    for (const item of items) {
      const split = splitByLineId.get(Number(item.id));
      if (!split) {
        const error = new Error(`Missing amounts for line "${item.particulars || item.id}".`);
        error.statusCode = 400;
        throw error;
      }
      const buckets = split.buckets || {};
      const amounts = {};
      let sum = 0;
      for (const bucket of RECONCILE_BUCKETS) {
        const value = Number(buckets[bucket.key] || 0);
        if (!Number.isFinite(value) || value < 0) {
          const error = new Error(`Invalid ${bucket.key} amount for line "${item.particulars || item.id}".`);
          error.statusCode = 400;
          throw error;
        }
        amounts[bucket.key] = value;
        sum += value;
      }
      // Reconciliation settles the WEIGHT taken (kg), not the piece count.
      const taken = Number(item.weight || 0);
      if (Math.abs(sum - taken) > 0.01) {
        const error = new Error(
          `Line "${item.particulars || item.id}" must settle its full ${taken} kg; got ${Number(sum.toFixed(4))} kg.`,
        );
        error.statusCode = 400;
        throw error;
      }
      plan.push({ item, amounts, taken });
    }

    const actor = actorFromRequest(req);
    const primaryGroup = await ensureReconcilePrimaryGroup();
    const kgUnitId = await ensureKgUnit();
    const dateStr = new Date().toISOString().slice(0, 10);
    const breakdown = [];
    const affectedItemIds = new Set();
    const subGroupCache = new Map();

    await run('BEGIN TRANSACTION');
    try {
      for (const entry of plan) {
        const { item, amounts, taken } = entry;
        const sourceItem = item.item_id
          ? await get(
              `SELECT i.id, i.name, i.display_name, i.unit_id, u.symbol AS unit_symbol
               FROM items i LEFT JOIN units u ON u.id = i.unit_id WHERE i.id = ?`,
              [Number(item.item_id)],
            )
          : null;
        const baseName = String(
          sourceItem?.name || item.particulars || `item-${item.item_id || item.id}`,
        ).trim();
        // Reverted quantities are weights, so recon items/lots are in kg
        // regardless of the source item's own unit (which may be pieces).
        const unitId = kgUnitId;
        const unitSymbol = 'kg';

        const lineResult = {
          challanItemId: item.id,
          sourceItemId: item.item_id || null,
          itemName: baseName,
          variationLeafNodeId: Number(item.variation_leaf_node_id || 0),
          unit: unitSymbol,
          taken,
          buckets: amounts,
          reverts: [],
        };

        for (const bucket of RECONCILE_BUCKETS) {
          const qty = amounts[bucket.key];
          if (!(qty > 0)) continue;

          let subGroupId = subGroupCache.get(bucket.group);
          if (!subGroupId) {
            subGroupId = await ensureReconcileSubGroup(bucket.group, primaryGroup.id, unitId);
            subGroupCache.set(bucket.group, subGroupId);
          }

          const reconItemName = `${bucket.prefix}_${baseName}_${dateStr}`;
          const reconItemId = await ensureReconcileItem(reconItemName, subGroupId, unitId);
          affectedItemIds.add(reconItemId);

          const lotBarcode = `LOT-RECON-${challanId}-${bucket.prefix}-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
          await run(
            `INSERT INTO materials (
              barcode, name, type, kind, group_mode,
              linked_group_id, linked_item_id, linked_variation_leaf_node_id,
              unit, unit_id, inventory_state, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              lotBarcode, reconItemName, 'Reconciled', 'lot', 'tracked',
              subGroupId, reconItemId, 0,
              unitSymbol, unitId, 'available', nowIso(),
            ],
          );

          await applyInventoryMovementCore(
            {
              barcode: lotBarcode,
              movementType: 'receive',
              qty,
              primaryQty: qty,
              uom: unitSymbol,
              toLocationId: 'MAIN',
              reasonCode: 'challan_reconcile',
              referenceType: 'challan_reconcile',
              referenceId: String(challanId),
              lotCode: lotBarcode,
              actor: actor?.id || null,
            },
            { useTransaction: false },
          );

          lineResult.reverts.push({
            bucket: bucket.key,
            subGroupId,
            itemId: reconItemId,
            itemName: reconItemName,
            lotBarcode,
            qty,
          });
        }

        breakdown.push(lineResult);
      }

      const now = nowIso();
      await run(
        `UPDATE delivery_challans SET status = 'completed', reconciliation_json = ?, updated_by = ?, updated_at = ? WHERE id = ?`,
        [JSON.stringify(breakdown), actor?.id || null, now, challanId],
      );

      await run('COMMIT');
    } catch (error) {
      await run('ROLLBACK');
      throw error;
    }

    // Order completion runs after COMMIT because updateOrderLifecycle manages
    // its own transaction (SQLite has no nested transactions). Once no other use
    // challan for this order is still awaiting reconciliation, every order line
    // for that order number is marked completed (best-effort).
    const completedOrderIds = [];
    const orderNo = await resolveReconcileOrderNo(challan);
    if (orderNo) {
      const pending = await pendingUseChallanCountForOrderNo(
        challan.internal_purpose || '',
        challanId,
      );
      if (pending === 0) {
        const orderItems = await all(
          `SELECT id FROM order_items WHERE order_no = ?`,
          [orderNo],
        );
        for (const orderItem of orderItems) {
          const done = await completeOrderItemBestEffort(orderItem.id, actor);
          if (done) completedOrderIds.push(orderItem.id);
        }
      }
    }

    const updatedRow = await getDeliveryChallanRowById(challanId);
    const dto = await rowToDeliveryChallanDto(updatedRow);
    if (io) {
      io.emit('challan_generated_ok', dto);
      for (const itemId of affectedItemIds) io.emit('item_updated', { id: itemId });
    }

    res.json({
      success: true,
      data: dto,
      reconciliation: { breakdown, completedOrderIds },
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
};

app.post('/api/challans/:id/reconcile', requirePermission('config.write'), handleReconcileChallan);
app.post('/api/delivery-challans/:id/reconcile', requirePermission('config.write'), handleReconcileChallan);

const handleGetCancelOptions = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const invoices = await all(
      `SELECT DISTINCT ih.id, ih.status 
       FROM invoice_headers ih 
       JOIN invoice_lines il ON ih.id = il.invoice_id 
       WHERE il.challan_id = ?`, [id]
    );
    const actions = [];
    actions.push({
      key: 'block',
      label: 'Cancel linked invoices manually',
      description: 'You must handle each linked invoice first, then cancel the challan.',
      requiresConfirmation: false
    });
    const drafts = invoices.filter(i => i.status === 'draft');
    const issued = invoices.filter(i => i.status !== 'draft');
    if (drafts.length > 0 && issued.length === 0) {
      actions.push({
        key: 'cascade_delete_drafts_only',
        label: `Delete ${drafts.length} draft invoice(s) and cancel challan`,
        description: 'Draft invoices will be permanently deleted. No issued invoices are affected.',
        requiresConfirmation: true
      });
    }
    res.json({ success: true, challanId: id, linkedInvoices: invoices, availableActions: actions, error: null });
  } catch (error) {
    res.status(500).json({ success: false, data: null, message: error.message, error: error.message });
  }
};

const handleCancelChallan = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { action } = req.body;
    
    const invoices = await all(
      `SELECT DISTINCT ih.id, ih.status 
       FROM invoice_headers ih 
       JOIN invoice_lines il ON ih.id = il.invoice_id 
       WHERE il.challan_id = ?`, [id]
    );

    if (invoices.length > 0) {
      if (!action || action === 'block') {
        const err = new Error('Please handle linked invoices manually before cancelling.');
        err.statusCode = 400;
        throw err;
      }
      if (action === 'cascade_delete_drafts_only') {
        const issued = invoices.filter(i => i.status !== 'draft');
        if (issued.length > 0) {
          const err = new Error('Issued invoices present; cannot auto-delete.');
          err.statusCode = 400;
          throw err;
        }
        for (const draft of invoices) {
          await run('DELETE FROM invoice_lines WHERE invoice_id = ?', [draft.id]);
          await run('DELETE FROM invoice_headers WHERE id = ?', [draft.id]);
        }
      } else {
        const err = new Error('Invalid cancel action.');
        err.statusCode = 400;
        throw err;
      }
    }

    const challan = await cancelDeliveryChallan(id, actorFromRequest(req));
    res.json({ success: true, data: await rowToDeliveryChallanDto(challan), error: null });
    
    // Emit item_updated for each item affected if stock was modified
    if (io && challan && Number(challan.maintain_stocks || 1) !== 0) {
      const items = await all('SELECT item_id FROM delivery_challan_items WHERE challan_id = ?', [challan.id]);
      const uniqueItemIds = new Set(items.map(i => i.item_id).filter(id => Number.isFinite(id) && id > 0));
      for (const itemId of uniqueItemIds) {
        io.emit('item_updated', { id: itemId });
      }
    }
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
};

app.post('/api/challans/:id/cancel', requirePermission('config.write'), handleCancelChallan);
app.post('/api/delivery-challans/:id/cancel', requirePermission('config.write'), handleCancelChallan);
app.get('/api/challans/:id/cancel-options', requirePermission('config.write'), handleGetCancelOptions);
app.get('/api/delivery-challans/:id/cancel-options', requirePermission('config.write'), handleGetCancelOptions);

const handleUpdateChallanReportGroups = async (req, res) => {
  try {
    const challanId = Number(req.params.id);
    const existing = await getDeliveryChallanRowById(challanId);
    if (!existing) {
      res.status(404).json({
        success: false,
        data: null,
        message: 'Challan not found.',
        error: 'Challan not found.',
      });
      return;
    }
    const requestedCodes = normalizeChallanType(existing.type) === 'delivery'
      ? await effectiveReportGroupCodesForChallan(existing)
      : normalizeReportGroupCodes(
          req.body?.reportGroupCodes ?? req.body?.report_group_codes ?? [],
        );
    await run('BEGIN TRANSACTION');
    try {
      await replaceChallanReportGroups(challanId, requestedCodes);
      await logDeliveryChallanActivity(
        challanId,
        'report_groups_updated',
        actorFromRequest(req),
        { reportGroupCodes: requestedCodes },
      );
      await run('COMMIT');
    } catch (error) {
      await run('ROLLBACK');
      throw error;
    }
    const refreshed = await getDeliveryChallanRowById(challanId);
    res.json({
      success: true,
      data: await rowToDeliveryChallanDto(refreshed),
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
};

app.patch('/api/challans/:id/report-groups', requirePermission('config.write'), handleUpdateChallanReportGroups);
app.patch('/api/delivery-challans/:id/report-groups', requirePermission('config.write'), handleUpdateChallanReportGroups);

app.get('/api/invoices', requirePermission('config.read'), async (req, res) => {
  try {
    res.json({ success: true, data: await listInvoices(), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: [],
      message: error.message,
      error: error.message,
    });
  }
});

app.get('/api/invoices/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const invoice = await getInvoiceDtoById(Number(req.params.id));
    if (!invoice) {
      res.status(404).json({
        success: false,
        data: null,
        message: 'Invoice not found.',
        error: 'Invoice not found.',
      });
      return;
    }
    res.json({ success: true, data: invoice, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.get('/api/invoices/:id/pdf', requirePermission('config.read'), async (req, res) => {
  try {
    const invoiceId = Number(req.params.id);
    if (!Number.isFinite(invoiceId) || invoiceId <= 0) {
      return res.status(400).json({
        success: false,
        message: 'Valid invoice ID is required.',
        error: 'Valid invoice ID is required.'
      });
    }
    const buffer = await generateInvoicePdf(invoiceId);
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader(
      'Content-Disposition',
      `inline; filename="Invoice-${invoiceId}.pdf"`
    );
    res.send(buffer);
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      message: error.message,
      error: error.message,
    });
  }
});

app.patch('/api/invoices/:id/status', requirePermission('config.write'), async (req, res) => {
  try {
    const { status } = req.body || {};
    if (!status) {
      return res.status(400).json({
        success: false,
        message: 'Status is required.',
        error: 'Status is required.'
      });
    }
    const normalizedStatus = String(status).trim().toLowerCase();
    if (!['issued', 'paid'].includes(normalizedStatus)) {
      return res.status(400).json({
        success: false,
        message: "Invoice status must be 'issued' or 'paid'.",
        error: "Invoice status must be 'issued' or 'paid'."
      });
    }
    const invoiceId = Number(req.params.id);
    if (!Number.isFinite(invoiceId) || invoiceId <= 0) {
      return res.status(400).json({
        success: false,
        message: 'Valid invoice id is required.',
        error: 'Valid invoice id is required.'
      });
    }
    await run(
      'UPDATE invoice_headers SET status = ?, updated_at = ? WHERE id = ?',
      [normalizedStatus, new Date().toISOString(), invoiceId]
    );
    const updatedInvoice = await getInvoiceDtoById(invoiceId);
    if (!updatedInvoice) {
      return res.status(404).json({
        success: false,
        message: 'Invoice not found.',
        error: 'Invoice not found.'
      });
    }
    res.json({ success: true, data: updatedInvoice, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.put('/api/invoices/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const input = req.body || {};
    const linesInput = Array.isArray(input.lines) ? input.lines : [];
    if (linesInput.length === 0) {
      throw new Error('Add at least one invoice line.');
    }
    const invoiceNo = String(input.invoiceNo ?? input.invoice_no ?? '').trim();
    if (invoiceNo) {
      const duplicate = await get('SELECT id FROM invoice_headers WHERE LOWER(TRIM(invoice_no)) = LOWER(TRIM(?)) AND id != ?', [invoiceNo, id]);
      if (duplicate) throw new Error(`Invoice number [${invoiceNo}] is already in use.`);
    }

    const now = new Date().toISOString();
    const invoiceDate = input.invoiceDate ?? input.invoice_date ?? now;

    let totalQuantity = 0, taxableValue = 0, cgstAmount = 0, sgstAmount = 0;
    const normalizedLines = [];
    for (const rawLine of linesInput) {
      const qty = Number(rawLine.quantity ?? rawLine.qty ?? 0) || 0;
      const unitP = Number(rawLine.unitPrice ?? rawLine.unit_price ?? 0) || 0;
      const cRate = Number(rawLine.cgstRate ?? rawLine.cgst_rate ?? 0) || 0;
      const sRate = Number(rawLine.sgstRate ?? rawLine.sgst_rate ?? 0) || 0;
      const taxVal = qty * unitP;
      const cgst = taxVal * cRate / 100;
      const sgst = taxVal * sRate / 100;

      totalQuantity += qty;
      taxableValue += taxVal;
      cgstAmount += cgst;
      sgstAmount += sgst;

      normalizedLines.push({
        orderId: Number(rawLine.orderId ?? rawLine.order_id ?? 0) || null,
        challanId: Number(rawLine.challanId ?? rawLine.challan_id ?? 0) || null,
        challanItemId: Number(rawLine.challanItemId ?? rawLine.challan_item_id ?? 0) || null,
        itemId: Number(rawLine.itemId ?? rawLine.item_id ?? 0) || null,
        variationLeafNodeId: Number(rawLine.variationLeafNodeId ?? rawLine.variation_leaf_node_id ?? 0) || 0,
        itemName: String(rawLine.itemName ?? rawLine.item_name ?? '').trim(),
        hsnCode: String(rawLine.hsnCode ?? rawLine.hsn_code ?? '').trim(),
        quantity: qty, unitPrice: unitP, taxableValue: taxVal, cgstRate: cRate, sgstRate: sRate, cgstAmount: cgst, sgstAmount: sgst
      });
    }

    await run('BEGIN TRANSACTION');
    try {
      await run(
        `UPDATE invoice_headers SET 
          client_id = ?, client_name = ?, gstin = ?, status = ?, invoice_date = ?,
          total_quantity = ?, taxable_value = ?, cgst_amount = ?, sgst_amount = ?, total_amount = ?, updated_at = ?
         WHERE id = ?`,
        [
          Number(input.clientId ?? input.client_id ?? 0) || null,
          String(input.clientName ?? input.client_name ?? '').trim(),
          String(input.gstin ?? input.customerGstin ?? input.customer_gstin ?? '').trim(),
          String(input.status || 'draft').trim() || 'draft',
          invoiceDate, totalQuantity, taxableValue, cgstAmount, sgstAmount, taxableValue + cgstAmount + sgstAmount, now, id
        ]
      );
      if (invoiceNo) {
        await run(`UPDATE invoice_headers SET invoice_no = ? WHERE id = ?`, [invoiceNo, id]);
      }

      await run('DELETE FROM invoice_lines WHERE invoice_id = ?', [id]);
      
      const insertLine = await prepare(`
        INSERT INTO invoice_lines (
          invoice_id, order_id, challan_id, challan_item_id, item_id, variation_leaf_node_id,
          item_name, hsn_code, quantity, unit_price, taxable_value, cgst_rate, sgst_rate, cgst_amount, sgst_amount, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);
      for (const line of normalizedLines) {
        await insertLine.run([
          id, line.orderId, line.challanId, line.challanItemId, line.itemId, line.variationLeafNodeId,
          line.itemName, line.hsnCode, line.quantity, line.unitPrice, line.taxableValue, line.cgstRate, line.sgstRate, line.cgstAmount, line.sgstAmount, now, now
        ]);
      }
      await insertLine.finalize();
      await run('COMMIT');
      
      const invoice = await getInvoiceDtoById(id);
      res.json({ success: true, data: invoice, error: null });
    } catch (e) {
      await run('ROLLBACK');
      throw e;
    }
  } catch (error) {
    res.status(500).json({ success: false, data: null, error: error.message });
  }
});

app.delete('/api/invoices/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = req.params.id;
    await run('BEGIN TRANSACTION');
    await run('DELETE FROM invoice_lines WHERE invoice_id = ?', [id]);
    await run('DELETE FROM invoice_headers WHERE id = ?', [id]);
    await run('COMMIT');
    res.json({ success: true, error: null });
  } catch (error) {
    await run('ROLLBACK');
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/invoices', requirePermission('config.write'), async (req, res) => {
  try {
    const invoice = await createInvoice(req.body || {});
    res.status(201).json({ success: true, data: invoice, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.get('/api/reconciliation/report', requirePermission('config.read'), async (req, res) => {
  try {
    res.json({ success: true, data: await buildReconciliationReport(), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.get('/api/reconciliation/conversion-overrides', requirePermission('config.read'), async (req, res) => {
  try {
    res.json({ success: true, data: await listConversionOverrides(), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: [],
      message: error.message,
      error: error.message,
    });
  }
});

app.patch('/api/reconciliation/conversion-overrides', requirePermission('config.write'), async (req, res) => {
  try {
    res.json({ success: true, data: await saveConversionOverride(req.body || {}), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.get('/api/reconciliation/waste-audit', requirePermission('config.read'), async (req, res) => {
  try {
    res.json({ success: true, data: await listWasteAuditRows(), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: [],
      message: error.message,
      error: error.message,
    });
  }
});

app.post('/api/reports/client-statement', requirePermission('config.read'), async (req, res) => {
  try {
    res.json({ success: true, data: await buildClientStatementReport(req.body || {}), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});


app.get('/api/production/pipeline-templates', requirePermission('config.read'), async (req, res) => {
  try {
    const factoryId = req.query.factoryId;
    let rows;
    if (factoryId) {
      rows = await all(
        'SELECT * FROM pipeline_templates WHERE factory_id = ? OR factory_id = "" ORDER BY created_at DESC',
        [factoryId]
      );
    } else {
      rows = await all(
        'SELECT * FROM pipeline_templates ORDER BY created_at DESC'
      );
    }
    res.json({ success: true, templates: rows.map(rowToTemplate), error: null });
  } catch (error) {
    res.status(500).json({ success: false, templates: [], error: error.message });
  }
});

app.post('/api/production/pipeline-templates', requirePermission('config.write'), async (req, res) => {
  try {
    const data = req.body;
    const now = new Date().toISOString();
    
    await run(
      `
      INSERT INTO pipeline_templates (
        id, factory_id, shop_floor_id, name, description, version, status,
        stage_labels_json, lane_labels_json, nodes_json, flows_json, intermediate_naming_convention, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        data.id,
        data.factoryId || '',
        data.shopFloorId || '',
        data.name || 'Untitled',
        data.description || '',
        data.version || 1,
        data.status || 'draft',
        JSON.stringify(data.stageLabels || []),
        JSON.stringify(data.laneLabels || []),
        JSON.stringify(data.nodes || []),
        JSON.stringify(data.flows || []),
        data.intermediateNamingConvention || '',
        now,
        now
      ]
    );

    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [data.id]);
    trackCreate('pipeline_templates', row.id, row, req);
    res.json({ success: true, template: rowToTemplate(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

app.put('/api/production/pipeline-templates/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = req.params.id;
    const data = req.body;
    const now = new Date().toISOString();

    const existing = await get('SELECT * FROM pipeline_templates WHERE id = ?', [id]);
    if (!existing) {
      return res.status(404).json({ success: false, template: null, error: 'Not found' });
    }
    
    await run(
      `
      UPDATE pipeline_templates
      SET factory_id = ?, shop_floor_id = ?, name = ?, description = ?, version = ?, status = ?,
          stage_labels_json = ?, lane_labels_json = ?, nodes_json = ?, flows_json = ?, intermediate_naming_convention = ?, updated_at = ?
      WHERE id = ?
      `,
      [
        data.factoryId ?? existing.factory_id,
        data.shopFloorId ?? existing.shop_floor_id,
        data.name ?? existing.name,
        data.description ?? existing.description,
        data.version ?? nextVersion,
        data.status ?? existing.status,
        data.stageLabels ? JSON.stringify(data.stageLabels) : existing.stage_labels_json,
        data.laneLabels ? JSON.stringify(data.laneLabels) : existing.lane_labels_json,
        data.nodes ? JSON.stringify(data.nodes) : existing.nodes_json,
        data.flows ? JSON.stringify(data.flows) : existing.flows_json,
        data.intermediateNamingConvention ?? existing.intermediate_naming_convention,
        now,
        id
      ]
    );

    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [id]);
    trackUpdate('pipeline_templates', id, existing, row, req);
    res.json({ success: true, template: rowToTemplate(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

app.delete('/api/production/pipeline-templates/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = req.params.id;
    const runsCount = await get('SELECT COUNT(*) as count FROM pipeline_runs WHERE template_id = ?', [id]);
    if (runsCount && runsCount.count > 0) {
      return res.status(400).json({ success: false, error: 'Cannot delete pipeline template: there are ongoing or historical runs using it.' });
    }
    const before = await get('SELECT * FROM pipeline_templates WHERE id = ?', [id]);
    await run('DELETE FROM pipeline_templates WHERE id = ?', [id]);
    trackDelete('pipeline_templates', id, before, req);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/production-runs/completed', requirePermission('config.read'), async (req, res) => {
  try {
    const runs = await listCompletedProductionRuns({
      search: req.query.search || req.query.q || '',
      limit: req.query.limit || 25,
    });
    res.json({ success: true, data: runs, productionRuns: runs, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: [],
      productionRuns: [],
      message: error.message,
      error: error.message,
    });
  }
});

const handlePrintChallan = async (req, res) => {
  try {
    const challan = await getDeliveryChallanRowById(Number(req.params.id));
    if (!challan) {
      res.status(404).json({
        success: false,
        data: null,
        message: 'Challan not found.',
        error: 'Challan not found.',
      });
      return;
    }
    await logDeliveryChallanActivity(Number(req.params.id), 'challan_printed', actorFromRequest(req), {
      challanNo: challan.challan_no,
    });
    res.json({ success: true, data: null, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
};

app.post('/api/challans/:id/print', requirePermission('config.write'), handlePrintChallan);
app.post('/api/delivery-challans/:id/print', requirePermission('config.write'), handlePrintChallan);

const handleDeleteChallan = async (req, res) => {
  try {
    await deleteDraftDeliveryChallan(Number(req.params.id), actorFromRequest(req));
    res.json({ success: true, data: null, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
};

app.delete('/api/challans/:id', requirePermission('config.write'), handleDeleteChallan);
app.delete('/api/delivery-challans/:id', requirePermission('config.write'), handleDeleteChallan);

app.get('/api/challan-templates', requirePermission('config.read'), async (req, res) => {
  try {
    const templates = await listChallanTemplates({
      partyType: req.query.partyType || req.query.party_type || '',
      partyId: req.query.partyId || req.query.party_id,
      challanType: req.query.challanType || req.query.challan_type || '',
      activeOnly: parseBooleanEnv(req.query.activeOnly || req.query.active_only, false),
    });
    res.json({ success: true, templates, data: templates, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      templates: [],
      data: [],
      message: error.message,
      error: error.message,
    });
  }
});

app.get('/api/challan-templates/scans', requirePermission('config.read'), async (req, res) => {
  try {
    const scans = await listChallanTemplateScans({
      limit: req.query.limit,
    });
    res.json({ success: true, scans, data: scans, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      scans: [],
      data: [],
      message: error.message,
      error: error.message,
    });
  }
});

app.get('/api/challan-templates/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const template = await getChallanTemplateRowById(Number(req.params.id));
    if (!template) {
      res.status(404).json({
        success: false,
        template: null,
        data: null,
        message: 'Challan template not found.',
        error: 'Challan template not found.',
      });
      return;
    }
    const dto = await rowToChallanTemplateDto(template);
    res.json({ success: true, template: dto, data: dto, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      template: null,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.post('/api/challan-templates', requirePermission('config.write'), async (req, res) => {
  try {
    const template = await saveChallanTemplate(req.body || {});
    res.status(201).json({ success: true, template, data: template, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      template: null,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.patch('/api/challan-templates/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const template = await saveChallanTemplate(req.body || {}, Number(req.params.id));
    res.json({ success: true, template, data: template, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      template: null,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.delete('/api/challan-templates/:id', requirePermission('config.write'), async (req, res) => {
  try {
    await deleteChallanTemplate(Number(req.params.id));
    res.json({ success: true, data: null, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.post('/api/challan-templates/upload-intent', requirePermission('config.write'), async (req, res) => {
  try {
    const upload = await createChallanTemplateUploadIntent({
      ...(req.body || {}),
      uploadType: 'CHALLAN_TEMPLATE_BACKGROUND',
    });
    res.status(201).json({ success: true, upload, data: upload, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      upload: null,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.post('/api/challan-templates/upload-complete', requirePermission('config.write'), async (req, res) => {
  try {
    const background = await completeChallanTemplateUpload(req.body || {});
    res.json({ success: true, background, data: background, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      background: null,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.post('/api/challan-templates/stamp-upload-intent', requirePermission('config.write'), async (req, res) => {
  try {
    const upload = await createChallanTemplateUploadIntent({
      ...(req.body || {}),
      uploadType: 'CHALLAN_TEMPLATE_STAMP',
    });
    res.status(201).json({ success: true, upload, data: upload, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      upload: null,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

app.post('/api/challan-templates/stamp-upload-complete', requirePermission('config.write'), async (req, res) => {
  try {
    const stamp = await completeChallanTemplateUpload(req.body || {});
    res.json({ success: true, stamp, data: stamp, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      stamp: null,
      data: null,
      message: error.message,
      error: error.message,
    });
  }
});

async function handleChallanTemplateTestPrint(req, res) {
  try {
    const templateId = Number(
        req.body?.templateId ||
        req.body?.template_id ||
        req.query.templateId ||
        req.query.template_id ||
        req.params?.id ||
        0,
    );
    if (!templateId) {
      res.status(400).json({
        success: false,
        message: 'Template id is required.',
        error: 'Template id is required.',
      });
      return;
    }
    const itemCount = Number(
      req.body?.itemCount ||
        req.body?.item_count ||
        req.query.itemCount ||
        req.query.item_count ||
        3,
    );
    const template = await getChallanTemplateRowById(templateId);
    if (!template) {
      res.status(404).json({
        success: false,
        message: 'Challan template not found.',
        error: 'Challan template not found.',
      });
      return;
    }
    const mappingOverride = Array.isArray(req.body?.mappings)
      ? req.body.mappings
      : null;
    const templateSnapshot = mappingOverride
      ? {
          ...(await rowToChallanTemplateDto(template)),
          mappings: mappingOverride,
        }
      : null;
    const buffer = await generateChallanTemplatePdf({
      challanRow: null,
      challanDtoOverride: buildTemplateTestChallanDto(itemCount),
      templateRow: templateSnapshot ? null : template,
      templateSnapshot,
      mode: req.body?.mode || req.query.mode,
    });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader(
      'Content-Disposition',
      `inline; filename="challan-template-test-${templateId}.pdf"`,
    );
    res.send(buffer);
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      message: error.message,
      error: error.message,
    });
  }
}

app.post('/api/challan-templates/test-print', requirePermission('config.read'), async (req, res) => {
  await handleChallanTemplateTestPrint(req, res);
});

app.get('/api/challan-templates/test-print', requirePermission('config.read'), async (req, res) => {
  await handleChallanTemplateTestPrint(req, res);
});

app.get('/api/templates/:id/test-print', requirePermission('config.read'), async (req, res) => {
  await handleChallanTemplateTestPrint(req, res);
});

app.get('/api/challans/:id/print-template-preview', requirePermission('config.read'), async (req, res) => {
  try {
    const challan = await getDeliveryChallanRowById(Number(req.params.id));
    if (!challan) {
      res.status(404).json({
        success: false,
        message: 'Challan not found.',
        error: 'Challan not found.',
      });
      return;
    }
    const snapshot = parseJsonObject(challan.template_snapshot_json, null);
    const useSnapshot = challan.status !== 'draft' && snapshot;
    const templateId = Number(req.query.templateId || req.query.template_id || 0);
    const template = useSnapshot
      ? null
      : templateId > 0
      ? await getChallanTemplateRowById(templateId)
      : await findActiveChallanTemplateForChallan(challan);
    if (!useSnapshot && !template) {
      res.status(404).json({
        success: false,
        message: 'Matching challan template not found.',
        error: 'Matching challan template not found.',
      });
      return;
    }
    const buffer = await generateChallanTemplatePdf({
      challanRow: challan,
      templateRow: template,
      templateSnapshot: useSnapshot ? snapshot : null,
      mode: req.query.mode,
    });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader(
      'Content-Disposition',
      `inline; filename="${String(challan.challan_no || 'challan').replace(/[^a-zA-Z0-9_.-]/g, '_')}-${String(req.query.mode || 'digital')}.pdf"`,
    );
    res.send(buffer);
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      message: error.message,
      error: error.message,
    });
  }
});

app.get('/api/orders', requirePermission('config.read'), async (req, res) => {
  try {
    const rows = await getOrders();
    res.json({ success: true, orders: rows.map(rowToOrderDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, orders: [], error: error.message });
  }
});

app.post('/api/orders', requirePermission('config.write'), async (req, res) => {
  try {
    const actor = {
      id: req.user?.id || null,
      name: req.user?.name || 'System',
      role: req.user?.role || 'system',
      source: 'api'
    };
    const result = await saveOrder({ ...(req.body || {}), actor }, { returnMeta: true });
    res.status(result.merged ? 200 : 201).json({
      success: true,
      order: rowToOrderDto(result.orderRow),
      merged: result.merged,
      quantityBefore: result.quantityBefore,
      quantityAdded: result.quantityAdded,
      quantityAfter: result.quantityAfter,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      order: null,
      error: error.message,
    });
  }
});

app.post('/api/order-po-uploads/intent', requirePermission('config.write'), async (req, res) => {
  try {
    const intent = await createPoUploadIntent(req.body || {});
    res.status(intent.alreadyUploaded ? 200 : 201).json({
      success: true,
      intent,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      intent: null,
      error: error.message,
    });
  }
});

app.post('/api/order-po-uploads/complete', requirePermission('config.write'), async (req, res) => {
  try {
    const document = await completePoUpload(req.body || {});
    res.json({ success: true, document, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      document: null,
      error: error.message,
    });
  }
});


app.post('/api/upload/generic', requirePermission('config.write'), async (req, res) => {
  try {
    const { fileName, contentType, sha256 } = req.body || {};
    if (!fileName || !contentType) {
      const error = new Error('fileName and contentType are required.');
      error.statusCode = 400;
      throw error;
    }
    
    const normalizedName = normalizeAssetFileName(fileName);
    const uniqueStem = `${Date.now()}-${String(sha256 || '').slice(0, 12)}`;
    const objectKey = `generic/${uniqueStem}-${normalizedName}`;
    const now = new Date();
    const expiresAt = new Date(now.getTime() + 15 * 60 * 1000).toISOString();
    const uploadSessionId = `generic-upload-${now.getTime()}-${crypto.randomBytes(8).toString('hex')}`;
    
    const uploadUrl = await presignS3Url({
      method: 'PUT',
      objectKey,
      contentType,
      expiresSeconds: 900,
    });
    
    const readUrl = await presignS3Url({
      method: 'GET',
      objectKey,
      expiresSeconds: 7 * 24 * 60 * 60, // 7 days (maximum for presigned URLs typically)
    });

    const intent = {
      alreadyUploaded: false,
      upload: {
        uploadSessionId,
        objectKey,
        uploadUrl,
        headers: { 'Content-Type': contentType },
        expiresAt,
        readUrl,
      }
    };

    res.status(201).json({
      success: true,
      intent,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      intent: null,
      error: error.message,
    });
  }
});

app.post('/api/assets/upload-intent', requirePermission('config.write'), async (req, res) => {
  try {
    const intent = await createAssetUploadIntent(req.body || {});
    res.status(intent.alreadyUploaded ? 200 : 201).json({
      success: true,
      intent,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      intent: null,
      error: error.message,
    });
  }
});

app.post('/api/delivery-challans/:id/assets/upload-intent', requirePermission('config.write'), async (req, res) => {
  try {
    const entityId = Number(req.params.id);
    if (!Number.isInteger(entityId) || entityId <= 0) {
      res.status(400).json({
        success: false,
        intent: null,
        error: 'A valid challan id is required.',
      });
      return;
    }
    const requestedEntityId = req.body?.entityId;
    if (requestedEntityId != null && Number(requestedEntityId) !== entityId) {
      res.status(400).json({
        success: false,
        intent: null,
        error: 'Request challan id does not match the upload route challan id.',
      });
      return;
    }
    const intent = await createAssetUploadIntent({
      ...(req.body || {}),
      entityType: 'delivery_challan',
      entityId,
    });
    res.status(intent.alreadyUploaded ? 200 : 201).json({
      success: true,
      intent,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      intent: null,
      error: error.message,
    });
  }
});

app.post('/api/delivery-challans/:id/assets/upload-complete', requirePermission('config.write'), async (req, res) => {
  try {
    const entityId = Number(req.params.id);
    if (!Number.isInteger(entityId) || entityId <= 0) {
      res.status(400).json({
        success: false,
        asset: null,
        error: 'A valid challan id is required.',
      });
      return;
    }
    const requestedEntityId = req.body?.entityId;
    if (requestedEntityId != null && Number(requestedEntityId) !== entityId) {
      res.status(400).json({
        success: false,
        asset: null,
        error: 'Request challan id does not match the upload route challan id.',
      });
      return;
    }
    const assetRow = await handleAssetUploadComplete({
      ...(req.body || {}),
      entityType: 'delivery_challan',
      entityId,
    });
    const assetDto = await rowToUploadedAssetDto(assetRow);
    res.status(200).json({
      success: true,
      asset: assetDto,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      asset: null,
      error: error.message,
    });
  }
});



app.get('/api/barcode/lookup', requirePermission('config.read'), async (req, res) => {
  try {
    const { code } = req.query;
    if (!code) {
      return res.status(400).json({ success: false, error: 'Code is required' });
    }
    
    const row = await get(`
      SELECT pb.*, 
             ci.item_id, ci.challan_id, ci.quantity_pcs, ci.weight, ci.note,
             i.name as item_name, i.short_code,
             c.order_no, c.type as challan_type, c.vendor_name
      FROM piece_barcodes pb
      JOIN delivery_challan_items ci ON pb.challan_item_id = ci.id
      JOIN items i ON ci.item_id = i.id
      JOIN delivery_challans c ON ci.challan_id = c.id
      WHERE pb.parent_code = ? OR pb.child_code = ?
    `, [code, code]);
    
    if (!row) {
      return res.status(404).json({ success: false, error: 'Barcode not found in database.' });
    }
    
    res.json({ success: true, result: row });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/items/:id/assets/upload-intent', requirePermission('config.write'), async (req, res) => {
  try {
    const entityId = Number(req.params.id);
    if (!Number.isInteger(entityId) || entityId <= 0) {
      res.status(400).json({
        success: false,
        intent: null,
        error: 'A valid item id is required.',
      });
      return;
    }
    const requestedEntityId = req.body?.entityId;
    if (requestedEntityId != null && Number(requestedEntityId) !== entityId) {
      res.status(400).json({
        success: false,
        intent: null,
        error: 'Request item id does not match the upload route item id.',
      });
      return;
    }
    const intent = await createAssetUploadIntent({
      ...(req.body || {}),
      entityType: 'item',
      entityId,
    });
    res.status(intent.alreadyUploaded ? 200 : 201).json({
      success: true,
      intent,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      intent: null,
      error: error.message,
    });
  }
});

app.post('/api/assets/upload-complete', requirePermission('config.write'), async (req, res) => {
  try {
    const asset = await completeAssetUpload(req.body || {});
    res.json({ success: true, asset, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      asset: null,
      error: error.message,
    });
  }
});

app.post('/api/items/:id/assets/upload-complete', requirePermission('config.write'), async (req, res) => {
  try {
    const entityId = Number(req.params.id);
    if (!Number.isInteger(entityId) || entityId <= 0) {
      res.status(400).json({
        success: false,
        asset: null,
        error: 'A valid item id is required.',
      });
      return;
    }
    const asset = await completeAssetUpload(req.body || {});
    if (asset.entityType !== 'item' || Number(asset.entityId) !== entityId) {
      res.status(400).json({
        success: false,
        asset: null,
        error: 'Completed upload does not belong to the requested item.',
      });
      return;
    }
    res.json({ success: true, asset, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      asset: null,
      error: error.message,
    });
  }
});

app.get('/api/items/:id/assets', requirePermission('config.read'), async (req, res) => {
  try {
    const assets = await listAssetsForEntity('item', Number(req.params.id));
    res.json({ success: true, assets, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      assets: [],
      error: error.message,
    });
  }
});

app.post('/api/assets/:id/read-url', requirePermission('config.read'), async (req, res) => {
  try {
    const payload = await createAssetReadUrl(Number(req.params.id));
    res.json({ success: true, ...payload, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      asset: null,
      readUrl: null,
      error: error.message,
    });
  }
});

app.patch('/api/assets/:id/primary', requirePermission('config.write'), async (req, res) => {
  try {
    const asset = await setPrimaryAsset(Number(req.params.id));
    res.json({ success: true, asset, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      asset: null,
      error: error.message,
    });
  }
});

app.delete('/api/assets/:id', requirePermission('config.write'), async (req, res) => {
  try {
    await deleteAsset(Number(req.params.id));
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      error: error.message,
    });
  }
});

app.get('/api/orders/:id/po-documents', requirePermission('config.read'), async (req, res) => {
  try {
    const documents = await getPoDocumentsForOrder(Number(req.params.id));
    res.json({ success: true, documents, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      documents: [],
      error: error.message,
    });
  }
});

app.post('/api/orders/:id/po-documents', requirePermission('config.write'), async (req, res) => {
  try {
    const orderId = Number(req.params.id);
    const { newlyLinkedIds } = await linkPoDocumentsToOrder(orderId, req.body?.documentIds || []);
    if (newlyLinkedIds.length > 0) {
      const actor = {
        id: req.user?.id || null,
        name: req.user?.name || 'System',
        role: req.user?.role || 'system',
        source: 'api'
      };
      await insertOrderActivityLog({
        orderId,
        activityType: 'po_documents_linked',
        actor,
        details: { documentIds: newlyLinkedIds },
      });
    }
    const documents = await getPoDocumentsForOrder(orderId);
    res.json({ success: true, documents, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      documents: [],
      error: error.message,
    });
  }
});

app.get('/api/orders/:id/material-requirements', requirePermission('config.read'), async (req, res) => {
  try {
    const requirements = await all(
      'SELECT * FROM order_material_requirements WHERE order_id = ? ORDER BY id ASC',
      [Number(req.params.id)]
    );
    res.json({ success: true, requirements, error: null });
  } catch (error) {
    res.status(500).json({
      success: false,
      requirements: [],
      error: error.message,
    });
  }
});

app.get('/api/orders/:id/activity', requirePermission('config.read'), async (req, res) => {
  try {
    const orderId = Number(req.params.id);
    const rows = await getOrderActivity(orderId);
    res.json({ success: true, activities: rows.map(rowToOrderActivityDto), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      activities: [],
      error: error.message,
    });
  }
});

app.get('/api/orders/:id/status-history', requirePermission('config.read'), async (req, res) => {
  try {
    const orderId = Number(req.params.id);
    const rows = await getOrderStatusHistory(orderId);
    res.json({ success: true, history: rows.map(rowToOrderStatusHistoryDto), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      history: [],
      error: error.message,
    });
  }
});

app.get('/api/orders/:orderNo/pipeline-runs', requirePermission('config.read'), async (req, res) => {
  try {
    const orderNo = req.params.orderNo;
    const rows = await all(`
      SELECT pr.*
      FROM pipeline_runs pr
      JOIN order_pipeline_assignments opa ON pr.id = opa.pipeline_run_id
      JOIN order_items i ON opa.order_item_id = i.id
      WHERE i.order_no = ?
      ORDER BY pr.created_at DESC
    `, [orderNo]);

    const runs = [];
    for (const row of rows) {
      runs.push(await rowToRun(row));
    }
    res.json({ success: true, runs, error: null });
  } catch (error) {
    res.status(500).json({ success: false, runs: [], error: error.message });
  }
});

// Quantities-only production report for an order: pipeline stages with actual
// consumption/output/waste from stage_reconciliations. No costs by design —
// rates are filled in on paper.
app.get('/api/orders/:orderNo/production-report', requirePermission('config.read'), async (req, res) => {
  try {
    const orderNo = req.params.orderNo;
    const header = await get(`
      SELECT h.order_no, h.po_number, c.name AS client_name
      FROM order_headers h
      LEFT JOIN clients c ON h.client_id = c.id
      WHERE h.order_no = ?
    `, [orderNo]);
    if (!header) {
      return res.status(404).json({ success: false, report: null, error: 'Order not found.' });
    }
    const items = await all(`
      SELECT id, item_name, variation_path_label, quantity, unit_name, unit_symbol, unit_price
      FROM order_items WHERE order_no = ? ORDER BY id ASC
    `, [orderNo]);
    const runRows = await all(`
      SELECT pr.*, opa.order_item_id
      FROM pipeline_runs pr
      JOIN order_pipeline_assignments opa ON pr.id = opa.pipeline_run_id
      JOIN order_items i ON opa.order_item_id = i.id
      WHERE i.order_no = ?
      ORDER BY pr.created_at DESC
    `, [orderNo]);
    const itemById = new Map(items.map((item) => [item.id, item]));
    const machineRows = await all('SELECT * FROM machines');
    const machineByKey = new Map();
    for (const row of machineRows) {
      const dto = machineRowToDto(row);
      [String(row.id), row.asset_id, row.name].forEach((key) => {
        if (key) machineByKey.set(String(key).trim(), dto);
      });
    }
    const dieRows = await all('SELECT * FROM dies');
    const dieByKey = new Map();
    for (const row of dieRows) {
      const dto = dieRowToDto(row);
      [String(row.id), row.tool_code].forEach((key) => {
        if (key) dieByKey.set(String(key).trim(), dto);
      });
    }

    const templateCache = new Map();
    const runs = [];
    for (const runRow of runRows) {
      if (!templateCache.has(runRow.template_id)) {
        templateCache.set(runRow.template_id, await get(
          'SELECT id, name, nodes_json FROM pipeline_templates WHERE id = ?',
          [runRow.template_id],
        ));
      }
      const template = templateCache.get(runRow.template_id);
      const nodes = template ? parseJson(template.nodes_json, []) : [];
      const metricsByNode = await getMergedNodeMetrics(runRow);
      const orderItem = itemById.get(runRow.order_item_id);
      const orderQty = Number(orderItem?.quantity || 0);
      const stages = nodes
        .slice()
        .sort((a, b) => (a.stageIndex || 0) - (b.stageIndex || 0))
        .map((node) => {
          const metrics = metricsByNode[node.id] || {};
          const machineKey = String(
            node.machineId || node.machine_id || node.machineAssetId || node.machine || node.machineName || ''
          ).trim();
          const dieKey = String(node.dieId || node.die_id || '').trim();
          const machine = machineByKey.get(machineKey) || null;
          const die = dieByKey.get(dieKey) || null;
          const quantityPerUnit = Number(
            node.quantityPerUnit ??
            node.quantity_per_unit ??
            node.inputItem?.quantityPerUnit ??
            node.inputItem?.quantity_per_unit ??
            node.inputItem?.perUnitQty ??
            NaN
          );
          const plannedMaterialQty = Number.isFinite(quantityPerUnit) && orderQty > 0
            ? quantityPerUnit * orderQty
            : null;
          return {
            nodeId: node.id,
            name: node.name || '',
            stageIndex: Number(node.stageIndex || 0),
            processType: node.processType || '',
            material: node.inputItem?.variationPathLabel || node.inputItem?.itemName || '',
            materialUnit: node.inputItem?.unitSymbol || '',
            outputName: node.outputItem?.variationPathLabel || node.outputItem?.itemName || '',
            outputUnit: node.outputItem?.unitSymbol || '',
            quantityPerUnit: Number.isFinite(quantityPerUnit) ? quantityPerUnit : null,
            plannedMaterialQty,
            machine: machine?.name || node.machine || node.machineGroupName || '',
            machineAssetId: machine?.assetId || machineKey,
            machineOutputPerHour: machine?.reportOutputPerHour ?? null,
            machineSetupMinutes: machine?.setupMinutes ?? null,
            machineLaborCount: machine?.laborCount ?? null,
            machinePowerKw: machine?.powerKw ?? null,
            machineReportNotes: machine?.reportNotes || '',
            dieId: dieKey,
            dieToolCode: die?.toolCode || dieKey,
            dieCavities: die?.numberOfCavities ?? null,
            dieMaxStrokes: die?.maxStrokes ?? null,
            dieStrokesPerPiece: die?.strokesPerPiece ?? null,
            dieSetupMinutes: die?.setupMinutes ?? null,
            dieReportNotes: die?.reportNotes || '',
            plannedHours: Number(node.durationHours || 0),
            allotted: metrics.allotted ?? null,
            output: metrics.output ?? metrics.goodYield ?? null,
            leftover: metrics.remaining ?? null,
            scrap: metrics.scrap ?? null,
            inputTime: metrics.inputTime ?? null,
            outputTime: metrics.outputTime ?? null,
            actualHours: metrics.actualHours ?? null,
          };
        });
      runs.push({
        runId: runRow.id,
        runName: runRow.name || '',
        status: runRow.status || 'planned',
        orderItemId: runRow.order_item_id,
        templateName: template?.name || '',
        startedAt: runRow.started_at,
        completedAt: runRow.completed_at,
        stages,
      });
    }

    res.json({
      success: true,
      report: {
        orderNo,
        clientName: header.client_name || '',
        poNumber: header.po_number || '',
        items: items.map((item) => ({
          orderItemId: item.id,
          itemName: item.item_name || '',
          variationPathLabel: item.variation_path_label || '',
          quantity: Number(item.quantity || 0),
          unitSymbol: item.unit_symbol || item.unit_name || 'pcs',
          unitPrice: Number(item.unit_price || 0),
        })),
        runs,
      },
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, report: null, error: error.message });
  }
});

app.post('/api/order-po-documents/:id/read-url', requirePermission('config.read'), async (req, res) => {
  try {
    const result = await createPoDocumentReadUrl(Number(req.params.id));
    res.json({ success: true, ...result, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      document: null,
      readUrl: null,
      error: error.message,
    });
  }
});

app.patch('/api/orders/:id/lifecycle', requirePermission('config.write'), async (req, res) => {
  try {
    const actor = {
      id: req.user?.id || null,
      name: req.user?.name || 'System',
      role: req.user?.role || 'system',
      source: 'api'
    };
    const order = await updateOrderLifecycle({
      ...(req.body || {}),
      id: Number(req.params.id),
      actor
    });
    res.json({ success: true, order: rowToOrderDto(order), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      order: null,
      error: error.message,
    });
  }
});

app.put('/api/orders/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const orderId = Number(req.params.id);
    const updates = req.body || {};
    
    // Begin transaction
    await run('BEGIN TRANSACTION');
    
    // Get existing order item
    const existingItem = await get('SELECT * FROM order_items WHERE id = ?', [orderId]);
    if (!existingItem) {
      await run('ROLLBACK').catch(() => {});
      return res.status(404).json({ success: false, error: 'Order not found.' });
    }

    const orderNo = updates.orderNo || existingItem.order_no;
    const clientId = updates.clientId || existingItem.client_id;
    let clientCode = updates.clientCode || existingItem.client_code;
    let clientName = updates.clientName || existingItem.client_name;
    
    // Auto-update client code and name if client changed
    if (updates.clientId && updates.clientId !== existingItem.client_id) {
      const client = await get('SELECT name, alias FROM clients WHERE id = ?', [updates.clientId]);
      if (client) {
        clientName = client.name;
        clientCode = client.alias || client.name.substring(0, 3).toUpperCase();
      }
    }

    // Update order_headers if order_no or client changed
    if (orderNo !== existingItem.order_no || clientId !== existingItem.client_id) {
      // Create new header if it doesn't exist
      await run(
        'INSERT OR IGNORE INTO order_headers (order_no, client_id, po_number, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [orderNo, clientId, '', new Date().toISOString(), new Date().toISOString()]
      );
      
      // Update header client_id if order_no stayed the same
      if (orderNo === existingItem.order_no) {
         await run('UPDATE order_headers SET client_id = ?, updated_at = ? WHERE order_no = ?', [clientId, new Date().toISOString(), orderNo]);
      }
    }

    await run(`
      UPDATE order_items 
      SET order_no = ?, client_id = ?, client_name = ?, client_code = ?, item_id = ?, 
          variation_leaf_node_id = ?, variation_path_label = ?, item_name = ?, 
          hsn_code = ?, quantity = ?, unit_price = ?, taxable_value = ?, 
          cgst_rate = ?, sgst_rate = ?, cgst_amount = ?, sgst_amount = ?, updated_at = ?
      WHERE id = ?
    `, [
      orderNo, clientId, clientName, clientCode,
      updates.itemId || existingItem.item_id,
      updates.variationLeafNodeId || existingItem.variation_leaf_node_id,
      updates.variationPathLabel || existingItem.variation_path_label,
      updates.itemName || existingItem.item_name,
      updates.hsnCode || existingItem.hsn_code,
      updates.quantity !== undefined ? updates.quantity : existingItem.quantity,
      updates.unitPrice !== undefined ? updates.unitPrice : existingItem.unit_price,
      updates.taxableValue !== undefined ? updates.taxableValue : existingItem.taxable_value,
      updates.cgstRate !== undefined ? updates.cgstRate : existingItem.cgst_rate,
      updates.sgstRate !== undefined ? updates.sgstRate : existingItem.sgst_rate,
      updates.cgstAmount !== undefined ? updates.cgstAmount : existingItem.cgst_amount,
      updates.sgstAmount !== undefined ? updates.sgstAmount : existingItem.sgst_amount,
      new Date().toISOString(),
      orderId
    ]);

    await run('COMMIT');
    const orders = await getOrders();
    const updated = orders.find(o => o.id === orderId);
    res.json({ success: true, order: updated, error: null });
  } catch (error) {
    await run('ROLLBACK').catch(() => {});
    res.status(error.statusCode || 500).json({ success: false, error: error.message });
  }
});

app.delete('/api/orders/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const orderId = Number(req.params.id);
    const actorName = req.user?.name || 'System';
    
    await run('BEGIN TRANSACTION');

    const wipBarcode = req.body?.wip_barcode;
    const wipQty = Number(req.body?.wip_qty || 0);
    const recoveredMovements = [];

    const assignments = await all('SELECT * FROM order_pipeline_assignments WHERE order_item_id = ?', [orderId]);
    for (const assignment of assignments) {
      const runId = assignment.pipeline_run_id;

      // Dissolve unused raw inputs (that were consumed) back to inventory
      const consumedMovements = await all(
        "SELECT * FROM inventory_movements WHERE movement_type = 'consume' AND reference_type = 'pipeline_run' AND reference_id = ?",
        [runId]
      );

      for (const move of consumedMovements) {
        const qty = move.qty;
        if (qty > 0) {
          await applyInventoryMovementCore({
            barcode: move.material_barcode,
            movementType: 'adjust_in',
            qty: qty,
            actor: actorName,
            referenceType: 'pipeline_dissolution',
            referenceId: String(orderId),
            reasonCode: 'ORDER_DELETED',
            toLocationId: move.from_location_id || 'MAIN'
          }, { useTransaction: false });
          recoveredMovements.push({ barcode: move.material_barcode, qty, reason: 'Raw Material Recovery' });
        }
      }

      await run('DELETE FROM run_barcode_inputs WHERE run_id = ?', [runId]);
      await run('DELETE FROM pipeline_runs WHERE id = ?', [runId]);
    }

    if (wipBarcode && wipQty > 0) {
      await applyInventoryMovementCore({
        barcode: wipBarcode,
        movementType: 'adjust_in',
        qty: wipQty,
        actor: actorName,
        referenceType: 'pipeline_dissolution',
        referenceId: String(orderId),
        reasonCode: 'WIP_RECOVERY',
        toLocationId: 'MAIN'
      }, { useTransaction: false });
      recoveredMovements.push({ barcode: wipBarcode, qty: wipQty, reason: 'WIP Recovery' });
    }

    await run('DELETE FROM order_pipeline_assignments WHERE order_item_id = ?', [orderId]);
    await run('DELETE FROM order_status_history WHERE order_id = ?', [orderId]);
    await run('DELETE FROM order_activity_log WHERE order_id = ?', [orderId]);
    await run('DELETE FROM order_material_requirements WHERE order_id = ?', [orderId]);
    await run('DELETE FROM order_po_documents WHERE order_id = ?', [orderId]);

    const item = await get('SELECT order_no FROM order_items WHERE id = ?', [orderId]);
    if (item) {
      await run('DELETE FROM order_items WHERE id = ?', [orderId]);
      const otherItems = await get('SELECT id FROM order_items WHERE order_no = ?', [item.order_no]);
      if (!otherItems) {
        await run('DELETE FROM order_headers WHERE order_no = ?', [item.order_no]);
      }
    }

    // Audit log
    await run(
      "INSERT INTO activity_logs (entity_type, entity_id, action, actor_id, actor_name, details_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      ['order', String(orderId), 'deleted', req.user?.id || 1, actorName, JSON.stringify({ reason: 'User requested Undo' }), new Date().toISOString()]
    ).catch(() => {});

    await run('COMMIT');
    res.json({ success: true, recoveredMovements, error: null });
  } catch (error) {
    await run('ROLLBACK').catch(() => {});
    res.status(error.statusCode || 500).json({ success: false, error: error.message });
  }
});
app.post('/api/clients', requirePermission('config.write'), async (req, res) => {
  try {
    const client = await saveClient(req.body || {});
    const clientDto = rowToClientDto(client);
    if (io) {
      io.emit('client_added', clientDto);
    }
    trackCreate('clients', client.id, client, req);
    res.status(201).json({ success: true, client: clientDto, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      client: null,
      error: error.message,
    });
  }
});
app.delete('/api/clients/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const before = await get('SELECT * FROM clients WHERE id = ?', [id]);
    await trashAndDelete('clients', id, req);
    trackDelete('clients', id, before, req);
    if (io) {
      io.emit('client_deleted', { id });
    }
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.patch('/api/clients/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const before = await get('SELECT * FROM clients WHERE id = ?', [id]);
    const client = await saveClient({
      ...(req.body || {}),
      id,
    });
    const clientDto = rowToClientDto(client);
    if (io) {
      io.emit('client_updated', clientDto);
    }
    const after = await get('SELECT * FROM clients WHERE id = ?', [id]);
    trackUpdate('clients', id, before, after, req);
    res.json({ success: true, client: clientDto, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      client: null,
      error: error.message,
    });
  }
});

app.get('/api/vendors', requirePermission('config.read'), async (_req, res) => {
  try {
    const rows = await getVendorsWithUsage();
    res.json({ success: true, vendors: rows.map(rowToVendorDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, vendors: [], error: error.message });
  }
});

app.get('/api/vendors/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const row = await get(`
      SELECT
        vendors.*,
        (SELECT COUNT(*) FROM delivery_challans WHERE delivery_challans.vendor_id = vendors.id) AS usage_count
      FROM vendors
      WHERE id = ?
    `, [req.params.id]);
    if (!row) {
      return res.status(404).json({ success: false, vendor: null, error: 'Not found' });
    }
    res.json({ success: true, vendor: rowToVendorDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, vendor: null, error: error.message });
  }
});

app.get('/api/vendors/:id/purchase-history', requirePermission('config.read'), async (req, res) => {
  try {
    const vendorId = Number(req.params.id);
    const rows = await all(`
      SELECT DISTINCT
        dci.item_id,
        dci.variation_leaf_node_id,
        dci.variation_path_label,
        dci.variation_path_node_ids_json,
        dci.custom_variation_values_json,
        dci.particulars,
        i.name as item_name
      FROM delivery_challans dc
      JOIN delivery_challan_items dci ON dc.id = dci.challan_id
      JOIN items i ON dci.item_id = i.id
      WHERE dc.vendor_id = ? AND dc.type = 'reception'
      ORDER BY dci.created_at DESC
      LIMIT 100
    `, [vendorId]);

    const historyItems = rows.map(r => ({
      itemId: r.item_id,
      variationLeafNodeId: r.variation_leaf_node_id,
      variationPathLabel: r.variation_path_label,
      variationPathNodeIds: JSON.parse(r.variation_path_node_ids_json || '[]'),
      customVariationValues: JSON.parse(r.custom_variation_values_json || '{}'),
      particulars: r.particulars || r.item_name
    }));

    // Deduplicate on backend just in case DISTINCT missed something due to JSON differences
    const uniqueItems = [];
    const seen = new Set();
    for (const item of historyItems) {
      const key = `${item.itemId}_${item.variationLeafNodeId}`;
      if (!seen.has(key)) {
        seen.add(key);
        uniqueItems.push(item);
      }
    }

    res.json({ success: true, history: uniqueItems, error: null });
  } catch (error) {
    res.status(500).json({ success: false, history: [], error: error.message });
  }
});

app.post('/api/vendors', requirePermission('config.write'), async (req, res) => {
  try {
    const vendor = await saveVendor(req.body || {});
    const vendorDto = rowToVendorDto(vendor);
    if (io) {
      io.emit('vendor_added', vendorDto);
    }
    trackCreate('vendors', vendor.id, vendor, req);
    res.status(201).json({ success: true, vendor: vendorDto, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, vendor: null, error: error.message });
  }
});
app.delete('/api/vendors/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const before = await get('SELECT * FROM vendors WHERE id = ?', [id]);
    await trashAndDelete('vendors', id, req);
    trackDelete('vendors', id, before, req);
    if (io) {
      io.emit('vendor_deleted', { id });
    }
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.patch('/api/vendors/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const before = await get('SELECT * FROM vendors WHERE id = ?', [id]);
    const vendor = await saveVendor({
      ...(req.body || {}),
      id,
    });
    const vendorDto = rowToVendorDto(vendor);
    if (io) {
      io.emit('vendor_updated', vendorDto);
    }
    const after = await get('SELECT * FROM vendors WHERE id = ?', [id]);
    trackUpdate('vendors', id, before, after, req);
    res.json({ success: true, vendor: vendorDto, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, vendor: null, error: error.message });
  }
});

app.get('/api/items/:id/usage', requirePermission('config.read'), async (req, res) => {
  try {
    const usage = await getItemUsageDetails(Number(req.params.id));
    res.json({ success: true, usage, error: null });
  } catch (error) {
    res.status(500).json({ success: false, usage: [], error: error.message });
  }
});

app.get('/api/items', requirePermission('config.read'), async (req, res) => {
  try {
    const rows = await getItemsWithUsage();
    const items = await Promise.all(rows.map(rowToItemDto));
    res.json({ success: true, items, error: null });
  } catch (error) {
    res.status(500).json({ success: false, items: [], error: error.message });
  }
});

app.get('/api/items/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const row = await get(`
      SELECT
        items.*,
        pipeline_templates.name AS default_pipeline_name,
        (
          (SELECT COUNT(*) FROM order_items WHERE order_items.item_id = items.id) +
          (SELECT COUNT(*) FROM delivery_challan_items WHERE delivery_challan_items.item_id = items.id) +
          (SELECT COUNT(*) FROM order_material_requirements WHERE order_material_requirements.item_id = items.id) +
          (SELECT COUNT(*) FROM materials WHERE materials.linked_item_id = items.id) +
          (SELECT COUNT(*) FROM material_group_item_links WHERE material_group_item_links.item_id = items.id)
        ) AS usage_count
      FROM items
      LEFT JOIN pipeline_templates ON items.default_pipeline_id = pipeline_templates.id
      WHERE items.id = ?
    `, [req.params.id]);
    if (!row) {
      return res.status(404).json({ success: false, item: null, error: 'Not found' });
    }
    res.json({ success: true, item: await rowToItemDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, item: null, error: error.message });
  }
});

app.get('/api/inventory/sets', requirePermission('inventory.read'), async (_req, res) => {
  try {
    const sets = await getInventorySets();
    res.json({ success: true, sets, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      sets: [],
      error: error.message,
    });
  }
});

app.post('/api/inventory/sets', requirePermission('inventory.create'), async (req, res) => {
  try {
    const set = await saveInventorySet(req.body || {});
    res.status(201).json({ success: true, set, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      set: null,
      error: error.message,
    });
  }
});

app.patch('/api/inventory/sets/:id', requirePermission('inventory.update'), async (req, res) => {
  try {
    const set = await saveInventorySet({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, set, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      set: null,
      error: error.message,
    });
  }
});

app.delete('/api/inventory/sets/:id', requirePermission('inventory.delete'), async (req, res) => {
  try {
    await deleteInventorySet(Number(req.params.id));
    res.json({ success: true, set: null, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      set: null,
      error: error.message,
    });
  }
});


app.put('/api/items/:id/short-code', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const shortCode = req.body.shortCode || '';
    
    if (!id) {
      return res.status(400).json({ success: false, error: 'Invalid ID' });
    }

    const item = await get('SELECT * FROM items WHERE id = ?', [id]);
    if (!item) {
      return res.status(404).json({ success: false, error: 'Item not found' });
    }

    await run('UPDATE items SET short_code = ?, updated_at = ? WHERE id = ?', [shortCode, new Date().toISOString(), id]);
    
    // Notify clients of the change
    await logChange('items', id, 'UPDATE');
    
    const updatedRow = await get('SELECT * FROM items WHERE id = ?', [id]);
    const itemDto = await rowToItemDto(updatedRow);
    
    if (io) {
      io.emit('item_updated', itemDto);
    }
    
    res.json({ success: true, item: itemDto, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/items', requirePermission('config.write'), async (req, res) => {
  try {
    const item = await saveItem(req.body || {});
    const itemDto = await rowToItemDto(item);
    if (io) {
      io.emit('item_added', itemDto);
    }
    trackCreate('items', item.id, item, req);
    res.status(201).json({ success: true, item: itemDto, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      item: null,
      error: error.message,
    });
  }
});

app.patch('/api/items/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const before = await get('SELECT * FROM items WHERE id = ?', [id]);
    const item = await saveItem({
      ...(req.body || {}),
      id,
    });
    const itemDto = await rowToItemDto(item);
    if (io) {
      io.emit('item_updated', itemDto);
    }
    const after = await get('SELECT * FROM items WHERE id = ?', [id]);
    trackUpdate('items', id, before, after, req);
    res.json({ success: true, item: itemDto, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      item: null,
      error: error.message,
    });
  }
});

app.delete('/api/items/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const before = await get('SELECT * FROM items WHERE id = ?', [id]);

    const nodeIds = (await all('SELECT id FROM item_variation_nodes WHERE item_id = ?', [id])).map(r => r.id);
    await trashAndDeleteMany('item_variation_nodes', nodeIds, req);
    
    const convIds = (await all('SELECT id FROM item_unit_conversions WHERE item_id = ?', [id])).map(r => r.id);
    await trashAndDeleteMany('item_unit_conversions', convIds, req);
    
    const varIds = (await all('SELECT id FROM item_variations WHERE item_id = ?', [id])).map(r => r.id);
    await trashAndDeleteMany('item_variations', varIds, req);
    
    const assetIds = (await all("SELECT id FROM uploaded_assets WHERE entity_type='item' AND entity_id=?", [id])).map(r => r.id);
    await trashAndDeleteMany('uploaded_assets', assetIds, req);
    
    await trashAndDelete('items', id, req);
    trackDelete('items', id, before, req);

    if (io) {
      io.emit('item_deleted', { id });
    }
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});



// Relocate an item to another group without touching its variation tree /
// conversions (saveItem would rewrite those). Used by the delete-group flow.
app.patch('/api/items/:id/group', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const groupId = Number((req.body || {}).groupId);
    const existing = await getItemRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, item: null, error: 'Item not found.' });
      return;
    }
    if (!groupId) {
      res.status(400).json({ success: false, item: null, error: 'A target group is required.' });
      return;
    }
    const groupRow = await get('SELECT * FROM groups WHERE id = ?', [groupId]);
    if (!groupRow || groupRow.is_archived) {
      res.status(400).json({
        success: false,
        item: null,
        error: 'Selected group does not exist or is archived.',
      });
      return;
    }
    await run('UPDATE items SET group_id = ?, updated_at = ? WHERE id = ?', [
      groupId,
      new Date().toISOString(),
      id,
    ]);
    const updated = await getItemRowById(id);
    res.json({ success: true, item: await rowToItemDto(updated), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, item: null, error: error.message });
  }
});

app.post('/api/groups', requirePermission('config.write'), async (req, res) => {
  try {
    const group = await saveGroup(req.body || {});
    res.status(201).json({ success: true, group: rowToGroupDto(group), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      group: null,
      error: error.message,
    });
  }
});

// Enhancement 2.2/2.3 — bulk-assign item variants to a combination group.
// Idempotent: re-assigning an item that is already a member is a no-op, and the
// item's primary hierarchical group (items.group_id) is never modified, so dual
// membership is preserved.
app.post('/api/groups/:groupId/items', requirePermission('config.write'), async (req, res) => {
  try {
    const groupId = Number(req.params.groupId);
    const group = await getGroupRowById(groupId);
    if (!group) {
      res.status(404).json({ success: false, group: null, assignedCount: 0, error: 'Group not found.' });
      return;
    }
    if ((group.group_structure || 'hierarchical') !== 'combination') {
      res.status(400).json({
        success: false,
        group: rowToGroupDto(group),
        assignedCount: 0,
        error: 'Items can only be bulk-assigned to combination groups.',
      });
      return;
    }
    const rawIds = Array.isArray(req.body?.itemIds) ? req.body.itemIds : [];
    const itemIds = [...new Set(rawIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))];
    if (itemIds.length === 0) {
      res.status(400).json({
        success: false,
        group: rowToGroupDto(group),
        assignedCount: 0,
        error: 'itemIds must be a non-empty array of item ids.',
      });
      return;
    }

    const placeholders = itemIds.map(() => '?').join(', ');
    const existingItems = await all(
      `SELECT id FROM items WHERE id IN (${placeholders})`,
      itemIds,
    );
    const validIds = existingItems.map((row) => row.id);
    if (validIds.length === 0) {
      res.status(400).json({
        success: false,
        group: rowToGroupDto(group),
        assignedCount: 0,
        error: 'None of the supplied item ids exist.',
      });
      return;
    }

    const now = new Date().toISOString();
    const maxOrderRow = await get(
      'SELECT MAX(sort_order) AS max_order FROM group_item_memberships WHERE group_id = ?',
      [groupId],
    );
    let sortOrder = Number(maxOrderRow?.max_order || 0);
    let assignedCount = 0;
    for (const itemId of validIds) {
      sortOrder += 1;
      const result = await run(
        `
        INSERT OR IGNORE INTO group_item_memberships (group_id, item_id, sort_order, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        `,
        [groupId, itemId, sortOrder, now, now],
      );
      if (result.changes > 0) {
        assignedCount += 1;
      } else {
        sortOrder -= 1; // already a member; don't burn a sort slot
      }
    }
    await run('UPDATE groups SET updated_at = ? WHERE id = ?', [now, groupId]);

    res.status(201).json({
      success: true,
      group: rowToGroupDto(await getGroupRowById(groupId)),
      assignedCount,
      skippedCount: validIds.length - assignedCount,
      missingCount: itemIds.length - validIds.length,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      group: null,
      assignedCount: 0,
      error: error.message,
    });
  }
});

// List the item ids that belong to a combination (or any) group.
app.get('/api/groups/:groupId/items', requirePermission('config.read'), async (req, res) => {
  try {
    const groupId = Number(req.params.groupId);
    const group = await getGroupRowById(groupId);
    if (!group) {
      res.status(404).json({ success: false, itemIds: [], error: 'Group not found.' });
      return;
    }
    const rows = await all(
      'SELECT item_id FROM group_item_memberships WHERE group_id = ? ORDER BY sort_order ASC',
      [groupId],
    );
    res.json({ success: true, itemIds: rows.map((row) => row.item_id), error: null });
  } catch (error) {
    res.status(500).json({ success: false, itemIds: [], error: error.message });
  }
});

app.patch('/api/groups/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const group = await saveGroup({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, group: rowToGroupDto(group), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      group: null,
      error: error.message,
    });
  }
});

app.delete('/api/groups/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    await trashAndDelete('groups', id, req);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});



app.get('/api/groups/:id/effective-schema', requirePermission('config.read'), async (req, res) => {
  try {
    const schema = await getEffectiveSchema(Number(req.params.id));
    res.json({ success: true, schema, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      schema: null,
      error: error.message,
    });
  }
});

app.post('/api/materials/parent', requirePermission('inventory.create'), async (req, res) => {
  try {
    const payload = { ...(req.body || {}), actor: currentActor(req) };
    if (!payload.name || !payload.type || payload.numberOfChildren == null) {
      res.status(400).json({
        success: false,
        material: null,
        error: 'name, type, and numberOfChildren are required.',
      });
      return;
    }

    const material = await createParentWithChildren(payload);
    const createdRow = await getMaterialRowByBarcode(material.barcode);
    const groupConfiguration = createdRow
      ? await getMaterialGroupGovernance(createdRow.id)
      : { selectedItemIds: [], selectedItems: [], propertyDrafts: [] };
    res.status(201).json({ success: true, material, groupConfiguration, error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, material: null, error: error.message });
  }
});

app.post('/api/materials/:barcode/child', requirePermission('inventory.create'), async (req, res) => {
  try {
    const payload = { ...(req.body || {}), actor: currentActor(req) };
    if (!String(payload.name || '').trim()) {
      res.status(400).json({
        success: false,
        material: null,
        error: 'name is required.',
      });
      return;
    }
    const material = await createChildMaterial(req.params.barcode, payload);
    res.status(201).json({ success: true, material: rowToMaterialDto(material), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode', requirePermission('inventory.update'), async (req, res) => {
  try {
    const payload = { ...(req.body || {}), actor: currentActor(req) };
    if (!payload.name || !payload.type) {
      res.status(400).json({
        success: false,
        material: null,
        error: 'name and type are required.',
      });
      return;
    }
    const material = await updateMaterialRecord(req.params.barcode, payload);
    const groupConfiguration = await getMaterialGroupGovernance(material.id);
    res.json({
      success: true,
      material: rowToMaterialDto(material),
      groupConfiguration,
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/group-config', requirePermission('inventory.update'), async (req, res) => {
  try {
    const payload = req.body || {};
    const material = await updateMaterialGroupConfiguration(req.params.barcode, payload);
    const groupConfiguration = await getMaterialGroupGovernance(material.id);
    res.json({
      success: true,
      material: rowToMaterialDto(material),
      groupConfiguration,
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.delete('/api/materials/:barcode', requirePermission('inventory.delete'), async (req, res) => {
  try {
    await deleteMaterialRecord(req.params.barcode);
    res.json({ success: true, material: null, error: null });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/link-group', requirePermission('inventory.update'), async (req, res) => {
  try {
    const material = await linkMaterialRecordToGroup(
      req.params.barcode,
      req.body?.groupId,
    );
    res.json({ success: true, material: rowToMaterialDto(material), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/link-item', requirePermission('inventory.update'), async (req, res) => {
  try {
    const material = await linkMaterialRecordToItem(
      req.params.barcode,
      req.body?.itemId,
      req.body?.variationLeafNodeId,
    );
    res.json({ success: true, material: rowToMaterialDto(material), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/unlink', requirePermission('inventory.update'), async (req, res) => {
  try {
    const material = await unlinkMaterialRecord(req.params.barcode);
    res.json({ success: true, material: rowToMaterialDto(material), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/scan', requirePermission('inventory.update'), async (req, res) => {
  try {
    const materialRow = await incrementMaterialScanCount(req.params.barcode);
    if (!materialRow) {
      res.status(404).json({
        success: false,
        material: null,
        error: `No material found for barcode ${req.params.barcode}.`,
      });
      return;
    }
    res.json({
      success: true,
      material: rowToMaterialDto(materialRow),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/scan/reset', requirePermission('inventory.update'), async (req, res) => {
  try {
    const row = await getMaterialRowByBarcode(req.params.barcode);
    if (!row) {
      res.status(404).json({
        success: false,
        material: null,
        error: `No material found for barcode ${req.params.barcode}.`,
      });
      return;
    }
    await run(
      'UPDATE materials SET scan_count = 0, updated_at = ?, last_scanned_at = NULL WHERE id = ?',
      [new Date().toISOString(), row.id],
    );
    await run('DELETE FROM scan_history WHERE barcode = ?', [row.barcode]);
    await logMaterialActivity({
      barcode: row.barcode,
      type: 'scanReset',
      label: 'Trace reset',
      description: 'Scan history was cleared for this material.',
      actor: row.created_by || 'Demo Admin',
    });
    const updatedRow = await get('SELECT * FROM materials WHERE id = ?', [row.id]);
    res.json({
      success: true,
      material: rowToMaterialDto(updatedRow),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.post('/api/inventory/movements', requirePermission('inventory.update'), async (req, res) => {
  try {
    const detail = await applyInventoryMovement({
      ...(req.body || {}),
      actor: currentActor(req),
    });
    res.status(201).json({
      success: true,
      ...detail,
      error: null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      material: null,
      error: error.message,
    });
  }
});

app.get('/api/materials/:barcode/activity', requirePermission('inventory.read'), async (req, res) => {
  try {
    const events = await getMaterialActivity(req.params.barcode);
    res.json({
      success: true,
      events: events.map(rowToMaterialActivityDto),
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, events: [], error: error.message });
  }
});

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

app.get('/templates', requirePermission('config.read'), async (req, res) => {
  try {
    const rows = await all(
      'SELECT * FROM pipeline_templates ORDER BY updated_at DESC, name ASC',
    );
    res.json({ success: true, templates: rows.map(rowToTemplate) });
  } catch (error) {
    res.status(500).json({ success: false, templates: [], error: error.message });
  }
});

app.post('/templates', async (req, res) => {
  try {
    const payload = req.body || {};
    if (!payload.id || !payload.name) {
      res.status(400).json({
        success: false,
        template: null,
        error: 'id and name are required.',
      });
      return;
    }
    const now = new Date().toISOString();
    await run(
      `
      INSERT INTO pipeline_templates (
        id, factory_id, shop_floor_id, name, description, version, status, stage_labels_json, lane_labels_json,
        nodes_json, flows_json, intermediate_naming_convention, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        payload.id,
        payload.factoryId || payload.factory_id || '',
        payload.shopFloorId || payload.shop_floor_id || '',
        payload.name,
        payload.description || '',
        1,
        payload.status || 'draft',
        JSON.stringify(payload.stageLabels || []),
        JSON.stringify(payload.laneLabels || []),
        JSON.stringify(payload.nodes || []),
        JSON.stringify(payload.flows || []),
        payload.intermediateNamingConvention || payload.intermediate_naming_convention || '',
        now,
        now,
      ],
    );
    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [payload.id]);
    res.status(201).json({ success: true, template: rowToTemplate(row) });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

app.put('/templates/:id', async (req, res) => {
  try {
    const existing = await get('SELECT * FROM pipeline_templates WHERE id = ?', [
      req.params.id,
    ]);
    if (!existing) {
      res.status(404).json({
        success: false,
        template: null,
        error: 'Template not found.',
      });
      return;
    }
    const payload = req.body || {};
    const nextVersion = (existing.version || 1) + 1;
    const now = new Date().toISOString();
    await run(
      `
      UPDATE pipeline_templates
      SET factory_id = ?, shop_floor_id = ?, name = ?, description = ?, version = ?, status = ?,
          stage_labels_json = ?, lane_labels_json = ?, nodes_json = ?, flows_json = ?, intermediate_naming_convention = ?, updated_at = ?
      WHERE id = ?
      `,
      [
        payload.factoryId || payload.factory_id || existing.factory_id || '',
        payload.shopFloorId || payload.shop_floor_id || existing.shop_floor_id || '',
        payload.name || existing.name,
        payload.description || existing.description || '',
        nextVersion,
        payload.status || existing.status || 'draft',
        JSON.stringify(payload.stageLabels || parseJson(existing.stage_labels_json, [])),
        JSON.stringify(payload.laneLabels || parseJson(existing.lane_labels_json, [])),
        JSON.stringify(payload.nodes || parseJson(existing.nodes_json, [])),
        JSON.stringify(payload.flows || parseJson(existing.flows_json, [])),
        payload.intermediateNamingConvention ?? payload.intermediate_naming_convention ?? existing.intermediate_naming_convention ?? '',
        now,
        req.params.id,
      ],
    );
    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [
      req.params.id,
    ]);
    res.json({ success: true, template: rowToTemplate(row) });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

app.get('/templates/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [
      req.params.id,
    ]);
    if (!row) {
      res.status(404).json({
        success: false,
        template: null,
        error: 'Template not found.',
      });
      return;
    }
    res.json({ success: true, template: rowToTemplate(row) });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

app.delete('/templates/:id', async (req, res) => {
  try {
    const existing = await get('SELECT * FROM pipeline_templates WHERE id = ?', [req.params.id]);
    if (!existing) {
      res.status(404).json({ success: false, error: 'Template not found.' });
      return;
    }
    await run('DELETE FROM pipeline_templates WHERE id = ?', [req.params.id]);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/runs/:id', async (req, res) => {
  try {
    const existing = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!existing) {
      res.status(404).json({ success: false, error: 'Run not found.' });
      return;
    }
    await run('DELETE FROM run_barcode_inputs WHERE run_id = ?', [req.params.id]);
    await run('DELETE FROM production_scrap WHERE pipeline_run_id = ?', [req.params.id]);
    await run('DELETE FROM pipeline_runs WHERE id = ?', [req.params.id]);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/runs', requirePermission('config.read'), async (req, res) => {
  try {
    const { template_id: templateId } = req.query;
    const rows = templateId
      ? await all(
          'SELECT * FROM pipeline_runs WHERE template_id = ? ORDER BY created_at DESC',
          [templateId],
        )
      : await all('SELECT * FROM pipeline_runs ORDER BY created_at DESC');
    const runs = [];
    for (const row of rows) {
      runs.push(await rowToRun(row));
    }
    res.json({ success: true, runs });
  } catch (error) {
    res.status(500).json({ success: false, runs: [], error: error.message });
  }
});

app.post('/runs', async (req, res) => {
  try {
    const { templateId, name, orderNo, orderItemId, scrapRouting } = req.body || {};
    if (!templateId) {
      res.status(400).json({
        success: false,
        run: null,
        error: 'templateId is required.',
      });
      return;
    }
    const run = await createRunFromTemplate(templateId, name, orderNo, orderItemId, scrapRouting || 'inventory');
    if (!run) {
      res.status(404).json({
        success: false,
        run: null,
        error: 'Template not found.',
      });
      return;
    }
    res.status(201).json({ success: true, run });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.post('/dev/seed-manufacturing-demo', async (req, res) => {
  try {
    const demoBarcode = `DEMO-MAT-${Date.now()}`;
    const demoMachine = `MCH-DEMO-${Date.now()}`;
    const demoDie = `DIE-DEMO-${Date.now()}`;
    
    await run(`
      INSERT INTO machines (
        asset_id, name, primary_photo_url, status, created_at, updated_at
      ) VALUES (?, ?, ?, 'active', datetime('now'), datetime('now'))
    `, [demoMachine, 'Demo Power Press', '/public/power_press.png']);

    await run(`
      INSERT INTO dies (
        tool_code, produced_part_numbers, photo_urls, compatible_machine_group_ids, status, ownership, created_at, updated_at
      ) VALUES (?, '[]', ?, '[]', 'active', 'owned', datetime('now'), datetime('now'))
    `, [demoDie, JSON.stringify(['/public/demo_die.png'])]);
    
    await run(`
      INSERT INTO materials (
        barcode, type, name, unit, kind, created_at, updated_at
      ) VALUES (?, 'raw_material', 'Demo PVC Resin', 'kg', 'single', datetime('now'), datetime('now'))
    `, [demoBarcode]);
    
    const templateId = `tpl-demo-${Date.now()}`;
    const nodes = [
      { id: 'node-1', type: 'operation', machineId: demoMachine, dieId: demoDie }
    ];
    await run(`
      INSERT INTO pipeline_templates (
        id, name, version, status, stage_labels_json, lane_labels_json, nodes_json, flows_json
      ) VALUES (?, 'Demo Power Press Pipeline', 1, 'published', '["Pressing", "Inspection"]', '[]', ?, '[]')
    `, [templateId, JSON.stringify(nodes)]);
    
    const pipelineRun = await createRunFromTemplate(templateId, 'Demo Production Run', null, null, 'inventory');
    
    await run(`
      INSERT INTO run_barcode_inputs (
        id, run_id, node_id, barcode, material_payload_json, scanned_at
      ) VALUES (?, ?, 'node-1', ?, '{}', datetime('now'))
    `, [`input-${Date.now()}`, pipelineRun.id, demoBarcode]);
    
    res.json({ success: true, barcode: demoBarcode });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get('/runs/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const row = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!row) {
      res.status(404).json({ success: false, run: null, error: 'Run not found.' });
      return;
    }
    res.json({ success: true, run: await rowToRun(row) });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.put('/runs/:id/node-status', async (req, res) => {
  try {
    const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!runRow) {
      res.status(404).json({ success: false, run: null, error: 'Run not found.' });
      return;
    }

    const payload = req.body || {};
    const nodeId = payload.nodeId;
    if (!nodeId || !payload.status) {
      res.status(400).json({
        success: false,
        run: null,
        error: 'nodeId and status are required.',
      });
      return;
    }

    const nodeStatuses = parseJson(runRow.node_status_json, {});
    nodeStatuses[nodeId] = payload.status;

    const overrides = parseJson(runRow.overrides_json, {
      actualDurationHoursByNode: {},
      batchQuantityByNode: {},
      machineOverrideByNode: {},
    });

    if (payload.actualDurationHours !== undefined && payload.actualDurationHours !== null) {
      overrides.actualDurationHoursByNode[nodeId] = Number(payload.actualDurationHours);
    }
    if (payload.batchQuantity !== undefined && payload.batchQuantity !== null) {
      overrides.batchQuantityByNode[nodeId] = Number(payload.batchQuantity);
    }
    if (payload.machineOverride) {
      overrides.machineOverrideByNode[nodeId] = payload.machineOverride;
    }

    await run(
      'UPDATE pipeline_runs SET node_status_json = ?, overrides_json = ? WHERE id = ?',
      [JSON.stringify(nodeStatuses), JSON.stringify(overrides), req.params.id],
    );

    // Push to freelancer pool if Assembly node is reached
    const templateRowNode = await get('SELECT * FROM pipeline_templates WHERE id = ?', [runRow.template_id]);
    if (templateRowNode && (payload.status === 'ready' || payload.status === 'active' || payload.status === 'queued')) {
      const tpl = rowToTemplate(templateRowNode);
      const targetNode = tpl.nodes.find(n => n.id === nodeId);
      if (targetNode && targetNode.processType === 'Assembly') {
        const qty = overrides.batchQuantityByNode[nodeId] || 1;
        
        // Find output item
        let itemId = 0;
        const outName = targetNode.outputs && targetNode.outputs[0];
        if (outName) {
           const matched = await get('SELECT id FROM items WHERE LOWER(name) = ? OR LOWER(alias) = ?', [outName.toLowerCase(), outName.toLowerCase()]);
           if (matched) itemId = matched.id;
        }
        
        // Check if job already exists for this run/node
        // To be safe, we'll just insert a new pending job. We will need a way to track the run_id, but the schema doesn't have it. We'll just insert.
        const result = await run(
          `INSERT INTO freelancer_jobs (batch_id, item_id, variation_leaf_node_id, quantity, status, payout_balance, created_at, updated_at)
           VALUES (NULL, ?, 0, ?, 'pending', 0, ?, ?)`,
          [itemId, qty, new Date().toISOString(), new Date().toISOString()]
        );
        const newJobId = result.lastID;

        // Populate tasks from BOM
        const bomLines = await all('SELECT * FROM item_bom_lines WHERE item_id = ?', [itemId]);
        for (const line of bomLines) {
           // We map the material barcode back to an item if needed, but tasks schema requires item_id.
           // Since item_bom_lines has material_barcode, let's find the linked item.
           const mat = await get('SELECT linked_item_id, linked_variation_leaf_node_id FROM materials WHERE barcode = ?', [line.material_barcode]);
           if (mat && mat.linked_item_id) {
             const reqQty = (line.quantity_per_unit * qty) * (1 + (line.wastage_percent / 100));
             await run(
               `INSERT INTO freelancer_job_tasks (job_id, item_id, variation_leaf_node_id, required_quantity, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'pending', ?, ?)`,
               [newJobId, mat.linked_item_id, mat.linked_variation_leaf_node_id || 0, reqQty, new Date().toISOString(), new Date().toISOString()]
             );
           }
        }
      }
    }

    // Check if the overall pipeline run is completed
    const templateRow = await get('SELECT * FROM pipeline_templates WHERE id = ?', [
      runRow.template_id,
    ]);
    if (templateRow) {
      const template = rowToTemplate(templateRow);
      const allDone = template.nodes.every((node) => {
        const s = nodeStatuses[node.id];
        return s === 'done' || s === 'skipped';
      });

      if (allDone && runRow.status !== 'completed') {
        const now = new Date().toISOString();
        await run(
          "UPDATE pipeline_runs SET status = 'completed', completed_at = ? WHERE id = ?",
          [now, req.params.id],
        );

        // Find item ID to link to the flat production run
        let itemId = null;
        let variationLeafNodeId = 0;
        let variationPathLabel = '';

        const lastNode = template.nodes.find((n) => !n.isIntermediate) || template.nodes[template.nodes.length - 1];
        const finalOutput = lastNode && lastNode.outputs && lastNode.outputs[0];
        if (finalOutput) {
          const matchedItem = await get(
            'SELECT * FROM items WHERE LOWER(name) = ? OR LOWER(display_name) = ? OR LOWER(alias) = ?',
            [finalOutput.toLowerCase(), finalOutput.toLowerCase(), finalOutput.toLowerCase()]
          );
          if (matchedItem) {
            itemId = matchedItem.id;
            const variationRow = await get(
              "SELECT * FROM item_variation_nodes WHERE item_id = ? AND kind = 'leaf' LIMIT 1",
              [itemId]
            );
            if (variationRow) {
              variationLeafNodeId = variationRow.id;
              variationPathLabel = variationRow.display_name || variationRow.name || '';
            }
          }
        }

        if (!itemId) {
          const fallbackItem = await get('SELECT * FROM items LIMIT 1');
          if (fallbackItem) {
            itemId = fallbackItem.id;
            const variationRow = await get(
              "SELECT * FROM item_variation_nodes WHERE item_id = ? AND kind = 'leaf' LIMIT 1",
              [itemId]
            );
            if (variationRow) {
              variationLeafNodeId = variationRow.id;
              variationPathLabel = variationRow.display_name || variationRow.name || '';
            }
          }
        }

        if (itemId) {
          const batchQuantity = (lastNode && overrides.batchQuantityByNode[lastNode.id]) || 1;
          const runCode = `RUN-${req.params.id.substring(0, 8).toUpperCase()}`;
          
          // Check if this run code already exists in production_runs
          const exists = await get('SELECT id FROM production_runs WHERE run_code = ?', [runCode]);
          if (!exists) {
            await run(
              `
              INSERT INTO production_runs (
                run_code, status, completed_at, item_id, variation_leaf_node_id,
                variation_path_label, output_quantity, uom, location,
                source_metadata_json, created_at, updated_at
              ) VALUES (?, 'completed', ?, ?, ?, ?, ?, 'pcs', 'Production Output', ?, ?, ?)
              `,
              [
                runCode,
                now,
                itemId,
                variationLeafNodeId,
                variationPathLabel,
                batchQuantity,
                JSON.stringify({
                  pipelineRunId: req.params.id,
                  pipelineTemplateId: runRow.template_id,
                  pipelineName: runRow.name,
                }),
                now,
                now,
              ]
            );
            
            // Generate a fresh barcode and add inventory for the completed pipeline
            const freshBarcode = `LOT-${runCode}-${Math.floor(Math.random() * 1000)}`;
            const actor = actorFromRequest(req);
            
            // We use ensureMaterialForItemSelection, but we override barcode to force a fresh lot
            // First get the template/snapshot
            const snapshot = await getItemSelectionSnapshot(itemId, variationLeafNodeId);
            if (snapshot) {
              const uom = snapshot.item.unit || 'pcs';
              const uomId = snapshot.item.unit_id || null;
              
              await run(`
                INSERT INTO materials (
                  barcode, name, type, kind, group_mode, 
                  linked_group_id, linked_item_id, linked_variation_leaf_node_id,
                  unit, unit_id, inventory_state, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              `, [
                freshBarcode,
                snapshot.fullName || 'Finished Good',
                'material',
                'lot',
                'tracked',
                snapshot.item.group_id,
                itemId,
                variationLeafNodeId,
                uom,
                uomId,
                'available',
                now
              ]);
              
              await applyInventoryMovementCore({
                barcode: freshBarcode,
                movementType: 'receive',
                qty: Number(batchQuantity),
                primaryQty: Number(batchQuantity),
                uom: uom,
                toLocationId: 'MAIN',
                reasonCode: 'production_output',
                referenceType: 'pipeline_run',
                referenceId: req.params.id,
                actor: actor?.id || null,
                lotCode: freshBarcode,
              }, { useTransaction: false });
            }
          }
        }
      }
    }

    const updatedRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [
      req.params.id,
    ]);
    res.json({ success: true, run: await rowToRun(updatedRow) });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.post('/runs/:id/barcodes', async (req, res) => {
  try {
    const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!runRow) {
      res.status(404).json({ success: false, run: null, error: 'Run not found.' });
      return;
    }

    const payload = req.body || {};
    if (!payload.nodeId || !payload.barcode) {
      res.status(400).json({
        success: false,
        run: null,
        error: 'nodeId and barcode are required.',
      });
      return;
    }

    const materialRow = await incrementMaterialScanCount(payload.barcode);
    if (!materialRow) {
      res.status(404).json({
        success: false,
        run: null,
        error: `No material found for barcode ${payload.barcode}.`,
      });
      return;
    }
    const material = rowToMaterialDto(materialRow);
    const barcodeInputId = `barcode-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
    await run(
      `
      INSERT INTO run_barcode_inputs (
        id, run_id, node_id, barcode, material_id, material_payload_json, scanned_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      [
        barcodeInputId,
        req.params.id,
        payload.nodeId,
        material.barcode,
        String(material.id || ''),
        JSON.stringify({
          barcode: material.barcode,
          materialName: material.name,
          materialType: material.type,
          scanCount: material.scanCount,
          quantity: payload.quantity !== undefined && payload.quantity !== null ? Number(payload.quantity) : null,
          unit: material.unit,
        }),
        new Date().toISOString(),
      ],
    );

    if (payload.quantity !== undefined && payload.quantity !== null) {
      const qty = Number(payload.quantity);
      if (qty > 0) {
        await applyInventoryMovement({
          barcode: material.barcode,
          movementType: 'consume',
          qty: qty,
          actor: 'Floor Engineer',
          referenceType: 'pipeline_run',
          referenceId: req.params.id,
          reasonCode: 'PRODUCTION_ASSIGN',
        });
      }
    }

    const updatedRunRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [
      req.params.id,
    ]);
    res.json({ success: true, run: await rowToRun(updatedRunRow) });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, run: null, error: error.message });
  }
});

app.put(['/runs/:id/barcodes', '/runs/:id/barcodes/:nodeId/:barcode'], async (req, res) => {
  try {
    const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!runRow) {
      res.status(404).json({ success: false, run: null, error: 'Run not found.' });
      return;
    }

    const nodeId = req.params.nodeId || req.query.nodeId || req.body?.nodeId;
    const barcode = req.params.barcode || req.query.barcode || req.body?.barcode;
    const quantity = req.body?.quantity !== undefined && req.body.quantity !== null 
      ? Number(req.body.quantity) 
      : (req.query.quantity !== undefined && req.query.quantity !== null ? Number(req.query.quantity) : null);

    if (!nodeId || !barcode || quantity === null || isNaN(quantity)) {
      res.status(400).json({
        success: false,
        run: null,
        error: 'nodeId, barcode, and valid quantity are required.',
      });
      return;
    }

    const existingInput = await get(
      'SELECT * FROM run_barcode_inputs WHERE run_id = ? AND node_id = ? AND barcode = ?',
      [req.params.id, nodeId, barcode]
    );

    if (!existingInput) {
      res.status(404).json({
        success: false,
        run: null,
        error: 'Assigned stock not found for this node.',
      });
      return;
    }

    const materialPayload = JSON.parse(existingInput.material_payload_json || '{}');
    const oldQty = materialPayload.quantity !== undefined && materialPayload.quantity !== null 
      ? Number(materialPayload.quantity) 
      : 0;

    const qtyDiff = quantity - oldQty;

    if (qtyDiff > 0) {
      await applyInventoryMovement({
        barcode: barcode,
        movementType: 'consume',
        qty: qtyDiff,
        actor: 'Floor Engineer',
        referenceType: 'pipeline_run',
        referenceId: req.params.id,
        reasonCode: 'PRODUCTION_ASSIGN_UPDATE',
      });
    } else if (qtyDiff < 0) {
      await applyInventoryMovement({
        barcode: barcode,
        movementType: 'adjust',
        qty: -qtyDiff,
        actor: 'Floor Engineer',
        referenceType: 'pipeline_run',
        referenceId: req.params.id,
        reasonCode: 'PRODUCTION_ASSIGN_UPDATE',
      });
    }

    materialPayload.quantity = quantity;
    await run(
      'UPDATE run_barcode_inputs SET material_payload_json = ? WHERE id = ?',
      [JSON.stringify(materialPayload), existingInput.id]
    );

    const updatedRunRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    res.json({ success: true, run: await rowToRun(updatedRunRow) });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, run: null, error: error.message });
  }
});

app.delete(['/runs/:id/barcodes', '/runs/:id/barcodes/:nodeId/:barcode'], async (req, res) => {
  try {
    const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!runRow) {
      res.status(404).json({ success: false, run: null, error: 'Run not found.' });
      return;
    }

    const nodeId = req.params.nodeId || req.query.nodeId || req.body?.nodeId;
    const barcode = req.params.barcode || req.query.barcode || req.body?.barcode;

    if (!nodeId || !barcode) {
      res.status(400).json({
        success: false,
        run: null,
        error: 'nodeId and barcode are required.',
      });
      return;
    }

    const existingInput = await get(
      'SELECT * FROM run_barcode_inputs WHERE run_id = ? AND node_id = ? AND barcode = ?',
      [req.params.id, nodeId, barcode]
    );

    if (!existingInput) {
      res.status(404).json({
        success: false,
        run: null,
        error: 'Assigned stock not found for this node.',
      });
      return;
    }

    const materialPayload = JSON.parse(existingInput.material_payload_json || '{}');
    const oldQty = materialPayload.quantity !== undefined && materialPayload.quantity !== null 
      ? Number(materialPayload.quantity) 
      : 0;

    if (oldQty > 0) {
      await applyInventoryMovement({
        barcode: barcode,
        movementType: 'adjust',
        qty: oldQty,
        actor: 'Floor Engineer',
        referenceType: 'pipeline_run',
        referenceId: req.params.id,
        reasonCode: 'PRODUCTION_ASSIGN_DELETE',
      });
    }

    await run(
      'DELETE FROM run_barcode_inputs WHERE id = ?',
      [existingInput.id]
    );

    // Recompute AFTER the row is gone so linked_pipeline_count (and the
    // "in pipeline" headband) reflects the detachment. Any movement above ran
    // while the row still existed, so it would have counted the stale row.
    await recomputeMaterialInventorySummary(barcode);

    const updatedRunRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    res.json({ success: true, run: await rowToRun(updatedRunRow) });
  } catch (error) {
    res.status(error.statusCode || 500).json({ success: false, run: null, error: error.message });
  }
});
app.put('/runs/:id/node-metrics', async (req, res) => {
  try {
    const { nodeId, metrics } = req.body;
    if (!nodeId || !metrics) {
      return res.status(400).json({ success: false, run: null, error: 'nodeId and metrics are required.' });
    }
    const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!runRow) {
      return res.status(404).json({ success: false, run: null, error: 'Run not found.' });
    }

    await upsertStageReconciliation(req.params.id, nodeId, metrics);

    // Auto-generate internal challan for leftover if remaining is specified
    if (metrics.remaining !== undefined) {
      const runId = req.params.id;
      const sourceRef = `Leftover/Run ${runId}/Node ${nodeId}`;
      
      // Find input item for this node
      let itemId = null;
      const templateRow = await get('SELECT * FROM pipeline_templates WHERE id = ?', [runRow.template_id]);
      if (templateRow) {
        const tpl = rowToTemplate(templateRow);
        const node = tpl.nodes.find(n => n.id === nodeId);
        const inName = node && node.inputs && node.inputs[0];
        if (inName) {
          const matched = await get('SELECT id FROM items WHERE LOWER(name) = ? OR LOWER(alias) = ?', [inName.toLowerCase(), inName.toLowerCase()]);
          if (matched) itemId = matched.id;
        }
      }
      
      if (itemId) {
        let existingChallan = await get('SELECT id FROM delivery_challans WHERE source_reference = ?', [sourceRef]);
        if (existingChallan) {
          if (Number(metrics.remaining) > 0) {
            await run(`UPDATE delivery_challan_items SET quantity_pcs = ?, weight = ? WHERE challan_id = ?`, [Number(metrics.remaining), Number(metrics.remaining), existingChallan.id]);
          } else {
            // If they set it back to 0, let's delete the challan items or the whole challan
            await run('DELETE FROM delivery_challan_items WHERE challan_id = ?', [existingChallan.id]);
            await run('DELETE FROM delivery_challans WHERE id = ?', [existingChallan.id]);
          }
        } else if (Number(metrics.remaining) > 0) {
          const challanNo = await generateChallanNumber('internal');
          const challanRes = await run(
            `INSERT INTO delivery_challans (
              type, challan_no, date, location, source_reference, status, maintain_stocks, purpose, internal_purpose, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              'internal', challanNo, new Date().toISOString(), 'MAIN', sourceRef, 'completed', 0, 'manufacturing', 'leftover', new Date().toISOString(), new Date().toISOString()
            ]
          );
          const challanId = challanRes.lastID;
          await run(
            `INSERT INTO delivery_challan_items (
              challan_id, item_id, quantity_pcs, weight, line_no, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
            [
              challanId, itemId, Number(metrics.remaining), Number(metrics.remaining), 1, new Date().toISOString(), new Date().toISOString()
            ]
          );
        }
      }
    }

    res.json({ success: true, run: await rowToRun(runRow) });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.put('/runs/:id/batches', async (req, res) => {
  try {
    const { batches } = req.body;
    if (!Array.isArray(batches)) {
      return res.status(400).json({ success: false, run: null, error: 'batches array is required.' });
    }
    const runRow = await get('SELECT id FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!runRow) {
      return res.status(404).json({ success: false, run: null, error: 'Run not found.' });
    }
    await run('UPDATE pipeline_runs SET batches_json = ? WHERE id = ?', [
      JSON.stringify(batches),
      req.params.id,
    ]);
    const updatedRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    res.json({ success: true, run: await rowToRun(updatedRow) });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.post('/api/production-scrap', requirePermission('config.write'), async (req, res) => {
  try {
    const { pipelineRunId, nodeId, orderNo, materialBarcode, scrapQty, scrapItemId, scrapItemName } = req.body;
    if (!pipelineRunId || !nodeId || !materialBarcode) {
      return res.status(400).json({ success: false, error: 'pipelineRunId, nodeId, and materialBarcode are required.' });
    }

    // First log to legacy production_scrap table
    await run(`
      INSERT INTO production_scrap (pipeline_run_id, node_id, order_no, material_barcode, scrap_qty, logged_by)
      VALUES (?, ?, ?, ?, ?, ?)
    `, [pipelineRunId, nodeId, orderNo, materialBarcode, scrapQty, actorFromRequest(req)]);

    // Check pipeline for targeted scrap routing group
    const runRow = await get('SELECT scrap_routing FROM pipeline_runs WHERE id = ?', [pipelineRunId]);
    const scrapRoutingGroupId = runRow?.scrap_routing && runRow.scrap_routing !== 'inventory' ? runRow.scrap_routing : null;

    // Bridge to actual inventory. The stage's chosen Scrap-group item (set in
    // the pipeline builder) wins: the lot is linked to that item and named per
    // order, so each order's scrap shows as its own entry under the item.
    // Without a scrap item we fall back to the legacy source-material link.
    const scrapItem = scrapItemId
      ? await get(`
          SELECT i.id, i.name, i.display_name, i.unit_id, u.symbol AS unit_symbol
          FROM items i
          LEFT JOIN units u ON u.id = i.unit_id
          WHERE i.id = ?
        `, [Number(scrapItemId)])
      : null;
    const sourceMaterial = await getMaterialRowByBarcode(materialBarcode);
    if ((scrapItem || sourceMaterial) && Number(scrapQty) > 0) {
      const actor = actorFromRequest(req);
      const newLotBarcode = `LOT-SCRAP-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
      const lotName = scrapItem
        ? `${scrapItemName || scrapItem.display_name || scrapItem.name} - ${orderNo || pipelineRunId}`
        : `Scrap - ${sourceMaterial.name}`;
      const lotUnit = sourceMaterial?.unit || scrapItem?.unit_symbol || 'pcs';

      await run(`
        INSERT INTO materials (
          barcode, name, type, kind, group_mode,
          linked_group_id, linked_item_id, linked_variation_leaf_node_id,
          unit, unit_id, inventory_state, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `, [
        newLotBarcode,
        lotName,
        sourceMaterial?.type ?? 'Scrap',
        'lot',
        'tracked',
        scrapRoutingGroupId ? Number(scrapRoutingGroupId) : null,
        scrapItem ? scrapItem.id : sourceMaterial.linked_item_id,
        scrapItem ? null : sourceMaterial.linked_variation_leaf_node_id,
        lotUnit,
        sourceMaterial?.unit_id ?? scrapItem?.unit_id ?? null,
        'available',
        new Date().toISOString()
      ]);

      await applyInventoryMovementCore({
        barcode: newLotBarcode,
        movementType: 'receive',
        qty: Number(scrapQty),
        primaryQty: Number(scrapQty),
        uom: lotUnit,
        toLocationId: 'SCRAP-BIN',
        reasonCode: 'production_scrap',
        referenceType: 'pipeline_scrap',
        referenceId: pipelineRunId,
        actor: actor?.id || null,
        lotCode: newLotBarcode,
      }, { useTransaction: false });

      // Auto-generate internal challan for scrap so it appears in Ledger
      const challanNo = await generateChallanNumber('internal');
      const challanRes = await run(
        `INSERT INTO delivery_challans (
          type, challan_no, date, location, source_reference, status, maintain_stocks, purpose, internal_purpose, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          'internal', challanNo, new Date().toISOString(), 'MAIN', `Scrap/Run ${pipelineRunId}/Node ${nodeId}`, 'completed', 0, 'manufacturing', 'scrap', new Date().toISOString(), new Date().toISOString()
        ]
      );
      
      const challanId = challanRes.lastID;
      await run(
        `INSERT INTO delivery_challan_items (
          challan_id, item_id, quantity_pcs, weight, line_no, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          challanId, scrapItem ? scrapItem.id : sourceMaterial.linked_item_id, Number(scrapQty), Number(scrapQty), 1, new Date().toISOString(), new Date().toISOString()
        ]
      );
    }

    res.status(201).json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/production-scrap', requirePermission('config.read'), async (req, res) => {
  try {
    const { pipelineRunId, nodeId } = req.query;
    let query = 'SELECT * FROM production_scrap WHERE 1=1';
    const params = [];
    if (pipelineRunId) {
      query += ' AND pipeline_run_id = ?';
      params.push(pipelineRunId);
    }
    if (nodeId) {
      query += ' AND node_id = ?';
      params.push(nodeId);
    }
    query += ' ORDER BY created_at DESC';
    const rows = await all(query, params);
    res.json({ success: true, data: rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});


// ── SANDBOX CONTROL PLANE ROUTES ──

// Public configuration fetch endpoint (polled by clients at startup/update check)
app.get('/sandbox-config/:clientId', async (req, res) => {
  try {
    const clientId = req.params.clientId;
    const row = await get('SELECT config_json FROM sandbox_client_configs WHERE client_id = ?', [clientId]);
    if (row) {
      res.setHeader('Content-Type', 'application/json');
      return res.send(row.config_json);
    }
    // Fall back to default config if client specific config doesn't exist
    const defaultRow = await get('SELECT config_json FROM sandbox_client_configs WHERE client_id = ?', ['default']);
    if (defaultRow) {
      res.setHeader('Content-Type', 'application/json');
      return res.send(defaultRow.config_json);
    }
    // Static fallback
    res.json({
      "modules": {
        "orders": true,
        "masters": true,
        "inventory": true,
        "production": true,
        "pm": true,
        "jobs": true,
        "delivery_challans": true
      },
      "orders": {
        "statusColors": {
          "pending": "#FFA500",
          "in_progress": "#1E90FF",
          "completed": "#32CD32"
        },
        "allowCustomActions": true
      },
      "update": {
        "channel": "stable",
        "latest_version": "1.0.0"
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Dynamic Appcast XML endpoint for the auto-updater
app.get('/api/appcast/:clientId.xml', async (req, res) => {
  try {
    const clientId = req.params.clientId;
    let configStr = null;
    const row = await get('SELECT config_json FROM sandbox_client_configs WHERE client_id = ?', [clientId]);
    if (row) {
      configStr = row.config_json;
    } else {
      const defaultRow = await get('SELECT config_json FROM sandbox_client_configs WHERE client_id = ?', ['default']);
      if (defaultRow) configStr = defaultRow.config_json;
    }
    
    let targetVersion = '1.0.0';
    if (configStr) {
      try {
        const config = JSON.parse(configStr);
        if (config.update && config.update.latest_version) {
          targetVersion = config.update.latest_version;
        }
      } catch (e) {}
    }

    // Replace this with your actual S3 bucket public URL or CloudFront distribution
    const bucketUrl = process.env.AWS_S3_UPDATE_BUCKET_URL || 'https://your-bucket.s3.amazonaws.com/releases';
    const downloadUrl = `${bucketUrl}/${targetVersion}/paper-windows-v${targetVersion}.exe`;

    const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Paper Appcast</title>
        <item>
            <title>Version ${targetVersion}</title>
            <sparkle:version>${targetVersion}</sparkle:version>
            <enclosure url="${downloadUrl}" sparkle:os="windows" />
        </item>
    </channel>
</rss>`;

    res.setHeader('Content-Type', 'application/xml');
    res.send(xml);
  } catch (error) {
    res.status(500).send('<error>Internal Server Error</error>');
  }
});

// Serve the centralized feature registry definition
app.get('/api/sandbox-dashboard/feature-registry', (req, res) => {
  try {
    const registryPath = path.join(__dirname, 'feature_registry.json');
    if (fs.existsSync(registryPath)) {
      const data = fs.readFileSync(registryPath, 'utf8');
      res.setHeader('Content-Type', 'application/json');
      return res.send(data);
    }
    return res.json([]);
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Client SQLite database sync endpoint
app.post('/api/sandbox-sync/:clientId', async (req, res) => {
  try {
    const clientId = req.params.clientId;
    const { data } = req.body;
    if (!data) {
      return res.status(400).json({ success: false, error: 'Missing sync data' });
    }
    
    const zlib = require('zlib');
    const buffer = Buffer.from(data, 'base64');
    zlib.gunzip(buffer, async (err, decoded) => {
      if (err) {
        console.error('[Sandbox Sync Error] Gunzip failed:', err);
        return res.status(400).json({ success: false, error: 'Decompression failed' });
      }
      try {
        const dbStateStr = decoded.toString('utf8');
        // Validate JSON
        JSON.parse(dbStateStr);
        
        await run(`
          INSERT INTO sandbox_sync_states (client_id, db_state, updated_at)
          VALUES (?, ?, datetime('now'))
          ON CONFLICT(client_id) DO UPDATE SET
            db_state = excluded.db_state,
            updated_at = excluded.updated_at
        `, [clientId, dbStateStr]);
        
        res.json({ success: true, message: 'Sync successful' });
      } catch (e) {
        console.error('[Sandbox Sync Error] JSON parse or SQL save failed:', e);
        res.status(400).json({ success: false, error: 'Invalid sync payload structure' });
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Client session replay sync endpoint
app.post('/api/session-replay/:clientId', async (req, res) => {
  try {
    const clientId = req.params.clientId;
    const { data } = req.body;
    if (!data) return res.status(400).json({ success: false, error: 'Missing replay data' });
    
    const zlib = require('zlib');
    const buffer = Buffer.from(data, 'base64');
    zlib.gunzip(buffer, async (err, decoded) => {
      if (err) {
        console.error('[Replay Sync Error] Gunzip failed:', err);
        return res.status(400).json({ success: false, error: 'Decompression failed' });
      }
      try {
        const payload = JSON.parse(decoded.toString('utf8'));
        const { sessionId, events } = payload;
        
        // Fetch existing replay for this session
        const existing = await get('SELECT events_json FROM sandbox_replays WHERE client_id = ? AND session_id = ?', [clientId, sessionId]);
        let allEvents = [];
        if (existing) {
          allEvents = JSON.parse(existing.events_json);
        }
        allEvents.push(...events);
        
        if (existing) {
          await run('UPDATE sandbox_replays SET events_json = ? WHERE client_id = ? AND session_id = ?', [JSON.stringify(allEvents), clientId, sessionId]);
        } else {
          await run('INSERT INTO sandbox_replays (client_id, session_id, events_json, created_at) VALUES (?, ?, ?, datetime(\'now\'))', [clientId, sessionId, JSON.stringify(allEvents)]);
        }
        
        res.json({ success: true, message: 'Replay synced successfully' });
      } catch (e) {
        console.error('[Replay Sync Error] JSON parse or SQL save failed:', e);
        res.status(400).json({ success: false, error: 'Invalid payload structure' });
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Dashboard APIs (for config and observation)
app.get('/api/sandbox-dashboard/clients', async (req, res) => {
  try {
    const configs = await all('SELECT client_id, updated_at FROM sandbox_client_configs');
    const syncs = await all('SELECT client_id, updated_at FROM sandbox_sync_states');
    
    const clientsMap = {};
    for (const c of configs) {
      clientsMap[c.client_id] = { clientId: c.client_id, configUpdatedAt: c.updated_at, syncUpdatedAt: null };
    }
    for (const s of syncs) {
      if (!clientsMap[s.client_id]) {
        clientsMap[s.client_id] = { clientId: s.client_id, configUpdatedAt: null };
      }
      clientsMap[s.client_id].syncUpdatedAt = s.updated_at;
    }
    res.json({ success: true, clients: Object.values(clientsMap) });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/sandbox-dashboard/client/:clientId', async (req, res) => {
  try {
    const clientId = req.params.clientId;
    const configRow = await get('SELECT config_json FROM sandbox_client_configs WHERE client_id = ?', [clientId]);
    const syncRow = await get('SELECT db_state, updated_at FROM sandbox_sync_states WHERE client_id = ?', [clientId]);
    const pinRow = await get('SELECT activation_pin FROM sandbox_client_pins WHERE client_id = ?', [clientId]);
    const machines = await all('SELECT * FROM sandbox_activated_machines WHERE client_id = ?', [clientId]);
    const users = await all('SELECT * FROM sandbox_client_users WHERE client_id = ?', [clientId]);
    
    res.json({
      success: true,
      clientId,
      activationPin: pinRow ? pinRow.activation_pin : null,
      activatedMachines: machines || [],
      users: users || [],
      config: configRow ? JSON.parse(configRow.config_json) : null,
      syncState: syncRow ? JSON.parse(syncRow.db_state) : null,
      syncUpdatedAt: syncRow ? syncRow.updated_at : null
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/sandbox-dashboard/client/:clientId/config', async (req, res) => {
  try {
    const clientId = req.params.clientId;
    const { config } = req.body;
    if (!config) {
      return res.status(400).json({ success: false, error: 'Missing configuration' });
    }
    
    await run(`
      INSERT INTO sandbox_client_configs (client_id, config_json, updated_at)
      VALUES (?, ?, datetime('now'))
      ON CONFLICT(client_id) DO UPDATE SET
        config_json = excluded.config_json,
        updated_at = excluded.updated_at
    `, [clientId, JSON.stringify(config)]);
    
    // Generate an activation pin if it doesn't exist
    const pinRow = await get('SELECT activation_pin FROM sandbox_client_pins WHERE client_id = ?', [clientId]);
    if (!pinRow) {
      const newPin = Math.floor(100000 + Math.random() * 900000).toString(); // 6 digit pin
      await run('INSERT INTO sandbox_client_pins (client_id, activation_pin, created_at) VALUES (?, ?, datetime("now"))', [clientId, newPin]);
    }
    
    res.json({ success: true, message: 'Configuration saved' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/activation/activate', async (req, res) => {
  try {
    const { client_id, activation_pin, fingerprint } = req.body;
    if (!client_id || !activation_pin || !fingerprint) {
      return res.status(400).json({ success: false, error: 'Missing required activation parameters' });
    }

    // Verify pin
    const pinRow = await get('SELECT activation_pin FROM sandbox_client_pins WHERE client_id = ?', [client_id]);
    if (!pinRow || pinRow.activation_pin !== activation_pin) {
      return res.status(401).json({ success: false, error: 'Invalid client ID or activation PIN' });
    }

    // Verify machine limit (max 3)
    const machineCountRow = await get('SELECT COUNT(*) as count FROM sandbox_activated_machines WHERE client_id = ?', [client_id]);
    if (machineCountRow && machineCountRow.count >= 3) {
      // Check if this fingerprint is already one of the 3
      const existing = await get('SELECT token FROM sandbox_activated_machines WHERE client_id = ? AND machine_fingerprint = ?', [client_id, fingerprint]);
      if (!existing) {
        return res.status(403).json({ success: false, error: 'Activation limit reached (Max 3 machines).' });
      }
    }

    // Generate token (crypto random for sandbox)
    const token = crypto.randomBytes(32).toString('hex');
    
    await run(`
      INSERT INTO sandbox_activated_machines (client_id, machine_fingerprint, token, activated_at)
      VALUES (?, ?, ?, datetime('now'))
      ON CONFLICT(client_id, machine_fingerprint) DO UPDATE SET token = excluded.token, activated_at = excluded.activated_at
    `, [client_id, fingerprint, token]);

    // Check if this is the first activation (to guide user creation on the frontend)
    const isFirstActivation = machineCountRow.count === 0;

    res.json({ success: true, token, isFirstActivation });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/sandbox-dashboard/client/:clientId/users', async (req, res) => {
  try {
    const clientId = req.params.clientId;
    const { email, role } = req.body;
    if (!email || !role) return res.status(400).json({ success: false, error: 'Missing user details' });

    await run(`
      INSERT INTO sandbox_client_users (client_id, user_email, role, created_at)
      VALUES (?, ?, ?, datetime('now'))
      ON CONFLICT(client_id, user_email) DO UPDATE SET role = excluded.role
    `, [clientId, email, role]);

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/sandbox-dashboard/client/:clientId/user/:email', async (req, res) => {
  try {
    const { clientId, email } = req.params;
    await run('DELETE FROM sandbox_client_users WHERE client_id = ? AND user_email = ?', [clientId, email]);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/activate/:clientId/:fingerprint', async (req, res) => {
  try {
    const clientId = req.params.clientId;
    const fingerprint = req.params.fingerprint;
    await run('DELETE FROM sandbox_activated_machines WHERE client_id = ? AND machine_fingerprint = ?', [clientId, fingerprint]);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/build/global', async (req, res) => {
  try {
    // Empty version = fresh build (artifact only). The workflow gates its S3
    // publish step on a non-empty target_version, so don't default it here.
    const targetVersion = (req.body.targetVersion || '').trim();
    const githubToken = process.env.GITHUB_TOKEN;
    const githubOwner = process.env.GITHUB_OWNER || 'your-github-username';
    const githubRepo = process.env.GITHUB_REPO || 'core-erp';

    if (!githubToken) {
      return res.status(500).json({ success: false, error: 'GITHUB_TOKEN is not set in environment variables.' });
    }

    const url = `https://api.github.com/repos/${githubOwner}/${githubRepo}/actions/workflows/build-desktop.yml/dispatches`;
    
    // Using global fetch (Node 18+)
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Accept': 'application/vnd.github+json',
        'Authorization': `Bearer ${githubToken}`,
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        ref: 'main',
        inputs: {
          target_version: targetVersion
        }
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      return res.status(response.status).json({ success: false, error: `GitHub API error: ${errorText}` });
    }

    res.json({
      success: true,
      message: targetVersion
        ? `Global Build v${targetVersion} dispatched successfully!`
        : 'Fresh build dispatched (no version, not published).',
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/sandbox-dashboard/client/:clientId/replays', async (req, res) => {
  try {
    const clientId = req.params.clientId;
    const rows = await all('SELECT id, session_id, created_at, length(events_json) as size FROM sandbox_replays WHERE client_id = ? ORDER BY created_at DESC', [clientId]);
    res.json({ success: true, replays: rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/sandbox-dashboard/replay/:id', async (req, res) => {
  try {
    const id = req.params.id;
    const row = await get('SELECT session_id, events_json, created_at FROM sandbox_replays WHERE id = ?', [id]);
    if (!row) return res.status(404).json({ success: false, error: 'Replay not found' });
    res.json({
      success: true,
      sessionId: row.session_id,
      events: JSON.parse(row.events_json),
      createdAt: row.created_at
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Serve the beautiful Dashboard UI
app.get('/dashboard', (req, res) => {
  const dashboardPath = path.join(__dirname, 'dashboard.html');
  if (fs.existsSync(dashboardPath)) {
    res.sendFile(dashboardPath);
  } else {
    res.status(404).send('Dashboard UI file not found');
  }
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


async function clearAllData() {
  await run('PRAGMA foreign_keys = OFF');
  await run('BEGIN TRANSACTION');
  try {
    const allTables = await all("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    const preserveTables = [
      'users',
      'auth_sessions',
      'auth_events',
      'role_permissions',
      'user_permission_overrides',
      'permission_templates',
      'permission_template_permissions',
      'user_permission_templates'
    ];
    for (const table of allTables) {
      if (!preserveTables.includes(table.name)) {
        await run("DELETE FROM " + table.name + "");
      }
    }
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
      await recomputeMaterialInventorySummary(barcode, now);
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
    status: 'published',
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
}

async function resetAndSeedDemoData(scenarioId = 'default') {
  await initDb();
  await clearAllData();
  await reseedDemoData(scenarioId);
}

function rowToDepartmentDto(row) {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    description: row.description || '',
    photoUrl: row.photo_url || '',
    isArchived: Number(row.is_archived || 0) === 1,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function rowToEmployeeDto(row) {
  if (!row) return null;
  return {
    id: row.id,
    departmentId: row.department_id,
    name: row.name,
    role: row.role || '',
    phone: row.phone || '',
    aadharNumber: row.aadhar_number || '',
    aadharPhotoUrl: row.aadhar_photo_url || '',
    panNumber: row.pan_number || '',
    panPhotoUrl: row.pan_photo_url || '',
    address: row.address || '',
    employeePhotoUrl: row.employee_photo_url || '',
    employmentType: row.employment_type || 'in-house',
    status: row.status || 'active',
    barcodeId: row.barcode_id || '',
    email: row.email || '',
    dateOfBirth: row.date_of_birth || '',
    isArchived: Number(row.is_archived || 0) === 1,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    // Unified People: the linked login/profile account (null when none).
    userId: row.user_id != null ? Number(row.user_id) : null,
    login: row.user_id != null
      ? {
          userId: Number(row.user_id),
          email: row.login_email || '',
          role: row.login_role || '',
          isActive: Number(row.login_is_active || 0) === 1,
          // The simple 4-digit staff login code (from DOB, adjusted on clash).
          loginCode: row.login_mobile_pin || '',
        }
      : null,
  };
}

// Re-fetch an employee joined to its linked login account (for DTOs that need
// the unified People shape after a write).
async function getEmployeeWithLogin(id) {
  return get(
    `SELECT e.*, u.email AS login_email, u.role AS login_role,
            u.is_active AS login_is_active, u.mobile_pin AS login_mobile_pin
       FROM employees e LEFT JOIN users u ON u.id = e.user_id
      WHERE e.id = ?`,
    [id],
  );
}

app.get('/api/departments', requirePermission('config.read'), async (_req, res) => {
  try {
    const rows = await all('SELECT * FROM departments WHERE is_archived = 0 ORDER BY name ASC');
    res.json({ success: true, departments: rows.map(rowToDepartmentDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, departments: [], error: error.message });
  }
});

app.get('/api/freelancer-jobs', requirePermission('config.read'), async (req, res) => {
  try {
    const jobs = await all('SELECT * FROM freelancer_jobs');
    const tasks = await all('SELECT * FROM freelancer_job_tasks');
    const batches = await all('SELECT * FROM freelancer_job_batches');
    res.json({ success: true, jobs, tasks, batches });
  } catch (error) {
    res.status(500).json({ success: false, jobs: [], error: error.message });
  }
});

app.post('/api/freelancer-jobs/batches', requirePermission('config.write'), async (req, res) => {
  try {
    const { freelancer_id, job_ids } = req.body;
    const batch_number = 'BATCH-' + Date.now();
    const result = await run(
      'INSERT INTO freelancer_job_batches (freelancer_id, batch_number, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      [freelancer_id, batch_number, 'assigned', new Date().toISOString(), new Date().toISOString()]
    );
    const batch_id = result.lastID;
    
    for (const jid of job_ids) {
      await run('UPDATE freelancer_jobs SET batch_id = ?, updated_at = ? WHERE id = ?', [batch_id, new Date().toISOString(), jid]);
    }
    
    const batch = await get('SELECT * FROM freelancer_job_batches WHERE id = ?', [batch_id]);
    res.json({ success: true, batch });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/freelancer-jobs', requirePermission('config.write'), async (req, res) => {
  try {
    const { item_id, quantity } = req.body;
    const result = await run(
      `INSERT INTO freelancer_jobs (batch_id, item_id, variation_leaf_node_id, quantity, status, payout_balance, created_at, updated_at)
       VALUES (NULL, ?, 0, ?, 'pending', 0, ?, ?)`,
      [item_id, quantity, new Date().toISOString(), new Date().toISOString()]
    );
    const newJobId = result.lastID;

    const bomLines = await all('SELECT * FROM item_bom_lines WHERE item_id = ?', [item_id]);
    for (const line of bomLines) {
       const mat = await get('SELECT linked_item_id, linked_variation_leaf_node_id FROM materials WHERE barcode = ?', [line.material_barcode]);
       if (mat && mat.linked_item_id) {
         const reqQty = (line.quantity_per_unit * quantity) * (1 + (line.wastage_percent / 100));
         await run(
           `INSERT INTO freelancer_job_tasks (job_id, item_id, variation_leaf_node_id, required_quantity, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, 'pending', ?, ?)`,
           [newJobId, mat.linked_item_id, mat.linked_variation_leaf_node_id || 0, reqQty, new Date().toISOString(), new Date().toISOString()]
         );
       }
    }
    
    const job = await get('SELECT * FROM freelancer_jobs WHERE id = ?', [newJobId]);
    res.json({ success: true, job });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.put('/api/freelancer-jobs/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const { status } = req.body;
    await run(
      'UPDATE freelancer_jobs SET status = ?, updated_at = ? WHERE id = ?',
      [status, new Date().toISOString(), req.params.id]
    );
    const updated = await get('SELECT * FROM freelancer_jobs WHERE id = ?', [req.params.id]);
    res.json({ success: true, job: updated });
  } catch (error) {
    res.status(500).json({ success: false, job: null, error: error.message });
  }
});

app.delete('/api/freelancer-jobs/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = req.params.id;
    await run('BEGIN TRANSACTION');
    await run('DELETE FROM freelancer_job_tasks WHERE job_id = ?', [id]);
    await run('DELETE FROM freelancer_jobs WHERE id = ?', [id]);
    await run('COMMIT');
    res.json({ success: true, error: null });
  } catch (error) {
    await run('ROLLBACK');
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/freelancer-portal/data', async (req, res) => {
  try {
    const token = req.query.token;
    if (!token) return res.status(400).json({ success: false, error: 'Missing token' });
    
    const crypto = require('crypto');
    const SECRET = 'my-very-secret-key-32charslong!!'; 
    let barcode_id;
    try {
      const parts = token.split(':');
      const iv = Buffer.from(parts[0], 'hex');
      const encryptedText = Buffer.from(parts[1], 'hex');
      const decipher = crypto.createDecipheriv('aes-256-cbc', Buffer.from(SECRET), iv);
      let decrypted = decipher.update(encryptedText);
      decrypted = Buffer.concat([decrypted, decipher.final()]);
      barcode_id = decrypted.toString();
    } catch (e) {
      return res.status(400).json({ success: false, error: 'Invalid or tampered token' });
    }

    const employee = await get('SELECT id FROM employees WHERE barcode_id = ?', [barcode_id]);
    if (!employee) return res.status(404).json({ success: false, error: 'Freelancer not found' });
    
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const isoDate = thirtyDaysAgo.toISOString();

    const batches = await all('SELECT * FROM freelancer_job_batches WHERE freelancer_id = ? AND created_at >= ?', [employee.id, isoDate]);
    const batchIds = batches.map(b => b.id);
    let jobs = [];
    let tasks = [];
    if (batchIds.length > 0) {
      jobs = await all(`SELECT * FROM freelancer_jobs WHERE batch_id IN (${batchIds.join(',')})`);
      const jobIds = jobs.map(j => j.id);
      if (jobIds.length > 0) {
        tasks = await all(`SELECT * FROM freelancer_job_tasks WHERE job_id IN (${jobIds.join(',')})`);
      }
    }
    
    res.json({ success: true, batches, jobs, tasks });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/departments', requirePermission('config.write'), async (req, res) => {
  try {
    const { name, description = '', photoUrl = '' } = req.body;
    if (!name || name.trim() === '') {
      return res.status(400).json({ success: false, error: 'Name is required' });
    }
    const now = new Date().toISOString();
    const result = await run(
      'INSERT INTO departments (name, description, photo_url, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      [name.trim(), description.trim(), photoUrl, now, now]
    );
    const row = await get('SELECT * FROM departments WHERE id = ?', [result.lastID]);
    res.status(201).json({ success: true, department: rowToDepartmentDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.patch('/api/departments/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { name, description, photoUrl } = req.body;
    const existing = await get('SELECT * FROM departments WHERE id = ?', [id]);
    if (!existing) {
      return res.status(404).json({ success: false, error: 'Department not found' });
    }
    const newName = name !== undefined ? name.trim() : existing.name;
    const newDesc = description !== undefined ? description.trim() : existing.description;
    const newPhoto = photoUrl !== undefined ? photoUrl : existing.photo_url;
    
    await run(
      'UPDATE departments SET name = ?, description = ?, photo_url = ?, updated_at = ? WHERE id = ?',
      [newName, newDesc, newPhoto, new Date().toISOString(), id]
    );
    const row = await get('SELECT * FROM departments WHERE id = ?', [id]);
    res.json({ success: true, department: rowToDepartmentDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/departments/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    // Employees are owned by their department (employees.department_id is NOT NULL),
    // so cascade-trash them before removing the department. Cross-entity references
    // (e.g. an order that names a deleted client) are intentionally left for the
    // Action Center to surface rather than cascade-deleted.
    const employeeIds = (await all('SELECT id FROM employees WHERE department_id = ?', [id])).map((r) => r.id);
    await trashAndDeleteMany('employees', employeeIds, req);
    await trashAndDelete('departments', id, req);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/employees', requirePermission('config.read'), async (_req, res) => {
  try {
    // Unified People read: each employee joined to its login account (if any).
    const rows = await all(
      `SELECT e.*,
              u.email AS login_email,
              u.role AS login_role,
              u.is_active AS login_is_active,
              u.mobile_pin AS login_mobile_pin
         FROM employees e
         LEFT JOIN users u ON u.id = e.user_id
        WHERE e.is_archived = 0
        ORDER BY e.name ASC`,
    );
    res.json({ success: true, employees: rows.map(rowToEmployeeDto), error: null });
  } catch (error) {
    res.status(500).json({ success: false, employees: [], error: error.message });
  }
});

app.post('/api/employees', requirePermission('config.write'), async (req, res) => {
  try {
    const { departmentId, name, role = '', phone = '', aadharNumber = '', aadharPhotoUrl = '', panNumber = '', panPhotoUrl = '', address = '', employeePhotoUrl = '', employmentType = 'in-house', status = 'active', barcodeId = '', email = '', dateOfBirth = '' } = req.body;
    if (!name || !departmentId) {
      return res.status(400).json({ success: false, error: 'Name and departmentId are required' });
    }
    const now = new Date().toISOString();
    const result = await run(
      'INSERT INTO employees (department_id, name, role, phone, aadhar_number, aadhar_photo_url, pan_number, pan_photo_url, address, employee_photo_url, employment_type, status, barcode_id, email, date_of_birth, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [departmentId, name.trim(), role.trim(), phone.trim(), aadharNumber.trim(), aadharPhotoUrl, panNumber.trim(), panPhotoUrl, address.trim(), employeePhotoUrl, employmentType, status, barcodeId.trim(), String(email || '').trim(), String(dateOfBirth || '').trim(), now, now]
    );
    const row = await getEmployeeWithLogin(result.lastID);
    trackCreate('employees', result.lastID, row, req);
    res.status(201).json({ success: true, employee: rowToEmployeeDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.patch('/api/employees/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { name, role, phone, aadharNumber, aadharPhotoUrl, panNumber, panPhotoUrl, address, employeePhotoUrl, employmentType, status, departmentId, barcodeId, email, dateOfBirth } = req.body;
    const existing = await get('SELECT * FROM employees WHERE id = ?', [id]);
    if (!existing) {
      return res.status(404).json({ success: false, error: 'Employee not found' });
    }
    const newEmail = email !== undefined ? String(email || '').trim() : (existing.email || '');
    const newDob = dateOfBirth !== undefined ? String(dateOfBirth || '').trim() : (existing.date_of_birth || '');
    const newName = name !== undefined ? name.trim() : existing.name;
    const newRole = role !== undefined ? role.trim() : existing.role;
    const newPhone = phone !== undefined ? phone.trim() : existing.phone;
    const newAadhar = aadharNumber !== undefined ? aadharNumber.trim() : existing.aadhar_number;
    const newAadharPhoto = aadharPhotoUrl !== undefined ? aadharPhotoUrl : existing.aadhar_photo_url;
    const newPan = panNumber !== undefined ? panNumber.trim() : existing.pan_number;
    const newPanPhoto = panPhotoUrl !== undefined ? panPhotoUrl : existing.pan_photo_url;
    const newAddress = address !== undefined ? address.trim() : existing.address;
    const newEmployeePhoto = employeePhotoUrl !== undefined ? employeePhotoUrl : existing.employee_photo_url;
    const newEmpType = employmentType !== undefined ? employmentType : existing.employment_type;
    const newStatus = status !== undefined ? status : existing.status;
    const newDep = departmentId !== undefined ? departmentId : existing.department_id;
    const newBarcodeId = barcodeId !== undefined ? barcodeId.trim() : existing.barcode_id;

    await run(
      'UPDATE employees SET name = ?, role = ?, phone = ?, aadhar_number = ?, aadhar_photo_url = ?, pan_number = ?, pan_photo_url = ?, address = ?, employee_photo_url = ?, employment_type = ?, status = ?, department_id = ?, barcode_id = ?, email = ?, date_of_birth = ?, updated_at = ? WHERE id = ?',
      [newName, newRole, newPhone, newAadhar, newAadharPhoto, newPan, newPanPhoto, newAddress, newEmployeePhoto, newEmpType, newStatus, newDep, newBarcodeId, newEmail, newDob, new Date().toISOString(), id]
    );
    // Keep the staff login code in sync with DOB: if the birth date changed and
    // this employee has a linked login, re-derive their DDMM code (next free).
    if (existing.user_id && newDob !== (existing.date_of_birth || '')) {
      const dobPin = deriveDobPin(newDob);
      if (dobPin) {
        const pin = await nextFreeMobilePin(dobPin, existing.user_id);
        await run('UPDATE users SET mobile_pin = ?, updated_at = ? WHERE id = ?', [pin, new Date().toISOString(), existing.user_id]);
      }
    }
    const afterRow = await get('SELECT * FROM employees WHERE id = ?', [id]);
    trackUpdate('employees', id, existing, afterRow, req);
    const row = await getEmployeeWithLogin(id);
    res.json({ success: true, employee: rowToEmployeeDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/employees/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const before = await get('SELECT * FROM employees WHERE id = ?', [id]);
    await trashAndDelete('employees', id, req);
    trackDelete('employees', id, before, req);
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ---- Unified People: connect an in-house employee to a login/profile ---------

// Create a brand-new login account for an in-house employee and link it.
app.post(
  '/api/employees/:id/create-login',
  requireRoles('super_admin', 'admin'),
  requirePermission('users.create_user'),
  async (req, res) => {
    try {
      const id = Number(req.params.id);
      const emp = await get('SELECT * FROM employees WHERE id = ?', [id]);
      if (!emp) return res.status(404).json({ success: false, error: 'Employee not found.' });
      if ((emp.employment_type || 'in-house') !== 'in-house') {
        return res.status(400).json({ success: false, error: 'Only in-house employees can be given a login.' });
      }
      if (emp.user_id) {
        return res.status(409).json({ success: false, error: 'This employee already has a linked login.' });
      }
      const email = String(req.body?.email || emp.email || '').trim();
      if (!email) return res.status(400).json({ success: false, error: 'An email is required to create a login.' });
      const password = String(req.body?.password || '');
      // Employee logins default to the 'user' (staff) role. Elevating to 'admin'
      // requires the admin-creation permission; super_admin cannot be created here.
      let role = String(req.body?.role || 'user').trim();
      if (role === 'super_admin') {
        return res.status(403).json({ success: false, error: 'Cannot create a super admin from an employee.' });
      }
      if (role === 'admin' && req.user.role !== 'super_admin') {
        return res.status(403).json({ success: false, error: 'Only a super admin can grant admin access.' });
      }
      if (role !== 'admin') role = 'user';

      const user = await createUserAccount({
        name: emp.name,
        email,
        password,
        role,
        createdByUserId: req.user.id,
      });
      await run('UPDATE employees SET user_id = ?, email = ?, updated_at = ? WHERE id = ?', [
        user.id, email, new Date().toISOString(), id,
      ]);
      // Simple staff login: use the employee's DDMM (from DOB) as their 4-digit
      // code, or the next free code if that one is already taken.
      const dobPin = deriveDobPin(emp.date_of_birth);
      if (dobPin) {
        const pin = await nextFreeMobilePin(dobPin, user.id);
        await run('UPDATE users SET mobile_pin = ? WHERE id = ?', [pin, user.id]);
      }
      await logAuthEvent({
        eventType: 'user_created',
        actorUserId: req.user.id,
        targetUserId: user.id,
        ipAddress: getRequestIp(req),
        userAgent: getRequestUserAgent(req),
        metadata: { role, viaEmployee: id },
      });
      const row = await getEmployeeWithLogin(id);
      res.status(201).json({ success: true, employee: rowToEmployeeDto(row), error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, error: error.message });
    }
  },
);

// Link an in-house employee to an EXISTING login account.
app.post(
  '/api/employees/:id/link-login',
  requireRoles('super_admin', 'admin'),
  requirePermission('config.write'),
  async (req, res) => {
    try {
      const id = Number(req.params.id);
      const userId = Number(req.body?.userId);
      const emp = await get('SELECT * FROM employees WHERE id = ?', [id]);
      if (!emp) return res.status(404).json({ success: false, error: 'Employee not found.' });
      if ((emp.employment_type || 'in-house') !== 'in-house') {
        return res.status(400).json({ success: false, error: 'Only in-house employees can be linked to a login.' });
      }
      if (!Number.isFinite(userId)) return res.status(400).json({ success: false, error: 'userId is required.' });
      const user = await get('SELECT id FROM users WHERE id = ?', [userId]);
      if (!user) return res.status(404).json({ success: false, error: 'Login account not found.' });
      const other = await get('SELECT id FROM employees WHERE user_id = ? AND id != ?', [userId, id]);
      if (other) return res.status(409).json({ success: false, error: 'That login is already linked to another employee.' });

      await run('UPDATE employees SET user_id = ?, updated_at = ? WHERE id = ?', [userId, new Date().toISOString(), id]);
      const row = await getEmployeeWithLogin(id);
      res.json({ success: true, employee: rowToEmployeeDto(row), error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, error: error.message });
    }
  },
);

// Unlink an employee from its login (the login account itself is kept).
app.post(
  '/api/employees/:id/unlink-login',
  requireRoles('super_admin', 'admin'),
  requirePermission('config.write'),
  async (req, res) => {
    try {
      const id = Number(req.params.id);
      const emp = await get('SELECT * FROM employees WHERE id = ?', [id]);
      if (!emp) return res.status(404).json({ success: false, error: 'Employee not found.' });
      await run('UPDATE employees SET user_id = NULL, updated_at = ? WHERE id = ?', [new Date().toISOString(), id]);
      const row = await getEmployeeWithLogin(id);
      res.json({ success: true, employee: rowToEmployeeDto(row), error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, error: error.message });
    }
  },
);

app.post('/api/mobile/stage-item', requireAuth, async (req, res) => {
  try {
    if (io) io.emit('item_staged', req.body);
    changeEmitter.emit('custom-event', { event: 'item_staged', data: req.body });
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/mobile/remove-staged-item', requireAuth, async (req, res) => {
  try {
    if (io) io.emit('item_removed', req.body);
    changeEmitter.emit('custom-event', { event: 'item_removed', data: req.body });
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/mobile/lock-inventory', requireAuth, async (req, res) => {
  try {
    if (io) io.emit('inventory_locked', req.body);
    changeEmitter.emit('custom-event', { event: 'inventory_locked', data: req.body });
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/mobile/challan-generated', requireAuth, async (req, res) => {
  try {
    if (io) io.emit('challan_generated_ok', req.body);
    changeEmitter.emit('custom-event', { event: 'challan_generated_ok', data: req.body });
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ==========================================
// PAYROLL APIs
// ==========================================

app.get('/api/payroll/components', requirePermission('config.read'), async (req, res) => {
  try {
    const components = await all('SELECT * FROM payroll_components ORDER BY name ASC');
    res.json({ success: true, components });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/payroll/components', requirePermission('config.write'), async (req, res) => {
  try {
    const { name, type, calculation_method, is_statutory, config_json } = req.body;
    if (!name || !type || !calculation_method) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }
    
    const result = await run(`
      INSERT INTO payroll_components (name, type, calculation_method, is_statutory, config_json)
      VALUES (?, ?, ?, ?, ?)
    `, [name, type, calculation_method, is_statutory ? 1 : 0, config_json || '{}']);
    
    res.json({ success: true, id: result.lastID });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/payroll/employees/:id/salary-structure', requirePermission('config.read'), async (req, res) => {
  try {
    const userId = Number(req.params.id);
    const structure = await get('SELECT * FROM employee_salary_structures WHERE user_id = ?', [userId]);
    if (!structure) {
      return res.json({ success: true, structure: null, lines: [] });
    }
    const lines = await all('SELECT * FROM employee_salary_structure_lines WHERE structure_id = ?', [structure.id]);
    res.json({ success: true, structure, lines });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.put('/api/payroll/employees/:id/salary-structure', requirePermission('config.write'), async (req, res) => {
  try {
    const userId = Number(req.params.id);
    const { base_salary, effective_date, lines } = req.body;
    
    await run('BEGIN TRANSACTION');
    let structure = await get('SELECT * FROM employee_salary_structures WHERE user_id = ?', [userId]);
    if (structure) {
      await run('UPDATE employee_salary_structures SET effective_from = ? WHERE id = ?', 
        [effective_date, structure.id]);
    } else {
      const resStruct = await run('INSERT INTO employee_salary_structures (user_id, effective_from) VALUES (?, ?)',
        [userId, effective_date]);
      structure = { id: resStruct.lastID };
    }
    
    await run('DELETE FROM employee_salary_structure_lines WHERE structure_id = ?', [structure.id]);
    if (lines && lines.length > 0) {
      for (const line of lines) {
        await run(`
          INSERT INTO employee_salary_structure_lines (structure_id, component_id, amount_or_formula, sequence)
          VALUES (?, ?, ?, ?)
        `, [structure.id, line.component_id, line.amount_or_formula, 1]);
      }
    }
    
    await run('COMMIT');
    res.json({ success: true });
  } catch (error) {
    await run('ROLLBACK').catch(() => {});
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/payroll/runs', requirePermission('config.read'), async (req, res) => {
  try {
    const runs = await all('SELECT * FROM payroll_runs ORDER BY created_at DESC');
    res.json({ success: true, runs });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/payroll/runs', requirePermission('config.write'), async (req, res) => {
  try {
    const { period_start, period_end, remarks } = req.body;
    if (!period_start || !period_end) {
      return res.status(400).json({ success: false, error: 'Missing period start/end' });
    }
    const result = await run(`
      INSERT INTO payroll_runs (period_start, period_end, status, total_gross, total_net, created_by, remarks, created_at, updated_at)
      VALUES (?, ?, 'draft', 0, 0, ?, ?, ?, ?)
    `, [period_start, period_end, req.user?.id || null, remarks || '', new Date().toISOString(), new Date().toISOString()]);
    
    res.json({ success: true, id: result.lastID });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/payroll/runs/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const runId = Number(req.params.id);
    const payrollRun = await get('SELECT * FROM payroll_runs WHERE id = ?', [runId]);
    if (!payrollRun) return res.status(404).json({ success: false, error: 'Not found' });
    
    const details = await all('SELECT * FROM payroll_run_details WHERE run_id = ?', [runId]);
    res.json({ success: true, run: payrollRun, details });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/payroll/runs/:id/finalize', requirePermission('config.write'), async (req, res) => {
  try {
    const runId = Number(req.params.id);
    await run('UPDATE payroll_runs SET status = "finalized", updated_at = ? WHERE id = ?', [new Date().toISOString(), runId]);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/payroll/runs/:id/summary', requirePermission('config.read'), async (req, res) => {
  try {
    const runId = Number(req.params.id);
    const payrollRun = await get('SELECT * FROM payroll_runs WHERE id = ?', [runId]);
    if (!payrollRun) return res.status(404).send('Not found');
    
    const details = await all('SELECT * FROM payroll_run_details WHERE run_id = ?', [runId]);
    
    let csv = 'Employee ID,Gross Pay,Deductions,Net Pay\\n';
    details.forEach(d => {
      csv += `${d.user_id},${d.gross_pay},${d.deductions},${d.net_pay}\\n`;
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="payroll_summary_' + runId + '.csv"');
    res.send(csv);
  } catch (error) {
    res.status(500).send('Error generating summary');
  }
});

// ==========================================
// B2B PORTAL APIs
// ==========================================

app.post('/api/clients/:id/portal-credentials', async (req, res) => {
  try {
    const clientId = req.params.id;
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ success: false, error: 'Email and password required' });
    }
    const hash = password; // Should hash password in production
    
    // UPSERT portal_users for this client
    const existing = await get('SELECT id FROM portal_users WHERE client_id = ?', [clientId]);
    if (existing) {
      await run('UPDATE portal_users SET email = ?, password_hash = ? WHERE client_id = ?', [email, hash, clientId]);
    } else {
      await run('INSERT INTO portal_users (client_id, email, password_hash) VALUES (?, ?, ?)', [clientId, email, hash]);
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get('/api/clients/:id/portal-catalog', async (req, res) => {
  try {
    const rows = await all('SELECT item_id FROM client_portal_catalog WHERE client_id = ?', [req.params.id]);
    res.json({ success: true, itemIds: rows.map(r => r.item_id) });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/clients/:id/portal-catalog', async (req, res) => {
  try {
    const clientId = req.params.id;
    const { itemIds } = req.body; // Array of item IDs
    
    await run('BEGIN TRANSACTION');
    await run('DELETE FROM client_portal_catalog WHERE client_id = ?', [clientId]);
    
    for (const itemId of itemIds) {
      await run('INSERT INTO client_portal_catalog (client_id, item_id) VALUES (?, ?)', [clientId, itemId]);
    }
    
    await run('COMMIT');
    res.json({ success: true });
  } catch (err) {
    await run('ROLLBACK');
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/portal/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    // Check real portal users first
    const user = await get('SELECT * FROM portal_users WHERE email = ? AND is_active = 1', [email]);
    if (user && user.password_hash === password) { // simple string match for now
      return res.json({ 
        success: true, 
        user: { 
          id: user.id, 
          email: user.email,
          client_id: user.client_id 
        } 
      });
    }

    // Fallback to mock
    if (email === 'test@example.com' && password === 'password') {
      return res.json({ success: true, user: { id: 1, name: 'Test Client User', client_id: 1 } });
    }
    return res.status(401).json({ success: false, error: 'Invalid credentials' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/portal/catalog', async (req, res) => {
  try {
    const clientId = req.query.client_id;
    if (!clientId) {
      return res.status(400).json({ success: false, error: 'client_id query parameter is required' });
    }
    
    // Only return items that aren't archived AND are in the client_portal_catalog
    const items = await all(`
      SELECT i.id, i.name, i.display_name, i.alias, i.quantity, i.naming_format 
      FROM items i
      JOIN client_portal_catalog cpc ON i.id = cpc.item_id
      WHERE i.is_archived = 0 AND cpc.client_id = ?
      ORDER BY i.display_name ASC
    `, [clientId]);
    
    res.json({ success: true, items });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/portal/cart', async (req, res) => {
  try {
    const { portal_user_id, item_id, quantity } = req.body;
    if (!portal_user_id || !item_id) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }
    
    const existing = await get('SELECT * FROM portal_carts WHERE portal_user_id = ? AND item_id = ?', [portal_user_id, item_id]);
    if (existing) {
      await run('UPDATE portal_carts SET quantity = quantity + ? WHERE id = ?', [quantity, existing.id]);
    } else {
      await run('INSERT INTO portal_carts (portal_user_id, item_id, quantity) VALUES (?, ?, ?)', 
        [portal_user_id, item_id, quantity]);
    }
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/portal/orders', async (req, res) => {
  try {
    const { portal_user_id, items, notes } = req.body;
    if (!portal_user_id || !items || !items.length) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }
    
    const pUser = await get('SELECT * FROM portal_users WHERE id = ?', [portal_user_id]);
    if (!pUser) return res.status(404).json({ success: false, error: 'Portal user not found' });
    
    await run('BEGIN TRANSACTION');
    
    const orderNo = 'B2B-ORD-' + Date.now();
    
    // Create header
    await run('INSERT INTO order_headers (order_no, client_id, created_at, updated_at) VALUES (?, ?, ?, ?)', 
      [orderNo, pUser.client_id, new Date().toISOString(), new Date().toISOString()]);
      
    // Save items
    for (const item of items) {
      await saveOrder({
        orderNo,
        clientId: pUser.client_id,
        itemId: item.item_id,
        quantity: item.quantity,
        status: 'draft',
        createdByPortalUserId: portal_user_id,
      }, { returnMeta: false });
    }
    
    // Clear cart
    await run('DELETE FROM portal_carts WHERE portal_user_id = ?', [portal_user_id]);
    
    await run('COMMIT');
    res.json({ success: true, orderNo });
  } catch (error) {
    await run('ROLLBACK').catch(() => {});
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/delete-s3-object', requirePermission('config.write'), async (req, res) => {
  try {
    const { url } = req.body;
    if (!url) return res.status(400).json({ success: false, error: 'URL is required' });
    try {
      const parsedUrl = new URL(url);
      const objectKey = parsedUrl.pathname.substring(1);
      const s3Client = getS3Client();
      await s3Client.send(new DeleteObjectCommand({
        Bucket: process.env.S3_BUCKET,
        Key: objectKey,
      }));
      // Update db status to deleted just in case
      await run("UPDATE uploaded_assets SET status = 'deleted' WHERE object_key = ?", [objectKey]);
      res.json({ success: true, error: null });
    } catch (e) {
      res.status(500).json({ success: false, error: 'Failed to delete S3 object: ' + e.message });
    }
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

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

let io = null;
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

      // Initialize Socket.io
      io = new Server(server, {
        cors: buildCorsOptions()
      });
      
      io.on('connection', (socket) => {
        console.log(`Socket connected: ${socket.id}`);
        
        // Mobile staging workflow events
        socket.on('stage_item', (data) => {
          console.log(`Item staged by mobile (WS):`, data);
          socket.broadcast.emit('item_staged', data);
        });

        socket.on('remove_staged_item', (data) => {
          socket.broadcast.emit('item_removed', data);
        });
        
        socket.on('lock_inventory', (data) => {
          socket.broadcast.emit('inventory_locked', data);
        });
        
        socket.on('challan_generated', (data) => {
          socket.broadcast.emit('challan_generated_ok', data);
        });

        socket.on('disconnect', () => {
          console.log(`Socket disconnected: ${socket.id}`);
        });
      });

      try {
        console.log('Running migrations...');
        await runMigrations();
        console.log('Initializing database schema...');
        await initDb();
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
  return {
    deploymentId: DEPLOYMENT_ID,
    deploymentName: DEPLOYMENT_NAME,
    appVersion: process.env.APP_VERSION || '',
    capturedAt: new Date().toISOString(),
    metrics,
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

// ─── TRASH BIN ───────────────────────────────────────────────────────────────
// Tables whose rows can be recovered from the trash. Kept explicit so a
// client-supplied tableName can never be interpolated into SQL unchecked.
const RESTORABLE_TABLES = new Set([
  'clients', 'vendors', 'units', 'items', 'groups', 'departments', 'employees',
  'item_variations', 'item_variation_nodes', 'item_unit_conversions', 'uploaded_assets',
]);

// GET /api/trash — list trashed records (most recent first), optionally filtered by table.
app.get('/api/trash', requirePermission('config.read'), async (req, res) => {
  try {
    const { tableName } = req.query;
    const params = [];
    let where = '';
    if (tableName) {
      where = 'WHERE table_name = ?';
      params.push(String(tableName));
    }
    const rows = await all(
      `SELECT id, table_name, record_id, data_json, deleted_at, deleted_by
       FROM deleted_records ${where} ORDER BY id DESC LIMIT 500`,
      params
    );
    const records = rows.map((r) => {
      let data = null;
      try {
        data = JSON.parse(r.data_json);
      } catch (_) {
        data = null;
      }
      return {
        id: r.id,
        tableName: r.table_name,
        recordId: r.record_id,
        deletedAt: r.deleted_at,
        deletedBy: r.deleted_by,
        label: (data && (data.display_name || data.name || data.challan_no)) || `${r.table_name} #${r.record_id}`,
        data,
      };
    });
    res.json({ success: true, records, total: records.length, error: null });
  } catch (error) {
    res.status(500).json({ success: false, records: [], total: 0, error: error.message });
  }
});

// POST /api/trash/restore — re-insert a trashed row (original id preserved) and
// remove it from the trash. Uses a plain INSERT (never OR REPLACE) so a live row
// is never silently clobbered; FK checks are skipped so a row can be restored even
// if some of its own references are still missing (those resurface in Action Center).
app.post('/api/trash/restore', requirePermission('config.write'), async (req, res) => {
  try {
    const tableName = String(req.body?.tableName || '');
    const recordId = Number(req.body?.recordId);
    if (!tableName || !Number.isFinite(recordId)) {
      return res.status(400).json({ success: false, error: 'tableName and recordId are required.' });
    }
    if (!RESTORABLE_TABLES.has(tableName)) {
      return res.status(400).json({ success: false, error: `Table "${tableName}" is not restorable.` });
    }

    const rec = await get(
      `SELECT * FROM deleted_records WHERE table_name = ? AND record_id = ? ORDER BY id DESC LIMIT 1`,
      [tableName, recordId]
    );
    if (!rec) {
      return res.status(404).json({ success: false, error: 'No trashed record found for that table and id.' });
    }

    // Never clobber a live row that already occupies this id.
    const live = await get(`SELECT id FROM ${tableName} WHERE id = ?`, [recordId]);
    if (live) {
      return res.status(409).json({ success: false, error: `A live ${tableName} record with id ${recordId} already exists.` });
    }

    let data;
    try {
      data = JSON.parse(rec.data_json);
    } catch (_) {
      return res.status(422).json({ success: false, error: 'Trashed record data is corrupt and cannot be restored.' });
    }
    const cols = Object.keys(data || {});
    if (cols.length === 0) {
      return res.status(422).json({ success: false, error: 'Trashed record has no columns to restore.' });
    }
    const colList = cols.map((c) => `"${c}"`).join(', ');
    const placeholders = cols.map(() => '?').join(', ');
    const values = cols.map((c) => data[c]);

    // Insert on the dedicated FK-off connection so a row can be restored even
    // while some of its own references are still missing (they resurface in the
    // Action Center) without touching FK enforcement on the main connection.
    try {
      await runOnDelete(`INSERT INTO ${tableName} (${colList}) VALUES (${placeholders})`, values);
    } catch (insertErr) {
      const msg = String((insertErr && insertErr.message) || insertErr);
      // Turn the common recoverable failures into clean 4xx responses instead of
      // a raw 500: a non-PK UNIQUE collision, or a column that no longer exists
      // because a migration changed the table since the row was trashed.
      if (/UNIQUE constraint/i.test(msg)) {
        return res.status(409).json({ success: false, error: `Cannot restore: it conflicts with an existing record. (${msg})` });
      }
      if (/no column named|has no column/i.test(msg)) {
        return res.status(422).json({ success: false, error: `Cannot restore: this table's structure changed since the record was deleted. (${msg})` });
      }
      return res.status(422).json({ success: false, error: `Restore failed: ${msg}` });
    }

    // Remove every trash entry for this record (there may be more than one).
    await run(`DELETE FROM deleted_records WHERE table_name = ? AND record_id = ?`, [tableName, recordId]);

    await logChange(tableName, recordId, 'INSERT');

    res.json({ success: true, restored: { tableName, recordId }, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─── ACTION CENTER ─────────────────────────────────────────────────────────────
// Scans for broken foreign-key references caused by hard-deletes and returns a
// structured list of issues the user can resolve.
app.get('/api/action-center/issues', requirePermission('config.read'), async (req, res) => {
  const issues = [];
  const scanErrors = [];

  // ownerTable/ownerId → the record holding the dangling reference (drives "Resolve").
  // brokenTable/brokenId → the missing target row (drives "Revert" = restore from trash).
  function addIssue({ severity, ownerTable, ownerId, ownerLabel, brokenTable, brokenField, brokenId, brokenLabel }) {
    issues.push({
      type: 'broken_reference',
      severity,
      ownerTable,
      ownerId,
      ownerLabel,
      brokenTable,
      brokenField,
      brokenId,
      brokenLabel,
    });
  }

  // Each scan runs in isolation so one failing query (e.g. a table absent on an
  // older DB) records an error but never aborts the remaining scans.
  async function scan(label, fn) {
    try {
      await fn();
    } catch (err) {
      scanErrors.push({ scan: label, error: err.message });
      console.error(`[ActionCenter] scan "${label}" failed:`, err.message);
    }
  }

  // Items → groups
  await scan('items.group_id', async () => {
    const rows = await all(`SELECT i.id, i.name, i.display_name, i.group_id FROM items i LEFT JOIN groups g ON g.id = i.group_id WHERE i.group_id IS NOT NULL AND g.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'error', ownerTable: 'items', ownerId: r.id, ownerLabel: r.display_name || r.name || `Item #${r.id}`, brokenTable: 'groups', brokenField: 'group_id', brokenId: r.group_id, brokenLabel: `Group #${r.group_id}` });
  });

  // Items → units
  await scan('items.unit_id', async () => {
    const rows = await all(`SELECT i.id, i.name, i.display_name, i.unit_id FROM items i LEFT JOIN units u ON u.id = i.unit_id WHERE i.unit_id IS NOT NULL AND u.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'error', ownerTable: 'items', ownerId: r.id, ownerLabel: r.display_name || r.name || `Item #${r.id}`, brokenTable: 'units', brokenField: 'unit_id', brokenId: r.unit_id, brokenLabel: `Unit #${r.unit_id}` });
  });

  // Groups → parent group
  await scan('groups.parent_group_id', async () => {
    const rows = await all(`SELECT g.id, g.name, g.parent_group_id FROM groups g LEFT JOIN groups p ON p.id = g.parent_group_id WHERE g.parent_group_id IS NOT NULL AND p.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'warning', ownerTable: 'groups', ownerId: r.id, ownerLabel: r.name || `Group #${r.id}`, brokenTable: 'groups', brokenField: 'parent_group_id', brokenId: r.parent_group_id, brokenLabel: `Group #${r.parent_group_id}` });
  });

  // Groups → units
  await scan('groups.unit_id', async () => {
    const rows = await all(`SELECT g.id, g.name, g.unit_id FROM groups g LEFT JOIN units u ON u.id = g.unit_id WHERE g.unit_id IS NOT NULL AND u.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'warning', ownerTable: 'groups', ownerId: r.id, ownerLabel: r.name || `Group #${r.id}`, brokenTable: 'units', brokenField: 'unit_id', brokenId: r.unit_id, brokenLabel: `Unit #${r.unit_id}` });
  });

  // Order lines → client
  await scan('order_items.client_id', async () => {
    const rows = await all(`SELECT oi.id, oi.order_no, oi.client_id FROM order_items oi LEFT JOIN clients c ON c.id = oi.client_id WHERE oi.client_id IS NOT NULL AND c.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'error', ownerTable: 'order_items', ownerId: r.id, ownerLabel: `Order ${r.order_no || '#' + r.id}`, brokenTable: 'clients', brokenField: 'client_id', brokenId: r.client_id, brokenLabel: `Client #${r.client_id}` });
  });

  // Order lines → item
  await scan('order_items.item_id', async () => {
    const rows = await all(`SELECT oi.id, oi.order_no, oi.item_id FROM order_items oi LEFT JOIN items i ON i.id = oi.item_id WHERE oi.item_id IS NOT NULL AND i.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'error', ownerTable: 'order_items', ownerId: r.id, ownerLabel: `Order ${r.order_no || '#' + r.id}`, brokenTable: 'items', brokenField: 'item_id', brokenId: r.item_id, brokenLabel: `Item #${r.item_id}` });
  });

  // Order lines → sub-contractor
  await scan('order_items.sub_contractor_id', async () => {
    const rows = await all(`SELECT oi.id, oi.order_no, oi.sub_contractor_id FROM order_items oi LEFT JOIN sub_contractors s ON s.id = oi.sub_contractor_id WHERE oi.sub_contractor_id IS NOT NULL AND s.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'warning', ownerTable: 'order_items', ownerId: r.id, ownerLabel: `Order ${r.order_no || '#' + r.id}`, brokenTable: 'sub_contractors', brokenField: 'sub_contractor_id', brokenId: r.sub_contractor_id, brokenLabel: `Sub-contractor #${r.sub_contractor_id}` });
  });

  // Delivery challans → material-owner client
  await scan('delivery_challans.material_owner_client_id', async () => {
    const rows = await all(`SELECT dc.id, dc.challan_no, dc.material_owner_client_id FROM delivery_challans dc LEFT JOIN clients c ON c.id = dc.material_owner_client_id WHERE dc.material_owner_client_id IS NOT NULL AND c.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'error', ownerTable: 'delivery_challans', ownerId: r.id, ownerLabel: r.challan_no ? `Challan ${r.challan_no}` : `Challan #${r.id}`, brokenTable: 'clients', brokenField: 'material_owner_client_id', brokenId: r.material_owner_client_id, brokenLabel: `Client #${r.material_owner_client_id}` });
  });

  // Delivery challans → vendor
  await scan('delivery_challans.vendor_id', async () => {
    const rows = await all(`SELECT dc.id, dc.challan_no, dc.vendor_id FROM delivery_challans dc LEFT JOIN vendors v ON v.id = dc.vendor_id WHERE dc.vendor_id IS NOT NULL AND v.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'error', ownerTable: 'delivery_challans', ownerId: r.id, ownerLabel: r.challan_no ? `Challan ${r.challan_no}` : `Challan #${r.id}`, brokenTable: 'vendors', brokenField: 'vendor_id', brokenId: r.vendor_id, brokenLabel: `Vendor #${r.vendor_id}` });
  });

  // Inventory movements → item
  await scan('inventory_movements.item_id', async () => {
    const rows = await all(`SELECT m.id, m.item_id, m.movement_type FROM inventory_movements m LEFT JOIN items i ON i.id = m.item_id WHERE m.item_id IS NOT NULL AND i.id IS NULL`);
    for (const r of rows) addIssue({ severity: 'warning', ownerTable: 'inventory_movements', ownerId: r.id, ownerLabel: `${r.movement_type || 'Movement'} #${r.id}`, brokenTable: 'items', brokenField: 'item_id', brokenId: r.item_id, brokenLabel: `Item #${r.item_id}` });
  });

  res.json({ success: true, issues, total: issues.length, scanErrors, error: null });
});


module.exports = {
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
