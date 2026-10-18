import 'package:core_erp/features/variations/data/variation_tree_service.dart';
import 'package:core_erp/features/variations/presentation/widgets/variation_tree_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/core/widgets/erp_form_dialog.dart';
import 'package:core_erp/core/utils/stamp_format.dart';
import 'package:core_erp/core/widgets/length_unit_field.dart';
import 'package:core_erp/features/dies/domain/die_code.dart';
import 'package:core_erp/core/widgets/searchable_select.dart';
import '../../domain/die.dart';
import '../providers/die_provider.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:paper/features/machines/domain/machine.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/core/navigation/app_navigation.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/clients/domain/client_definition.dart';
import 'package:core_erp/features/clients/presentation/screens/clients_screen.dart';

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
  const DieEditorSheet({super.key, this.die, this.onSaved, this.onCancel});

  final Die? die;

  /// Set when a host embeds the editor instead of opening it as a route: gets
  /// the saved die in place of `Navigator.pop`.
  final ValueChanged<Die>? onSaved;

  /// Set alongside [onSaved]; replaces closing the route on Cancel / close.
  final VoidCallback? onCancel;

  @override
  State<DieEditorSheet> createState() => _DieEditorSheetState();
}

class _DieEditorSheetState extends State<DieEditorSheet> {
  /// The die's variation tree. Held here rather than saved as it is typed: a
  /// die being created has no id to hang a tree off until its own save returns
  /// one, so the tree goes up right after the die does.
  VariationTreeController? _variations;

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _toolCodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _operationalNotesController;
  late final TextEditingController _storageLocationController;

  // The die sheet (migrations/048). The pair below REPLACES the free-text
  // location for anything written from now on; the old field stays visible so
  // a die that predates them still says where it is.
  late final TextEditingController _storeAreaController;
  late final TextEditingController _rackNoController;
  late final TextEditingController _madeByController;
  late final TextEditingController _noOfSetController;
  late final TextEditingController _linerSizeController;
  String _linerSizeUnit = 'mm';
  String? _linerSizeError;
  DieType? _dieType;
  DateTime? _poAt;
  DateTime? _dateInAt;
  late final TextEditingController _numberOfCavitiesController;
  late final TextEditingController _maxStrokesController;
  late final TextEditingController _setupMinutesController;
  late final TextEditingController _reportNotesController;

  DieStatus _status = DieStatus.ready;
  DieOwnership _ownership = DieOwnership.inHouse;
  bool _isUploading = false;
  int? _clientId;

  // Custom properties as a list of mutable objects for editing
  final List<_MutableProperty> _customProperties = [];

  // Compatible groups
  final List<int> _compatibleMachineGroupIds = [];

  // Multiple photos
  final List<String> _photoUrls = [];

  @override
  void initState() {
    super.initState();
    // Optional: a host that has not registered the service simply gets no
    // Variations section, the way the rest of this form treats its hooks.
    try {
      final service = context.read<VariationTreeService>();
      final controller = VariationTreeController(service: service, type: 'die');
      _variations = controller;
      final existing = widget.die?.id ?? '';
      if (existing.isNotEmpty) {
        Future<void>.microtask(() => controller.load(existing));
      }
    } catch (_) {
      _variations = null;
    }
    _toolCodeController = TextEditingController(
      text: widget.die?.toolCode ?? '',
    );
    _nameController = TextEditingController(text: widget.die?.name ?? '');
    _operationalNotesController = TextEditingController(
      text: widget.die?.operationalNotes ?? '',
    );
    _storageLocationController = TextEditingController(
      text: widget.die?.storageLocation ?? '',
    );
    _storeAreaController = TextEditingController(
      text: widget.die?.storeArea ?? '',
    );
    _rackNoController = TextEditingController(text: widget.die?.rackNo ?? '');
    _madeByController = TextEditingController(text: widget.die?.madeBy ?? '');
    _noOfSetController = TextEditingController(
      text: widget.die?.noOfSet?.toString() ?? '',
    );
    _linerSizeUnit = widget.die?.linerSizeUnit ?? 'mm';
    _linerSizeController = TextEditingController(
      text: formatLengthFromNanometres(widget.die?.linerSizeNm, _linerSizeUnit),
    );
    _dieType = DieType.fromSlug(widget.die?.dieType);
    _poAt = widget.die?.poAt;
    _dateInAt = widget.die?.dateInAt;
    _numberOfCavitiesController = TextEditingController(
      text: widget.die?.numberOfCavities?.toString() ?? '',
    );
    _maxStrokesController = TextEditingController(
      text: widget.die?.maxStrokes?.toString() ?? '',
    );
    _setupMinutesController = TextEditingController(
      text: _formatOptionalNumber(widget.die?.setupMinutes),
    );
    _reportNotesController = TextEditingController(
      text: widget.die?.reportNotes ?? '',
    );

    if (widget.die != null) {
      _status = widget.die!.status;
      _ownership = widget.die!.ownership;
      _clientId = widget.die!.clientId;
      _photoUrls.addAll(widget.die!.photoUrls);
      _compatibleMachineGroupIds.addAll(widget.die!.compatibleMachineGroupIds);

      for (var prop in widget.die!.physicalSpecs) {
        String key = prop.key;
        if (key == 'bedSize') key = 'Bed Size';
        if (key == 'tonnage') key = 'Tonnage Req.';
        if (key == 'shutHeight') key = 'Shut Height';

        _customProperties.add(
          _MutableProperty(
            key: key,
            value: prop.value,
            type: prop.type,
            unitId: prop.unitId,
            options: List.from(prop.options),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _variations?.dispose();
    _toolCodeController.dispose();
    _nameController.dispose();
    _operationalNotesController.dispose();
    _storageLocationController.dispose();
    _storeAreaController.dispose();
    _rackNoController.dispose();
    _madeByController.dispose();
    _noOfSetController.dispose();
    _linerSizeController.dispose();
    _numberOfCavitiesController.dispose();
    _maxStrokesController.dispose();
    _setupMinutesController.dispose();
    _reportNotesController.dispose();
    super.dispose();
  }

  String _formatOptionalNumber(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  double? _optionalDouble(TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  int? _optionalInt(TextEditingController controller) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    return int.tryParse(value);
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
          !_customProperties[index].options.contains(
            _customProperties[index].value,
          )) {
        _customProperties[index].value = '';
      }
    });
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
    final dieId =
        widget.die?.id ?? DateTime.now().millisecondsSinceEpoch.toString();

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
    final provider = context.read<DiesProvider>();
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final contentType =
          file.mimeType ??
          lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
          _contentTypeFromExtension(file.name);

      final intent = await provider.createAssetUploadIntent(
        DieAssetUploadIntentInput(
          dieId: dieId,
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
          isPrimary: _photoUrls.isEmpty,
        ),
      );
      if (intent == null) {
        throw Exception(provider.errorMessage ?? 'Failed to prepare upload.');
      }
      if (intent.alreadyUploaded && intent.photoUrl != null) {
        setState(() {
          _photoUrls.add(intent.photoUrl!);
        });
        showAppSnack(const SnackBar(content: Text('Image already uploaded.')));
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
        CompleteDieAssetUploadInput(
          uploadSessionId: upload.uploadSessionId,
          objectKey: upload.objectKey,
          dieId: dieId,
        ),
      );
      if (finalUrl == null) {
        throw Exception(provider.errorMessage ?? 'Failed to finish upload.');
      }
      setState(() {
        _photoUrls.add(finalUrl);
      });
      showAppSnack(const SnackBar(content: Text('Die photo uploaded.')));
    } catch (error) {
      showAppSnack(SnackBar(content: Text('Image upload failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
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
    final groups = context.watch<GroupsProvider>().machineGroups;
    final clients = context.watch<ClientsProvider>().clients;

    return Form(
      key: _formKey,
      child: ErpFormScaffold(
        onClose: widget.onCancel,
        title: title,
        // Embedded in the creation wizard, the title is enough.
        subtitle: widget.onSaved != null
            ? null
            : 'Manage die/tooling details, machine compatibilities, and photos.',
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
                    subtitle:
                        'Core information for tracking the tool and the parts it produces.',
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
                        _dieSheetFields(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DieTextField(
                                controller: _storageLocationController,
                                label: 'Storage Rack / Location (old)',
                                helper:
                                    'Only for dies made before Store Area and '
                                    'Rack No. existed',
                                required: false,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SearchableSelectField<int>(
                                tapTargetKey: const ValueKey(
                                  'die-client-field',
                                ),
                                value: _clientId,
                                decoration: const InputDecoration(
                                  labelText: 'Client (Optional)',
                                  helperText: 'Associated customer',
                                  filled: true,
                                  fillColor: Color(0xFFF9FAFB),
                                ),
                                dialogTitle: 'Select Client',
                                options: [
                                  const SearchableSelectOption<int>(
                                    value: 0,
                                    label: 'None / In-House',
                                  ),
                                  ...clients.map(
                                    (c) => SearchableSelectOption<int>(
                                      value: c.id,
                                      label: c.displayLabel,
                                    ),
                                  ),
                                ],
                                canCreateOption: (query, allOptions) {
                                  if (query.trim().isEmpty) return false;
                                  return !allOptions.any(
                                    (opt) =>
                                        opt.label.toLowerCase() ==
                                        query.trim().toLowerCase(),
                                  );
                                },
                                onCreateOption: (query) async {
                                  final client = await ClientsScreen.openEditor(
                                    context,
                                    initialName: query,
                                  );
                                  if (client == null || !mounted) return null;
                                  // Refresh provider manually or just let it react if it's already watching
                                  try {
                                    await context
                                        .read<ClientsProvider>()
                                        .refresh();
                                  } catch (_) {}
                                  return SearchableSelectOption<int>(
                                    value: client.id,
                                    label: client.displayLabel,
                                  );
                                },
                                createOptionLabelBuilder: (query) =>
                                    'Create new client "$query"',
                                onChanged: (val) {
                                  setState(() {
                                    _clientId = (val == 0) ? null : val;
                                  });
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
                    title: 'Machine Compatibility',
                    subtitle: 'Determine where the die can run.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SearchableSelectField<int>(
                          tapTargetKey: const ValueKey<String>(
                            'die-add-machine-group-field',
                          ),
                          decoration: InputDecoration(
                            labelText: 'Add Compatible Machine Group',
                            helperText:
                                'Select group to add compatible machine groups',
                            suffixIcon: TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                try {
                                  context.read<AppNavigation>().select(
                                    'configurator_machine_groups',
                                  );
                                } catch (_) {}
                              },
                              child: const Text('Manage'),
                            ),
                          ),
                          dialogTitle: 'Select Machine Group',
                          options: groups
                              .where(
                                (g) =>
                                    !_compatibleMachineGroupIds.contains(g.id),
                              )
                              .map(
                                (g) => SearchableSelectOption<int>(
                                  value: g.id,
                                  label: g.name,
                                  highlightColor: const Color(0xFFE4C17C),
                                ),
                              )
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
                    title: 'Report Defaults',
                    subtitle:
                        'Non-financial tooling assumptions used to print order reports.',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _DieTextField(
                                controller: _numberOfCavitiesController,
                                label: 'Cavities',
                                helper: 'Pieces produced per stroke',
                                required: false,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DieTextField(
                                controller: _maxStrokesController,
                                label: 'Expected Life',
                                helper: 'Total rated strokes',
                                required: false,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DieTextField(
                                controller: _setupMinutesController,
                                label: 'Setup Minutes',
                                helper: 'Default mounting time',
                                required: false,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _DieTextField(
                          controller: _reportNotesController,
                          label: 'Report Notes',
                          helper: 'Setup notes printed with formulas',
                          required: false,
                        ),
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
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
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
                                            hintText:
                                                'e.g. Tonnage, Location, etc.',
                                            filled: true,
                                            fillColor: const Color(0xFFF9FAFB),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                color: Color(0xFFD7DBE7),
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                color: Color(0xFFD7DBE7),
                                              ),
                                            ),
                                          ),
                                          onChanged: (val) =>
                                              _updateCustomPropertyKey(
                                                index,
                                                val,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child:
                                            SearchableSelectField<
                                              CustomPropertyType
                                            >(
                                              tapTargetKey: ValueKey<String>(
                                                'die-custom-property-type-$index',
                                              ),
                                              value: prop.type,
                                              decoration: const InputDecoration(
                                                labelText: 'Field Type',
                                                filled: true,
                                                fillColor: Color(0xFFF9FAFB),
                                              ),
                                              dialogTitle: 'Field Type',
                                              options: const [
                                                SearchableSelectOption(
                                                  value:
                                                      CustomPropertyType.text,
                                                  label: 'Text',
                                                ),
                                                SearchableSelectOption(
                                                  value: CustomPropertyType
                                                      .numeric,
                                                  label: 'Numeric',
                                                ),
                                                SearchableSelectOption(
                                                  value: CustomPropertyType
                                                      .dropdown,
                                                  label: 'Dropdown',
                                                ),
                                              ],
                                              onChanged: (val) {
                                                if (val != null) {
                                                  _updateCustomPropertyType(
                                                    index,
                                                    val,
                                                  );
                                                }
                                              },
                                            ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: () =>
                                            _removeCustomProperty(index),
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
                                              fillColor: const Color(
                                                0xFFF9FAFB,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFFD7DBE7),
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFFD7DBE7),
                                                ),
                                              ),
                                            ),
                                            onChanged: (val) =>
                                                _updateCustomPropertyValue(
                                                  index,
                                                  val,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 48),
                                      ],
                                    )
                                  else if (prop.type ==
                                      CustomPropertyType.numeric)
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: SearchableSelectField<int?>(
                                            tapTargetKey: ValueKey<String>(
                                              'die-custom-property-unit-$index',
                                            ),
                                            value: prop.unitId,
                                            decoration: const InputDecoration(
                                              labelText: 'Unit (Optional)',
                                              filled: true,
                                              fillColor: Color(0xFFF9FAFB),
                                            ),
                                            dialogTitle: 'Select Unit',
                                            options: [
                                              const SearchableSelectOption<
                                                int?
                                              >(value: null, label: 'None'),
                                              ...context
                                                  .watch<UnitsProvider>()
                                                  .activeUnits
                                                  .map((u) {
                                                    return SearchableSelectOption<
                                                      int?
                                                    >(
                                                      value: u.id,
                                                      label: u.symbol,
                                                    );
                                                  }),
                                            ],
                                            onChanged: (val) =>
                                                _updateCustomPropertyUnit(
                                                  index,
                                                  val,
                                                ),
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
                                              hintText:
                                                  'Enter numeric value...',
                                              filled: true,
                                              fillColor: const Color(
                                                0xFFF9FAFB,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFFD7DBE7),
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFFD7DBE7),
                                                ),
                                              ),
                                            ),
                                            onChanged: (val) =>
                                                _updateCustomPropertyValue(
                                                  index,
                                                  val,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 48),
                                      ],
                                    )
                                  else if (prop.type ==
                                      CustomPropertyType.dropdown)
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: TextFormField(
                                            initialValue: prop.options.join(
                                              ', ',
                                            ),
                                            decoration: InputDecoration(
                                              labelText: 'Dropdown Options',
                                              hintText:
                                                  'A, B, C (comma separated)',
                                              filled: true,
                                              fillColor: const Color(
                                                0xFFF9FAFB,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFFD7DBE7),
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFFD7DBE7),
                                                ),
                                              ),
                                            ),
                                            onChanged: (val) =>
                                                _updateCustomPropertyOptions(
                                                  index,
                                                  val,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 3,
                                          child: SearchableSelectField<String>(
                                            tapTargetKey: ValueKey<String>(
                                              'die-custom-property-value-$index',
                                            ),
                                            value:
                                                prop.options.contains(
                                                  prop.value,
                                                )
                                                ? prop.value
                                                : null,
                                            decoration: const InputDecoration(
                                              labelText: 'Select Value',
                                              filled: true,
                                              fillColor: Color(0xFFF9FAFB),
                                            ),
                                            dialogTitle: 'Select Value',
                                            options: prop.options.map((opt) {
                                              return SearchableSelectOption<
                                                String
                                              >(value: opt, label: opt);
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) {
                                                _updateCustomPropertyValue(
                                                  index,
                                                  val,
                                                );
                                              }
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
                    subtitle:
                        'Multiple images of the die, setup conditions, or parts.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              style: BorderStyle.solid,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.collections_outlined,
                                size: 32,
                                color: Color(0xFF94A3B8),
                              ),
                              const SizedBox(height: 8),
                              AppButton(
                                label: 'Upload New Photo',
                                variant: AppButtonVariant.secondary,
                                isLoading: _isUploading,
                                onPressed: _pickAndUploadImage,
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
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.broken_image,
                                        size: 24,
                                        color: Colors.grey,
                                      ),
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
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _removePhoto(index),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  if (_variations case final variations?) ...[
                    const SizedBox(height: 16),
                    ErpDialogSectionCard(
                      title: 'Variations',
                      subtitle:
                          'What this die varies by, and what each one can be. '
                          'Items derived from it are derived under the version '
                          'shown.',
                      child: VariationTreeEditor(
                        controller: variations,
                        // Only offered once the die exists: a version is
                        // declared against a record, and a die being created
                        // has nothing yet to declare against.
                        onDeclareVersion: (widget.die?.id ?? '').isEmpty
                            ? null
                            : () => _declareVariationVersion(variations),
                      ),
                    ),
                  ],
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
              onPressed:
                  widget.onCancel ?? () => Navigator.of(context).maybePop(),
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

  Future<void> _declareVariationVersion(
    VariationTreeController variations,
  ) async {
    final dieId = widget.die?.id ?? '';
    if (dieId.isEmpty) return;
    await showDeclareVersionDialog(
      context,
      controller: variations,
      entityId: dieId,
      nextVersion: variations.version + 1,
    );
  }


  /// The die sheet the floor keeps: who made it, what kind, how big, how many,
  /// and where it sits. Added with migration 048 — a die made from the Quick
  /// entry wizard fills these in, and this is where they get corrected.
  Widget _dieSheetFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 110,
              child: Text(
                'Type',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in DieType.values)
                    ChoiceChip(
                      label: Text(
                        type.label,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      selected: _dieType == type,
                      onSelected: (selected) =>
                          setState(() => _dieType = selected ? type : null),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DieTextField(
                controller: _madeByController,
                label: 'Die Made By',
                helper: 'A fitter here, or an outside toolroom',
                required: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DieTextField(
                controller: _noOfSetController,
                label: 'No. of Sets',
                helper: 'How many sets were made',
                required: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LengthUnitField(
          controller: _linerSizeController,
          unitSymbol: _linerSizeUnit,
          label: 'Liner Size',
          helperText: 'Optional',
          errorText: _linerSizeError,
          onUnitChanged: (symbol) => setState(() {
            _linerSizeUnit = symbol;
            _linerSizeError = null;
          }),
          onChanged: () {
            final parsed = parseLengthToNanometres(
              _linerSizeController.text,
              _linerSizeUnit,
            );
            if (parsed.error != _linerSizeError) {
              setState(() => _linerSizeError = parsed.error);
            }
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DieTextField(
                controller: _storeAreaController,
                label: 'Store Area',
                helper: 'E.g. F206',
                required: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DieTextField(
                controller: _rackNoController,
                label: 'Rack No.',
                helper: 'E.g. 23-4',
                required: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _dieMomentRow(
          label: 'PO Date & Time',
          value: _poAt,
          onPicked: (value) => setState(() => _poAt = value),
          onCleared: () => setState(() => _poAt = null),
        ),
        const SizedBox(height: 8),
        _dieMomentRow(
          label: 'Date In & Time',
          value: _dateInAt,
          onPicked: (value) => setState(() => _dateInAt = value),
          onCleared: () => setState(() => _dateInAt = null),
        ),
      ],
    );
  }

  Widget _dieMomentRow({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onPicked,
    required VoidCallback onCleared,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final seed = value?.toLocal() ?? DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    initialDate: seed,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(seed.year + 10),
                  );
                  if (date == null || !mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(seed),
                  );
                  if (!mounted) return;
                  onPicked(
                    DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time?.hour ?? seed.hour,
                      time?.minute ?? seed.minute,
                    ),
                  );
                },
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  // Through partStamp: the instant is UTC, and a shop at
                  // +05:30 must not read 11.30 AM as 6.00 AM.
                  value == null ? 'Pick' : partStamp(value),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (value != null)
                TextButton(
                  onPressed: onCleared,
                  child: const Text('Clear', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Construct Custom Properties list
    final customPropsList = <CustomProperty>[];
    for (var prop in _customProperties) {
      if (prop.key.trim().isNotEmpty) {
        customPropsList.add(
          CustomProperty(
            key: prop.key.trim(),
            value: prop.value.trim(),
            type: prop.type,
            unitId: prop.unitId,
            options: prop.options,
          ),
        );
      }
    }

    final id = widget.die?.id ?? '';

    final newDie = Die(
      id: id,
      name: _nameController.text.trim(),
      toolCode: _toolCodeController.text.trim(),
      photoUrls: _photoUrls,
      operationalNotes: _operationalNotesController.text.trim(),
      compatibleMachineGroupIds: _compatibleMachineGroupIds,
      strokeCount: widget.die?.strokeCount ?? 0,
      storageLocation: _storageLocationController.text.trim(),
      numberOfCavities: _optionalInt(_numberOfCavitiesController),
      maxStrokes: _optionalInt(_maxStrokesController),
      // No longer asked for on this form. Preserved so editing a die that
      // already carries one does not silently clear it.
      strokesPerPiece: widget.die?.strokesPerPiece,
      setupMinutes: _optionalDouble(_setupMinutesController),
      reportNotes: _reportNotesController.text.trim(),
      physicalSpecs: customPropsList,
      status: _status,
      ownership: _ownership,
      clientId: _clientId,
      dieType: _dieType?.slug ?? '',
      madeBy: _madeByController.text.trim(),
      poAt: _poAt,
      dateInAt: _dateInAt,
      linerSizeNm: parseLengthToNanometres(
        _linerSizeController.text,
        _linerSizeUnit,
      ).nanometres,
      linerSizeUnit: _linerSizeUnit,
      noOfSet: _optionalInt(_noOfSetController),
      storeArea: _storeAreaController.text.trim(),
      rackNo: _rackNoController.text.trim(),
      createdAt: widget.die?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Die? savedDie;
    if (widget.die == null) {
      savedDie = await context.read<DiesProvider>().createDie(newDie);
    } else {
      savedDie = await context.read<DiesProvider>().updateDie(newDie);
    }

    if (savedDie == null && mounted) {
      final error =
          context.read<DiesProvider>().errorMessage ?? 'Failed to save die';
      showAppSnack(SnackBar(content: Text(error), backgroundColor: Colors.red));
      return;
    }

    // The tree goes up straight after the die, now that there is an id to
    // hang it on. A refusal is reported and the die stays saved: the two are
    // separate records, and losing the die because its tree was locked would
    // be the wrong trade.
    final variations = _variations;
    if (variations != null && savedDie != null) {
      final failure = await variations.save(savedDie.id);
      if (failure != null && mounted) {
        showAppToast(context, failure, kind: AppToastKind.error);
      }
    }

    if (mounted) {
      showAppToast(
        context,
        widget.die == null ? 'Die created' : 'Die saved',
        kind: AppToastKind.success,
      );
      final onSaved = widget.onSaved;
      if (onSaved != null) {
        onSaved(savedDie!);
      } else {
        Navigator.of(context).pop(savedDie);
      }
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
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
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
