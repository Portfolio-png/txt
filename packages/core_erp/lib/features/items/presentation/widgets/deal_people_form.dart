import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/services/entity_photos.dart';
import '../../../../core/widgets/fit_to_text.dart';
import '../../../../core/widgets/mini_photo.dart';
import '../../../../core/widgets/pick_or_type_field.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../sheet/column_option.dart';
import '../../../clients/presentation/widgets/designation_field.dart'
    show kDesignationSuggestions;
import '../../../../sheet/item_master_controller.dart';
import '../../../../sheet/sheet_binding.dart';
import '../../../../sheet/sheet_controller.dart';
import '../../../../sheet/sheet_draft.dart';

/// The Client / Vendor section as an ordinary form: the deal (company,
/// quotation, when it was recorded) and the people at that company, each a
/// line of normal text fields with a "dealt with" tick.
///
/// A view only. Every edit lands on the same drafts the sheet cells used —
/// `clientVendorController` for the deal, `peopleController` for the people —
/// so saving, flushing people to the company and ticking are unchanged.
///
/// It replaced the spreadsheet cells, which ate keystrokes here: each rebuild
/// re-selected the cell's text, so typing 85000 left "0". This form owns its
/// text controllers and only copies a draft's text into a field the field is
/// not being typed into, so a rebuild can never take a character back.
class DealPeopleForm extends StatefulWidget {
  const DealPeopleForm({
    super.key,
    required this.controller,
    this.partSaved = false,
    this.onSaveDeal,
  });

  final ItemMasterController controller;

  /// Whether the part exists yet. Before it does, the deal is saved with the
  /// part row; after, the deal line has its own Save and Edit.
  final bool partSaved;

  /// Writes the deal (company, quotation, ticks) on the saved part. True when
  /// it landed.
  final Future<bool> Function()? onSaveDeal;

  @override
  State<DealPeopleForm> createState() => _DealPeopleFormState();
}

class _DealPeopleFormState extends State<DealPeopleForm> {
  final Map<String, TextEditingController> _texts = {};
  final Map<String, FocusNode> _focus = {};

  /// The deal line is open for editing. A saved part's deal opens with its
  /// Edit and closes again with its Save.
  bool _dealEditing = false;
  bool _savingDeal = false;

  /// A company just added from the dropdown, in case the pickers have not
  /// caught up by the time it is picked.
  Party? _created;

  SheetController get _deal => widget.controller.clientVendorController;

  /// Designations people at any company were given before, then the usual
  /// ones nobody has used yet — so "Purchase Head" is typed once and picked
  /// after that, and is not spelt three ways across the client list.
  List<String> _designations() {
    final seen = <String>{};
    return [
      for (final value in [
        for (final contact in _people.contacts) contact.designation ?? '',
        ...kDesignationSuggestions,
      ])
        if (value.trim().isNotEmpty && seen.add(value.trim().toLowerCase()))
          value.trim(),
    ];
  }
  SheetController get _people => widget.controller.peopleController;

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// The field for [key], showing [draftText] unless it is being typed into —
  /// then the field is the truth and the draft follows it.
  TextEditingController _field(String key, String draftText) {
    final controller = _texts.putIfAbsent(
      key,
      () => TextEditingController(text: draftText),
    );
    final focus = _focus.putIfAbsent(key, FocusNode.new);
    if (!focus.hasFocus && controller.text != draftText) {
      controller.text = draftText;
    }
    return controller;
  }

  int? _column(SheetController sheet, String binds) =>
      sheet.sheetDef.columnBoundTo(binds)?.id;

  String _text(SheetController sheet, String binds, {int? row}) {
    final id = _column(sheet, binds);
    if (id == null) return '';
    final value = (row == null ? sheet.draft : sheet.draftAt(row)).get(id);
    return value?.textValue ?? value?.optionLabel ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final hasCompany = widget.controller.dealPartyId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dealRow(),
        const SizedBox(height: 18),
        Tooltip(
          message: hasCompany ? '' : 'Pick a company first',
          child: IgnorePointer(
            ignoring: !hasCompany,
            child: Opacity(
              opacity: hasCompany ? 1 : 0.45,
              child: _peopleList(hasCompany),
            ),
          ),
        ),
      ],
    );
  }

  // --- the deal --------------------------------------------------------------

  Widget _dealRow() {
    final partyColumn = _column(_deal, SheetBindsTo.developedForParty);
    final quotationColumn = _column(_deal, SheetBindsTo.developedForQuotation);
    final partyId = widget.controller.dealPartyId;
    final quotation = _field('deal:quotation', _text(_deal, SheetBindsTo.developedForQuotation));

    // Before the part exists everything is open; after, a chosen deal is
    // closed until its Edit.
    final dealLocked = widget.partSaved && !_dealEditing && partyId != null;

    final date = _text(_deal, SheetBindsTo.createdDate);
    final time = _text(_deal, SheetBindsTo.createdTime);
    final recorded = date.isEmpty || date == 'Set on save'
        ? 'Set on save'
        : '$date · $time';

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        // The company's logo, kept on the company: every part for it shows
        // the same one.
        MiniPhoto(
          owner: PhotoOwner.client,
          id: partyId?.toString(),
          size: 44,
          what: 'company logo',
          disabledReason: 'Pick the company first to add its logo',
        ),
        FitToText(
          texts: ['Company', widget.controller.dealPartyName],
          minWidth: 260,
          chrome: 72,
          child: SearchableSelectField<int>(
            key: const ValueKey<String>('deal_company'),
            tapTargetKey: const ValueKey<String>('deal_company_tap'),
            value: partyId,
            fieldEnabled: !dealLocked,
            dialogTitle: 'Company',
            searchHintText: 'Search companies',
            options: [
              for (final party in _deal.parties)
                SearchableSelectOption<int>(value: party.id, label: party.name),
            ],
            decoration: const InputDecoration(
              labelText: 'Company',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            // A part for a new customer should not need a trip to the
            // Clients screen. A name the master already has is that company.
            canCreateOption: (query, _) {
              final wanted = query.trim().toLowerCase();
              return wanted.isNotEmpty &&
                  !_deal.parties.any((p) => p.name.trim().toLowerCase() == wanted);
            },
            createOptionLabelBuilder: (query) => 'Add company “${query.trim()}”',
            onCreateOption: (query) async {
              final party = await widget.controller.addParty(query);
              if (party == null) return null;
              _created = party;
              return SearchableSelectOption<int>(value: party.id, label: party.name);
            },
            onChanged: (id) {
              if (partyColumn == null) return;
              final party = _deal.parties.where((p) => p.id == id).firstOrNull ??
                  (_created?.id == id ? _created : null);
              _deal.updateValue(
                partyColumn,
                party == null
                    ? CellValue(columnId: partyColumn)
                    : CellValue(
                        columnId: partyColumn,
                        refId: party.id,
                        optionLabel: party.name,
                      ),
              );
            },
          ),
        ),
        FitToText(
          controller: quotation,
          texts: const ['Quotation (₹)'],
          minWidth: 170,
          child: TextField(
            key: const ValueKey<String>('deal_quotation'),
            controller: quotation,
            focusNode: _focus['deal:quotation'],
            readOnly: dealLocked,
            // Paise allowed, letters not — "12.50" is a quotation, and the
            // sheet used to keep only its digits and store ₹1250.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,₹ ]')),
            ],
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Quotation (₹)',
              helperText: 'One figure for the part',
              errorText: quotationColumn == null
                  ? null
                  : _deal.errors[quotationColumn]?.message,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (text) {
              if (quotationColumn != null) {
                _deal.updateTextValue(quotationColumn, text);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock_outlined,
                  size: 18, color: SoftErpTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Recorded: $recorded',
                style: const TextStyle(
                  fontSize: 14,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _dealAction(dealLocked),
        ),
      ],
    );
  }

  /// The deal line's own Save, or its Edit once saved.
  Widget _dealAction(bool locked) {
    if (!widget.partSaved) {
      return const Tooltip(
        message: 'The deal is saved with the part — save the part row first',
        child: FilledButton(
          onPressed: null,
          child: Text('Saved with the part', style: TextStyle(fontSize: 14)),
        ),
      );
    }
    if (locked) {
      return OutlinedButton.icon(
        key: const ValueKey<String>('deal_edit'),
        onPressed: () => setState(() => _dealEditing = true),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit', style: TextStyle(fontSize: 14)),
      );
    }
    return FilledButton.icon(
      key: const ValueKey<String>('deal_save'),
      onPressed: _savingDeal ||
              widget.onSaveDeal == null ||
              widget.controller.isSavingNow
          ? null
          : () async {
              setState(() => _savingDeal = true);
              final ok = await widget.onSaveDeal!();
              if (!mounted) return;
              setState(() {
                _savingDeal = false;
                if (ok) _dealEditing = false;
              });
            },
      icon: const Icon(Icons.save_outlined, size: 18),
      label: const Text('Save', style: TextStyle(fontSize: 14)),
    );
  }

  // --- the people ------------------------------------------------------------

  Widget _peopleList(bool hasCompany) {
    final company = widget.controller.dealPartyName;
    final rows = _people.rowCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasCompany ? 'People at $company' : 'People',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Everyone you deal with there. Tick whoever this part’s deal was done with.',
          style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
        ),
        const SizedBox(height: 10),
        for (var row = 0; row < rows; row += 1) ...[
          _personRow(row),
          const SizedBox(height: 10),
        ],
        TextButton.icon(
          key: const ValueKey<String>('deal_add_person'),
          onPressed: () => _people.addRow(),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('Add person', style: TextStyle(fontSize: 14)),
        ),
      ],
    );
  }

  Widget _personRow(int row) {
    final draft = _people.draftAt(row);
    final saved = draft.entityId != null;
    final errors = _people.errorsForRow(row);
    final tickColumn = _column(_people, SheetBindsTo.personDealtWith);
    final ticked = tickColumn != null && draft.get(tickColumn)?.intValue == 1;
    // The person's details are the company's record: closed once saved, opened
    // with the row's Edit. The tick belongs to the DEAL, so it follows the
    // deal line's lock, not the person's.
    final locked = _people.isRowLocked(row);
    final dealLocked =
        widget.partSaved && !_dealEditing && widget.controller.dealPartyId != null;
    final blank = _people.isRowBlank(row);

    Widget field(
      String binds,
      String label, {
      TextInputType? keyboard,
      double min = 150,
      List<String>? options,
    }) {
      final column = _column(_people, binds);
      final key = 'person:$row:$binds';
      final text = _field(key, _text(_people, binds, row: row));
      if (options != null) {
        // A dropdown of what was said before. It writes through the same
        // draft the text field does, so saving is unchanged.
        return FitToText(
          controller: text,
          texts: [label, ...options.take(8)],
          minWidth: min,
          chrome: 72,
          child: PickOrTypeField(
            fieldKey: ValueKey<String>('deal_person_${row}_$binds'),
            controller: text,
            label: label,
            options: options,
            enabled: !locked,
            errorText: column == null ? null : errors[column]?.message,
            onChanged: () {
              if (column != null) {
                _people.updateTextValue(column, text.text, row: row);
              }
            },
          ),
        );
      }
      return FitToText(
        controller: text,
        texts: [label],
        minWidth: min,
        child: TextField(
          key: ValueKey<String>('deal_person_${row}_$binds'),
          controller: text,
          focusNode: _focus[key],
          readOnly: locked,
          keyboardType: keyboard,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            errorText: column == null ? null : errors[column]?.message,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            if (column != null) _people.updateTextValue(column, value, row: row);
          },
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MiniPhoto(
          owner: PhotoOwner.person,
          id: _people.draftAt(row).entityId?.toString(),
          size: 40,
          what: 'photo',
          disabledReason: 'Save this person first to add a photo',
        ),
        Tooltip(
          message: 'Dealt with on this part',
          child: Checkbox(
            key: ValueKey<String>('deal_person_${row}_tick'),
            value: ticked,
            onChanged: tickColumn == null || dealLocked
                ? null
                : (value) => _people.updateValue(
                      tickColumn,
                      value == true
                          ? CellValue(columnId: tickColumn, intValue: 1)
                          : CellValue(columnId: tickColumn),
                      row: row,
                    ),
          ),
        ),
        field(SheetBindsTo.personName, 'Name', min: 180),
        field(
          SheetBindsTo.personDesignation,
          'Designation',
          min: 170,
          options: _designations(),
        ),
        field(SheetBindsTo.personPhone, 'Contact No', keyboard: TextInputType.phone),
        field(SheetBindsTo.personEmail, 'Email ID',
            keyboard: TextInputType.emailAddress, min: 200),
        if (locked)
          OutlinedButton.icon(
            key: ValueKey<String>('deal_person_${row}_edit'),
            onPressed: () => _people.setRowLocked(row, false),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit', style: TextStyle(fontSize: 14)),
          )
        else
          FilledButton.icon(
            key: ValueKey<String>('deal_person_${row}_save'),
            // Off while that person is saving: a second click added them twice.
            onPressed: blank || widget.controller.isSavingPerson(row)
                ? null
                : () => widget.controller.savePersonRow(row),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save', style: TextStyle(fontSize: 14)),
          ),
        Tooltip(
          message: saved
              ? 'Saved people stay on the company’s file — untick instead'
              : 'Remove this row',
          child: IconButton(
            key: ValueKey<String>('deal_person_${row}_remove'),
            onPressed: saved || _people.rowCount <= 1
                ? null
                : () => _people.removeRow(row),
            icon: const Icon(Icons.close, size: 18),
          ),
        ),
      ],
    );
  }
}
