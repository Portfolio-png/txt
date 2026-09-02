'use strict';

// Generates the cross-language barcode codec vectors by RUNNING the backend
// implementation, so both pinned fixtures record what the code actually does
// rather than what anyone believes it does.
//
// Invoked by tool/regen_barcode_vectors.sh — see that script for when it is
// appropriate to run this at all.

const fs = require('fs');
const path = require('path');
const barcodes = require(path.join(__dirname, '..', 'backend', 'kernel', 'barcodes.js'));

const types = Object.keys(barcodes.TYPES);

// One vector per type, so a type added to the kernel without a vector is caught
// by the coverage assertion on the Dart side.
const encodeInputs = types.map((type) => [type, 'REC-1-L1']);
encodeInputs.push(
  ['MAT', 'sheet-metal-flow'], // ids are not always uppercase
  ['MAT', '  spaced  code '],  // guns and phone keyboards add whitespace
  ['mat', 'lowercase-1'],
  ['DC', '00042'],
  ['RUN', '42'],
  ['ITM', 'A'],                // a one-character id, which decode must not eat
  ['MFG', 'RUN-2026-0001'],    // an id containing dashes
  ['MAT', ''],                 // -> null
  ['NOPE', '1'],               // -> null, unknown type
  ['MAT', '   '],              // -> null, whitespace-only id
  // Places. Their ids are free-text with spaces, and a code strips whitespace,
  // so these pin that 'Cutting bay' and 'CUTTINGBAY' travel as the same code.
  ['LOC', 'MAIN'],
  ['LOC', 'Rack A1'],
  ['FLR', 'Cutting bay'],
  ['FLR', 'Assembly line 1'],
);

const encodeVectors = encodeInputs.map(([type, id]) => ({
  type,
  id,
  code: barcodes.encode(type, id),
}));

const decodeInputs = [
  'MAT-REC-1-L1-K',      // a plausible-looking code whose check is WRONG
  'DC-00042-L1',         // trailing part is two chars, so not a check
  'RUN-A',               // only two parts
  'ITM-A',
  '',
  'FOO-1',               // unknown type
  'MAT',                 // no separator at all
  'mat-rec-1-l1-k',
  ' MAT-REC-1-L1-K ',
  'MAT-REC-1-L1-Z',
  'DC-00042',
  'MFG-RUN-2026-0001',
];
// Every valid encoded code, and each with its check character broken, so the
// vectors can never consist only of codes that pass.
for (const vector of encodeVectors) {
  if (!vector.code) continue;
  decodeInputs.push(vector.code);
  const last = vector.code.slice(-1);
  decodeInputs.push(vector.code.slice(0, -1) + (last === '0' ? '1' : '0'));
}

const decodeVectors = [...new Set(decodeInputs)].map((input) => ({
  input,
  out: barcodes.decode(input),
}));

const payload = { encodeVectors, decodeVectors };

fs.writeFileSync(
  path.join(__dirname, '..', 'backend', 'test', 'fixtures', 'barcode-vectors.json'),
  JSON.stringify(payload),
);

const quote = (value) =>
  `'${String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$')}'`;

let dart = '';
dart += '// GENERATED — do not edit by hand.\n';
dart += '//\n';
dart += '// Produced from the real backend implementation (backend/kernel/barcodes.js)\n';
dart += '// so the Dart mirror is checked against what the server actually does rather\n';
dart += '// than against a reading of it. A mirror verified by hand-written expectations\n';
dart += '// only proves the two agree with the author, not with each other.\n';
dart += '//\n';
dart += '// Regenerate: tool/regen_barcode_vectors.sh\n';
dart += '\n';
dart += 'class EncodeVector {\n  const EncodeVector(this.type, this.id, this.code);\n  final String type;\n  final String id;\n  final String? code;\n}\n\n';
dart += 'class DecodeVector {\n  const DecodeVector(this.input, {this.type, this.id, this.hasCheck, this.checkValid});\n  final String input;\n  final String? type;\n  final String? id;\n  final bool? hasCheck;\n  final bool? checkValid;\n  bool get isNull => type == null;\n}\n\n';
dart += 'const List<EncodeVector> kEncodeVectors = <EncodeVector>[\n';
for (const vector of encodeVectors) {
  dart += `  EncodeVector(${quote(vector.type)}, ${quote(vector.id)}, ${vector.code === null ? 'null' : quote(vector.code)}),\n`;
}
dart += '];\n\n';
dart += 'const List<DecodeVector> kDecodeVectors = <DecodeVector>[\n';
for (const vector of decodeVectors) {
  if (vector.out === null) {
    dart += `  DecodeVector(${quote(vector.input)}),\n`;
  } else {
    dart += `  DecodeVector(${quote(vector.input)}, type: ${quote(vector.out.type)}, id: ${quote(vector.out.id)}, hasCheck: ${vector.out.hasCheck}, checkValid: ${vector.out.checkValid}),\n`;
  }
}
dart += '];\n';

fs.writeFileSync(
  path.join(__dirname, '..', 'packages', 'core_erp', 'test', 'fixtures', 'barcode_codec_vectors.dart'),
  dart,
);

console.log(
  `Wrote ${encodeVectors.length} encode and ${decodeVectors.length} decode vectors to both fixtures.`,
);
