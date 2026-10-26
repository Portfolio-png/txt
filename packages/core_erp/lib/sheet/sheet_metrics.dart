import 'package:flutter/widgets.dart';

import 'column_def.dart';

/// How wide and how tall a sheet draws itself, decided from the viewport.
///
/// Every number the grid used to hard-code lives here, together, so density is
/// one decision rather than twenty literals scattered across four widgets.
/// The pattern is `_InventoryTableMetrics` in `inventory_screen.dart`, which
/// already does this for the inventory table — widths, heights and type sizes
/// chosen together from the available width.
///
/// It exists because **nothing in `sheet/` read the viewport at all.** Column
/// widths came from a `switch` on kind with no width parameter, and the cell
/// height was the literal `46` in two files. So the item sheet needed ~1645px,
/// got 1292px on a 1600px monitor, and overflowed — while on a 2000px monitor
/// it left ~47px of gutter unspent and truncated its headers just the same. The
/// extra room a wide desktop offers never reached the columns that needed it.
@immutable
class SheetMetrics {
  const SheetMetrics({
    required this.rowHeight,
    required this.headerHeight,
    required this.titleBarHeight,
    required this.labelFontSize,
    required this.valueFontSize,
    required this.gutterWidth,
    required this.tableGap,
    required this.scale,
  });

  /// A value cell's height, and the header's.
  final double rowHeight;
  final double headerHeight;

  /// The "Group and item" / "Properties" strip above each table.
  ///
  /// Padding 6 above and below, one line of [labelFontSize] text, and a 1px
  /// bottom border — so it tracks the type size rather than being a constant
  /// that goes a pixel short the moment the type grows.
  final double titleBarHeight;

  final double labelFontSize;
  final double valueFontSize;

  /// The row-state gutter down the left of the first table.
  final double gutterWidth;

  /// Between one table and the next.
  final double tableGap;

  /// How much wider than the base every column is drawn. 1.0 is the base.
  final double scale;

  /// The base width for a kind, before [scale].
  ///
  /// These are the old `_widthForKind` numbers, which were tuned by hand when
  /// the header badge font went 9 → 13 and were never tuned enough.
  static double baseWidthFor(ColumnKind kind) => switch (kind) {
        ColumnKind.list => 180,
        ColumnKind.material => 180,
        ColumnKind.email => 180,
        ColumnKind.text => 155,
        ColumnKind.quantity => 150,
        ColumnKind.gauge => 150,
        ColumnKind.phone => 150,
        ColumnKind.money => 150,
        ColumnKind.code => 150,
        ColumnKind.seq => 135,
        ColumnKind.number => 130,
        ColumnKind.date => 130,
        ColumnKind.time => 120,
        ColumnKind.check => 120,
      };

  /// Floored to a whole pixel: at `scale < 1` a width like 157.83 puts a cell's
  /// 1px border on a fractional device pixel, where it draws as 0 or 2.
  double widthFor(ColumnKind kind) => (baseWidthFor(kind) * scale).floorToDouble();

  /// Past about a third wider, columns stop looking like columns.
  static const double maxScale = 1.35;

  /// The narrowest a column may be drawn, however little room there is.
  ///
  /// A list cell spends 12px on padding and 18 on the caret, and 40 more on the
  /// "New" chip a value typed on this row carries. The house type floor of 14
  /// means the text cannot give instead, so under this the affordances are the
  /// whole cell. This constant is the dial that decides whether the first added
  /// property fits: at 92 it does, at 100 it does not. Do not "tidy" it.
  static const double minColumnWidth = 92;

  /// The lowest scale that leaves the narrowest of [columns] usable.
  static double scaleFloor(Iterable<ColumnDef> columns) {
    var narrowest = double.infinity;
    for (final column in columns) {
      final base = baseWidthFor(column.kind);
      if (base < narrowest) narrowest = base;
    }
    if (!narrowest.isFinite || narrowest <= 0) return 1;
    return (minColumnWidth / narrowest).clamp(0.0, 1.0);
  }

  /// This density, with every column scaled so the strip lands on [width].
  ///
  /// [columns] is every column the strip draws, across all of its tables.
  /// [fixedWidth] is everything that must NOT scale: the status gutter, one
  /// border per table, the gaps between tables and the strip's own padding.
  ///
  /// Solves `fixedWidth + Σ base(kind) * scale == width`. Handing the whole
  /// measured strip in as one number — chrome included — was wrong in **both**
  /// directions, because the chrome sat in the denominator but not in the sum.
  /// Drawn width came to `C + B·W/(C+B)`, which misses `W` by
  /// `C·(C + B − W)/(C + B)`: going up that left a few pixels unspent, but
  /// going down it is **positive**, so the columns were scaled to cover their
  /// own borders and overshot the viewport they had just been fitted to.
  ///
  /// The result is held in `[scaleFloor(columns), maxScale]`. At the floor the
  /// strip may still be wider than [width] — ask [fitsIn], do not assume.
  SheetMetrics fitTo(
    double width, {
    required Iterable<ColumnDef> columns,
    double fixedWidth = 0,
  }) {
    // An unbounded parent used to silently take the full 1.35 stretch.
    if (!width.isFinite || width <= 0) return this;

    var base = 0.0;
    for (final column in columns) {
      base += baseWidthFor(column.kind);
    }
    if (base <= 0) return this;

    final want = (width - fixedWidth) / base;
    return copyWith(scale: want.clamp(scaleFloor(columns), maxScale));
  }

  /// What the strip occupies as drawn.
  ///
  /// Summed from [widthFor] rather than re-derived from `base * scale`, so it
  /// carries the per-column flooring instead of predicting it. There must be
  /// exactly one width formula: a 0.1px disagreement with what layout produces
  /// is a `RenderFlex` overflow.
  double stripWidth(Iterable<ColumnDef> columns, {double fixedWidth = 0}) {
    var total = fixedWidth;
    for (final column in columns) {
      total += widthFor(column.kind);
    }
    return total;
  }

  /// Whether the strip fits [width] on one line, with nothing cut off.
  bool fitsIn(
    double width,
    Iterable<ColumnDef> columns, {
    double fixedWidth = 0,
  }) =>
      stripWidth(columns, fixedWidth: fixedWidth) <= width + 0.5;

  /// What a table of [columns] occupies, including its border.
  double tableWidth(Iterable<ColumnDef> columns, {bool withGutter = false}) {
    var total = withGutter ? gutterWidth : 0.0;
    for (final column in columns) {
      total += widthFor(column.kind);
    }
    return total + 2;
  }

  /// What a grid of [rowCount] rows occupies top to bottom.
  ///
  /// The height was two magic numbers on the screen — `96 + 50 * rowCount` —
  /// against a real need of `91 + 46 * rowCount`, so dead air accrued at 4px a
  /// row and the party sheet's fixed `150` overflowed the moment it held two.
  /// Derived from the same object that sizes the cells, it cannot drift.
  double gridHeight(int rowCount, {double verticalPadding = 12}) =>
      verticalPadding + 2 + titleBarHeight + headerHeight + rowHeight * rowCount;

  /// Picks the density tier for a viewport of [width], at scale 1.
  ///
  /// That is all it does. Fitting the columns to the room available is
  /// [fitTo]'s job, because it needs to know which part of the strip can shrink
  /// and only the caller knows that.
  factory SheetMetrics.forWidth(double width) {
    final base = width < 1120
        ? const SheetMetrics(
            rowHeight: 44,
            headerHeight: 44,
            titleBarHeight: 34,
            labelFontSize: 14,
            valueFontSize: 14,
            gutterWidth: 32,
            tableGap: 8,
            scale: 1,
          )
        : width < 1500
            ? const SheetMetrics(
                rowHeight: 48,
                headerHeight: 46,
                titleBarHeight: 35,
                labelFontSize: 14,
                valueFontSize: 15,
                gutterWidth: 34,
                tableGap: 10,
                scale: 1,
              )
            : const SheetMetrics(
                rowHeight: 52,
                headerHeight: 48,
                titleBarHeight: 36,
                labelFontSize: 15,
                valueFontSize: 15,
                gutterWidth: 36,
                tableGap: 12,
                scale: 1,
              );

    return base;
  }

  SheetMetrics copyWith({
    double? rowHeight,
    double? headerHeight,
    double? titleBarHeight,
    double? labelFontSize,
    double? valueFontSize,
    double? gutterWidth,
    double? tableGap,
    double? scale,
  }) {
    return SheetMetrics(
      rowHeight: rowHeight ?? this.rowHeight,
      headerHeight: headerHeight ?? this.headerHeight,
      titleBarHeight: titleBarHeight ?? this.titleBarHeight,
      labelFontSize: labelFontSize ?? this.labelFontSize,
      valueFontSize: valueFontSize ?? this.valueFontSize,
      gutterWidth: gutterWidth ?? this.gutterWidth,
      tableGap: tableGap ?? this.tableGap,
      scale: scale ?? this.scale,
    );
  }

  /// The density used when nobody has measured — tests, and any widget built
  /// outside a `LayoutBuilder`.
  static const SheetMetrics fallback = SheetMetrics(
    rowHeight: 48,
    headerHeight: 46,
    titleBarHeight: 35,
    labelFontSize: 14,
    valueFontSize: 15,
    gutterWidth: 34,
    tableGap: 10,
    scale: 1,
  );
}
