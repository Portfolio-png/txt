const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();

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
const IS_PRODUCTION = process.env.NODE_ENV === 'production';
const JWT_SECRET = resolveJwtSecret();
const JWT_TTL_SECONDS = Number(process.env.PAPER_JWT_TTL_SECONDS || 60 * 60 * 12);
const PASSWORD_ITERATIONS = 120000;
const PASSWORD_KEY_LENGTH = 32;
const PASSWORD_POLICY_ERROR =
  'Use at least 10 characters with letters and numbers. Avoid names or common words.';
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
const USER_ROLES = new Set(['super_admin', 'admin', 'user']);
const PERMISSION_KEYS = [
  'inventory.read',
  'inventory.create',
  'inventory.update',
  'inventory.delete',
  'inventory.request_delete',
  'delete_requests.review',
  'users.read',
  'users.create_user',
  'users.create_admin',
  'users.update_status',
  'users.reset_password',
  'users.manage_permissions',
  'sessions.manage',
  'audit.read',
  'config.read',
  'config.write',
];
const PERMISSION_DESCRIPTORS = {
  'inventory.read': {
    label: 'View inventory',
    description: 'Read inventory records and detail pages.',
  },
  'inventory.create': {
    label: 'Create inventory',
    description: 'Create parent or child inventory records.',
  },
  'inventory.update': {
    label: 'Update inventory',
    description: 'Edit inventory records, links, scans, and movements.',
  },
  'inventory.delete': {
    label: 'Delete inventory',
    description: 'Delete inventory records directly.',
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
    label: 'View users',
    description: 'Read user directory and account summaries.',
  },
  'users.create_user': {
    label: 'Create users',
    description: 'Register user accounts.',
  },
  'users.create_admin': {
    label: 'Create admins',
    description: 'Register admin accounts.',
  },
  'users.update_status': {
    label: 'Update user status',
    description: 'Activate or deactivate user accounts.',
  },
  'users.reset_password': {
    label: 'Reset passwords',
    description: 'Reset passwords for managed accounts.',
  },
  'users.manage_permissions': {
    label: 'Manage permissions',
    description: 'Edit per-user permission overrides.',
  },
  'sessions.manage': {
    label: 'Manage sessions',
    description: 'View and revoke user sessions.',
  },
  'audit.read': {
    label: 'View security activity',
    description: 'Read authentication and security events.',
  },
  'config.read': {
    label: 'View configuration',
    description: 'Read units, clients, groups, items, orders, templates, and runs.',
  },
  'config.write': {
    label: 'Edit configuration',
    description: 'Create and edit units, clients, groups, items, orders, templates, and runs.',
  },
};
const DEFAULT_ROLE_PERMISSIONS = {
  super_admin: Object.fromEntries(PERMISSION_KEYS.map((key) => [key, true])),
  admin: {
    'inventory.read': true,
    'inventory.create': true,
    'inventory.update': true,
    'inventory.delete': true,
    'inventory.request_delete': true,
    'delete_requests.review': true,
    'users.read': true,
    'users.create_user': true,
    'users.create_admin': false,
    'users.update_status': true,
    'users.reset_password': true,
    'users.manage_permissions': false,
    'sessions.manage': true,
    'audit.read': true,
    'config.read': true,
    'config.write': true,
  },
  user: {
    'inventory.read': true,
    'inventory.create': false,
    'inventory.update': false,
    'inventory.delete': false,
    'inventory.request_delete': true,
    'delete_requests.review': false,
    'users.read': false,
    'users.create_user': false,
    'users.create_admin': false,
    'users.update_status': false,
    'users.reset_password': false,
    'users.manage_permissions': false,
    'sessions.manage': false,
    'audit.read': false,
    'config.read': true,
    'config.write': false,
  },
};
const DEFAULT_PERMISSION_TEMPLATES = [
  {
    name: 'Inventory Viewer',
    description: 'Can view inventory and basic configuration records.',
    permissions: {
      'inventory.read': true,
      'inventory.request_delete': false,
      'config.read': true,
    },
  },
  {
    name: 'Inventory Operator',
    description: 'Can work inventory records and request deletes.',
    permissions: {
      'inventory.read': true,
      'inventory.create': true,
      'inventory.update': true,
      'inventory.request_delete': true,
      'config.read': true,
    },
  },
  {
    name: 'Inventory Manager',
    description: 'Can run full inventory workflow including direct deletes and approvals.',
    permissions: {
      'inventory.read': true,
      'inventory.create': true,
      'inventory.update': true,
      'inventory.delete': true,
      'inventory.request_delete': true,
      'delete_requests.review': true,
      'config.read': true,
    },
  },
  {
    name: 'Configurator Manager',
    description: 'Can edit units, groups, clients, items, orders, templates, and runs.',
    permissions: {
      'config.read': true,
      'config.write': true,
      'inventory.read': true,
    },
  },
  {
    name: 'User Admin',
    description: 'Can manage user accounts, session controls, and permission overrides.',
    permissions: {
      'users.read': true,
      'users.create_user': true,
      'users.update_status': true,
      'users.reset_password': true,
      'users.manage_permissions': true,
      'sessions.manage': true,
      'audit.read': true,
    },
  },
  {
    name: 'Auditor',
    description: 'Can view and export security activity and delete requests.',
    permissions: {
      'audit.read': true,
      'delete_requests.review': true,
      'users.read': true,
      'inventory.read': true,
      'config.read': true,
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

process.on('uncaughtException', (error) => {
  console.error('Uncaught exception:', error);
});

process.on('unhandledRejection', (error) => {
  console.error('Unhandled rejection:', error);
});

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
app.use(cors(buildCorsOptions()));
app.use(express.json());

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
      error: `Database initialization failed: ${dbInitError.message}`,
    });
    return;
  }
  if (!dbReady) {
    res.status(503).json({
      success: false,
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

function validatePasswordPolicy(password, { email = '' } = {}) {
  const value = String(password || '');
  const normalized = value.toLowerCase();
  if (value.length < 10) {
    return PASSWORD_POLICY_ERROR;
  }
  if (!/[a-z]/i.test(value) || !/[0-9]/.test(value)) {
    return PASSWORD_POLICY_ERROR;
  }
  const emailPrefix = String(email || '').split('@')[0].trim().toLowerCase();
  if (emailPrefix && emailPrefix.length >= 3 && normalized.includes(emailPrefix)) {
    return PASSWORD_POLICY_ERROR;
  }
  if (COMMON_WEAK_PASSWORDS.has(normalized)) {
    return PASSWORD_POLICY_ERROR;
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

function permissionDescriptors() {
  return PERMISSION_KEYS.map((key) => ({
    key,
    label: PERMISSION_DESCRIPTORS[key]?.label || key,
    description: PERMISSION_DESCRIPTORS[key]?.description || '',
  }));
}

async function getRolePermissionMap(role) {
  if (role === 'super_admin') {
    return Object.fromEntries(PERMISSION_KEYS.map((key) => [key, true]));
  }
  const rows = await all(
    'SELECT permission_key, is_allowed FROM role_permissions WHERE role = ?',
    [role],
  );
  const defaults = createEmptyPermissionMap();
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

function safeUserDto(row, permissionMap = null) {
  if (!row) {
    return null;
  }
  const effectivePermissions = permissionMap || createEmptyPermissionMap();
  return {
    id: row.id,
    name: row.name || '',
    email: row.email || '',
    role: row.role || 'user',
    permissions: permissionMapToList(effectivePermissions),
    isActive: Number(row.is_active || 0) === 1,
    failedLoginAttempts: Number(row.failed_login_attempts || 0),
    lockoutUntil: row.lockout_until || null,
    createdByUserId: row.created_by_user_id || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
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

async function createAuthSession({ user, req }) {
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

async function createUserAccount({
  name,
  email,
  password,
  role,
  createdByUserId = null,
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
  const passwordError = validatePasswordPolicy(password, { email: normalizedEmail });
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
  const result = await run(
    `
    INSERT INTO users (
      name, email, password_hash, role, is_active, created_by_user_id, created_at, updated_at
    ) VALUES (?, ?, ?, ?, 1, ?, ?, ?)
    `,
    [
      normalizedName,
      normalizedEmail,
      hashPassword(password),
      normalizedRole,
      createdByUserId,
      now,
      now,
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
  return safeUserDto(row, permissionMap);
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
  const email = process.env.PAPER_SUPER_ADMIN_EMAIL || 'super@paper.local';
  const password = process.env.PAPER_SUPER_ADMIN_PASSWORD || 'Paper@12345';
  const name = process.env.PAPER_SUPER_ADMIN_NAME || 'Super Admin';
  await createUserAccount({
    name,
    email,
    password,
    role: 'super_admin',
  });
  if (!process.env.PAPER_SUPER_ADMIN_PASSWORD) {
    console.warn(
      'Bootstrapped default super admin: super@paper.local / Paper@12345. Set PAPER_SUPER_ADMIN_* before production use.',
    );
  }
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

function requireApiWritePermission(req, res, next) {
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
    db.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
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
  const childCount = Number(row.number_of_children || 0);
  const displayStock = String(row.display_stock || '').trim() ||
    (unitLabel
      ? `${Math.max(childCount, 1) * 100} ${unitLabel}`
      : `${Math.max(childCount, 1) * 100} Pieces`);

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

function rowToGroupDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    parentGroupId: row.parent_group_id || null,
    unitId: row.unit_id || null,
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
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

function rowToOrderDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    orderNo: row.order_no || '',
    clientId: row.client_id || 0,
    clientName: row.client_name || '',
    poNumber: row.po_number || '',
    clientCode: row.client_code || '',
    itemId: row.item_id || 0,
    itemName: row.item_name || '',
    variationLeafNodeId: row.variation_leaf_node_id || 0,
    variationPathLabel: row.variation_path_label || '',
    variationPathNodeIds: parseJson(row.variation_path_node_ids_json, []),
    quantity: Number(row.quantity || 0),
    status: row.status || 'notStarted',
    createdAt: row.created_at,
    startDate: row.start_date,
    endDate: row.end_date,
  };
}

async function rowToItemDto(row) {
  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name || '',
    alias: row.alias || '',
    displayName: row.display_name || '',
    quantity: Number(row.quantity || 0),
    groupId: row.group_id || null,
    unitId: row.unit_id || null,
    isArchived: Boolean(row.is_archived),
    usageCount: row.usage_count || 0,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    variationTree: await getItemVariationTree(row.id),
  };
}

function rowToTemplate(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    name: row.name,
    description: row.description || '',
    version: row.version || 1,
    status: row.status || 'draft',
    stageLabels: parseJson(row.stage_labels_json, []),
    laneLabels: parseJson(row.lane_labels_json, []),
    nodes: parseJson(row.nodes_json, []),
    flows: parseJson(row.flows_json, []),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
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

  return {
    id: row.id,
    templateId: row.template_id,
    templateVersion: row.template_version,
    name: row.name || '',
    status: row.status || 'planned',
    overrides: parseJson(row.overrides_json, {}),
    nodeStatuses: parseJson(row.node_status_json, {}),
    attachedBarcodeInputs,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    createdAt: row.created_at,
  };
}

function buildSeedTemplates() {
  return [
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

async function initDb() {
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
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(material_id)
    )
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
      from_location_id TEXT,
      to_location_id TEXT,
      reason_code TEXT,
      reference_type TEXT,
      reference_id TEXT,
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
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      parent_group_id INTEGER REFERENCES groups(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

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
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      display_name TEXT NOT NULL,
      quantity REAL NOT NULL DEFAULT 0,
      group_id INTEGER NOT NULL REFERENCES groups(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await run(`
    CREATE TABLE IF NOT EXISTS orders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_no TEXT NOT NULL,
      client_id INTEGER NOT NULL REFERENCES clients(id),
      client_name TEXT NOT NULL DEFAULT '',
      po_number TEXT DEFAULT '',
      client_code TEXT DEFAULT '',
      item_id INTEGER NOT NULL REFERENCES items(id),
      item_name TEXT NOT NULL DEFAULT '',
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      variation_path_label TEXT DEFAULT '',
      variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
      quantity INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'notStarted',
      created_at TEXT NOT NULL,
      start_date TEXT,
      end_date TEXT
    )
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
      display_name TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);

  await ensureColumnExists('items', 'quantity', 'REAL NOT NULL DEFAULT 0');
  await ensureColumnExists('item_variations', 'alias', "TEXT DEFAULT ''");
  await ensureColumnExists('item_variations', 'display_name', "TEXT DEFAULT ''");

  await ensureColumnExists('materials', 'unit_id', 'INTEGER');
  await ensureColumnExists('units', 'unit_group_id', 'INTEGER');
  await ensureColumnExists('units', 'conversion_factor', 'REAL NOT NULL DEFAULT 1');
  await ensureColumnExists('units', 'conversion_base_unit_id', 'INTEGER');
  await ensureColumnExists('materials', 'linked_group_id', 'INTEGER');
  await ensureColumnExists('materials', 'linked_item_id', 'INTEGER');
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
  await ensureColumnExists('users', 'failed_login_attempts', 'INTEGER NOT NULL DEFAULT 0');
  await ensureColumnExists('users', 'first_failed_login_at', 'TEXT');
  await ensureColumnExists('users', 'lockout_until', 'TEXT');
  await ensureColumnExists('users', 'last_login_at', 'TEXT');
  await ensureColumnExists('users', 'last_login_ip', "TEXT DEFAULT ''");
  await ensureColumnExists('auth_sessions', 'ip_address', "TEXT DEFAULT ''");
  await ensureColumnExists('auth_sessions', 'user_agent', "TEXT DEFAULT ''");
  await ensureColumnExists('auth_sessions', 'revoked_reason', "TEXT DEFAULT ''");
  await ensureColumnExists('delete_requests', 'reviewed_note', "TEXT DEFAULT ''");
  await run("UPDATE materials SET updated_at = created_at WHERE updated_at IS NULL");
  await seedRolePermissions();
  await seedPermissionTemplates();

  await run(`
    CREATE TABLE IF NOT EXISTS pipeline_templates (
      id TEXT PRIMARY KEY,
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

  await seedMaterialsIfEmpty();
  await seedUnitsIfEmpty();
  await bootstrapUnitsFromMaterials();
  await backfillMaterialUnitIds();
  await seedClientsIfEmpty();
  await seedGroupsIfEmpty();
  await seedItemsIfEmpty();
  await seedOrdersIfEmpty();
  await seedTemplatesIfEmpty();
  await ensureDemoDataset();
  await bootstrapSuperAdminIfNeeded();
  dbReady = true;
}

async function ensureDemoDataset() {
  await ensureDemoUnitsPresent();
  await backfillMaterialUnitIds();
  await ensureDemoClientsPresent();
  await ensureDemoGroupsPresent();
  await ensureDemoItemsPresent();
  await ensureDemoOrdersPresent();
  await ensureDemoMaterialsPresent();
  await backfillInventoryLedgerForMaterials();
  await backfillMaterialUnitIds();
  await ensureDemoPipelineRunsPresent();
}

async function backfillInventoryLedgerForMaterials() {
  const materials = await all('SELECT * FROM materials');
  for (const material of materials) {
    const positionCountRow = await get(
      'SELECT COUNT(*) AS count FROM inventory_stock_positions WHERE material_barcode = ?',
      [material.barcode],
    );
    const hasPosition = Number(positionCountRow?.count || 0) > 0;
    if (!hasPosition) {
      const inferredOnHand = Number(material.number_of_children || 0) > 0
        ? Number(material.number_of_children || 0) * 100
        : 100;
      await upsertInventoryStockPosition({
        materialBarcode: material.barcode,
        locationId: String(material.location || '').trim() || 'MAIN',
        lotCode: material.barcode,
        unitId: material.unit_id || null,
        onHandDelta: inferredOnHand,
      });
    }
    await recomputeMaterialInventorySummary(material.barcode);
  }
}

async function ensureColumnExists(tableName, columnName, definition) {
  const columns = await all(`PRAGMA table_info(${tableName})`);
  const hasColumn = columns.some((column) => column.name === columnName);
  if (!hasColumn) {
    await run(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${definition}`);
  }
}

async function seedMaterialsIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM materials');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  await createParentWithChildren({
    name: 'Copper Master Roll',
    type: 'Raw Material',
    grade: 'A1',
    thickness: '1.2 mm',
    supplier: 'Shree Metals',
    unit: 'Kg',
    notes: 'Demo seed',
    numberOfChildren: 3,
  });
  await createParentWithChildren({
    name: 'Steel Sheet Batch',
    type: 'Raw Material',
    grade: 'B2',
    thickness: '2.0 mm',
    supplier: 'Metro Steels',
    unit: 'Sheet',
    notes: 'Demo seed',
    numberOfChildren: 2,
  });
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
      name: 'Kilogram',
      symbol: 'Kg',
      notes: 'Bulk raw materials, powders, and compounds.',
    },
    {
      name: 'Sheet',
      symbol: 'Sheet',
      notes: 'Flat paperboard and sheet-based stock.',
    },
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
      name: 'Roll',
      symbol: 'Roll',
      notes: 'Coils, reels, and roll-fed substrates.',
    },
    {
      name: 'Set',
      symbol: 'Set',
      notes: 'Bundled assemblies sold as one unit.',
    },
    {
      name: 'Meter',
      symbol: 'Mtr',
      notes: 'Linear materials like film, tape, and sleeves.',
    },
    {
      name: 'Legacy Lot',
      symbol: 'Lot',
      notes: 'Archived legacy measurement kept for historical data.',
      isArchived: true,
    },
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

async function seedTemplatesIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM pipeline_templates');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const templates = buildSeedTemplates();
  for (const template of templates) {
    const now = new Date().toISOString();
    await run(
      `
      INSERT INTO pipeline_templates (
        id, name, description, version, status, stage_labels_json,
        lane_labels_json, nodes_json, flows_json, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        template.id,
        template.name,
        template.description,
        template.version,
        template.status,
        JSON.stringify(template.stageLabels),
        JSON.stringify(template.laneLabels),
        JSON.stringify(template.nodes),
        JSON.stringify(template.flows),
        now,
        now,
      ],
    );
  }
}

async function createParentWithChildren(payload) {
  const resolvedUnit = await resolveUnitPayload(payload);
  const actor = String(payload?.actor || '').trim() || 'Demo Admin';
  const parentBarcode = generateParentBarcode();
  const childBarcodes = Array.from(
    { length: Number(payload.numberOfChildren || 0) },
    (_, index) => generateChildBarcode(parentBarcode, index + 1),
  );
  const createdAt = new Date().toISOString();
  const parentDisplayStock = resolvedUnit.unit
    ? `${Number(payload.numberOfChildren || 0) * 100} ${resolvedUnit.unit}`
    : `${Number(payload.numberOfChildren || 0) * 100} Pieces`;

  await run('BEGIN TRANSACTION');
  try {
    const parentResult = await run(
      `
      INSERT INTO materials (
        barcode, name, type, grade, thickness, supplier, location, unit_id, unit, notes, group_mode, inheritance_enabled,
        created_at, kind, parent_barcode, number_of_children,
        linked_child_barcodes, scan_count, linked_group_id, linked_item_id,
        display_stock, created_by, workflow_status, updated_at, last_scanned_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'parent', NULL, ?, ?, 0, NULL, NULL, ?, ?, ?, ?, NULL)
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
        String(payload.groupMode || '').trim() || null,
        payload.inheritanceEnabled ? 1 : 0,
        createdAt,
        Number(payload.numberOfChildren || 0),
        JSON.stringify(childBarcodes),
        parentDisplayStock,
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
          String(payload.groupMode || '').trim() || null,
          payload.inheritanceEnabled ? 1 : 0,
          createdAt,
          parentBarcode,
          JSON.stringify([]),
          resolvedUnit.unit ? `100 ${resolvedUnit.unit}` : '100 Pieces',
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
    await upsertInventoryStockPosition({
      materialBarcode: parentBarcode,
      locationId: String(payload.location || '').trim() || 'MAIN',
      lotCode: parentBarcode,
      unitId: resolvedUnit.unitId,
      onHandDelta: Number(payload.numberOfChildren || 0) * 100,
      now: createdAt,
    });
    for (const childBarcode of childBarcodes) {
      await upsertInventoryStockPosition({
        materialBarcode: childBarcode,
        locationId: String(payload.location || '').trim() || 'MAIN',
        lotCode: childBarcode,
        unitId: resolvedUnit.unitId,
        onHandDelta: 100,
        now: createdAt,
      });
    }
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
      COUNT(materials.id) AS usage_count
    FROM units
    LEFT JOIN unit_groups ON unit_groups.id = units.unit_group_id
    LEFT JOIN units AS base_unit ON base_unit.id = units.conversion_base_unit_id
    LEFT JOIN materials ON materials.unit_id = units.id
    WHERE units.id = ?
    GROUP BY units.id
    `,
    [id],
  );
}

async function getGroupRowById(id) {
  return get(
    `
    SELECT
      groups.*,
      0 AS usage_count
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
      0 AS usage_count
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
    WHERE item_id = ?
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
      0 AS usage_count
    FROM items
    WHERE items.id = ?
    `,
    [id],
  );
}

async function getItemsWithUsage() {
  return all(`
    SELECT
      items.*,
      0 AS usage_count
    FROM items
    ORDER BY items.is_archived ASC, LOWER(items.name) ASC
  `);
}

async function findItemDuplicate({ name, groupId, quantity, excludeId = null }) {
  const rows = await all('SELECT id, name, group_id, quantity FROM items');
  const normalizedName = normalizeUnitValue(name);
  return rows.find((row) => {
    if (excludeId != null && row.id === excludeId) {
      return false;
    }
    return (
      row.group_id === groupId &&
      Number(row.quantity || 0) === Number(quantity || 0) &&
      normalizeUnitValue(row.name) === normalizedName
    );
  }) || null;
}

async function getGroupsWithUsage() {
  return all(`
    SELECT
      groups.*,
      0 AS usage_count
    FROM groups
    ORDER BY groups.is_archived ASC, LOWER(groups.name) ASC
  `);
}

async function getClientsWithUsage() {
  return all(`
    SELECT
      clients.*,
      0 AS usage_count
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

async function saveClient({ name, alias = '', gstNumber = '', address = '', id = null }) {
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
    return getClientRowById(result.lastID);
  }

  const existing = await getClientRowById(id);
  if (!existing) {
    const error = new Error('Client not found.');
    error.statusCode = 404;
    throw error;
  }

  await run(
    'UPDATE clients SET name = ?, alias = ?, gst_number = ?, address = ?, updated_at = ? WHERE id = ?',
    [trimmedName, trimmedAlias, trimmedGstNumber, trimmedAddress, now, id],
  );
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

async function getOrderRowById(id) {
  return get('SELECT * FROM orders WHERE id = ?', [id]);
}

async function getOrders() {
  return all('SELECT * FROM orders ORDER BY datetime(created_at) DESC, id DESC');
}

async function saveOrder({
  orderNo,
  clientId,
  clientName = '',
  poNumber = '',
  clientCode = '',
  itemId,
  itemName = '',
  variationLeafNodeId = 0,
  variationPathLabel = '',
  variationPathNodeIds = [],
  quantity,
  status = 'notStarted',
  startDate = null,
  endDate = null,
}) {
  const trimmedOrderNo = String(orderNo || '').trim();
  const normalizedClientId = Number(clientId);
  const normalizedItemId = Number(itemId);
  const normalizedLeafId = Number(variationLeafNodeId || 0);
  const normalizedQuantity = Number(quantity || 0);
  const trimmedPoNumber = String(poNumber || '').trim();
  const trimmedClientName = String(clientName || '').trim();
  const trimmedClientCode = String(clientCode || '').trim();
  const trimmedItemName = String(itemName || '').trim();
  const trimmedVariationPathLabel = String(variationPathLabel || '').trim();
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
  if (!normalizedClientId || !normalizedItemId || !normalizedLeafId) {
    const error = new Error('Client, item, and variation path are required.');
    error.statusCode = 400;
    throw error;
  }
  if (!Number.isFinite(normalizedQuantity) || normalizedQuantity <= 0) {
    const error = new Error('Quantity must be greater than zero.');
    error.statusCode = 400;
    throw error;
  }

  const now = new Date().toISOString();
  const existing = await get(
    `
    SELECT * FROM orders
    WHERE LOWER(TRIM(order_no)) = LOWER(TRIM(?))
      AND client_id = ?
      AND item_id = ?
      AND variation_leaf_node_id = ?
      AND LOWER(TRIM(po_number)) = LOWER(TRIM(?))
    `,
    [trimmedOrderNo, normalizedClientId, normalizedItemId, normalizedLeafId, trimmedPoNumber],
  );

  if (existing) {
    await run(
      `
      UPDATE orders
      SET quantity = quantity + ?,
          client_name = ?,
          client_code = ?,
          item_name = ?,
          variation_path_label = ?,
          variation_path_node_ids_json = ?
      WHERE id = ?
      `,
      [
        normalizedQuantity,
        trimmedClientName,
        trimmedClientCode,
        trimmedItemName,
        trimmedVariationPathLabel,
        JSON.stringify(Array.isArray(variationPathNodeIds) ? variationPathNodeIds : []),
        existing.id,
      ],
    );
    return getOrderRowById(existing.id);
  }

  const result = await run(
    `
    INSERT INTO orders (
      order_no, client_id, client_name, po_number, client_code, item_id, item_name,
      variation_leaf_node_id, variation_path_label, variation_path_node_ids_json,
      quantity, status, created_at, start_date, end_date
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      trimmedVariationPathLabel,
      JSON.stringify(Array.isArray(variationPathNodeIds) ? variationPathNodeIds : []),
      Math.round(normalizedQuantity),
      normalizedStatus,
      now,
      startDate || null,
      endDate || null,
    ],
  );
  return getOrderRowById(result.lastID);
}

async function updateOrderLifecycle({
  id,
  status = 'notStarted',
  startDate = null,
  endDate = null,
}) {
  const existing = await getOrderRowById(id);
  if (!existing) {
    const error = new Error('Order not found.');
    error.statusCode = 404;
    throw error;
  }
  const allowedStatuses = new Set([
    'draft',
    'notStarted',
    'inProgress',
    'completed',
    'delayed',
  ]);
  const normalizedStatus = allowedStatuses.has(status) ? status : 'notStarted';
  await run(
    'UPDATE orders SET status = ?, start_date = ?, end_date = ? WHERE id = ?',
    [normalizedStatus, startDate || null, endDate || null, id],
  );
  return getOrderRowById(id);
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

async function saveGroup({ name, parentGroupId = null, unitId, id = null }) {
  const trimmedName = String(name || '').trim();
  const normalizedParentId = parentGroupId == null ? null : Number(parentGroupId);
  const normalizedUnitId = Number(unitId);

  if (!trimmedName || !normalizedUnitId) {
    throw new Error('name and unitId are required.');
  }

  const unitRow = await get('SELECT * FROM units WHERE id = ?', [normalizedUnitId]);
  if (!unitRow || unitRow.is_archived) {
    const error = new Error('Selected unit does not exist or is archived.');
    error.statusCode = 400;
    throw error;
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
      INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
      VALUES (?, ?, ?, 0, ?, ?)
      `,
      [trimmedName, normalizedParentId, normalizedUnitId, now, now],
    );
    return getGroupRowById(result.lastID);
  }

  const existing = await getGroupRowById(id);
  if (!existing) {
    const error = new Error('Group not found.');
    error.statusCode = 404;
    throw error;
  }
  if ((existing.usage_count || 0) > 0) {
    const error = new Error('Used groups cannot be edited.');
    error.statusCode = 409;
    throw error;
  }

  await run(
    'UPDATE groups SET name = ?, parent_group_id = ?, unit_id = ?, updated_at = ? WHERE id = ?',
    [trimmedName, normalizedParentId, normalizedUnitId, now, id],
  );
  return getGroupRowById(id);
}

async function seedGroupsIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM groups');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const units = await all(
    'SELECT id, symbol FROM units WHERE is_archived = 0 ORDER BY id ASC',
  );
  const sheetUnit = units.find((unit) => normalizeUnitValue(unit.symbol) === 'sheet');
  const kilogramUnit = units.find((unit) => normalizeUnitValue(unit.symbol) === 'kg');
  const fallbackUnit = sheetUnit || kilogramUnit || units[0];
  if (!fallbackUnit) {
    return;
  }

  const now = new Date().toISOString();
  const paperResult = await run(
    `
    INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
    VALUES (?, NULL, ?, 0, ?, ?)
    `,
    ['Paper', sheetUnit?.id || fallbackUnit.id, now, now],
  );
  await run(
    `
    INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
    VALUES (?, ?, ?, 0, ?, ?)
    `,
    ['Kraft', paperResult.lastID, sheetUnit?.id || fallbackUnit.id, now, now],
  );
  await run(
    `
    INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
    VALUES (?, NULL, ?, 0, ?, ?)
    `,
    ['Chemical', kilogramUnit?.id || fallbackUnit.id, now, now],
  );
  await run(
    `
    INSERT INTO groups (name, parent_group_id, unit_id, is_archived, created_at, updated_at)
    VALUES (?, NULL, ?, 1, ?, ?)
    `,
    ['Legacy Group', kilogramUnit?.id || fallbackUnit.id, now, now],
  );
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
  const sheetUnit = bySymbol.get('sheet') || units[0];
  const kilogramUnit = bySymbol.get('kg') || units[0];
  const pieceUnit = bySymbol.get('pc') || units[0];
  const rollUnit = bySymbol.get('roll') || sheetUnit || units[0];
  const meterUnit = bySymbol.get('mtr') || units[0];
  if (!sheetUnit || !kilogramUnit || !pieceUnit || !rollUnit || !meterUnit) {
    return;
  }

  const paper = await ensureGroupRecord({
    name: 'Paper',
    unitId: sheetUnit.id,
  });
  await ensureGroupRecord({
    name: 'Kraft',
    parentGroupId: paper.id,
    unitId: sheetUnit.id,
  });
  await ensureGroupRecord({
    name: 'Duplex Board',
    parentGroupId: paper.id,
    unitId: sheetUnit.id,
  });
  await ensureGroupRecord({
    name: 'Corrugated',
    parentGroupId: paper.id,
    unitId: sheetUnit.id,
  });

  const chemicals = await ensureGroupRecord({
    name: 'Chemical',
    unitId: kilogramUnit.id,
  });
  await ensureGroupRecord({
    name: 'Adhesives',
    parentGroupId: chemicals.id,
    unitId: kilogramUnit.id,
  });
  await ensureGroupRecord({
    name: 'Coatings',
    parentGroupId: chemicals.id,
    unitId: kilogramUnit.id,
  });

  const packaging = await ensureGroupRecord({
    name: 'Packaging Components',
    unitId: pieceUnit.id,
  });
  await ensureGroupRecord({
    name: 'Caps',
    parentGroupId: packaging.id,
    unitId: pieceUnit.id,
  });
  await ensureGroupRecord({
    name: 'Sleeves',
    parentGroupId: packaging.id,
    unitId: meterUnit.id,
  });
  await ensureGroupRecord({
    name: 'Film Rolls',
    parentGroupId: packaging.id,
    unitId: rollUnit.id,
  });

  await ensureGroupRecord({
    name: 'Legacy Group',
    unitId: kilogramUnit.id,
    isArchived: true,
  });
}

function buildItemDisplayName(name, alias, quantity) {
  const parts = [String(name || '').trim(), String(alias || '').trim()].filter(Boolean);
  const base = parts.join(' / ');
  const qty = Number(quantity || 0);
  const qtyLabel = Number.isInteger(qty) ? String(qty) : String(qty);
  return base ? `${base} - ${qtyLabel}` : qtyLabel;
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
  quantity,
  groupId,
  unitId,
  variationTree = [],
  id = null,
}) {
  const trimmedName = String(name || '').trim();
  const trimmedAlias = String(alias || '').trim();
  const normalizedQuantity = Number(quantity);
  const trimmedDisplayName =
    String(displayName || '').trim() || buildItemDisplayName(name, alias, normalizedQuantity);
  const normalizedGroupId = Number(groupId);
  const normalizedUnitId = Number(unitId);

  if (
    !trimmedName ||
    !normalizedQuantity ||
    !normalizedGroupId ||
    !normalizedUnitId ||
    !trimmedDisplayName
  ) {
    throw new Error('name, quantity, displayName, groupId, and unitId are required.');
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

  const duplicate = await findItemDuplicate({
    name: trimmedName,
    groupId: normalizedGroupId,
    quantity: normalizedQuantity,
    excludeId: id,
  });
  if (duplicate) {
    const error = new Error('An item with the same name and quantity already exists in this group.');
    error.statusCode = 409;
    throw error;
  }

  const sanitizeNodes = (nodes, expectedKind, pathSegments = [], parentPropertyName = '') => {
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
        const error = new Error('Variation tree must alternate between property groups and values.');
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

      if (kind === 'property') {
        return {
          kind,
          name: trimmedName,
          displayName: '',
          position: index,
          children: sanitizeNodes(node.children || [], 'value', pathSegments, trimmedName),
        };
      }

      const nextSegments = [...pathSegments, trimmedName];
      const children = sanitizeNodes(node.children || [], 'property', nextSegments, '');
      return {
        kind,
        name: trimmedName,
        displayName:
          children.length === 0
            ? String(node.displayName || '').trim() || buildVariationPathLabel(nextSegments)
            : '',
        position: index,
        children,
      };
    });
  };

  const sanitizedTree = sanitizeNodes(variationTree, 'property');

  const now = new Date().toISOString();
  await run('BEGIN TRANSACTION');
  try {
    let itemId = id;
    if (id == null) {
      const result = await run(
        `
        INSERT INTO items (
          name, alias, display_name, quantity, group_id, unit_id, is_archived, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
        `,
        [
          trimmedName,
          trimmedAlias,
          trimmedDisplayName,
          normalizedQuantity,
          normalizedGroupId,
          normalizedUnitId,
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
        const error = new Error('Used items cannot be edited.');
        error.statusCode = 409;
        throw error;
      }
      await run(
        `
        UPDATE items
        SET name = ?, alias = ?, display_name = ?, quantity = ?, group_id = ?, unit_id = ?, updated_at = ?
        WHERE id = ?
        `,
        [
          trimmedName,
          trimmedAlias,
          trimmedDisplayName,
          normalizedQuantity,
          normalizedGroupId,
          normalizedUnitId,
          now,
          id,
        ],
      );
      await run('DELETE FROM item_variation_nodes WHERE item_id = ?', [id]);
    }

    const insertNodes = async (nodes, parentNodeId = null) => {
      for (const node of nodes) {
        const result = await run(
          `
          INSERT INTO item_variation_nodes (
            item_id, parent_node_id, kind, name, display_name, position,
            is_archived, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
          `,
          [
            itemId,
            parentNodeId,
            node.kind,
            node.name,
            node.displayName,
            node.position,
            now,
            now,
          ],
        );
        await insertNodes(node.children, result.lastID);
      }
    };

    await insertNodes(sanitizedTree);

    await run('COMMIT');
    return getItemRowById(itemId);
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }
}

async function seedItemsIfEmpty() {
  const countRow = await get('SELECT COUNT(*) AS count FROM items');
  if ((countRow?.count || 0) > 0) {
    return;
  }

  const groups = await all('SELECT * FROM groups WHERE is_archived = 0 ORDER BY id ASC');
  const units = await all('SELECT * FROM units WHERE is_archived = 0 ORDER BY id ASC');
  const kraftGroup = groups.find((group) => normalizeUnitValue(group.name) === 'kraft') || groups[0];
  const chemicalGroup = groups.find((group) => normalizeUnitValue(group.name) === 'chemical') || groups[0];
  const sheetUnit = units.find((unit) => normalizeUnitValue(unit.symbol) === 'sheet') || units[0];
  const kilogramUnit = units.find((unit) => normalizeUnitValue(unit.symbol) === 'kg') || units[0] || sheetUnit;
  if (!kraftGroup || !sheetUnit) {
    return;
  }

  await saveItem({
    name: 'Switch Action Dolly',
    alias: 'Finish Goods Variant',
    displayName: 'Switch Action Dolly - 1',
    quantity: 1,
    groupId: kraftGroup.id,
    unitId: sheetUnit.id,
    variationTree: [
      {
        kind: 'property',
        name: 'Action Dolly Amp',
        children: [
          {
            kind: 'value',
            name: '5 Amp',
            children: [
              {
                kind: 'property',
                name: 'Action Patti + Dabbi',
                children: [
                  {
                    kind: 'value',
                    name: '11+1',
                    children: [
                      {
                        kind: 'property',
                        name: 'Action Dolly Alloy',
                        children: [
                          {
                            kind: 'value',
                            name: 'Brass',
                            children: [
                              {
                                kind: 'property',
                                name: 'Action Dolly Contact',
                                children: [
                                  {
                                    kind: 'value',
                                    name: '1 Way',
                                    children: [
                                      {
                                        kind: 'property',
                                        name: 'Action Dolly Type',
                                        children: [
                                          {
                                            kind: 'value',
                                            name: 'Dolly',
                                            children: [
                                              {
                                                kind: 'property',
                                                name: 'Action Dolly Plating',
                                                children: [
                                                  {
                                                    kind: 'value',
                                                    name: 'Without Plating',
                                                    displayName:
                                                      '5 Amp 11+1 Brass 1 Way Dolly Without Plating',
                                                  },
                                                  {
                                                    kind: 'value',
                                                    name: 'With Plating',
                                                    displayName:
                                                      '5 Amp 11+1 Brass 1 Way Dolly With Plating',
                                                  },
                                                ],
                                              },
                                            ],
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
          {
            kind: 'value',
            name: '6 Amp',
            children: [
              {
                kind: 'property',
                name: 'Action Patti + Dabbi',
                children: [
                  {
                    kind: 'value',
                    name: '11+1',
                    children: [
                      {
                        kind: 'property',
                        name: 'Action Dolly Alloy',
                        children: [
                          {
                            kind: 'value',
                            name: 'Brass',
                            children: [
                              {
                                kind: 'property',
                                name: 'Action Dolly Contact',
                                children: [
                                  {
                                    kind: 'value',
                                    name: '1 Way',
                                    children: [
                                      {
                                        kind: 'property',
                                        name: 'Action Dolly Type',
                                        children: [
                                          {
                                            kind: 'value',
                                            name: 'Dolly',
                                            children: [
                                              {
                                                kind: 'property',
                                                name: 'Action Dolly Plating',
                                                children: [
                                                  {
                                                    kind: 'value',
                                                    name: 'Without Plating',
                                                    displayName:
                                                      '6 Amp 11+1 Brass 1 Way Dolly Without Plating',
                                                  },
                                                ],
                                              },
                                            ],
                                          },
                                        ],
                                      },
                                    ],
                                  },
                                ],
                              },
                            ],
                          },
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  });
  if (chemicalGroup && kilogramUnit) {
    await saveItem({
      name: 'Glue Compound',
      alias: 'Adhesive',
      displayName: 'Glue Compound - 1',
      quantity: 1,
      groupId: chemicalGroup.id,
      unitId: kilogramUnit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Cure Speed',
          children: [{ kind: 'value', name: 'Fast Cure' }],
        },
      ],
    });

    await saveItem({
      name: 'Luxury Pump Bottle',
      alias: 'Cosmetic Pack',
      displayName: 'Luxury Pump Bottle - 100',
      quantity: 100,
      groupId: kraftGroup.id,
      unitId: sheetUnit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Bottle Material',
          children: [
            {
              kind: 'value',
              name: 'PET',
              children: [
                {
                  kind: 'property',
                  name: 'Bottle Color',
                  children: [
                    {
                      kind: 'value',
                      name: 'Frosted Clear',
                      children: [
                        {
                          kind: 'property',
                          name: 'Pump Finish',
                          children: [
                            {
                              kind: 'value',
                              name: 'Matte Silver',
                              children: [
                                {
                                  kind: 'property',
                                  name: 'Lock Type',
                                  children: [
                                    {
                                      kind: 'value',
                                      name: 'Left Lock',
                                      displayName:
                                        'PET Frosted Clear Matte Silver Left Lock',
                                    },
                                    {
                                      kind: 'value',
                                      name: 'Right Lock',
                                      displayName:
                                        'PET Frosted Clear Matte Silver Right Lock',
                                    },
                                  ],
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                    {
                      kind: 'value',
                      name: 'Amber',
                      children: [
                        {
                          kind: 'property',
                          name: 'Pump Finish',
                          children: [
                            {
                              kind: 'value',
                              name: 'Gloss Gold',
                              children: [
                                {
                                  kind: 'property',
                                  name: 'Lock Type',
                                  children: [
                                    {
                                      kind: 'value',
                                      name: 'Left Lock',
                                      displayName:
                                        'PET Amber Gloss Gold Left Lock',
                                    },
                                  ],
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
            {
              kind: 'value',
              name: 'Glass',
              children: [
                {
                  kind: 'property',
                  name: 'Bottle Color',
                  children: [
                    {
                      kind: 'value',
                      name: 'Clear',
                      children: [
                        {
                          kind: 'property',
                          name: 'Pump Finish',
                          children: [
                            {
                              kind: 'value',
                              name: 'Rose Gold',
                              children: [
                                {
                                  kind: 'property',
                                  name: 'Lock Type',
                                  children: [
                                    {
                                      kind: 'value',
                                      name: 'Right Lock',
                                      displayName:
                                        'Glass Clear Rose Gold Right Lock',
                                    },
                                  ],
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    });

    await saveItem({
      name: 'Premium Mono Carton',
      alias: 'Retail Carton',
      displayName: 'Premium Mono Carton - 500',
      quantity: 500,
      groupId: kraftGroup.id,
      unitId: sheetUnit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Board GSM',
          children: [
            {
              kind: 'value',
              name: '300 GSM',
              children: [
                {
                  kind: 'property',
                  name: 'Print Finish',
                  children: [
                    {
                      kind: 'value',
                      name: 'Matte',
                      children: [
                        {
                          kind: 'property',
                          name: 'Foil',
                          children: [
                            {
                              kind: 'value',
                              name: 'Gold Foil',
                              children: [
                                {
                                  kind: 'property',
                                  name: 'Window',
                                  children: [
                                    {
                                      kind: 'value',
                                      name: 'With Window',
                                      displayName:
                                        '300 GSM Matte Gold Foil With Window',
                                    },
                                    {
                                      kind: 'value',
                                      name: 'No Window',
                                      displayName:
                                        '300 GSM Matte Gold Foil No Window',
                                    },
                                  ],
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                    {
                      kind: 'value',
                      name: 'Gloss',
                      children: [
                        {
                          kind: 'property',
                          name: 'Foil',
                          children: [
                            {
                              kind: 'value',
                              name: 'No Foil',
                              children: [
                                {
                                  kind: 'property',
                                  name: 'Window',
                                  children: [
                                    {
                                      kind: 'value',
                                      name: 'No Window',
                                      displayName:
                                        '300 GSM Gloss No Foil No Window',
                                    },
                                  ],
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
            {
              kind: 'value',
              name: '350 GSM',
              children: [
                {
                  kind: 'property',
                  name: 'Print Finish',
                  children: [
                    {
                      kind: 'value',
                      name: 'Matte',
                      children: [
                        {
                          kind: 'property',
                          name: 'Foil',
                          children: [
                            {
                              kind: 'value',
                              name: 'Rose Gold Foil',
                              children: [
                                {
                                  kind: 'property',
                                  name: 'Window',
                                  children: [
                                    {
                                      kind: 'value',
                                      name: 'With Window',
                                      displayName:
                                        '350 GSM Matte Rose Gold Foil With Window',
                                    },
                                  ],
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    });
  }
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
    }
    return getItemRowById(item.id);
  }

  if (Boolean(existing.is_archived) !== isArchived) {
    const now = new Date().toISOString();
    await run('UPDATE items SET is_archived = ?, updated_at = ? WHERE id = ?', [isArchived ? 1 : 0, now, existing.id]);
    await run('UPDATE item_variation_nodes SET is_archived = ?, updated_at = ? WHERE item_id = ?', [isArchived ? 1 : 0, now, existing.id]);
  }
  return getItemRowById(existing.id);
}

async function ensureDemoItemsPresent() {
  const groups = await getGroupsWithUsage();
  const units = await getUnitsWithUsage();
  const groupByName = new Map(
    groups.map((group) => [normalizeUnitValue(group.name), group]),
  );
  const unitBySymbol = new Map(
    units.map((unit) => [normalizeUnitValue(unit.symbol), unit]),
  );

  const kraft = groupByName.get('kraft');
  const adhesives = groupByName.get('adhesives');
  const caps = groupByName.get('caps');
  const sleeves = groupByName.get('sleeves');
  const duplex = groupByName.get('duplex board') || groupByName.get('paper');
  const sheetUnit = unitBySymbol.get('sheet');
  const kilogramUnit = unitBySymbol.get('kg');
  const pieceUnit = unitBySymbol.get('pc') || unitBySymbol.get('pieces');
  const meterUnit = unitBySymbol.get('mtr');

  if (!kraft || !adhesives || !caps || !sleeves || !duplex) {
    return;
  }
  if (!sheetUnit || !kilogramUnit || !pieceUnit || !meterUnit) {
    return;
  }

  const itemSeeds = [
    {
      name: 'Bottle Carton',
      alias: 'Classic Bottle',
      displayName: 'Bottle Carton - 100',
      quantity: 100,
      groupId: kraft.id,
      unitId: sheetUnit.id,
      matchDisplayNames: ['Bottle - 100'],
      variationTree: [
        {
          kind: 'property',
          name: 'Color',
          children: [
            {
              kind: 'value',
              name: 'Black',
              children: [
                {
                  kind: 'property',
                  name: 'Finish',
                  children: [
                    { kind: 'value', name: 'Matte' },
                    { kind: 'value', name: 'Glossy' },
                  ],
                },
              ],
            },
            {
              kind: 'value',
              name: 'Natural',
              children: [
                {
                  kind: 'property',
                  name: 'Print',
                  children: [
                    { kind: 'value', name: 'Flexo' },
                    { kind: 'value', name: 'Offset' },
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
    {
      name: 'Glue Compound',
      alias: 'Adhesive',
      displayName: 'Glue Compound - 25',
      quantity: 25,
      groupId: adhesives.id,
      unitId: kilogramUnit.id,
      matchDisplayNames: ['Glue Compound - 1'],
      variationTree: [
        {
          kind: 'property',
          name: 'Cure Speed',
          children: [
            {
              kind: 'value',
              name: 'Fast Cure',
              children: [
                {
                  kind: 'property',
                  name: 'Viscosity',
                  children: [
                    { kind: 'value', name: 'High' },
                    { kind: 'value', name: 'Medium' },
                  ],
                },
              ],
            },
            { kind: 'value', name: 'Standard Cure' },
          ],
        },
      ],
    },
    {
      name: 'Flip-Top Cap',
      alias: 'Secure Cap',
      displayName: 'Flip-Top Cap - 500',
      quantity: 500,
      groupId: caps.id,
      unitId: pieceUnit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Diameter',
          children: [
            {
              kind: 'value',
              name: '28 mm',
              children: [
                {
                  kind: 'property',
                  name: 'Color',
                  children: [
                    { kind: 'value', name: 'White' },
                    { kind: 'value', name: 'Blue' },
                  ],
                },
              ],
            },
            { kind: 'value', name: '32 mm' },
          ],
        },
      ],
    },
    {
      name: 'Printed Sleeve',
      alias: 'Shrink Sleeve',
      displayName: 'Printed Sleeve - 200',
      quantity: 200,
      groupId: sleeves.id,
      unitId: meterUnit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Finish',
          children: [
            {
              kind: 'value',
              name: 'Gloss',
              children: [
                {
                  kind: 'property',
                  name: 'Region',
                  children: [
                    { kind: 'value', name: 'Domestic' },
                    { kind: 'value', name: 'Export' },
                  ],
                },
              ],
            },
            { kind: 'value', name: 'Matte' },
          ],
        },
      ],
    },
    {
      name: 'Legacy Duplex Carton',
      alias: 'Old Mono',
      displayName: 'Legacy Duplex Carton - 50',
      quantity: 50,
      groupId: duplex.id,
      unitId: sheetUnit.id,
      isArchived: true,
      variationTree: [
        {
          kind: 'property',
          name: 'Coating',
          children: [{ kind: 'value', name: 'None' }],
        },
      ],
    },
  ];

  for (const itemSeed of itemSeeds) {
    await ensureItemRecord(itemSeed);
  }
}

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
  const countRow = await get('SELECT COUNT(*) AS count FROM orders');
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
      COUNT(materials.id) AS usage_count
    FROM units
    LEFT JOIN unit_groups ON unit_groups.id = units.unit_group_id
    LEFT JOIN units AS base_unit ON base_unit.id = units.conversion_base_unit_id
    LEFT JOIN materials ON materials.unit_id = units.id
    GROUP BY units.id
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
      String(existing.notes || '').trim() !== trimmedNotes;
    if (detailsChanged) {
      const error = new Error('Used units cannot change name, symbol, or notes.');
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

function normalizePropertyKey(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeGroupPropertyDraft(rawDraft) {
  const name = String(rawDraft?.name || '').trim();
  if (!name) {
    return null;
  }
  const inputType = String(rawDraft?.inputType || 'Text').trim() || 'Text';
  const sourceType = rawDraft?.sourceType === 'inherited_item' ? 'inherited_item' : 'manual';
  const state = ['active', 'unlinked', 'overridden'].includes(rawDraft?.state)
    ? rawDraft.state
    : 'active';
  const overrideLocked = Boolean(rawDraft?.overrideLocked);
  const hasTypeConflict = Boolean(rawDraft?.hasTypeConflict);
  const mandatory = Boolean(rawDraft?.mandatory);
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
    propertyKey: normalizePropertyKey(name),
    displayName: name,
    inputType,
    sourceType,
    state,
    mandatory,
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
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      material_id, common_only_mode, show_partial_matches, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?)
    `,
    [
      materialId,
      preferences.commonOnlyMode ? 1 : 0,
      preferences.showPartialMatches ? 1 : 0,
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

  return { selectedItemIds, selectedItems, propertyDrafts, unitGovernance, uiPreferences };
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
        Math.max(0, Number(onHandDelta || 0)),
        Math.max(0, Number(reservedDelta || 0)),
        Math.max(0, Number(damagedDelta || 0)),
        now,
      ],
    );
    return;
  }

  const nextOnHand = Math.max(0, Number(existing.on_hand_qty || 0) + Number(onHandDelta || 0));
  const nextReserved = Math.max(0, Number(existing.reserved_qty || 0) + Number(reservedDelta || 0));
  const nextDamaged = Math.max(0, Number(existing.damaged_qty || 0) + Number(damagedDelta || 0));
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
            'SELECT COUNT(*) AS count FROM orders WHERE item_id = ?',
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
          await get('SELECT COALESCE(SUM(quantity), 0) AS qty FROM orders WHERE item_id = ?', [
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

  return {
    material: rowToMaterialDto(refreshed),
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
      fromLocationId: row.from_location_id || null,
      toLocationId: row.to_location_id || null,
      reasonCode: row.reason_code || null,
      referenceType: row.reference_type || null,
      referenceId: row.reference_id || null,
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
        "SELECT COUNT(*) AS count FROM inventory_movements WHERE movement_type = 'receive' AND datetime(created_at) >= datetime('now', '-1 day')",
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

async function applyInventoryMovement(payload) {
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
  const toLocationId = String(payload?.toLocationId || '').trim() || material.location || 'MAIN';
  const lotCode = String(payload?.lotCode || '').trim() || barcode;
  const actor = String(payload?.actor || '').trim() || 'Demo Admin';

  await run('BEGIN TRANSACTION');
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
      await upsertInventoryStockPosition({
        materialBarcode: material.barcode,
        locationId: fromLocationId || material.location || 'MAIN',
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
        id, material_barcode, movement_type, qty, from_location_id, to_location_id,
        reason_code, reference_type, reference_id, actor, lot_code, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        movementId,
        material.barcode,
        movementType,
        qty,
        fromLocationId,
        toLocationId,
        String(payload?.reasonCode || '').trim() || null,
        String(payload?.referenceType || '').trim() || null,
        String(payload?.referenceId || '').trim() || null,
        actor,
        lotCode,
        now,
      ],
    );

    await recomputeMaterialInventorySummary(material.barcode, now);
    await logMaterialActivity({
      barcode: material.barcode,
      type: movementType,
      label: 'Inventory movement posted',
      description: `${movementType} ${qty.toFixed(2)} ${material.unit || 'units'}.`,
      actor,
      createdAt: now,
    });
    await run('COMMIT');
  } catch (error) {
    await run('ROLLBACK');
    throw error;
  }

  return getMaterialControlTowerDetail(material.barcode);
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
    ? `100 ${String(parent.unit || '').trim()}`
    : '100 Pieces';

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

  await upsertInventoryStockPosition({
    materialBarcode: childBarcode,
    locationId: String(parent.location || '').trim() || 'MAIN',
    lotCode: childBarcode,
    unitId: parent.unit_id || null,
    onHandDelta: 100,
    now: createdAt,
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
      ? `${Math.max(Number(existing.number_of_children || 0), 1) * 100} ${resolvedUnit.unit}`
      : `${Math.max(Number(existing.number_of_children || 0), 1) * 100} Pieces`
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
    'UPDATE materials SET linked_group_id = ?, linked_item_id = NULL, updated_at = ? WHERE id = ?',
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

async function linkMaterialRecordToItem(barcode, itemId) {
  const existing = await getMaterialRowByBarcode(barcode);
  if (!existing) {
    throw new Error('Material not found.');
  }
  const item = await getItemRowById(Number(itemId));
  if (!item || item.is_archived) {
    throw new Error('Selected item is not available.');
  }
  await run(
    'UPDATE materials SET linked_group_id = NULL, linked_item_id = ?, updated_at = ? WHERE id = ?',
    [item.id, new Date().toISOString(), existing.id],
  );
  await logMaterialActivity({
    barcode: existing.barcode,
    type: 'linked',
    label: 'Inheritance linked',
    description: `Linked to item ${item.display_name || item.name || item.id}.`,
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
    'UPDATE materials SET linked_group_id = NULL, linked_item_id = NULL, updated_at = ? WHERE id = ?',
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
    parent = await linkMaterialRecordToItem(parent.barcode, seed.linkItemId);
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
      name: 'Copper Master Roll',
      type: 'Raw Material',
      grade: 'A1',
      thickness: '1.2 mm',
      supplier: 'Shree Metals',
      unit: 'Kg',
      notes: 'Primary copper feed for dolly and frame jobs.',
      numberOfChildren: 3,
      scanCount: 5,
      childScanCounts: [3, 2, 1],
      createdAt: oneDayAgo(14),
      linkGroupId: groupByName.get('chemical')?.id || null,
    },
    {
      name: 'Steel Sheet Batch',
      type: 'Raw Material',
      grade: 'B2',
      thickness: '2.0 mm',
      supplier: 'Metro Steels',
      unit: 'Sheet',
      notes: 'Sheet stock for drilled frame support panels.',
      numberOfChildren: 2,
      scanCount: 4,
      childScanCounts: [2, 0],
      createdAt: oneDayAgo(12),
      linkItemId: itemByDisplayName.get(normalizeUnitValue('Flip-Top Cap - 500'))?.id || null,
    },
    {
      name: 'Kraft Paper Reel',
      type: 'Substrate',
      grade: 'Natural 180 GSM',
      thickness: '180 GSM',
      supplier: 'West Coast Paper',
      unit: 'Roll',
      notes: 'Used across bottle carton and mono-carton demo orders.',
      numberOfChildren: 4,
      scanCount: 9,
      childScanCounts: [4, 3, 1, 1],
      createdAt: oneDayAgo(9),
      linkItemId: itemByDisplayName.get(normalizeUnitValue('Bottle Carton - 100'))?.id || null,
    },
    {
      name: 'Shrink Film Reel',
      type: 'Packaging Material',
      grade: 'PET-G',
      thickness: '40 micron',
      supplier: 'FlexWrap Industries',
      unit: 'Roll',
      notes: 'Supports export sleeve jobs and barcode attachment demos.',
      numberOfChildren: 3,
      scanCount: 6,
      childScanCounts: [2, 2, 1],
      createdAt: oneDayAgo(7),
      linkItemId: itemByDisplayName.get(normalizeUnitValue('Printed Sleeve - 200'))?.id || null,
    },
  ];

  for (const material of materials) {
    await ensureParentMaterialRecord(material);
  }
}

async function createRunFromTemplate(templateId, name) {
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
      node_status_json, started_at, completed_at, created_at
    ) VALUES (?, ?, ?, ?, 'planned', ?, ?, NULL, NULL, ?)
    `,
    [
      runId,
      template.id,
      template.version,
      name || `Run ${new Date(now).toLocaleDateString('en-IN')}`,
      JSON.stringify({
        actualDurationHoursByNode: {},
        batchQuantityByNode: {},
        machineOverrideByNode: {},
      }),
      JSON.stringify(nodeStatuses),
      now,
    ],
  );

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
    const user = await get('SELECT * FROM users WHERE email = ?', [email]);
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
    if (!user || Number(user.is_active || 0) !== 1 || !verifyPassword(password, user.password_hash)) {
      await registerLoginFailure({ user, email, req });
      res.status(401).json({ success: false, user: null, token: null, error: 'Invalid email or password.' });
      return;
    }
    const permissionMap = await getEffectivePermissionMap(user.id, user.role);
    const safeUser = safeUserDto(user, permissionMap);
    const { token } = await createAuthSession({ user, req });
    res.json({ success: true, user: safeUser, token, error: null });
  } catch (error) {
    res.status(500).json({ success: false, user: null, token: null, error: error.message });
  }
});

app.use('/api', requireAuth);
app.use('/api', requireApiWritePermission);

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
    const passwordError = validatePasswordPolicy(nextPassword, { email: user.email });
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
      whereClauses.push('(LOWER(name) LIKE ? OR LOWER(email) LIKE ?)');
      params.push(`%${queryText}%`, `%${queryText}%`);
    }
    if (USER_ROLES.has(role)) {
      whereClauses.push('role = ?');
      params.push(role);
    }
    if (isActiveRaw === 'true' || isActiveRaw === 'false') {
      whereClauses.push('is_active = ?');
      params.push(isActiveRaw === 'true' ? 1 : 0);
    }
    if (req.user.role === 'admin') {
      whereClauses.push('(role = ? OR id = ?)');
      params.push('user', req.user.id);
    }
    const whereSql = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';
    const { limit, offset } = parsePagination(req.query, { defaultLimit: 25, maxLimit: 100 });
    const countRow = await get(`SELECT COUNT(*) AS count FROM users ${whereSql}`, params);
    const total = Number(countRow?.count || 0);
    const rows = await all(
      `
      SELECT *
      FROM users
      ${whereSql}
      ORDER BY role ASC, name ASC
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

app.patch('/api/users/:id/password', requirePermission('users.reset_password'), async (req, res) => {
  try {
    const targetId = Number(req.params.id);
    const target = await get('SELECT * FROM users WHERE id = ?', [targetId]);
    if (!target) {
      res.status(404).json({ success: false, error: 'User not found.' });
      return;
    }
    if (req.user.role === 'admin' && target.role !== 'user') {
      res.status(403).json({ success: false, error: 'Admins can reset user passwords only.' });
      return;
    }
    const newPassword = String(req.body?.newPassword || req.body?.password || '');
    const passwordError = validatePasswordPolicy(newPassword, { email: target.email });
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
    if (req.user.role === 'admin' && target.role !== 'user') {
      res.status(403).json({ success: false, user: null, error: 'Admins can update user accounts only.' });
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

app.post('/api/delete-requests', requirePermission('inventory.request_delete'), async (req, res) => {
  try {
    const entityType = String(req.body?.entityType || '').trim();
    const entityId = String(req.body?.entityId || '').trim();
    const entityLabel = String(req.body?.entityLabel || '').trim();
    const reason = String(req.body?.reason || '').trim();
    if (!entityType || !entityId) {
      res.status(400).json({ success: false, request: null, error: 'entityType and entityId are required.' });
      return;
    }
    if (entityType !== 'material') {
      res.status(400).json({ success: false, request: null, error: 'Only material delete requests are supported in v1.' });
      return;
    }
    const now = new Date().toISOString();
    const result = await run(
      `
      INSERT INTO delete_requests (
        entity_type, entity_id, entity_label, reason, status, requested_by_user_id, created_at
      ) VALUES (?, ?, ?, ?, 'pending', ?, ?)
      `,
      [entityType, entityId, entityLabel, reason, req.user.id, now],
    );
    const row = await getDeleteRequestById(result.lastID);
    await logAuthEvent({
      eventType: 'delete_request_created',
      actorUserId: req.user.id,
      targetUserId: req.user.id,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { entityType, entityId },
    });
    res.status(201).json({ success: true, request: rowToDeleteRequestDto(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, request: null, error: error.message });
  }
});

app.get('/api/delete-requests', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const status = String(req.query.status || '').trim();
    const requesterId = Number(req.query.requestedByUserId || 0);
    const from = normalizeNullableDate(req.query.from);
    const to = normalizeNullableDate(req.query.to);
    const { limit, offset } = parsePagination(req.query, {
      defaultLimit: 25,
      maxLimit: 100,
    });
    const params = [];
    const whereClauses = [];
    if (status) {
      whereClauses.push('dr.status = ?');
      params.push(status);
    }
    if (requesterId > 0) {
      whereClauses.push('dr.requested_by_user_id = ?');
      params.push(requesterId);
    }
    if (from) {
      whereClauses.push('datetime(dr.created_at) >= datetime(?)');
      params.push(from);
    }
    if (to) {
      whereClauses.push('datetime(dr.created_at) <= datetime(?)');
      params.push(to);
    }
    const where = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';
    const countRow = await get(
      `SELECT COUNT(*) AS count FROM delete_requests dr ${where}`,
      params,
    );
    const total = Number(countRow?.count || 0);
    const rows = await all(
      `
      SELECT
        dr.*,
        requester.name AS requested_by_name,
        reviewer.name AS reviewed_by_name
      FROM delete_requests dr
      LEFT JOIN users requester ON requester.id = dr.requested_by_user_id
      LEFT JOIN users reviewer ON reviewer.id = dr.reviewed_by_user_id
      ${where}
      ORDER BY dr.created_at DESC
      LIMIT ? OFFSET ?
      `,
      [...params, limit, offset],
    );
    res.json({
      success: true,
      requests: rows.map(rowToDeleteRequestDto),
      pagination: {
        total,
        limit,
        offset,
        hasMore: offset + rows.length < total,
      },
      error: null,
    });
  } catch (error) {
    res.status(500).json({ success: false, requests: [], error: error.message });
  }
});

app.post('/api/delete-requests/:id/approve', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const request = await getDeleteRequestById(Number(req.params.id));
    if (!request) {
      res.status(404).json({ success: false, request: null, error: 'Delete request not found.' });
      return;
    }
    if (request.status !== 'pending') {
      res.status(409).json({ success: false, request: rowToDeleteRequestDto(request), error: 'Delete request has already been reviewed.' });
      return;
    }
    if (request.entity_type !== 'material') {
      res.status(400).json({ success: false, request: null, error: 'Unsupported delete request type.' });
      return;
    }
    await deleteMaterialRecord(request.entity_id, currentActor(req));
    const reviewedNote = String(req.body?.reviewedNote || '').trim();
    await run('UPDATE delete_requests SET status = ?, reviewed_by_user_id = ?, reviewed_note = ?, reviewed_at = ? WHERE id = ?', [
      'approved',
      req.user.id,
      reviewedNote,
      new Date().toISOString(),
      request.id,
    ]);
    const updated = await getDeleteRequestById(request.id);
    await logAuthEvent({
      eventType: 'delete_request_approved',
      actorUserId: req.user.id,
      targetUserId: request.requested_by_user_id || null,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { requestId: request.id, entityType: request.entity_type, entityId: request.entity_id, reviewedNote },
    });
    res.json({ success: true, request: rowToDeleteRequestDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, request: null, error: error.message });
  }
});

app.post('/api/delete-requests/:id/reject', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const request = await getDeleteRequestById(Number(req.params.id));
    if (!request) {
      res.status(404).json({ success: false, request: null, error: 'Delete request not found.' });
      return;
    }
    if (request.status !== 'pending') {
      res.status(409).json({ success: false, request: rowToDeleteRequestDto(request), error: 'Delete request has already been reviewed.' });
      return;
    }
    const reviewedNote = String(req.body?.reviewedNote || '').trim();
    await run('UPDATE delete_requests SET status = ?, reviewed_by_user_id = ?, reviewed_note = ?, reviewed_at = ? WHERE id = ?', [
      'rejected',
      req.user.id,
      reviewedNote,
      new Date().toISOString(),
      request.id,
    ]);
    const updated = await getDeleteRequestById(request.id);
    await logAuthEvent({
      eventType: 'delete_request_rejected',
      actorUserId: req.user.id,
      targetUserId: request.requested_by_user_id || null,
      ipAddress: getRequestIp(req),
      userAgent: getRequestUserAgent(req),
      metadata: { requestId: request.id, entityType: request.entity_type, entityId: request.entity_id, reviewedNote },
    });
    res.json({ success: true, request: rowToDeleteRequestDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, request: null, error: error.message });
  }
});

app.get('/api/delete-requests/export', requirePermission('audit.read'), async (_req, res) => {
  try {
    const rows = await all(
      `
      SELECT
        dr.*,
        requester.name AS requested_by_name,
        reviewer.name AS reviewed_by_name
      FROM delete_requests dr
      LEFT JOIN users requester ON requester.id = dr.requested_by_user_id
      LEFT JOIN users reviewer ON reviewer.id = dr.reviewed_by_user_id
      ORDER BY datetime(dr.created_at) DESC
      LIMIT 5000
      `,
    );
    const csv = toCsv(
      [
        'id',
        'created_at',
        'status',
        'entity_type',
        'entity_id',
        'entity_label',
        'reason',
        'requested_by_user_id',
        'requested_by_name',
        'reviewed_by_user_id',
        'reviewed_by_name',
        'reviewed_note',
        'reviewed_at',
      ],
      rows.map((row) => [
        row.id,
        row.created_at,
        row.status,
        row.entity_type,
        row.entity_id,
        row.entity_label || '',
        row.reason || '',
        row.requested_by_user_id || '',
        row.requested_by_name || '',
        row.reviewed_by_user_id || '',
        row.reviewed_by_name || '',
        row.reviewed_note || '',
        row.reviewed_at || '',
      ]),
    );
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="delete-requests-${new Date().toISOString().slice(0, 10)}.csv"`,
    );
    res.status(200).send(csv);
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
    res.status(500).json({ success: false, material: null, error: error.message });
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
    const unit = await saveUnit({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, unit: rowToUnitDto(unit), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      unit: null,
      error: error.message,
    });
  }
});

app.patch('/api/units/:id/archive', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getUnitRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, unit: null, error: 'Unit not found.' });
      return;
    }
    await run('UPDATE units SET is_archived = 1, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getUnitRowById(id);
    res.json({ success: true, unit: rowToUnitDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, unit: null, error: error.message });
  }
});

app.patch('/api/units/:id/restore', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getUnitRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, unit: null, error: 'Unit not found.' });
      return;
    }
    await run('UPDATE units SET is_archived = 0, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getUnitRowById(id);
    res.json({ success: true, unit: rowToUnitDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, unit: null, error: error.message });
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
    const order = await saveOrder(req.body || {});
    res.status(201).json({ success: true, order: rowToOrderDto(order), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      order: null,
      error: error.message,
    });
  }
});

app.patch('/api/orders/:id/lifecycle', requirePermission('config.write'), async (req, res) => {
  try {
    const order = await updateOrderLifecycle({
      ...(req.body || {}),
      id: Number(req.params.id),
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

app.post('/api/clients', requirePermission('config.write'), async (req, res) => {
  try {
    const client = await saveClient(req.body || {});
    res.status(201).json({ success: true, client: rowToClientDto(client), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      client: null,
      error: error.message,
    });
  }
});

app.patch('/api/clients/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const client = await saveClient({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, client: rowToClientDto(client), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      client: null,
      error: error.message,
    });
  }
});

app.patch('/api/clients/:id/archive', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getClientRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, client: null, error: 'Client not found.' });
      return;
    }
    await run('UPDATE clients SET is_archived = 1, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getClientRowById(id);
    res.json({ success: true, client: rowToClientDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, client: null, error: error.message });
  }
});

app.patch('/api/clients/:id/restore', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getClientRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, client: null, error: 'Client not found.' });
      return;
    }
    await run('UPDATE clients SET is_archived = 0, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getClientRowById(id);
    res.json({ success: true, client: rowToClientDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, client: null, error: error.message });
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

app.post('/api/items', requirePermission('config.write'), async (req, res) => {
  try {
    const item = await saveItem(req.body || {});
    res.status(201).json({ success: true, item: await rowToItemDto(item), error: null });
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
    const item = await saveItem({
      ...(req.body || {}),
      id: Number(req.params.id),
    });
    res.json({ success: true, item: await rowToItemDto(item), error: null });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      item: null,
      error: error.message,
    });
  }
});

app.patch('/api/items/:id/archive', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getItemRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, item: null, error: 'Item not found.' });
      return;
    }
    const now = new Date().toISOString();
    await run('UPDATE items SET is_archived = 1, updated_at = ? WHERE id = ?', [now, id]);
    await run('UPDATE item_variation_nodes SET is_archived = 1, updated_at = ? WHERE item_id = ?', [now, id]);
    const updated = await getItemRowById(id);
    res.json({ success: true, item: await rowToItemDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, item: null, error: error.message });
  }
});

app.patch('/api/items/:id/restore', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getItemRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, item: null, error: 'Item not found.' });
      return;
    }
    const now = new Date().toISOString();
    await run('UPDATE items SET is_archived = 0, updated_at = ? WHERE id = ?', [now, id]);
    await run('UPDATE item_variation_nodes SET is_archived = 0, updated_at = ? WHERE item_id = ?', [now, id]);
    const updated = await getItemRowById(id);
    res.json({ success: true, item: await rowToItemDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, item: null, error: error.message });
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

app.patch('/api/groups/:id/archive', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getGroupRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, group: null, error: 'Group not found.' });
      return;
    }
    const activeChildren = await getActiveChildGroups(id);
    if (activeChildren.length > 0) {
      res.status(409).json({
        success: false,
        group: null,
        error: 'This group has active child groups. Reassign or archive them first.',
      });
      return;
    }
    await run('UPDATE groups SET is_archived = 1, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getGroupRowById(id);
    res.json({ success: true, group: rowToGroupDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, group: null, error: error.message });
  }
});

app.patch('/api/groups/:id/restore', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await getGroupRowById(id);
    if (!existing) {
      res.status(404).json({ success: false, group: null, error: 'Group not found.' });
      return;
    }
    await run('UPDATE groups SET is_archived = 0, updated_at = ? WHERE id = ?', [
      new Date().toISOString(),
      id,
    ]);
    const updated = await getGroupRowById(id);
    res.json({ success: true, group: rowToGroupDto(updated), error: null });
  } catch (error) {
    res.status(500).json({ success: false, group: null, error: error.message });
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
    res.status(500).json({ success: false, material: null, error: error.message });
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
    res.status(500).json({ success: false, material: null, error: error.message });
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
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/link-item', requirePermission('inventory.update'), async (req, res) => {
  try {
    const material = await linkMaterialRecordToItem(
      req.params.barcode,
      req.body?.itemId,
    );
    res.json({ success: true, material: rowToMaterialDto(material), error: null });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
  }
});

app.patch('/api/materials/:barcode/unlink', requirePermission('inventory.update'), async (req, res) => {
  try {
    const material = await unlinkMaterialRecord(req.params.barcode);
    res.json({ success: true, material: rowToMaterialDto(material), error: null });
  } catch (error) {
    res.status(500).json({ success: false, material: null, error: error.message });
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
        id, name, description, version, status, stage_labels_json, lane_labels_json,
        nodes_json, flows_json, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
      [
        payload.id,
        payload.name,
        payload.description || '',
        1,
        payload.status || 'draft',
        JSON.stringify(payload.stageLabels || []),
        JSON.stringify(payload.laneLabels || []),
        JSON.stringify(payload.nodes || []),
        JSON.stringify(payload.flows || []),
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
      SET name = ?, description = ?, version = ?, status = ?, stage_labels_json = ?,
          lane_labels_json = ?, nodes_json = ?, flows_json = ?, updated_at = ?
      WHERE id = ?
      `,
      [
        payload.name || existing.name,
        payload.description || existing.description || '',
        nextVersion,
        payload.status || existing.status || 'draft',
        JSON.stringify(payload.stageLabels || parseJson(existing.stage_labels_json, [])),
        JSON.stringify(payload.laneLabels || parseJson(existing.lane_labels_json, [])),
        JSON.stringify(payload.nodes || parseJson(existing.nodes_json, [])),
        JSON.stringify(payload.flows || parseJson(existing.flows_json, [])),
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
    const { templateId, name } = req.body || {};
    if (!templateId) {
      res.status(400).json({
        success: false,
        run: null,
        error: 'templateId is required.',
      });
      return;
    }
    const run = await createRunFromTemplate(templateId, name);
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
        }),
        new Date().toISOString(),
      ],
    );

    const updatedRunRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [
      req.params.id,
    ]);
    res.json({ success: true, run: await rowToRun(updatedRunRow) });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.use((error, _req, res, _next) => {
  console.error('Request failed:', error);
  res.status(error.statusCode || 500).json({
    success: false,
    error: IS_PRODUCTION ? 'Request failed.' : error.message,
  });
});

async function resetAndSeedDemoData() {
  await initDb();
  await run('DELETE FROM run_barcode_inputs');
  await run('DELETE FROM pipeline_runs');
  await run('DELETE FROM pipeline_templates');
  await run('DELETE FROM orders');
  await run('DELETE FROM item_variation_values');
  await run('DELETE FROM item_variations');
  await run('DELETE FROM item_variation_dimensions');
  await run('DELETE FROM item_variation_nodes');
  await run('DELETE FROM items');
  await run('DELETE FROM clients');
  await run('DELETE FROM material_group_item_links');
  await run('DELETE FROM material_group_properties');
  await run('DELETE FROM material_group_units');
  await run('DELETE FROM material_group_preferences');
  await run('DELETE FROM inventory_stock_positions');
  await run('DELETE FROM inventory_movements');
  await run('DELETE FROM inventory_reservations');
  await run('DELETE FROM inventory_alerts');
  await run('DELETE FROM materials');
  await run('DELETE FROM groups');
  await run('DELETE FROM units');
  await seedMaterialsIfEmpty();
  await seedUnitsIfEmpty();
  await bootstrapUnitsFromMaterials();
  await backfillMaterialUnitIds();
  await seedClientsIfEmpty();
  await seedGroupsIfEmpty();
  await seedItemsIfEmpty();
  await seedOrdersIfEmpty();
  await seedTemplatesIfEmpty();
  await ensureDemoDataset();
}

function startServer() {
  console.log(`Booting Paper backend on port ${PORT} using ${DB_PATH}`);
  return new Promise((resolve, reject) => {
    const server = app.listen(PORT, '0.0.0.0', () => {
      console.log(`Paper backend listening on port ${PORT}`);
      console.log('Initializing database schema...');
      initDb()
        .then(() => {
          dbReady = true;
          console.log('Database schema ready.');
          console.log(`Paper backend running on port ${PORT} using ${DB_PATH}`);
        })
        .catch((error) => {
          dbInitError = error;
          console.error('Failed to initialize backend database:', error);
        });
      resolve(server);
    });
    server.on('error', reject);
  });
}

if (require.main === module) {
  startServer().catch((error) => {
    console.error('Failed to initialize backend:', error);
    process.exit(1);
  });
}

module.exports = {
  app,
  initDb,
  startServer,
  closeDb,
  all,
  get,
  run,
  saveUnit,
  saveClient,
  saveItem,
  saveOrder,
  ensureMockOrdersPresent,
  ensureDemoDataset,
  resetAndSeedDemoData,
  updateOrderLifecycle,
  getOrders,
  getUnitsWithUsage,
  getGroupsWithUsage,
  getClientsWithUsage,
  getItemsWithUsage,
  createParentWithChildren,
  getMaterialRowByBarcode,
  getMaterialGroupGovernance,
  updateMaterialGroupConfiguration,
  rowToClientDto,
  rowToOrderDto,
  rowToItemDto,
};
