import 'package:flutter/foundation.dart';
import 'column_def.dart';
import 'sheet_binding.dart';

@immutable
class SheetDef {
  SheetDef({
    required this.id,
    required this.key,
    required this.title,
    required List<ColumnDef> columns,
  }) : _columns = List<ColumnDef>.unmodifiable(
          [...columns]..sort((a, b) => a.position.compareTo(b.position)),
        );

  final int id;
  final String key;
  final String title;
  final List<ColumnDef> _columns;

  List<ColumnDef> get columns => _columns;

  ColumnDef? getColumn(int id) {
    for (final col in _columns) {
      if (col.id == id) return col;
    }
    return null;
  }

  ColumnDef? get groupColumn {
    for (final col in _columns) {
      if (col.role == ColumnRole.group) return col;
    }
    return null;
  }

  ColumnDef? get itemColumn {
    for (final col in _columns) {
      if (col.role == ColumnRole.item) return col;
    }
    return null;
  }

  /// The column that feeds [binds], or null when this sheet has none.
  ///
  /// The way anything outside a binding should reach a column. Reading a cell
  /// by literal id is how the prototype screen ended up with 34 sites that
  /// break the moment a column is inserted.
  ColumnDef? columnBoundTo(String binds) {
    for (final col in _columns) {
      if (col.bindsTo == binds) return col;
    }
    return null;
  }

  /// Every column feeding a `variation:` property, in sheet order.
  List<ColumnDef> get variationColumns => [
        for (final col in _columns)
          if (SheetBindsTo.isVariation(col.bindsTo)) col,
      ];

  List<ColumnDef> ancestors(int columnId) {
    final list = <ColumnDef>[];
    var current = getColumn(columnId);
    while (current?.parentId != null) {
      final parent = getColumn(current!.parentId!);
      if (parent != null) {
        list.add(parent);
        current = parent;
      } else {
        break;
      }
    }
    return list.reversed.toList();
  }

  TableGroup tableOf(ColumnDef col) {
    if (col.role == ColumnRole.stamp) {
      return TableGroup.created;
    }

    if (col.role == ColumnRole.group || col.role == ColumnRole.item) {
      return TableGroup.groupItem;
    }

    final item = itemColumn;
    if (item != null) {
      final itemAncestors = ancestors(item.id);
      if (itemAncestors.any((a) => a.id == col.id)) {
        return TableGroup.groupItem;
      }
    }

    // A cell that feeds a variation property IS a property, whatever widget it
    // uses to collect the value.
    //
    // This used to be decided by `kind` alone, which put Alloy and Thickness in
    // Properties **by accident** — neither is a `list` — and gave Finish, which
    // is, its own table headed "Primary Group (Finish)". Worse, the + dialog
    // defaults to `ColumnKind.list`, so the most natural of its four choices
    // was the one that filed the new property in the wrong table.
    if (SheetBindsTo.isVariation(col.bindsTo)) {
      return TableGroup.properties;
    }

    // Typed values and derived columns always sit in Properties
    if (col.kind != ColumnKind.list) {
      return TableGroup.properties;
    }

    // If it's a list column under Group or Item hierarchy, it's in Properties
    final colAncestors = ancestors(col.id);
    final root = colAncestors.isNotEmpty ? colAncestors.first : null;
    if (root != null && (root.role == ColumnRole.group || root.role == ColumnRole.item)) {
      return TableGroup.properties;
    }

    // Independent list column (or sub-list under an independent list)
    return TableGroup.independent;
  }

  (bool allowed, String? reason) canMoveLeft(int columnId) {
    final col = getColumn(columnId);
    if (col == null) return (false, 'Column not found');
    if (col.isDefault) return (false, '${col.label} is a default column and cannot be moved.');

    final table = tableOf(col);
    final tableCols = _columns.where((c) => tableOf(c) == table).toList();
    final idx = tableCols.indexWhere((c) => c.id == columnId);
    if (idx <= 0) return (false, 'Cannot move further left.');

    final leftNeighbor = tableCols[idx - 1];
    final parent = col.parentId != null ? getColumn(col.parentId!) : null;
    if (col.parentId == leftNeighbor.id || (parent != null && leftNeighbor.position <= parent.position)) {
      return (false, 'A column cannot move left past its parent.');
    }

    return (true, null);
  }

  (bool allowed, String? reason) canMoveRight(int columnId) {
    final col = getColumn(columnId);
    if (col == null) return (false, 'Column not found');
    if (col.isDefault) return (false, '${col.label} is a default column and cannot be moved.');

    final table = tableOf(col);
    final tableCols = _columns.where((c) => tableOf(c) == table).toList();
    final idx = tableCols.indexWhere((c) => c.id == columnId);
    if (idx >= tableCols.length - 1) return (false, 'Cannot move further right.');

    final rightNeighbor = tableCols[idx + 1];
    if (rightNeighbor.parentId == col.id) {
      return (false, 'A column cannot move right past its child.');
    }

    return (true, null);
  }

  (bool allowed, String? reason) canRemove(int columnId) {
    final col = getColumn(columnId);
    if (col == null) return (false, 'Column not found');
    if (col.isDefault) {
      return (false, '${col.label} is a default column and cannot be removed.');
    }

    final dependents = _columns.where((c) => c.parentId == columnId && c.id != itemColumn?.id).toList();
    if (dependents.isNotEmpty) {
      return (
        false,
        'Cannot remove ${col.label} while ${dependents.map((d) => d.label).join(", ")} depends on it.'
      );
    }

    return (true, null);
  }

  (bool allowed, String? reason) canReparent(int columnId, int? newParentId) {
    final col = getColumn(columnId);
    if (col == null) return (false, 'Column not found');
    if (col.isGroup) return (false, 'Group belongs to Primary Group.');
    if (col.isStamp) return (false, 'Timestamp columns cannot have a parent.');

    if (newParentId == null) {
      if (col.isItem) {
        return (false, 'Item name must sit under a group or sub-group.');
      }
      return (true, null);
    }

    final parent = getColumn(newParentId);
    if (parent == null) return (false, 'Parent column not found.');
    if (parent.kind != ColumnKind.list) {
      return (false, 'Parent must be a list column.');
    }
    if (parent.position >= col.position) {
      return (false, 'A column can only take a parent to its left.');
    }

    return (true, null);
  }

  SheetDef moveColumn(int columnId, int delta) {
    final col = getColumn(columnId);
    if (col == null) return this;
    final (allowed, _) = delta < 0 ? canMoveLeft(columnId) : canMoveRight(columnId);
    if (!allowed) return this;

    final table = tableOf(col);
    final tableCols = _columns.where((c) => tableOf(c) == table).toList();
    final idx = tableCols.indexWhere((c) => c.id == columnId);
    final targetCol = tableCols[idx + delta];

    final updated = _columns.map((c) {
      if (c.id == col.id) {
        return c.copyWith(position: targetCol.position);
      }
      if (c.id == targetCol.id) {
        return c.copyWith(position: col.position);
      }
      return c;
    }).toList();

    return SheetDef(id: id, key: key, title: title, columns: updated);
  }

  SheetDef addColumn({
    required String label,
    required ColumnKind kind,
    int? parentId,
    ColumnSource source = ColumnSource.options,
    int? familyId,
    String? bindsTo,
  }) {
    final maxId = _columns.fold<int>(0, (prev, c) => c.id > prev ? c.id : prev);
    final newId = maxId + 1;

    // Before the code column if there is one, else before the stamps.
    //
    // The code is built FROM the properties, so a property added after it
    // would not be folded in — the column would exist and change nothing,
    // which is the most confusing possible outcome of pressing +.
    final anchor = _columns.firstWhere(
      (c) => c.kind == ColumnKind.code,
      orElse: () => _columns.firstWhere(
        (c) => c.role == ColumnRole.stamp,
        orElse: () => _columns.last,
      ),
    );
    final insertPos = anchor.position;

    final updated = <ColumnDef>[];
    for (final col in _columns) {
      if (col.position >= insertPos) {
        updated.add(col.copyWith(position: col.position + 1));
      } else {
        updated.add(col);
      }
    }

    updated.add(
      ColumnDef(
        id: newId,
        sheetId: id,
        label: label,
        kind: kind,
        parentId: parentId,
        position: insertPos,
        source: source,
        familyId: familyId,
        bindsTo: bindsTo,
      ),
    );

    return SheetDef(id: id, key: key, title: title, columns: updated);
  }

  SheetDef addSubGroupLevel(String label) {
    final item = itemColumn;
    if (item == null) return this;

    final maxId = _columns.fold<int>(0, (prev, c) => c.id > prev ? c.id : prev);
    final newId = maxId + 1;
    final oldParentId = item.parentId;

    final updated = <ColumnDef>[];
    for (final col in _columns) {
      if (col.id == item.id) {
        updated.add(
          ColumnDef(
            id: newId,
            sheetId: id,
            label: label,
            kind: ColumnKind.list,
            parentId: oldParentId,
            position: col.position,
          ),
        );
        updated.add(col.copyWith(
          position: col.position + 1,
          parentId: newId,
        ));
      } else if (col.position > item.position) {
        updated.add(col.copyWith(position: col.position + 1));
      } else {
        updated.add(col);
      }
    }

    return SheetDef(id: id, key: key, title: title, columns: updated);
  }

  SheetDef removeColumn(int columnId) {
    final col = getColumn(columnId);
    if (col == null) return this;
    final (allowed, _) = canRemove(columnId);
    if (!allowed) return this;

    final item = itemColumn;
    final parentIdOfCol = col.parentId;

    final updated = <ColumnDef>[];
    for (final c in _columns) {
      if (c.id == columnId) continue;
      if (c.id == item?.id && c.parentId == columnId) {
        updated.add(c.copyWith(parentId: parentIdOfCol));
      } else if (c.parentId == columnId) {
        updated.add(c.copyWith(parentId: parentIdOfCol));
      } else {
        updated.add(c);
      }
    }

    var pos = 0;
    final reindexed = updated.map((c) => c.copyWith(position: pos++)).toList();
    return SheetDef(id: id, key: key, title: title, columns: reindexed);
  }

  SheetDef renameColumn(int columnId, String newLabel) {
    final updated = _columns.map((c) {
      if (c.id == columnId) {
        return c.copyWith(label: newLabel);
      }
      return c;
    }).toList();
    return SheetDef(id: id, key: key, title: title, columns: updated);
  }

  SheetDef reparentColumn(int columnId, int? newParentId) {
    final updated = _columns.map((c) {
      if (c.id == columnId) {
        return c.copyWith(parentId: newParentId, clearParent: newParentId == null);
      }
      return c;
    }).toList();
    return SheetDef(id: id, key: key, title: title, columns: updated);
  }
}
