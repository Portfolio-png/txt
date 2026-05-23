import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/vendor_definition.dart';
import '../../domain/vendor_inputs.dart';
import '../providers/vendors_provider.dart';

class VendorsScreen extends StatelessWidget {
  const VendorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VendorsProvider>(
      builder: (context, vendors, _) {
        if (vendors.isLoading && vendors.vendors.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return SoftMasterDataPage(
          title: 'Vendors',
          subtitle:
              'Manage inbound supplier records used by reception challans and purchasing references.',
          action: AppButton(
            label: 'Add Vendor',
            icon: Icons.add,
            isLoading: vendors.isSaving,
            onPressed: () => _openEditor(context),
          ),
          toolbar: const _VendorsToolbar(),
          messages: [
            if (vendors.errorMessage != null)
              _MessageBanner(message: vendors.errorMessage!, isError: true),
          ],
          body: vendors.filteredVendors.isEmpty
              ? const AppEmptyState(
                  title: 'No vendors found',
                  message:
                      'Add your first vendor so reception challans can point to a real inbound source.',
                  icon: Icons.local_shipping_outlined,
                )
              : _VendorsTable(vendors: vendors.filteredVendors),
        );
      },
    );
  }

  static Future<VendorDefinition?> openEditor(
    BuildContext context, {
    VendorDefinition? vendor,
  }) {
    return showErpFormDialog<VendorDefinition?>(
      context,
      maxWidth: 820,
      maxHeight: 760,
      child: _VendorEditorSheet(vendor: vendor),
    );
  }

  static Future<VendorDefinition?> _openEditor(
    BuildContext context, {
    VendorDefinition? vendor,
  }) => openEditor(context, vendor: vendor);
}

class _VendorsToolbar extends StatelessWidget {
  const _VendorsToolbar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VendorsProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return SoftMasterToolbar(
      children: [
        if (!isDesktop)
          SoftMasterSearchField(
            hintText: 'Search vendor, contact, GST, or address',
            onChanged: provider.setSearchQuery,
          ),
        SoftSegmentedFilter<VendorStatusFilter>(
          selected: provider.statusFilter,
          onChanged: provider.setStatusFilter,
          options: const [
            SoftSegmentOption(
              value: VendorStatusFilter.active,
              label: 'Active',
            ),
            SoftSegmentOption(
              value: VendorStatusFilter.archived,
              label: 'Archived',
            ),
            SoftSegmentOption(value: VendorStatusFilter.all, label: 'All'),
          ],
        ),
      ],
    );
  }
}

class _VendorsTable extends StatelessWidget {
  const _VendorsTable({required this.vendors});

  final List<VendorDefinition> vendors;

  @override
  Widget build(BuildContext context) {
    return SoftMasterTable(
      minWidth: 1320,
      columns: const [
        SoftTableColumn('Vendor', flex: 2),
        SoftTableColumn('Contact', flex: 2),
        SoftTableColumn('GST / Phone', flex: 2),
        SoftTableColumn('Email', flex: 2),
        SoftTableColumn('Address', flex: 3),
        SoftTableColumn('Status', flex: 1),
        SoftTableColumn('Actions', flex: 2),
      ],
      itemCount: vendors.length,
      rowBuilder: (context, index) => _VendorRow(vendor: vendors[index]),
    );
  }
}

class _VendorRow extends StatelessWidget {
  const _VendorRow({required this.vendor});

  final VendorDefinition vendor;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VendorsProvider>();
    return SoftMasterRow(
      children: [
        Expanded(
          flex: 2,
          child: SoftInlineText(vendor.displayLabel, weight: FontWeight.w700),
        ),
        Expanded(
          flex: 2,
          child: SoftInlineText(
            vendor.contactName.isEmpty ? '—' : vendor.contactName,
          ),
        ),
        Expanded(
          flex: 2,
          child: SoftInlineText(
            [
                  if (vendor.gstNumber.isNotEmpty) vendor.gstNumber,
                  if (vendor.phone.isNotEmpty) vendor.phone,
                ].isEmpty
                ? '—'
                : [
                    if (vendor.gstNumber.isNotEmpty) vendor.gstNumber,
                    if (vendor.phone.isNotEmpty) vendor.phone,
                  ].join(' • '),
          ),
        ),
        Expanded(
          flex: 2,
          child: SoftInlineText(vendor.email.isEmpty ? '—' : vendor.email),
        ),
        Expanded(
          flex: 3,
          child: SoftInlineText(
            vendor.address.isEmpty ? '—' : vendor.address,
            maxLines: 2,
          ),
        ),
        Expanded(
          flex: 1,
          child: SoftStatusPill(
            label: vendor.isArchived ? 'Archived' : 'Active',
            background: vendor.isArchived
                ? const Color(0xFFF3F4F6)
                : const Color(0xFFECFDF5),
            textColor: vendor.isArchived
                ? const Color(0xFF6B7280)
                : const Color(0xFF0F766E),
            borderColor: vendor.isArchived
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
                onTap: () => VendorsScreen.openEditor(context, vendor: vendor),
              ),
              SoftActionLink(
                label: vendor.isArchived ? 'Restore' : 'Archive',
                onTap: provider.isSaving
                    ? null
                    : () {
                        if (vendor.isArchived) {
                          provider.restoreVendor(vendor.id);
                        } else {
                          provider.archiveVendor(vendor.id);
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

class _VendorEditorSheet extends StatefulWidget {
  const _VendorEditorSheet({this.vendor});

  final VendorDefinition? vendor;

  @override
  State<_VendorEditorSheet> createState() => _VendorEditorSheetState();
}

class _VendorEditorSheetState extends State<_VendorEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _aliasController;
  late final TextEditingController _gstController;
  late final TextEditingController _addressController;
  late final TextEditingController _contactController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final vendor = widget.vendor;
    _nameController = TextEditingController(text: vendor?.name ?? '');
    _aliasController = TextEditingController(text: vendor?.alias ?? '');
    _gstController = TextEditingController(text: vendor?.gstNumber ?? '');
    _addressController = TextEditingController(text: vendor?.address ?? '');
    _contactController = TextEditingController(text: vendor?.contactName ?? '');
    _phoneController = TextEditingController(text: vendor?.phone ?? '');
    _emailController = TextEditingController(text: vendor?.email ?? '');
    for (final controller in [
      _nameController,
      _aliasController,
      _gstController,
      _addressController,
      _contactController,
      _phoneController,
      _emailController,
    ]) {
      controller.addListener(_handleChange);
    }
  }

  void _handleChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _aliasController,
      _gstController,
      _addressController,
      _contactController,
      _phoneController,
      _emailController,
    ]) {
      controller.removeListener(_handleChange);
    }
    _nameController.dispose();
    _aliasController.dispose();
    _gstController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VendorsProvider>();
    final duplicate = provider.checkDuplicate(
      name: _nameController.text,
      gstNumber: _gstController.text,
      excludeId: widget.vendor?.id,
    );
    final banner =
        _localError ??
        (provider.isSaving == false ? provider.errorMessage : null);
    return Form(
      key: _formKey,
      child: ErpFormScaffold(
        title: widget.vendor == null ? 'Create Vendor' : 'Edit Vendor',
        subtitle:
            'Capture inbound supplier details once so reception challans and purchasing references stay consistent.',
        errorBanner: banner == null
            ? null
            : ErpFormMessageBanner(message: banner, isError: true),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ErpDialogSectionCard(
              title: 'Vendor Identity',
              subtitle:
                  'Store the legal identity, shorthand alias, and tax details your team should reuse.',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          'Vendor name',
                          _nameController,
                          helper: 'Required. Primary supplier or source name',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          'Alias',
                          _aliasController,
                          helper: 'Optional short label used in quick lists',
                          required: false,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          'GST number',
                          _gstController,
                          helper: 'Optional. Must stay unique when provided',
                          required: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          'Email',
                          _emailController,
                          helper: 'Optional dispatch or accounts contact email',
                          required: false,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _VendorWarningText(warning: duplicate.warning),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ErpDialogSectionCard(
              title: 'Contacts & Address',
              subtitle:
                  'Keep the people and address details operators need while creating reception documents.',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          'Contact name',
                          _contactController,
                          helper: 'Optional primary person or desk name',
                          required: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          'Phone',
                          _phoneController,
                          helper: 'Optional mobile or office number',
                          required: false,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    'Address',
                    _addressController,
                    helper: 'Optional billing or dispatch address',
                    required: false,
                    maxLines: 3,
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
            if (widget.vendor != null)
              AppButton(
                label: widget.vendor!.isArchived ? 'Restore' : 'Archive',
                variant: AppButtonVariant.secondary,
                isLoading: provider.isSaving,
                onPressed: () async {
                  final saved = widget.vendor!.isArchived
                      ? await provider.restoreVendor(widget.vendor!.id)
                      : await provider.archiveVendor(widget.vendor!.id);
                  if (!context.mounted ||
                      saved == null ||
                      provider.errorMessage != null) {
                    return;
                  }
                  Navigator.of(context).pop(saved);
                },
              ),
            AppButton(
              label: widget.vendor == null ? 'Create Vendor' : 'Save Changes',
              icon: Icons.save_outlined,
              isLoading: provider.isSaving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    String? helper,
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: (value) {
        final trimmed = (value ?? '').trim();
        if (required && trimmed.isEmpty) {
          return 'Required';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final provider = context.read<VendorsProvider>();
    final duplicate = provider.checkDuplicate(
      name: _nameController.text,
      gstNumber: _gstController.text,
      excludeId: widget.vendor?.id,
    );
    if (duplicate.blockingDuplicate) {
      setState(() {
        _localError =
            'A vendor with the same name or GST number already exists.';
      });
      return;
    }
    setState(() {
      _localError = null;
    });
    final saved = widget.vendor == null
        ? await provider.createVendor(
            CreateVendorInput(
              name: _nameController.text,
              alias: _aliasController.text,
              gstNumber: _gstController.text,
              address: _addressController.text,
              contactName: _contactController.text,
              phone: _phoneController.text,
              email: _emailController.text,
            ),
          )
        : await provider.updateVendor(
            UpdateVendorInput(
              id: widget.vendor!.id,
              name: _nameController.text,
              alias: _aliasController.text,
              gstNumber: _gstController.text,
              address: _addressController.text,
              contactName: _contactController.text,
              phone: _phoneController.text,
              email: _emailController.text,
            ),
          );
    if (saved != null && mounted && provider.errorMessage == null) {
      Navigator.of(context).pop(saved);
    }
  }
}

class _VendorWarningText extends StatelessWidget {
  const _VendorWarningText({required this.warning});

  final VendorDuplicateWarning warning;

  @override
  Widget build(BuildContext context) {
    final message = switch (warning) {
      VendorDuplicateWarning.none => null,
      VendorDuplicateWarning.nameOnly =>
        'A vendor with this name already exists.',
      VendorDuplicateWarning.gstOnly =>
        'A vendor with this GST number already exists.',
      VendorDuplicateWarning.nameAndGst =>
        'A vendor with this exact identity already exists.',
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

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return ErpFormMessageBanner(message: message, isError: isError);
  }
}
