import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/client_definition.dart';
import '../../domain/client_inputs.dart';
import '../providers/clients_provider.dart';

class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientsProvider>(
      builder: (context, clients, _) {
        if (clients.isLoading && clients.clients.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return SoftMasterDataPage(
          title: 'Clients',
          subtitle:
              'Manage client master data for sales flows, billing details, and downstream transaction forms.',
          action: AppButton(
            label: 'Add Client',
            icon: Icons.add,
            isLoading: clients.isSaving,
            onPressed: () => _openClientEditor(context),
          ),
          toolbar: const _ClientsToolbar(),
          messages: [
            if (clients.errorMessage != null)
              _ClientsMessageBanner(
                message: clients.errorMessage!,
                isError: true,
              ),
          ],
          body: clients.filteredClients.isEmpty
              ? const AppEmptyState(
                  title: 'No clients found',
                  message:
                      'Add your first client to keep names, GST numbers, and addresses consistent across the system.',
                  icon: Icons.groups_outlined,
                )
              : _ClientsTable(clients: clients.filteredClients),
        );
      },
    );
  }

  static Future<ClientDefinition?> openEditor(
    BuildContext context, {
    ClientDefinition? client,
  }) {
    return showErpFormDialog<ClientDefinition?>(
      context,
      maxWidth: 760,
      maxHeight: 760,
      child: _ClientEditorSheet(client: client),
    );
  }

  static Future<ClientDefinition?> _openClientEditor(
    BuildContext context, {
    ClientDefinition? client,
  }) {
    return openEditor(context, client: client);
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
        SoftSegmentedFilter<ClientStatusFilter>(
          selected: provider.statusFilter,
          onChanged: provider.setStatusFilter,
          options: const [
            SoftSegmentOption<ClientStatusFilter>(
              value: ClientStatusFilter.active,
              label: 'Active',
            ),
            SoftSegmentOption<ClientStatusFilter>(
              value: ClientStatusFilter.archived,
              label: 'Archived',
            ),
            SoftSegmentOption<ClientStatusFilter>(
              value: ClientStatusFilter.all,
              label: 'All',
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
            label: client.isArchived ? 'Archived' : 'Active',
            background: client.isArchived
                ? const Color(0xFFF3F4F6)
                : const Color(0xFFECFDF5),
            textColor: client.isArchived
                ? const Color(0xFF6B7280)
                : const Color(0xFF0F766E),
            borderColor: client.isArchived
                ? const Color(0xFFE5E7EB)
                : const Color(0xFFBFEAD8),
          ),
        ),
        Expanded(
          flex: 2,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftActionLink(
                label: 'Edit',
                onTap: () => ClientsScreen.openEditor(context, client: client),
              ),
              SoftActionLink(
                label: client.isArchived ? 'Restore' : 'Archive',
                onTap: provider.isSaving
                    ? null
                    : () {
                        if (client.isArchived) {
                          provider.restoreClient(client.id);
                        } else {
                          provider.archiveClient(client.id);
                        }
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
  const _ClientEditorSheet({this.client});

  final ClientDefinition? client;

  @override
  State<_ClientEditorSheet> createState() => _ClientEditorSheetState();
}

class _ClientEditorSheetState extends State<_ClientEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _aliasController;
  late final TextEditingController _gstController;
  late final TextEditingController _addressController;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.client?.name ?? '');
    _aliasController = TextEditingController(text: widget.client?.alias ?? '');
    _gstController = TextEditingController(
      text: widget.client?.gstNumber ?? '',
    );
    _addressController = TextEditingController(
      text: widget.client?.address ?? '',
    );
    _nameController.addListener(_handleChange);
    _aliasController.addListener(_handleChange);
    _gstController.addListener(_handleChange);
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
    _nameController.dispose();
    _aliasController.dispose();
    _gstController.dispose();
    _addressController.dispose();
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
            if (widget.client != null)
              AppButton(
                label: widget.client!.isArchived ? 'Restore' : 'Archive',
                variant: AppButtonVariant.secondary,
                isLoading: provider.isSaving,
                onPressed: () async {
                  final result = widget.client!.isArchived
                      ? await provider.restoreClient(widget.client!.id)
                      : await provider.archiveClient(widget.client!.id);
                  if (context.mounted && result != null) {
                    Navigator.of(context).pop(result);
                  }
                },
              ),
            AppButton(
              label: widget.client == null ? 'Create Client' : 'Save Changes',
              isLoading: provider.isSaving,
              onPressed: () => _submit(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
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
    });

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
            ),
          )
        : await provider.updateClient(
            UpdateClientInput(
              id: widget.client!.id,
              name: _nameController.text.trim(),
              alias: _aliasController.text.trim(),
              gstNumber: normalizedGst,
              address: _addressController.text.trim(),
            ),
          );

    if (context.mounted && result != null) {
      Navigator.of(context).pop(result);
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

class _ClientsMessageBanner extends StatelessWidget {
  const _ClientsMessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return ErpFormMessageBanner(message: message, isError: isError);
  }
}
