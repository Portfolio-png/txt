/**
 * The whole item-sheet workflow through the API, then proof it stuck.
 *
 * Fills everything a part carries — the company and its people, a vendor, the
 * part with its alloy and gauge, the deal, a die and a machine linked to it,
 * a route, the raw-sheet plan with its material figures, a photo on each of
 * five kinds of record — deletes one photo, then signs in AGAIN (a fresh
 * token, nothing cached) and reads every record back, comparing field by
 * field. Each photo is fetched through the link saved on its record, so on a
 * deployed server the bytes make the whole trip: app → EC2 → S3 → back.
 *
 * Every step is timed; times are reported, never judged. Mismatches are
 * collected rather than thrown, so one run lists everything that did not
 * stick, not just the first.
 *
 * Cheap on purpose: photos are a 1x1 PNG (~70 bytes); a run is about eighty
 * small requests and ten to S3.
 */

const { performance } = require('node:perf_hooks');

// A real 1x1 PNG.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);

function sha256(buffer) {
  return require('node:crypto').createHash('sha256').update(buffer).digest('hex');
}

/**
 * A distinct tiny PNG per photo — the same image with a few bytes after its
 * end marker, which decoders ignore — so no two photos share a hash and none
 * is mistaken for a re-upload of another.
 */
function pngFor(index) {
  return Buffer.concat([PNG, Buffer.from(`e2e-${index}`)]);
}

class Journey {
  constructor({ baseUrl, email, password, runId, log = () => {} }) {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this.email = email;
    this.password = password;
    this.runId = runId;
    this.log = log;
    this.token = null;
    this.timings = [];
    this.mismatches = [];
    this.records = {};
    this.sent = {};
    this.readBack = {};
  }

  tag(label) {
    return `E2E ${this.runId} ${label}`;
  }

  async timed(step, fn) {
    const started = performance.now();
    try {
      return await fn();
    } finally {
      const ms = Math.round(performance.now() - started);
      this.timings.push({ step, ms });
      this.log(`  ${step.padEnd(34)} ${String(ms).padStart(6)} ms`);
    }
  }

  async call(method, path, body) {
    const response = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let payload = {};
    try {
      payload = await response.json();
    } catch (_) {
      payload = {};
    }
    if (response.status >= 400) {
      const error = new Error(
        `${method} ${path} → ${response.status}: ${payload.error || JSON.stringify(payload)}`,
      );
      error.status = response.status;
      throw error;
    }
    return payload;
  }

  expect(label, actual, expected) {
    const same = JSON.stringify(actual) === JSON.stringify(expected);
    if (!same) this.mismatches.push({ label, expected, actual });
  }

  async login() {
    this.token = null;
    const payload = await this.call('POST', '/api/auth/login', {
      email: this.email,
      password: this.password,
    });
    if (!payload.token) throw new Error('Login answered without a token.');
    this.token = payload.token;
  }

  /** intent → PUT (to S3, or the local store) → complete. */
  async uploadPhoto(entityType, entityId, bytes, fileName) {
    const intent = await this.call('POST', '/api/assets/upload-intent', {
      uploadType:
        { item: 'ITEM_IMAGE', die: 'DIE_IMAGE', machine: 'MACHINE_IMAGE' }[entityType] ||
        'PARTY_IMAGE',
      entityType,
      entityId,
      fileName,
      contentType: 'image/png',
      sizeBytes: bytes.length,
      sha256: sha256(bytes),
      isPrimary: true,
    });
    if (intent.intent?.alreadyUploaded) return intent.intent.asset;
    const upload = intent.intent.upload;
    const put = await fetch(upload.uploadUrl, {
      method: 'PUT',
      headers: upload.headers || { 'Content-Type': 'image/png' },
      body: bytes,
    });
    if (put.status >= 300) {
      throw new Error(`Photo PUT → ${put.status}: ${await put.text()}`);
    }
    const done = await this.call('POST', '/api/assets/upload-complete', {
      uploadSessionId: upload.uploadSessionId,
      objectKey: upload.objectKey,
    });
    return done.asset;
  }

  /** The bytes behind a saved photo link, following its redirect. */
  async photoBytes(url) {
    const response = await fetch(url, { redirect: 'follow' });
    if (response.status !== 200) {
      throw new Error(`Photo link → ${response.status}`);
    }
    return {
      type: response.headers.get('content-type'),
      bytes: Buffer.from(await response.arrayBuffer()),
    };
  }

  async run() {
    const r = this.records;
    this.log(`Journey ${this.runId} against ${this.baseUrl}`);

    await this.timed('sign in', () => this.login());

    const [groups, units, stages] = await this.timed('read masters', () =>
      Promise.all([
        this.call('GET', '/api/groups'),
        this.call('GET', '/api/units'),
        this.call('GET', '/api/process-stages'),
      ]),
    );
    const group = (groups.groups || []).find(
      (g) => !g.isArchived && (!g.groupType || g.groupType === 'item'),
    );
    const unit = (units.units || []).find((u) => !u.isArchived) || (units.units || [])[0];
    if (!group || !unit) throw new Error('No item group or unit to file a part under.');
    const stageId = (code) => (stages.stages || []).find((s) => s.code === code)?.id;

    // --- company, people, vendor ---------------------------------------------
    this.sent.client = { name: this.tag('Company') };
    r.client = (
      await this.timed('create company', () => this.call('POST', '/api/clients', this.sent.client))
    ).client;

    this.sent.people = [
      {
        name: this.tag('Ravi'),
        designation: 'Purchase Manager',
        phone: '9820012345',
        email: `ravi.${this.runId}@example.com`,
      },
      {
        name: this.tag('Meena'),
        designation: 'Accounts',
        phone: '9820054321',
        email: `meena.${this.runId}@example.com`,
      },
    ];
    r.people = [];
    for (const person of this.sent.people) {
      r.people.push(
        (
          await this.timed(`add person ${person.designation}`, () =>
            this.call('POST', `/api/clients/${r.client.id}/contacts`, person),
          )
        ).contact,
      );
    }

    this.sent.vendor = { name: this.tag('Steel Supplier') };
    r.vendor = (
      await this.timed('create vendor', () => this.call('POST', '/api/vendors', this.sent.vendor))
    ).vendor;

    // --- die and machine ---------------------------------------------------------
    this.sent.die = {
      toolCode: `E2E-${this.runId}-D1`,
      status: 'active',
      ownership: 'owned',
      dieType: 'cutting',
      madeBy: this.tag('Toolroom'),
      noOfSet: 2,
      storeArea: 'Die Store A',
      rackNo: 'R-12',
      linerSizeNm: 800000,
      linerSizeUnit: 'mm',
    };
    const die = await this.timed('create die', () => this.call('POST', '/api/dies', this.sent.die));
    r.die = die.die || die;

    this.sent.machine = {
      name: this.tag('Press'),
      assetId: `E2E-${this.runId}-M1`,
      status: 'operational',
      machineMake: 'Bhurji',
      feederMake: 'Servo',
      runningHours: 1200,
    };
    const machine = await this.timed('create machine', () =>
      this.call('POST', '/api/machines', this.sent.machine),
    );
    r.machine = machine.machine || machine;

    // --- the part, with everything it carries ----------------------------------
    this.sent.baseline = {
      isGranular: false,
      materialFromPlan: false,
      sheetWidthInches: 48,
      sheetHeightInches: 96,
      sheetThicknessMm: 0.61,
      faceUnit: 'in',
      gaugeUnit: 'mm',
      materialName: 'MS',
      materialGrade: 'First',
      vendorId: r.vendor.id,
      vendorName: r.vendor.name,
      primaryAxis: 'columns',
      bands: [{ sizeMm: 300, count: 4 }],
      subCuts: { 0: [{ sizeMm: 40, count: 10 }] },
      kerfMm: 3,
      edgeTrimMm: 5,
      stageReconciliations: [
        {
          stageId: 'whole_pipeline',
          stageName: 'Entire Pipeline',
          inputKg: 24.5,
          outputKg: 21.25,
          scrapKg: 3.25,
          rejectionKg: 0,
          weightLossKg: 0,
          inputSheets: 1,
          inputQty: 1,
          outputPieces: 2900,
          outputQty: 2900,
          inputLabel: 'MS · First grade · 48 × 96 in',
          outputLabel: this.tag('Patti'),
        },
      ],
    };
    this.sent.part = {
      name: this.tag('Patti'),
      displayName: this.tag('Patti'),
      groupId: group.id,
      unitId: unit.id,
      variationTree: [
        {
          kind: 'property',
          name: 'Alloy',
          inputType: 'Material',
          children: [{ kind: 'value', name: 'MS', children: [] }],
        },
        {
          kind: 'property',
          name: 'Thickness',
          inputType: 'Gauge',
          children: [{ kind: 'value', name: '23 Gauge', children: [] }],
        },
      ],
      developedFor: {
        kind: 'client',
        clientId: r.client.id,
        quotationAmount: 45000,
        contactIds: [r.people[0].id],
      },
      dieIds: [String(r.die.id)],
      machineIds: [String(r.machine.id)],
      penPaperBaseline: this.sent.baseline,
    };
    r.part = (
      await this.timed('create part (deal, links, raw sheet)', () =>
        this.call('POST', '/api/items', this.sent.part),
      )
    ).item;

    // --- route ------------------------------------------------------------------
    const steps = ['die', 'shearing', 'cutting', 'riveting'].map(stageId).filter(Boolean);
    this.sent.route = { steps };
    r.route = await this.timed('author route', () =>
      this.call('POST', `/api/items/${r.part.id}/routes`, this.sent.route),
    );

    // --- photos -----------------------------------------------------------------
    const photoTargets = [
      ['item', r.part.id],
      ['client', r.client.id],
      ['party_contact', r.people[0].id],
      ['party_contact', r.people[1].id],
      ['die', Number(r.die.id)],
      ['machine', Number(r.machine.id)],
    ];
    r.photos = [];
    for (const [index, [type, id]] of photoTargets.entries()) {
      const bytes = pngFor(index);
      const asset = await this.timed(`upload photo ${type}#${id}`, () =>
        this.uploadPhoto(type, id, bytes, `e2e-${type}-${id}.png`),
      );
      r.photos.push({ type, id, assetId: asset.id, bytes, viewUrl: asset.viewUrl });
    }
    // One deleted: the second person's.
    const doomed = r.photos.find((p) => p.type === 'party_contact' && p.id === r.people[1].id);
    await this.timed('delete a photo', () => this.call('DELETE', `/api/assets/${doomed.assetId}`));
    doomed.deleted = true;

    // --- retention: a fresh sign-in, everything read back ----------------------
    await this.timed('sign in again (fresh token)', () => this.login());
    const b = this.readBack;
    b.part = (await this.timed('read part', () => this.call('GET', `/api/items/${r.part.id}`))).item;
    b.client = (
      await this.timed('read company', () => this.call('GET', `/api/clients/${r.client.id}`))
    ).client;
    b.people = (
      await this.timed('read people', () =>
        this.call('GET', `/api/clients/${r.client.id}/contacts`),
      )
    ).contacts;
    b.vendor = (
      await this.timed('read vendor', () => this.call('GET', `/api/vendors/${r.vendor.id}`))
    ).vendor;
    const readDie = await this.timed('read die', () => this.call('GET', `/api/dies/${r.die.id}`));
    b.die = readDie.die || readDie;
    const readMachine = await this.timed('read machine', () =>
      this.call('GET', `/api/machines/${r.machine.id}`),
    );
    b.machine = readMachine.machine || readMachine;
    b.routes = await this.timed('read route', () => this.call('GET', `/api/items/${r.part.id}/routes`));
    b.primaryPhotos = {};
    for (const type of ['item', 'client', 'party_contact', 'die', 'machine']) {
      const ids = r.photos.filter((p) => p.type === type).map((p) => p.id);
      b.primaryPhotos[type] = (
        await this.timed(`read ${type} photos`, () =>
          this.call('POST', '/api/assets/primary', { entityType: type, entityIds: ids }),
        )
      ).photos;
    }

    this.compare();

    // --- the photos make the whole trip back -----------------------------------
    const savedLinks = [
      ['part photo', b.part.photoUrl, 'item'],
      ['company logo', b.client.logoUrl, 'client'],
      ['machine photo', b.machine.primaryPhotoUrl, 'machine'],
      ['die photo', (b.die.photoUrls || [])[0], 'die'],
    ];
    for (const [label, url, type] of savedLinks) {
      const expected = r.photos.find((p) => p.type === type);
      if (!url) {
        this.mismatches.push({ label: `${label} link on the record`, expected: 'a link', actual: url });
        continue;
      }
      const got = await this.timed(`fetch ${label} via saved link`, () => this.photoBytes(url));
      this.expect(`${label} type`, got.type, 'image/png');
      this.expect(`${label} bytes`, sha256(got.bytes), sha256(expected.bytes));
    }
    const personPhoto = b.primaryPhotos.party_contact?.[String(r.people[0].id)];
    if (personPhoto) {
      const got = await this.timed('fetch person photo', () => this.photoBytes(personPhoto.readUrl));
      this.expect('person photo bytes', sha256(got.bytes), sha256(r.photos[2].bytes));
    }

    return this.result();
  }

  /** Field by field: what was sent against what a fresh sign-in reads. */
  compare() {
    const { sent: s, readBack: b, records: r } = this;
    const part = b.part;
    this.expect('part name', part.name, s.part.name);
    this.expect('part group', part.groupId, s.part.groupId);
    const valueOf = (property) =>
      (part.variationTree || [])
        .find((node) => node.name === property)
        ?.children?.map((child) => child.name);
    this.expect('part alloy', valueOf('Alloy'), ['MS']);
    this.expect('part thickness', valueOf('Thickness'), ['23 Gauge']);
    this.expect('part code stamped', Boolean(part.partCode), true);
    const deal = part.developedFor || {};
    this.expect('deal kind', deal.kind, 'client');
    this.expect('deal company', deal.clientId, r.client.id);
    this.expect('deal quotation', deal.quotationAmount, 45000);
    this.expect('deal people ticked', deal.contactIds, [r.people[0].id]);
    this.expect(
      'part dies',
      (part.dies || []).map((d) => String(d.id)),
      [String(r.die.id)],
    );
    this.expect(
      'part machines',
      (part.machines || []).map((m) => String(m.id)),
      [String(r.machine.id)],
    );
    const baseline = part.penPaperBaseline || {};
    for (const key of [
      'sheetWidthInches',
      'sheetHeightInches',
      'sheetThicknessMm',
      'materialName',
      'materialGrade',
      'vendorId',
      'vendorName',
      'bands',
      'kerfMm',
      'edgeTrimMm',
    ]) {
      this.expect(`raw sheet ${key}`, baseline[key], s.baseline[key]);
    }
    const row = (baseline.stageReconciliations || [])[0] || {};
    for (const key of ['inputKg', 'outputKg', 'scrapKg', 'outputPieces', 'inputSheets']) {
      this.expect(`material data ${key}`, row[key], s.baseline.stageReconciliations[0][key]);
    }

    this.expect('company name', b.client.name, s.client.name);
    for (const [index, person] of s.people.entries()) {
      const found = (b.people || []).find((p) => p.id === r.people[index].id) || {};
      for (const key of ['name', 'designation', 'phone', 'email']) {
        this.expect(`person ${index + 1} ${key}`, found[key], person[key]);
      }
    }
    this.expect('vendor name', b.vendor.name, s.vendor.name);
    for (const key of ['toolCode', 'dieType', 'madeBy', 'noOfSet', 'storeArea', 'rackNo']) {
      this.expect(`die ${key}`, b.die[key], s.die[key]);
    }
    for (const key of ['name', 'assetId', 'machineMake', 'feederMake', 'runningHours']) {
      this.expect(`machine ${key}`, b.machine[key], s.machine[key]);
    }
    const active = (b.routes.routes || []).find((route) => route.status === 'active') || {};
    this.expect(
      'route steps',
      // Steps come back as rows: stage_id, seq, stage_code.
      (active.steps || []).map((step) => Number(step.stageId ?? step.stage_id)),
      s.route.steps,
    );
    for (const photo of r.photos) {
      const primary = b.primaryPhotos[photo.type]?.[String(photo.id)];
      this.expect(
        `${photo.type}#${photo.id} photo ${photo.deleted ? 'removed' : 'kept'}`,
        primary ? primary.assetId : null,
        photo.deleted ? null : photo.assetId,
      );
    }
  }

  result() {
    const sorted = this.timings.map((t) => t.ms).sort((a, b) => a - b);
    const pick = (q) => sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))] || 0;
    return {
      runId: this.runId,
      target: this.baseUrl,
      ok: this.mismatches.length === 0,
      mismatches: this.mismatches,
      timings: this.timings,
      summary: {
        steps: sorted.length,
        totalMs: sorted.reduce((a, b) => a + b, 0),
        p50Ms: pick(0.5),
        maxMs: sorted[sorted.length - 1] || 0,
      },
      records: {
        part: { id: this.records.part.id, name: this.records.part.name, code: this.readBack.part?.partCode },
        company: { id: this.records.client.id, name: this.records.client.name },
        people: this.records.people.map((p) => ({ id: p.id, name: p.name, designation: p.designation })),
        vendor: { id: this.records.vendor.id, name: this.records.vendor.name },
        die: { id: this.records.die.id, toolCode: this.records.die.toolCode },
        machine: { id: this.records.machine.id, assetId: this.records.machine.assetId },
        route: { version: this.records.route.version, steps: this.sent.route.steps.length },
        photos: this.records.photos.map((p) => ({
          type: p.type,
          id: p.id,
          assetId: p.assetId,
          deleted: Boolean(p.deleted),
        })),
      },
      sent: this.sent,
      readBack: this.readBack,
    };
  }
}

/** Prints what a run wrote and how long each step took. */
function printReport(result, log = console.log) {
  log('');
  log(`Journey ${result.runId} — ${result.ok ? 'everything persisted' : `${result.mismatches.length} mismatch(es)`}`);
  log('');
  log('Records written');
  const rec = result.records;
  const rows = [
    ['part', rec.part.id, `${rec.part.name}  code ${rec.part.code || '—'}`],
    ['company', rec.company.id, rec.company.name],
    ...rec.people.map((p) => ['person', p.id, `${p.name} — ${p.designation}`]),
    ['vendor', rec.vendor.id, rec.vendor.name],
    ['die', rec.die.id, rec.die.toolCode],
    ['machine', rec.machine.id, rec.machine.assetId],
    ['route', `v${rec.route.version}`, `${rec.route.steps} steps`],
    ...rec.photos.map((p) => [
      'photo',
      p.assetId,
      `${p.type}#${p.id}${p.deleted ? '  (deleted)' : ''}`,
    ]),
  ];
  for (const [kind, id, what] of rows) {
    log(`  ${String(kind).padEnd(8)} ${String(id).padEnd(8)} ${what}`);
  }
  log('');
  log(
    `Timing: ${result.summary.steps} steps, ${result.summary.totalMs} ms in all, ` +
      `p50 ${result.summary.p50Ms} ms, slowest ${result.summary.maxMs} ms`,
  );
  const slowest = [...result.timings].sort((a, b) => b.ms - a.ms).slice(0, 5);
  for (const t of slowest) log(`  ${t.step.padEnd(34)} ${String(t.ms).padStart(6)} ms`);
  if (!result.ok) {
    log('');
    log('Did not persist as sent:');
    for (const m of result.mismatches) {
      log(`  ${m.label}: sent ${JSON.stringify(m.expected)}, read ${JSON.stringify(m.actual)}`);
    }
  }
}

/** Archives what a run made and deletes its photos, from its saved report. */
async function cleanup(result, { baseUrl, email, password, log = console.log }) {
  const journey = new Journey({ baseUrl, email, password, runId: result.runId, log });
  await journey.login();
  const rec = result.records;
  const attempt = async (label, fn) => {
    try {
      await fn();
      log(`  ${label}`);
    } catch (error) {
      log(`  ${label} — skipped: ${error.message}`);
    }
  };
  for (const photo of rec.photos.filter((p) => !p.deleted)) {
    await attempt(`deleted photo ${photo.assetId}`, () =>
      journey.call('DELETE', `/api/assets/${photo.assetId}`),
    );
  }
  await attempt(`archived part ${rec.part.id}`, () =>
    journey.call('PATCH', `/api/items/${rec.part.id}/archive`, { isArchived: true }),
  );
}

module.exports = { Journey, printReport, cleanup, PNG };
