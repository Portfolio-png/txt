import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// How wide and how tall the sheet draws itself.
//
// Nothing in `sheet/` read the viewport at all: column widths came from a
// switch on kind with no width parameter, and the cell height was the literal
// 46 in two files. So the item sheet needed ~1645px, got 1292 on a 1600px
// monitor and overflowed — and on a 2000px monitor left ~47px of gutter unspent
// while truncating its headers just the same.

void main() {
  group('density by viewport', () {
    test('a narrow window gets tighter rows than a wide one', () {
      final narrow = SheetMetrics.forWidth(1100);
      final wide = SheetMetrics.forWidth(1800);

      expect(narrow.rowHeight, lessThan(wide.rowHeight));
      expect(narrow.tableGap, lessThanOrEqualTo(wide.tableGap));
      expect(narrow.valueFontSize, lessThanOrEqualTo(wide.valueFontSize));
    });

    test('type never drops below the house floor', () {
      for (final width in [900.0, 1100.0, 1366.0, 1600.0, 1920.0, 2560.0]) {
        final m = SheetMetrics.forWidth(width);
        expect(m.valueFontSize, greaterThanOrEqualTo(14),
            reason: 'body text at ${width}px');
        expect(m.labelFontSize, greaterThanOrEqualTo(14),
            reason: 'header label at ${width}px');
      }
    });
  });

  group('fitting the columns to the room', () {
    // The body of the sheet screen at a 1600px window: 1600 less the 268px app
    // rail and 40px of padding.
    const body = 1292.0;

    // What the strip does not scale: the status gutter, one border per table,
    // and the gaps between them. Three tables, one gutter.
    const chrome = 34.0 + 3 * 2 + 10 * 2;

    test('a window wider than the content widens every column', () {
      const m = SheetMetrics.fallback;
      final exact = m.fitTo(1600, columns: itemSheetColumns);
      final roomy = m.fitTo(1600, columns: itemSheetColumns.take(4));

      expect(roomy.scale, greaterThan(exact.scale));
      expect(
        roomy.widthFor(ColumnKind.code),
        greaterThan(exact.widthFor(ColumnKind.code)),
        reason: 'the surplus should reach the columns that truncate',
      );
    });

    test('a window narrower than the content shrinks the columns to fit', () {
      // This used to assert `scale == 1` — that a narrow window did NOT shrink,
      // on the grounds that squeezing the columns made the headers worse. That
      // reversed: `scale` multiplies widths only, the font comes from the
      // density tier and the house floor is 14, so width is the only thing left
      // that can give. A 154px column beats a sideways scrollbar.
      const m = SheetMetrics.fallback;
      final fitted = m.fitTo(body, columns: itemSheetColumns, fixedWidth: chrome);

      expect(fitted.scale, lessThan(1));
      expect(
        fitted.stripWidth(itemSheetColumns, fixedWidth: chrome),
        lessThanOrEqualTo(body),
      );
      expect(fitted.fitsIn(body, itemSheetColumns, fixedWidth: chrome), isTrue);
    });

    test('the party sheet fits the same window', () {
      const m = SheetMetrics.fallback;
      final fitted =
          m.fitTo(body, columns: partySheetColumns, fixedWidth: chrome);
      expect(
        fitted.fitsIn(body, partySheetColumns, fixedWidth: chrome),
        isTrue,
      );
    });

    test('one property added with the + still fits', () {
      const m = SheetMetrics.fallback;
      final withOne = [
        ...itemSheetColumns,
        const ColumnDef(
          id: 99,
          sheetId: 1,
          label: 'Plating',
          kind: ColumnKind.list,
          position: 6,
          bindsTo: 'variation:Plating',
        ),
      ];
      final fitted = m.fitTo(body, columns: withOne, fixedWidth: chrome);
      expect(fitted.fitsIn(body, withOne, fixedWidth: chrome), isTrue);
    });

    test('the gutter and the gaps never scale', () {
      // The whole point of keeping them out of the scaled sum: a shrunk chip
      // rail breaks the chips it exists to hold.
      const m = SheetMetrics.fallback;
      final fitted = m.fitTo(body, columns: itemSheetColumns, fixedWidth: chrome);
      expect(fitted.gutterWidth, m.gutterWidth);
      expect(fitted.tableGap, m.tableGap);
      expect(fitted.valueFontSize, m.valueFontSize);
      expect(fitted.labelFontSize, m.labelFontSize);
    });

    test('the shrink stops before a cell is unusable, and says it did not fit', () {
      // Twenty columns cannot be made to fit 1292px and should not pretend to.
      // The floor holding AND `fitsIn` answering false is the contract — it is
      // what makes the strip wrap instead of drawing slivers.
      const m = SheetMetrics.fallback;
      final many = [
        for (var i = 0; i < 20; i++)
          ColumnDef(
            id: 100 + i,
            sheetId: 1,
            label: 'P$i',
            kind: ColumnKind.list,
            position: i,
            bindsTo: 'variation:P$i',
          ),
      ];
      final fitted = m.fitTo(body, columns: many, fixedWidth: chrome);

      for (final c in many) {
        expect(
          fitted.widthFor(c.kind),
          greaterThanOrEqualTo(SheetMetrics.minColumnWidth - 1),
          reason: 'a cell narrower than this is all affordance and no value',
        );
      }
      expect(fitted.fitsIn(body, many, fixedWidth: chrome), isFalse);
    });

    test('the stretch is capped', () {
      // Past about a third wider, columns stop looking like columns.
      const m = SheetMetrics.fallback;
      final fitted = m.fitTo(4000, columns: itemSheetColumns.take(3));
      expect(fitted.scale, lessThanOrEqualTo(SheetMetrics.maxScale));
    });

    test('an unbounded parent is left alone rather than stretched', () {
      const m = SheetMetrics.fallback;
      expect(
        m.fitTo(double.infinity, columns: itemSheetColumns).scale,
        m.scale,
      );
    });
  });

  group('height follows the cells', () {
    test('a grid is its title bar, its header and its rows', () {
      const m = SheetMetrics.fallback;
      for (final rows in [1, 2, 3, 10]) {
        expect(
          m.gridHeight(rows),
          12 + 2 + m.titleBarHeight + m.headerHeight + m.rowHeight * rows,
          reason: '$rows rows',
        );
      }
    });

    test('it grows by exactly one row height per row', () {
      const m = SheetMetrics.fallback;
      // The old formula added 50 per row while a row was 46, so dead air
      // accrued at 4px a row.
      expect(m.gridHeight(2) - m.gridHeight(1), m.rowHeight);
      expect(m.gridHeight(10) - m.gridHeight(9), m.rowHeight);
    });
  });

  group('column widths', () {
    test('every kind has one, and the wordy kinds get more', () {
      for (final kind in ColumnKind.values) {
        expect(SheetMetrics.baseWidthFor(kind), greaterThan(0),
            reason: '$kind');
      }
      expect(
        SheetMetrics.baseWidthFor(ColumnKind.list),
        greaterThan(SheetMetrics.baseWidthFor(ColumnKind.time)),
      );
    });

    test('a table knows what it occupies', () {
      const m = SheetMetrics.fallback;
      final width = m.tableWidth(itemSheetColumns);
      var sum = 2.0;
      for (final c in itemSheetColumns) {
        sum += m.widthFor(c.kind);
      }
      expect(width, sum);
      expect(
        m.tableWidth(itemSheetColumns, withGutter: true) - width,
        m.gutterWidth,
      );
    });
  });
}
