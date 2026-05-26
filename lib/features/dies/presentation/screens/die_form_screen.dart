import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../domain/die.dart';
import '../providers/die_provider.dart';
import '../../../../features/groups/presentation/providers/groups_provider.dart';

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
  late final TextEditingController _partsController;
  late final TextEditingController _operationalNotesController;
  late final TextEditingController _strokeCountController;
  late final TextEditingController _storageLocationController;
  late final TextEditingController _numberOfCavitiesController;
  
  DieStatus _status = DieStatus.ready;
  DieOwnership _ownership = DieOwnership.inHouse;
  
  // Physical specs
  late final TextEditingController _bedSizeController;
  late final TextEditingController _tonnageController;
  late final TextEditingController _shutHeightController;

  // Compatible groups
  final List<int> _compatibleMachineGroupIds = [];

  // Multiple photos
  final List<String> _photoUrls = [];

  @override
  void initState() {
    super.initState();
    _toolCodeController = TextEditingController(text: widget.die?.toolCode ?? '');
    _partsController = TextEditingController(text: widget.die?.producedPartNumbers.join(', ') ?? '');
    _operationalNotesController = TextEditingController(text: widget.die?.operationalNotes ?? '');
    _strokeCountController = TextEditingController(text: widget.die?.strokeCount?.toString() ?? '');
    _storageLocationController = TextEditingController(text: widget.die?.storageLocation ?? '');
    _numberOfCavitiesController = TextEditingController(text: widget.die?.numberOfCavities?.toString() ?? '');
    
    _bedSizeController = TextEditingController(text: widget.die?.physicalSpecs['bedSize']?.toString() ?? '');
    _tonnageController = TextEditingController(text: widget.die?.physicalSpecs['tonnage']?.toString() ?? '');
    _shutHeightController = TextEditingController(text: widget.die?.physicalSpecs['shutHeight']?.toString() ?? '');
    
    if (widget.die != null) {
      _status = widget.die!.status;
      _ownership = widget.die!.ownership;
      _photoUrls.addAll(widget.die!.photoUrls);
      _compatibleMachineGroupIds.addAll(widget.die!.compatibleMachineGroupIds);
    }
  }

  @override
  void dispose() {
    _toolCodeController.dispose();
    _partsController.dispose();
    _operationalNotesController.dispose();
    _strokeCountController.dispose();
    _storageLocationController.dispose();
    _numberOfCavitiesController.dispose();
    _bedSizeController.dispose();
    _tonnageController.dispose();
    _shutHeightController.dispose();
    super.dispose();
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
  
  void _toggleGroup(int groupId) {
    setState(() {
      if (_compatibleMachineGroupIds.contains(groupId)) {
        _compatibleMachineGroupIds.remove(groupId);
      } else {
        _compatibleMachineGroupIds.add(groupId);
      }
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
                                controller: _partsController,
                                label: 'Produced Part Numbers',
                                helper: 'Comma-separated list',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DieTextField(
                                controller: _numberOfCavitiesController,
                                label: 'Number of Cavities',
                                helper: 'E.g. 1, 2, 4',
                                required: false,
                                isNumber: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DieTextField(
                                controller: _storageLocationController,
                                label: 'Storage Rack / Location',
                                helper: 'E.g. Rack A, Shelf 1',
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
                    title: 'Compatibility & Lifecycle',
                    subtitle: 'Determine where the die can run and its current wear.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Compatible Machine Groups', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: groups.map((g) {
                            final isSelected = _compatibleMachineGroupIds.contains(g.id);
                            return FilterChip(
                              label: Text(g.name),
                              selected: isSelected,
                              onSelected: (_) => _toggleGroup(g.id),
                              selectedColor: const Color(0xFFEFF6FF),
                              checkmarkColor: const Color(0xFF2563EB),
                              labelStyle: TextStyle(
                                color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF475569),
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isSelected ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              backgroundColor: const Color(0xFFF8FAFC),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _DieTextField(
                                controller: _strokeCountController,
                                label: 'Stroke Count',
                                helper: 'Current number of strokes',
                                required: false,
                                isNumber: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SearchableSelectField<DieOwnership>(
                                tapTargetKey: const ValueKey<String>('die-ownership-field'),
                                value: _ownership,
                                decoration: const InputDecoration(
                                  labelText: 'Ownership',
                                ),
                                dialogTitle: 'Ownership',
                                options: DieOwnership.values.map((o) {
                                  return SearchableSelectOption(
                                    value: o,
                                    label: o == DieOwnership.inHouse ? 'In-House' : 'Customer Owned',
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _ownership = val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ErpDialogSectionCard(
                    title: 'Physical Specs',
                    subtitle: 'Dimensions and limits for matching with machines.',
                    child: Row(
                      children: [
                        Expanded(
                          child: _DieTextField(
                            controller: _bedSizeController,
                            label: 'Bed Size',
                            helper: 'E.g. 1000x800mm',
                            required: false,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DieTextField(
                            controller: _tonnageController,
                            label: 'Tonnage Req.',
                            helper: 'E.g. 100T',
                            required: false,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DieTextField(
                            controller: _shutHeightController,
                            label: 'Shut Height',
                            helper: 'E.g. 350mm',
                            required: false,
                          ),
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
                    title: 'Status',
                    subtitle: 'Current operational state.',
                    child: SearchableSelectField<DieStatus>(
                      tapTargetKey: const ValueKey<String>('die-status-field'),
                      value: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                      ),
                      dialogTitle: 'Status',
                      options: DieStatus.values.map((s) {
                        return SearchableSelectOption(
                          value: s,
                          label: s.name.toUpperCase(),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _status = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
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
    
    final newDie = Die(
      id: widget.die?.id ?? '',
      toolCode: _toolCodeController.text.trim(),
      producedPartNumbers: _partsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      photoUrls: _photoUrls,
      operationalNotes: _operationalNotesController.text.trim(),
      compatibleMachineGroupIds: _compatibleMachineGroupIds,
      strokeCount: int.tryParse(_strokeCountController.text.trim()),
      storageLocation: _storageLocationController.text.trim(),
      numberOfCavities: int.tryParse(_numberOfCavitiesController.text.trim()),
      physicalSpecs: {
        'bedSize': _bedSizeController.text.trim(),
        'tonnage': _tonnageController.text.trim(),
        'shutHeight': _shutHeightController.text.trim(),
      },
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
