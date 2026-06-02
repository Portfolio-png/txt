import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/erp_form_dialog.dart';
import 'package:core_erp/core/widgets/searchable_select.dart';
import 'package:core_erp/core/navigation/app_navigation.dart';
import 'package:core_erp/features/groups/presentation/screens/groups_screen.dart';
import '../../domain/machine.dart';
import '../../domain/machine_capability.dart';
import '../providers/machine_provider.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';

class _MutableCapability {
  _MutableCapability({
    this.id,
    this.processType = '',
    this.inputMaterialBarcode = '',
    this.inputMaterialName = '',
    this.inputUnitId,
    this.outputMaterialBarcode = '',
    this.outputMaterialName = '',
    this.outputUnitId,
    this.dieId,
    this.dieName,
    this.expectedYieldRatio,
    this.conversionFactor,
    this.durationPerUnit,
  });

  String? id;
  String processType;
  String inputMaterialBarcode;
  String inputMaterialName;
  int? inputUnitId;
  String outputMaterialBarcode;
  String outputMaterialName;
  int? outputUnitId;
  String? dieId;
  String? dieName;
  double? expectedYieldRatio;
  double? conversionFactor;
  double? durationPerUnit;
}

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
  late final TextEditingController _photoUrlController;
  
  int? _groupId;
  MachineStatus _status = MachineStatus.active;
  bool _isUploading = false;
  
  // Custom properties as a list of mutable objects for editing
  final List<_MutableProperty> _customProperties = [];

  // Capabilities as a list of mutable objects for editing
  final List<_MutableCapability> _capabilities = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.machine?.name ?? '');
    _assetIdController = TextEditingController(text: widget.machine?.assetId ?? '');
    _photoUrlController = TextEditingController(text: widget.machine?.primaryPhotoUrl ?? '');
    
    _groupId = widget.machine?.groupId;
    
    if (widget.machine != null) {
      _status = widget.machine!.status;
      
      // Convert legacy fields to custom fields dynamically to preserve data
      if (widget.machine!.makeModel.trim().isNotEmpty) {
        _customProperties.add(_MutableProperty(
          key: 'Make/Model',
          value: widget.machine!.makeModel.trim(),
        ));
      }
      if (widget.machine!.serialNumber.trim().isNotEmpty) {
        _customProperties.add(_MutableProperty(
          key: 'Serial Number',
          value: widget.machine!.serialNumber.trim(),
        ));
      }
      if (widget.machine!.location != null && widget.machine!.location!.trim().isNotEmpty) {
        _customProperties.add(_MutableProperty(
          key: 'Location',
          value: widget.machine!.location!.trim(),
        ));
      }
      if (widget.machine!.installationDate != null) {
        final d = widget.machine!.installationDate!;
        final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        _customProperties.add(_MutableProperty(
          key: 'Installation Date',
          value: dateStr,
        ));
      }

      for (var prop in widget.machine!.customProperties) {
        _customProperties.add(_MutableProperty(
          key: prop.key,
          value: prop.value,
          type: prop.type,
          unitId: prop.unitId,
          options: List.from(prop.options),
        ));
      }

      for (var cap in widget.machine!.capabilities) {
        _capabilities.add(_MutableCapability(
          id: cap.id,
          processType: cap.processType,
          inputMaterialBarcode: cap.inputMaterialBarcode,
          inputMaterialName: cap.inputMaterialName,
          inputUnitId: cap.inputUnitId,
          outputMaterialBarcode: cap.outputMaterialBarcode,
          outputMaterialName: cap.outputMaterialName,
          outputUnitId: cap.outputUnitId,
          dieId: cap.dieId,
          dieName: cap.dieName,
          expectedYieldRatio: cap.expectedYieldRatio,
          conversionFactor: cap.conversionFactor,
          durationPerUnit: cap.durationPerUnit,
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

  void _addCapability() {
    setState(() {
      _capabilities.add(_MutableCapability());
    });
  }

  void _removeCapability(int index) {
    setState(() {
      _capabilities.removeAt(index);
    });
  }

  String _contentTypeFromExtension(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'webp': return 'image/webp';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _pickAndUploadImage() async {
    // If we're creating a new machine, we don't have an ID yet.
    // So we can only upload photos for existing machines right now,
    // or we'd have to pre-generate an ID.
    // Let's use the ID if we have it, else generate one that will be used for creation.
    final machineId = widget.machine?.id ?? DateTime.now().millisecondsSinceEpoch.toString();

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
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<MachinesProvider>();
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final contentType =
          file.mimeType ??
          lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
          _contentTypeFromExtension(file.name);
      
      final intent = await provider.createAssetUploadIntent(
        MachineAssetUploadIntentInput(
          machineId: machineId,
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
          isPrimary: true,
        ),
      );
      if (intent == null) {
        throw Exception(provider.errorMessage ?? 'Failed to prepare upload.');
      }
      if (intent.alreadyUploaded && intent.photoUrl != null) {
        _photoUrlController.text = intent.photoUrl!;
        messenger.showSnackBar(
          const SnackBar(content: Text('Image already uploaded.')),
        );
        return;
      }
      final upload = intent.upload;
      if (upload == null) {
        throw Exception('Upload target was not returned.');
      }
      if (upload.uploadUrl.host != 'mock.local') {
        final response = await http.put(
          upload.uploadUrl,
          headers: upload.headers,
          body: bytes,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'Image upload failed with status ${response.statusCode}.',
          );
        }
      }
      final finalUrl = await provider.completeAssetUpload(
        CompleteMachineAssetUploadInput(
          uploadSessionId: upload.uploadSessionId,
          objectKey: upload.objectKey,
          machineId: machineId,
        ),
      );
      if (finalUrl == null) {
        throw Exception(provider.errorMessage ?? 'Failed to finish upload.');
      }
      _photoUrlController.text = finalUrl;
      messenger.showSnackBar(
        const SnackBar(content: Text('Machine photo uploaded.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Image upload failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SearchableSelectField<int>(
                                tapTargetKey: const ValueKey<String>('machine-group-field'),
                                value: _groupId,
                                decoration: InputDecoration(
                                  labelText: 'Machine Group',
                                  helperText: 'Categorization from Group Master',
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
                                dialogTitle: 'Machine Group',
                                searchHintText: 'Search machine groups',
                                options: groups.map((g) => SearchableSelectOption<int>(
                                  value: g.id,
                                  label: g.name,
                                )).toList(),
                                onChanged: (val) => setState(() => _groupId = val),
                                validator: (val) => val == null ? 'Required' : null,
                                onCreateOption: (query) async {
                                  final created = await GroupsScreen.openEditor(
                                    context,
                                    initialName: query,
                                  );
                                  if (!context.mounted || created == null) {
                                    return null;
                                  }
                                  await context.read<GroupsProvider>().refresh();
                                  return SearchableSelectOption<int>(
                                    value: created.id,
                                    label: created.name,
                                  );
                                },
                                createOptionLabelBuilder: (query) => 'Create group "$query"',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SearchableSelectField<MachineStatus>(
                                tapTargetKey: const ValueKey<String>('machine-status-field'),
                                value: _status,
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                  helperText: 'Current operational state',
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
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ErpDialogSectionCard(
                    title: 'Custom Fields',
                    subtitle: 'Define any text field name and its corresponding value.',
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
                                          tapTargetKey: ValueKey<String>('machine-custom-property-type-$index'),
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
                                            tapTargetKey: ValueKey<String>('machine-custom-property-unit-$index'),
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
                                            tapTargetKey: ValueKey<String>('machine-custom-property-value-$index'),
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
                          label: 'Add Field',
                          icon: Icons.add,
                          variant: AppButtonVariant.secondary,
                          onPressed: _addCustomProperty,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCapabilitiesSection(context),
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

  Widget _buildCapabilitiesSection(BuildContext context) {
    return ErpDialogSectionCard(
      title: 'Capabilities — What This Machine Does',
      subtitle: 'Define the material transformations this machine can perform.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_capabilities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'No capabilities defined yet.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            )
          else
            ..._capabilities.asMap().entries.map((entry) {
              final index = entry.key;
              final cap = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Capability #${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _removeCapability(index),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            initialValue: cap.processType,
                            decoration: InputDecoration(
                              labelText: 'Process Type',
                              hintText: 'e.g. Slitting, Punching',
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                            ),
                            onChanged: (val) => setState(() => cap.processType = val),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            initialValue: cap.dieName,
                            decoration: InputDecoration(
                              labelText: 'Die/Tooling (Optional)',
                              hintText: 'e.g. Die-A',
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                            ),
                            onChanged: (val) => setState(() => cap.dieName = val),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.0),
                      child: Divider(height: 1),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('INPUT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B))),
                              const SizedBox(height: 8),
                              SearchableSelectField<String>(
                                tapTargetKey: ValueKey<String>('machine-cap-input-mat-$index'),
                                value: cap.inputMaterialBarcode.isEmpty ? null : cap.inputMaterialBarcode,
                                decoration: const InputDecoration(labelText: 'Material', filled: true, fillColor: Color(0xFFF9FAFB)),
                                dialogTitle: 'Select Input Material',
                                options: context.watch<InventoryProvider>().materials.map((m) {
                                  return SearchableSelectOption<String>(value: m.barcode, label: '${m.name} (${m.barcode})');
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      cap.inputMaterialBarcode = val;
                                      cap.inputMaterialName = context.read<InventoryProvider>().materials.firstWhere((m) => m.barcode == val).name;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 8),
                              SearchableSelectField<int>(
                                tapTargetKey: ValueKey<String>('machine-cap-input-unit-$index'),
                                value: cap.inputUnitId,
                                decoration: const InputDecoration(labelText: 'Unit', filled: true, fillColor: Color(0xFFF9FAFB)),
                                dialogTitle: 'Select Input Unit',
                                options: context.watch<UnitsProvider>().activeUnits.map((u) {
                                  return SearchableSelectOption<int>(value: u.id, label: u.symbol);
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => cap.inputUnitId = val);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(Icons.arrow_forward, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('OUTPUT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B))),
                              const SizedBox(height: 8),
                              SearchableSelectField<String>(
                                tapTargetKey: ValueKey<String>('machine-cap-output-mat-$index'),
                                value: cap.outputMaterialBarcode.isEmpty ? null : cap.outputMaterialBarcode,
                                decoration: const InputDecoration(labelText: 'Material', filled: true, fillColor: Color(0xFFF9FAFB)),
                                dialogTitle: 'Select Output Material',
                                options: context.watch<InventoryProvider>().materials.map((m) {
                                  return SearchableSelectOption<String>(value: m.barcode, label: '${m.name} (${m.barcode})');
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      cap.outputMaterialBarcode = val;
                                      cap.outputMaterialName = context.read<InventoryProvider>().materials.firstWhere((m) => m.barcode == val).name;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 8),
                              SearchableSelectField<int>(
                                tapTargetKey: ValueKey<String>('machine-cap-output-unit-$index'),
                                value: cap.outputUnitId,
                                decoration: const InputDecoration(labelText: 'Unit', filled: true, fillColor: Color(0xFFF9FAFB)),
                                dialogTitle: 'Select Output Unit',
                                options: context.watch<UnitsProvider>().activeUnits.map((u) {
                                  return SearchableSelectOption<int>(value: u.id, label: u.symbol);
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => cap.outputUnitId = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.0),
                      child: Divider(height: 1),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: cap.expectedYieldRatio?.toString(),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Yield % (Optional)',
                              hintText: 'e.g. 0.95',
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                            ),
                            onChanged: (val) => setState(() => cap.expectedYieldRatio = double.tryParse(val)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: cap.conversionFactor?.toString(),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Conversion Factor',
                              hintText: 'e.g. 150',
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                            ),
                            onChanged: (val) => setState(() => cap.conversionFactor = double.tryParse(val)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: cap.durationPerUnit?.toString(),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Hrs/Unit',
                              hintText: 'e.g. 0.05',
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD7DBE7))),
                            ),
                            onChanged: (val) => setState(() => cap.durationPerUnit = double.tryParse(val)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 12),
          AppButton(
            label: 'Add Capability',
            icon: Icons.add,
            variant: AppButtonVariant.secondary,
            onPressed: _addCapability,
          ),
        ],
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

    final capabilitiesList = <MachineCapability>[];
    for (var cap in _capabilities) {
      if (cap.processType.trim().isNotEmpty && cap.inputUnitId != null && cap.outputUnitId != null) {
        capabilitiesList.add(MachineCapability(
          id: cap.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
          processType: cap.processType.trim(),
          inputMaterialBarcode: cap.inputMaterialBarcode.trim(),
          inputMaterialName: cap.inputMaterialName.trim(),
          inputUnitId: cap.inputUnitId!,
          inputUnitLabel: context.read<UnitsProvider>().findById(cap.inputUnitId)?.symbol ?? '',
          outputMaterialBarcode: cap.outputMaterialBarcode.trim(),
          outputMaterialName: cap.outputMaterialName.trim(),
          outputUnitId: cap.outputUnitId!,
          outputUnitLabel: context.read<UnitsProvider>().findById(cap.outputUnitId)?.symbol ?? '',
          dieId: cap.dieId?.trim().isEmpty ?? true ? null : cap.dieId?.trim(),
          dieName: cap.dieName?.trim().isEmpty ?? true ? null : cap.dieName?.trim(),
          expectedYieldRatio: cap.expectedYieldRatio,
          conversionFactor: cap.conversionFactor,
          durationPerUnit: cap.durationPerUnit,
        ));
      }
    }

    // If we're creating a new machine, use the ID we might have generated during image upload
    // If _photoUrlController has text and we generated an ID, let's just use a timestamp if we didn't store it.
    // Wait, the id generation should be consistent.
    final id = widget.machine?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    final newMachine = Machine(
      id: id,
      name: _nameController.text.trim(),
      assetId: _assetIdController.text.trim(),
      primaryPhotoUrl: _photoUrlController.text.trim(),
      groupId: _groupId,
      makeModel: '',
      serialNumber: '',
      location: null,
      installationDate: null,
      status: _status,
      customProperties: customPropsList,
      capabilities: capabilitiesList,
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
            errorBuilder: (_, _, _) => _buildPlaceholderUploadBox(),
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
            isLoading: _isUploading,
            onPressed: _pickAndUploadImage,
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
