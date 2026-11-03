import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../column_def.dart';
import '../column_option.dart';
import '../sheet_def.dart';
import '../sheet_draft.dart';
import '../sheet_controller.dart';
import '../sheet_engine.dart';

/// Opens the column's option list under [context]'s box: the sheet's one
/// picker, shared by the grid's cells and the item sheet's part lines.
///
/// [onDone] runs after a pick or an add — the grid moves to the next cell.
void showColumnOptionPicker(
  BuildContext context, {
  required ColumnDef column,
  required SheetDef sheetDef,
  required SheetController controller,
  required int row,
  VoidCallback? onDone,
}) {
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
      column: column,
      sheetDef: sheetDef,
      controller: controller,
      rowIndex: row,
      onSelectOption: (opt) {
        Navigator.of(ctx).pop();
        controller.setOption(
          column.id,
          opt,
          row: row,
        );
        onDone?.call();
      },
      onAddNew: (newLabel) {
        Navigator.of(ctx).pop();
        controller.addNewOption(
          column.id,
          newLabel,
          row: row,
        );
        onDone?.call();
      },
      onSelectParty: (p) {
        Navigator.of(ctx).pop();
        controller.updateValue(
          column.id,
          CellValue(
            columnId: column.id,
            refId: p.id,
            optionLabel: p.name,
          ),
          row: row,
        );
        onDone?.call();
      },
      onSelectContact: (c) {
        Navigator.of(ctx).pop();
        // Fills this cell AND the designation, phone and email columns beside
        // it. `updateValue` alone wrote only the name, so choosing a contact
        // left its three projection columns blank — the one method that
        // filled them, `ItemMasterController.pickContact`, had no caller in
        // the app at all.
        controller.applyContact(
          column.id,
          c,
          row: row,
        );
        onDone?.call();
      },
      onAddContact: controller.onAddContact == null
          ? null
          : (typed) async {
              // The company this contact column hangs under. Read here
              // rather than taken from the picker, which has its own copy.
              final parentId = column.parentId;
              final partyId = parentId == null
                  ? null
                  : controller
                      .draftAt(row)
                      .get(parentId)
                      ?.refId;
              if (partyId == null) return;
              final made = await controller.onAddContact!(
                partyId,
                typed,
              );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              if (made == null) return;
              // Selected straight away: the picker's list was built before
              // this person existed, so waiting for a refresh would close on
              // nothing.
              controller.applyContact(
                column.id,
                made,
                row: row,
              );
              onDone?.call();
            },
    ),
    ),
  );
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
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
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
              color: SoftErpTheme.shellSurface,
              border: Border(bottom: BorderSide(color: SoftErpTheme.sectionSurface)),
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
                      color: SoftErpTheme.textSecondary,
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
                  borderRadius: BorderRadius.circular(SoftErpTheme.radiusControl),
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
                        color: SoftErpTheme.textMuted,
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
                        color: SoftErpTheme.textMuted,
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
                                color: SoftErpTheme.textSecondary,
                              ),
                            ),
                      trailing: _trailingFor(opt),
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

  /// The "New" badge on a value typed this session, and the delete button on
  /// a value the host keeps a list of.
  Widget? _trailingFor(ColumnOption opt) {
    final removal = widget.controller.removalFor?.call(widget.column, opt);
    final badge = opt.isNew
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: SoftErpTheme.successBg,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
            ),
            child: const Text(
              'New',
              style: TextStyle(fontSize: 13, color: SoftErpTheme.successText),
            ),
          )
        : null;
    if (removal == null) return badge;
    final remove = removal.remove;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?badge,
        // Drawn disabled, with the reason, rather than hidden: a button that
        // comes and goes reads as broken.
        IconButton(
          key: ValueKey<String>('sheet_option_delete_${opt.label}'),
          tooltip: removal.blockedBecause ?? 'Delete “${opt.label}” from this list',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          color: SoftErpTheme.dangerText,
          onPressed: remove == null
              ? null
              : () async {
                  final gone = await remove();
                  if (!gone || !mounted) return;
                  widget.controller.dropOption(widget.column.id, opt.label);
                },
        ),
      ],
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
            color: SoftErpTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
