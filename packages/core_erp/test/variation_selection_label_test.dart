import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/presentation/utils/naming_format_helper.dart';
import 'package:flutter_test/flutter_test.dart';

final _stamp = DateTime(2026, 1, 1);

ItemVariationNodeDefinition _node({
  required int id,
  required ItemVariationNodeKind kind,
  required String name,
  int? parentNodeId,
  List<ItemVariationNodeDefinition> children = const [],
}) {
  return ItemVariationNodeDefinition(
    id: id,
    itemId: 493,
    parentNodeId: parentNodeId,
    kind: kind,
    name: name,
    // The seeded rows this reproduces leave display_name at its '' default,
    // which is what made every option render as "<item> • ".
    displayName: '',
    position: 0,
    isArchived: false,
    createdAt: _stamp,
    updatedAt: _stamp,
    children: children,
  );
}

/// Mirrors item 493 in the seeded database: two sibling top-level properties,
/// each with a single value whose display_name is blank.
ItemDefinition _anchorRomaSocket() {
  return ItemDefinition(
    id: 493,
    name: 'Anchor Roma Classic Socket 10A',
    alias: '',
    displayName: 'Anchor Roma Classic Socket 10A',
    quantity: 0,
    groupId: 1,
    unitId: 1,
    isArchived: false,
    usageCount: 0,
    createdAt: _stamp,
    updatedAt: _stamp,
    variationTree: [
      _node(
        id: 4082,
        kind: ItemVariationNodeKind.property,
        name: 'Color',
        children: [
          _node(
            id: 4083,
            kind: ItemVariationNodeKind.value,
            name: 'White',
            parentNodeId: 4082,
          ),
        ],
      ),
      _node(
        id: 4084,
        kind: ItemVariationNodeKind.property,
        name: 'Module',
        children: [
          _node(
            id: 4085,
            kind: ItemVariationNodeKind.value,
            name: '2M',
            parentNodeId: 4084,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('variation leaf labelling', () {
    final item = _anchorRomaSocket();

    test('leaf nodes carry no usable displayName of their own', () {
      expect(item.leafVariationNodes.map((n) => n.id), [4083, 4085]);
      expect(
        item.leafVariationNodes.every((n) => n.displayName.trim().isEmpty),
        isTrue,
        reason: 'this is the condition the dialog used to render directly',
      );
    });

    test('the path builder labels each leaf by its value name', () {
      expect(
        NamingFormatHelper.buildVariationSelectionLabel(
          item,
          const [4083],
          const {},
          false,
        ).trim(),
        'White',
      );
      expect(
        NamingFormatHelper.buildVariationSelectionLabel(
          item,
          const [4085],
          const {},
          false,
        ).trim(),
        '2M',
      );
    });

    test('the two leaves no longer produce identical option labels', () {
      final labels = [
        const [4083],
        const [4085],
      ].map((path) {
        final built = NamingFormatHelper.buildVariationSelectionLabel(
          item,
          path,
          const {},
          false,
        ).trim();
        return built.isEmpty
            ? item.displayName
            : '${item.displayName} • $built';
      }).toList();

      expect(labels, [
        'Anchor Roma Classic Socket 10A • White',
        'Anchor Roma Classic Socket 10A • 2M',
      ]);
      expect(labels.toSet().length, 2);
      expect(labels.any((l) => l.trimRight().endsWith('•')), isFalse);
    });
  });
}
