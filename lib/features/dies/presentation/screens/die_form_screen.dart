import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/erp_form_dialog.dart';
import 'package:core_erp/core/widgets/searchable_select.dart';
import '../../domain/die.dart';
import '../providers/die_provider.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:paper/features/machines/domain/machine.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/core/navigation/app_navigation.dart';

class _MutableProperty {
  _MutableProperty({
    this.key = '',
    this.value = '',
    this.type = CustomPropertyType.text,
    this.unitId,
    List<String>? options,
  }) : options = options ?? [];
  String key;
  String value;
  CustomPropertyType type;
  int? unitId;
  List<String> options;
}

Future<Die?> showDieFormDialog(BuildContext context, {Die? die}) {
  return showErpFormDialog<Die?>(
    context,
    maxWidth: 1380,
    maxHeight: 900,
    child: DieEditorSheet(die: die),
  );
}

class DieEditorSheet extends StatefulWidget {
  const DieEditorSheet({super.key, this.die});

  final Die? die;

  @override
  State<DieEditorSheet> createState() => _DieEditorSheetState();
}

class _DieEditorSheetState extends State<DieEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  
  late final TextEditingController _toolCodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _operationalNotesController;
  late final TextEditingController _storageLocationController;
  
  DieStatus _status = DieStatus.ready;
  DieOwnership _ownership = DieOwnership.inHouse;
  
  // Custom properties as a list of mutable objects for editing
  final List<_MutableProperty> _customProperties = [];

  // Compatible groups
  final List<int> _compatibleMachineGroupIds = [];

  // Multiple photos
  final List<String> _photoUrls = [];

  @override
  void initState() {
    super.initState();
    _toolCodeController = TextEditingController(text: widget.die?.toolCode ?? '');
    _nameController = TextEditingController(text: widget.die?.name ?? '');
    _operationalNotesController = TextEditingController(text: widget.die?.operationalNotes ?? '');
    _storageLocationController = TextEditingController(text: widget.die?.storageLocation ?? '');
    
    if (widget.die != null) {
      _status = widget.die!.status;
      _ownership = widget.die!.ownership;
      _photoUrls.addAll(widget.die!.photoUrls);
      _compatibleMachineGroupIds.addAll(widget.die!.compatibleMachineGroupIds);
      
      for (var prop in widget.die!.physicalSpecs) {
        String key = prop.key;
        if (key == 'bedSize') key = 'Bed Size';
        if (key == 'tonnage') key = 'Tonnage Req.';
        if (key == 'shutHeight') key = 'Shut Height';

        _customProperties.add(_MutableProperty(
          key: key,
          value: prop.value,
          type: prop.type,
          unitId: prop.unitId,
          options: List.from(prop.options),
        ));
      }
    }
  }

  @override
  void dispose() {
    _toolCodeController.dispose();
    _nameController.dispose();
    _operationalNotesController.dispose();
    _storageLocationController.dispose();
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
    setState(() {
      _customProperties[index].value = value;
    });
  }

  void _updateCustomPropertyType(int index, CustomPropertyType type) {
    setState(() {
      _customProperties[index].type = type;
      if (type != CustomPropertyType.numeric) {
        _customProperties[index].unitId = null;
      }
      if (type != CustomPropertyType.dropdown) {
        _customProperties[index].options = [];
      }
    });
  }

  void _updateCustomPropertyUnit(int index, int? unitId) {
    setState(() {
      _customProperties[index].unitId = unitId;
    });
  }

  void _updateCustomPropertyOptions(int index, String optionsStr) {
    setState(() {
      _customProperties[index].options = optionsStr
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (_customProperties[index].value.isNotEmpty &&
          !_customProperties[index].options.contains(_customProperties[index].value)) {
        _customProperties[index].value = '';
      }
    });
  }

  void _addPhotoPlaceholder() {
    setState(() {
      _photoUrls.add('https://images.unsplash.com/photo-1590494165264-1ebe3602eb80?auto=format&fit=crop&q=80');
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _photoUrls.removeAt(index);
    });
  }


  @override
  Widget build(BuildContext context) {
    final title = widget.die == null ? 'Create Die' : 'Edit Die';
    final isLoading = context.watch<DiesProvider>().isLoading;
    final groups = context.watch<GroupsProvider>().activeGroups;

    return Form(
      key: _formKey,
      child: ErpFormScaffold(
        title: title,
        subtitle: 'Manage die/tooling details, machine compatibilities, and photos.',
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ErpDialogSectionCard(
                    title: 'Identity & Production',
                    subtitle: 'Core information for tracking the tool and the parts it produces.',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _DieTextField(
                                controller: _toolCodeController,
                                label: 'Tool Code / ID',
                                helper: 'Unique tool identifier',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DieTextField(
                                controller: _nameController,
                                label: 'Die Name',
                                helper: 'Name of the tool/die',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _DieTextField(
                          controller: _storageLocationController,
                          label: 'Storage Rack / Location',
                          helper: 'E.g. Rack A, Shelf 1',
                          required: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ErpDialogSectionCard(
                    title: 'Machine Compatibility',
                    subtitle: 'Determine where the die can run.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SearchableSelectField<int>(
                          tapTargetKey: const ValueKey<String>('die-add-machine-group-field'),
                          decoration: InputDecoration(
                            labelText: 'Add Compatible Machine Group',
                            helperText: 'Select group to add compatible machine groups',
                            suffixIcon: TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                try {
                                  context.read<AppNavigation>().select('configurator_machine_groups');
                                } catch (_) {}
                              },
                              child: const Text('Manage'),
                            ),
                          ),
                          dialogTitle: 'Select Machine Group',
                          options: groups
                              .where((g) => !_compatibleMachineGroupIds.contains(g.id))
                              .map((g) => SearchableSelectOption<int>(
                                    value: g.id,
                                    label: g.name,
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _compatibleMachineGroupIds.add(val);
                              });
                            }
                          },
                        ),
                        if (_compatibleMachineGroupIds.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _compatibleMachineGroupIds.map((id) {
                              String getGroupName(int id) {
                                for (final g in groups) {
                                  if (g.id == id) return g.name;
                                }
                                return 'Group $id';
                              }
                              return InputChip(
                                label: Text(getGroupName(id)),
                                onDeleted: () {
                                  setState(() {
                                    _compatibleMachineGroupIds.remove(id);
                                  });
                                },
                                deleteIconColor: Colors.redAccent,
                                backgroundColor: const Color(0xFFEFF6FF),
                                labelStyle: const TextStyle(
                                  color: Color(0xFF1E3A8A),
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ErpDialogSectionCard(
                    title: 'Properties',
                    subtitle: 'Define custom properties and their values.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_customProperties.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'No custom fields added yet.',
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          )
                        else
                          ..._customProperties.asMap().entries.map((entry) {
                            final index = entry.key;
                            final prop = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: TextFormField(
                                          initialValue: prop.key,
                                          decoration: InputDecoration(
                                            labelText: 'Field Name',
                                            hintText: 'e.g. Tonnage, Location, etc.',
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
                                          onChanged: (val) => _updateCustomPropertyKey(index, val),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child: SearchableSelectField<CustomPropertyType>(
                                          tapTargetKey: ValueKey<String>('die-custom-property-type-$index'),
                                          value: prop.type,
                                          decoration: const InputDecoration(
                                            labelText: 'Field Type',
                                            filled: true,
                                            fillColor: Color(0xFFF9FAFB),
                                          ),
                                          dialogTitle: 'Field Type',
                                          options: const [
                                            SearchableSelectOption(value: CustomPropertyType.text, label: 'Text'),
                                            SearchableSelectOption(value: CustomPropertyType.numeric, label: 'Numeric'),
                                            SearchableSelectOption(value: CustomPropertyType.dropdown, label: 'Dropdown'),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) _updateCustomPropertyType(index, val);
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                        onPressed: () => _removeCustomProperty(index),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (prop.type == CustomPropertyType.text)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            initialValue: prop.value,
                                            decoration: InputDecoration(
                                              labelText: 'Value',
                                              hintText: 'Enter text value...',
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
                                            onChanged: (val) => _updateCustomPropertyValue(index, val),
                                          ),
                                        ),
                                        const SizedBox(width: 48),
                                      ],
                                    )
                                  else if (prop.type == CustomPropertyType.numeric)
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: SearchableSelectField<int?>(
                                            tapTargetKey: ValueKey<String>('die-custom-property-unit-$index'),
                                            value: prop.unitId,
                                            decoration: const InputDecoration(
                                              labelText: 'Unit (Optional)',
                                              filled: true,
                                              fillColor: Color(0xFFF9FAFB),
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
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 3,
                                          child: TextFormField(
                                            initialValue: prop.value,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(
                                              labelText: 'Value',
                                              hintText: 'Enter numeric value...',
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
                                            onChanged: (val) => _updateCustomPropertyValue(index, val),
                                          ),
                                        ),
                                        const SizedBox(width: 48),
                                      ],
                                    )
                                  else if (prop.type == CustomPropertyType.dropdown)
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: TextFormField(
                                            initialValue: prop.options.join(', '),
                                            decoration: InputDecoration(
                                              labelText: 'Dropdown Options',
                                              hintText: 'A, B, C (comma separated)',
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
                                            onChanged: (val) => _updateCustomPropertyOptions(index, val),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 3,
                                          child: SearchableSelectField<String>(
                                            tapTargetKey: ValueKey<String>('die-custom-property-value-$index'),
                                            value: prop.options.contains(prop.value) ? prop.value : null,
                                            decoration: const InputDecoration(
                                              labelText: 'Select Value',
                                              filled: true,
                                              fillColor: Color(0xFFF9FAFB),
                                            ),
                                            dialogTitle: 'Select Value',
                                            options: prop.options.map((opt) {
                                              return SearchableSelectOption<String>(
                                                value: opt,
                                                label: opt,
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) _updateCustomPropertyValue(index, val);
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 48),
                                      ],
                                    ),
                                  const Divider(height: 24),
                                ],
                              ),
                            );
                          }),
                        const SizedBox(height: 12),
                        AppButton(
                          label: 'Add Property',
                          icon: Icons.add,
                          variant: AppButtonVariant.secondary,
                          onPressed: _addCustomProperty,
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
                    title: 'Photos',
                    subtitle: 'Multiple images of the die, setup conditions, or parts.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            border: Border.all(color: const Color(0xFFE2E8F0), style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.collections_outlined, size: 32, color: Color(0xFF94A3B8)),
                              const SizedBox(height: 8),
                              AppButton(
                                label: 'Upload New Photo',
                                variant: AppButtonVariant.secondary,
                                onPressed: _addPhotoPlaceholder,
                              ),
                            ],
                          ),
                        ),
                        if (_photoUrls.isNotEmpty) const SizedBox(height: 12),
                        ..._photoUrls.asMap().entries.map((entry) {
                          final index = entry.key;
                          final url = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 24, color: Colors.grey),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: url,
                                    decoration: const InputDecoration(
                                      labelText: 'Photo URL',
                                      isDense: true,
                                    ),
                                    onChanged: (val) {
                                      _photoUrls[index] = val;
                                      setState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: () => _removePhoto(index),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ErpDialogSectionCard(
                    title: 'Operational Notes',
                    subtitle: 'Setup instructions or maintenance warnings.',
                    child: _DieTextField(
                      controller: _operationalNotesController,
                      label: 'Notes',
                      helper: 'Multi-line notes for operators',
                      required: false,
                      maxLines: 4,
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
              label: widget.die == null ? 'Create Die' : 'Save Changes',
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
          options: prop.options,
        ));
      }
    }

    final newDie = Die(
      id: widget.die?.id ?? '',
      name: _nameController.text.trim(),
      toolCode: _toolCodeController.text.trim(),
      photoUrls: _photoUrls,
      operationalNotes: _operationalNotesController.text.trim(),
      compatibleMachineGroupIds: _compatibleMachineGroupIds,
      strokeCount: widget.die?.strokeCount ?? 0,
      storageLocation: _storageLocationController.text.trim(),
      numberOfCavities: widget.die?.numberOfCavities,
      physicalSpecs: customPropsList,
      status: _status,
      ownership: _ownership,
      createdAt: widget.die?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    if (widget.die == null) {
      await context.read<DiesProvider>().createDie(newDie);
    } else {
      await context.read<DiesProvider>().updateDie(newDie);
    }
    
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _DieTextField extends StatelessWidget {
  const _DieTextField({
    required this.controller,
    required this.label,
    required this.helper,
    this.required = true,
    this.maxLines = 1,
    this.isNumber = false,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final bool required;
  final int maxLines;
  final bool isNumber;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: isNumber ? TextInputType.number : null,
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
