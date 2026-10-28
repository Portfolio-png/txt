#!/usr/bin/env node
/**
 * Runs the full journey against a deployed server, on demand.
 *
 *   PAPER_E2E_EMAIL=… PAPER_E2E_PASSWORD=… \
 *     npm run journey -- --target http://<staging-host>:18081
 *
 *   npm run journey -- --target … --cleanup journey-<runId>.json
 *
 * Staging by default. A target on the production port (18080), or a host that
 * says "prod", is refused unless --allow-production is given — the journey
 * writes real records.
 *
 * What it writes is KEPT, tagged "E2E <runId>", so it can be browsed in the
 * app pointed at the same server; the report (every record, everything sent
 * and read back, every step's time) is saved as journey-<runId>.json.
 * --cleanup archives the part and deletes the photos of a saved report's run.
 *
 * Costs next to nothing: ~80 small API calls and ~10 S3 requests per run,
 * photos of ~70 bytes. Nothing schedules it; it runs when someone runs it.
 */

const fs = require('node:fs');
const path = require('node:path');
const { Journey, printReport, cleanup } = require('./full-journey');

function argValue(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function main() {
  const target = argValue('--target');
  const email = process.env.PAPER_E2E_EMAIL;
  const password = process.env.PAPER_E2E_PASSWORD;
  if (!target || !email || !password) {
    console.error(
      'Usage: PAPER_E2E_EMAIL=… PAPER_E2E_PASSWORD=… npm run journey -- --target <url> ' +
        '[--cleanup <report.json>] [--out <dir>] [--allow-production]',
    );
    process.exit(2);
  }
  const url = new URL(target);
  const looksLikeProduction =
    url.port === '18080' || /prod/i.test(url.hostname);
  if (looksLikeProduction && !process.argv.includes('--allow-production')) {
    console.error(
      `Refusing ${target}: it looks like production, and the journey writes real ` +
        'records. Use staging, or pass --allow-production if you mean it.',
    );
    process.exit(2);
  }

  const cleanupReport = argValue('--cleanup');
  if (cleanupReport) {
    const result = JSON.parse(fs.readFileSync(cleanupReport, 'utf8'));
    console.log(`Cleaning up journey ${result.runId} on ${target}`);
    await cleanup(result, { baseUrl: target, email, password });
    return;
  }

  const runId = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 12);
  const journey = new Journey({ baseUrl: target, email, password, runId, log: console.log });
  let result;
  try {
    result = await journey.run();
  } catch (error) {
    console.error(`\nThe journey stopped: ${error.message}`);
    if (journey.timings.length) {
      console.error(`(${journey.timings.length} steps had run.)`);
    }
    process.exit(1);
  }
  printReport(result);
  const outDir = argValue('--out') || process.cwd();
  const file = path.join(outDir, `journey-${runId}.json`);
  fs.writeFileSync(file, JSON.stringify(result, null, 2));
  console.log(`\nFull report (everything sent and read back): ${file}`);
  console.log(`Clean up later with: npm run journey -- --target ${target} --cleanup ${file}`);
  process.exit(result.ok ? 0 : 1);
}

main();
