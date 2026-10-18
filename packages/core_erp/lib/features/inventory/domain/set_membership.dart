/// What a set's line list becomes when a part joins it, leaves it, or changes
/// how many of it the set holds.
///
/// `saveSet` replaces the whole line list — there is no per-line endpoint — so
/// every one of these returns the complete list to write back, with positions
/// re-based `0..n-1` and `(itemId, variationLeafNodeId)` deduped. The same item
/// twice is one line with a higher quantity, which is what the server does too.
///
/// This dedupe-and-reposition logic is written five times in this codebase:
/// here, `api_inventory_repository._mergeSetLines`,
/// `inventory_set_editor_dialog._save`, `items_screen._fileVariantsIntoSet`,
/// and `mergeInventorySetLines` on the server. Whoever consolidates them next
/// should start from that list.
library;

import '../../items/domain/item_definition.dart';
import 'inventory_set_definition.dart';

/// The set's current lines, as inputs — the "replay what is there" step every
/// write begins with.
List<SaveInventorySetLineInput> linesFrom(InventorySetDefinition existing) {
  return existing.lines
      .map(
        (line) => SaveInventorySetLineInput(
          itemId: line.itemId,
          variationLeafNodeId: line.variationLeafNodeId,
          quantity: line.quantity,
          position: line.position,
          itemName: line.itemName,
          itemDisplayName: line.itemDisplayName,
          variationPathLabel: line.variationPathLabel,
          variationPathNodeIds: line.variationPathNodeIds,
        ),
      )
      .toList(growable: false);
}

/// The lines an existing set should be saved with once [added] joins it.
List<SaveInventorySetLineInput> mergeSetLines(
  InventorySetDefinition existing, {
  required ItemDefinition added,
  int variationLeafNodeId = 0,
  int quantity = 1,
  String variationPathLabel = '',
}) {
  return _rebased(<SaveInventorySetLineInput>[
    ...linesFrom(existing),
    SaveInventorySetLineInput(
      itemId: added.id,
      variationLeafNodeId: variationLeafNodeId,
      quantity: quantity,
      position: existing.lines.length,
      itemName: added.name,
      itemDisplayName: added.displayName,
      variationPathLabel: variationPathLabel,
    ),
  ]);
}

/// The lines left after this part's line comes out.
///
/// Keyed on item **and** leaf, because a set may legitimately hold the same
/// part at two variations and only one of them is being removed.
List<SaveInventorySetLineInput> linesWithout(
  InventorySetDefinition existing, {
  required int itemId,
  required int variationLeafNodeId,
}) {
  return _rebased(
    linesFrom(existing)
        .where(
          (line) =>
              line.itemId != itemId ||
              line.variationLeafNodeId != variationLeafNodeId,
        )
        .toList(growable: false),
  );
}

/// The lines with this part's quantity set to [quantity].
///
/// A quantity of zero or less is not a removal — the server refuses it, and
/// silently turning a typo into a deletion is worse than refusing. Use
/// [linesWithout] to remove.
List<SaveInventorySetLineInput> linesWithQuantity(
  InventorySetDefinition existing, {
  required int itemId,
  required int variationLeafNodeId,
  required int quantity,
}) {
  if (quantity <= 0) {
    throw ArgumentError.value(
      quantity,
      'quantity',
      'A set line holds at least one. Remove the line instead.',
    );
  }
  return _rebased(
    linesFrom(existing)
        .map(
          (line) =>
              line.itemId == itemId &&
                  line.variationLeafNodeId == variationLeafNodeId
              ? SaveInventorySetLineInput(
                  itemId: line.itemId,
                  variationLeafNodeId: line.variationLeafNodeId,
                  quantity: quantity,
                  position: line.position,
                  itemName: line.itemName,
                  itemDisplayName: line.itemDisplayName,
                  variationPathLabel: line.variationPathLabel,
                  variationPathNodeIds: line.variationPathNodeIds,
                )
              : line,
        )
        .toList(growable: false),
  );
}

/// One quantity-1 line for an item with no variations.
///
/// Leaf 0 is what the border accepts precisely for an item that has no
/// orderable leaves — see [canFileAtLeafZero].
SaveInventorySetLineInput newSetLineFor(
  ItemDefinition item, {
  required int position,
}) {
  return SaveInventorySetLineInput(
    itemId: item.id,
    variationLeafNodeId: 0,
    quantity: 1,
    position: position,
    itemName: item.name,
    itemDisplayName: item.displayName,
  );
}

/// Whether this item can be a set line without naming a variation.
///
/// Mirrors the server's own check: a set line may use leaf 0 only for an item
/// with no active property carrying an active value. An item with a variation
/// tree has to say which variation it is.
bool canFileAtLeafZero(ItemDefinition item) {
  return !item.topLevelProperties.any(
    (property) => property.activeChildren.any(
      (child) => child.kind == ItemVariationNodeKind.value,
    ),
  );
}

/// Dedupe on item+leaf, summing quantities, then renumber from zero.
List<SaveInventorySetLineInput> _rebased(
  List<SaveInventorySetLineInput> lines,
) {
  final byKey = <String, SaveInventorySetLineInput>{};
  for (final line in lines) {
    final key = '${line.itemId}:${line.variationLeafNodeId}';
    final current = byKey[key];
    byKey[key] = current == null
        ? line
        : SaveInventorySetLineInput(
            itemId: current.itemId,
            variationLeafNodeId: current.variationLeafNodeId,
            quantity: current.quantity + line.quantity,
            position: current.position,
            itemName: current.itemName,
            itemDisplayName: current.itemDisplayName,
            variationPathLabel: current.variationPathLabel,
            variationPathNodeIds: current.variationPathNodeIds,
          );
  }

  final ordered = byKey.values.toList(growable: false)
    ..sort((a, b) => a.position.compareTo(b.position));
  return <SaveInventorySetLineInput>[
    for (var i = 0; i < ordered.length; i++)
      SaveInventorySetLineInput(
        itemId: ordered[i].itemId,
        variationLeafNodeId: ordered[i].variationLeafNodeId,
        quantity: ordered[i].quantity,
        position: i,
        itemName: ordered[i].itemName,
        itemDisplayName: ordered[i].itemDisplayName,
        variationPathLabel: ordered[i].variationPathLabel,
        variationPathNodeIds: ordered[i].variationPathNodeIds,
      ),
  ];
}
