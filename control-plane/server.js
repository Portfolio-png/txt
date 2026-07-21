'use strict';

// ============================================================================
// Paper Control Plane + Falcon View
// ----------------------------------------------------------------------------
// A vendor-side service (runs on ONE vendor-owned AWS box, separate from any
// client deployment). Each client deployment's backend pushes a periodic
// telemetry snapshot here — business KPIs plus its user roster — over an
// authenticated endpoint. The Falcon View dashboard renders the whole fleet:
// cross-client benchmarks and every user from staff to admin.
//
// IMPORTANT (disclosure): the data collected here — business aggregates and the
// user roster — is a MANAGED-SERVICE / BENCHMARKING feature. It must be
// disclosed to each client in the contract / DPA and, where PII is involved,
// consented. Do not run this against a client who has not agreed. See README.
// ============================================================================

const express = require('express');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();

const PORT = Number(process.env.CONTROL_PLANE_PORT || 19090);
const DB_PATH = process.env.CONTROL_PLANE_DB || path.join(__dirname, 'control_plane.db');
// Vendor dashboard auth (HTTP Basic). CHANGE THIS via env in production.
const DASH_USER = process.env.FALCON_USER || 'vendor';
const DASH_PASS = process.env.FALCON_PASSWORD || 'change-me';
// Optional allow-list of deployment keys. If empty, trust-on-first-use: the
// first snapshot from a key registers that deployment (fine for a small fleet).
const ALLOWED_KEYS = String(process.env.DEPLOYMENT_KEYS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

const db = new sqlite3.Database(DB_PATH);
const run = (sql, p = []) =>
  new Promise((res, rej) => db.run(sql, p, function (e) { e ? rej(e) : res(this); }));
const all = (sql, p = []) =>
  new Promise((res, rej) => db.all(sql, p, (e, r) => (e ? rej(e) : res(r))));
const get = (sql, p = []) =>
  new Promise((res, rej) => db.get(sql, p, (e, r) => (e ? rej(e) : res(r))));

async function initDb() {
  await run(`CREATE TABLE IF NOT EXISTS deployments (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL DEFAULT '',
    api_key TEXT NOT NULL,
    app_version TEXT DEFAULT '',
    first_seen TEXT NOT NULL,
    last_seen TEXT NOT NULL
  )`);
  await run(`CREATE TABLE IF NOT EXISTS snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    deployment_id TEXT NOT NULL,
    captured_at TEXT NOT NULL,
    received_at TEXT NOT NULL,
    metrics_json TEXT NOT NULL DEFAULT '{}'
  )`);
  await run('CREATE INDEX IF NOT EXISTS idx_snap_dep ON snapshots(deployment_id, captured_at)');
  await run(`CREATE TABLE IF NOT EXISTS users_seen (
    deployment_id TEXT NOT NULL,
    user_id INTEGER NOT NULL,
    name TEXT DEFAULT '',
    email TEXT DEFAULT '',
    role TEXT DEFAULT '',
    is_active INTEGER DEFAULT 1,
    last_login TEXT DEFAULT '',
    last_seen TEXT NOT NULL,
    PRIMARY KEY (deployment_id, user_id)
  )`);
  // Vendor-issued commands a deployment pulls and applies (e.g. provision an
  // admin login). The deployment polls pending rows, applies them, then acks.
  await run(`CREATE TABLE IF NOT EXISTS deployment_commands (
    id TEXT PRIMARY KEY,
    deployment_id TEXT NOT NULL,
    type TEXT NOT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending',
    result TEXT DEFAULT '',
    issued_by TEXT DEFAULT '',
    created_at TEXT NOT NULL,
    applied_at TEXT
  )`);
  await run('CREATE INDEX IF NOT EXISTS idx_cmd_dep_status ON deployment_commands(deployment_id, status)');
}

const app = express();
app.use(express.json({ limit: '2mb' }));

// ---- Ingest (called by each client deployment) -----------------------------
app.post('/api/ingest', async (req, res) => {
  try {
    const key = String(req.header('x-deployment-key') || '').trim();
    if (!key) return res.status(401).json({ success: false, error: 'Missing deployment key.' });
    if (ALLOWED_KEYS.length && !ALLOWED_KEYS.includes(key)) {
      return res.status(403).json({ success: false, error: 'Unknown deployment key.' });
    }
    const body = req.body || {};
    const deploymentId = String(body.deploymentId || '').trim();
    if (!deploymentId) return res.status(400).json({ success: false, error: 'deploymentId required.' });

    const now = new Date().toISOString();
    const capturedAt = String(body.capturedAt || now);
    const name = String(body.deploymentName || deploymentId);
    const appVersion = String(body.appVersion || '');

    const existing = await get('SELECT id FROM deployments WHERE id = ?', [deploymentId]);
    if (existing) {
      await run(
        'UPDATE deployments SET name = ?, api_key = ?, app_version = ?, last_seen = ? WHERE id = ?',
        [name, key, appVersion, now, deploymentId],
      );
    } else {
      await run(
        'INSERT INTO deployments (id, name, api_key, app_version, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?)',
        [deploymentId, name, key, appVersion, now, now],
      );
    }

    await run(
      'INSERT INTO snapshots (deployment_id, captured_at, received_at, metrics_json) VALUES (?, ?, ?, ?)',
      [deploymentId, capturedAt, now, JSON.stringify(body.metrics || {})],
    );

    const users = Array.isArray(body.users) ? body.users : [];
    for (const u of users) {
      const uid = Number(u.id);
      if (!Number.isFinite(uid)) continue;
      await run(
        `INSERT INTO users_seen (deployment_id, user_id, name, email, role, is_active, last_login, last_seen)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(deployment_id, user_id) DO UPDATE SET
           name = excluded.name, email = excluded.email, role = excluded.role,
           is_active = excluded.is_active, last_login = excluded.last_login, last_seen = excluded.last_seen`,
        [deploymentId, uid, String(u.name || ''), String(u.email || ''), String(u.role || ''),
         u.isActive === false ? 0 : 1, String(u.lastLogin || ''), now],
      );
    }
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ---- Deployment-key auth (client deployments) ------------------------------
async function requireDeploymentKey(req, res, next) {
  try {
    const key = String(req.header('x-deployment-key') || '').trim();
    if (!key) return res.status(401).json({ success: false, error: 'Missing deployment key.' });
    if (ALLOWED_KEYS.length && !ALLOWED_KEYS.includes(key)) {
      return res.status(403).json({ success: false, error: 'Unknown deployment key.' });
    }
    const dep = await get('SELECT * FROM deployments WHERE api_key = ?', [key]);
    if (!dep) {
      return res.status(404).json({ success: false, error: 'Deployment not registered yet — send a snapshot first.' });
    }
    req.deployment = dep;
    next();
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
}

function newCommandId() {
  return 'cmd-' + Date.now() + '-' + Math.floor(Math.random() * 1e6);
}

// Vendor enqueues a command for a deployment (dashboard-authed). Today the only
// type is create_admin — provision an admin login on that client's app.
app.post('/api/deployments/:id/commands', requireDash, async (req, res) => {
  try {
    const depId = String(req.params.id);
    const dep = await get('SELECT id FROM deployments WHERE id = ?', [depId]);
    if (!dep) return res.status(404).json({ success: false, error: 'Deployment not found.' });
    const type = String(req.body?.type || '').trim();
    const payload = req.body?.payload || {};
    if (type !== 'create_admin') {
      return res.status(400).json({ success: false, error: 'Unsupported command type.' });
    }
    if (!payload.email || !payload.password) {
      return res.status(400).json({ success: false, error: 'email and password are required.' });
    }
    const id = newCommandId();
    await run(
      'INSERT INTO deployment_commands (id, deployment_id, type, payload_json, status, issued_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, depId, type, JSON.stringify(payload), 'pending', DASH_USER, new Date().toISOString()],
    );
    res.status(201).json({ success: true, id, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// A deployment pulls its pending commands.
app.get('/api/commands', requireDeploymentKey, async (req, res) => {
  try {
    const rows = await all(
      "SELECT id, type, payload_json FROM deployment_commands WHERE deployment_id = ? AND status = 'pending' ORDER BY created_at ASC",
      [req.deployment.id],
    );
    const commands = rows.map((r) => {
      let payload = {};
      try { payload = JSON.parse(r.payload_json); } catch (_) { payload = {}; }
      return { id: r.id, type: r.type, payload };
    });
    res.json({ success: true, commands, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// A deployment acks a command it applied (or failed). Sensitive fields (the
// password) are scrubbed from the stored payload once applied.
app.post('/api/commands/:id/ack', requireDeploymentKey, async (req, res) => {
  try {
    const id = String(req.params.id);
    const cmd = await get('SELECT * FROM deployment_commands WHERE id = ? AND deployment_id = ?', [id, req.deployment.id]);
    if (!cmd) return res.status(404).json({ success: false, error: 'Command not found.' });
    const status = req.body?.status === 'failed' ? 'failed' : 'done';
    const result = String(req.body?.result || '').slice(0, 500);
    let scrubbed = cmd.payload_json;
    try {
      const p = JSON.parse(cmd.payload_json);
      if (p.password) p.password = '***';
      scrubbed = JSON.stringify(p);
    } catch (_) { /* keep as-is */ }
    await run(
      'UPDATE deployment_commands SET status = ?, result = ?, payload_json = ?, applied_at = ? WHERE id = ?',
      [status, result, scrubbed, new Date().toISOString(), id],
    );
    res.json({ success: true, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ---- Dashboard auth (HTTP Basic) -------------------------------------------
function requireDash(req, res, next) {
  const hdr = req.header('authorization') || '';
  const m = hdr.match(/^Basic (.+)$/);
  if (m) {
    const [u, p] = Buffer.from(m[1], 'base64').toString('utf8').split(':');
    if (u === DASH_USER && p === DASH_PASS) return next();
  }
  res.set('WWW-Authenticate', 'Basic realm="Falcon View"');
  return res.status(401).send('Authentication required.');
}

// ---- Falcon View data ------------------------------------------------------
const KPI_KEYS = [
  { key: 'orders', label: 'Orders' },
  { key: 'ordersOpen', label: 'Open orders' },
  { key: 'challans', label: 'Challans' },
  { key: 'items', label: 'Items' },
  { key: 'inventoryOnHand', label: 'On-hand qty' },
  { key: 'productionRuns', label: 'Prod. runs' },
  { key: 'clients', label: 'Clients' },
  { key: 'activeUsers', label: 'Active users' },
];

async function loadFleet() {
  const deployments = await all('SELECT * FROM deployments ORDER BY name');
  const rows = [];
  for (const d of deployments) {
    const snap = await get(
      'SELECT metrics_json, captured_at FROM snapshots WHERE deployment_id = ? ORDER BY captured_at DESC LIMIT 1',
      [d.id],
    );
    let metrics = {};
    try { metrics = snap ? JSON.parse(snap.metrics_json) : {}; } catch (_) { metrics = {}; }
    // Orders series (oldest -> newest) from snapshot history, for a trend line.
    const hist = await all(
      'SELECT metrics_json FROM snapshots WHERE deployment_id = ? ORDER BY captured_at ASC LIMIT 60',
      [d.id],
    );
    const ordersSeries = hist.map((h) => {
      try { return Number(JSON.parse(h.metrics_json).orders) || 0; } catch (_) { return 0; }
    });
    rows.push({ ...d, capturedAt: snap ? snap.captured_at : null, metrics, ordersSeries, snapshotCount: hist.length });
  }
  const users = await all('SELECT * FROM users_seen ORDER BY role DESC, name');
  const commands = await all(
    'SELECT * FROM deployment_commands ORDER BY created_at DESC LIMIT 25',
  );
  return { rows, users, commands };
}

// Tiny inline-SVG sparkline for a numeric series (self-contained, CSP-safe).
function sparkline(values, w = 130, h = 26) {
  const v = (values || []).filter((n) => Number.isFinite(n));
  if (v.length < 2) return '<span class="sub">—</span>';
  const min = Math.min(...v);
  const max = Math.max(...v);
  const range = max - min || 1;
  const step = w / (v.length - 1);
  const pts = v
    .map((n, i) => `${(i * step).toFixed(1)},${(h - ((n - min) / range) * (h - 4) - 2).toFixed(1)}`)
    .join(' ');
  const up = v[v.length - 1] >= v[0];
  const color = up ? 'var(--ok)' : 'var(--off)';
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true">`
    + `<polyline fill="none" stroke="${color}" stroke-width="1.5" points="${pts}"/></svg>`;
}

function median(nums) {
  const a = nums.filter((n) => Number.isFinite(n)).sort((x, y) => x - y);
  if (!a.length) return 0;
  const mid = Math.floor(a.length / 2);
  return a.length % 2 ? a[mid] : (a[mid - 1] + a[mid]) / 2;
}

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function renderDashboard({ rows, users, commands = [] }) {
  const kpiCols = KPI_KEYS.map((k) => `<th>${esc(k.label)}</th>`).join('');

  const depOptions = rows
    .map((d) => `<option value="${esc(d.id)}">${esc(d.name)} (${esc(d.id)})</option>`)
    .join('');
  const cmdRows = commands.map((c) => {
    let email = '';
    try { email = JSON.parse(c.payload_json).email || ''; } catch (_) { /* ignore */ }
    const badge = c.status === 'done' ? 'ok' : (c.status === 'failed' ? 'off' : 'pending');
    return `<tr>
      <td class="sub">${esc((c.created_at || '').replace('T', ' ').slice(0, 16))}</td>
      <td>${esc(deploymentName(rows, c.deployment_id))}</td>
      <td>${esc(c.type)}</td>
      <td class="sub">${esc(email)}</td>
      <td><span class="cmd-${badge}">${esc(c.status)}</span></td>
      <td class="sub">${esc(c.result || '')}</td>
    </tr>`;
  }).join('');
  const depRows = rows.map((d) => {
    const cells = KPI_KEYS.map((k) => `<td class="num">${esc(d.metrics[k.key] ?? '—')}</td>`).join('');
    const stale = d.capturedAt && (Date.now() - Date.parse(d.capturedAt)) > 36 * 3600 * 1000;
    return `<tr>
      <td><strong>${esc(d.name)}</strong><div class="sub">${esc(d.id)} · v${esc(d.app_version || '?')}</div></td>
      ${cells}
      <td>${sparkline(d.ordersSeries)}<div class="sub">${d.snapshotCount} pts</div></td>
      <td class="sub ${stale ? 'stale' : ''}">${d.capturedAt ? esc(d.capturedAt.replace('T', ' ').slice(0, 16)) : 'never'}</td>
    </tr>`;
  }).join('');

  const bench = KPI_KEYS.map((k) => {
    const vals = rows.map((d) => Number(d.metrics[k.key])).filter((n) => Number.isFinite(n));
    const total = vals.reduce((s, n) => s + n, 0);
    return `<tr><td>${esc(k.label)}</td><td class="num">${total}</td>
      <td class="num">${vals.length ? Math.min(...vals) : 0}</td>
      <td class="num">${median(vals)}</td>
      <td class="num">${vals.length ? Math.max(...vals) : 0}</td></tr>`;
  }).join('');

  const userRows = users.map((u) => `<tr data-s="${esc((u.name + ' ' + u.email + ' ' + u.role).toLowerCase())}">
    <td>${esc(u.name || '—')}</td>
    <td class="sub">${esc(u.email)}</td>
    <td><span class="role r-${esc(u.role)}">${esc(u.role || '?')}</span></td>
    <td>${u.is_active ? '<span class="ok">active</span>' : '<span class="off">disabled</span>'}</td>
    <td class="sub">${esc(deploymentName(rows, u.deployment_id))}</td>
    <td class="sub">${esc((u.last_login || '').replace('T', ' ').slice(0, 16) || '—')}</td>
  </tr>`).join('');

  const totalUsers = users.length;
  const totalDeployments = rows.length;
  const fleetOrders = rows.reduce((s, d) => s + (Number(d.metrics.orders) || 0), 0);

  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Falcon View — Fleet Control Plane</title>
  <style>
    :root{--bg:#0d1017;--panel:#151a24;--ink:#e8ecf4;--soft:#9aa4b8;--faint:#5c6678;--line:#232a38;--accent:#5b8cff;--ok:#37d39b;--off:#f0776a;--mono:ui-monospace,'SF Mono',Menlo,monospace}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;line-height:1.5}
    .wrap{max-width:1240px;margin:0 auto;padding:32px 24px 64px}
    h1{font-size:26px;margin:0 0 2px;letter-spacing:-.02em}.eyebrow{font-family:var(--mono);font-size:12px;letter-spacing:.16em;text-transform:uppercase;color:var(--accent)}
    .disc{margin:14px 0 24px;padding:10px 14px;border:1px solid var(--line);border-left:3px solid var(--accent);border-radius:0 10px 10px 0;color:var(--soft);font-size:12.5px;background:var(--panel)}
    .tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:26px}
    .tile{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:14px 16px}
    .tile .n{font-size:28px;font-weight:800;font-family:var(--mono)}.tile .l{color:var(--faint);font-size:12px;text-transform:uppercase;letter-spacing:.05em}
    h2{font-size:16px;margin:30px 0 10px;border-bottom:1px solid var(--line);padding-bottom:8px}
    .scroll{overflow-x:auto;border:1px solid var(--line);border-radius:12px;background:var(--panel)}
    table{border-collapse:collapse;width:100%;font-size:13px;min-width:640px}
    th{ text-align:left;color:var(--faint);font-size:11px;text-transform:uppercase;letter-spacing:.05em;padding:10px 12px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--panel)}
    td{padding:9px 12px;border-bottom:1px solid var(--line)}tr:last-child td{border-bottom:none}
    td.num,th.num{text-align:right;font-family:var(--mono);font-variant-numeric:tabular-nums}
    .sub{color:var(--faint);font-size:11.5px}.stale{color:var(--off)}
    .role{font-family:var(--mono);font-size:11px;padding:2px 7px;border-radius:5px;background:#1e2636;color:var(--soft)}
    .r-super_admin{background:#3a2740;color:#e6a3ff}.r-admin{background:#26344f;color:#8fb4ff}.r-user{background:#1e2a24;color:#7fe0b6}
    .ok{color:var(--ok)}.off{color:var(--off)}
    input{background:var(--panel);border:1px solid var(--line);color:var(--ink);border-radius:8px;padding:8px 12px;width:260px;font-size:13px;margin-bottom:10px}
    .provision{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
    .provision select,.provision input{margin-bottom:0}
    .provision select{background:var(--panel);border:1px solid var(--line);color:var(--ink);border-radius:8px;padding:8px 12px;font-size:13px}
    .provision button{background:var(--accent);color:#fff;border:none;border-radius:8px;padding:9px 16px;font-size:13px;font-weight:600;cursor:pointer}
    .cmd-ok{color:var(--ok);font-family:var(--mono);font-size:12px}
    .cmd-off{color:var(--off);font-family:var(--mono);font-size:12px}
    .cmd-pending{color:var(--faint);font-family:var(--mono);font-size:12px}
  </style></head><body><div class="wrap">
    <div class="eyebrow">Paper · Control Plane</div>
    <h1>Falcon View</h1>
    <div class="disc">Managed-service benchmarking data. Business aggregates and the user roster below are collected under the client agreement / DPA. Do not use for any purpose the client has not been told about.</div>
    <div class="tiles">
      <div class="tile"><div class="n">${totalDeployments}</div><div class="l">Deployments</div></div>
      <div class="tile"><div class="n">${totalUsers}</div><div class="l">Users (all roles)</div></div>
      <div class="tile"><div class="n">${fleetOrders}</div><div class="l">Fleet orders</div></div>
    </div>

    <h2>Deployments — latest snapshot</h2>
    <div class="scroll"><table><thead><tr><th>Client</th>${kpiCols}<th>Orders trend</th><th>Last seen</th></tr></thead><tbody>${depRows || '<tr><td colspan="12" class="sub">No deployments have reported yet.</td></tr>'}</tbody></table></div>

    <h2>Provision admin logins</h2>
    <p class="sub" style="margin:0 0 12px">Create a client's admin account here. It is queued and applied on that deployment's next check-in — you never log into the client app. Use TLS in production; the password is in transit until applied.</p>
    <div class="provision">
      <select id="pa-dep">${depOptions || '<option value="">No deployments yet</option>'}</select>
      <input id="pa-name" placeholder="Admin name (optional)">
      <input id="pa-email" placeholder="Admin email" type="email">
      <input id="pa-pass" placeholder="Temporary password" type="password">
      <button onclick="provisionAdmin()">Create admin</button>
      <span id="pa-msg" class="sub"></span>
    </div>
    <div class="scroll" style="margin-top:12px"><table><thead><tr><th>Issued</th><th>Deployment</th><th>Type</th><th>Email</th><th>Status</th><th>Result</th></tr></thead><tbody>${cmdRows || '<tr><td colspan="6" class="sub">No admin commands yet.</td></tr>'}</tbody></table></div>

    <h2>Benchmarks across the fleet</h2>
    <div class="scroll"><table><thead><tr><th>Metric</th><th class="num">Fleet total</th><th class="num">Min</th><th class="num">Median</th><th class="num">Max</th></tr></thead><tbody>${bench}</tbody></table></div>

    <h2>Every user — staff to admin (${totalUsers})</h2>
    <input id="uf" placeholder="Filter users by name, email, role…" oninput="filterUsers()">
    <div class="scroll"><table id="ut"><thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Status</th><th>Deployment</th><th>Last login</th></tr></thead><tbody>${userRows || '<tr><td colspan="6" class="sub">No users reported yet.</td></tr>'}</tbody></table></div>
  </div>
  <script>
    function filterUsers(){var q=document.getElementById('uf').value.toLowerCase();
      document.querySelectorAll('#ut tbody tr').forEach(function(r){r.style.display=(r.dataset.s||'').includes(q)?'':'none';});}
    async function provisionAdmin(){
      var dep=document.getElementById('pa-dep').value;
      var name=document.getElementById('pa-name').value;
      var email=document.getElementById('pa-email').value;
      var password=document.getElementById('pa-pass').value;
      var msg=document.getElementById('pa-msg');
      if(!dep||!email||!password){msg.textContent='Deployment, email and password are required.';return;}
      msg.textContent='Sending…';
      try{
        var r=await fetch('/api/deployments/'+encodeURIComponent(dep)+'/commands',{
          method:'POST',headers:{'content-type':'application/json'},
          body:JSON.stringify({type:'create_admin',payload:{name:name,email:email,password:password}})
        });
        var j=await r.json();
        if(j.success){msg.textContent='Queued — the deployment will create this admin on its next check-in.';setTimeout(function(){location.reload();},1200);}
        else{msg.textContent='Error: '+(j.error||r.status);}
      }catch(e){msg.textContent='Error: '+e.message;}
    }
  </script>
  </body></html>`;
}

function deploymentName(rows, id) {
  const d = rows.find((r) => r.id === id);
  return d ? d.name : id;
}

async function serveDashboard(_req, res) {
  try {
    const fleet = await loadFleet();
    res.set('content-type', 'text/html; charset=utf-8').send(renderDashboard(fleet));
  } catch (error) {
    res.status(500).send('Error: ' + esc(error.message));
  }
}
// The control-plane website. Reachable at http://<aws-ip>/ and /control-plane.
app.get('/', requireDash, serveDashboard);
app.get('/control-plane', requireDash, serveDashboard);

// JSON API (same data, for programmatic use / a future richer UI)
app.get('/api/fleet', requireDash, async (_req, res) => {
  try { res.json({ success: true, ...(await loadFleet()) }); }
  catch (error) { res.status(500).json({ success: false, error: error.message }); }
});

app.get('/healthz', (_req, res) => res.json({ ok: true }));

if (require.main === module) {
  initDb()
    .then(() => app.listen(PORT, () => {
      console.log(`Falcon View control plane on :${PORT} (db ${DB_PATH})`);
      if (DASH_PASS === 'change-me') console.warn('WARNING: set FALCON_PASSWORD before exposing this.');
    }))
    .catch((e) => { console.error('Control plane failed to start:', e); process.exit(1); });
}

module.exports = { app, initDb };
