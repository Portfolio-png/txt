import 'package:core_erp/features/inventory/domain/inventory_set_definition.dart';
import 'package:core_erp/features/inventory/domain/set_membership.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:flutter_test/flutter_test.dart';

/// `saveSet` replaces a set's whole line list, so every membership change is
/// really "work out the new list". These are the rules that list follows:
/// positions re-based from zero, and the same part at the same variation
/// appearing once with the quantities added up.

ItemDefinition _item(int id, String name) => ItemDefinition(
  id: id,
  name: name,
  displayName: name,
  alias: '',
  groupId: 1,
  unitId: 1,
  quantity: 0,
  namingFormat: const <String>[],
  variationTree: const <ItemVariationNodeDefinition>[],
  usageCount: 0,
  isArchived: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

InventorySetLineDefinition _line(
  int itemId, {
  int leaf = 0,
  int quantity = 1,
  int position = 0,
}) => InventorySetLineDefinition(
  id: itemId,
  itemId: itemId,
  variationLeafNodeId: leaf,
  quantity: quantity,
  position: position,
  itemName: 'Item $itemId',
  itemDisplayName: 'Item $itemId',
  variationPathLabel: '',
  variationPathNodeIds: const <int>[],
);

InventorySetDefinition _set(List<InventorySetLineDefinition> lines) =>
    InventorySetDefinition(
      id: 5,
      name: 'Kit',
      totalItemCount: lines.fold(0, (sum, line) => sum + line.quantity),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lines: lines,
    );

void main() {
  group('mergeSetLines', () {
    test('appends, renumbers positions and keeps the existing lines', () {
      final merged = mergeSetLines(
        _set([
          _line(1, quantity: 2, position: 0),
          _line(2, position: 1),
        ]),
        added: _item(3, 'C'),
      );
      expect(merged.map((line) => line.itemId), <int>[1, 2, 3]);
      expect(merged.map((line) => line.position), <int>[0, 1, 2]);
      expect(merged.first.quantity, 2);
    });

    test('the same part at the same variation is one line, quantities added', () {
      final merged = mergeSetLines(
        _set([_line(1, quantity: 2)]),
        added: _item(1, 'A'),
      );
      expect(merged, hasLength(1));
      expect(merged.single.quantity, 3);
    });

    test('the same part at another variation is a second line', () {
      final merged = mergeSetLines(
        _set([_line(1)]),
        added: _item(1, 'A'),
        variationLeafNodeId: 9,
        variationPathLabel: 'Red',
      );
      expect(merged, hasLength(2));
      expect(merged.last.variationLeafNodeId, 9);
      expect(merged.last.variationPathLabel, 'Red');
    });
  });

  group('linesWithout', () {
    test('drops only the named variation and re-bases the rest', () {
      final left = linesWithout(
        _set([
          _line(1, position: 0),
          _line(2, leaf: 9, position: 1),
          _line(2, leaf: 8, position: 2),
        ]),
        itemId: 2,
        variationLeafNodeId: 9,
      );
      expect(left.map((line) => line.itemId), <int>[1, 2]);
      expect(left.last.variationLeafNodeId, 8);
      expect(left.map((line) => line.position), <int>[0, 1]);
    });

    test('a part that is not there leaves the list alone', () {
      final left = linesWithout(
        _set([_line(1)]),
        itemId: 99,
        variationLeafNodeId: 0,
      );
      expect(left, hasLength(1));
    });
  });

  group('linesWithQuantity', () {
    test('changes one line and leaves the others', () {
      final next = linesWithQuantity(
        _set([_line(1, quantity: 1, position: 0), _line(2, quantity: 4, position: 1)]),
        itemId: 1,
        variationLeafNodeId: 0,
        quantity: 7,
      );
      expect(next.first.quantity, 7);
      expect(next.last.quantity, 4);
      expect(next.map((line) => line.position), <int>[0, 1]);
    });

    test('zero is refused rather than quietly removing the line', () {
      // The server refuses it too, and turning a typo into a deletion is worse
      // than refusing.
      expect(
        () => linesWithQuantity(
          _set([_line(1)]),
          itemId: 1,
          variationLeafNodeId: 0,
          quantity: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
