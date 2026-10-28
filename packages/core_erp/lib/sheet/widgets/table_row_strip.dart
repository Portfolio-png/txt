import 'package:flutter/material.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../column_def.dart';
import '../sheet_def.dart';
import '../sheet_draft.dart';
import '../sheet_controller.dart';
import '../sheet_metrics.dart';
import 'mini_table.dart';

class TableRowStrip extends StatefulWidget {
  const TableRowStrip({
    super.key,
    required this.sheetDef,
    required this.controller,
    this.onAddSubGroup,
    this.onAddPropertyColumn,
    this.rowDrafts = const [],
    this.onRowSelected,
    this.selectedRowIndex = 0,
    this.highlightedColumnIds,
    this.groupTitle = 'Group and item',
    this.propertiesTitle = 'Properties',
    this.primaryGroupTitle = 'Primary Group',
    this.createdTitle = 'Created',
    this.rowStatusBuilder,
    this.gutterExtra = 0,
  });

  /// The band container, so a test can measure what the strip actually drew
  /// rather than recomputing what it should have drawn.
  static const Key stripKey = ValueKey<String>('sheet_strip');

  final SheetDef sheetDef;
  final SheetController controller;
  final VoidCallback? onAddSubGroup;
  final VoidCallback? onAddPropertyColumn;
  final List<Map<int, CellValue>> rowDrafts;
  final ValueChanged<int>? onRowSelected;
  final int selectedRowIndex;
  final Set<int>? highlightedColumnIds;

  /// The four table headings. Defaulted to what the item sheet calls them so
  /// existing callers are unchanged, but named here rather than written into
  /// the build method — a die sheet's first table is not "Group and item", and
  /// a widget that hardcodes its headings can only ever serve one sheet.
  final String groupTitle;
  final String propertiesTitle;

  /// Shown as `<primaryGroupTitle> (<first column's label>)`.
  final String primaryGroupTitle;
  final String createdTitle;

  /// A gutter down the left of the FIRST table saying what state each row is
  /// in. Only the first, because one gutter per table would repeat the same
  /// four chips four times across one row.
  final Widget? Function(int row)? rowStatusBuilder;

  /// Width the gutter needs beyond its status chip — a photo per row.
  final double gutterExtra;

  @override
  State<TableRowStrip> createState() => _TableRowStripState();
}

class _TableRowStripState extends State<TableRowStrip> {
  @override
  Widget build(BuildContext context) {
    final groupCols = widget.sheetDef.columns
        .where((c) => widget.sheetDef.tableOf(c) == TableGroup.groupItem)
        .toList();

    final propertyCols = widget.sheetDef.columns
        .where((c) => widget.sheetDef.tableOf(c) == TableGroup.properties)
        .toList();

    final independentCols = widget.sheetDef.columns
        .where((c) => widget.sheetDef.tableOf(c) == TableGroup.independent)
        .toList();

    final createdCols = widget.sheetDef.columns
        .where((c) => widget.sheetDef.tableOf(c) == TableGroup.created)
        .toList();

    // The drawn order of the whole row, which is what Enter and Tab walk.
    final traversal = <ColumnDef>[
      ...groupCols,
      ...propertyCols,
      ...independentCols,
      ...createdCols,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final plain = SheetMetrics.forWidth(constraints.maxWidth);
        final base = widget.rowStatusBuilder != null && widget.gutterExtra > 0
            ? plain.copyWith(gutterWidth: plain.gutterWidth + widget.gutterExtra)
            : plain;

        // Everything that must not scale. Counted off the tables that actually
        // render: the old sum charged 2px for an empty table and three gaps
        // when only two are drawn, then added 24px of its own padding on top of
        // the host's — about 36px of demand for nothing, which is most of what
        // a first added property needs.
        final rendered = [groupCols, propertyCols, independentCols, createdCols]
            .where((c) => c.isNotEmpty)
            .length;
        final fixed = rendered * 2 +
            (widget.rowStatusBuilder != null ? base.gutterWidth : 0) +
            base.tableGap * (rendered - 1).clamp(0, 3);

        final metrics = base.fitTo(
          constraints.maxWidth,
          columns: traversal,
          fixedWidth: fixed,
        );

        return _buildStrip(
          context,
          metrics,
          groupCols,
          propertyCols,
          independentCols,
          createdCols,
          traversal,
          constraints.maxWidth,
        );
      },
    );
  }

  Widget _buildStrip(
    BuildContext context,
    SheetMetrics metrics,
    List<ColumnDef> groupCols,
    List<ColumnDef> propertyCols,
    List<ColumnDef> independentCols,
    List<ColumnDef> createdCols,
    List<ColumnDef> traversal,
    double maxWidth,
  ) {
    // The tables, flowing onto a line below when they do not fit across.
    //
    // This was a horizontally scrolling `Row`. Horizontal scroll is the one
    // thing this strip must not do, and `BouncingScrollPhysics` made it worse
    // than it looked: `applyBoundaryConditions` never clamps, so a trackpad
    // swipe wobbled the strip even at `maxScrollExtent == 0` — the sheet could
    // be *felt* to scroll sideways when it already fitted.
    //
    // The cost of bands, which is real: every `MiniTable` draws ALL the rows,
    // so a second band repeats rows 1..N below the first and a record's last
    // cells sit a band-height below its first. The selected-row highlight is
    // passed to every table, so it is the thread that ties a record across
    // bands. Vertical scroll is allowed here; horizontal is not.
    //
    // (It was a Stack before that, carrying a 180px "pinned name" card that
    // appeared after 200px of scroll and shunted the strip's left padding
    // 0 → 190 mid-scroll. The host pins the record above the content instead.)
    return Wrap(
      key: TableRowStrip.stripKey,
      spacing: metrics.tableGap,
      runSpacing: metrics.tableGap,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        // 1. Group and item table
        if (groupCols.isNotEmpty)
          MiniTable(
            title: widget.groupTitle,
            tableGroup: TableGroup.groupItem,
            columns: groupCols,
            sheetDef: widget.sheetDef,
            controller: widget.controller,
            onAddHeaderAction: widget.onAddSubGroup,
            rowStatusBuilder: widget.rowStatusBuilder,
            rowDrafts: widget.rowDrafts,
            onRowSelected: widget.onRowSelected,
            selectedRowIndex: widget.selectedRowIndex,
            highlightedColumnIds: widget.highlightedColumnIds,
            traversalColumns: traversal,
            metrics: metrics,
            maxWidth: maxWidth,
          ),

        // 2. Properties table
        if (propertyCols.isNotEmpty)
          MiniTable(
            title: widget.propertiesTitle,
            tableGroup: TableGroup.properties,
            columns: propertyCols,
            sheetDef: widget.sheetDef,
            controller: widget.controller,
            onAddHeaderAction: widget.onAddPropertyColumn,
            rowDrafts: widget.rowDrafts,
            onRowSelected: widget.onRowSelected,
            selectedRowIndex: widget.selectedRowIndex,
            highlightedColumnIds: widget.highlightedColumnIds,
            traversalColumns: traversal,
            metrics: metrics,
            maxWidth: maxWidth,
          ),

        // 3. Primary Group table(s)
        if (independentCols.isNotEmpty)
          MiniTable(
            title:
                '${widget.primaryGroupTitle} (${independentCols.first.label})',
            tableGroup: TableGroup.primaryGroup,
            columns: independentCols,
            sheetDef: widget.sheetDef,
            controller: widget.controller,
            rowDrafts: widget.rowDrafts,
            onRowSelected: widget.onRowSelected,
            selectedRowIndex: widget.selectedRowIndex,
            highlightedColumnIds: widget.highlightedColumnIds,
            traversalColumns: traversal,
            metrics: metrics,
            maxWidth: maxWidth,
          ),

        // 4. Created table (Date & Time stamps)
        if (createdCols.isNotEmpty)
          MiniTable(
            title: widget.createdTitle,
            tableGroup: TableGroup.created,
            columns: createdCols,
            sheetDef: widget.sheetDef,
            controller: widget.controller,
            rowDrafts: widget.rowDrafts,
            onRowSelected: widget.onRowSelected,
            selectedRowIndex: widget.selectedRowIndex,
            highlightedColumnIds: widget.highlightedColumnIds,
            traversalColumns: traversal,
            metrics: metrics,
            maxWidth: maxWidth,
          ),
      ],
    );
  }
}
