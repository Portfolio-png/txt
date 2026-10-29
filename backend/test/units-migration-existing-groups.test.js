const assert = require('node:assert/strict');
const fs = require('node:fs');
const { mkdtempSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');
const sqlite3 = require('sqlite3');

// A deployed database that already had its own unit group called "Count"
// stopped the server from booting: migration 051 inserted the Count family
// with code 'count', then gave the old group the same code, and the unique
// index refused — "UNIQUE constraint failed: unit_groups.code" on every boot.

function open(file) {
  const db = new sqlite3.Database(file);
  const exec = (sql) => new Promise((res, rej) => db.exec(sql, (e) => (e ? rej(e) : res())));
  const all = (sql, params = []) =>
    new Promise((res, rej) => db.all(sql, params, (e, rows) => (e ? rej(e) : res(rows))));
  const close = () => new Promise((res) => db.close(res));
  return { exec, all, close };
}

test('051 on a database that already has groups named for the families', async () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'paper-051-'));
  const db = open(path.join(dir, 'old.db'));
  try {
    // The shape before 051: no code columns, and two groups called Count.
    await db.exec(`
      CREATE TABLE unit_groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        dimension TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
      CREATE TABLE units (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        symbol TEXT NOT NULL, unit_group_id INTEGER);
      INSERT INTO unit_groups (name, created_at, updated_at) VALUES
        ('Count', 'x', 'x'), ('count', 'x', 'x'), ('Mass', 'x', 'x');
    `);
    const sql = fs.readFileSync(
      path.join(__dirname, '..', 'migrations', '051-units-contract-ladders.sql'),
      'utf8',
    );
    await db.exec(sql);

    const counts = await db.all(
      "SELECT id, code FROM unit_groups WHERE LOWER(name) = 'count' ORDER BY id",
    );
    assert.deepEqual(
      counts.map((row) => row.code),
      ['count', null],
      'the oldest Count takes the code, the other is left alone, none is added',
    );
    const codes = await db.all(
      'SELECT code, COUNT(*) AS n FROM unit_groups WHERE code IS NOT NULL GROUP BY code',
    );
    assert.ok(codes.every((row) => row.n === 1), 'every code is on one row');
    assert.deepEqual(
      codes.map((row) => row.code).sort(),
      ['area', 'count', 'length', 'mass', 'time', 'volume'],
    );

    // Every boot runs it again; nothing may change or fail.
    await db.exec(sql.replace(/^ALTER TABLE.*$/gm, ''));
    assert.equal(
      (await db.all("SELECT COUNT(*) AS n FROM unit_groups WHERE code = 'count'"))[0].n,
      1,
    );
  } finally {
    await db.close();
  }
});

test('a server left with a coded Count and an older uncoded one still boots', async () => {
  // What the failed 051 left on the deployed database: the family it inserted
  // (coded) beside the group the database already had (not coded). The boot
  // seeding then picked the older, uncoded row and coded it — the same error.
  const dir = mkdtempSync(path.join(tmpdir(), 'paper-051-boot-'));
  process.env.DB_PATH = path.join(dir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'units-051@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'Units051Pass1';
  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.initDb();

  const now = new Date().toISOString();
  await backend.run(
    'INSERT INTO unit_groups (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
    [0, 'Count', now, now],
  );

  await backend.initDb();
  const rows = await backend.all(
    "SELECT id, code FROM unit_groups WHERE LOWER(name) = 'count' ORDER BY id",
  );
  assert.equal(rows.filter((row) => row.code === 'count').length, 1);
  assert.equal(rows.find((row) => row.id === 0).code, null, 'the old group is left as it was');
});
