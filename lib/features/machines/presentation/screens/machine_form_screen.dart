import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../domain/machine.dart';
import '../providers/machine_provider.dart';
import '../../../../features/units/presentation/providers/units_provider.dart';
import '../../../../features/groups/presentation/providers/groups_provider.dart';

class _MutableProperty {
  _MutableProperty({
    this.key = '',
    this.value = '',
    this.type = CustomPropertyType.text,
    this.unitId,
  });
  String key;
  String value;
  CustomPropertyType type;
  int? unitId;
}

Future<Machine?> showMachineFormDialog(BuildContext context, {Machine? machine}) {
  return showErpFormDialog<Machine?>(
    context,
    maxWidth: 1380,
    maxHeight: 900,
    child: MachineEditorSheet(machine: machine),
  );
}

class MachineEditorSheet extends StatefulWidget {
  const MachineEditorSheet({super.key, this.machine});

  final Machine? machine;

  @override
  State<MachineEditorSheet> createState() => _MachineEditorSheetState();
}

class _MachineEditorSheetState extends State<MachineEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  
  late final TextEditingController _nameController;
  late final TextEditingController _assetIdController;
  late final TextEditingController _makeModelController;
  late final TextEditingController _serialNumberController;
  late final TextEditingController _locationController;
  late final TextEditingController _photoUrlController;
  
  int? _groupId;
  DateTime? _installationDate;
  MachineStatus _status = MachineStatus.active;
  
  // Custom properties as a list of mutable objects for editing
  final List<_MutableProperty> _customProperties = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.machine?.name ?? '');
    _assetIdController = TextEditingController(text: widget.machine?.assetId ?? '');
    _makeModelController = TextEditingController(text: widget.machine?.makeModel ?? '');
    _serialNumberController = TextEditingController(text: widget.machine?.serialNumber ?? '');
    _locationController = TextEditingController(text: widget.machine?.location ?? '');
    _photoUrlController = TextEditingController(text: widget.machine?.primaryPhotoUrl ?? '');
    
    _groupId = widget.machine?.groupId;
    _installationDate = widget.machine?.installationDate;
    
    if (widget.machine != null) {
      _status = widget.machine!.status;
      for (var prop in widget.machine!.customProperties) {
        _customProperties.add(_MutableProperty(
          key: prop.key,
          value: prop.value,
          type: prop.type,
          unitId: prop.unitId,
        ));
      }
    }
    
    _photoUrlController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _assetIdController.dispose();
    _makeModelController.dispose();
    _serialNumberController.dispose();
    _locationController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  void _addCustomProperty() {
    setState(() {
      _customProperties.add(_MutableProperty());
    });
  }

  void _removeCustomProperty(int index) {
    setState(() {
      _customProperties.removeAt(index);
    });
  }

  void _updateCustomPropertyKey(int index, String key) {
    _customProperties[index].key = key;
  }

  void _updateCustomPropertyValue(int index, String value) {
    _customProperties[index].value = value;
  }

  void _updateCustomPropertyType(int index, CustomPropertyType type) {
    setState(() {
      _customProperties[index].type = type;
      if (type == CustomPropertyType.text) {
        _customProperties[index].unitId = null;
      }
    });
  }

  void _updateCustomPropertyUnit(int index, int? unitId) {
    setState(() {
      _customProperties[index].unitId = unitId;
    });
  }

  Future<void> _pickInstallationDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _installationDate ?? DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() {
        _installationDate = date;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.machine == null ? 'Create Machine' : 'Edit Machine';
    final isLoading = context.watch<MachinesProvider>().isLoading;
    final groups = context.watch<GroupsProvider>().activeGroups;

    return Form(
      key: _formKey,
      child: ErpFormScaffold(
        title: title,
        subtitle: 'Define machine identity, properties, and current operational status.',
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ErpDialogSectionCard(
                    title: 'Identity & Details',
                    subtitle: 'Core information for identifying the machine on the floor.',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _MachineTextField(
                                controller: _nameController,
                                label: 'Machine Name',
                                helper: 'E.g. Komatsu 100T Press',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _MachineTextField(
                                controller: _assetIdController,
                                label: 'Asset ID / Eq. Code',
                                helper: 'Unique factory identifier',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _MachineTextField(
                                controller: _makeModelController,
                                label: 'Make/Model',
                                helper: 'Manufacturer and model',
                                required: false,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _MachineTextField(
                                controller: _serialNumberController,
                                label: 'Serial Number',
                                helper: 'Hardware serial number',
                                required: false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: SearchableSelectField<int>(
                                tapTargetKey: const ValueKey<String>('machine-group-field'),
                                value: _groupId,
                                decoration: const InputDecoration(
                                  labelText: 'Machine Group',
                                  helperText: 'Categorization from Group Master',
                                ),
                                dialogTitle: 'Machine Group',
                                searchHintText: 'Search machine groups',
                                options: groups.map((g) => SearchableSelectOption<int>(
                                  value: g.id,
                                  label: g.name,
                                )).toList(),
                                onChanged: (val) => setState(() => _groupId = val),
                                validator: (val) => val == null ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _MachineTextField(
                                controller: _locationController,
                                label: 'Location / Zone',
                                helper: 'E.g. Press Shop A',
                                required: false,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ErpDialogSectionCard(
                    title: 'Custom Properties',
                    subtitle: 'Define flexible properties like Tonnage, Power, Coolant Type.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._customProperties.asMap().entries.map((entry) {
                          final index = entry.key;
                          final prop = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          initialValue: prop.key,
                                          decoration: const InputDecoration(
                                            labelText: 'Property Name',
                                            hintText: 'e.g. Tonnage',
                                            isDense: true,
                                          ),
                                          onChanged: (val) => _updateCustomPropertyKey(index, val),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 1,
                                        child: SearchableSelectField<CustomPropertyType>(
                                          tapTargetKey: ValueKey<String>('machine-custom-property-type-$index'),
                                          value: prop.type,
                                          decoration: const InputDecoration(
                                            labelText: 'Type',
                                            isDense: true,
                                          ),
                                          dialogTitle: 'Property Type',
                                          options: const [
                                            SearchableSelectOption(value: CustomPropertyType.text, label: 'Text'),
                                            SearchableSelectOption(value: CustomPropertyType.numeric, label: 'Numeric'),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) _updateCustomPropertyType(index, val);
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                        onPressed: () => _removeCustomProperty(index),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      if (prop.type == CustomPropertyType.numeric) ...[
                                        Expanded(
                                          flex: 1,
                                          child: SearchableSelectField<int?>(
                                            tapTargetKey: ValueKey<String>('machine-custom-property-unit-$index'),
                                            value: prop.unitId,
                                            decoration: const InputDecoration(
                                              labelText: 'Unit (Optional)',
                                              isDense: true,
                                            ),
                                            dialogTitle: 'Select Unit',
                                            options: [
                                              const SearchableSelectOption<int?>(value: null, label: 'None'),
                                              ...context.watch<UnitsProvider>().activeUnits.map((u) {
                                                return SearchableSelectOption<int?>(
                                                  value: u.id,
                                                  label: u.symbol,
                                                );
                                              }),
                                            ],
                                            onChanged: (val) => _updateCustomPropertyUnit(index, val),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          initialValue: prop.value,
                                          keyboardType: prop.type == CustomPropertyType.numeric ? TextInputType.number : TextInputType.text,
                                          decoration: InputDecoration(
                                            labelText: 'Value',
                                            hintText: prop.type == CustomPropertyType.numeric ? 'e.g. 100' : 'e.g. Red',
                                            isDense: true,
                                          ),
                                          onChanged: (val) => _updateCustomPropertyValue(index, val),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _addCustomProperty,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Property'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ErpDialogSectionCard(
                    title: 'Status & Lifecycle',
                    subtitle: 'Current operational state.',
                    child: Column(
                      children: [
                        SearchableSelectField<MachineStatus>(
                          tapTargetKey: const ValueKey<String>('machine-status-field'),
                          value: _status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                          dialogTitle: 'Status',
                          options: MachineStatus.values.map((s) {
                            return SearchableSelectOption(
                              value: s,
                              label: s.name.toUpperCase(),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _status = val);
                          },
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _pickInstallationDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Installation Date',
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
                              ),
                            ),
                            child: Text(
                              _installationDate == null 
                                ? 'Not specified' 
                                : '${_installationDate!.year}-${_installationDate!.month.toString().padLeft(2, '0')}-${_installationDate!.day.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ErpDialogSectionCard(
                    title: 'Primary Photo',
                    subtitle: 'A visual identifier for the machine.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPhotoPreview(),
                        const SizedBox(height: 12),
                        _MachineTextField(
                          controller: _photoUrlController,
                          label: 'Photo URL',
                          helper: 'Direct image link',
                          required: false,
                        ),
                      ],
                    ),
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
            AppButton(
              label: widget.machine == null ? 'Create Machine' : 'Save Changes',
              isLoading: isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Construct Custom Properties list
    final customPropsList = <CustomProperty>[];
    for (var prop in _customProperties) {
      if (prop.key.trim().isNotEmpty) {
        customPropsList.add(CustomProperty(
          key: prop.key.trim(), 
          value: prop.value.trim(),
          type: prop.type,
          unitId: prop.unitId,
        ));
      }
    }

    final newMachine = Machine(
      id: widget.machine?.id ?? '',
      name: _nameController.text.trim(),
      assetId: _assetIdController.text.trim(),
      primaryPhotoUrl: _photoUrlController.text.trim(),
      groupId: _groupId,
      makeModel: _makeModelController.text.trim(),
      serialNumber: _serialNumberController.text.trim(),
      location: _locationController.text.trim(),
      installationDate: _installationDate,
      status: _status,
      customProperties: customPropsList,
      createdAt: widget.machine?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    if (widget.machine == null) {
      await context.read<MachinesProvider>().createMachine(newMachine);
    } else {
      await context.read<MachinesProvider>().updateMachine(newMachine);
    }
    
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildPhotoPreview() {
    final url = _photoUrlController.text.trim();
    if (url.isNotEmpty) {
      return Container(
        width: double.infinity,
        height: 200,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholderUploadBox(),
          ),
        ),
      );
    }
    return _buildPlaceholderUploadBox();
  }

  Widget _buildPlaceholderUploadBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0), style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 48, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          const Text('Upload Photo'),
          const SizedBox(height: 8),
          AppButton(
            label: 'Select Image',
            variant: AppButtonVariant.secondary,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _MachineTextField extends StatelessWidget {
  const _MachineTextField({
    required this.controller,
    required this.label,
    required this.helper,
    this.required = true,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
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
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Required';
        }
        return null;
      },
    );
  }
}
