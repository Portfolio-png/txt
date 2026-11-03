import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/fit_to_text.dart';
import '../../../../sheet/sheet.dart';

/// The parts on the item sheet, one line each — drawn the way a person is
/// drawn under "People at …": photo, labelled fields, Save, ×.
///
/// It was a grid of titled tables ("Group and item", "Properties", "Created",
/// "Action — Save / Edit"). On a narrow window the last two wrapped onto a
/// line of their own, so a part's Save was not on the part's line, and the
/// Date and Time columns — filled in by the save itself — read as something
/// to type. Here a part is one line and its Save ends it.
///
/// Everything underneath is the same [SheetController]: validation, cascade,
/// derive, locking, and the save when the cursor leaves a row. The dropdowns
/// are the grid's own picker ([showColumnOptionPicker]) and the Auto pill is
/// its [ModeChip]. Nothing is drawn red here; what is missing is said by the
/// Save button's tooltip, and a refused save by the app's toast.
class PartRowsForm extends StatelessWidget {
  const PartRowsForm({
    super.key,
    required this.sheet,
    required this.actionBuilder,
    required this.onAddPart,
    this.photoBuilder,
    this.statusBuilder,
    this.onAddProperty,
    this.onRemoveRow,
  });

  final SheetController sheet;

  /// The line's Save part, or its Edit once saved.
  final Widget Function(int row) actionBuilder;
  final VoidCallback onAddPart;

  /// The part's photo, or null where this app keeps none.
  final Widget Function(int row)? photoBuilder;

  /// Saved, refused or gone — a small icon before the photo.
  final Widget? Function(int row)? statusBuilder;

  /// Opens "Add property". Null hides nothing: the button is drawn disabled.
  final VoidCallback? onAddProperty;

  /// The line's ×. The host asks first when the line holds anything — typed
  /// cells, or dies and machines waiting for the part. Null removes at once.
  final Future<void> Function(int row)? onRemoveRow;

  /// The fields of a line, in the order the grid drew its columns. The stamp
  /// columns (Date, Time) are left out: the save fills them, nobody types them.
  static List<ColumnDef> lineColumns(SheetDef def) => [
        for (final group in const [
          TableGroup.groupItem,
          TableGroup.properties,
          TableGroup.primaryGroup,
        ])
          ...def.columns.where((c) => def.tableOf(c) == group && !c.isStamp),
      ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sheet,
      builder: (context, _) {
        final columns = lineColumns(sheet.sheetDef);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var row = 0; row < sheet.rowCount; row += 1) ...[
              _PartLine(
                key: ValueKey<Object>(sheet.draftAt(row).rowKey),
                sheet: sheet,
                row: row,
                columns: columns,
                photo: photoBuilder?.call(row),
                status: statusBuilder?.call(row),
                action: actionBuilder(row),
                onRemove: onRemoveRow,
              ),
              const SizedBox(height: 10),
            ],
            _footer(columns),
          ],
        );
      },
    );
  }

  Widget _footer(List<ColumnDef> columns) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          key: const ValueKey<String>('part_add_row'),
          onPressed: onAddPart,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add part', style: TextStyle(fontSize: 14)),
        ),
        Tooltip(
          message: onAddProperty == null
              ? 'Properties cannot be added here'
              : 'A new field on every part — Grade, Finish, …',
          child: TextButton.icon(
            key: const ValueKey<String>('mini_table_add_properties_item'),
            onPressed: onAddProperty,
            icon: const Icon(Icons.playlist_add_rounded, size: 18),
            label: const Text('Add property', style: TextStyle(fontSize: 14)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            'Parts on this sheet: ${sheet.rowCount}',
            style: SheetStyle.hint,
          ),
        ),
      ],
    );
  }
}

/// One part: status, photo, its fields, then Save / Edit and ×.
class _PartLine extends StatelessWidget {
  const _PartLine({
    super.key,
    required this.sheet,
    required this.row,
    required this.columns,
    required this.photo,
    required this.status,
    required this.action,
    this.onRemove,
  });

  final Future<void> Function(int row)? onRemove;
  final SheetController sheet;
  final int row;
  final List<ColumnDef> columns;
  final Widget? photo;
  final Widget? status;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final selected = sheet.row == row;
    final draft = sheet.draftAt(row);
    final saved = draft.entityId != null;
    final String? removeWhy = saved
        ? 'Saved parts stay in the catalogue — use Archive part'
        : (sheet.rowCount <= 1 ? 'A sheet always keeps one part' : null);

    return GestureDetector(
      // A tap on the line's empty space picks the part, as a field would.
      behavior: HitTestBehavior.translucent,
      onTap: () => sheet.selectRow(row),
      child: Container(
        key: ValueKey<String>('part_line_$row'),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: selected
              ? SoftErpTheme.accent.withValues(alpha: 0.04)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? SoftErpTheme.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        // The fields wrap among themselves; Save and × stay at the line's
        // end whatever the width — the Save that wrapped off its part's line
        // is what this replaced.
        child: Row(
          children: [
            if (status != null) ...[
              SizedBox(width: 28, child: status),
              const SizedBox(width: 6),
            ],
            if (photo != null) ...[photo!, const SizedBox(width: 10)],
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final column in columns)
                    _PartField(
                      key: ValueKey<String>(
                        'cell_${sheet.sheetDef.key}_${row}_${column.id}',
                      ),
                      sheet: sheet,
                      row: row,
                      column: column,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            action,
            Tooltip(
              message: removeWhy ?? 'Remove this line',
              child: IconButton(
                key: ValueKey<String>('row_remove_$row'),
                onPressed: removeWhy == null
                    ? () => onRemove == null ? sheet.removeRow(row) : onRemove!(row)
                    : null,
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled field of a part line.
///
/// A list (and gauge, material) opens the sheet's picker; Part No and Part
/// Code carry the Auto pill; everything else is typed. It writes through the
/// controller exactly as the grid's cell did, and keeps that cell's focus
/// contract: gaining focus moves the cursor here (and so the sections below
/// onto this part), leaving marks it touched.
class _PartField extends StatefulWidget {
  const _PartField({
    super.key,
    required this.sheet,
    required this.row,
    required this.column,
  });

  final SheetController sheet;
  final int row;
  final ColumnDef column;

  @override
  State<_PartField> createState() => _PartFieldState();
}

class _PartFieldState extends State<_PartField> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hadFocus = false;
  bool _wasWanted = false;

  ColumnDef get _column => widget.column;
  SheetController get _sheet => widget.sheet;

  bool get _isList =>
      _column.kind == ColumnKind.list ||
      _column.kind == ColumnKind.gauge ||
      _column.kind == ColumnKind.material;

  bool get _isDerived =>
      _column.kind == ColumnKind.seq || _column.kind == ColumnKind.code;

  bool get _locked => _sheet.isRowLocked(widget.row);

  CellValue? get _value => _sheet.draftAt(widget.row).get(_column.id);

  String get _shown {
    final v = _value;
    if (v == null) return '';
    return v.optionLabel ?? v.textValue ?? (v.intValue?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    _text.text = _shown;
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _hadFocus = true;
        _sheet.focusCell(_column.id, row: widget.row);
      } else if (_hadFocus) {
        _hadFocus = false;
        _sheet.markTouched(_column.id, row: widget.row);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _PartField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follows the draft — derive, a picked option, a loaded part — unless the
    // person is typing in it.
    if (!_focus.hasFocus && _text.text != _shown) _text.text = _shown;
    // Focus arrives with the cursor (Add part puts it on the new Group), but
    // only on arrival: taking it on every rebuild stole it from other fields.
    final wanted = _sheet.row == widget.row &&
        !_sheet.isHeaderFocused &&
        _sheet.focusedColumnId == _column.id;
    if (wanted && !_wasWanted && !_focus.hasFocus) _focus.requestFocus();
    _wasWanted = wanted;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open(BuildContext anchor) {
    if (_locked) return;
    _sheet.focusCell(_column.id, row: widget.row);
    showColumnOptionPicker(
      anchor,
      column: _column,
      sheetDef: _sheet.sheetDef,
      controller: _sheet,
      row: widget.row,
      onDone: () {
        if (mounted) _focus.nextFocus();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isList) return _optionField();
    final derived = _isDerived;
    final mode = _value?.mode ?? ValueMode.auto;
    final numeric = _column.kind == ColumnKind.seq ||
        _column.kind == ColumnKind.number ||
        _column.kind == ColumnKind.money;
    return FitToText(
      controller: _text,
      texts: [_column.label],
      minWidth: numeric ? 120 : 150,
      chrome: derived ? 64 : 24,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        readOnly: _locked,
        keyboardType: numeric ? TextInputType.number : null,
        style: const TextStyle(fontSize: 14),
        decoration: SheetStyle.field(
          label: _column.label,
          suffixIcon: derived && !_locked
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    widthFactor: 1,
                    child: ModeChip(
                      controller: _sheet,
                      columnId: _column.id,
                      row: widget.row,
                      mode: mode,
                    ),
                  ),
                )
              : null,
        ),
        onChanged: (value) =>
            _sheet.updateTextValue(_column.id, value, row: widget.row),
        onSubmitted: (_) => _focus.nextFocus(),
      ),
    );
  }

  /// A property — Alloy, Thickness, one added with Add property.
  bool get _isProperty => SheetBindsTo.isVariation(_column.bindsTo);

  Widget _optionField() {
    final field = _optionBox(labelInside: !_isProperty);
    if (!_isProperty) return field;
    // A property's name is a heading over its box, with its Edit and Delete.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PropertyHeading(sheet: _sheet, column: _column, row: widget.row),
        const SizedBox(height: 2),
        field,
      ],
    );
  }

  Widget _optionBox({required bool labelInside}) {
    final value = _value;
    final label = _shown;
    final isNew = value?.isNew ?? false;
    // A property can be taken off the part: × empties the box, and the save
    // takes the value off. Group, Type and the name are not optional.
    final clearable = _isProperty && !_locked && label.isNotEmpty;
    return FitToText(
      controller: _text,
      texts: [_column.label, 'Select…'],
      minWidth: 150,
      chrome: (isNew ? 96 : 56) + (clearable ? 32 : 0),
      child: Builder(
        builder: (anchor) => Focus(
          focusNode: _focus,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            final alt = HardwareKeyboard.instance.isAltPressed;
            if ((alt && key == LogicalKeyboardKey.arrowDown) ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.space) {
              _open(anchor);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ListenableBuilder(
            listenable: _focus,
            builder: (context, _) => InkWell(
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
              onTap: () {
                _focus.requestFocus();
                _open(anchor);
              },
              child: InputDecorator(
                isFocused: _focus.hasFocus,
                isEmpty: false,
                decoration: SheetStyle.field(
                  label: labelInside ? _column.label : null,
                  suffixIcon: _locked
                      ? null
                      : const Icon(
                          Icons.arrow_drop_down_rounded,
                          color: SoftErpTheme.textSecondary,
                        ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label.isEmpty ? (_locked ? '—' : 'Select…') : label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: label.isEmpty
                            ? SheetStyle.muted
                            : const TextStyle(
                                fontSize: 14,
                                color: SoftErpTheme.textPrimary,
                              ),
                      ),
                    ),
                    if (clearable)
                      Tooltip(
                        message: 'Clear ${_column.label}',
                        child: InkWell(
                          key: ValueKey<String>(
                            'property_clear_${_column.id}_${widget.row}',
                          ),
                          borderRadius:
                              BorderRadius.circular(SoftErpTheme.radiusXs),
                          onTap: () =>
                              _sheet.clearCell(_column.id, row: widget.row),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: SoftErpTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    if (isNew) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: SoftErpTheme.successBg,
                          borderRadius:
                              BorderRadius.circular(SoftErpTheme.radiusXs),
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
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A property's name over its box, and its two actions: Edit and Delete.
///
/// Each asks first — a property is the whole sheet's, not this part's. One
/// that is built into every part sheet (Alloy, Thickness) has neither, and
/// says so rather than hiding them.
class _PropertyHeading extends StatelessWidget {
  const _PropertyHeading({
    required this.sheet,
    required this.column,
    required this.row,
  });

  final SheetController sheet;
  final ColumnDef column;
  final int row;

  @override
  Widget build(BuildContext context) {
    // Only a property added here is stored, and so can be edited or removed.
    final stored = sheet.canEditOptions?.call(column) ?? false;
    final builtIn = '${column.label} is built into every part sheet';
    final (removable, removeWhy) = sheet.sheetDef.canRemove(column.id);
    final String? deleteWhy =
        !stored ? builtIn : (removable ? null : removeWhy);

    Widget action({
      required String key,
      required IconData icon,
      required String tip,
      required VoidCallback? onPressed,
      Color? color,
    }) =>
        Tooltip(
          message: tip,
          child: IconButton(
            key: ValueKey<String>(key),
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            color: color ?? SoftErpTheme.accent,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(column.label, style: SheetStyle.label),
        const SizedBox(width: 4),
        action(
          key: 'property_edit_${column.id}_$row',
          icon: Icons.edit_outlined,
          tip: stored ? 'Edit ${column.label}' : builtIn,
          onPressed: stored ? () => _edit(context) : null,
        ),
        action(
          key: 'property_delete_${column.id}_$row',
          icon: Icons.delete_outline_rounded,
          tip: deleteWhy ?? 'Delete ${column.label}',
          color: SoftErpTheme.dangerText,
          // The sheet's own remove asks "Remove … from the sheet?" first.
          onPressed: deleteWhy == null
              ? () => sheet.requestRemoveColumn(column.id)
              : null,
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context) async {
    final sure = await showConfirmDialog(
      context,
      title: 'Edit ${column.label}?',
      message: 'Its list is the whole sheet’s — a change shows on every part. '
          'Parts keep the values they were saved with.',
      confirmLabel: 'Edit',
      destructive: false,
    );
    if (sure) sheet.onEditOptions?.call(column);
  }
}
