import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/utils/stamp_format.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../clients/domain/client_definition.dart';
import '../../../clients/domain/sub_contractor_definition.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../clients/presentation/providers/sub_contractors_provider.dart';
import '../../../clients/presentation/screens/clients_screen.dart';
import '../../domain/developed_for.dart';

/// The Developed For block, as one form shared by every surface that shows it.
///
/// Three places edit this — the catalogue wizard, the item editor and (read
/// only) the item detail panel — and they have to agree, because the thing
/// being edited is one row on one part. The alternative is the state the part
/// code was in before it was extracted: the same rule written out three times
/// and true in two of them.
///
/// It owns no part of the value. [value] in, [onChanged] out, so the host
/// decides whether a change is a staged edit or an immediate write.
class DevelopedForForm extends StatefulWidget {
  const DevelopedForForm({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.quotationLabel = 'Quotation',
    this.quotationHelper = 'Optional. What was quoted for this part',
  });

  final DevelopedFor value;
  final ValueChanged<DevelopedFor> onChanged;
  final bool enabled;

  /// The wizard calls this "Quotation for this part", because three ticks of
  /// the same form record the same figure three times, once per part.
  final String quotationLabel;
  final String quotationHelper;

  @override
  State<DevelopedForForm> createState() => _DevelopedForFormState();
}

class _DevelopedForFormState extends State<DevelopedForForm> {
  late final TextEditingController _quotationController;

  /// The contractors provider, or null where the host has not registered one.
  ///
  /// Not every screen that embeds this form sits under the whole app's
  /// provider tree — several tests pump the item editor with only the
  /// providers that editor used to need, and a hard `read` turned those into
  /// ProviderNotFoundError before this form had drawn anything. Degrading to
  /// "no contractors to pick from" is the right failure: Self and Client still
  /// work, and the real app registers it in main.dart.
  SubContractorsProvider? get _contractors {
    try {
      return context.read<SubContractorsProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  List<SubContractorDefinition> get _contractorOptions =>
      _contractors?.allSubContractors ?? const <SubContractorDefinition>[];

  /// Clients, with the same tolerance for a host that has not registered them.
  List<ClientDefinition> get _clientOptions {
    try {
      return context.read<ClientsProvider>().clients;
    } on ProviderNotFoundException {
      return const <ClientDefinition>[];
    }
  }

  @override
  void initState() {
    super.initState();
    _quotationController = TextEditingController(
      text: widget.value.quotationAmount == null
          ? ''
          : _plainAmount(widget.value.quotationAmount!),
    );
    // Contractors are picked from a list this provider may never have loaded —
    // the clients screen is the only other thing that loads it. Deferred by a
    // frame because the host is mid-build when this is first laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = _contractors;
      if (provider != null && provider.allSubContractors.isEmpty) {
        provider.loadAll();
      }
    });
  }

  @override
  void didUpdateWidget(DevelopedForForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seeded only when the incoming figure is genuinely different from what
    // is in the field. Writing the text back on every rebuild would move the
    // caret to the end while someone was typing in the middle of it.
    final incoming = widget.value.quotationAmount;
    final current = parseRupees(_quotationController.text);
    if (incoming != current) {
      _quotationController.text = incoming == null ? '' : _plainAmount(incoming);
    }
  }

  @override
  void dispose() {
    _quotationController.dispose();
    super.dispose();
  }

  /// `85000` or `4200.5` — what belongs in an input, as against the `₹85,000/-`
  /// that belongs in a label.
  static String _plainAmount(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  void _emit(DevelopedFor next) => widget.onChanged(next);

  // --- picking a party -------------------------------------------------------

  Future<void> _pickClient() async {
    final clients = _clientOptions
        .where((client) => !client.isArchived)
        .toList(growable: false);

    final selected = await showSearchableSelectDialog<int>(
      context: context,
      title: 'Developed for which client?',
      searchHintText: 'Search clients',
      options: clients
          .map(
            (client) => SearchableSelectOption<int>(
              value: client.id,
              label: client.displayLabel,
              searchText: '${client.name} ${client.alias} ${client.gstNumber}',
            ),
          )
          .toList(growable: false),
      selectedValue: widget.value.clientId,
      // Inline create, the die_form_screen way: a part is being named right
      // now and the client it was made for may not be in the master yet.
      canCreateOption: (query, options) => query.trim().isNotEmpty,
      createOptionLabelBuilder: (query) => 'Add client "$query"',
      onCreateOption: (query) async {
        final created = await ClientsScreen.openEditor(
          context,
          initialName: query.trim(),
        );
        if (created == null) return null;
        // The picker's own list was built before this existed, so the created
        // row is handed straight back as the selection.
        return SearchableSelectOption<int>(
          value: created.id,
          label: created.displayLabel,
        );
      },
    );
    if (selected == null || !mounted) return;

    final client = _clientOptions
        .where((entry) => entry.id == selected.value)
        .firstOrNull;
    _emit(_withClient(widget.value, selected.value, client));
  }

  Future<void> _pickContractor() async {
    final clients = _clientOptions;
    final contractors = _contractorOptions;

    String companyOf(SubContractorDefinition entry) =>
        entry.clientName ??
        clients
            .where((client) => client.id == entry.clientId)
            .map((client) => client.name)
            .firstOrNull ??
        '';

    final selected = await showSearchableSelectDialog<int>(
      context: context,
      title: 'Developed for which contractor?',
      searchHintText: 'Search contractors',
      options: contractors
          .map(
            (entry) => SearchableSelectOption<int>(
              value: entry.id,
              // The company is in the label, not only the search text: two
              // contractors can share a first name and the part belongs to
              // whichever company is behind them.
              label: companyOf(entry).isEmpty
                  ? entry.name
                  : '${entry.name} · ${companyOf(entry)}',
              searchText:
                  '${entry.name} ${companyOf(entry)} ${entry.designation} ${entry.phone}',
            ),
          )
          .toList(growable: false),
      selectedValue: widget.value.subContractorId,
      canCreateOption: (query, options) => query.trim().isNotEmpty,
      createOptionLabelBuilder: (query) => 'Add contractor "$query"',
      onCreateOption: (query) async {
        final created = await ClientsScreen.openSubContractorEditor(
          context,
          initialClientId: widget.value.clientId,
          initialName: query.trim(),
        );
        if (created == null) return null;
        return SearchableSelectOption<int>(value: created.id, label: created.name);
      },
    );
    if (selected == null || !mounted) return;

    final contractor = _contractorOptions
        .where((entry) => entry.id == selected.value)
        .firstOrNull;
    if (contractor == null) {
      // Created and not yet in any cache. The ids are what the save needs; the
      // person comes back resolved on the next read.
      _emit(
        widget.value.copyWith(
          kind: DevelopedForKind.contractor,
          subContractorId: selected.value,
          subContractorName: selected.label,
          contactName: selected.label,
        ),
      );
      return;
    }
    _emit(_withContractor(widget.value, contractor, companyOf(contractor)));
  }

  /// The person as the client record has them. Filled in locally so the form
  /// shows what it is about to save; the server resolves the same fields on
  /// every read, and they are not sent back.
  static DevelopedFor _withClient(
    DevelopedFor value,
    int clientId,
    ClientDefinition? client,
  ) {
    return value.copyWith(
      kind: DevelopedForKind.client,
      clientId: clientId,
      clientName: client?.name ?? '',
      clearSubContractorId: true,
      subContractorName: '',
      companyName: client?.name ?? '',
      contactName: client?.contactName ?? '',
      designation: client?.designation ?? '',
      phone: client?.phone ?? '',
      email: client?.email ?? '',
    );
  }

  static DevelopedFor _withContractor(
    DevelopedFor value,
    SubContractorDefinition contractor,
    String companyName,
  ) {
    return value.copyWith(
      kind: DevelopedForKind.contractor,
      // The parent client rides along: it is the company the part belongs to,
      // and the backend derives it anyway.
      clientId: contractor.clientId,
      clientName: companyName,
      subContractorId: contractor.id,
      subContractorName: contractor.name,
      companyName: companyName,
      // For a contractor the party IS the person you deal with.
      contactName: contractor.name,
      designation: contractor.designation,
      phone: contractor.phone,
      email: contractor.email,
    );
  }

  // --- when ------------------------------------------------------------------

  Future<void> _pickDate() async {
    final current = widget.value.at?.toLocal() ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(current.year + 10),
    );
    if (picked == null) return;
    _emit(
      widget.value.copyWith(
        at: DateTime(
          picked.year,
          picked.month,
          picked.day,
          current.hour,
          current.minute,
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final current = widget.value.at?.toLocal() ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    _emit(
      widget.value.copyWith(
        at: DateTime(
          current.year,
          current.month,
          current.day,
          picked.hour,
          picked.minute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final enabled = widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kindSelector(value, enabled),
        if (value.kind == DevelopedForKind.client ||
            value.kind == DevelopedForKind.contractor) ...[
          const SizedBox(height: 14),
          _partyRow(value, enabled),
          if (value.isNotEmpty && !value.needsParty) ...[
            const SizedBox(height: 12),
            _personCard(value, enabled),
          ],
        ],
        if (value.kind != DevelopedForKind.none) ...[
          const SizedBox(height: 14),
          _whenRow(value, enabled),
          const SizedBox(height: 12),
          _quotationField(enabled),
        ],
      ],
    );
  }

  Widget _kindSelector(DevelopedFor value, bool enabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'For',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in const [
              DevelopedForKind.self,
              DevelopedForKind.client,
              DevelopedForKind.contractor,
            ])
              ChoiceChip(
                label: Text(
                  kind == DevelopedForKind.self ? 'Self' : kind.label,
                  style: const TextStyle(fontSize: 13.5),
                ),
                selected: value.kind == kind,
                onSelected: !enabled
                    ? null
                    : (selected) {
                        // Tapping the selected chip again clears the whole
                        // answer, which is the only way back to "nobody has
                        // said" once something has been picked.
                        _emit(
                          value.withKind(
                            selected ? kind : DevelopedForKind.none,
                          ),
                        );
                      },
              ),
            if (value.kind != DevelopedForKind.none && enabled)
              TextButton.icon(
                onPressed: () => _emit(
                  DevelopedFor(at: value.at, quotationAmount: value.quotationAmount)
                      .withKind(DevelopedForKind.none),
                ),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Clear', style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
        if (value.kind == DevelopedForKind.self)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Developed in-house. No client or contractor is recorded.',
              style: TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _partyRow(DevelopedFor value, bool enabled) {
    final isContractor = value.kind == DevelopedForKind.contractor;
    final picked = isContractor
        ? value.subContractorName
        : (value.companyName.isNotEmpty ? value.companyName : value.clientName);
    final label = isContractor ? 'Contractor' : 'Company';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            picked.isEmpty ? 'Nobody picked yet' : picked,
            style: TextStyle(
              fontSize: 15,
              fontWeight: picked.isEmpty ? FontWeight.w400 : FontWeight.w700,
              color: picked.isEmpty
                  ? SoftErpTheme.textSecondary
                  : SoftErpTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: picked.isEmpty ? 'Pick' : 'Change',
          icon: Icons.person_search_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: !enabled
              ? null
              : (isContractor ? _pickContractor : _pickClient),
        ),
      ],
    );
  }

  Widget _personCard(DevelopedFor value, bool enabled) {
    final rows = <(String, String)>[
      if (value.kind == DevelopedForKind.contractor)
        ('Company', value.companyName),
      ('Client Name', value.contactName),
      ('Designation', value.designation),
      ('Contact No.', value.phone),
      ('Email ID', value.email),
    ].where((row) => row.$2.isNotEmpty).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty)
            const Text(
              'No contact is recorded against them yet.',
              style: TextStyle(fontSize: 13.5, color: SoftErpTheme.textSecondary),
            )
          else
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        row.$1,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SoftErpTheme.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: SoftErpTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Read from their record, so one correction there fixes every '
                  'part developed for them.',
                  style: TextStyle(fontSize: 12.5, color: SoftErpTheme.textSecondary),
                ),
              ),
              if (enabled)
                TextButton.icon(
                  onPressed: () => _editParty(value),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(
                    value.kind == DevelopedForKind.contractor
                        ? 'Edit contractor'
                        : 'Edit client',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editParty(DevelopedFor value) async {
    if (value.kind == DevelopedForKind.contractor) {
      final contractor = _contractorOptions
          .where((entry) => entry.id == value.subContractorId)
          .firstOrNull;
      if (contractor == null) return;
      final saved = await ClientsScreen.openSubContractorEditor(
        context,
        subContractor: contractor,
      );
      if (saved == null || !mounted) return;
      _emit(_withContractor(value, saved, value.companyName));
      return;
    }

    final client = _clientOptions
        .where((entry) => entry.id == value.clientId)
        .firstOrNull;
    if (client == null) return;
    final saved = await ClientsScreen.openEditor(context, client: client);
    if (saved == null || !mounted) return;
    _emit(_withClient(value, saved.id, saved));
  }

  Widget _whenRow(DevelopedFor value, bool enabled) {
    final at = value.at;
    return Row(
      children: [
        const SizedBox(
          width: 110,
          child: Text(
            'Date & Time',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? _pickDate : null,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  at == null ? 'Pick a date' : partStampDate(at),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              OutlinedButton.icon(
                onPressed: enabled ? _pickTime : null,
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: Text(
                  at == null ? 'Pick a time' : partStampTime(at),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (enabled)
                TextButton(
                  onPressed: () =>
                      _emit(value.copyWith(at: DateTime.now())),
                  child: const Text('Now', style: TextStyle(fontSize: 13)),
                ),
              if (enabled && at != null)
                TextButton(
                  onPressed: () => _emit(value.copyWith(clearAt: true)),
                  child: const Text('Clear', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quotationField(bool enabled) {
    return TextFormField(
      controller: _quotationController,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: widget.quotationLabel,
        helperText: widget.quotationHelper,
        prefixText: '₹ ',
        border: const OutlineInputBorder(),
      ),
      validator: (raw) {
        final text = (raw ?? '').trim();
        if (text.isEmpty) return null;
        return parseRupees(text) == null ? 'Not an amount' : null;
      },
      onChanged: (raw) {
        final parsed = parseRupees(raw);
        // An empty field is "never quoted" and clears the figure; junk is left
        // for the validator to refuse rather than silently read as nothing.
        if (raw.trim().isEmpty) {
          _emit(widget.value.copyWith(clearQuotationAmount: true));
          return;
        }
        if (parsed == null) return;
        _emit(widget.value.copyWith(quotationAmount: parsed));
      },
    );
  }
}

/// The same block, to read rather than to fill in. One line per fact, in the
/// order the sketch had them.
class DevelopedForSummary extends StatelessWidget {
  const DevelopedForSummary({super.key, required this.value});

  final DevelopedFor value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return const Text(
        'Nobody has recorded who this part was developed for.',
        style: TextStyle(fontSize: 13.5, color: SoftErpTheme.textSecondary),
      );
    }

    final rows = <(String, String)>[
      ('For', value.kind.label),
      if (value.kind == DevelopedForKind.contractor)
        ('Contractor', value.subContractorName),
      ('Company Name', value.companyName),
      ('Client Name', value.contactName),
      ('Designation', value.designation),
      if (value.at != null) ('Date', partStampDate(value.at!)),
      if (value.at != null) ('Time', partStampTime(value.at!)),
      if (value.quotationAmount != null)
        ('Quotation', rupeeStamp(value.quotationAmount!)),
      ('Contact No.', value.phone),
      ('Email ID', value.email),
    ].where((row) => row.$2.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    row.$1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: SoftErpTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
