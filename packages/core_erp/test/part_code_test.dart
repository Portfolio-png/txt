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
}
