import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/utils/dropdown_intents.dart';
import '../../../../core/utils/typed_character.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/even_grid.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../production_pipelines/domain/thickness_label.dart';
import '../../../units/domain/global_length_units.dart';
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
    this.flow,
    this.lineActions,
    this.showShortcuts = false,
  });

  /// Whether to display Alt keytip badges for rapid keyboard navigation.
  final bool showShortcuts;

  /// The keyboard's order of the screen's steps; each line is one.
  final SheetFlow? flow;

  /// What Tab past a line's last field does — its save prompt.
  final SheetStepActions Function(int row)? lineActions;

  /// The step id of the line with [rowKey].
  static Object stepId(Object rowKey) => ('part', rowKey);

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

  /// The fields of a line, row by row as [lineGrid] draws them — which is
  /// also the order Tab visits them in.
  static List<ColumnDef> lineColumns(SheetDef def) => [
        for (final cells in lineGrid(def)) ...cells.whereType<ColumnDef>(),
      ];

  /// A line's fields as four even columns, so every part reads the same:
  ///
  ///     Group | Type      | Part Name | Part Code
  ///     Alloy | Thickness | Grade     | Part No
  ///
  /// A window too narrow for four reads two at a time, in the same order
  /// ([EvenGrid]).
  ///
  /// The last column holds the part's two numbers; the properties fill the
  /// three before it, a row at a time, however many have been added. A null
  /// is an empty cell. The stamp columns (Date, Time) are left out: the save
  /// fills them, nobody types them — the heading shows them.
  static const int gridColumns = 4;

  static List<List<ColumnDef?>> lineGrid(SheetDef def) {
    final columns = [
      for (final group in const [
        TableGroup.groupItem,
        TableGroup.properties,
        TableGroup.primaryGroup,
      ])
        ...def.columns.where((c) => def.tableOf(c) == group && !c.isStamp),
    ];
    ColumnDef? bound(String binds) =>
        columns.where((c) => c.bindsTo == binds).firstOrNull;
    final identity = [
      bound(SheetBindsTo.group),
      bound(SheetBindsTo.set),
      bound(SheetBindsTo.name),
    ];
    final code = bound(SheetBindsTo.partCode);
    final number = bound(SheetBindsTo.partNo);
    final placed = {
      for (final column in [...identity, code, number])
        if (column != null) column.id,
    };
    final rest = columns.where((c) => !placed.contains(c.id)).toList();
    final rows = <List<ColumnDef?>>[
      [...identity, code],
      for (var i = 0; i == 0 || i < rest.length; i += 3)
        [
          for (var j = i; j < i + 3; j += 1) j < rest.length ? rest[j] : null,
          i == 0 ? number : null,
        ],
    ];
    return [
      for (final cells in rows)
        if (cells.any((c) => c != null)) cells,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sheet,
      builder: (context, _) {
        final grid = lineGrid(sheet.sheetDef);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var row = 0; row < sheet.rowCount; row += 1) ...[
              _step(
                row,
                _PartLine(
                  key: ValueKey<Object>(sheet.draftAt(row).rowKey),
                  sheet: sheet,
                  row: row,
                  grid: grid,
                  photo: photoBuilder?.call(row),
                  status: statusBuilder?.call(row),
                  action: actionBuilder(row),
                  onRemove: onRemoveRow,
                  showShortcuts: showShortcuts,
                ),
              ),
              const SizedBox(height: 10),
            ],
            SheetStep.noTab(_footer()),
          ],
        );
      },
    );
  }

  /// A line as one keyboard step: Tab through its fields, then its save.
  Widget _step(int row, Widget line) {
    final actions = lineActions;
    if (actions == null) return line;
    final rowKey = sheet.draftAt(row).rowKey;
    return SheetStep(
      key: ValueKey<Object>(('step', rowKey)),
      flow: flow,
      id: stepId(rowKey),
      actions: actions(row),
      child: line,
    );
  }

  Widget _footer() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              key: const ValueKey<String>('part_add_row'),
              onPressed: onAddPart,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add part', style: TextStyle(fontSize: 14)),
            ),
            if (showShortcuts) ...[
              const SizedBox(width: 2),
              const KeyTipBadge(label: 'Alt+1'),
            ],
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            if (showShortcuts) ...[
              const SizedBox(width: 2),
              const KeyTipBadge(label: 'Alt+D'),
            ],
          ],
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
    required this.grid,
    required this.photo,
    required this.status,
    required this.action,
    this.onRemove,
    this.showShortcuts = false,
  });

  final Future<void> Function(int row)? onRemove;
  final SheetController sheet;
  final int row;
  final bool showShortcuts;

  /// The fields, row by row: see [PartRowsForm.lineGrid].
  final List<List<ColumnDef?>> grid;
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
        // The fields sit in even columns; Save and × stay at the line's end
        // whatever the width, with the part's photo showcased right above Save.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (status != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: SizedBox(width: 28, child: status),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: EvenGrid(
                columns: PartRowsForm.gridColumns,
                minColumnWidth: 160,
                children: [
                  for (final cells in grid)
                    for (final column in cells)
                      column == null
                          ? const SizedBox.shrink()
                          : _PartField(
                              key: ValueKey<String>(
                                'cell_${sheet.sheetDef.key}_${row}_${column.id}',
                              ),
                              sheet: sheet,
                              row: row,
                              column: column,
                              showShortcuts: showShortcuts,
                            ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: EdgeInsets.only(top: photo != null ? 2 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (photo != null) ...[
                    SheetStep.noTab(photo!),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SheetStep.noTab(action),
                      SheetStep.noTab(Tooltip(
                        message: removeWhy ?? 'Remove this line',
                        child: IconButton(
                          key: ValueKey<String>('row_remove_$row'),
                          onPressed: removeWhy == null
                              ? () => onRemove == null ? sheet.removeRow(row) : onRemove!(row)
                              : null,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      )),
                    ],
                  ),
                ],
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
    this.showShortcuts = false,
  });

  final SheetController sheet;
  final int row;
  final ColumnDef column;
  final bool showShortcuts;

  @override
  State<_PartField> createState() => _PartFieldState();
}

class _PartFieldState extends State<_PartField> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hadFocus = false;
  bool _wasWanted = false;
  bool _isPickerOpen = false;
  bool _skipNextAutoOpen = false;

  ColumnDef get _column => widget.column;
  SheetController get _sheet => widget.sheet;

  String? get _shortcutKey {
    final binds = _column.bindsTo;
    if (binds == SheetBindsTo.group) return 'G';
    if (binds == SheetBindsTo.set) return 'T';
    if (binds == SheetBindsTo.name) return 'N';
    if (binds == SheetBindsTo.partCode) return 'C';
    if (binds == SheetBindsTo.partNo) return 'P';
    final label = _column.label.trim().toLowerCase();
    if (label.contains('alloy')) return 'A';
    if (label.contains('thick')) return 'K';
    if (label.contains('grade')) return 'R';
    if (label.contains('hard')) return 'H';
    return _column.label.isNotEmpty ? _column.label[0].toUpperCase() : null;
  }

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
    _text.text = _isThickness ? _thicknessNumber : _shown;
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
    // A dropdown box is never typed into, so it follows even with focus — a
    // focused Part Name kept its old width and cut the name it now shows.
    if (_isThickness) {
      // The number follows the cell unless it is being typed.
      if (!_focus.hasFocus && _text.text != _thicknessNumber) {
        _text.text = _thicknessNumber;
      }
    } else if ((_isList || !_focus.hasFocus) && _text.text != _shown) {
      _text.text = _shown;
    }
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

  void _open(BuildContext anchor, {String initialQuery = ''}) {
    if (_locked || _isPickerOpen) return;
    _isPickerOpen = true;
    _sheet.focusCell(_column.id, row: widget.row);
    showColumnOptionPicker(
      anchor,
      column: _column,
      sheetDef: _sheet.sheetDef,
      controller: _sheet,
      row: widget.row,
      initialQuery: initialQuery,
      onDone: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
      },
      // Tab in the open list keeps the box as it is and goes on from it.
      onTabOut: (back) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _focus.requestFocus();
          tabOutFrom(_focus, back: back);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isThickness) return _thicknessField();
    if (_isList) return _optionField();
    final derived = _isDerived;
    final mode = _value?.mode ?? ValueMode.auto;
    final numeric = _column.kind == ColumnKind.seq ||
        _column.kind == ColumnKind.number ||
        _column.kind == ColumnKind.money;
    return SheetStyle.labelled(
      label: _column.label,
      shortcutKey: _shortcutKey,
      showShortcut: widget.showShortcuts,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        readOnly: _locked,
        keyboardType: numeric ? TextInputType.number : null,
        style: const TextStyle(fontSize: 14),
        decoration: SheetStyle.field(
          suffixIcon: derived && !_locked
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    widthFactor: 1,
                    child: SheetStep.noTab(ModeChip(
                      controller: _sheet,
                      columnId: _column.id,
                      row: widget.row,
                      mode: mode,
                    )),
                  ),
                )
              : null,
        ),
        onChanged: (value) =>
            _sheet.updateTextValue(_column.id, value, row: widget.row),
        onSubmitted: (_) => tabOutFrom(_focus, back: false),
      ),
    );
  }

  /// A property — Alloy, Thickness, one added with Add property.
  bool get _isProperty => SheetBindsTo.isVariation(_column.bindsTo);

  // --- Thickness: a number and its unit ---------------------------------------

  /// A gauge column: typed as a number with a unit beside it, not picked from
  /// the gauge table. A number on its own is a gauge.
  bool get _isThickness => _column.kind == ColumnKind.gauge;

  /// The unit chosen while the cell is still empty — gauge until changed.
  String _pendingUnit = 'ga';

  /// The units a thickness is given in: gauge first, the default.
  static final List<GlobalLengthUnit> _thicknessUnits = [
    ...globalLengthUnits.where((unit) => unit.isGauge),
    ...globalLengthUnits.where((unit) => !unit.isGauge),
  ];

  ThicknessReading? get _thicknessReading => readThickness(_shown);

  /// The cell's number, as typed: "23" for "23 Gauge", "1.2" for "1.2 mm".
  String get _thicknessNumber {
    final reading = _thicknessReading;
    if (reading == null) return _shown;
    final value = reading.value;
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value
              .toStringAsFixed(4)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }

  /// The cell's unit, or the one chosen for it before a number was typed.
  String get _thicknessUnit => _thicknessReading?.unit.symbol ?? _pendingUnit;

  /// Writes number + unit into the cell the way the raw panel does
  /// ("23 Gauge", "1.2 mm") — a gauge that is in the table is that option.
  void _writeThickness(String number, String unitSymbol) {
    final text = number.trim();
    if (text.isEmpty) {
      _sheet.clearCell(_column.id, row: widget.row);
      return;
    }
    final value = double.tryParse(text);
    final label = value == null
        ? text
        : writeThickness(value, lengthUnitBySymbol(unitSymbol));
    final wanted = label.toLowerCase();
    final option = _sheet.options
        .where((o) => o.columnId == _column.id && o.label.toLowerCase() == wanted)
        .firstOrNull;
    if (option != null) {
      _sheet.setOption(_column.id, option, row: widget.row);
    } else {
      _sheet.updateValue(
        _column.id,
        CellValue(columnId: _column.id, optionLabel: label),
        row: widget.row,
      );
    }
  }

  Widget _thicknessField() {
    final unit = _thicknessUnit;
    return SheetStyle.labelled(
      label: _column.label,
      shortcutKey: _shortcutKey,
      showShortcut: widget.showShortcuts,
      actions: [
        SheetStep.noTab(
          _PropertyActions(sheet: _sheet, column: _column, row: widget.row),
        ),
      ],
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              readOnly: _locked,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // A gauge is a whole number; a measurement may have decimals.
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  unit == 'ga' ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
                ),
              ],
              style: const TextStyle(fontSize: 14),
              decoration: SheetStyle.field(hint: unit == 'ga' ? 'Gauge' : unit),
              onChanged: (value) => _writeThickness(value, unit),
              onSubmitted: (_) => tabOutFrom(_focus, back: false),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 118,
            child: SearchableSelectField<String>(
              key: ValueKey<String>('thickness_unit_${widget.row}'),
              value: unit,
              fieldEnabled: !_locked,
              dialogTitle: 'Thickness in',
              searchHintText: 'Search units',
              options: [
                for (final option in _thicknessUnits)
                  SearchableSelectOption<String>(
                    value: option.symbol,
                    label: option.isGauge ? 'Gauge' : option.symbol,
                    subtitle: option.name,
                    searchText: '${option.name} ${option.symbol}',
                  ),
              ],
              decoration: SheetStyle.field(),
              onChanged: (symbol) {
                if (symbol == null) return;
                setState(() => _pendingUnit = symbol);
                // The number keeps what was typed; the unit says what it is.
                if (_text.text.trim().isNotEmpty) _writeThickness(_text.text, symbol);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionField() => SheetStyle.labelled(
        label: _column.label,
        shortcutKey: _shortcutKey,
        showShortcut: widget.showShortcuts,
        actions: _isProperty
            ? [
                SheetStep.noTab(
                  _PropertyActions(sheet: _sheet, column: _column, row: widget.row),
                ),
              ]
            : const [],
        child: _optionBox(),
      );

  Widget _optionBox() {
    final value = _value;
    final label = _shown;
    final isNew = value?.isNew ?? false;
    // A property can be taken off the part: × empties the box, and the save
    // takes the value off. Group, Type and the name are not optional.
    final clearable = _isProperty && !_locked && label.isNotEmpty;
    return Builder(
        // Tab landing on the box (the sheet's keyboard flow) opens its list.
        builder: (anchor) => Actions(
          actions: {
            OpenDropdownIntent: CallbackAction<OpenDropdownIntent>(
              onInvoke: (_) {
                if (_locked) return null;
                _open(anchor);
                return true;
              },
            ),
          },
          child: Focus(
          focusNode: _focus,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            // A saved line is closed: its step takes Enter as its Edit. And
            // Ctrl+Enter is the step's "save and add another".
            final keyboard = HardwareKeyboard.instance;
            if (_locked || keyboard.isControlPressed || keyboard.isMetaPressed) {
              return KeyEventResult.ignored;
            }
            final key = event.logicalKey;
            final alt = HardwareKeyboard.instance.isAltPressed;
            if ((alt && key == LogicalKeyboardKey.arrowDown) ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter ||
                key == LogicalKeyboardKey.space) {
              _open(anchor);
              return KeyEventResult.handled;
            }
            // Typing on the closed box starts the search with that letter.
            final typed = typedCharacter(event);
            if (typed != null) {
              _open(anchor, initialQuery: typed);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ListenableBuilder(
            listenable: _focus,
            builder: (context, _) => InkWell(
              // The box's own Focus is its one Tab stop.
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
              onTap: () {
                _focus.requestFocus();
                _open(anchor);
              },
              child: InputDecorator(
                isFocused: _focus.hasFocus,
                isEmpty: false,
                decoration: SheetStyle.field(
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
                      SheetStep.noTab(Tooltip(
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
                      )),
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

/// A property's two actions, after its name: Edit and Delete.
///
/// Each asks first — a property is the whole sheet's, not this part's. One
/// that is built into every part sheet (Alloy, Thickness) has neither, and
/// says so rather than hiding them.
class _PropertyActions extends StatelessWidget {
  const _PropertyActions({
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
          child: Opacity(
            opacity: stored ? 1.0 : 0.4,
            child: IconButton(
              key: ValueKey<String>(key),
              onPressed: onPressed,
              icon: Icon(icon, size: stored ? 16 : 14),
              color: color ?? SoftErpTheme.textSecondary,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: stored ? 24 : 20,
                height: stored ? 24 : 20,
              ),
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          color: stored ? SoftErpTheme.dangerText : SoftErpTheme.textSecondary,
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
