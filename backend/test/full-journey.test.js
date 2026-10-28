const assert = require('node:assert/strict');
const { mkdtempSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { Journey, printReport } = require('../journey/full-journey');

// The whole item-sheet workflow through the API, on a throwaway server with
// the local photo store — every commit. The same journey runs against a
// deployed server with `npm run journey -- --target …`.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
    server.on('error', reject);
  });
}

test('everything a part carries is written, survives a fresh sign-in, and the photos come back', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-journey-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_UPLOAD_DIR = path.join(tempDir, 'uploads');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'journey@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'JourneyPass1234';
  delete process.env.PAPER_S3_BUCKET_NAME;
  delete process.env.S3_BUCKET;

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  try {
    const lines = [];
    const journey = new Journey({
      baseUrl: `http://127.0.0.1:${port}`,
      email: 'journey@paper.local',
      password: 'JourneyPass1234',
      runId: 'local',
      log: (line) => lines.push(line),
    });
    const result = await journey.run();
    if (!result.ok || process.env.JOURNEY_VERBOSE) printReport(result);
    assert.deepEqual(result.mismatches, [], 'everything sent should read back the same');
    assert.ok(result.timings.length > 20, 'every step is timed');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    delete process.env.PAPER_UPLOAD_DIR;
  }
});
