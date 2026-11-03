import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../column_def.dart';
import '../sheet_def.dart';
import '../sheet_metrics.dart';
import '../sheet_draft.dart';
import '../sheet_controller.dart';
import 'mode_chip.dart';
import 'option_picker.dart';

class ValueCell extends StatefulWidget {
  const ValueCell({
    super.key,
    required this.column,
    required this.sheetDef,
    required this.controller,
    required this.width,
    this.onAdvance,
    this.onBack,
    this.cellValue,
    this.rowIndex = 0,
    this.isSelected = false,
    this.isHighlighted = false,
    this.onTap,
    this.metrics = SheetMetrics.fallback,
  });

  final ColumnDef column;
  final SheetDef sheetDef;
  final SheetController controller;
  final double width;
  final SheetMetrics metrics;
  final VoidCallback? onAdvance;
  final VoidCallback? onBack;
  final CellValue? cellValue;
  final int rowIndex;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onTap;

  @override
  State<ValueCell> createState() => _ValueCellState();
}

class _ValueCellState extends State<ValueCell> {
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();

  /// Whether [_focusNode] has been focused since it was last left.
  bool _hadFocus = false;

  /// The key listener's own node — held, not made in build, where a new one
  /// per rebuild (one per keystroke while typing) was never disposed.
  final FocusNode _keyListenerNode = FocusNode(skipTraversal: true);

  /// This cell's own row, from the controller.
  ///
  /// It used to read `controller.draft` — the one shared draft — for the
  /// selected row and a passed-in map for the others, which is how an edit
  /// could be written to one row and read back from another.
  CellValue? get _currentVal =>
      widget.controller.draftAt(widget.rowIndex).get(widget.column.id) ??
      widget.cellValue;

  @override
  void initState() {
    super.initState();
    final cellVal = _currentVal;
    _textController = TextEditingController(text: _formatInitialText(cellVal));

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _hadFocus = true;
        widget.controller.focusCell(
          widget.column.id,
          isHeader: false,
          row: widget.rowIndex,
        );
      } else if (_hadFocus) {
        // Left: an empty required cell is now shown as missing.
        _hadFocus = false;
        widget.controller.markTouched(widget.column.id, row: widget.rowIndex);
      }
    });
  }

  String _formatInitialText(CellValue? val) {
    if (val == null) return '';
    if (val.optionLabel != null) return val.optionLabel!;
    if (val.textValue != null) return val.textValue!;
    if (val.intValue != null) return val.intValue.toString();
    return '';
  }

  @override
  void didUpdateWidget(covariant ValueCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cellVal = _currentVal;
    final expected = _formatInitialText(cellVal);
    if (_textController.text != expected && !_focusNode.hasFocus) {
      _textController.text = expected;
    }
    _syncFocus();
  }

  /// Puts real focus where the controller says the cursor is.
  ///
  /// **Nothing in the sheet called `requestFocus` at all.** The cursor moved on
  /// Enter and Tab and the focus ring followed it, but keyboard focus stayed
  /// wherever it happened to be — so no shortcut bound to a cell could ever
  /// receive a key, which is why the status bar's "Alt+↓ for dropdowns" did
  /// nothing. The focus listener above sets the controller's focused cell when
  /// a node gains focus; this is the other direction.
  ///
  /// **Edge-triggered: only when the cursor ARRIVES here.** It used to run on
  /// every rebuild, so whichever cell was the sheet's cursor took focus back
  /// any time the screen rebuilt — and once the item sheet shared a page with
  /// ordinary text fields, every keystroke in one of them rebuilt the screen
  /// and the cursor cell snatched focus after a single letter.
  void _syncFocus() {
    final wanted = widget.isSelected &&
        !widget.controller.isHeaderFocused &&
        widget.controller.focusedColumnId == widget.column.id;
    if (wanted && !_wasWanted && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    _wasWanted = wanted;
  }

  /// Whether this cell was the cursor at the last sync — what makes the sync
  /// fire on arrival rather than on every rebuild.
  bool _wasWanted = false;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _keyListenerNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cellVal = _currentVal;
    final error = widget.isSelected
        ? widget.controller.visibleErrors(row: widget.rowIndex)[widget.column.id]
        : null;
    final isFocused =
        widget.isSelected &&
        widget.controller.focusedColumnId == widget.column.id &&
        !widget.controller.isHeaderFocused;

    final isListLike =
        widget.column.kind == ColumnKind.list ||
        widget.column.kind == ColumnKind.gauge ||
        widget.column.kind == ColumnKind.material;

    // A saved row is closed until its Edit: it shows its values, opens no
    // picker and takes no keyboard focus — but a tap still selects the row,
    // which is how the sections below are moved onto that part.
    final locked = widget.controller.isRowLocked(widget.rowIndex);
    _focusNode.canRequestFocus = !locked;
    if (locked) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: _lockedBody(cellVal),
      );
    }

    return CallbackShortcuts(
      // Alt+↓ opens the dropdown. The status bar has advertised this since the
      // sheet was written — "Alt+↓ for dropdowns" — and nothing anywhere
      // handled the key, so the one documented way to open a picker from the
      // keyboard did nothing at all.
      bindings: {
        // Tab and Shift+Tab walk the row. The status bar has said "Enter / Tab
        // to traverse cells" since the sheet was written and NOTHING handled
        // either key — Tab fell through to Flutter's own focus traversal,
        // which visits whatever happens to be focusable in whatever order.
        if (widget.isSelected)
          const SingleActivator(LogicalKeyboardKey.tab): () =>
              widget.onAdvance?.call(),
        if (widget.isSelected)
          const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
              widget.onBack?.call(),
        // Enter, for the cells that have no text field of their own to submit.
        if (isListLike && widget.isSelected)
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              widget.onAdvance?.call(),
        if (isListLike && widget.isSelected)
          const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
              _showOptionsPopup(context),
        // Ctrl+D / Cmd+D — the spreadsheet idiom for "same as the one above".
        if (widget.isSelected)
          const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
              widget.controller
                  .fillDown(widget.column.id, row: widget.rowIndex),
        if (widget.isSelected)
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () =>
              widget.controller
                  .fillDown(widget.column.id, row: widget.rowIndex),
      },
      child: InkWell(
        // Addressable by (sheet, row, column) so a driver can reach one cell.
        // Without this the sheet had no keys at all and an integration test
        // could only find cells by the text already in them — which is the one
        // thing it is there to change.
        key: ValueKey<String>(
          'cell_${widget.sheetDef.key}_${widget.rowIndex}_${widget.column.id}',
        ),
        onTap: widget.onTap,
        child: Container(
          width: widget.width,
          // The table's row height, as the locked body and the status gutter
          // use — a fixed 46 drifted off the gutter by a few pixels a row.
          height: widget.metrics.rowHeight,
          decoration: BoxDecoration(
            color: widget.isHighlighted
                ? SoftErpTheme.successBg
                : (widget.isSelected
                      ? SoftErpTheme.accent.withValues(alpha: 0.05)
                      : SoftErpTheme.cardSurface),
            border: widget.isHighlighted
                ? Border.all(color: SoftErpTheme.successText, width: 2)
                : Border(
                    right: const BorderSide(color: SoftErpTheme.border),
                    bottom: const BorderSide(color: SoftErpTheme.border),
                    top: isFocused
                        ? const BorderSide(color: SoftErpTheme.accent, width: 2)
                        : BorderSide.none,
                    left: error != null
                        ? const BorderSide(color: SoftErpTheme.dangerText, width: 3)
                        : (widget.isSelected && widget.column.position == 0
                              ? const BorderSide(
                                  color: SoftErpTheme.accent,
                                  width: 3,
                                )
                              : BorderSide.none),
                  ),
            boxShadow: widget.isHighlighted
                ? [
                    BoxShadow(
                      color: SoftErpTheme.successText.withValues(alpha: 0.35),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              // Positioned.fill, not a bare child: a Stack gives its
              // non-positioned children loose constraints, so the content hugged
              // its own height — 20px at the top of a 46px cell. The picker's tap
              // target is inside this, which meant the lower 26px of every list
              // cell did nothing but re-select the row, and clicking the middle
              // of a cell looked like a dead control.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _buildCellContent(cellVal),
                ),
              ),
              if (error != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: CustomPaint(
                    size: const Size(8, 8),
                    painter: _ErrorCornerPainter(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A locked cell: the value as text, in the cell's own box.
  Widget _lockedBody(CellValue? cellVal) {
    final text = _formatInitialText(cellVal);
    return Container(
      width: widget.width,
      height: widget.metrics.rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      // The selected row reads as selected, saved or not.
      color: widget.isSelected ? SoftErpTheme.accentSoft : null,
      child: Text(
        text.isEmpty ? '—' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: text.isEmpty ? SoftErpTheme.textMuted : SoftErpTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildCellContent(CellValue? cellVal) {
    if (widget.column.isStamp) {
      return _buildStampCell(cellVal);
    }

    if (widget.column.kind == ColumnKind.seq ||
        widget.column.kind == ColumnKind.code) {
      return _buildDerivedCell(cellVal);
    }

    // Gauge and Material are list-like: both pick from `controller.options`,
    // which the host seeds from `swgGaugeTable` and the materials master. The
    // kind matters to the badge, the width, and — the reason it exists — to the
    // binding, which turns it into the variation node's `inputType`.
    //
    // A typed value is still allowed on a gauge, because the house rule is that
    // vendor values are recorded verbatim and the table only fills the field
    // when a gauge is picked.
    if (widget.column.kind == ColumnKind.list ||
        widget.column.kind == ColumnKind.gauge ||
        widget.column.kind == ColumnKind.material) {
      return _buildListCell(cellVal);
    }

    if (widget.column.kind == ColumnKind.check) {
      return _buildCheckCell(cellVal);
    }

    return _buildTextCell(cellVal);
  }

  /// A tick. Writes 1 when ticked and an empty cell when not — see
  /// [ColumnKind.check] for why unticked is not 0.
  Widget _buildCheckCell(CellValue? cellVal) {
    final ticked = cellVal?.intValue == 1;
    return Align(
      alignment: Alignment.centerLeft,
      child: Checkbox(
        value: ticked,
        onChanged: (next) => widget.controller.updateValue(
                  widget.column.id,
                  next == true
                      ? CellValue(columnId: widget.column.id, intValue: 1)
                      : CellValue(columnId: widget.column.id),
                  row: widget.rowIndex,
                ),
      ),
    );
  }

  Widget _buildStampCell(CellValue? cellVal) {
    final stored = cellVal?.textValue?.trim() ?? '';
    // "Set on save" is what the prototype seeded into these cells; read it as
    // empty. Short when empty — "Set on sa…" was all a narrow column showed.
    final isSet = stored.isNotEmpty && stored != 'Set on save';
    final text = isSet ? stored : 'On save';

    final row = Row(
      children: [
        Icon(
          isSet ? Icons.lock_clock_rounded : Icons.lock_outline_rounded,
          size: 13,
          color: isSet ? SoftErpTheme.successText : SoftErpTheme.textMuted,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSet ? FontWeight.w700 : FontWeight.w500,
              color: isSet ? SoftErpTheme.textPrimary : SoftErpTheme.textMuted,
            ),
          ),
        ),
      ],
    );
    return isSet
        ? row
        : Tooltip(message: 'Filled in when the part is saved', child: row);
  }

  Widget _buildDerivedCell(CellValue? cellVal) {
    if (!widget.isSelected) {
      final text =
          cellVal?.textValue ??
          (cellVal?.intValue != null ? '${cellVal!.intValue}' : '');
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.isEmpty ? '-' : text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
          ),
        ),
      );
    }

    final mode = cellVal?.mode ?? ValueMode.auto;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textController,
            focusNode: _focusNode,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
            onChanged: (val) {
              widget.controller.updateTextValue(
                widget.column.id,
                val,
                row: widget.rowIndex,
              );
            },
            onSubmitted: (_) => widget.onAdvance?.call(),
          ),
        ),
        const SizedBox(width: 2),
        ModeChip(
          controller: widget.controller,
          columnId: widget.column.id,
          row: widget.rowIndex,
          mode: mode,
        ),
      ],
    );
  }

  Widget _buildListCell(CellValue? cellVal) {
    final isNew = cellVal?.isNew ?? false;
    final label = cellVal?.optionLabel ?? cellVal?.textValue ?? '';

    if (!widget.isSelected) {
      return Row(
        children: [
          Expanded(
            child: Text(
              label.isEmpty ? '-' : label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: label.isNotEmpty
                    ? FontWeight.w500
                    : FontWeight.w400,
                color: label.isNotEmpty
                    ? SoftErpTheme.textPrimary
                    : SoftErpTheme.textMuted,
              ),
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: SoftErpTheme.borderStrong),
        ],
      );
    }

    return InkWell(
      focusNode: _focusNode,
      onTap: () => _showOptionsPopup(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.isEmpty ? 'Select...' : label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: label.isNotEmpty
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: label.isNotEmpty
                    ? SoftErpTheme.textPrimary
                    : SoftErpTheme.textMuted,
              ),
            ),
          ),
          if (isNew)
            Container(
              margin: const EdgeInsets.only(right: 3),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: SoftErpTheme.successBg,
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
              ),
              child: const Text(
                'New',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: SoftErpTheme.successText,
                ),
              ),
            ),
          const Icon(Icons.arrow_drop_down, size: 18, color: SoftErpTheme.textMuted),
        ],
      ),
    );
  }

  Widget _buildTextCell(CellValue? cellVal) {
    if (!widget.isSelected) {
      final text =
          cellVal?.textValue ??
          (cellVal?.intValue != null ? '${cellVal!.intValue}' : '');
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.isEmpty ? '-' : text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: SoftErpTheme.textPrimary,
          ),
        ),
      );
    }
    return KeyboardListener(
      focusNode: _keyListenerNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onAdvance?.call();
          }
        }
      },
      child: TextField(
        controller: _textController,
        focusNode: _focusNode,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: SoftErpTheme.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: widget.column.kind == ColumnKind.money
              ? '0.00'
              : 'Type here...',
          hintStyle: const TextStyle(fontSize: 14, color: SoftErpTheme.borderStrong),
        ),
        onChanged: (val) {
          widget.controller.updateTextValue(
            widget.column.id,
            val,
            row: widget.rowIndex,
          );
        },
        onSubmitted: (_) => widget.onAdvance?.call(),
      ),
    );
  }

  void _showOptionsPopup(BuildContext context) => showColumnOptionPicker(
        context,
        column: widget.column,
        sheetDef: widget.sheetDef,
        controller: widget.controller,
        row: widget.rowIndex,
        onDone: widget.onAdvance,
      );
}

class _ErrorCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SoftErpTheme.dangerText;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
