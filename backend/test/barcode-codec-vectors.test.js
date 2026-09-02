'use strict';

// The codec exists in two languages: backend/kernel/barcodes.js and
// packages/core_erp/lib/core/services/barcode_codec.dart. Duplicated logic is a
// real hazard — nothing stops one side drifting, and the symptom would be a
// freshly printed label the server refuses to resolve.
//
// The defence is a pinned set of vectors checked by BOTH sides. This file is the
// JS half. If it fails and the Dart half passes, the JS moved; if the Dart half
// fails and this passes, the mirror moved. Regenerating (see
// tool/regen_barcode_vectors.sh) is correct ONLY when the change was deliberate.

const test = require('node:test');
const assert = require('node:assert/strict');

const barcodes = require('../kernel/barcodes');
const vectors = require('./fixtures/barcode-vectors.json');

test('every pinned encode vector still holds', () => {
  assert.ok(vectors.encodeVectors.length > 0, 'fixture is not empty');
  for (const vector of vectors.encodeVectors) {
    assert.equal(
      barcodes.encode(vector.type, vector.id),
      vector.code,
      `encode(${JSON.stringify(vector.type)}, ${JSON.stringify(vector.id)})`,
    );
  }
});

test('every pinned decode vector still holds', () => {
  assert.ok(vectors.decodeVectors.length > 0, 'fixture is not empty');
  for (const vector of vectors.decodeVectors) {
    assert.deepEqual(
      barcodes.decode(vector.input),
      vector.out,
      `decode(${JSON.stringify(vector.input)})`,
    );
  }
});

test('the fixture covers every type the kernel declares', () => {
  // A type added to TYPES without a vector would otherwise go unexercised on
  // both sides forever, which is exactly how a mirror rots quietly.
  const declared = new Set(Object.keys(barcodes.TYPES));
  const covered = new Set(
    vectors.encodeVectors
      .filter((vector) => vector.code)
      .map((vector) => barcodes.normalize(vector.type)),
  );
  const missing = [...declared].filter((type) => !covered.has(type));
  assert.deepEqual(
    missing,
    [],
    `types with no vector: ${missing.join(', ')} — run tool/regen_barcode_vectors.sh`,
  );
});

test('the fixture exercises a failing check character, not only passing ones', () => {
  // A check character is worthless if every vector was a valid code.
  const withBadCheck = vectors.decodeVectors.filter(
    (vector) => vector.out && vector.out.hasCheck && !vector.out.checkValid,
  );
  const withGoodCheck = vectors.decodeVectors.filter(
    (vector) => vector.out && vector.out.hasCheck && vector.out.checkValid,
  );
  const withNoCheck = vectors.decodeVectors.filter(
    (vector) => vector.out && !vector.out.hasCheck,
  );
  assert.ok(withBadCheck.length > 0, 'some vector must fail its check');
  assert.ok(withGoodCheck.length > 0, 'some vector must pass its check');
  assert.ok(withNoCheck.length > 0, 'some vector must be an unverified legacy code');
});

test('the generator reproduces the committed fixture exactly', () => {
  // Guards the guard: if the generator and the committed fixture disagree, the
  // fixture was hand-edited, and a hand-edited fixture proves nothing.
  const regenerated = vectors.encodeVectors.map((vector) => ({
    type: vector.type,
    id: vector.id,
    code: barcodes.encode(vector.type, vector.id),
  }));
  assert.deepEqual(regenerated, vectors.encodeVectors);
});
