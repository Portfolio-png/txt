import 'package:flutter/material.dart';

import '../sheet_binding.dart';
import '../sheet_controller.dart';
import '../sheet_draft.dart';
import 'coloured_tabs.dart';

export 'coloured_tabs.dart';

/// The parts on the sheet as tabs, a browser's way, and under them the open
/// part's sheet: one per part, + for another. [ColouredTabs] over the sheet's
/// rows.
class PartTabs extends StatelessWidget {
  const PartTabs({
    super.key,
    required this.sheet,
    required this.colors,
    required this.onAddPart,
    required this.onClose,
    required this.child,
    this.showShortcuts = false,
  });

  final SheetController sheet;
  final PartTabColors colors;
  final VoidCallback onAddPart;

  /// Closes the tab at a row. The host asks first when the part holds work.
  final Future<void> Function(int row) onClose;

  /// The open part's sheet, drawn inside the frame.
  final Widget child;
  final bool showShortcuts;

  /// What a tab calls its part: the name, or "New part" until it has one.
  static String titleOf(SheetController sheet, SheetDraft draft) {
    final def = sheet.sheetDef;
    final column = def.columnBoundTo(SheetBindsTo.name) ?? def.itemColumn;
    final value = column == null ? null : draft.get(column.id);
    final name = (value?.optionLabel ?? value?.textValue ?? '').trim();
    return name.isEmpty ? 'New part' : name;
  }

  static String codeOf(SheetController sheet, SheetDraft draft) {
    final column = sheet.sheetDef.columnBoundTo(SheetBindsTo.partCode);
    return column == null ? '' : (draft.get(column.id)?.textValue ?? '').trim();
  }

  @override
  Widget build(BuildContext context) => ColouredTabs(
    strip: _SheetParts(sheet),
    colors: colors,
    onAdd: onAddPart,
    onClose: onClose,
    noun: 'part',
    plural: 'parts',
    keyPrefix: 'part',
    addKey: 'part_add_row',
    addShortcut: 'Alt+1',
    fillHeight: true,
    showShortcuts: showShortcuts,
    child: child,
  );
}

/// The sheet's rows as a [TabStrip].
class _SheetParts implements TabStrip {
  _SheetParts(this.sheet);
  final SheetController sheet;

  @override
  int get count => sheet.rowCount;
  @override
  int get selected => sheet.row;
  @override
  Object keyAt(int i) => sheet.draftAt(i).rowKey;
  @override
  String titleAt(int i) => PartTabs.titleOf(sheet, sheet.draftAt(i));
  @override
  String codeAt(int i) => PartTabs.codeOf(sheet, sheet.draftAt(i));
  @override
  bool savedAt(int i) => sheet.draftAt(i).entityId != null;
  @override
  String? closeWhyAt(int i) {
    // The line's own rule: a saved part is not taken off the sheet by an ×.
    if (savedAt(i))
      return 'Saved parts stay in the catalogue — Refresh starts a clear sheet';
    if (sheet.rowCount <= 1) return 'A sheet always keeps one part';
    return null;
  }

  @override
  String? closeTipAt(int i) => null;
  @override
  String? keyNameAt(int i) => null;
  @override
  void select(int i) => sheet.selectRow(i);
  @override
  void addListener(VoidCallback listener) => sheet.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => sheet.removeListener(listener);

  // A fresh adapter is made each build; equal over the same sheet, so the
  // strip does not re-subscribe every frame.
  @override
  bool operator ==(Object other) =>
      other is _SheetParts && identical(other.sheet, sheet);
  @override
  int get hashCode => identityHashCode(sheet);
}
