import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// An open sheet following the parts it shows as they change elsewhere.
//
// It read each part once: a part deleted or archived in another window sat
// there looking saved and editable, and a quotation changed elsewhere never
// showed — so the next save here wrote the old one back.

class _Part {
  _Part(this.id, this.name, {this.quote, this.isArchived = false});
  final int id;
  final String name;
  final int? quote;
  final bool isArchived;
  final String partCode = '';
  final DateTime createdAt = DateTime(2026);
}

class _Binding extends SheetBinding<Object?> {
  @override
  String? get lastError => null;

  @override
  Future<List<Object?>?> save(List<SheetDraft> rows) async => null;

  @override
  Future<Object?> saveRow(SheetDraft row) async => null;

  @override
  List<SheetDraft> toDrafts(List<Object?> entities) => [
        for (final e in entities.cast<_Part>())
          SheetDraft(sheetKey: 'item', entityId: e.id, values: {
            3: CellValue(columnId: 3, textValue: e.name),
          }),
      ];

  @override
  ({SheetDraft deal, Set<int> ticked})? dealOf(Object? entity) {
    final part = entity as _Part;
    if (part.quote == null) return null;
    final quotation = dealSheetColumns
        .firstWhere((c) => c.bindsTo == SheetBindsTo.developedForQuotation)
        .id;
    return (
      deal: SheetDraft(sheetKey: 'item_party', values: {
        quotation: CellValue(
          columnId: quotation,
          intValue: part.quote,
          textValue: '${part.quote}',
        ),
      }),
      ticked: const <int>{},
    );
  }
}

int _quoteColumn() => dealSheetColumns
    .firstWhere((c) => c.bindsTo == SheetBindsTo.developedForQuotation)
    .id;

void main() {
  ItemMasterController open(_Part part) {
    final ctrl = ItemMasterController.live(binding: _Binding());
    addTearDown(ctrl.dispose);
    ctrl.loadItems([part]);
    return ctrl;
  }

  test('a part deleted elsewhere marks its row and offers no edit', () {
    final ctrl = open(_Part(500, 'Patti'));
    // Something else is still in the catalogue; this part is not.
    ctrl.refreshLockedRows([_Part(501, 'Dabbi')]);
    expect(ctrl.isRowGone(0), isTrue);
    expect(ctrl.rowError(0), contains('deleted'));
    expect(ctrl.groupItemController.isRowLocked(0), isTrue);
  });

  test('a part archived elsewhere says so, and coming back clears it', () {
    final ctrl = open(_Part(500, 'Patti'));
    ctrl.refreshLockedRows([_Part(500, 'Patti', isArchived: true)]);
    expect(ctrl.rowError(0), contains('archived'));
    ctrl.refreshLockedRows([_Part(500, 'Patti')]);
    expect(ctrl.isRowGone(0), isFalse);
    expect(ctrl.rowError(0), isNull);
  });

  test('the deal follows the part when nothing here is unsaved', () {
    final ctrl = open(_Part(500, 'Patti', quote: 85000));
    final column = _quoteColumn();
    expect(ctrl.clientVendorController.draft.get(column)?.intValue, 85000);

    ctrl.refreshLockedRows([_Part(500, 'Patti', quote: 90000)]);
    expect(ctrl.clientVendorController.draft.get(column)?.intValue, 90000);
    expect(ctrl.clientVendorController.draft.isDirtySinceSave, isFalse);
  });

  test('a deal being typed into is left alone', () {
    final ctrl = open(_Part(500, 'Patti', quote: 85000));
    final column = _quoteColumn();
    ctrl.clientVendorController.updateTextValue(column, '87000');

    ctrl.refreshLockedRows([_Part(500, 'Patti', quote: 90000)]);
    expect(ctrl.clientVendorController.draft.get(column)?.textValue, '87000');
  });
}
