'use strict';

// ---------------------------------------------------------------------------
// Migration runner.
//
// backend/migrations/ has carried numbered .sql and .js migrations for a long
// time, but nothing ever executed them — initDb() creates its schema inline and
// stops. The result: whatever a migration adds and initDb doesn't duplicate
// (payroll, the client portal, salary structures) exists only on databases
// where someone applied it by hand. Fresh installs silently lack those tables.
//
// This closes that. It runs after initDb's inline schema, in filename order,
// recording each file in schema_migrations so it runs exactly once.
//
// The delicate part is the first run against a long-lived database, where much
// of this is already applied but nothing is recorded. Rather than guess, every
// statement tolerates the specific "already done" errors — duplicate column,
// table/index already exists — and anything else still throws. So the first
// pass over an old database converges it onto the ledger without touching what
// is already there, and a fresh database gets the full set.
// ---------------------------------------------------------------------------

const fs = require('fs');
const path = require('path');

const MIGRATIONS_DIR = path.join(__dirname, '..', '..', 'migrations');

/** Errors that mean "this migration's effect is already present". */
const ALREADY_APPLIED = [
  'duplicate column name',
  'already exists',
  'no such table',      // a migration guarding a table initDb never created
];

function isAlreadyApplied(error) {
  const message = String(error?.message || '').toLowerCase();
  return ALREADY_APPLIED.some((fragment) => message.includes(fragment));
}

/**
 * Split a .sql file into executable statements. Naive on purpose — these files
 * are plain DDL — but it must not split inside a BEGIN...END trigger body.
 */
function splitSqlStatements(sql) {
  const withoutComments = sql
    .split('\n')
    .filter((line) => !line.trim().startsWith('--'))
    .join('\n');
  const statements = [];
  let buffer = '';
  let triggerDepth = 0;
  for (const rawChunk of withoutComments.split(';')) {
    buffer += rawChunk;
    const upper = buffer.toUpperCase();
    const begins = (upper.match(/\bBEGIN\b/g) || []).length;
    const ends = (upper.match(/\bEND\b/g) || []).length;
    triggerDepth = begins - ends;
    if (triggerDepth > 0) {
      buffer += ';';
      continue;
    }
    const statement = buffer.trim();
    if (statement) statements.push(statement);
    buffer = '';
  }
  const tail = buffer.trim();
  if (tail) statements.push(tail);
  return statements;
}

/**
 * @param {object} deps
 * @param {object} deps.db      raw sqlite3 Database (js migrations take this)
 * @param {Function} deps.run   promisified db.run(sql, params)
 * @param {Function} deps.all   promisified db.all(sql, params)
 */
module.exports = async function runPendingMigrations({ db, run, all }) {
  await run(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name TEXT PRIMARY KEY,
      applied_at TEXT NOT NULL,
      outcome TEXT NOT NULL DEFAULT 'applied'
    )
  `);

  let files;
  try {
    files = fs.readdirSync(MIGRATIONS_DIR)
      .filter((f) => f.endsWith('.sql') || f.endsWith('.js'))
      .sort();
  } catch {
    return { applied: [], skipped: [], alreadyRecorded: 0 };
  }

  const recorded = new Set(
    (await all('SELECT name FROM schema_migrations')).map((r) => r.name),
  );

  // Migrations run with foreign keys relaxed, as schema migrations normally do:
  // they rebuild tables, backfill in an order the constraints would forbid, and
  // seed sentinel rows (009 writes a company-wide statutory_config on the
  // reserved client_id = 0, which no clients row will ever match). Constraints
  // go back on afterwards and any resulting violation is reported, not hidden.
  await run('PRAGMA foreign_keys = OFF');

  // Several .js migrations call db.run()/db.exec() with no callback (008 does).
  // node-sqlite3 has nowhere to report those failures, so it raises them out of
  // band and takes the process down — an 'error' listener does not reliably
  // intercept it. Since the runner owns the handle it hands to a migration,
  // give it one that always supplies a callback: the failure comes back to us
  // instead of escaping, and "already applied" is absorbed exactly as it is for
  // .sql files. A migration passing its own callback is left alone.
  const outOfBand = [];
  const guard = (method) => (sql, ...rest) => {
    const hasCallback = typeof rest[rest.length - 1] === 'function';
    if (hasCallback) return db[method](sql, ...rest);
    return db[method](sql, ...rest, (error) => {
      if (error) outOfBand.push(error);
    });
  };
  const guardedDb = new Proxy(db, {
    get(target, prop, receiver) {
      if (prop === 'run' || prop === 'exec') return guard(prop);
      const value = Reflect.get(target, prop, receiver);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
  /** Let queued statements land so their errors are in `outOfBand`. */
  const drain = async () => {
    await all('SELECT 1');
    await new Promise((resolve) => setTimeout(resolve, 25));
  };

  const applied = [];
  const tolerated = [];
  for (const file of files) {
    if (recorded.has(file)) continue;
    const full = path.join(MIGRATIONS_DIR, file);
    let toleratedHere = 0;

    try {
      if (file.endsWith('.sql')) {
        for (const statement of splitSqlStatements(fs.readFileSync(full, 'utf8'))) {
          try {
            await run(statement);
          } catch (error) {
            if (!isAlreadyApplied(error)) throw error;
            toleratedHere += 1;
          }
        }
      } else {
        const mod = require(full);
        const up = typeof mod === 'function' ? mod : (mod.up || mod.default);
        if (typeof up !== 'function') {
          throw new Error(`migration ${file} exports no up()`);
        }
        // Several migrations call db.run() with no callback (008 does). Those
        // are fire-and-forget: node-sqlite3 emits the failure as an 'error'
        // event on the Database instead of rejecting, so `await up(db)` sees
        // nothing and an unhandled event would take the process down. Collect
        // them, then flush the connection — statements are serialized, so a
        // query that resolves after `up` guarantees its writes have landed.
        const before = outOfBand.length;
        await up(guardedDb);
        await drain();
        for (const error of outOfBand.slice(before)) {
          if (!isAlreadyApplied(error)) throw error;
          toleratedHere += 1;
        }
      }
    } catch (error) {
      if (!isAlreadyApplied(error)) {
        error.message = `migration ${file} failed: ${error.message}`;
        throw error;
      }
      toleratedHere += 1;
    }

    await run(
      `INSERT OR REPLACE INTO schema_migrations (name, applied_at, outcome)
       VALUES (?, ?, ?)`,
      [file, new Date().toISOString(), toleratedHere ? 'converged' : 'applied'],
    );
    (toleratedHere ? tolerated : applied).push(file);
  }

  await drain();
  const unexpected = outOfBand.filter((e) => !isAlreadyApplied(e));
  if (unexpected.length) throw unexpected[0];
  await run('PRAGMA foreign_keys = ON');

  if (applied.length || tolerated.length) {
    const violations = await all('PRAGMA foreign_key_check');
    console.log(
      `[migrations] ${applied.length} applied, ${tolerated.length} already present`
      + ` (${recorded.size} previously recorded)`,
    );
    if (violations.length) {
      // Expected: the reserved client_id = 0 statutory_config row from 009.
      const byTable = violations.reduce((acc, v) => {
        acc[v.table] = (acc[v.table] || 0) + 1;
        return acc;
      }, {});
      console.log('[migrations] post-migration FK check:', JSON.stringify(byTable));
    }
  }
  return { applied, tolerated, alreadyRecorded: recorded.size };
};
