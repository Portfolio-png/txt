const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { mkdtempSync, existsSync } = require('node:fs');
const http = require('node:http');
const { tmpdir } = require('node:os');
const path = require('node:path');
const test = require('node:test');

// A part's photos — its views, up to five — against the local store: each
// photo with its thumbnail, an ordered array to read, one PUT for order and
// the main photo, a limit the server holds, and a sweep that really deletes
// the stored objects a day after a photo is removed.

function listen(app) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(app);
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
    server.on('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

// Bytes that stand in for a photo: the local store checks the declared type,
// not the pixels. Each [n] is different bytes, so a different hash.
const photoBytes = (n) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.from(`photo ${n}`)]);
const thumbBytes = (n) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.from(`thumb ${n}`)]);
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');

test('a part keeps up to five photos, each with a thumbnail, in an order', async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'paper-gallery-'));
  process.env.DB_PATH = path.join(tempDir, 'paper.db');
  process.env.PAPER_UPLOAD_DIR = path.join(tempDir, 'uploads');
  process.env.PAPER_SUPER_ADMIN_EMAIL = 'gallery@paper.local';
  process.env.PAPER_SUPER_ADMIN_PASSWORD = 'OwnerPass1234';
  delete process.env.PAPER_S3_BUCKET_NAME;
  delete process.env.S3_BUCKET;

  delete require.cache[require.resolve('../server.js')];
  const backend = require('../server.js');
  await backend.resetAndSeedDemoData();
  const { server, port } = await listen(backend.app);
  const base = `http://127.0.0.1:${port}`;
  const local = (url) => {
    const parsed = new URL(url);
    return `${base}${parsed.pathname}${parsed.search}`;
  };
  const stored = (key) => existsSync(path.join(tempDir, 'uploads', key));

  try {
    const { token } = await fetch(`${base}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'gallery@paper.local', password: 'OwnerPass1234' }),
    }).then((r) => r.json());
    const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
    const call = async (method, url, body) => {
      const response = await fetch(`${base}${url}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      return { status: response.status, body: await response.json() };
    };

    const groups = (await call('GET', '/api/groups')).body.groups;
    const parent = groups.find((g) => g.groupType === 'item');
    const made = await call('POST', '/api/items', {
      name: 'Gallery Patti',
      groupId: parent.id,
      unitId: parent.unitId,
    });
    assert.equal(made.status, 201, JSON.stringify(made.body));
    const part = made.body.item;

    const intentFor = (n, extra = {}) =>
      call('POST', '/api/assets/upload-intent', {
        uploadType: 'ITEM_IMAGE',
        entityType: 'item',
        entityId: part.id,
        fileName: `view-${n}.jpg`,
        contentType: 'image/jpeg',
        sizeBytes: photoBytes(n).length,
        sha256: sha(photoBytes(n)),
        isPrimary: false,
        thumbnail: { sizeBytes: thumbBytes(n).length, sha256: sha(thumbBytes(n)) },
        width: 2048,
        height: 1536,
        ...extra,
      });

    async function upload(n) {
      const intent = await intentFor(n);
      assert.equal(intent.status, 201, JSON.stringify(intent.body));
      const { upload: slot } = intent.body.intent;
      // The URLs are signed for this exact header: the object is stored
      // with it, and anything that fetches it may keep it.
      assert.equal(slot.headers['Cache-Control'], 'private, max-age=31536000, immutable');
      assert.match(slot.thumbnail.objectKey, /\/thumbs\/[^/]+\.jpg$/);
      for (const [url, body, type] of [
        [slot.uploadUrl, photoBytes(n), 'image/jpeg'],
        [slot.thumbnail.uploadUrl, thumbBytes(n), 'image/jpeg'],
      ]) {
        const put = await fetch(local(url), { method: 'PUT', headers: { 'Content-Type': type }, body });
        assert.equal(put.status, 200);
      }
      const done = await call('POST', '/api/assets/upload-complete', {
        uploadSessionId: slot.uploadSessionId,
        objectKey: slot.objectKey,
      });
      assert.equal(done.status, 200, JSON.stringify(done.body));
      return { ...done.body.asset, thumbKey: slot.thumbnail.objectKey };
    }

    // A thumbnail is part of the upload: completing without it is refused.
    const half = await intentFor(99);
    const halfSlot = half.body.intent.upload;
    await fetch(local(halfSlot.uploadUrl), {
      method: 'PUT',
      headers: { 'Content-Type': 'image/jpeg' },
      body: photoBytes(99),
    });
    const refusedHalf = await call('POST', '/api/assets/upload-complete', {
      uploadSessionId: halfSlot.uploadSessionId,
      objectKey: halfSlot.objectKey,
    });
    assert.equal(refusedHalf.status, 400);

    const first = await upload(1);
    // The first photo of a part is its main one, though not asked to be.
    assert.equal(first.isPrimary, true);
    assert.equal(first.position, 1);
    assert.equal(first.width, 2048);
    const uploaded = [first];
    for (const n of [2, 3, 4, 5]) uploaded.push(await upload(n));
    assert.deepEqual(uploaded.map((a) => a.position), [1, 2, 3, 4, 5]);
    assert.deepEqual(uploaded.map((a) => a.isPrimary), [true, false, false, false, false]);

    // A sixth is refused before anything is uploaded — and so is asking the
    // phone for one.
    const sixth = await intentFor(6);
    assert.equal(sixth.status, 409);
    assert.equal(sixth.body.code, 'photo_limit');
    assert.match(sixth.body.error, /up to 5 photos/);
    const phone = await call('POST', '/api/photo-requests', {
      entityType: 'item',
      entityId: part.id,
      context: 'gallery',
    });
    assert.equal(phone.status, 409);
    // The same bytes again are the photo already there, not a sixth.
    assert.equal((await intentFor(3)).status, 200);

    // One ordered array, with links to the thumbnail and to the photo.
    const listed = await call('GET', `/api/items/${part.id}/photos`);
    assert.equal(listed.status, 200);
    assert.equal(listed.body.limit, 5);
    assert.deepEqual(listed.body.photos.map((p) => p.id), uploaded.map((a) => a.id));
    const thumb = await fetch(local(listed.body.photos[0].thumbUrl), { redirect: 'manual' });
    assert.equal(thumb.status, 302);
    const thumbServed = await fetch(local(thumb.headers.get('location')));
    assert.deepEqual(Buffer.from(await thumbServed.arrayBuffer()), thumbBytes(1));
    assert.equal(thumbServed.headers.get('cache-control'), 'private, max-age=31536000, immutable');

    // The list of parts' main photos hands over the small copy too.
    const primary = await call('POST', '/api/assets/primary', {
      entityType: 'item',
      entityIds: [part.id],
    });
    assert.ok(primary.body.photos[part.id].thumbReadUrl);
    assert.equal(primary.body.photos[part.id].count, 5);

    // The gallery's Save: a new order and a new main photo, in one request.
    const [a, b, c, d, e] = uploaded.map((x) => x.id);
    const arranged = await call('PUT', `/api/items/${part.id}/photos`, {
      order: [c, a, b],
      primaryId: c,
    });
    assert.equal(arranged.status, 200, JSON.stringify(arranged.body));
    assert.deepEqual(arranged.body.photos.map((p) => p.id), [c, a, b, d, e]);
    assert.deepEqual(arranged.body.photos.map((p) => p.position), [1, 2, 3, 4, 5]);
    assert.deepEqual(arranged.body.photos.filter((p) => p.isPrimary).map((p) => p.id), [c]);
    // ...and the part's own photo field follows it.
    const third = uploaded.find((x) => x.id === c);
    const row = await backend.get('SELECT photo_url FROM items WHERE id = ?', [part.id]);
    assert.equal(row.photo_url, third.viewUrl);

    // A photo that is not this part's is refused, and nothing moves.
    const foreign = await call('PUT', `/api/items/${part.id}/photos`, { order: [c, 999999] });
    assert.equal(foreign.status, 400);

    // Removing the main photo: the next one becomes main, the rest close up.
    assert.equal((await call('DELETE', `/api/assets/${c}`)).status, 200);
    const after = (await call('GET', `/api/items/${part.id}/photos`)).body.photos;
    assert.deepEqual(after.map((p) => p.id), [a, b, d, e]);
    assert.deepEqual(after.map((p) => p.position), [1, 2, 3, 4]);
    assert.equal(after[0].isPrimary, true);
    // Room again for a fifth.
    assert.equal((await intentFor(7)).status, 201);

    // The removed photo's objects stay for a day (it can still be put back),
    // and are gone after it.
    assert.ok(stored(third.objectKey) && stored(third.thumbKey));
    await backend.sweepDeletedAssets();
    assert.ok(stored(third.objectKey) && stored(third.thumbKey), 'kept for the day');
    assert.ok(stored(halfSlot.objectKey), 'an unfinished upload is kept while its link lives');
    const later = new Date(Date.now() + 25 * 3600 * 1000);
    const swept = await backend.sweepDeletedAssets({ now: later });
    assert.equal(swept.assets, 1);
    assert.ok(!stored(third.objectKey) && !stored(third.thumbKey), 'both objects deleted');
    const purged = await backend.get('SELECT status FROM uploaded_assets WHERE id = ?', [c]);
    assert.equal(purged.status, 'purged');

    // The upload begun and never finished above leaves nothing behind.
    assert.ok(swept.sessions >= 1);
    assert.ok(!stored(halfSlot.objectKey), 'an abandoned upload is deleted too');

    // The gallery's Save is uploads, deletes and this PUT: all of it asks
    // the part's photo right, so someone with that (and not items.update)
    // saves the whole of it, and someone without it saves none.
    async function userWith(email, overrides) {
      const made = await call('POST', '/api/users', {
        name: email, email, password: 'PhotoPass1234', role: 'user',
        permissions: ['items.read', 'login.desktop'],
      });
      assert.equal(made.status, 201, JSON.stringify(made.body));
      const grid = await call('PATCH', `/api/users/${made.body.user.id}/permissions`, { overrides });
      assert.equal(grid.status, 200, JSON.stringify(grid.body));
      const { token: userToken } = await fetch(`${base}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password: 'PhotoPass1234' }),
      }).then((r) => r.json());
      return (method, url, body) =>
        fetch(`${base}${url}`, {
          method,
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${userToken}` },
          body: body === undefined ? undefined : JSON.stringify(body),
        });
    }
    const photographer = await userWith('photographer@paper.local', [
      { key: 'items.asset.upload', allowed: true },
      { key: 'items.asset.list', allowed: true },
      { key: 'items.update', allowed: false },
    ]);
    const order = after.map((p) => p.id);
    assert.equal((await photographer('GET', `/api/items/${part.id}/photos`)).status, 200);
    assert.equal(
      (await photographer('PUT', `/api/items/${part.id}/photos`, { order, primaryId: order[0] })).status,
      200,
      'the photo right is enough for the order and the main photo',
    );
    const editor = await userWith('editor@paper.local', [
      { key: 'items.update', allowed: true },
      { key: 'items.asset.upload', allowed: false },
    ]);
    assert.equal(
      (await editor('PUT', `/api/items/${part.id}/photos`, { order })).status,
      403,
      'items.update alone does not arrange photos it could not upload',
    );

    // A part deleted keeps its photos while the trash can bring it back: the
    // sweep a day on leaves them, and a restore returns them, main one and all.
    const remaining = await backend.all(
      "SELECT object_key, thumb_key FROM uploaded_assets WHERE entity_type = 'item' AND entity_id = ? AND status = 'uploaded'",
      [part.id],
    );
    assert.equal(remaining.length, 4);
    const mainBefore = (await call('GET', `/api/items/${part.id}/photos`)).body.photos.find((p) => p.isPrimary);
    const removed = await call('DELETE', `/api/items/${part.id}`);
    assert.equal(removed.status, 200, JSON.stringify(removed.body));
    const marked = await backend.all(
      "SELECT status FROM uploaded_assets WHERE entity_type = 'item' AND entity_id = ? AND status = 'record_deleted'",
      [part.id],
    );
    assert.equal(marked.length, 4, 'the rows are kept, marked, not erased');
    await backend.sweepDeletedAssets({ now: new Date(Date.now() + 25 * 3600 * 1000) });
    for (const r of remaining) {
      assert.ok(stored(r.object_key) && stored(r.thumb_key), 'kept while the part is in the trash');
    }
    const restored = await call('POST', '/api/trash/restore', { tableName: 'items', recordId: part.id });
    assert.equal(restored.status, 200, JSON.stringify(restored.body));
    const back = (await call('GET', `/api/items/${part.id}/photos`)).body.photos;
    assert.equal(back.length, 4, 'the photos come back with the part');
    assert.equal(back.find((p) => p.isPrimary)?.id, mainBefore.id, 'the same one is main');
    const field = await backend.get('SELECT photo_url FROM items WHERE id = ?', [part.id]);
    assert.equal(field.photo_url, mainBefore.viewUrl);

    // Gone for good — not live and not in the trash — the sweep takes them.
    assert.equal((await call('DELETE', `/api/items/${part.id}`)).status, 200);
    await backend.run("DELETE FROM deleted_records WHERE table_name = 'items' AND record_id = ?", [part.id]);
    await backend.sweepDeletedAssets({ now: new Date(Date.now() + 25 * 3600 * 1000) });
    for (const r of remaining) {
      assert.ok(!stored(r.object_key) && !stored(r.thumb_key), 'swept once the trash let it go');
    }

    // Photos from before positions: a new one goes after them, not in front.
    const older = (await call('POST', '/api/items', {
      name: 'Gallery Older',
      groupId: parent.id,
      unitId: parent.unitId,
    })).body.item;
    for (const n of [21, 22]) {
      const intent = await call('POST', '/api/assets/upload-intent', {
        uploadType: 'ITEM_IMAGE', entityType: 'item', entityId: older.id,
        fileName: `old-${n}.jpg`, contentType: 'image/jpeg',
        sizeBytes: photoBytes(n).length, sha256: sha(photoBytes(n)),
      });
      const slot = intent.body.intent.upload;
      await fetch(local(slot.uploadUrl), { method: 'PUT', headers: { 'Content-Type': 'image/jpeg' }, body: photoBytes(n) });
      await call('POST', '/api/assets/upload-complete', { uploadSessionId: slot.uploadSessionId, objectKey: slot.objectKey });
    }
    await backend.run("UPDATE uploaded_assets SET position = NULL WHERE entity_type = 'item' AND entity_id = ?", [older.id]);
    const shownBefore = (await call('GET', `/api/items/${older.id}/photos`)).body.photos.map((p) => p.id);
    const intent = await call('POST', '/api/assets/upload-intent', {
      uploadType: 'ITEM_IMAGE', entityType: 'item', entityId: older.id,
      fileName: 'new.jpg', contentType: 'image/jpeg',
      sizeBytes: photoBytes(23).length, sha256: sha(photoBytes(23)), isPrimary: false,
    });
    const slot = intent.body.intent.upload;
    await fetch(local(slot.uploadUrl), { method: 'PUT', headers: { 'Content-Type': 'image/jpeg' }, body: photoBytes(23) });
    const added = (await call('POST', '/api/assets/upload-complete', {
      uploadSessionId: slot.uploadSessionId, objectKey: slot.objectKey,
    })).body.asset;
    const shownAfter = (await call('GET', `/api/items/${older.id}/photos`)).body.photos;
    assert.deepEqual(shownAfter.map((p) => p.id), [...shownBefore, added.id]);
    assert.deepEqual(shownAfter.map((p) => p.position), [1, 2, 3]);
  } finally {
    await closeServer(server);
    delete process.env.PAPER_UPLOAD_DIR;
  }
});

test('a thumbnail sits beside its photo', () => {
  const backend = require('../server.js');
  assert.equal(
    backend.thumbnailKeyFor('masters/items/item-7/1730-abc-patti.jpeg'),
    'masters/items/item-7/thumbs/1730-abc-patti.jpg',
  );
  assert.equal(backend.thumbnailKeyFor('a/b/photo'), 'a/b/thumbs/photo.jpg');
});
