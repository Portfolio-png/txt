import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/utils/dropdown_intents.dart';
import '../../../../core/utils/typed_character.dart';
import '../../../../core/widgets/confirm_dialog.dart';
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
    this.showcaseRow,
    this.showcasePhotoBuilder,
    this.currentRowOnly = false,
  });

  /// Draws the part the cursor is on and no other: the host shows the parts
  /// as tabs ([PartTabs]), and its + adds one. Every part is still a row of
  /// [sheet]; what was typed on the others waits there.
  final bool currentRowOnly;

  /// The line whose photo is shown big, beside its fields — as tall as they
  /// are — with Save and × under it. Null shows every line's small photo.
  ///
  /// The host decides when: the photos sit in the right-hand column while a
  /// line is being typed in, and come over to the line once the work has
  /// moved on to the right-hand form (raw material).
  final int? showcaseRow;

  /// The showcased line's photo at [side] × [side].
  final Widget Function(int row, double side)? showcasePhotoBuilder;

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

  /// A line's fields, in two lines (user, 2026-11-25):
  ///
  ///     Group | Type      | Part Name | Part No
  ///     Alloy | Thickness | Grade     | Hardness | … | Part Code
  ///
  /// The second line always starts on a line of its own, holds every
  /// property — the two built in, then each one added with the + — and ends
  /// with the Part Code, which is built from them. Each line is a wrap of
  /// fields as wide as what they hold, so a long second line wraps within
  /// itself; this is also the order Tab follows. The stamp columns (Date,
  /// Time) are left out: the save fills them, nobody types them — the
  /// heading shows them.
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
    // Part No ends the first line, beside the name; the properties make the
    // second line, and the code they build ends it.
    final rows = <List<ColumnDef?>>[
      [...identity, number],
      [...rest, code],
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
            for (var row = 0; row < sheet.rowCount; row += 1)
              if (!currentRowOnly || row == sheet.row) ...[
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
                    // One part at a time: its Save and × sit on the footer's
                    // line beside Add property instead of a row of their own.
                    actionsInLine: !currentRowOnly,
                    onRemove: onRemoveRow,
                    showShortcuts: showShortcuts,
                    showcasePhoto: row == showcaseRow
                        ? showcasePhotoBuilder
                        : null,
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
    final row = sheet.row;
    final actions = currentRowOnly && row >= 0 && row < sheet.rowCount;
    final tools = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!currentRowOnly)
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
                label: const Text(
                  'Add property',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
            if (showShortcuts) ...[
              const SizedBox(width: 2),
              const KeyTipBadge(label: 'Alt+D'),
            ],
          ],
        ),
      ],
    );
    if (!actions) return tools;
    return Row(
      children: [
        Expanded(child: tools),
        const SizedBox(width: 10),
        actionBuilder(row),
        partRemoveButton(sheet, row, onRemoveRow),
      ],
    );
  }
}

/// A part's ×: drawn always, disabled with the reason when the part may not
/// go — a saved part, or the sheet's last one.
Widget partRemoveButton(
  SheetController sheet,
  int row,
  Future<void> Function(int row)? onRemove,
) {
  final saved = sheet.draftAt(row).entityId != null;
  final String? why = saved
      ? 'Saved parts stay in the catalogue — use Archive part'
      : (sheet.rowCount <= 1 ? 'A sheet always keeps one part' : null);
  return Tooltip(
    message: why ?? 'Remove this line',
    child: IconButton(
      key: ValueKey<String>('row_remove_$row'),
      onPressed: why == null
          ? () => onRemove == null ? sheet.removeRow(row) : onRemove(row)
          : null,
      icon: const Icon(Icons.close, size: 18),
    ),
  );
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
    this.showcasePhoto,
    this.actionsInLine = true,
  });

  final Future<void> Function(int row)? onRemove;

  /// Whether Save and × are drawn in the line; false when the form's footer
  /// carries them ([PartRowsForm.currentRowOnly]).
  final bool actionsInLine;

  /// Set when this line shows its photo big ([PartRowsForm.showcaseRow]).
  final Widget Function(int row, double side)? showcasePhoto;
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
        child: showcasePhoto != null
            ? _showcase(context)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (status != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: SizedBox(width: 28, child: status),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: _fields()),
                  const SizedBox(width: 10),
                  Padding(
                    padding: EdgeInsets.only(top: photo != null ? 2 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (photo != null) SheetStep.noTab(photo!),
                        if (actionsInLine) ...[
                          if (photo != null) const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SheetStep.noTab(action),
                              SheetStep.noTab(
                                partRemoveButton(sheet, row, onRemove),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// The line's fields in even columns: see [PartRowsForm.lineGrid].
  ///
  /// Keyed globally to the line: it switches between its two layouts (small
  /// photo, big photo) the moment one of its fields takes focus, and without
  /// the key the fields were rebuilt in the new layout and lost that focus.
  /// The line's fields, each as wide as what it holds, side by side in the
  /// grid's order and wrapping only when the line is full.
  ///
  /// Keyed globally to the line: it switches between its two layouts (small
  /// photo, big photo) the moment one of its fields takes focus, and without
  /// the key the fields were rebuilt in the new layout and lost that focus.
  ///
  /// One wrap per line of [PartRowsForm.lineGrid], so the properties always
  /// start a line of their own instead of following the name on whatever
  /// room is left.
  Widget _fields() => Column(
    key: _LineFieldsKey(sheet.draftAt(row).rowKey),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < grid.length; i += 1) ...[
        if (i > 0) const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            for (final column in grid[i])
              if (column != null)
                _PartField(
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
      ],
    ],
  );

  /// The line with its photo shown big: the fields, and beside them the
  /// photo as a square as tall as they are; Save and × under the photo.
  Widget _showcase(BuildContext context) {
    final build = showcasePhoto!;
    return Row(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FieldsBesidePhoto(
                fields: _fields(),
                photo: SheetStep.noTab(
                  LayoutBuilder(
                    builder: (context, box) => KeyedSubtree(
                      key: ValueKey<String>('part_showcase_photo_$row'),
                      child: build(row, box.maxWidth),
                    ),
                  ),
                ),
              ),
              if (actionsInLine) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SheetStep.noTab(action),
                      SheetStep.noTab(partRemoveButton(sheet, row, onRemove)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A part line's fields, by the line's own identity (not its index).
class _LineFieldsKey extends GlobalObjectKey {
  const _LineFieldsKey(super.value);
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

  double? _lastTextWidth;
  void _onTextWidth() {
    if (!mounted) return;
    final width = _text.text.length.toDouble();
    if (width == _lastTextWidth) return;
    _lastTextWidth = width;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _text.text = _isThickness ? _thicknessNumber : _shown;
    // The box grows and shrinks with what is typed into it.
    _text.addListener(_onTextWidth);
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
    final wanted =
        _sheet.row == widget.row &&
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
      // However it closes — a pick, Escape, a click outside, Tab. The flag was
      // set here and never cleared, so after a field's first pick neither a
      // click nor a key could open its list again.
      onClosed: () => _isPickerOpen = false,
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
    final field = _isThickness
        ? _thicknessField()
        : (_isList ? _optionField() : _textField());
    return SizedBox(width: _fitWidth(context), child: field);
  }

  // --- the field's width: as wide as what it holds -------------------------

  /// The narrowest a field goes, so an empty one is still a target.
  static const double minFieldWidth = 96;

  /// The widest: past it the text is cut with … and the box keeps its place.
  static const double maxFieldWidth = 360;

  static const TextStyle _valueStyle = TextStyle(fontSize: 14);

  /// A picked value, measured a shade heavy so it never comes up short.
  static const TextStyle _pickedStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// The theme's font, which the fields draw in: measured in another, a
  /// box came out short for its own text.
  TextStyle _themed(TextStyle style) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).merge(
        style,
      );

  double _measure(String text, TextStyle style, TextScaler scaler) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _themed(style)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The widest of the field's heading and the text in its box, with room
  /// for what sits beside each: a property's Edit and Delete, a key tip, the
  /// box's padding, its arrow, its × or New, the Auto pill, the unit picker.
  double _fitWidth(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    var heading = _measure(
      SheetStyle.titleCase(_column.label),
      SheetStyle.label,
      scaler,
    );
    if (_isProperty || _isThickness) heading += 4 + 2 * 24;
    if (widget.showShortcuts && _shortcutKey != null) heading += 34;

    // The box: 12 padding each side, the border, the caret.
    const box = 12.0 * 2 + 2 + 4;
    final double inBox;
    if (_isThickness) {
      final unit = _thicknessUnit;
      final typed = _text.text.isEmpty
          ? (unit == 'ga' ? 'Gauge' : unit)
          : _text.text;
      inBox = _measure(typed, _valueStyle, scaler) + box + 6 + 118;
    } else if (_isList) {
      final label = _shown;
      final shown = label.isEmpty ? (_locked ? '—' : 'Select…') : label;
      // The arrow is the decoration's suffix icon, which takes 48 whatever
      // it draws; 32 here cut every name short ("Manufacturi…").
      var extra = 48.0;
      if (_isProperty && !_locked && label.isNotEmpty) extra += 30; // its ×
      if (_value?.isNew ?? false) extra += 50; // "New"
      inBox = _measure(shown, _pickedStyle, scaler) + box + extra;
    } else {
      final derived = _isDerived && !_locked;
      inBox =
          _measure(_text.text, _pickedStyle, scaler) + box + (derived ? 80 : 0);
    }
    final widest = heading > inBox ? heading : inBox;
    return widest.clamp(minFieldWidth, maxFieldWidth).toDouble();
  }

  Widget _textField() {
    final derived = _isDerived;
    final mode = _value?.mode ?? ValueMode.auto;
    final numeric =
        _column.kind == ColumnKind.seq ||
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
                    child: SheetStep.noTab(
                      ModeChip(
                        controller: _sheet,
                        columnId: _column.id,
                        row: widget.row,
                        mode: mode,
                      ),
                    ),
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
        .where(
          (o) => o.columnId == _column.id && o.label.toLowerCase() == wanted,
        )
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
                if (_text.text.trim().isNotEmpty)
                  _writeThickness(_text.text, symbol);
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
            if (_locked ||
                keyboard.isControlPressed ||
                keyboard.isMetaPressed) {
              return KeyEventResult.ignored;
            }
            final key = event.logicalKey;
            final alt = HardwareKeyboard.instance.isAltPressed;
            // Enter again, straight after the one that picked: next field,
            // as Tab — not the list again (user, 2026-11-24).
            if (EnterTwice.isSecond(event)) {
              tabOutFrom(_focus, back: false);
              return KeyEventResult.handled;
            }
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
                      SheetStep.noTab(
                        Tooltip(
                          message: 'Clear ${_column.label}',
                          child: InkWell(
                            key: ValueKey<String>(
                              'property_clear_${_column.id}_${widget.row}',
                            ),
                            borderRadius: BorderRadius.circular(
                              SoftErpTheme.radiusXs,
                            ),
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
                          borderRadius: BorderRadius.circular(
                            SoftErpTheme.radiusXs,
                          ),
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
    final String? deleteWhy = !stored
        ? builtIn
        : (removable ? null : removeWhy);

    Widget action({
      required String key,
      required IconData icon,
      required String tip,
      required VoidCallback? onPressed,
      Color? color,
    }) => Tooltip(
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
      message:
          'Its list is the whole sheet’s — a change shows on every part. '
          'Parts keep the values they were saved with.',
      confirmLabel: 'Edit',
      destructive: false,
    );
    if (sure) sheet.onEditOptions?.call(column);
  }
}

/// A line's fields with its photo beside them, the photo a square exactly as
/// tall as the fields are.
///
/// The fields' height depends on their width (they wrap onto more lines on
/// a narrow one), and their width on how much the photo takes — so this lays
/// the fields out, sizes the photo to them, and lays them out again if that
/// changed the wrap. Two or three passes settle it. Text fields have no dry
/// layout to ask instead.
class _FieldsBesidePhoto extends MultiChildRenderObjectWidget {
  _FieldsBesidePhoto({required Widget fields, required Widget photo})
    : super(children: [fields, photo]);

  /// Between the fields and the photo.
  static const double gap = 16;

  /// The photo stays recognisable, and never crowds the fields out.
  static const double minSide = 120;
  static const double maxSide = 320;
  static const double maxShare = 0.38;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFieldsBesidePhoto();
}

class _FieldsBesidePhotoParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFieldsBesidePhoto extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FieldsBesidePhotoParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _FieldsBesidePhotoParentData
        > {
  /// The side the last layout settled on: the first guess for the next one,
  /// so a line that has not changed shape settles in one pass.
  double _side = _FieldsBesidePhoto.minSide;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FieldsBesidePhotoParentData) {
      child.parentData = _FieldsBesidePhotoParentData();
    }
  }

  @override
  void performLayout() {
    final fields = firstChild!;
    final photo = childAfter(fields)!;
    final width = constraints.maxWidth;
    final largest = math.min(
      _FieldsBesidePhoto.maxSide,
      math.max(_FieldsBesidePhoto.minSide, width * _FieldsBesidePhoto.maxShare),
    );
    var side = _side.clamp(_FieldsBesidePhoto.minSide, largest);
    for (var pass = 0; pass < 3; pass += 1) {
      final fieldsWidth = math.max(0.0, width - _FieldsBesidePhoto.gap - side);
      fields.layout(
        BoxConstraints.tightFor(width: fieldsWidth),
        parentUsesSize: true,
      );
      final next = fields.size.height.clamp(
        _FieldsBesidePhoto.minSide,
        largest,
      );
      if ((next - side).abs() < 0.5) break;
      side = next;
    }
    _side = side;
    photo.layout(BoxConstraints.tight(Size(side, side)), parentUsesSize: true);
    (fields.parentData! as _FieldsBesidePhotoParentData).offset = Offset.zero;
    (photo.parentData! as _FieldsBesidePhotoParentData).offset = Offset(
      width - side,
      0,
    );
    size = constraints.constrain(
      Size(width, math.max(fields.size.height, side)),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
