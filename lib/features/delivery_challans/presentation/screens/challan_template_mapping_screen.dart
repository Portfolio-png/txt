import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../vendors/presentation/providers/vendors_provider.dart';
import '../../domain/challan_template.dart';
import '../../domain/delivery_challan.dart';
import '../providers/delivery_challan_provider.dart';

class TemplateMappingScreen extends StatefulWidget {
  const TemplateMappingScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<TemplateMappingScreen> createState() => _TemplateMappingScreenState();
}

class _TemplateMappingScreenState extends State<TemplateMappingScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<ChallanTemplate> _templates = const <ChallanTemplate>[];
  List<ChallanTemplateMapping> _mappings = <ChallanTemplateMapping>[];
  ChallanTemplate? _selectedTemplate;
  ChallanTemplatePartyType _partyType = ChallanTemplatePartyType.client;
  ChallanType _challanType = ChallanType.delivery;
  int? _partyId;
  String _backgroundObjectKey = '';
  String? _backgroundImageUrl;
  Uint8List? _localBackgroundBytes;
  final Map<String, Uint8List> _localStampBytesByObjectKey =
      <String, Uint8List>{};
  int _canvasWidth = 0;
  int _canvasHeight = 0;
  double _rotationDegrees = 0;
  double _globalOffsetXmm = 0;
  double _globalOffsetYmm = 0;
  bool _showGrid = false;
  bool _showScaleCheck = false;
  double _screenScale = 1;
  bool _showBoundingBoxes = true;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _selectedFieldKey;
  String? _selectedMappingFieldKey;
  String? _error;

  static const _fields = <_TemplateField>[
    _TemplateField('challan_no', 'Challan No'),
    _TemplateField('date', 'Date'),
    _TemplateField('party_name', 'Party Name'),
    _TemplateField('gstin', 'GSTIN'),
    _TemplateField('location', 'Location'),
    _TemplateField('source_ref', 'Source Ref'),
    _TemplateField('total_qty', 'Total Qty'),
    _TemplateField('notes', 'Notes'),
    _TemplateField('item_particulars', 'Item Particulars', isTable: true),
    _TemplateField('hsn', 'HSN', isTable: true),
    _TemplateField('qty_pcs', 'Qty Pcs', isTable: true),
    _TemplateField('weight', 'Weight', isTable: true),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitial();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    await Future.wait([
      context.read<ClientsProvider>().initialize(),
      context.read<VendorsProvider>().initialize(),
    ]);
    await _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final templates = await context
        .read<DeliveryChallanProvider>()
        .loadTemplates();
    if (!mounted) {
      return;
    }
    setState(() {
      _templates = templates;
      _isLoading = false;
      if (_selectedTemplate == null && templates.isNotEmpty) {
        _applyTemplate(templates.first);
      }
    });
  }

  void _applyTemplate(ChallanTemplate template) {
    _selectedTemplate = template;
    _nameController.text = template.name;
    _partyType = template.partyType;
    _partyId = template.partyId;
    _challanType = template.challanType;
    _backgroundObjectKey = template.backgroundObjectKey;
    _backgroundImageUrl = template.backgroundImageUrl;
    _localBackgroundBytes = null;
    _canvasWidth = template.canvasWidth;
    _canvasHeight = template.canvasHeight;
    _rotationDegrees = template.rotationDegrees;
    _globalOffsetXmm = template.globalOffsetXmm;
    _globalOffsetYmm = template.globalOffsetYmm;
    _mappings = template.mappings.toList();
    _selectedMappingFieldKey = _mappings.isEmpty
        ? null
        : _mappings.first.fieldKey;
    _selectedFieldKey = null;
  }

  void _startNewTemplate() {
    setState(() {
      _selectedTemplate = null;
      _nameController.clear();
      _partyType = ChallanTemplatePartyType.client;
      _challanType = ChallanType.delivery;
      _partyId = null;
      _backgroundObjectKey = '';
      _backgroundImageUrl = null;
      _localBackgroundBytes = null;
      _canvasWidth = 0;
      _canvasHeight = 0;
      _rotationDegrees = 0;
      _globalOffsetXmm = 0;
      _globalOffsetYmm = 0;
      _showScaleCheck = false;
      _screenScale = 1;
      _mappings = <ChallanTemplateMapping>[];
      _selectedFieldKey = null;
      _selectedMappingFieldKey = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 14),
        if (_error != null) ...[
          _ErrorBanner(message: _error!),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1100;
              if (compact) {
                return ListView(
                  children: [
                    _buildLeftPanel(),
                    const SizedBox(height: 12),
                    SizedBox(height: 640, child: _buildCanvasPanel()),
                    const SizedBox(height: 12),
                    _buildRightPanel(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 300, child: _buildLeftPanel()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildCanvasPanel()),
                  const SizedBox(width: 12),
                  SizedBox(width: 280, child: _buildRightPanel()),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppButton(
          label: 'Back',
          icon: Icons.arrow_back_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: widget.onBack,
        ),
        Text(
          'Challan Templates',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: SoftErpTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        AppButton(
          label: 'New Template',
          icon: Icons.add_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: _startNewTemplate,
        ),
        AppButton(
          label: 'Save Template',
          icon: Icons.save_outlined,
          isLoading: _isSaving,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _buildLeftPanel() {
    final clients = context.watch<ClientsProvider>().filteredClients;
    final vendors = context.watch<VendorsProvider>().filteredVendors;
    final partyItems = _partyType == ChallanTemplatePartyType.client
        ? clients
              .map(
                (client) => DropdownMenuItem<int>(
                  value: client.id,
                  child: Text(client.name),
                ),
              )
              .toList()
        : vendors
              .map(
                (vendor) => DropdownMenuItem<int>(
                  value: vendor.id,
                  child: Text(vendor.name),
                ),
              )
              .toList();

    return SoftSurface(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text(
            'Template Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedTemplate?.id,
            decoration: const InputDecoration(labelText: 'Existing templates'),
            items: _templates
                .map(
                  (template) => DropdownMenuItem<int>(
                    value: template.id,
                    child: Text(template.name),
                  ),
                )
                .toList(),
            onChanged: (id) {
              final template = _templates.firstWhere((entry) => entry.id == id);
              setState(() => _applyTemplate(template));
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Template Name'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ChallanTemplatePartyType>(
            selected: {_partyType},
            segments: const [
              ButtonSegment(
                value: ChallanTemplatePartyType.client,
                label: Text('Client'),
              ),
              ButtonSegment(
                value: ChallanTemplatePartyType.vendor,
                label: Text('Vendor'),
              ),
            ],
            onSelectionChanged: (value) {
              setState(() {
                _partyType = value.first;
                _partyId = null;
                _challanType = _partyType == ChallanTemplatePartyType.vendor
                    ? ChallanType.reception
                    : ChallanType.delivery;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: partyItems.any((item) => item.value == _partyId)
                ? _partyId
                : null,
            decoration: InputDecoration(
              labelText: _partyType == ChallanTemplatePartyType.client
                  ? 'Client'
                  : 'Vendor',
            ),
            items: partyItems,
            onChanged: (value) => setState(() => _partyId = value),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ChallanType>(
            selected: {_challanType},
            segments: const [
              ButtonSegment(
                value: ChallanType.delivery,
                label: Text('Delivery'),
              ),
              ButtonSegment(
                value: ChallanType.reception,
                label: Text('Reception'),
              ),
            ],
            onSelectionChanged: (value) =>
                setState(() => _challanType = value.first),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: _backgroundObjectKey.isEmpty
                ? 'Upload Scan'
                : 'Replace Scan',
            icon: Icons.upload_file_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: _pickAndUploadBackground,
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showGrid,
            onChanged: (value) => setState(() => _showGrid = value),
            title: const Text('Calibration Grid'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showBoundingBoxes,
            onChanged: (value) => setState(() => _showBoundingBoxes = value),
            title: const Text('Bounding Boxes'),
            subtitle: const Text('Show field extents for overlap checks.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showScaleCheck,
            onChanged: (value) => setState(() => _showScaleCheck = value),
            title: const Text('Scale Check'),
            subtitle: const Text(
              'Hold a physical ruler to the 10cm square and tune zoom.',
            ),
          ),
          if (_showScaleCheck)
            _NumberSlider(
              label: 'Screen Scale',
              value: _screenScale,
              min: 0.5,
              max: 1.5,
              divisions: 100,
              suffix: 'x',
              onChanged: (value) => setState(() => _screenScale = value),
            ),
          _NumberSlider(
            label: 'Rotate',
            value: _rotationDegrees,
            min: -5,
            max: 5,
            divisions: 20,
            suffix: 'deg',
            onChanged: (value) => setState(() => _rotationDegrees = value),
          ),
          _NumberSlider(
            label: 'X Offset',
            value: _globalOffsetXmm,
            min: -20,
            max: 20,
            divisions: 80,
            suffix: 'mm',
            onChanged: (value) => setState(() => _globalOffsetXmm = value),
          ),
          _NumberSlider(
            label: 'Y Offset',
            value: _globalOffsetYmm,
            min: -20,
            max: 20,
            divisions: 80,
            suffix: 'mm',
            onChanged: (value) => setState(() => _globalOffsetYmm = value),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasPanel() {
    return SoftSurface(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: AspectRatio(
          aspectRatio: _canvasWidth > 0 && _canvasHeight > 0
              ? _canvasWidth / _canvasHeight
              : 210 / 297,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (details) {
                  final key = _selectedFieldKey;
                  if (key == null) {
                    return;
                  }
                  final x = (details.localPosition.dx / constraints.maxWidth)
                      .clamp(0.0, 1.0);
                  final y = (details.localPosition.dy / constraints.maxHeight)
                      .clamp(0.0, 1.0);
                  _placeField(key, x, y);
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: SoftErpTheme.border),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Transform.rotate(
                          angle: _rotationDegrees * 3.141592653589793 / 180,
                          child: _buildBackgroundImage(),
                        ),
                      ),
                    ),
                    if (_showGrid) const _CentimeterGrid(),
                    if (_showScaleCheck) _ScaleCheckSquare(scale: _screenScale),
                    for (final mapping in _mappings)
                      Positioned(
                        left: mapping.xPercent * constraints.maxWidth,
                        top: mapping.yPercent * constraints.maxHeight,
                        child: _MappedCanvasElement(
                          mapping: mapping,
                          label: _displayTextForMapping(mapping),
                          canvasWidth: constraints.maxWidth,
                          canvasHeight: constraints.maxHeight,
                          localImageBytes: mapping.assetObjectKey.isEmpty
                              ? null
                              : _localStampBytesByObjectKey[mapping
                                    .assetObjectKey],
                          imageUrl: mapping.assetImageUrl,
                          selected:
                              _selectedMappingFieldKey == mapping.fieldKey,
                          showBoundingBox: _showBoundingBoxes,
                          onTap: () => setState(
                            () => _selectedMappingFieldKey = mapping.fieldKey,
                          ),
                          onDrag: (delta) {
                            final nextX =
                                ((mapping.xPercent * constraints.maxWidth +
                                            delta.dx) /
                                        constraints.maxWidth)
                                    .clamp(0.0, 1.0);
                            final nextY =
                                ((mapping.yPercent * constraints.maxHeight +
                                            delta.dy) /
                                        constraints.maxHeight)
                                    .clamp(0.0, 1.0);
                            _updateMapping(
                              mapping.fieldKey,
                              mapping.copyWith(
                                xPercent: nextX,
                                yPercent: nextY,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundImage() {
    if (_localBackgroundBytes != null) {
      return Image.memory(_localBackgroundBytes!, fit: BoxFit.fill);
    }
    if (_backgroundImageUrl != null && _backgroundImageUrl!.isNotEmpty) {
      return Image.network(_backgroundImageUrl!, fit: BoxFit.fill);
    }
    return const Center(
      child: Text(
        'Upload a scanned challan to start mapping fields.',
        style: TextStyle(color: SoftErpTheme.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRightPanel() {
    final selected = _mappingForField(_selectedMappingFieldKey);
    return SoftSurface(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text(
            'ERP Data Sources',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Add Text',
            icon: Icons.text_fields_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: _addStaticText,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Add Image / Stamp',
            icon: Icons.approval_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: _pickAndUploadStamp,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _fields
                .map(
                  (field) => SoftPill(
                    label: field.label,
                    foreground: _selectedFieldKey == field.key
                        ? Colors.white
                        : SoftErpTheme.textPrimary,
                    background: _selectedFieldKey == field.key
                        ? SoftErpTheme.accent
                        : SoftErpTheme.cardSurfaceAlt,
                    onTap: () => setState(() => _selectedFieldKey = field.key),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          if (selected == null)
            const Text(
              'Select a placed field to edit font and table settings.',
              style: TextStyle(color: SoftErpTheme.textSecondary),
            )
          else
            _buildMappingProperties(selected),
        ],
      ),
    );
  }

  Widget _buildMappingProperties(ChallanTemplateMapping mapping) {
    final field = _fieldForKey(mapping.fieldKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _displayTitleForMapping(mapping),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          selected: {
            switch (mapping.fieldType.toUpperCase()) {
              'STATIC' => 'STATIC',
              'IMAGE' => 'IMAGE',
              _ => 'DYNAMIC',
            },
          },
          segments: const [
            ButtonSegment(value: 'DYNAMIC', label: Text('Dynamic')),
            ButtonSegment(value: 'STATIC', label: Text('Static')),
            ButtonSegment(value: 'IMAGE', label: Text('Image')),
          ],
          onSelectionChanged: (value) {
            final nextType = value.first;
            final currentType = mapping.fieldType.toUpperCase();
            final nextKey = nextType == 'DYNAMIC'
                ? (_fieldForKey(mapping.fieldKey) != null
                      ? mapping.fieldKey
                      : _fields.first.key)
                : currentType == 'DYNAMIC'
                ? _newStaticFieldKey()
                : mapping.fieldKey;
            _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(
                fieldType: nextType,
                fieldKey: nextKey,
                fieldValue: nextType == 'STATIC'
                    ? (mapping.fieldValue.isEmpty
                          ? _displayTextForMapping(mapping)
                          : mapping.fieldValue)
                    : nextType == 'IMAGE'
                    ? ''
                    : mapping.fieldValue,
              ),
            );
            setState(() => _selectedMappingFieldKey = nextKey);
          },
        ),
        const SizedBox(height: 12),
        if (mapping.fieldType.toUpperCase() == 'IMAGE') ...[
          Text(
            mapping.assetObjectKey.isEmpty
                ? 'No image uploaded.'
                : 'Stamp asset: ${mapping.assetObjectKey.split('/').last}',
            style: const TextStyle(color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          _NumberSlider(
            label: 'Image Width',
            value: mapping.imageWidthMm,
            min: 2,
            max: 120,
            divisions: 59,
            suffix: 'mm',
            onChanged: (value) {
              final ratio =
                  mapping.assetWidthPx > 0 && mapping.assetHeightPx > 0
                  ? mapping.assetHeightPx / mapping.assetWidthPx
                  : mapping.imageHeightMm / mapping.imageWidthMm;
              _updateMapping(
                mapping.fieldKey,
                mapping.copyWith(
                  imageWidthMm: value,
                  imageHeightMm: mapping.lockAspectRatio
                      ? value * ratio
                      : mapping.imageHeightMm,
                ),
              );
            },
          ),
          _NumberSlider(
            label: 'Image Height',
            value: mapping.imageHeightMm,
            min: 2,
            max: 120,
            divisions: 59,
            suffix: 'mm',
            onChanged: (value) {
              final ratio =
                  mapping.assetWidthPx > 0 && mapping.assetHeightPx > 0
                  ? mapping.assetWidthPx / mapping.assetHeightPx
                  : mapping.imageWidthMm / mapping.imageHeightMm;
              _updateMapping(
                mapping.fieldKey,
                mapping.copyWith(
                  imageHeightMm: value,
                  imageWidthMm: mapping.lockAspectRatio
                      ? value * ratio
                      : mapping.imageWidthMm,
                ),
              );
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: mapping.lockAspectRatio,
            onChanged: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(lockAspectRatio: value),
            ),
            title: const Text('Lock Aspect Ratio'),
          ),
        ] else if (mapping.fieldType.toUpperCase() == 'STATIC')
          TextField(
            decoration: const InputDecoration(labelText: 'Static Text'),
            minLines: 1,
            maxLines: 4,
            controller: TextEditingController(text: mapping.fieldValue)
              ..selection = TextSelection.collapsed(
                offset: mapping.fieldValue.length,
              ),
            onChanged: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(fieldValue: value),
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _fields.any((field) => field.key == mapping.fieldKey)
                ? mapping.fieldKey
                : _fields.first.key,
            decoration: const InputDecoration(labelText: 'ERP Data Source'),
            items: _fields
                .map(
                  (field) => DropdownMenuItem<String>(
                    value: field.key,
                    child: Text(field.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              _updateMapping(
                mapping.fieldKey,
                mapping.copyWith(fieldKey: value, fieldType: 'DYNAMIC'),
              );
              setState(() => _selectedMappingFieldKey = value);
            },
          ),
        if (mapping.fieldType.toUpperCase() != 'IMAGE') ...[
          const SizedBox(height: 12),
          Text(
            'Sample: ${_displayTextForMapping(mapping)}',
            style: const TextStyle(color: SoftErpTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
        if (mapping.fieldType.toUpperCase() != 'IMAGE')
          _NumberSlider(
            label: 'Font Size',
            value: mapping.fontSize,
            min: 8,
            max: 16,
            divisions: 8,
            suffix: 'pt',
            onChanged: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(fontSize: value),
            ),
          ),
        if (mapping.fieldType.toUpperCase() != 'IMAGE')
          _NumberSlider(
            label: 'Letter Spacing',
            value: mapping.letterSpacing,
            min: -2,
            max: 6,
            divisions: 16,
            suffix: '',
            onChanged: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(letterSpacing: value),
            ),
          ),
        if (mapping.fieldType.toUpperCase() != 'IMAGE')
          TextField(
            decoration: const InputDecoration(labelText: 'Max Characters'),
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: '${mapping.maxChars}')
              ..selection = TextSelection.collapsed(
                offset: '${mapping.maxChars}'.length,
              ),
            onSubmitted: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(maxChars: int.tryParse(value) ?? 0),
            ),
          ),
        if (mapping.fieldType.toUpperCase() != 'IMAGE') ...[
          const SizedBox(height: 12),
          _NumberSlider(
            label: 'Max Width',
            value: mapping.maxWidthMm,
            min: 5,
            max: 210,
            divisions: 41,
            suffix: 'mm',
            onChanged: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(maxWidthMm: value),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (mapping.fieldType.toUpperCase() != 'IMAGE')
          DropdownButtonFormField<String>(
            initialValue: mapping.alignment,
            decoration: const InputDecoration(labelText: 'Alignment'),
            items: const [
              DropdownMenuItem(value: 'left', child: Text('Left')),
              DropdownMenuItem(value: 'center', child: Text('Center')),
              DropdownMenuItem(value: 'right', child: Text('Right')),
            ],
            onChanged: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(alignment: value ?? 'left'),
            ),
          ),
        const SizedBox(height: 12),
        if (mapping.fieldType.toUpperCase() != 'IMAGE')
          DropdownButtonFormField<String>(
            initialValue: _normalizedTextColor(mapping.textColor),
            decoration: const InputDecoration(labelText: 'Text Color'),
            items: const [
              DropdownMenuItem(value: 'black', child: Text('Black')),
              DropdownMenuItem(value: 'blue', child: Text('Blue')),
              DropdownMenuItem(value: 'red', child: Text('Red')),
            ],
            onChanged: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(textColor: value ?? 'black'),
            ),
          ),
        const SizedBox(height: 12),
        if (mapping.fieldType.toUpperCase() != 'IMAGE')
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: mapping.fontWeight == 'bold',
            onChanged: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(fontWeight: value ? 'bold' : 'normal'),
            ),
            title: const Text('Bold'),
          ),
        if (mapping.fieldType.toUpperCase() != 'STATIC' &&
            (field?.isTable ?? false))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NumberSlider(
                label: 'Row Pitch',
                value: mapping.rowHeightMm,
                min: 2,
                max: 20,
                divisions: 18,
                suffix: 'mm',
                onChanged: (value) => _updateMapping(
                  mapping.fieldKey,
                  mapping.copyWith(rowHeightMm: value),
                ),
              ),
              _NumberSlider(
                label: 'Max Rows',
                value: mapping.maxRows.toDouble(),
                min: 0,
                max: 40,
                divisions: 40,
                suffix: '',
                onChanged: (value) => _updateMapping(
                  mapping.fieldKey,
                  mapping.copyWith(maxRows: value.round()),
                ),
              ),
              const Text(
                '0 means unlimited. If exceeded, the PDF continues on page 2.',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Remove Field',
          icon: Icons.delete_outline,
          variant: AppButtonVariant.secondary,
          onPressed: () {
            setState(() {
              _mappings = _mappings
                  .where((entry) => entry.fieldKey != mapping.fieldKey)
                  .toList();
              _selectedMappingFieldKey = null;
            });
          },
        ),
      ],
    );
  }

  Future<void> _pickAndUploadBackground() async {
    final provider = context.read<DeliveryChallanProvider>();
    try {
      final file = await _pickFileWithFallback(
        primary: const [
          XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg'],
            mimeTypes: ['image/png', 'image/jpeg'],
          ),
        ],
        fallback: const [
          XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg']),
        ],
      );
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final contentType = _contentTypeForName(file.name);
      setState(() {
        _isSaving = true;
        _error = null;
      });
      final intent = await provider.createTemplateUploadIntent(
        ChallanTemplateUploadIntentInput(
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
        ),
      );
      if (intent == null) {
        throw Exception(provider.errorMessage ?? 'Failed to prepare upload.');
      }
      if (intent.uploadUrl.host != 'mock.local') {
        final response = await http.put(
          intent.uploadUrl,
          headers: intent.headers,
          body: bytes,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Upload failed with status ${response.statusCode}.');
        }
      }
      final background = await provider.completeTemplateUpload(
        uploadSessionId: intent.uploadSessionId,
        objectKey: intent.objectKey,
      );
      if (background == null) {
        throw Exception(provider.errorMessage ?? 'Failed to complete upload.');
      }
      setState(() {
        _backgroundObjectKey = background.objectKey;
        _canvasWidth = background.canvasWidth;
        _canvasHeight = background.canvasHeight;
        _localBackgroundBytes = bytes;
        _backgroundImageUrl = null;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _partyId == null || _backgroundObjectKey.isEmpty) {
      setState(() {
        _error = 'Template name, party, and background scan are required.';
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final provider = context.read<DeliveryChallanProvider>();
    final saved = await provider.saveTemplate(
      id: _selectedTemplate?.id,
      input: ChallanTemplateInput(
        name: name,
        partyType: _partyType,
        partyId: _partyId!,
        challanType: _challanType,
        backgroundObjectKey: _backgroundObjectKey,
        canvasWidth: _canvasWidth,
        canvasHeight: _canvasHeight,
        rotationDegrees: _rotationDegrees,
        globalOffsetXmm: _globalOffsetXmm,
        globalOffsetYmm: _globalOffsetYmm,
        isActive: true,
        mappings: _mappings,
      ),
    );
    if (!mounted) {
      return;
    }
    if (saved == null) {
      setState(() {
        _isSaving = false;
        _error = provider.errorMessage ?? 'Failed to save template.';
      });
      return;
    }
    await _loadTemplates();
    setState(() {
      _isSaving = false;
      _applyTemplate(saved);
    });
  }

  void _placeField(String fieldKey, double xPercent, double yPercent) {
    final existing = _mappingForField(fieldKey);
    final mapping =
        (existing ??
                ChallanTemplateMapping(
                  id: 0,
                  templateId: _selectedTemplate?.id ?? 0,
                  fieldType: 'DYNAMIC',
                  fieldKey: fieldKey,
                  fieldValue: '',
                  assetObjectKey: '',
                  assetImageUrl: null,
                  assetWidthPx: 0,
                  assetHeightPx: 0,
                  imageWidthMm: 35,
                  imageHeightMm: 20,
                  lockAspectRatio: true,
                  xPercent: xPercent,
                  yPercent: yPercent,
                  fontSize: 10,
                  fontWeight: 'normal',
                  alignment: 'left',
                  textColor: 'black',
                  letterSpacing: 0,
                  maxChars: 0,
                  maxWidthMm: 80,
                  maxRows: 0,
                  rowHeightMm: 6,
                ))
            .copyWith(xPercent: xPercent, yPercent: yPercent);
    _updateMapping(fieldKey, mapping);
    setState(() {
      _selectedMappingFieldKey = fieldKey;
      _selectedFieldKey = null;
    });
  }

  void _addStaticText() {
    final fieldKey = _newStaticFieldKey();
    final mapping = ChallanTemplateMapping(
      id: 0,
      templateId: _selectedTemplate?.id ?? 0,
      fieldType: 'STATIC',
      fieldKey: fieldKey,
      fieldValue: 'Authorized Signatory',
      assetObjectKey: '',
      assetImageUrl: null,
      assetWidthPx: 0,
      assetHeightPx: 0,
      imageWidthMm: 35,
      imageHeightMm: 20,
      lockAspectRatio: true,
      xPercent: 0.12,
      yPercent: 0.82,
      fontSize: 10,
      fontWeight: 'normal',
      alignment: 'left',
      textColor: 'black',
      letterSpacing: 0,
      maxChars: 0,
      maxWidthMm: 80,
      maxRows: 0,
      rowHeightMm: 6,
    );
    setState(() {
      _mappings = [..._mappings, mapping];
      _selectedMappingFieldKey = fieldKey;
      _selectedFieldKey = null;
    });
  }

  Future<void> _pickAndUploadStamp() async {
    final provider = context.read<DeliveryChallanProvider>();
    try {
      final file = await _pickFileWithFallback(
        primary: const [
          XTypeGroup(
            label: 'Transparent PNG',
            extensions: ['png'],
            mimeTypes: ['image/png'],
          ),
        ],
        fallback: const [
          XTypeGroup(label: 'Transparent PNG', extensions: ['png']),
        ],
      );
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      setState(() {
        _isSaving = true;
        _error = null;
      });
      final intent = await provider.createTemplateStampUploadIntent(
        ChallanTemplateUploadIntentInput(
          fileName: file.name,
          contentType: 'image/png',
          sizeBytes: bytes.length,
          sha256: digest,
        ),
      );
      if (intent == null) {
        throw Exception(
          provider.errorMessage ?? 'Failed to prepare stamp upload.',
        );
      }
      if (intent.uploadUrl.host != 'mock.local') {
        final response = await http.put(
          intent.uploadUrl,
          headers: intent.headers,
          body: bytes,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Upload failed with status ${response.statusCode}.');
        }
      }
      final stamp = await provider.completeTemplateStampUpload(
        uploadSessionId: intent.uploadSessionId,
        objectKey: intent.objectKey,
      );
      if (stamp == null) {
        throw Exception(
          provider.errorMessage ?? 'Failed to complete stamp upload.',
        );
      }
      final fieldKey = _newStaticFieldKey();
      final aspectRatio = stamp.canvasWidth > 0 && stamp.canvasHeight > 0
          ? stamp.canvasHeight / stamp.canvasWidth
          : 0.5;
      final mapping = ChallanTemplateMapping(
        id: 0,
        templateId: _selectedTemplate?.id ?? 0,
        fieldType: 'IMAGE',
        fieldKey: fieldKey,
        fieldValue: '',
        assetObjectKey: stamp.objectKey,
        assetImageUrl: null,
        assetWidthPx: stamp.canvasWidth,
        assetHeightPx: stamp.canvasHeight,
        imageWidthMm: 35,
        imageHeightMm: 35 * aspectRatio,
        lockAspectRatio: true,
        xPercent: 0.12,
        yPercent: 0.76,
        fontSize: 10,
        fontWeight: 'normal',
        alignment: 'left',
        textColor: 'black',
        letterSpacing: 0,
        maxChars: 0,
        maxWidthMm: 80,
        maxRows: 0,
        rowHeightMm: 6,
      );
      setState(() {
        _localStampBytesByObjectKey[stamp.objectKey] = bytes;
        _mappings = [..._mappings, mapping];
        _selectedMappingFieldKey = fieldKey;
        _selectedFieldKey = null;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<XFile?> _pickFileWithFallback({
    required List<XTypeGroup> primary,
    required List<XTypeGroup> fallback,
  }) async {
    try {
      return await openFile(acceptedTypeGroups: primary);
    } catch (_) {
      return openFile(acceptedTypeGroups: fallback);
    }
  }

  void _updateMapping(String fieldKey, ChallanTemplateMapping mapping) {
    setState(() {
      final index = _mappings.indexWhere((entry) => entry.fieldKey == fieldKey);
      if (index >= 0) {
        _mappings[index] = mapping;
        _mappings = [
          for (var i = 0; i < _mappings.length; i += 1)
            if (i == index || _mappings[i].fieldKey != mapping.fieldKey)
              _mappings[i],
        ];
      } else {
        _mappings.add(mapping);
      }
    });
  }

  ChallanTemplateMapping? _mappingForField(String? fieldKey) {
    if (fieldKey == null) {
      return null;
    }
    for (final mapping in _mappings) {
      if (mapping.fieldKey == fieldKey) {
        return mapping;
      }
    }
    return null;
  }

  String _labelForField(String key) => _fieldForKey(key)?.label ?? key;

  String _newStaticFieldKey() {
    return 'static_${DateTime.now().microsecondsSinceEpoch}';
  }

  String _displayTitleForMapping(ChallanTemplateMapping mapping) {
    if (mapping.fieldType.toUpperCase() == 'IMAGE') {
      return 'Stamp / Signature';
    }
    if (mapping.fieldType.toUpperCase() == 'STATIC') {
      return 'Static Text';
    }
    return _labelForField(mapping.fieldKey);
  }

  String _displayTextForMapping(ChallanTemplateMapping mapping) {
    if (mapping.fieldType.toUpperCase() == 'IMAGE') {
      final fileName = mapping.assetObjectKey.split('/').last.trim();
      return fileName.isEmpty ? 'Stamp' : fileName;
    }
    if (mapping.fieldType.toUpperCase() == 'STATIC') {
      return mapping.fieldValue.trim().isEmpty
          ? 'Static text'
          : mapping.fieldValue;
    }
    switch (mapping.fieldKey) {
      case 'challan_no':
        return 'DC-00042';
      case 'date':
        return '13-05-2026';
      case 'party_name':
        return 'Sarvadnya Udyog Private Limited';
      case 'gstin':
        return '27ABCDE1234F1Z5';
      case 'location':
        return 'Main Warehouse';
      case 'source_ref':
        return 'PO-1042';
      case 'total_qty':
        return '12,345.00';
      case 'notes':
        return 'Handle with care';
      case 'item_particulars':
        return 'Duplex Board - A4';
      case 'hsn':
        return '4802';
      case 'qty_pcs':
        return '120';
      case 'weight':
        return '48.5';
      default:
        return _labelForField(mapping.fieldKey);
    }
  }

  String _normalizedTextColor(String value) {
    final normalized = value.toLowerCase();
    return ['black', 'blue', 'red'].contains(normalized) ? normalized : 'black';
  }

  _TemplateField? _fieldForKey(String key) {
    for (final field in _fields) {
      if (field.key == key) {
        return field;
      }
    }
    return null;
  }

  String _contentTypeForName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    return 'image/jpeg';
  }
}

class _TemplateField {
  const _TemplateField(this.key, this.label, {this.isTable = false});

  final String key;
  final String label;
  final bool isTable;
}

class _MappedCanvasElement extends StatelessWidget {
  const _MappedCanvasElement({
    required this.mapping,
    required this.label,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.localImageBytes,
    required this.imageUrl,
    required this.selected,
    required this.showBoundingBox,
    required this.onTap,
    required this.onDrag,
  });

  final ChallanTemplateMapping mapping;
  final String label;
  final double canvasWidth;
  final double canvasHeight;
  final Uint8List? localImageBytes;
  final String? imageUrl;
  final bool selected;
  final bool showBoundingBox;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    if (mapping.fieldType.toUpperCase() == 'IMAGE') {
      final width = (mapping.imageWidthMm / 210 * canvasWidth).clamp(
        20.0,
        canvasWidth,
      );
      final height = (mapping.imageHeightMm / 297 * canvasHeight).clamp(
        20.0,
        canvasHeight,
      );
      return GestureDetector(
        onTap: onTap,
        onPanUpdate: (details) => onDrag(details.delta),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: selected
                ? SoftErpTheme.accent.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? SoftErpTheme.accent
                  : showBoundingBox
                  ? SoftErpTheme.border
                  : Colors.transparent,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: localImageBytes != null
              ? Image.memory(localImageBytes!, fit: BoxFit.contain)
              : (imageUrl != null && imageUrl!.isNotEmpty
                    ? Image.network(imageUrl!, fit: BoxFit.contain)
                    : Center(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )),
        ),
      );
    }
    final width = (mapping.maxWidthMm / 210 * canvasWidth).clamp(
      28.0,
      canvasWidth,
    );
    final scale = canvasWidth / 595.28;
    final textColor = switch (mapping.textColor.toLowerCase()) {
      'blue' => const Color(0xFF1D4ED8),
      'red' => const Color(0xFFB91C1C),
      _ => SoftErpTheme.textPrimary,
    };
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: (details) => onDrag(details.delta),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? SoftErpTheme.accent.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? SoftErpTheme.accent
                : showBoundingBox
                ? SoftErpTheme.border
                : Colors.transparent,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          label,
          maxLines: 4,
          overflow: TextOverflow.visible,
          textAlign: switch (mapping.alignment) {
            'center' => TextAlign.center,
            'right' => TextAlign.right,
            _ => TextAlign.left,
          },
          style: TextStyle(
            color: textColor,
            fontSize: (mapping.fontSize * scale).clamp(6.0, 30.0),
            fontWeight: mapping.fontWeight == 'bold'
                ? FontWeight.w800
                : FontWeight.w500,
            letterSpacing: mapping.letterSpacing * scale,
          ),
        ),
      ),
    );
  }
}

class _CentimeterGrid extends StatelessWidget {
  const _CentimeterGrid();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _CentimeterGridPainter()));
  }
}

class _ScaleCheckSquare extends StatelessWidget {
  const _ScaleCheckSquare({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = 378.0 * scale;
    return Positioned(
      left: 18,
      top: 18,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SoftErpTheme.accent.withValues(alpha: 0.08),
            border: Border.all(color: SoftErpTheme.accent, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '10 cm x 10 cm',
            style: TextStyle(
              color: SoftErpTheme.accentDark,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _CentimeterGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SoftErpTheme.accent.withValues(alpha: 0.18)
      ..strokeWidth = 0.8;
    final cellWidth = size.width / 21;
    final cellHeight = size.height / 29.7;
    for (var x = 0.0; x <= size.width; x += cellWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += cellHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NumberSlider extends StatelessWidget {
  const _NumberSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(1)}$suffix'),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3B4AF)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF9F1D18),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
