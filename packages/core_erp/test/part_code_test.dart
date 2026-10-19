import 'package:core_erp/features/items/domain/part_code.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared fixture. The same table is asserted in
/// backend/test/item-part-identity.test.js — the two implementations are
/// allowed to exist, drifting apart is not.
const _fixture = <(String?, String?, String?, int?, String)>[
  ('Switch Action', 'Dolly', 'Patti', 48, 'SADP48'),
  ('Switch Action', '', 'Patti', 1, 'SAP1'),
  ('Ash Trays', null, 'Lid', null, 'ATL'),
  ('', '', '2mm Washer', 3, 'W3'),
  ('', '', 'M8 Bolt', 3, 'MB3'),
  ('', '', 'L-Bracket', 7, 'LB7'),
  ('', '', '48', 48, ''),
  ('', '', '', 48, ''),
  ('पट्टी', '', '', 2, ''),
  (
    'Switch Action Assembly',
    'Mounting Plate Bracket',
    'Rear Cover Plate',
    9,
    'SAAMPBRCP9',
  ),
];

void main() {
  test('every fixture row builds the code the backend builds', () {
    for (final (group, set, item, no, expected) in _fixture) {
      expect(
        buildPartCode(
          groupName: group,
          setName: set,
          itemName: item,
          partNo: no,
        ),
        expected,
        reason: '$group / $set / $item / $no',
      );
    }
  });

  test('null and empty are the same absence, and neither leaves a gap', () {
    expect(
      buildPartCode(groupName: null, setName: '', itemName: 'Lid', partNo: 2),
      buildPartCode(groupName: '', setName: null, itemName: 'Lid', partNo: 2),
    );
    expect(buildPartCode(itemName: 'Lid', partNo: 2), 'L2');
  });

  test('a name with no letters yields no code, never a bare number', () {
    // A code that is only digits cannot be told from the part number.
    expect(buildPartCode(itemName: '2026', partNo: 7), '');
    expect(buildPartCode(itemName: '!!', partNo: 7), '');
  });

  test('the letter run is capped before the number, so a code stays sayable', () {
    expect(
      buildPartCode(
        groupName: 'A B C D E F G H I J K L M N',
        itemName: 'O P',
        partNo: 5,
      ),
      'ABCDEFGHIJKL5',
    );
  });

  test('initials take one letter per word, and only where a word starts with one', () {
    expect(partCodeInitials('Switch Action'), 'SA');
    expect(partCodeInitials('2mm Washer'), 'W');
    expect(partCodeInitials('M8 Bolt'), 'MB');
    expect(partCodeInitials('L-Bracket'), 'LB');
    expect(partCodeInitials('  spaced   out  '), 'SO');
    expect(partCodeInitials(null), '');
  });

  // --- variants -------------------------------------------------------------
  // The same table is asserted in backend/test/item-part-identity.test.js.
  // Two implementations are allowed to exist; drifting apart is not.

  test('a variant code is the trunk, the value codes, then the number', () {
    const fixture = <List<Object?>>[
      // group, set, item, values, no, code
      ['Switch Action', 'Dolly', 'Patti', ['B', '22'], 48, 'SADPB2248'],
      ['Switch Action', 'Dolly', 'Patti', ['MS', '22'], 48, 'SADPMS2248'],
      // Order is the caller's and is kept verbatim — gauge-then-alloy is a
      // different code, which is why the item's naming format decides it.
      ['Switch Action', 'Dolly', 'Patti', ['22', 'B'], 48, 'SADP22B48'],
      // Blank and punctuation-only codes drop out rather than leaving a gap.
      ['Switch Action', 'Dolly', 'Patti', ['B', '', '  ', '-'], 48, 'SADPB48'],
      // No values is the plain part code, so a variant of nothing is not a
      // second name for the part.
      ['Switch Action', 'Dolly', 'Patti', <String>[], 48, 'SADP48'],
      ['Ash Trays', '', 'Lid', ['ss 304'], 2, 'ATLSS3042'],
      ['', '', '', ['B'], 48, ''],
      // The 12-letter cap applies to the trunk only.
      [
        'Switch Action Assembly',
        'Mounting Plate Bracket',
        'Rear Cover Plate',
        ['BRASS', '22'],
        9,
        'SAAMPBRCPBRASS229',
      ],
    ];

    for (final row in fixture) {
      expect(
        buildVariantPartCode(
          groupName: row[0] as String,
          setName: row[1] as String,
          itemName: row[2] as String,
          valueCodes: (row[3] as List).cast<String>(),
          partNo: row[4] as int,
        ),
        row[5] as String,
        reason: '${row[0]}/${row[1]}/${row[2]} ${row[3]} #${row[4]}',
      );
    }
  });

  test('a value with no typed code derives one', () {
    // "Brass" is BRAS, not B. B is a decision somebody makes in the Code
    // field; BRAS is the guess made when nobody did. "Mild Steel" gets MS on
    // its own, because two words become their initials.
    expect(variationValueCode('Brass'), 'BRAS');
    expect(variationValueCode('MS'), 'MS');
    expect(variationValueCode('Mild Steel'), 'MS');
    expect(variationValueCode('22'), '22');
    expect(variationValueCode('Stainless Steel 304'), 'SS304');
    expect(variationValueCode('Aluminium'), 'ALUM');
    expect(variationValueCode(''), '');
    expect(variationValueCode(null), '');
  });

  test('a variant never shares a code with its own part', () {
    // A scan could not otherwise tell the part from one of its variants.
    final part = buildPartCode(
      groupName: 'Switch Action',
      setName: 'Dolly',
      itemName: 'Patti',
      partNo: 48,
    );
    final variant = buildVariantPartCode(
      groupName: 'Switch Action',
      setName: 'Dolly',
      itemName: 'Patti',
      valueCodes: const ['B', '22'],
      partNo: 48,
    );
    expect(variant, isNot(part));
    expect(variant.startsWith('SADP'), isTrue, reason: 'still legible as a variant of SADP48');
  });

  test('a variant code can be built from the base part\'s own code', () {
    // Preferred when spawning, because the trunk then comes from the code the
    // part is actually known by rather than being re-derived from names the
    // editor may not have loaded. No Node twin: no server path derives from an
    // existing code — the server builds trunks from names via
    // buildVariantPartCode.
    expect(
      variantCodeFromPartCode('SADP48', valueCodes: const ['B', '22']),
      'SADPB2248',
    );
    expect(
      variantCodeFromPartCode('SADP48', valueCodes: const ['MS', '22']),
      'SADPMS2248',
    );
    // The number stays last, so a variant reads the same way round as its part.
    expect(variantCodeFromPartCode('ATL', valueCodes: const ['SS']), 'ATLSS');
    expect(variantCodeFromPartCode('W3', valueCodes: const ['B']), 'WB3');
    // No values is the part's own code, not a second name for it.
    expect(variantCodeFromPartCode('SADP48'), 'SADP48');
    expect(variantCodeFromPartCode('SADP48', valueCodes: const ['', ' ', '-']), 'SADP48');
    // A base with no code cannot have variants with one: inventing a trunk
    // would give the variant a code its parent does not share.
    expect(variantCodeFromPartCode(''), '');
    expect(variantCodeFromPartCode(null, valueCodes: const ['B']), '');
    // Lower case and punctuation in a typed code are normalised.
    expect(variantCodeFromPartCode('sadp48', valueCodes: const ['ss 304']), 'SADPSS30448');
    // An all-digit base has no trunk to insert into, so it is left alone
    // rather than silently reordered.
    expect(variantCodeFromPartCode('48', valueCodes: const ['B']), '48');
  });
}
