import 'package:flutter_test/flutter_test.dart';
import 'package:core_erp/sheet/sheet.dart';

void main() {
  group('SheetEngine and Shared Test Vectors', () {
    late ItemMasterController masterCtrl;

    setUp(() {
      // The shared vectors are written against the demo fixture.
      masterCtrl = ItemMasterController(demoData: true);
    });

    tearDown(() {
      masterCtrl.dispose();
    });

    test('Vector 1: Changing Type from Dolly to Rocker keeps Patti and moves Part No to Rocker series: 10', () {
      final sheet = masterCtrl.groupItemController.sheetDef;
      final draft = masterCtrl.groupItemController.draft;

      expect(draft.get(1)?.optionLabel, 'Switch Action');
      expect(draft.get(2)?.optionLabel, 'Dolly');
      expect(draft.get(3)?.optionLabel, 'Patti');
      expect(draft.get(4)?.intValue, 48);

      // Change Type to Rocker (id: 102)
      final rockerOpt = masterCtrl.groupItemController.options.firstWhere((o) => o.id == 102);
      masterCtrl.groupItemController.setOption(2, rockerOpt);

      // Patti (id 204 exists under Rocker 102), so it is kept
      expect(masterCtrl.groupItemController.draft.get(2)?.optionLabel, 'Rocker');
      expect(masterCtrl.groupItemController.draft.get(3)?.optionLabel, 'Patti');
      // Counter for Rocker series is 9, so next is 10
      expect(masterCtrl.groupItemController.draft.get(4)?.intValue, 10);
      // SA RP (Switch Action › Rocker › Patti) + B 22G (Brass, 22 Gauge) + 10.
      // The properties are part of the code now: every top-level property
      // contributes, numbers whole and letters first.
      expect(
        masterCtrl.groupItemController.draft.get(5)?.textValue,
        'SARPB22G10',
      );
    });

    test('Vector 2: Changing Group from Switch Action to Cutout clears Type and Part Name; the properties stay', () {
      final cutoutOpt = masterCtrl.groupItemController.options.firstWhere((o) => o.id == 11);
      masterCtrl.groupItemController.setOption(1, cutoutOpt);

      expect(masterCtrl.groupItemController.draft.get(1)?.optionLabel, 'Cutout');
      expect(masterCtrl.groupItemController.draft.get(2), isNull);
      expect(masterCtrl.groupItemController.draft.get(3), isNull);
      // A property hangs off nothing in the group chain, so moving the part to
      // another group must not wipe what it is pressed from.
      expect(masterCtrl.groupItemController.draft.get(6)?.optionLabel, 'Brass');
      expect(masterCtrl.groupItemController.draft.get(7)?.textValue, '22 Gauge');
    });

    test('Vector 3: Putting Part Name directly under Group moves Type to Properties', () {
      final sheet = masterCtrl.groupItemController.sheetDef;
      // Reparent Part Name (id: 3) to Group (id: 1)
      masterCtrl.groupItemController.reparentColumn(3, 1);

      final updatedSheet = masterCtrl.groupItemController.sheetDef;
      final partNameCol = updatedSheet.getColumn(3)!;
      final typeCol = updatedSheet.getColumn(2)!;

      // Part Name is now in Group and item
      expect(updatedSheet.tableOf(partNameCol), TableGroup.groupItem);
      // Type is now detached from the item path, so it moves to Properties or stays based on hierarchy
      expect(updatedSheet.tableOf(typeCol), TableGroup.properties);
    });

    test('Vector 4: a property added with the + lands in Properties, whichever kind it takes', () {
      // The regression this whole change exists to prevent. `tableOf` used to
      // decide from `ColumnKind`, so Alloy and Thickness were in Properties by
      // accident (neither is a `list`) — and the + dialog's default and most
      // natural choice, "A list of values", filed the new property under
      // Primary Group instead.
      for (final kind in [
        ColumnKind.list,
        ColumnKind.material,
        ColumnKind.gauge,
        ColumnKind.text,
      ]) {
        final ctrl = ItemMasterController(demoData: true);
        addTearDown(ctrl.dispose);

        ctrl.groupItemController.addPropertyColumn('Plating', kind: kind);
        final sheet = ctrl.groupItemController.sheetDef;
        final added = sheet.columns.firstWhere((c) => c.label == 'Plating');

        expect(sheet.tableOf(added), TableGroup.properties, reason: '$kind');
        expect(
          sheet.variationColumns.map((c) => c.label),
          contains('Plating'),
          reason: '$kind should feed the variation tree',
        );
      }
    });

    test('Vector 4b: a parentless list column that binds nothing is still independent', () {
      // The Primary Group table draws no column on either live sheet now, but
      // the concept is intact: it is for a list that hangs off nothing and is
      // not a property.
      final sheet = SheetDef(
        id: 9,
        key: 'other',
        title: 'Other',
        columns: const [
          ColumnDef(
            id: 1,
            sheetId: 9,
            label: 'Group',
            kind: ColumnKind.list,
            role: ColumnRole.group,
            position: 0,
          ),
          ColumnDef(
            id: 2,
            sheetId: 9,
            label: 'Shift',
            kind: ColumnKind.list,
            position: 1,
          ),
        ],
      );

      expect(sheet.tableOf(sheet.getColumn(2)!), TableGroup.independent);
    });

    test('Vector 5: Column can only take parent to its left; moving left past parent is refused', () {
      final sheet = masterCtrl.groupItemController.sheetDef;
      // Col 2 (Type) parent is Col 1 (Group). Col 2 cannot take a parent to its right (e.g. col 3).
      final (canReparentRight, reasonReparent) = sheet.canReparent(2, 3);
      expect(canReparentRight, isFalse);
      expect(reasonReparent, 'A column can only take a parent to its left.');

      // Add a dependent property in Properties table that sits immediately right of its parent
      masterCtrl.groupItemController.addColumn(
        label: 'Sub Spec',
        kind: ColumnKind.text,
        parentId: 7, // sits under Thickness
      );
      final updatedSheet = masterCtrl.groupItemController.sheetDef;
      final subSpecCol = updatedSheet.columns.firstWhere((c) => c.label == 'Sub Spec');
      final (canMovePastParent, reasonMove) = updatedSheet.canMoveLeft(subSpecCol.id);
      expect(canMovePastParent, isFalse);
      expect(reasonMove, 'A column cannot move left past its parent.');
    });

    test('Vector 6: Removing a sub-group level re-attaches child to its own parent', () {
      // Add a sub-group level "Sub Category" before Part Name
      masterCtrl.groupItemController.addSubGroupLevel('Sub Category');
      final sheetWithSub = masterCtrl.groupItemController.sheetDef;
      final subCol = sheetWithSub.columns.firstWhere((c) => c.label == 'Sub Category');
      final partNameCol = sheetWithSub.getColumn(3)!;
      expect(partNameCol.parentId, subCol.id);

      // Now remove Sub Category
      masterCtrl.groupItemController.removeColumn(subCol.id);
      final finalSheet = masterCtrl.groupItemController.sheetDef;
      final finalPartName = finalSheet.getColumn(3)!;
      // Re-attached to Type (id: 2)
      expect(finalPartName.parentId, 2);
    });

    test('Vector 7: Code for Switch Action › Dolly › Patti in Brass 22G, '
        'No 48, is SADPB22G48', () {
      // The trunk is unchanged — SADP is still the forty-eighth Dolly patti in
      // Switch Action. What is new is that the properties are in the code:
      // B for Brass, 22G for 22 Gauge (the digits kept, so 24 Gauge does not
      // collide with it).
      final draft = masterCtrl.groupItemController.draft;
      expect(draft.get(5)?.textValue, 'SADPB22G48');
    });

    test('Vector 7b: a part with no properties keeps the bare trunk', () {
      // Nothing changes for a part that has no properties — the code is the
      // trunk and the number, as it always was.
      final ctrl = ItemMasterController(demoData: true);
      addTearDown(ctrl.dispose);
      for (final id in [6, 7, 8]) {
        ctrl.groupItemController.updateValue(
          id,
          CellValue(columnId: id),
        );
      }
      expect(ctrl.groupItemController.draft.get(5)?.textValue, 'SADP48');
    });

    test('Vector 8: Edit running number at or below last used is refused; above is accepted', () {
      // Last used for scope is 47
      masterCtrl.groupItemController.updateValue(
        4,
        const CellValue(columnId: 4, intValue: 40, mode: ValueMode.edit),
      );
      expect(masterCtrl.groupItemController.errors[4]?.code, 'seq_used');

      // Greater than last used
      masterCtrl.groupItemController.updateValue(
        4,
        const CellValue(columnId: 4, intValue: 50, mode: ValueMode.edit),
      );
      expect(masterCtrl.groupItemController.errors[4], isNull);
    });

    test('Vector 9: Typed phone of 9 digits and email without dot after @ are both refused', () {
      masterCtrl.clientVendorController.updateTextValue(23, '987654321'); // 9 digits
      expect(masterCtrl.clientVendorController.errors[23]?.code, 'phone_digits');

      masterCtrl.clientVendorController.updateTextValue(24, 'bademail@company'); // no dot
      expect(masterCtrl.clientVendorController.errors[24]?.code, 'email_format');
    });

    test('Vector 10: Picking Kissan Jain fills Director, phone and email', () {
      final kissan = masterCtrl.clientVendorController.contacts.firstWhere((c) => c.name == 'Kissan Jain');
      masterCtrl.pickContact(kissan);

      expect(masterCtrl.clientVendorController.draft.get(21)?.optionLabel, 'Kissan Jain');
      expect(masterCtrl.clientVendorController.draft.get(22)?.textValue, 'Director');
      expect(masterCtrl.clientVendorController.draft.get(23)?.textValue, '9865656560');
      expect(masterCtrl.clientVendorController.draft.get(24)?.textValue, 'kissan@goldmedal.in');
    });

    test('Vector 11: with no writer, a save says nothing was saved', () async {
      // This vector used to assert `success == true` and `savedItemId == 5012`
      // on a controller with no way to write anything — the id was a literal
      // and the two stamps were hand-formatted strings. A save that cannot
      // happen must not look like one that did.
      expect(masterCtrl.isSaved, isFalse);
      expect(masterCtrl.groupItemController.draft.get(9)?.textValue, 'Set on save');

      final success = await masterCtrl.saveItem();
      expect(success, isFalse);
      expect(masterCtrl.isSaved, isFalse);
      expect(masterCtrl.savedItemId, isNull);
      expect(masterCtrl.statusBarMessage, contains('Nothing was saved'));
      expect(
        masterCtrl.groupItemController.draft.get(9)?.textValue,
        'Set on save',
        reason: 'an unsaved sheet must not carry a stamp',
      );
    });

    test('Vector 11b: the id, code and stamps come from the saved record', () async {
      final writer = _RecordingBinding(
        _SavedRecord(id: 5012, partCode: 'SADP48', createdAt: DateTime(2026, 5, 15, 10, 5)),
      );
      final ctrl = ItemMasterController(binding: writer, demoData: true);
      addTearDown(ctrl.dispose);

      final success = await ctrl.saveItem();
      expect(success, isTrue, reason: ctrl.statusBarMessage);
      expect(writer.savedRows, isNotEmpty, reason: 'the rows must reach the writer');

      expect(ctrl.savedItemId, 5012);
      expect(ctrl.groupItemController.draft.get(9)?.textValue, '15/05/26');
      expect(ctrl.groupItemController.draft.get(10)?.textValue, '10:05');
      expect(ctrl.statusBarMessage, contains('SADP48'));
    });

    test('Vector 11c: a second save while one is in flight does not start', () async {
      // `ItemsProvider._save` answers null with no error set when a save is
      // already running, so without this guard the second one reads as a
      // silent failure.
      final writer = _RecordingBinding(
        _SavedRecord(id: 1, partCode: 'X1', createdAt: DateTime(2026)),
        delay: const Duration(milliseconds: 40),
      );
      final ctrl = ItemMasterController(binding: writer, demoData: true);
      addTearDown(ctrl.dispose);

      final first = ctrl.saveItem();
      final second = await ctrl.saveItem();

      expect(second, isFalse);
      expect(ctrl.statusBarMessage, contains('Still saving'));
      expect(await first, isTrue);
      expect(writer.callCount, 1, reason: 'the second save must never start');
    });

    test('Vector 11d: a writer that refuses is reported, not swallowed', () async {
      final writer = _RecordingBinding(null, error: 'Could not reach the server.');
      final ctrl = ItemMasterController(binding: writer, demoData: true);
      addTearDown(ctrl.dispose);

      expect(await ctrl.saveItem(), isFalse);
      expect(ctrl.isSaved, isFalse);
      expect(ctrl.statusBarMessage, 'Could not reach the server.');
    });
  });
}

/// The small surface a saved record is read through — the sheet layer reads
/// `id`, `partCode` and `createdAt` off whatever it is handed, so that it need
/// not import the items feature to save one.
class _SavedRecord {
  _SavedRecord({required this.id, required this.partCode, required this.createdAt});
  final int id;
  final String partCode;
  final DateTime createdAt;
}

class _RecordingBinding extends SheetBinding<Object?> {
  _RecordingBinding(this._record, {this.error, this.delay});

  final _SavedRecord? _record;
  final String? error;
  final Duration? delay;

  final List<SheetDraft> savedRows = [];
  int callCount = 0;

  @override
  String? get lastError => error;

  @override
  Future<List<Object?>?> save(List<SheetDraft> rows) async {
    callCount += 1;
    savedRows.addAll(rows);
    if (delay != null) await Future<void>.delayed(delay!);
    return _record == null ? null : [_record];
  }

  @override
  Future<Object?> saveRow(SheetDraft row) async {
    callCount += 1;
    savedRows.add(row);
    if (delay != null) await Future<void>.delayed(delay!);
    return _record;
  }

  @override
  List<SheetDraft> toDrafts(List<Object?> entities) => const [];
}
