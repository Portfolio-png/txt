import 'dart:async';

import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// What a row commit does when the sheet keeps moving under it.
//
// A save takes a second or two against the real server, and in that time the
// cursor leaves the next row, rows are removed and keys keep arriving. Each of
// these used to be decided by the row INDEX captured before the await — which
// by then could name a different row.

class _Record {
  _Record(this.id);
  final int id;
  final String partCode = '';
  final DateTime createdAt = DateTime(2026, 5, 15, 10, 5);
}

/// Saves only when told to, so a test can act while one is in flight.
class _GatedBinding extends SheetBinding<Object?> {
  final List<Completer<void>> gates = [];
  final List<SheetDraft> rows = [];
  int _nextId = 700;

  @override
  String? get lastError => null;

  @override
  Future<List<Object?>?> save(List<SheetDraft> rows) async => null;

  @override
  Future<Object?> saveRow(SheetDraft row) async {
    rows.add(row);
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return _Record(_nextId++);
  }

  @override
  List<SheetDraft> toDrafts(List<Object?> entities) => const [];

  /// Lets every waiting save answer, and the follow-ups they trigger.
  Future<void> releaseAll() async {
    for (var i = 0; i < 10; i += 1) {
      final open = gates.where((g) => !g.isCompleted).toList();
      if (open.isEmpty) return;
      for (final gate in open) {
        gate.complete();
      }
      await pumpEventQueue();
    }
  }
}

/// A demo controller with [count] filled rows — the fixture's part, copied.
ItemMasterController _sheetWith(_GatedBinding writer, int count) {
  final ctrl = ItemMasterController(binding: writer, demoData: true);
  // The fixture deal is a demo; these tests are about the part rows.
  ctrl.setExternal(false);
  final sheet = ctrl.groupItemController;
  final seed = sheet.draftAt(0);
  for (var i = 1; i < count; i += 1) {
    sheet.addRow(draft: seed.clone());
  }
  return ctrl;
}

void main() {
  test('a row that leaves while another saves is queued, not dropped', () async {
    final writer = _GatedBinding();
    final ctrl = _sheetWith(writer, 2);
    addTearDown(ctrl.dispose);

    final first = ctrl.commitRow(0);
    await pumpEventQueue();
    final second = await ctrl.commitRow(1);
    expect(second, isFalse, reason: 'it cannot start yet');
    expect(ctrl.statusBarMessage, contains('row 2 is next'));

    await writer.releaseAll();
    expect(await first, isTrue);
    expect(writer.rows, hasLength(2), reason: 'the queued row was written too');
    expect(ctrl.savedRows, {0, 1});
  });

  test('removing a row mid-save stamps the id on the row that saved', () async {
    final writer = _GatedBinding();
    final ctrl = _sheetWith(writer, 3);
    addTearDown(ctrl.dispose);
    final sheet = ctrl.groupItemController;
    final saving = sheet.draftAt(1);
    final untouched = sheet.draftAt(2);

    final commit = ctrl.commitRow(1);
    await pumpEventQueue();
    sheet.removeRow(0);
    await writer.releaseAll();
    expect(await commit, isTrue);

    // The saved row is now index 0; the row below it never saved.
    expect(sheet.draftAt(0).entityId, 700);
    expect(sheet.draftAt(1).entityId, isNull);
    expect(identical(sheet.draftAt(1), untouched), isTrue);
    expect(saving.entityId, isNull, reason: 'replaced, not mutated');
  });

  test('typing into a row while it saves keeps that edit unsaved', () async {
    final writer = _GatedBinding();
    final ctrl = _sheetWith(writer, 1);
    addTearDown(ctrl.dispose);
    final sheet = ctrl.groupItemController;

    final commit = ctrl.commitRow(0);
    await pumpEventQueue();
    sheet.updateValue(
      6,
      const CellValue(columnId: 6, optionId: 302, optionLabel: 'Aluminium'),
      row: 0,
    );
    await writer.releaseAll();
    expect(await commit, isTrue);

    expect(sheet.draftAt(0).entityId, 700, reason: 'it did save');
    expect(sheet.draftAt(0).isDirtySinceSave, isTrue,
        reason: 'Aluminium was typed after the save left');
    expect(sheet.isRowLocked(0), isFalse, reason: 'still open for that edit');
  });

  group('typed amounts', () {
    SheetController deal() => SheetController(
          sheetDef: SheetDef(id: 2, key: 'deal', title: 'Deal', columns: dealSheetColumns),
        );
    int quotation(SheetController c) =>
        c.sheetDef.columnBoundTo(SheetBindsTo.developedForQuotation)!.id;

    test('paise are kept, not folded into the rupees', () {
      final c = deal();
      addTearDown(c.dispose);
      final id = quotation(c);
      c.updateTextValue(id, '12.50');
      final cell = c.draft.get(id)!;
      expect(cell.intValue, isNull, reason: '1250 was what this used to hold');
      expect(SheetEngine.parseMoney(cell.textValue), 12.5);
      expect(c.errors[id], isNull);
    });

    test('a grouped whole amount still reads as whole', () {
      final c = deal();
      addTearDown(c.dispose);
      final id = quotation(c);
      c.updateTextValue(id, '85,000');
      expect(c.draft.get(id)!.intValue, 85000);
      // And a later decimal does not keep the old whole number.
      c.updateTextValue(id, '85,000.5');
      expect(c.draft.get(id)!.intValue, isNull);
    });

    test('words are refused, and so is a negative amount', () {
      final c = deal();
      addTearDown(c.dispose);
      final id = quotation(c);
      c.updateTextValue(id, 'abc');
      expect(c.errors[id]?.code, 'not_number');
      c.updateTextValue(id, '-5');
      expect(c.errors[id]?.code, 'not_number');
    });
  });

  test('a stored part name is a duplicate whatever its case', () {
    final c = SheetController(
      sheetDef: SheetDef(id: 1, key: 'item', title: 'Item', columns: itemSheetColumns),
      options: const [
        ColumnOption(id: 10, columnId: 1, label: 'Switch Action'),
        ColumnOption(id: 101, columnId: 2, parentOptionId: 10, label: 'Dolly'),
        ColumnOption(id: 201, columnId: 3, parentOptionId: 101, label: 'Patti'),
      ],
      existingPaths: const {'switch action › dolly › patti'},
    );
    addTearDown(c.dispose);
    c.setOption(1, const ColumnOption(id: 10, columnId: 1, label: 'Switch Action'));
    c.setOption(2, const ColumnOption(id: 101, columnId: 2, parentOptionId: 10, label: 'Dolly'));
    c.setOption(3, const ColumnOption(id: 201, columnId: 3, parentOptionId: 101, label: 'Patti'));
    expect(c.errors[3]?.code, 'duplicate_item');
  });

  test('a part straight under a Group finds its names without a Type', () {
    final c = SheetController(
      sheetDef: SheetDef(id: 1, key: 'item', title: 'Item', columns: itemSheetColumns),
      options: const [
        ColumnOption(id: 10, columnId: 1, label: 'Switch Action'),
        // A name filed under the Group itself, as the binding offers one.
        ColumnOption(id: 501, columnId: 3, parentOptionId: 10, label: 'Plate'),
      ],
    );
    addTearDown(c.dispose);
    c.setOption(1, const ColumnOption(id: 10, columnId: 1, label: 'Switch Action'));
    c.updateValue(3, const CellValue(columnId: 3, optionId: 501, optionLabel: 'Plate'));
    expect(c.errors[3], isNull, reason: c.errors[3]?.message);
  });
}
