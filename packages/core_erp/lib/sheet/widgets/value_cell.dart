import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../column_def.dart';
import '../column_option.dart';
import '../sheet_def.dart';
import '../sheet_metrics.dart';
import '../sheet_draft.dart';
import '../sheet_controller.dart';
import '../sheet_engine.dart';

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
        widget.controller.focusCell(
          widget.column.id,
          isHeader: false,
          row: widget.rowIndex,
        );
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
        ? widget.controller.errors[widget.column.id]
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
                ? const Color(0xFFDCFCE7)
                : (widget.isSelected
                      ? SoftErpTheme.accent.withValues(alpha: 0.05)
                      : Colors.white),
            border: widget.isHighlighted
                ? Border.all(color: const Color(0xFF10B981), width: 2)
                : Border(
                    right: const BorderSide(color: Color(0xFFE2E8F0)),
                    bottom: const BorderSide(color: Color(0xFFE2E8F0)),
                    top: isFocused
                        ? const BorderSide(color: SoftErpTheme.accent, width: 2)
                        : BorderSide.none,
                    left: error != null
                        ? const BorderSide(color: Color(0xFFEF4444), width: 3)
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
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
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
      color: widget.isSelected ? const Color(0xFFEEF2FF) : null,
      child: Text(
        text.isEmpty ? '—' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: text.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
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
    final text = cellVal?.textValue ?? 'Set on save';
    final isSet = text != 'Set on save';

    return Row(
      children: [
        Icon(
          isSet ? Icons.lock_clock_rounded : Icons.lock_outline_rounded,
          size: 13,
          color: isSet ? const Color(0xFF059669) : const Color(0xFF94A3B8),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSet ? FontWeight.w700 : FontWeight.w500,
              color: isSet ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ],
    );
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
        _buildModeChip(mode),
      ],
    );
  }

  Widget _buildModeChip(ValueMode mode) {
    final (label, bg, fg) = switch (mode) {
      ValueMode.auto => (
        'Auto',
        const Color(0xFFEFF6FF),
        const Color(0xFF2563EB),
      ),
      ValueMode.edit => (
        'Edit',
        const Color(0xFFFEF3C7),
        const Color(0xFFD97706),
      ),
      ValueMode.ok => ('OK', const Color(0xFFECFDF5), const Color(0xFF059669)),
    };

    return PopupMenuButton<ValueMode>(
      tooltip: 'Value mode: $label',
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: fg.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: ValueMode.auto,
          child: Text('Auto (Derived proposal)'),
        ),
        const PopupMenuItem(
          value: ValueMode.edit,
          child: Text('Edit (Person entered)'),
        ),
        const PopupMenuItem(
          value: ValueMode.ok,
          child: Text('OK (Frozen confirmed)'),
        ),
      ],
      onSelected: (m) =>
          widget.controller.setMode(widget.column.id, m, row: widget.rowIndex),
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
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFFCBD5E1)),
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
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
          if (isNew)
            Container(
              margin: const EdgeInsets.only(right: 3),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'New',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF065F46),
                ),
              ),
            ),
          const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF94A3B8)),
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
          hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
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

  void _showOptionsPopup(BuildContext context) {
    // Anchored under the cell, not a modal sheet.
    //
    // This was `showModalBottomSheet`, which drew a large card across the
    // bottom of the window: you clicked a cell in the top-left of the sheet and
    // a panel opened at the bottom-centre, covering the rows underneath and
    // saying nothing about which cell it belonged to. A cell picker has to drop
    // from its cell — that is the whole affordance.
    final box = context.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null || !box.hasSize) return;
    final anchor =
        box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;

    showDialog<void>(
      context: context,
      // Transparent, so the rows stay readable behind the list the way a
      // dropdown's do. Still a barrier, so a click outside closes it.
      barrierColor: Colors.transparent,
      // The picker is handed the controller, not a snapshot of its options.
      // Taken at open time, the list could not change: reference data that
      // arrived a moment later left the dropdown empty until it was closed and
      // reopened — and arriving late is the normal case, because the screen
      // opens before the masters have finished loading.
      builder: (ctx) => _AnchoredPicker(
        anchor: anchor,
        overlaySize: overlayBox.size,
        child: _OptionsPickerSheet(
        column: widget.column,
        sheetDef: widget.sheetDef,
        controller: widget.controller,
        rowIndex: widget.rowIndex,
        onSelectOption: (opt) {
          Navigator.of(ctx).pop();
          widget.controller.setOption(
            widget.column.id,
            opt,
            row: widget.rowIndex,
          );
          widget.onAdvance?.call();
        },
        onAddNew: (newLabel) {
          Navigator.of(ctx).pop();
          widget.controller.addNewOption(
            widget.column.id,
            newLabel,
            row: widget.rowIndex,
          );
          widget.onAdvance?.call();
        },
        onSelectParty: (p) {
          Navigator.of(ctx).pop();
          widget.controller.updateValue(
            widget.column.id,
            CellValue(
              columnId: widget.column.id,
              refId: p.id,
              optionLabel: p.name,
            ),
            row: widget.rowIndex,
          );
          widget.onAdvance?.call();
        },
        onSelectContact: (c) {
          Navigator.of(ctx).pop();
          // Fills this cell AND the designation, phone and email columns beside
          // it. `updateValue` alone wrote only the name, so choosing a contact
          // left its three projection columns blank — the one method that
          // filled them, `ItemMasterController.pickContact`, had no caller in
          // the app at all.
          widget.controller.applyContact(
            widget.column.id,
            c,
            row: widget.rowIndex,
          );
          widget.onAdvance?.call();
        },
        onAddContact: widget.controller.onAddContact == null
            ? null
            : (typed) async {
                // The company this contact column hangs under. Read here
                // rather than taken from the picker, which has its own copy.
                final parentId = widget.column.parentId;
                final partyId = parentId == null
                    ? null
                    : widget.controller
                        .draftAt(widget.rowIndex)
                        .get(parentId)
                        ?.refId;
                if (partyId == null) return;
                final made = await widget.controller.onAddContact!(
                  partyId,
                  typed,
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                if (made == null) return;
                // Selected straight away: the picker's list was built before
                // this person existed, so waiting for a refresh would close on
                // nothing.
                widget.controller.applyContact(
                  widget.column.id,
                  made,
                  row: widget.rowIndex,
                );
                widget.onAdvance?.call();
              },
      ),
      ),
    );
  }
}

/// Places a picker under the cell that opened it, flipping above when there is
/// no room below and clamping to the window so it is never half off-screen.
class _AnchoredPicker extends StatelessWidget {
  const _AnchoredPicker({
    required this.anchor,
    required this.overlaySize,
    required this.child,
  });

  /// The cell's rectangle, in overlay coordinates.
  final Rect anchor;
  final Size overlaySize;
  final Widget child;

  /// A narrow column would give a useless list, so the picker is at least this
  /// wide and grows to the column.
  static const double _minWidth = 280;
  static const double _maxHeight = 360;
  static const double _gap = 4;
  static const double _margin = 8;

  @override
  Widget build(BuildContext context) {
    final width = anchor.width < _minWidth ? _minWidth : anchor.width;
    final maxLeft = (overlaySize.width - width - _margin);
    final left = maxLeft <= _margin
        ? _margin
        : anchor.left.clamp(_margin, maxLeft).toDouble();

    final below = overlaySize.height - anchor.bottom - _gap - _margin;
    final above = anchor.top - _gap - _margin;
    final dropDown = below >= above || below >= _maxHeight;
    final height = (dropDown ? below : above).clamp(0.0, _maxHeight);

    return Stack(
      children: [
        Positioned(
          left: left,
          width: width,
          top: dropDown ? anchor.bottom + _gap : null,
          bottom: dropDown ? null : overlaySize.height - anchor.top + _gap,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            // The picker's TextField and ListTiles need a Material ancestor;
            // `showModalBottomSheet` used to supply one and `showDialog` over a
            // bare Stack does not.
            child: Material(
              type: MaterialType.transparency,
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionsPickerSheet extends StatefulWidget {
  const _OptionsPickerSheet({
    required this.column,
    required this.sheetDef,
    required this.controller,
    required this.rowIndex,
    required this.onSelectOption,
    required this.onAddNew,
    required this.onSelectParty,
    required this.onSelectContact,
    this.onAddContact,
  });

  final ColumnDef column;
  final SheetDef sheetDef;
  final SheetController controller;
  final int rowIndex;
  final ValueChanged<ColumnOption> onSelectOption;
  final ValueChanged<String> onAddNew;
  final ValueChanged<Party> onSelectParty;
  final ValueChanged<Contact> onSelectContact;

  /// Adds a person at the party this cell is scoped to. Null hides the offer.
  final ValueChanged<String>? onAddContact;

  @override
  State<_OptionsPickerSheet> createState() => _OptionsPickerSheetState();
}

class _OptionsPickerSheetState extends State<_OptionsPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  /// Lowercased, for matching only.
  String _query = '';

  /// What was actually typed. Kept apart from [_query] because the add-new tile
  /// used the lowercased one as the value, so picking it filed "test bracket"
  /// for a part somebody typed as "Test Bracket" — and showed the lowercase
  /// back to them in the tile's own label. Pressing Enter in the same field
  /// filed the original, so the two routes disagreed.
  String _typed = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _typed = _searchController.text.trim();
        _query = _typed.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The column this one hangs off, if any — the Group above a Type.
  ColumnDef? get _parentColumn => widget.column.parentId == null
      ? null
      : widget.sheetDef.getColumn(widget.column.parentId!);

  /// What the parent cell holds on THIS row.
  CellValue? get _parentValue {
    final parent = _parentColumn;
    if (parent == null) return null;
    return widget.controller.draftAt(widget.rowIndex).get(parent.id);
  }

  /// Options for this column under this row's parent.
  List<ColumnOption> get _candidates {
    // The nearest level filled in, not only the one directly above: a part
    // straight under a Group has no Type, and its names hang off the Group.
    final parentOptionId = SheetEngine.parentOptionIdFor(
      widget.sheetDef,
      widget.controller.draftAt(widget.rowIndex),
      widget.column.id,
    );
    return [
      for (final opt in widget.controller.options)
        if (opt.columnId == widget.column.id &&
            opt.parentOptionId == parentOptionId)
          opt,
    ];
  }

  /// Contacts belonging to the party chosen beside this cell.
  ///
  /// Was every contact the sheet knew, whatever company was picked — so the
  /// Client Name dropdown listed other companies' people and choosing one gave
  /// a part a contact at a firm it was not developed for.
  List<Contact> get _contactsInScope {
    if (widget.column.source != ColumnSource.contact) return const [];
    final partyId = _parentValue?.refId;
    final all = widget.controller.contacts;
    if (partyId == null) return all;
    return [
      for (final c in all)
        if (c.partyId == partyId) c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt with the controller, so options arriving while this is open show
    // up here rather than only on the next open.
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final parties = widget.column.source == ColumnSource.party
        ? widget.controller.parties
        : const <Party>[];
    final contacts = _contactsInScope;
    final options = _candidates;

    final filteredOptions = options
        .where(
          (o) =>
              _query.isEmpty ||
              o.label.toLowerCase().contains(_query) ||
              o.detail.toLowerCase().contains(_query),
        )
        .toList();

    final filteredParties = parties
        .where((p) => _query.isEmpty || p.name.toLowerCase().contains(_query))
        .toList();

    final filteredContacts = contacts
        .where((c) => _query.isEmpty || c.name.toLowerCase().contains(_query))
        .toList();

    return Container(
      // No margin and no height of its own: _AnchoredPicker decides where this
      // goes and how tall it may be, from the cell it belongs to.
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Select ${widget.column.label}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Type to filter, or type new and press Enter...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  widget.onAddNew(val.trim());
                }
              },
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (parties.isNotEmpty)
                  ...filteredParties.map(
                    (p) => ListTile(
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Type: ${p.type.toUpperCase()}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: const Icon(
                        Icons.business_rounded,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                      onTap: () => widget.onSelectParty(p),
                    ),
                  )
                else if (contacts.isNotEmpty) ...[
                  ...filteredContacts.map(
                    (c) => ListTile(
                      title: Text(
                        c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${c.designation ?? ""} · ${c.phone ?? ""}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: const Icon(
                        Icons.person_outline_rounded,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                      onTap: () => widget.onSelectContact(c),
                    ),
                  ),
                  // A company has as many people as it has, and the one you
                  // are dealing with today may not be on file yet. Without
                  // this the contact list could only ever offer people somebody
                  // had entered on another screen.
                  if (_query.isNotEmpty &&
                      widget.onAddContact != null &&
                      !filteredContacts.any(
                        (c) => c.name.toLowerCase() == _query,
                      ))
                    ListTile(
                      key: const ValueKey<String>('sheet_add_contact'),
                      leading: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: SoftErpTheme.accent,
                      ),
                      title: Text(
                        'Add "$_typed" at this company',
                        style: const TextStyle(
                          color: SoftErpTheme.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => widget.onAddContact!(_typed),
                    ),
                ]
                else ...[
                  ...filteredOptions.map(
                    (opt) => ListTile(
                      title: Text(
                        opt.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: opt.detail.isEmpty
                          ? null
                          : Text(
                              opt.detail,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                              ),
                            ),
                      trailing: opt.isNew
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'New',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                            )
                          : null,
                      onTap: () => widget.onSelectOption(opt),
                    ),
                  ),
                  if (_query.isNotEmpty &&
                      !filteredOptions.any(
                        (o) => o.label.toLowerCase() == _query,
                      ))
                    ListTile(
                      leading: const Icon(
                        Icons.add_circle_outline_rounded,
                        color: SoftErpTheme.accent,
                      ),
                      title: Text(
                        'Add "$_typed" under current path',
                        style: const TextStyle(
                          color: SoftErpTheme.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => widget.onAddNew(_typed),
                    ),
                  if (filteredOptions.isEmpty && _query.isEmpty) _emptyNote(),
                ],
                if (parties.isEmpty &&
                    contacts.isEmpty &&
                    widget.column.source != ColumnSource.options)
                  _emptyNote(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Why this dropdown is empty.
  ///
  /// An empty list used to render as blank space under the search field, which
  /// reads as a broken control: there was no way to tell "this needs a Group
  /// picked first" from "the masters have not loaded" from "nothing has ever
  /// been entered here". Each of those is a different next action.
  Widget _emptyNote() {
    final parent = _parentColumn;
    final needsParent = parent != null && _parentValue?.optionId == null;

    final String message;
    if (needsParent) {
      message =
          'Pick a ${parent.label} first — ${widget.column.label} options '
          'depend on it.';
    } else if (widget.controller.isReferenceDataEmpty) {
      message =
          'Nothing loaded yet. If this stays empty, the masters have not '
          'arrived.';
    } else {
      message = 'Nothing here yet. Type a name above to add one.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            needsParent ? Icons.north_west_rounded : Icons.info_outline_rounded,
            size: 18,
            color: const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 14, color: Color(0xFF5A6A80)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFEF4444);
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
