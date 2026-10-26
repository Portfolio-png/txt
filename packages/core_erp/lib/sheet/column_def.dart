import 'package:flutter/foundation.dart';

enum ColumnKind {
  list,
  seq,
  code,
  text,
  number,

  /// A true quantity — an integer count of base units with a family.
  ///
  /// **Nothing uses this yet, deliberately.** The sheet's one candidate was
  /// Thickness, and a gauge is not a quantity: `Units.parse` rejects the
  /// suffix, and the item model keeps vendor gauge values verbatim on purpose.
  /// When a real quantity column appears, `ColumnDef.familyId`/`entryUnitId`
  /// (already here, still unread) and `UnitFamilyService.familyOfUnit` are what
  /// it needs, storing integer base units in `CellValue.intValue`.
  quantity,

  /// A sheet-metal gauge, filled from `swgGaugeTable`. Mirrors
  /// `ItemVariationNodeDefinition.inputType == 'Gauge'`.
  gauge,

  /// A material from the materials master, carrying `materialTypeId`. Mirrors
  /// `inputType == 'Material'`.
  material,

  money,
  phone,
  email,
  date,
  time,

  /// A yes/no tick. Ticked is `CellValue.intValue == 1`; unticked is an EMPTY
  /// cell rather than 0, so a row with only an untouched tick still reads as
  /// blank and is skipped instead of saved.
  check,
}

enum ColumnRole {
  group,
  item,
  stamp,
}

enum ColumnSource {
  options,
  party,
  contact,
}

enum ValueMode {
  auto,
  edit,
  ok,
}

enum TableGroup {
  groupItem,
  properties,
  primaryGroup,
  created;

  static const TableGroup independent = TableGroup.primaryGroup;
}

@immutable
class ColumnDef {
  const ColumnDef({
    required this.id,
    required this.sheetId,
    required this.label,
    required this.kind,
    this.role,
    this.parentId,
    required this.position,
    this.source = ColumnSource.options,
    this.familyId,
    this.entryUnitId,
    this.archivedAt,
    this.bindsTo,
  });

  final int id;
  final int sheetId;
  final String label;
  final ColumnKind kind;
  final ColumnRole? role;
  final int? parentId;
  final int position;
  final ColumnSource source;
  final int? familyId;
  final int? entryUnitId;
  final String? archivedAt;

  /// What this cell feeds on the entity being edited — `'name'`, `'partNo'`,
  /// `'variation:Alloy'`, `'developedFor.quotationAmount'`.
  ///
  /// A cell is keyed by `columnId` alone, so without this a mapper has nothing
  /// to key off and every binding ends up as a table of literal ids. Null means
  /// the column is for reading only and nothing is written from it.
  final String? bindsTo;

  bool get isDefault => role != null;
  bool get isGroup => role == ColumnRole.group;
  bool get isItem => role == ColumnRole.item;
  bool get isStamp => role == ColumnRole.stamp;
  bool get isPrimaryGroup => parentId == null && !isGroup && !isItem && !isStamp;
  bool get isIndependent => isPrimaryGroup;

  String get kindTag => switch (kind) {
        ColumnKind.list => 'List',
        ColumnKind.seq => 'No.',
        ColumnKind.code => 'Code',
        ColumnKind.text => 'Text',
        ColumnKind.number => '123',
        ColumnKind.quantity => 'Qty',
        ColumnKind.gauge => 'G',
        ColumnKind.material => 'Mat',
        ColumnKind.money => '₹',
        ColumnKind.phone => 'Ph',
        ColumnKind.email => '@',
        ColumnKind.date => 'Date',
        ColumnKind.time => 'Time',
        ColumnKind.check => '✓',
      };

  ColumnDef copyWith({
    int? id,
    int? sheetId,
    String? label,
    ColumnKind? kind,
    ColumnRole? role,
    int? parentId,
    bool clearParent = false,
    int? position,
    ColumnSource? source,
    int? familyId,
    int? entryUnitId,
    String? archivedAt,
    String? bindsTo,
  }) {
    return ColumnDef(
      id: id ?? this.id,
      sheetId: sheetId ?? this.sheetId,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      role: role ?? this.role,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      position: position ?? this.position,
      source: source ?? this.source,
      familyId: familyId ?? this.familyId,
      entryUnitId: entryUnitId ?? this.entryUnitId,
      archivedAt: archivedAt ?? this.archivedAt,
      bindsTo: bindsTo ?? this.bindsTo,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColumnDef &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sheetId == other.sheetId &&
          label == other.label &&
          kind == other.kind &&
          role == other.role &&
          parentId == other.parentId &&
          position == other.position &&
          source == other.source &&
          familyId == other.familyId &&
          entryUnitId == other.entryUnitId &&
          archivedAt == other.archivedAt;

  @override
  int get hashCode => Object.hash(
        id,
        sheetId,
        label,
        kind,
        role,
        parentId,
        position,
        source,
        familyId,
        entryUnitId,
        archivedAt,
      );
}
