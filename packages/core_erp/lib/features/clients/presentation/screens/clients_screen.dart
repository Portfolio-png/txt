import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/presentation/widgets/track_panel.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/client_definition.dart';
import '../../domain/client_inputs.dart';
import '../../domain/sub_contractor_definition.dart';
import '../../domain/sub_contractor_inputs.dart';
import '../providers/clients_provider.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../../core/services/generic_asset_service.dart';
import '../../../../core/widgets/export_preview_dialog.dart';
import '../widgets/sub_contractors_sheet.dart';
import '../providers/sub_contractors_provider.dart';

class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientsProvider>(
      builder: (context, clients, _) {
        if (clients.isLoading && clients.clients.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return FocusableActionDetector(
          autofocus: true,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyP, control: true):
                PrintIntent(),
            SingleActivator(LogicalKeyboardKey.keyP, meta: true): PrintIntent(),
          },
          actions: {
            PrintIntent: CallbackAction<PrintIntent>(
              onInvoke: (intent) {
                final data = clients.filteredClients
                    .map(
                      (c) => {
                        'id': c.id,
                        'name': c.name,
                        'alias': c.alias,
                        'gst_number': c.gstNumber,
                        'address': c.address,
                        'status': 'Active',
                      },
                    )
                    .toList();
                ExportPreviewDialog.show(context, title: 'Clients', data: data);
                return null;
              },
            ),
          },
          child: SoftMasterDataPage(
            title: 'Clients',
            subtitle:
                'Manage client master data for sales flows, billing details, and downstream transaction forms.',
            action: AppButton(
              label: clients.viewType == ClientMasterView.subContractors
                  ? 'Add Sub-contractor'
                  : 'Add Client',
              icon: Icons.add,
              isLoading: clients
                  .isSaving, // Or check if SubContractorsProvider is saving if needed
              onPressed: () {
                if (clients.viewType == ClientMasterView.subContractors) {
                  _openSubContractorEditor(context);
                } else {
                  _openClientEditor(context);
                }
              },
            ),
            toolbar: const _ClientsToolbar(),
            messages: [
              if (clients.errorMessage != null)
                _ClientsMessageBanner(
                  message: clients.errorMessage!,
                  isError: true,
                ),
            ],
            body: clients.viewType == ClientMasterView.subContractors
                ? _AllSubContractorsTable(searchQuery: clients.searchQuery)
                : clients.filteredClients.isEmpty
                ? const AppEmptyState(
                    title: 'No clients found',
                    message:
                        'Add your first client to keep names, GST numbers, and addresses consistent across the system.',
                    icon: Icons.groups_outlined,
                  )
                : _ClientsTable(clients: clients.filteredClients),
          ),
        );
      },
    );
  }

  static Future<ClientDefinition?> openEditor(
    BuildContext context, {
    ClientDefinition? client,
    String? initialName,
  }) {
    return showErpFormDialog<ClientDefinition?>(
      context,
      maxWidth: 760,
      maxHeight: 760,
      child: _ClientEditorSheet(client: client, initialName: initialName),
    );
  }

  static Future<ClientDefinition?> _openClientEditor(
    BuildContext context, {
    ClientDefinition? client,
  }) {
    return openEditor(context, client: client);
  }

  static Future<SubContractorDefinition?> _openSubContractorEditor(
    BuildContext context,
  ) {
    return showErpFormDialog<SubContractorDefinition?>(
      context,
      maxWidth: 600,
      maxHeight: 760,
      child: const _SubContractorEditorSheet(),
    );
  }
}

class _ClientsToolbar extends StatelessWidget {
  const _ClientsToolbar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClientsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return SoftMasterToolbar(
      children: [
        if (!isDesktop)
          SoftMasterSearchField(
            hintText: 'Search clients, alias, GST, or address',
            onChanged: provider.setSearchQuery,
          ),
        SoftSegmentedFilter<ClientMasterView>(
          selected: provider.viewType,
          onChanged: (view) {
            provider.setViewType(view);
            if (view == ClientMasterView.subContractors) {
              context.read<SubContractorsProvider>().loadAll();
            }
          },
          options: const [
            SoftSegmentOption<ClientMasterView>(
              value: ClientMasterView.clients,
              label: 'Clients',
            ),
            SoftSegmentOption<ClientMasterView>(
              value: ClientMasterView.subContractors,
              label: 'Sub-contractors',
            ),
          ],
        ),
      ],
    );
  }
}

class _ClientsTable extends StatelessWidget {
  const _ClientsTable({required this.clients});

  final List<ClientDefinition> clients;

  @override
  Widget build(BuildContext context) {
    return SoftMasterTable(
      minWidth: 1080,
      columns: const [
        SoftTableColumn('Name', flex: 2),
        SoftTableColumn('Alias', flex: 2),
        SoftTableColumn('GST No.', flex: 2),
        SoftTableColumn('Address', flex: 3),
        SoftTableColumn('Status', flex: 1),
        SoftTableColumn('Actions', flex: 2),
      ],
      itemCount: clients.length,
      rowBuilder: (context, index) => _ClientRow(client: clients[index]),
    );
  }
}

class _AllSubContractorsTable extends StatelessWidget {
  const _AllSubContractorsTable({required this.searchQuery});

  /// Passed in (rather than read from the provider) so this subtree rebuilds
  /// when the search text changes — a const, param-less widget would not.
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final subContractors = context
        .watch<SubContractorsProvider>()
        .filteredSubContractors(searchQuery);

    return SoftMasterTable(
      minWidth: 900,
      columns: const [
        SoftTableColumn('Name', flex: 2),
        SoftTableColumn('Client', flex: 2),
        SoftTableColumn('Phone', flex: 2),
        SoftTableColumn('Email', flex: 2),
      ],
      itemCount: subContractors.length,
      rowBuilder: (context, index) {
        final sub = subContractors[index];
        return SoftMasterRow(
          children: [
            Expanded(
              flex: 2,
              child: SoftInlineText(sub.name, weight: FontWeight.w700),
            ),
            Expanded(flex: 2, child: SoftInlineText(sub.clientName ?? '—')),
            Expanded(
              flex: 2,
              child: SoftInlineText(sub.phone.isEmpty ? '—' : sub.phone),
            ),
            Expanded(
              flex: 2,
              child: SoftInlineText(sub.email.isEmpty ? '—' : sub.email),
            ),
          ],
        );
      },
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client});

  final ClientDefinition client;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClientsProvider>();
    return SoftMasterRow(
      children: [
        Expanded(
          flex: 2,
          child: SoftInlineText(client.name, weight: FontWeight.w700),
        ),
        Expanded(
          flex: 2,
          child: SoftInlineText(client.alias.isEmpty ? '—' : client.alias),
        ),
        Expanded(
          flex: 2,
          child: SoftInlineText(
            client.gstNumber.isEmpty ? '—' : client.gstNumber,
          ),
        ),
        Expanded(
          flex: 3,
          child: SoftInlineText(
            client.address.isEmpty ? '—' : client.address,
            maxLines: 2,
          ),
        ),
        Expanded(
          flex: 1,
          child: SoftStatusPill(
            label: 'Active',
            background: const Color(0xFFECFDF5),
            textColor: const Color(0xFF0F766E),
            borderColor: const Color(0xFFBFEAD8),
          ),
        ),
        Expanded(
          flex: 2,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftActionLink(
                label: 'Purchases',
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => _ClientPurchasesSheet(client: client),
                  );
                },
              ),
              SoftActionLink(
                label: 'Portal Access',
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => _PortalSettingsSheet(client: client),
                  );
                },
              ),
              SoftActionLink(
                label: 'Edit',
                onTap: () => ClientsScreen.openEditor(context, client: client),
              ),
              SoftActionLink(
                label: 'Sub-contractors',
                onTap: () => SubContractorsSheet.show(context, client),
              ),
              SoftActionLink(
                label: 'Delete',
                onTap: provider.isSaving
                    ? null
                    : () async {
                        final ok = await showConfirmDialog(
                          context,
                          title: 'Delete client?',
                          message:
                              'Permanently delete "${client.name}"? You can restore it later from the Action Center.',
                        );
                        if (ok) provider.deleteClient(client.id);
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClientEditorSheet extends StatefulWidget {
  const _ClientEditorSheet({this.client, this.initialName});

  final ClientDefinition? client;
  final String? initialName;

  @override
  State<_ClientEditorSheet> createState() => _ClientEditorSheetState();
}

class _ClientEditorSheetState extends State<_ClientEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _aliasController;
  late final TextEditingController _gstController;
  late final TextEditingController _addressController;
  late final TextEditingController _logoUrlController;
  late final TextEditingController _photoUrlController;

  bool _isSaving = false;

  String? _localError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.client?.name ?? widget.initialName ?? '',
    );
    _aliasController = TextEditingController(text: widget.client?.alias ?? '');
    _gstController = TextEditingController(
      text: widget.client?.gstNumber ?? '',
    );
    _addressController = TextEditingController(
      text: widget.client?.address ?? '',
    );
    _logoUrlController = TextEditingController(
      text: widget.client?.logoUrl ?? '',
    );
    _photoUrlController = TextEditingController(
      text: widget.client?.photoUrl ?? '',
    );
    _nameController.addListener(_handleChange);
    _aliasController.addListener(_handleChange);
    _gstController.addListener(_handleChange);
    _logoUrlController.addListener(_handleChange);
    _photoUrlController.addListener(_handleChange);
  }

  void _handleChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleChange);
    _aliasController.removeListener(_handleChange);
    _gstController.removeListener(_handleChange);
    _logoUrlController.removeListener(_handleChange);
    _photoUrlController.removeListener(_handleChange);
    _nameController.dispose();
    _aliasController.dispose();
    _gstController.dispose();
    _addressController.dispose();
    _logoUrlController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClientsProvider>();
    final title = widget.client == null ? 'Create Client' : 'Edit Client';
    final banner =
        _localError ??
        (provider.isSaving == false ? provider.errorMessage : null);
    return Form(
      key: _formKey,
      child: ErpFormScaffold(
        title: title,
        subtitle:
            'Capture the billing identity your team will reuse across orders and transaction documents.',
        errorBanner: banner == null
            ? null
            : ErpFormMessageBanner(message: banner, isError: true),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ErpDialogSectionCard(
              title: 'Identity',
              subtitle:
                  'Store the core legal and shorthand naming your operators and billing flows reuse.',
              child: Column(
                children: [
                  _ClientTextField(
                    controller: _nameController,
                    label: 'Name',
                    helper: 'Required. Primary client or company name',
                  ),
                  const SizedBox(height: 12),
                  _ClientTextField(
                    controller: _aliasController,
                    label: 'Alias',
                    helper: 'Optional short name for quick recognition',
                    required: false,
                  ),
                  const SizedBox(height: 12),
                  _ClientTextField(
                    controller: _gstController,
                    label: 'GST No.',
                    helper: 'Optional. Must stay unique when provided',
                    required: false,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ErpDialogSectionCard(
              title: 'Photos',
              subtitle:
                  'Optional logo and contact photo for quick visual identification.',
              child: Column(
                children: [
                  _ClientImagePickerField(
                    controller: _logoUrlController,
                    label: 'Logo',
                    hintText: 'Paste logo image URL…',
                    placeholderIcon: Icons.business_rounded,
                  ),
                  const SizedBox(height: 16),
                  _ClientImagePickerField(
                    controller: _photoUrlController,
                    label: 'Client Photo',
                    hintText: 'Paste contact photo URL…',
                    placeholderIcon: Icons.person_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ErpDialogSectionCard(
              title: 'Address & Preview',
              subtitle:
                  'Keep the billing address close to the final record preview so mistakes are visible before save.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ClientTextField(
                    controller: _addressController,
                    label: 'Address',
                    helper: 'Optional billing or primary office address',
                    required: false,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  _ClientPreviewCard(
                    name: _nameController.text.trim(),
                    alias: _aliasController.text.trim(),
                    gstNumber: ClientsProvider.normalizeGstNumber(
                      _gstController.text,
                    ),
                    address: _addressController.text.trim(),
                  ),
                  const SizedBox(height: 12),
                  _ClientWarningText(
                    warning: provider
                        .checkDuplicate(
                          name: _nameController.text,
                          gstNumber: _gstController.text,
                          excludeId: widget.client?.id,
                        )
                        .warning,
                  ),
                ],
              ),
            ),
            if (widget.client != null) ...[
              const SizedBox(height: 16),
              ErpDialogSectionCard(
                title: 'Track',
                child: TrackPanel.entity(
                  entityType: 'clients',
                  entityId: '${widget.client!.id}',
                  showHeader: false,
                ),
              ),
            ],
          ],
        ),
        footer: Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),

            AppButton(
              label: widget.client == null ? 'Create Client' : 'Save Changes',
              isLoading: _isSaving || provider.isSaving,
              onPressed: () => _submit(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final provider = context.read<ClientsProvider>();
    final duplicate = provider.checkDuplicate(
      name: _nameController.text,
      gstNumber: _gstController.text,
      excludeId: widget.client?.id,
    );
    if (duplicate.blockingDuplicate) {
      setState(() {
        _localError = switch (duplicate.warning) {
          ClientDuplicateWarning.nameOnly =>
            'A client with the same name already exists.',
          ClientDuplicateWarning.gstOnly =>
            'A client with the same GST number already exists.',
          ClientDuplicateWarning.nameAndGst =>
            'A client with the same name and GST number already exists.',
          ClientDuplicateWarning.none => null,
        };
      });
      return;
    }

    setState(() {
      _localError = null;
      _isSaving = true;
    });

    try {
      final normalizedGst = ClientsProvider.normalizeGstNumber(
        _gstController.text,
      );
      final result = widget.client == null
          ? await provider.createClient(
              CreateClientInput(
                name: _nameController.text.trim(),
                alias: _aliasController.text.trim(),
                gstNumber: normalizedGst,
                address: _addressController.text.trim(),
                logoUrl: _logoUrlController.text.trim(),
                photoUrl: _photoUrlController.text.trim(),
              ),
            )
          : await provider.updateClient(
              UpdateClientInput(
                id: widget.client!.id,
                name: _nameController.text.trim(),
                alias: _aliasController.text.trim(),
                gstNumber: normalizedGst,
                address: _addressController.text.trim(),
                logoUrl: _logoUrlController.text.trim(),
                photoUrl: _photoUrlController.text.trim(),
              ),
            );

      if (context.mounted && result != null && provider.errorMessage == null) {
        showAppToast(
          context,
          widget.client == null ? 'Client created' : 'Client saved',
          kind: AppToastKind.success,
        );
        Navigator.of(context).pop(result);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _SubContractorEditorSheet extends StatefulWidget {
  const _SubContractorEditorSheet({this.subContractor, this.initialClientId});

  final SubContractorDefinition? subContractor;
  final int? initialClientId;

  @override
  State<_SubContractorEditorSheet> createState() =>
      _SubContractorEditorSheetState();
}

class _SubContractorEditorSheetState extends State<_SubContractorEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _notesController;
  late final TextEditingController _gstController;
  late final TextEditingController _addressController;
  late final TextEditingController _photoUrlController;

  int? _selectedClientId;
  bool _isSaving = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _selectedClientId =
        widget.subContractor?.clientId ?? widget.initialClientId;
    _nameController = TextEditingController(
      text: widget.subContractor?.name ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.subContractor?.phone ?? '',
    );
    _emailController = TextEditingController(
      text: widget.subContractor?.email ?? '',
    );
    _notesController = TextEditingController(
      text: widget.subContractor?.notes ?? '',
    );
    _gstController = TextEditingController(
      text: widget.subContractor?.gstNumber ?? '',
    );
    _addressController = TextEditingController(
      text: widget.subContractor?.address ?? '',
    );
    _photoUrlController = TextEditingController(
      text: widget.subContractor?.photoUrl ?? '',
    );

    _nameController.addListener(_handleChange);
    _gstController.addListener(_handleChange);
    _addressController.addListener(_handleChange);
    _photoUrlController.addListener(_handleChange);
  }

  void _handleChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleChange);
    _gstController.removeListener(_handleChange);
    _addressController.removeListener(_handleChange);
    _photoUrlController.removeListener(_handleChange);
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _gstController.dispose();
    _addressController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clientsProvider = context.watch<ClientsProvider>();
    final subProvider = context.watch<SubContractorsProvider>();
    final title = widget.subContractor == null
        ? 'Add Sub-contractor'
        : 'Edit Sub-contractor';
    final banner =
        _localError ??
        (subProvider.isLoading == false ? subProvider.error : null);

    return Form(
      key: _formKey,
      child: ErpFormScaffold(
        title: title,
        subtitle: 'Capture sub-contractor details for tracking assignments.',
        errorBanner: banner == null
            ? null
            : ErpFormMessageBanner(message: banner, isError: true),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ErpDialogSectionCard(
              title: 'Details',
              subtitle: 'Assign to a client and enter basic info.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    value: _selectedClientId,
                    decoration: const InputDecoration(
                      labelText: 'Client',
                      border: OutlineInputBorder(),
                    ),
                    items: clientsProvider.clients.map((c) {
                      return DropdownMenuItem(value: c.id, child: Text(c.name));
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedClientId = val),
                    validator: (val) =>
                        val == null ? 'Client is required' : null,
                  ),
                  const SizedBox(height: 12),
                  _ClientTextField(
                    controller: _nameController,
                    label: 'Name',
                    helper: 'Required. Sub-contractor name',
                  ),
                  const SizedBox(height: 12),
                  _ClientTextField(
                    controller: _phoneController,
                    label: 'Phone',
                    helper: 'Optional contact number',
                    required: false,
                  ),
                  const SizedBox(height: 12),
                  _ClientTextField(
                    controller: _emailController,
                    label: 'Email',
                    helper: 'Optional contact email',
                    required: false,
                    textCapitalization: TextCapitalization.none,
                  ),
                  const SizedBox(height: 12),
                  _ClientTextField(
                    controller: _notesController,
                    label: 'Notes',
                    helper: 'Optional internal notes',
                    required: false,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _ClientTextField(
                    controller: _gstController,
                    label: 'GST No.',
                    helper: 'Optional. Must stay unique when provided',
                    required: false,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ErpDialogSectionCard(
              title: 'Photos',
              subtitle:
                  'Optional contact photo for quick visual identification.',
              child: Column(
                children: [
                  _ClientImagePickerField(
                    controller: _photoUrlController,
                    label: 'Sub-contractor Photo',
                    hintText: 'Paste contact photo URL…',
                    placeholderIcon: Icons.person_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ErpDialogSectionCard(
              title: 'Address & Preview',
              subtitle: 'Keep the address close to the final record preview.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ClientTextField(
                    controller: _addressController,
                    label: 'Address',
                    helper: 'Optional primary address',
                    required: false,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  _ClientPreviewCard(
                    name: _nameController.text.trim(),
                    alias: '', // Sub-contractors don't have aliases currently
                    gstNumber: ClientsProvider.normalizeGstNumber(
                      _gstController.text,
                    ),
                    address: _addressController.text.trim(),
                  ),
                ],
              ),
            ),
          ],
        ),
        footer: Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context),
            ),
            AppButton(
              label: widget.subContractor == null
                  ? 'Create Sub-contractor'
                  : 'Save Changes',
              isLoading: _isSaving || subProvider.isLoading,
              onPressed: () => _submit(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate() || _selectedClientId == null) return;

    setState(() {
      _localError = null;
      _isSaving = true;
    });

    try {
      final subProvider = context.read<SubContractorsProvider>();
      final result = widget.subContractor == null
          ? await subProvider.create(
              _selectedClientId!,
              CreateSubContractorInput(
                name: _nameController.text.trim(),
                phone: _phoneController.text.trim(),
                email: _emailController.text.trim(),
                notes: _notesController.text.trim(),
                gstNumber: ClientsProvider.normalizeGstNumber(
                  _gstController.text,
                ),
                address: _addressController.text.trim(),
                photoUrl: _photoUrlController.text.trim(),
              ),
            )
          : null; // Update not fully implemented in form yet for global usage

      if (context.mounted && result != null && subProvider.error == null) {
        showAppToast(
          context,
          'Sub-contractor saved',
          kind: AppToastKind.success,
        );
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) setState(() => _localError = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _ClientTextField extends StatelessWidget {
  const _ClientTextField({
    required this.controller,
    required this.label,
    required this.helper,
    this.maxLines = 1,
    this.required = true,
    this.textCapitalization = TextCapitalization.words,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final int maxLines;
  final bool required;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
      ),
      validator: (value) {
        final trimmed = (value ?? '').trim();
        if (required && trimmed.isEmpty) {
          return 'Required';
        }
        if (label == 'GST No.' && trimmed.isNotEmpty && trimmed.length != 15) {
          return 'GST number must be 15 characters';
        }
        return null;
      },
    );
  }
}

class _ClientPreviewCard extends StatelessWidget {
  const _ClientPreviewCard({
    required this.name,
    required this.alias,
    required this.gstNumber,
    required this.address,
  });

  final String name;
  final String alias;
  final String gstNumber;
  final String address;

  @override
  Widget build(BuildContext context) {
    final previewName = name.isEmpty ? 'Client Name' : name;
    final previewAlias = alias.isEmpty ? 'No alias' : alias;
    final previewGst = gstNumber.isEmpty ? 'GST not provided' : gstNumber;
    final previewAddress = address.isEmpty ? 'Address not provided' : address;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            previewName,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('Alias: $previewAlias'),
          const SizedBox(height: 4),
          Text('GST: $previewGst'),
          const SizedBox(height: 4),
          Text(
            previewAddress,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class _ClientWarningText extends StatelessWidget {
  const _ClientWarningText({required this.warning});

  final ClientDuplicateWarning warning;

  @override
  Widget build(BuildContext context) {
    final message = switch (warning) {
      ClientDuplicateWarning.none => null,
      ClientDuplicateWarning.nameOnly =>
        'A client with this name already exists.',
      ClientDuplicateWarning.gstOnly =>
        'A client with this GST number already exists.',
      ClientDuplicateWarning.nameAndGst =>
        'A client with this exact identity already exists.',
    };
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: const Color(0xFFB91C1C),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ClientPurchasesSheet extends StatelessWidget {
  const _ClientPurchasesSheet({required this.client});

  final ClientDefinition client;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrdersProvider>();
    final purchases =
        provider.orders.where((o) => o.clientId == client.id).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 64,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Purchases: ${client.name}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: purchases.isEmpty
                  ? const Center(child: Text('No past purchases found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(24),
                      itemCount: purchases.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final order = purchases[index];
                        return ListTile(
                          title: Text(order.itemName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(order.variationPathLabel),
                              Text(
                                'Order No: ${order.orderNo} • Qty: ${order.quantity} ${order.unitSymbol}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientsMessageBanner extends StatelessWidget {
  const _ClientsMessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return ErpFormMessageBanner(message: message, isError: isError);
  }
}

class _ClientImagePickerField extends StatefulWidget {
  const _ClientImagePickerField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.placeholderIcon,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData placeholderIcon;

  @override
  State<_ClientImagePickerField> createState() =>
      _ClientImagePickerFieldState();
}

class _ClientImagePickerFieldState extends State<_ClientImagePickerField> {
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  String _contentTypeFromExtension(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickAndUploadImage() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
        ),
      ],
    );
    if (file == null || !mounted) {
      return;
    }

    setState(() => _isUploading = true);
    final baseUrl = const String.fromEnvironment(
      'PAPER_API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    );
    final service = GenericAssetService(baseUrl: baseUrl);

    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final contentType =
          file.mimeType ??
          lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
          _contentTypeFromExtension(file.name);

      final intent = await service.createUploadIntent(
        GenericAssetUploadIntentInput(
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
        ),
      );

      if (intent.uploadUrl.host != 'mock.local') {
        final response = await http.put(
          intent.uploadUrl,
          headers: intent.headers,
          body: bytes,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'Image upload failed with status ${response.statusCode}.',
          );
        }
      }

      if (intent.readUrl == null) {
        throw Exception('Failed to get read URL from intent.');
      }

      widget.controller.text = intent.readUrl!;
      showAppSnack(
        const SnackBar(content: Text('Image uploaded successfully.')),
      );
    } catch (error) {
      showAppSnack(SnackBar(content: Text('Image upload failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image preview
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE1F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: url.isNotEmpty
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, e) => Icon(
                        widget.placeholderIcon,
                        size: 36,
                        color: const Color(0xFFCBD5E1),
                      ),
                    )
                  : Icon(
                      widget.placeholderIcon,
                      size: 36,
                      color: const Color(0xFFCBD5E1),
                    ),
            ),
            const SizedBox(width: 12),
            // URL Input and Upload button
            Expanded(
              child: TextFormField(
                controller: widget.controller,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  helperText: 'Paste an image URL to preview',
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
                  ),
                  suffixIcon: url.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => widget.controller.clear(),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: 'Upload',
              icon: Icons.upload_file,
              variant: AppButtonVariant.secondary,
              isLoading: _isUploading,
              onPressed: _pickAndUploadImage,
            ),
          ],
        ),
      ],
    );
  }
}

class _PortalSettingsSheet extends StatefulWidget {
  const _PortalSettingsSheet({required this.client});
  final ClientDefinition client;
  @override
  State<_PortalSettingsSheet> createState() => _PortalSettingsSheetState();
}

class _PortalSettingsSheetState extends State<_PortalSettingsSheet> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  Set<int> _selectedItemIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      await context.read<ItemsProvider>().initialize();
      final itemIds = await context.read<ClientsProvider>().getPortalCatalog(
        widget.client.id,
      );
      if (mounted) {
        setState(() {
          _selectedItemIds = itemIds.toSet();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _save() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      showAppToast(
        context,
        'Email and password required',
        kind: AppToastKind.error,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final clientsProvider = context.read<ClientsProvider>();
      await clientsProvider.updatePortalCredentials(
        widget.client.id,
        email,
        password,
      );
      await clientsProvider.updatePortalCatalog(
        widget.client.id,
        _selectedItemIds.toList(),
      );
      if (mounted) {
        showAppToast(
          context,
          'Portal settings saved',
          kind: AppToastKind.success,
        );
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          'Error saving settings: $e',
          kind: AppToastKind.error,
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final itemsProvider = context.watch<ItemsProvider>();
    final activeItems = itemsProvider.items
        .where((i) => !i.isArchived)
        .toList();

    return ErpFormScaffold(
      title: 'Portal Access',
      subtitle: widget.client.name,
      onClose: () => Navigator.of(context).maybePop(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Portal Login Credentials',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _ClientTextField(
            controller: _emailController,
            label: 'Email',
            helper: 'Client will use this to login to B2B portal',
          ),
          const SizedBox(height: 12),
          _ClientTextField(
            controller: _passwordController,
            label: 'New Password',
            helper: 'Set a new password for this client',
          ),
          const SizedBox(height: 24),
          const Text(
            'Custom Catalog Items',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const Text(
            'Select which items this client is allowed to see and order.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              itemCount: activeItems.length,
              itemBuilder: (context, index) {
                final item = activeItems[index];
                return CheckboxListTile(
                  title: Text(item.displayName),
                  subtitle: Text('Qty Available: ${item.quantity}'),
                  value: _selectedItemIds.contains(item.id),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedItemIds.add(item.id);
                      } else {
                        _selectedItemIds.remove(item.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Save Settings',
            isLoading: _isSaving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
