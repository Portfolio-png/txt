const assert = require('node:assert/strict');
const { mkdtempSync, readFileSync, existsSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// Where the in-app marker's marks end up. The app is sandboxed on macOS and
// cannot write anywhere findable, so the backend keeps the file — which makes
// this round trip the only thing standing between "the badge counted up" and
// "the mark actually exists".

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

test('marks posted by the app are written, read back and cleared', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-dev-marks-'));
  const marksFile = path.join(tempDir, 'marks.jsonl');
  process.env.PAPER_MARKS_FILE = marksFile;
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'marks-owner@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const { token } = await (
      await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: 'marks-owner@paper.local',
          password: 'OwnerPass1234',
        }),
      })
    ).json();
    const headers = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };

    const mark = {
      n: 1,
      session: '1003-0930',
      label: 'unit',
      screen: 'ItemsScreen',
      keys: ['item_unit_field'],
      text: 'Unit',
      widgets: ['TextField'],
      at: [964, 561],
      ts: '2026-10-03T09:30:00.000Z',
    };
    const posted = await fetch(`${baseUrl}/api/dev/marks`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ marks: [mark] }),
    });
    assert.equal(posted.status, 200, await posted.clone().text());

    // On disk, one mark per line, exactly as sent.
    assert.ok(existsSync(marksFile), 'the file is written where the repo can see it');
    const lines = readFileSync(marksFile, 'utf8').trim().split('\n');
    assert.equal(lines.length, 1);
    assert.deepEqual(JSON.parse(lines[0]), mark);

    // A second mark appends rather than replacing.
    await fetch(`${baseUrl}/api/dev/marks`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ marks: [{ ...mark, n: 2, text: 'Qty' }] }),
    });
    const readBack = await (
      await fetch(`${baseUrl}/api/dev/marks`, { headers })
    ).json();
    assert.equal(readBack.marks.length, 2);
    assert.deepEqual(
      readBack.marks.map((entry) => entry.text),
      ['Unit', 'Qty'],
    );

    const cleared = await fetch(`${baseUrl}/api/dev/marks`, {
      method: 'DELETE',
      headers,
    });
    assert.equal(cleared.status, 200);
    assert.equal(
      (await (await fetch(`${baseUrl}/api/dev/marks`, { headers })).json()).marks
        .length,
      0,
    );
  } finally {
    delete process.env.PAPER_MARKS_FILE;
    await new Promise((resolve) => server.close(resolve));
  }
});
