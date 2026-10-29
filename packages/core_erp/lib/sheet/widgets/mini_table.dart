import 'package:flutter/material.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../column_def.dart';
import '../sheet_def.dart';
import '../sheet_metrics.dart';
import '../sheet_draft.dart';
import '../sheet_controller.dart';
import 'header_cell.dart';
import 'value_cell.dart';

class MiniTable extends StatelessWidget {
  const MiniTable({
    super.key,
    required this.title,
    required this.tableGroup,
    required this.columns,
    required this.sheetDef,
    required this.controller,
    this.onAddHeaderAction,
    this.rowDrafts = const [],
    this.onRowSelected,
    this.selectedRowIndex = 0,
    this.highlightedColumnIds,
    this.traversalColumns = const [],
    this.rowStatusBuilder,
    this.metrics = SheetMetrics.fallback,
    this.maxWidth = double.infinity,
  });

  final String title;
  final TableGroup tableGroup;
  final List<ColumnDef> columns;
  final SheetDef sheetDef;
  final SheetController controller;
  final VoidCallback? onAddHeaderAction;
  final List<Map<int, CellValue>> rowDrafts;
  final ValueChanged<int>? onRowSelected;
  final int selectedRowIndex;
  final Set<int>? highlightedColumnIds;

  /// Every column of the sheet in drawn order, so Enter and Tab cross from one
  /// table into the next. Empty falls back to this table's own columns.
  final List<ColumnDef> traversalColumns;

  /// A narrow gutter down the left saying what state each row is in.
  ///
  /// Rows commit one at a time, so without this a typist cannot tell which of
  /// their fifty rows landed — the only other signal describes the sheet, not
  /// a row.
  final Widget? Function(int row)? rowStatusBuilder;

  /// Widths, heights and type sizes, chosen from the viewport.
  final SheetMetrics metrics;

  /// The room this table has. Only one table can grow — Properties, by the +
  /// button — and a sheet with enough properties makes that one table wider
  /// than the window on its own, which wrapping cannot help. Past this it
  /// scrolls its own content rather than overflowing. Inactive at any
  /// realistic column count.
  final double maxWidth;

  /// What this table occupies, by the one formula the strip also measures with.
  double get _naturalWidth =>
      metrics.tableWidth(columns, withGutter: rowStatusBuilder != null);

  /// Who decides which row is selected. The controller's cursor is the truth;
  /// `selectedRowIndex` remains for a host that drives it from outside.
  int get _selectedRow =>
      rowDrafts.isNotEmpty ? selectedRowIndex : controller.row;

  /// Moves the cursor one cell along this table's columns, wrapping to the
  /// next row at the end.
  ///
  /// `ValueCell.onAdvance`/`onBack` existed and were invoked at seven sites,
  /// but nothing ever passed them, so Enter did nothing while the status bar
  /// advertised "Enter / Tab to traverse cells".
  /// The columns Enter and Tab walk, in the order they are drawn.
  ///
  /// Not this table's own columns. `TableRowStrip` splits a sheet into four
  /// tables, so walking `columns` trapped the cursor inside "Group and item"
  /// and a typist could never Tab across a whole part.
  /// Stamps are left out: they are set on save, hold no editable content, and
  /// Tabbing into "Set on save" on the way to the next row is a stop nobody
  /// wants.
  List<ColumnDef> get _traversal => [
        for (final column
            in traversalColumns.isEmpty ? columns : traversalColumns)
          if (!column.isStamp) column,
      ];

  void _advance(ColumnDef from, int row, int step) {
    final order = _traversal;
    final index = order.indexWhere((c) => c.id == from.id);
    if (index < 0) return;
    final next = index + step;
    if (next >= 0 && next < order.length) {
      controller.focusCell(order[next].id, row: row);
      return;
    }

    final nextRow = row + step;
    final rows = rowDrafts.isNotEmpty ? rowDrafts.length : controller.rowCount;

    // Past the last cell of the last row is where the next row belongs. It used
    // to be where Enter stopped dead, which for somebody typing a catalogue is
    // the one place a new row is always wanted.
    if (step > 0 && nextRow >= rows) {
      if (rowDrafts.isNotEmpty || !controller.canAddRows) return;
      final added = controller.addRow();
      controller.focusCell(order.first.id, row: added);
      return;
    }

    if (nextRow < 0 || nextRow >= rows) return;
    controller.focusCell(
      step > 0 ? order.first.id : order.last.id,
      row: nextRow,
    );
  }

  double _widthForKind(ColumnKind kind) => metrics.widthFor(kind);

  @override
  Widget build(BuildContext context) {
    if (columns.isEmpty) return const SizedBox.shrink();

    final table = Container(
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.borderStrong),
        boxShadow: SoftErpTheme.insetShadow,
      ),
      // Bound to what the columns need, less the border this Container draws,
      // so the table cannot be wider than `tableWidth()` reports.
      //
      // It could be, and the title bar was how: a `Row(mainAxisSize: min)` with
      // nothing constraining it, so a heading longer than its columns silently
      // widened the whole table — "Primary Group (Finish)" at 14/w800 is ~190px
      // against a single 155px column. That made the fit arithmetic a lie, and
      // with no horizontal scroll left to absorb it, an overflow.
      child: SizedBox(
        width: _naturalWidth - 2,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Table Group Title bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: SoftErpTheme.sectionSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(SoftErpTheme.radiusSm - 1)),
              border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Flexible, so a long heading ellipsises instead of widening
                // the table. It needs the SizedBox above to have bounded the
                // width — Flexible under unbounded width throws.
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: SoftErpTheme.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (onAddHeaderAction != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    key: ValueKey(
                      'mini_table_add_${tableGroup.name}_${controller.sheetDef.key}',
                    ),
                    onTap: onAddHeaderAction,
                    borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: SoftErpTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 13,
                        color: SoftErpTheme.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Header Row over multiple Value Rows
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rowStatusBuilder != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: metrics.gutterWidth,
                      height: metrics.headerHeight,
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: SoftErpTheme.border),
                          bottom: BorderSide(color: SoftErpTheme.border),
                        ),
                      ),
                    ),
                    for (
                      int r = 0;
                      r <
                          (rowDrafts.isNotEmpty
                              ? rowDrafts.length
                              : controller.rowCount);
                      r++
                    )
                      Container(
                        width: metrics.gutterWidth,
                        height: metrics.rowHeight,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: SoftErpTheme.border),
                            bottom: BorderSide(color: SoftErpTheme.border),
                          ),
                        ),
                        // The gutter selects its row too — the way onto a saved
                        // row whose cells are closed. Buttons in it still win
                        // their own taps.
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            controller.selectRow(r);
                            onRowSelected?.call(r);
                          },
                          child: SizedBox.expand(
                            child: Center(child: rowStatusBuilder!(r)),
                          ),
                        ),
                      ),
                  ],
                ),
              ...columns.map((col) {
                final w = _widthForKind(col.kind);
                // Rows from the controller. `rowDrafts` stays as an override
                // for a host rendering a projection, but it is no longer the
                // only way extra rows exist — and it is no longer read-only.
                final rowCount = rowDrafts.isNotEmpty
                    ? rowDrafts.length
                    : controller.rowCount;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HeaderCell(
                      column: col,
                      sheetDef: sheetDef,
                      controller: controller,
                      width: w,
                      metrics: metrics,
                    ),
                    for (int r = 0; r < rowCount; r++)
                      ValueCell(
                        column: col,
                        sheetDef: sheetDef,
                        controller: controller,
                        width: w,
                        cellValue: rowDrafts.isNotEmpty
                            ? rowDrafts[r][col.id]
                            : null,
                        rowIndex: r,
                        // Without this every cell measured itself against the
                        // fallback while the status gutter used the real
                        // metrics, and the icons slid off their rows.
                        metrics: metrics,
                        isSelected: r == _selectedRow,
                        isHighlighted:
                            (highlightedColumnIds?.contains(col.id) ?? false) &&
                            (r == _selectedRow),
                        // Selecting a row moves the controller's cursor, so the
                        // next keystroke lands where the click did.
                        onTap: () {
                          controller.selectRow(r);
                          onRowSelected?.call(r);
                        },
                        onAdvance: () => _advance(col, r, 1),
                        onBack: () => _advance(col, r, -1),
                      ),
                  ],
                );
              }),
            ],
          ),
        ],
        ),
      ),
    );

    // One table alone can beat the window — Properties with six or so added
    // properties — and no amount of wrapping helps a single band that is itself
    // too wide. Scrolling its own content is the honest degradation; the strip
    // as a whole still never scrolls.
    if (_naturalWidth <= maxWidth) return table;
    return SizedBox(
      width: maxWidth,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: table,
      ),
    );
  }
}
