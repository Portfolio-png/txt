import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/services/entity_photos.dart';
import '../../../../core/utils/stamp_format.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/company_documents_box.dart';
import '../../../../core/widgets/fit_to_text.dart';
import '../../../../core/widgets/mini_photo.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../clients/presentation/widgets/company_view_dialog.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/pick_or_type_field.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../sheet/column_option.dart';
import '../../../clients/presentation/widgets/designation_field.dart'
    show kDesignationSuggestions;
import '../../../../sheet/item_master_controller.dart';
import '../../../../sheet/sheet_binding.dart';
import '../../../../sheet/sheet_controller.dart';
import '../../../../sheet/sheet_draft.dart';
import '../../../../sheet/sheet_style.dart';

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
    this.recordedAt,
  });

  final ItemMasterController controller;

  /// Whether the part exists yet. Before it does, the deal is saved with the
  /// part row; after, the deal line has its own Save and Edit.
  final bool partSaved;

  /// Writes the deal (company, quotation, ticks) on the saved part. True when
  /// it landed.
  final Future<bool> Function()? onSaveDeal;

  /// When the saved part's deal was recorded, or null when it has not been.
  final DateTime? recordedAt;

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
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, _deal]),
      builder: (context, _) {
        final hasCompany = widget.controller.dealPartyId != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dealRow(),
            const SizedBox(height: 14),
            // The company's own papers — kept on the company, so every part for
            // it shows the same ones, and its view lists them too.
            CompanyDocumentsBox(
              owner: PhotoOwner.client,
              id: widget.controller.dealPartyId?.toString(),
              compact: true,
              disabledReason: 'Pick the company first to keep its documents',
              note: widget.controller.dealPartyName.trim().isEmpty
                  ? null
                  : 'for ${widget.controller.dealPartyName.trim()}',
            ),
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
      },
    );
  }

  // --- the deal --------------------------------------------------------------

  String? _companyLogo(int? partyId) {
    if (partyId == null) return null;
    try {
      final clients = Provider.of<ClientsProvider>(context, listen: false);
      for (final client in clients.clients) {
        if (client.id == partyId) return client.logoUrl;
      }
    } on ProviderNotFoundException {
      return null;
    }
    return null;
  }

  Widget _dealRow() {
    final partyColumn = _column(_deal, SheetBindsTo.developedForParty);
    final quotationColumn = _column(_deal, SheetBindsTo.developedForQuotation);
    final partyId = widget.controller.dealPartyId;
    final quotation = _field('deal:quotation', _text(_deal, SheetBindsTo.developedForQuotation));

    // Before the part exists everything is open; after, a chosen deal is
    // closed until its Edit.
    final dealLocked = widget.partSaved && !_dealEditing && partyId != null;

    // The stamp the saved part carries. The deal row's own date cells were
    // filled only by the old whole-sheet save, so a saved deal read "Set on
    // save" for good.
    final at = widget.recordedAt;
    final recorded = at == null ? 'Set on save' : partStamp(at);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        // The company's logo, kept on the company: every part for it shows
        // the same one.
        // Level with the boxes, which sit under their headings.
        Padding(
          padding: const EdgeInsets.only(top: _boxTop),
          child: MiniPhoto(
          owner: PhotoOwner.client,
          id: partyId?.toString(),
          size: 40,
          what: 'company logo',
          // The logo set on the Clients screen, until one is uploaded here.
          fallbackUrl: _companyLogo(partyId),
          disabledReason: 'Pick the company first to add its logo',
        ),
        ),
        SheetStyle.labelled(
          label: 'Company',
          child: FitToText(
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
            decoration: SheetStyle.field(),
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
        ),
        SheetStyle.labelled(
          label: 'Quotation (₹)',
          child: FitToText(
          controller: quotation,
          texts: const ['Quotation (₹)', 'One figure for the part'],
          helper: 'One figure for the part',
          minWidth: 195,
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
            decoration: SheetStyle.field(
              helper: 'One figure for the part',
              error: quotationColumn == null
                  ? null
                  : _deal.errors[quotationColumn]?.message,
            ),
            onChanged: (text) {
              if (quotationColumn != null) {
                _deal.updateTextValue(quotationColumn, text);
              }
            },
          ),
        ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: _boxTop + 10),
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
          padding: const EdgeInsets.only(top: _boxTop + 2),
          child: _dealAction(dealLocked),
        ),
        if (partyId != null)
          Padding(
            padding: const EdgeInsets.only(top: _boxTop + 2),
            child: TextButton.icon(
              key: const ValueKey<String>('deal_view_company'),
              onPressed: () => CompanyView.openClient(context, partyId),
              icon: const Icon(Icons.business_outlined, size: 18),
              label: const Text(
                'View company',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  /// The deal line's own Save, or its Edit once saved.
  Widget _dealAction(bool locked) {
    // The same Edit and Save a person's line has, so the page's Saves look
    // alike.
    if (locked) {
      return OutlinedButton.icon(
        key: const ValueKey<String>('deal_edit'),
        onPressed: () => setState(() => _dealEditing = true),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit', style: TextStyle(fontSize: 14)),
      );
    }

    // Enabled only when the save would land: a company, a valid quotation,
    // and a part row with every required cell filled. The row's REAL errors,
    // not the drawn ones — an untouched empty Group is not drawn red yet, and
    // read from those this enabled a Save that then failed.
    final sheet = widget.controller.groupItemController;
    final partyId = widget.controller.dealPartyId;
    final quotationCol = _column(_deal, SheetBindsTo.developedForQuotation);
    final quotationError =
        quotationCol == null ? null : _deal.errors[quotationCol];
    final activeRow = widget.controller.dealRow ?? sheet.row;
    final partBlank = sheet.isRowBlank(activeRow);
    final partErrors = sheet.errorsForRow(activeRow);
    final isSaving = _savingDeal || widget.controller.isSavingNow;

    final String? why;
    if (partyId == null) {
      why = 'Pick a company first';
    } else if (partBlank) {
      why = 'Type the part name first';
    } else if (partErrors.isNotEmpty) {
      why = partErrors.values.first.message;
    } else if (quotationError != null) {
      why = quotationError.message;
    } else if (isSaving) {
      why = 'Saving…';
    } else if (widget.onSaveDeal == null) {
      why = 'Save the part from its row';
    } else {
      why = null;
    }
    final canSave = why == null;
    final tooltipMessage =
        why ?? 'Saves the part with its company details (Ctrl+S)';

    return Tooltip(
      message: tooltipMessage,
      child: AppButton(
        key: const ValueKey<String>('deal_save'),
        label: 'Save company',
        icon: Icons.save_outlined,
        variant: AppButtonVariant.secondary,
        dense: true,
        isLoading: isSaving,
        onPressed: canSave
            ? () async {
                setState(() => _savingDeal = true);
                final ok = await widget.onSaveDeal!();
                if (!mounted) return;
                setState(() {
                  _savingDeal = false;
                  if (ok) _dealEditing = false;
                });
              }
            : null,
      ),
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
          style: SheetStyle.subHeading,
        ),
        const SizedBox(height: 2),
        const Text(
          'Everyone you deal with there. Tick whoever this part’s deal was done with.',
          style: SheetStyle.hint,
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
        return SheetStyle.labelled(
          label: label,
          child: FitToText(
          controller: text,
          texts: [label, ...options.take(8)],
          minWidth: min,
          chrome: 72,
          child: PickOrTypeField(
            fieldKey: ValueKey<String>('deal_person_${row}_$binds'),
            controller: text,
            label: label,
            floatLabel: false,
            options: options,
            enabled: !locked,
            errorText: column == null ? null : errors[column]?.message,
            decoration: SheetStyle.field(),
            onChanged: () {
              if (column != null) {
                _people.updateTextValue(column, text.text, row: row);
              }
            },
          ),
        ),
        );
      }
      return SheetStyle.labelled(
        label: label,
        child: FitToText(
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
          decoration: SheetStyle.field(
            error: column == null ? null : errors[column]?.message,
          ),
          onChanged: (value) {
            if (column != null) _people.updateTextValue(column, value, row: row);
          },
        ),
      ),
      );
    }

    // Bottoms level: every field has its name above it now, so the photo,
    // the buttons and the × line up with the boxes, not with the headings.
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        MiniPhoto(
          owner: PhotoOwner.person,
          id: _people.draftAt(row).entityId?.toString(),
          size: 40,
          what: 'photo',
          disabledReason: 'Save this person first to add a photo',
        ),
        SheetStyle.labelled(
          label: 'Dealt with',
          child: SizedBox(
          height: 44,
          child: Tooltip(
          message: dealLocked
              ? 'Edit the company line to change who it was dealt with'
              : 'Dealt with on this part',
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
          // Writes the person to the company's file now. The tick is the
          // deal's, so it waits for the part's save.
          Tooltip(
            message: blank
                ? 'Type a name first'
                : 'Saves this person to '
                    '${widget.controller.dealPartyName.trim().isEmpty ? 'the company' : widget.controller.dealPartyName.trim()} '
                    'now. Whether they’re ticked for this part is saved with the part.',
            child: AppButton(
              key: ValueKey<String>('deal_person_${row}_save'),
              label: 'Save contact',
              icon: Icons.save_outlined,
              variant: AppButtonVariant.secondary,
              dense: true,
              // Off while that person is saving: a second click added them twice.
              isLoading: widget.controller.isSavingPerson(row),
              onPressed: blank ? null : () => widget.controller.savePersonRow(row),
            ),
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

/// How far a field's box sits below the top of its heading
/// ([SheetStyle.labelled]): what sits beside a headed field is moved down by
/// it to stay level with the box.
const double _boxTop = 30;
