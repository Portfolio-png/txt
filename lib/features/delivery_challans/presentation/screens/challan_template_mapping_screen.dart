import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/challan_template.dart';
import '../../domain/delivery_challan.dart';
import '../providers/delivery_challan_provider.dart';

const MethodChannel _nativePrintingChannel = MethodChannel(
  'paper/native_printing',
);

class TemplateMappingScreen extends StatefulWidget {
  const TemplateMappingScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<TemplateMappingScreen> createState() => _TemplateMappingScreenState();
}

class _TemplateMappingScreenState extends State<TemplateMappingScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<ChallanTemplate> _templates = const <ChallanTemplate>[];
  List<ChallanTemplateScan> _uploadedScans = const <ChallanTemplateScan>[];
  List<ChallanTemplateMapping> _mappings = <ChallanTemplateMapping>[];
  ChallanTemplate? _selectedTemplate;
  ChallanType _challanType = ChallanType.delivery;
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
  String _stockSize = 'A4';
  String _paperSize = 'A4';
  int _nUpLayout = 1;
  bool _showGrid = false;
  bool _showScaleCheck = false;
  double _screenScale = 1;
  bool _showBoundingBoxes = true;
  bool _isLoading = true;
  bool _isLoadingScans = false;
  bool _isSaving = false;
  String _selectedBlockOwnerFieldKey = _headerOwnerKey;
  String? _selectedMappingFieldKey;
  Set<String> _selectedMappingFieldKeys = <String>{};
  String? _error;
  static const List<String> _tableColumnKeys = <String>[
    'hsn',
    'qty_pcs',
    'weight',
    'note',
  ];
  static const String _tableOwnerKey = 'item_particulars';
  static const String _headerOwnerKey = 'challan_no';
  static const List<_TemplateBlockSpec> _blocks = <_TemplateBlockSpec>[
    _TemplateBlockSpec(
      ownerFieldKey: 'challan_no',
      label: 'Challan No',
      description: 'Primary challan identifier.',
      companionFieldKeys: <String>[],
      defaultXPercent: 0.08,
      defaultYPercent: 0.08,
      defaultWidthMm: 88,
      defaultHeightMm: 12,
    ),
    _TemplateBlockSpec(
      ownerFieldKey: 'date',
      label: 'Date',
      description: 'Printed challan date.',
      companionFieldKeys: <String>[],
      defaultXPercent: 0.62,
      defaultYPercent: 0.08,
      defaultWidthMm: 46,
      defaultHeightMm: 12,
    ),
    _TemplateBlockSpec(
      ownerFieldKey: 'party_name',
      label: 'Party Name',
      description: 'Customer or vendor name.',
      companionFieldKeys: <String>[],
      defaultXPercent: 0.08,
      defaultYPercent: 0.18,
      defaultWidthMm: 150,
      defaultHeightMm: 14,
    ),
    _TemplateBlockSpec(
      ownerFieldKey: 'gstin',
      label: 'GSTIN',
      description: 'Tax registration line.',
      companionFieldKeys: <String>[],
      defaultXPercent: 0.08,
      defaultYPercent: 0.25,
      defaultWidthMm: 150,
      defaultHeightMm: 12,
    ),
    _TemplateBlockSpec(
      ownerFieldKey: 'location',
      label: 'Location',
      description: 'Warehouse or delivery location.',
      companionFieldKeys: <String>[],
      defaultXPercent: 0.08,
      defaultYPercent: 0.31,
      defaultWidthMm: 150,
      defaultHeightMm: 12,
    ),
    _TemplateBlockSpec(
      ownerFieldKey: 'source_ref',
      label: 'Source Ref',
      description: 'PO, order, or source reference.',
      companionFieldKeys: <String>[],
      defaultXPercent: 0.08,
      defaultYPercent: 0.14,
      defaultWidthMm: 150,
      defaultHeightMm: 12,
    ),
    _TemplateBlockSpec(
      ownerFieldKey: 'total_qty',
      label: 'Total Qty',
      description: 'Summary quantity field.',
      companionFieldKeys: <String>[],
      defaultXPercent: 0.08,
      defaultYPercent: 0.80,
      defaultWidthMm: 70,
      defaultHeightMm: 12,
    ),
    _TemplateBlockSpec(
      ownerFieldKey: 'notes',
      label: 'Notes',
      description: 'Freeform note or handling text.',
      companionFieldKeys: <String>[],
      defaultXPercent: 0.08,
      defaultYPercent: 0.86,
      defaultWidthMm: 150,
      defaultHeightMm: 16,
    ),
    _TemplateBlockSpec(
      ownerFieldKey: _tableOwnerKey,
      label: 'Table Block',
      description: 'Particulars with auto-layout columns',
      companionFieldKeys: _tableColumnKeys,
      defaultXPercent: 0.08,
      defaultYPercent: 0.34,
      defaultWidthMm: 150,
      defaultHeightMm: 70,
      isTable: true,
    ),
  ];

  static const _fields = <_TemplateField>[
    _TemplateField('challan_no', 'Challan No'),
    _TemplateField('date', 'Date'),
    _TemplateField('party_name', 'Party Name'),
    _TemplateField('gstin', 'GSTIN'),
    _TemplateField('location', 'Location'),
    _TemplateField('source_ref', 'Source Ref'),
    _TemplateField('total_qty', 'Total Qty'),
    _TemplateField('notes', 'Notes'),
    _TemplateField('item_particulars', 'Items Area', isTable: true),
    _TemplateField('hsn', 'HSN', isTable: true, hiddenFromPalette: true),
    _TemplateField(
      'qty_pcs',
      'Qty Pcs',
      isTable: true,
      hiddenFromPalette: true,
    ),
    _TemplateField('weight', 'Weight', isTable: true, hiddenFromPalette: true),
    _TemplateField('note', 'Note', isTable: true, hiddenFromPalette: true),
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
    await _loadTemplates();
    await _loadUploadedScans();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final templates = await context
        .read<DeliveryChallanProvider>()
        .loadTemplates(partyType: ChallanTemplatePartyType.generic);
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
    _challanType = template.challanType;
    _backgroundObjectKey = template.backgroundObjectKey;
    _backgroundImageUrl = template.backgroundImageUrl;
    _localBackgroundBytes = null;
    _canvasWidth = template.canvasWidth;
    _canvasHeight = template.canvasHeight;
    _rotationDegrees = template.rotationDegrees;
    _globalOffsetXmm = template.globalOffsetXmm;
    _globalOffsetYmm = template.globalOffsetYmm;
    _stockSize = template.stockSize;
    _paperSize = template.paperSize;
    _nUpLayout = template.nUpLayout;
    _mappings = _normalizeStructuredMappings(template.mappings.toList());
    _selectedMappingFieldKey = _canvasMappings.isEmpty
        ? null
        : _canvasMappings.first.fieldKey;
    _selectedBlockOwnerFieldKey =
        _blockForOwnerField(_selectedMappingFieldKey ?? '')?.ownerFieldKey ??
        _headerOwnerKey;
    _selectedMappingFieldKeys = _selectedMappingFieldKey == null
        ? <String>{}
        : <String>{_selectedMappingFieldKey!};
  }

  void _startNewTemplate() {
    setState(() {
      _selectedTemplate = null;
      _nameController.clear();
      _challanType = ChallanType.delivery;
      _backgroundObjectKey = '';
      _backgroundImageUrl = null;
      _localBackgroundBytes = null;
      _canvasWidth = 0;
      _canvasHeight = 0;
      _rotationDegrees = 0;
      _globalOffsetXmm = 0;
      _globalOffsetYmm = 0;
      _stockSize = 'A4';
      _paperSize = 'A4';
      _nUpLayout = 1;
      _showScaleCheck = false;
      _screenScale = 1;
      _mappings = <ChallanTemplateMapping>[];
      _selectedBlockOwnerFieldKey = _headerOwnerKey;
      _selectedMappingFieldKey = null;
      _selectedMappingFieldKeys = <String>{};
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
                    _buildLeftPanel(scrollable: false),
                    const SizedBox(height: 12),
                    SizedBox(height: 640, child: _buildCanvasPanel()),
                    const SizedBox(height: 12),
                    _buildRightPanel(scrollable: false),
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

  Widget _buildLeftPanel({bool scrollable = true}) {
    return SoftSurface(
      padding: const EdgeInsets.all(16),
      child: _buildPanelBody(
        scrollable: scrollable,
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
            isExpanded: true,
            decoration: _editorInputDecoration(label: 'Existing templates'),
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
            decoration: _editorInputDecoration(label: 'Template Name'),
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
          const SizedBox(height: 12),
          _buildUploadedScansSection(),
          const SizedBox(height: 12),
          const Text(
            'Print Presets',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _presetButton(
                label: 'Full Page',
                stockSize: 'A4',
                paperSize: 'A4',
                nUpLayout: 1,
              ),
              _presetButton(
                label: 'A5 Sheet',
                stockSize: 'A5',
                paperSize: 'A5',
                nUpLayout: 1,
              ),
              _presetButton(
                label: 'Half & Half',
                stockSize: 'A5',
                paperSize: 'A4',
                nUpLayout: 2,
              ),
              _presetButton(
                label: 'Quarter',
                stockSize: 'A6',
                paperSize: 'A4',
                nUpLayout: 4,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              'Advanced Calibration',
              style: TextStyle(
                color: SoftErpTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text('Grid, offsets, rotation, and scale tools.'),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showGrid,
                onChanged: (value) => setState(() => _showGrid = value),
                title: const Text('Calibration Grid'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showBoundingBoxes,
                onChanged: (value) =>
                    setState(() => _showBoundingBoxes = value),
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
                _DecimalInputField(
                  label: 'Screen Scale',
                  value: _screenScale,
                  min: 0.5,
                  max: 1.5,
                  suffix: 'x',
                  onSubmitted: (value) => setState(() => _screenScale = value),
                ),
              const SizedBox(height: 12),
              _DecimalInputField(
                label: 'Rotate',
                value: _rotationDegrees,
                min: -5,
                max: 5,
                suffix: 'deg',
                onSubmitted: (value) =>
                    setState(() => _rotationDegrees = value),
              ),
              _DecimalInputField(
                label: 'X Offset',
                value: _globalOffsetXmm,
                min: -20,
                max: 20,
                suffix: 'mm',
                onSubmitted: (value) =>
                    setState(() => _globalOffsetXmm = value),
              ),
              _DecimalInputField(
                label: 'Y Offset',
                value: _globalOffsetYmm,
                min: -20,
                max: 20,
                suffix: 'mm',
                onSubmitted: (value) =>
                    setState(() => _globalOffsetYmm = value),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Test Print',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send either a single item or a full table to the system print dialog.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          Column(
            children: [
              AppButton(
                label: 'Test Print: 1 Item',
                variant: AppButtonVariant.secondary,
                onPressed:
                    _selectedTemplate?.id != null &&
                        (_selectedTemplate?.id ?? 0) > 0 &&
                        _layoutValidity.isValid
                    ? () => _openTestPrint(itemCount: 1)
                    : null,
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Test Print: Full Table',
                variant: AppButtonVariant.secondary,
                onPressed:
                    _selectedTemplate?.id != null &&
                        (_selectedTemplate?.id ?? 0) > 0 &&
                        _layoutValidity.isValid
                    ? _openFullTableTestPrint
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TemplateLayoutHint(validity: _layoutValidity),
        ],
      ),
    );
  }

  Widget _buildUploadedScansSection() {
    final visibleScans = _visibleUploadedScans();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Uploaded Scans',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh scans',
              onPressed: _isLoadingScans ? null : _loadUploadedScans,
              icon: _isLoadingScans
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingScans && visibleScans.isEmpty)
          const LinearProgressIndicator(minHeight: 2)
        else if (visibleScans.isEmpty)
          Text(
            'No saved scans yet.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: SoftErpTheme.textSecondary),
          )
        else
          Column(
            children: [
              for (final scan in visibleScans) ...[
                _UploadedScanTile(
                  scan: scan,
                  selected: scan.objectKey == _backgroundObjectKey,
                  onTap: () => _selectUploadedScan(scan),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
      ],
    );
  }

  List<ChallanTemplateScan> _visibleUploadedScans() {
    final scans = _uploadedScans.take(6).toList();
    final selectedScan = _scanForObjectKey(_backgroundObjectKey);
    if (selectedScan != null &&
        !scans.any((scan) => scan.objectKey == selectedScan.objectKey)) {
      scans.add(selectedScan);
    }
    return scans;
  }

  void _selectUploadedScan(ChallanTemplateScan scan) {
    if (scan.objectKey.isEmpty) {
      return;
    }
    setState(() {
      _backgroundObjectKey = scan.objectKey;
      _backgroundImageUrl = scan.imageUrl;
      _localBackgroundBytes = null;
      if (scan.canvasWidth > 0) {
        _canvasWidth = scan.canvasWidth;
      }
      if (scan.canvasHeight > 0) {
        _canvasHeight = scan.canvasHeight;
      }
      _error = null;
    });
  }

  ChallanTemplateScan? _scanForObjectKey(String objectKey) {
    for (final scan in _uploadedScans) {
      if (scan.objectKey == objectKey) {
        return scan;
      }
    }
    return null;
  }

  Widget _buildCanvasPanel() {
    return SoftSurface(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: AspectRatio(
          aspectRatio:
              _templateInstanceMm().width / _templateInstanceMm().height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (_) => setState(() {
                  _selectedMappingFieldKey = null;
                  _selectedMappingFieldKeys = <String>{};
                }),
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
                    for (final mapping in _canvasMappings)
                      Builder(
                        builder: (context) {
                          final rect = _mappingRect(
                            mapping,
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          return Positioned(
                            left: rect.left,
                            top: rect.top,
                            child: _MappedCanvasElement(
                              mapping: mapping,
                              label: _displayTextForMapping(mapping),
                              canvasWidth: constraints.maxWidth,
                              canvasHeight: constraints.maxHeight,
                              boxWidth: rect.width,
                              boxHeight: rect.height,
                              localImageBytes: mapping.assetObjectKey.isEmpty
                                  ? null
                                  : _localStampBytesByObjectKey[mapping
                                        .assetObjectKey],
                              imageUrl: mapping.assetImageUrl,
                              tableRails: mapping.fieldKey == _tableOwnerKey
                                  ? _tableRailConfigsForOwner(mapping)
                                  : const <_TableRailConfig>[],
                              selected: _selectedMappingFieldKeys.contains(
                                mapping.fieldKey,
                              ),
                              showBoundingBox: _showBoundingBoxes,
                              onTap: () => _selectMapping(mapping.fieldKey),
                              onDrag: (delta) => _moveMappingByDelta(
                                mapping,
                                delta,
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              onDragEnd: _finishElementGesture,
                              onResize: (handle, delta) =>
                                  _resizeMappingByDelta(
                                    mapping,
                                    handle,
                                    delta,
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  ),
                              onResizeEnd: _finishElementGesture,
                              onRailDrag: (fieldKey, deltaMm) =>
                                  _moveTableRailByDelta(
                                    mapping,
                                    fieldKey,
                                    deltaMm,
                                  ),
                            ),
                          );
                        },
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

  Widget _buildRightPanel({bool scrollable = true}) {
    final selected = _mappingForField(_selectedMappingFieldKey);
    final selectedBlock = _requireBlock(_selectedBlockOwnerFieldKey);
    final selectedBlockPlaced =
        _mappingForField(selectedBlock.ownerFieldKey) != null;
    return SoftSurface(
      padding: const EdgeInsets.all(16),
      child: _buildPanelBody(
        scrollable: scrollable,
        children: [
          const Text(
            'Layout Blocks',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose a field from the dropdown, then add or remove it. The item lines stay as one table block.',
            style: TextStyle(color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: selectedBlock.ownerFieldKey,
            isExpanded: true,
            decoration: _editorInputDecoration(label: 'Field'),
            items: _blocks
                .map(
                  (block) => DropdownMenuItem<String>(
                    value: block.ownerFieldKey,
                    child: Text(block.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _selectedBlockOwnerFieldKey = value;
              });
            },
          ),
          const SizedBox(height: 10),
          AppButton(
            label: selectedBlockPlaced ? 'Delete Block' : 'Add Block',
            icon: selectedBlockPlaced
                ? Icons.delete_outline
                : Icons.add_box_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => _toggleBlockPlacement(selectedBlock),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SoftPill(
                label: selectedBlockPlaced ? 'Placed' : 'Not placed',
                background: selectedBlockPlaced
                    ? SoftErpTheme.successBg
                    : SoftErpTheme.cardSurfaceAlt,
                foreground: selectedBlockPlaced
                    ? SoftErpTheme.successText
                    : SoftErpTheme.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              'Advanced Freedom',
              style: TextStyle(
                color: SoftErpTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text('Custom text and detailed styling controls.'),
            children: [
              AppButton(
                label: 'Add Text',
                icon: Icons.text_fields_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: _addStaticText,
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (selected == null)
            const Text(
              'Select a block or custom text on the canvas to edit its size and settings.',
              style: TextStyle(color: SoftErpTheme.textSecondary),
            )
          else
            _buildMappingProperties(selected),
        ],
      ),
    );
  }

  Widget _buildPanelBody({
    required bool scrollable,
    required List<Widget> children,
  }) {
    if (!scrollable) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }
    return ListView(children: children);
  }

  Widget _buildMappingProperties(ChallanTemplateMapping mapping) {
    final block = _blockForOwnerField(mapping.fieldKey);
    final isImage = mapping.fieldType.toUpperCase() == 'IMAGE';
    final isStatic = mapping.fieldType.toUpperCase() == 'STATIC';
    final isTableOwner = mapping.fieldKey == _tableOwnerKey;
    final mappingOffset = _mappingOffsetMm(mapping);
    final instance = _templateInstanceMm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          block?.label ?? _displayTitleForMapping(mapping),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        if (block != null) ...[
          const SizedBox(height: 4),
          Text(
            block.description,
            style: const TextStyle(color: SoftErpTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
        if (isImage) ...[
          Text(
            mapping.assetObjectKey.isEmpty
                ? 'No image uploaded.'
                : 'Stamp asset: ${mapping.assetObjectKey.split('/').last}',
            style: const TextStyle(color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(height: 12),
        ] else if (isStatic) ...[
          TextField(
            decoration: _editorInputDecoration(label: 'Static Text'),
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
          ),
          const SizedBox(height: 12),
        ],
        if (!isImage) ...[
          Text(
            'Sample: ${_displayTextForMapping(mapping)}',
            style: const TextStyle(color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(height: 12),
        ],
        _DecimalInputField(
          label: 'X',
          value: mappingOffset.dx,
          min: 0,
          max: instance.width,
          suffix: 'mm',
          onSubmitted: (value) {
            _updateMapping(
              mapping.fieldKey,
              _withMmPosition(mapping, xMm: value),
            );
          },
        ),
        const SizedBox(height: 12),
        _DecimalInputField(
          label: 'Y',
          value: mappingOffset.dy,
          min: 0,
          max: instance.height,
          suffix: 'mm',
          onSubmitted: (value) {
            _updateMapping(
              mapping.fieldKey,
              _withMmPosition(mapping, yMm: value),
            );
          },
        ),
        const SizedBox(height: 12),
        _DecimalInputField(
          label: 'Width',
          value: mapping.widthMm,
          min: 2,
          max: instance.width,
          suffix: 'mm',
          onSubmitted: (value) {
            if (isImage) {
              final ratio =
                  mapping.assetWidthPx > 0 && mapping.assetHeightPx > 0
                  ? mapping.assetHeightPx / mapping.assetWidthPx
                  : mapping.heightMm / math.max(mapping.widthMm, 1);
              _updateMapping(
                mapping.fieldKey,
                mapping.copyWith(
                  widthMm: value,
                  heightMm: mapping.lockAspectRatio
                      ? value * ratio
                      : mapping.heightMm,
                  imageWidthMm: value,
                  imageHeightMm: mapping.lockAspectRatio
                      ? value * ratio
                      : mapping.imageHeightMm,
                ),
              );
              return;
            }
            _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(widthMm: value, maxWidthMm: value),
            );
          },
        ),
        const SizedBox(height: 12),
        _DecimalInputField(
          label: 'Height',
          value: mapping.heightMm,
          min: 2,
          max: instance.height,
          suffix: 'mm',
          onSubmitted: (value) {
            if (isImage) {
              final ratio =
                  mapping.assetWidthPx > 0 && mapping.assetHeightPx > 0
                  ? mapping.assetWidthPx / mapping.assetHeightPx
                  : mapping.widthMm / math.max(mapping.heightMm, 1);
              _updateMapping(
                mapping.fieldKey,
                mapping.copyWith(
                  heightMm: value,
                  widthMm: mapping.lockAspectRatio
                      ? value * ratio
                      : mapping.widthMm,
                  imageHeightMm: value,
                  imageWidthMm: mapping.lockAspectRatio
                      ? value * ratio
                      : mapping.imageWidthMm,
                ),
              );
              return;
            }
            _updateMapping(mapping.fieldKey, mapping.copyWith(heightMm: value));
          },
        ),
        if (block != null && !isImage) ...[
          const SizedBox(height: 12),
          _DecimalInputField(
            label: 'Font Size',
            value: mapping.fontSize,
            min: 6,
            max: 14,
            suffix: 'pt',
            onSubmitted: (value) => _updateStructuredBlockFont(mapping, value),
          ),
        ],
        if (isImage)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: mapping.lockAspectRatio,
            onChanged: (value) => _updateMapping(
              mapping.fieldKey,
              mapping.copyWith(lockAspectRatio: value),
            ),
            title: const Text('Lock Aspect Ratio'),
          ),
        if (isTableOwner)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              const Text(
                'Visible Columns',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              CheckboxListTile(
                value: _isTableColumnEnabled('hsn'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('HSN'),
                onChanged: (value) => _toggleTableColumn('hsn', value ?? false),
              ),
              CheckboxListTile(
                value: _isTableColumnEnabled('qty_pcs'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Qty'),
                onChanged: (value) =>
                    _toggleTableColumn('qty_pcs', value ?? false),
              ),
              CheckboxListTile(
                value: _isTableColumnEnabled('weight'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Weight'),
                onChanged: (value) =>
                    _toggleTableColumn('weight', value ?? false),
              ),
              CheckboxListTile(
                value: _isTableColumnEnabled('note'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Line Note'),
                subtitle: const Text('Prints below the item name.'),
                onChanged: (value) =>
                    _toggleTableColumn('note', value ?? false),
              ),
              const SizedBox(height: 8),
              const Text(
                'Column Rails',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Drag the vertical rails inside the table block to match the paper columns.',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              ..._tableRailConfigsForOwner(mapping).map(
                (rail) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DecimalInputField(
                    label: '${_tableRailLabel(rail.fieldKey)} X',
                    value: rail.xMm,
                    min: 0,
                    max: mapping.widthMm,
                    suffix: 'mm',
                    onSubmitted: (value) =>
                        _setTableRailX(mapping, rail.fieldKey, value),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _DecimalInputField(
                label: 'Table Height',
                value: mapping.tableHeightMm,
                min: 5,
                max: 240,
                suffix: 'mm',
                onSubmitted: (value) => _updateMapping(
                  mapping.fieldKey,
                  mapping.copyWith(
                    tableHeightMm: value,
                    heightMm: math.max(mapping.heightMm, value),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _DecimalInputField(
                label: 'Row Pitch',
                value: mapping.rowHeightMm,
                min: 2,
                max: 20,
                suffix: 'mm',
                onSubmitted: (value) => _updateMapping(
                  mapping.fieldKey,
                  mapping.copyWith(rowHeightMm: value),
                ),
              ),
              const SizedBox(height: 12),
              _DecimalInputField(
                label: 'Min Font Size',
                value: mapping.minFontSize,
                min: 6,
                max: 32,
                suffix: 'pt',
                onSubmitted: (value) => _updateMapping(
                  mapping.fieldKey,
                  mapping.copyWith(minFontSize: value),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Auto rows: ${_computedTableMaxRows(mapping)}',
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Drag one table block and the checked columns will auto-layout inside it.',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        if (!isTableOwner) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              'Advanced Controls',
              style: TextStyle(
                color: SoftErpTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text('Fine tune typography and color when needed.'),
            children: [
              if (!isImage)
                _DecimalInputField(
                  label: 'Letter Spacing',
                  value: mapping.letterSpacing,
                  min: -2,
                  max: 6,
                  suffix: '',
                  onSubmitted: (value) => _updateMapping(
                    mapping.fieldKey,
                    mapping.copyWith(letterSpacing: value),
                  ),
                ),
              if (!isImage) const SizedBox(height: 12),
              if (!isImage)
                TextField(
                  decoration: _editorInputDecoration(label: 'Max Characters'),
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
              if (!isImage) const SizedBox(height: 12),
              if (!isImage)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: mapping.alignment,
                  decoration: _editorInputDecoration(label: 'Alignment'),
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
              if (!isImage) const SizedBox(height: 12),
              if (!isImage)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _normalizedTextColor(mapping.textColor),
                  decoration: _editorInputDecoration(label: 'Text Color'),
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
              if (!isImage) const SizedBox(height: 12),
              if (!isImage)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: mapping.fontWeight == 'bold',
                  onChanged: (value) => _updateMapping(
                    mapping.fieldKey,
                    mapping.copyWith(fontWeight: value ? 'bold' : 'normal'),
                  ),
                  title: const Text('Bold'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        AppButton(
          label: block != null ? 'Remove Block' : 'Remove Asset',
          icon: Icons.delete_outline,
          variant: AppButtonVariant.secondary,
          onPressed: () {
            setState(() {
              _removeMapping(mapping.fieldKey);
              _selectedMappingFieldKey = null;
              _selectedMappingFieldKeys = <String>{};
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
      if (intent.reused) {
        final matchingScan = _scanForObjectKey(intent.objectKey);
        setState(() {
          _backgroundObjectKey = intent.objectKey;
          if (intent.canvasWidth > 0) {
            _canvasWidth = intent.canvasWidth;
          }
          if (intent.canvasHeight > 0) {
            _canvasHeight = intent.canvasHeight;
          }
          _localBackgroundBytes = null;
          _backgroundImageUrl = matchingScan?.imageUrl;
        });
        await _loadUploadedScans();
        return;
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
      await _loadUploadedScans();
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
    if (name.isEmpty || _backgroundObjectKey.isEmpty) {
      setState(() {
        _error = 'Template name and background scan are required.';
      });
      return;
    }
    if (!_layoutValidity.isValid) {
      setState(() => _error = _layoutValidity.message);
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
        partyType: ChallanTemplatePartyType.generic,
        partyId: 0,
        challanType: _challanType,
        backgroundObjectKey: _backgroundObjectKey,
        canvasWidth: _canvasWidth,
        canvasHeight: _canvasHeight,
        rotationDegrees: _rotationDegrees,
        globalOffsetXmm: _globalOffsetXmm,
        globalOffsetYmm: _globalOffsetYmm,
        stockSize: _stockSize,
        paperSize: _paperSize,
        nUpLayout: _nUpLayout,
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

  void _addStaticText() {
    final fieldKey = _newStaticFieldKey();
    final instance = _templateInstanceMm();
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
      widthMm: 80,
      heightMm: 14,
      imageWidthMm: 35,
      imageHeightMm: 20,
      lockAspectRatio: true,
      xMm: 0.12 * instance.width,
      yMm: 0.82 * instance.height,
      xPercent: 0.12,
      yPercent: 0.82,
      fontSize: 10,
      fontWeight: 'normal',
      alignment: 'left',
      textColor: 'black',
      letterSpacing: 0,
      maxChars: 0,
      maxWidthMm: 80,
      minFontSize: 6,
      minRows: 0,
      maxRows: 0,
      tableHeightMm: 60,
      rowHeightMm: 6,
    );
    setState(() {
      _mappings = [..._mappings, mapping];
      _selectedMappingFieldKey = fieldKey;
      _selectedMappingFieldKeys = {fieldKey};
    });
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
      final block = _blockForOwnerField(mapping.fieldKey);
      if (block != null) {
        _mappings = _syncStructuredBlockMappings(block, mapping, _mappings);
      } else {
        final index = _mappings.indexWhere(
          (entry) => entry.fieldKey == fieldKey,
        );
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
      }
    });
  }

  void _removeMapping(String fieldKey) {
    final block = _blockForOwnerField(fieldKey);
    if (block != null) {
      _mappings = _mappings
          .where(
            (entry) =>
                entry.fieldKey != block.ownerFieldKey &&
                !block.companionFieldKeys.contains(entry.fieldKey),
          )
          .toList();
      return;
    }
    _mappings = _mappings.where((entry) => entry.fieldKey != fieldKey).toList();
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
    final block = _blockForOwnerField(mapping.fieldKey);
    if (block != null) {
      return block.label;
    }
    if (mapping.fieldType.toUpperCase() == 'IMAGE') {
      return 'Stamp / Signature';
    }
    if (mapping.fieldType.toUpperCase() == 'STATIC') {
      return 'Static Text';
    }
    return _labelForField(mapping.fieldKey);
  }

  String _displayTextForMapping(ChallanTemplateMapping mapping) {
    final block = _blockForOwnerField(mapping.fieldKey);
    if (block != null) {
      if (block.ownerFieldKey == _tableOwnerKey) {
        final columns = <String>[
          'Particulars',
          if (_isTableColumnEnabled('hsn')) 'HSN',
          if (_isTableColumnEnabled('qty_pcs')) 'Qty',
          if (_isTableColumnEnabled('weight')) 'Weight',
          if (_isTableColumnEnabled('note')) 'Note',
        ];
        return '${block.label}\n${columns.join(' • ')}';
      }
      return '${block.label}\n${block.description}';
    }
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
      case 'hsn':
        return '4802';
      case 'qty_pcs':
        return '120';
      case 'weight':
        return '48.5';
      case 'note':
        return 'Packed in export-grade bundles';
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

  _TemplateLayoutValidity get _layoutValidity =>
      _resolveTemplateLayout(_stockSize, _paperSize, _nUpLayout);

  Size _templateInstanceMm() {
    final resolved = _layoutValidity.resolvedStockFrameMm;
    return Size(resolved.width, resolved.height);
  }

  Rect _mappingRect(
    ChallanTemplateMapping mapping,
    double canvasWidth,
    double canvasHeight,
  ) {
    final instance = _templateInstanceMm();
    final offsetMm = _mappingOffsetMm(mapping);
    final width = (mapping.widthMm / instance.width * canvasWidth).clamp(
      20.0,
      canvasWidth,
    );
    final height = (mapping.heightMm / instance.height * canvasHeight).clamp(
      20.0,
      canvasHeight,
    );
    return Rect.fromLTWH(
      (offsetMm.dx / instance.width * canvasWidth).clamp(
        0.0,
        math.max(0.0, canvasWidth - width),
      ),
      (offsetMm.dy / instance.height * canvasHeight).clamp(
        0.0,
        math.max(0.0, canvasHeight - height),
      ),
      width,
      height,
    );
  }

  Offset _mappingOffsetMm(ChallanTemplateMapping mapping) {
    final instance = _templateInstanceMm();
    final x = mapping.xMm > 0 || mapping.xPercent == 0
        ? mapping.xMm
        : mapping.xPercent * instance.width;
    final y = mapping.yMm > 0 || mapping.yPercent == 0
        ? mapping.yMm
        : mapping.yPercent * instance.height;
    return Offset(
      x.clamp(0.0, instance.width).toDouble(),
      y.clamp(0.0, instance.height).toDouble(),
    );
  }

  ChallanTemplateMapping _withMmPosition(
    ChallanTemplateMapping mapping, {
    double? xMm,
    double? yMm,
  }) {
    final instance = _templateInstanceMm();
    final current = _mappingOffsetMm(mapping);
    final nextX = (xMm ?? current.dx).clamp(0.0, instance.width).toDouble();
    final nextY = (yMm ?? current.dy).clamp(0.0, instance.height).toDouble();
    return mapping.copyWith(
      xMm: nextX,
      yMm: nextY,
      xPercent: instance.width <= 0 ? 0 : nextX / instance.width,
      yPercent: instance.height <= 0 ? 0 : nextY / instance.height,
    );
  }

  void _selectMapping(String fieldKey) {
    setState(() {
      _selectedMappingFieldKey = fieldKey;
      _selectedMappingFieldKeys = {fieldKey};
      final block = _blockForOwnerField(fieldKey);
      if (block != null) {
        _selectedBlockOwnerFieldKey = block.ownerFieldKey;
      }
    });
  }

  void _moveMappingByDelta(
    ChallanTemplateMapping mapping,
    Offset delta,
    double canvasWidth,
    double canvasHeight,
  ) {
    final rect = _mappingRect(mapping, canvasWidth, canvasHeight);
    final nextRect = rect.shift(delta);
    final nextLeft = nextRect.left
        .clamp(0.0, math.max(0.0, canvasWidth - rect.width))
        .toDouble();
    final nextTop = nextRect.top
        .clamp(0.0, math.max(0.0, canvasHeight - rect.height))
        .toDouble();
    final instance = _templateInstanceMm();
    final nextMapping = _withMmPosition(
      mapping,
      xMm: nextLeft / canvasWidth * instance.width,
      yMm: nextTop / canvasHeight * instance.height,
    );
    _updateMapping(mapping.fieldKey, nextMapping);
  }

  void _resizeMappingByDelta(
    ChallanTemplateMapping mapping,
    _ResizeHandle handle,
    Offset delta,
    double canvasWidth,
    double canvasHeight,
  ) {
    final instance = _templateInstanceMm();
    final rect = _mappingRect(mapping, canvasWidth, canvasHeight);
    var left = rect.left;
    var top = rect.top;
    var right = rect.right;
    var bottom = rect.bottom;
    if (handle.affectsLeft) {
      left += delta.dx;
    }
    if (handle.affectsRight) {
      right += delta.dx;
    }
    if (handle.affectsTop) {
      top += delta.dy;
    }
    if (handle.affectsBottom) {
      bottom += delta.dy;
    }
    var width = math.max(20.0, right - left);
    var height = math.max(20.0, bottom - top);
    if (mapping.fieldType.toUpperCase() == 'IMAGE' && mapping.lockAspectRatio) {
      final ratio = mapping.heightMm / math.max(mapping.widthMm, 0.1);
      if (handle.affectsLeft || handle.affectsRight) {
        height = width * ratio;
      } else {
        width = height / math.max(ratio, 0.01);
      }
    }
    left = left.clamp(0.0, math.max(0.0, canvasWidth - width));
    top = top.clamp(0.0, math.max(0.0, canvasHeight - height));
    final widthMm = (width / canvasWidth) * instance.width;
    final heightMm = (height / canvasHeight) * instance.height;
    final nextMapping = _withMmPosition(
      mapping.copyWith(
        widthMm: widthMm,
        heightMm: heightMm,
        maxWidthMm: mapping.fieldType.toUpperCase() == 'IMAGE'
            ? mapping.maxWidthMm
            : widthMm,
        imageWidthMm: mapping.fieldType.toUpperCase() == 'IMAGE'
            ? widthMm
            : mapping.imageWidthMm,
        imageHeightMm: mapping.fieldType.toUpperCase() == 'IMAGE'
            ? heightMm
            : mapping.imageHeightMm,
        tableHeightMm: mapping.fieldKey == 'item_particulars'
            ? heightMm
            : mapping.tableHeightMm,
      ),
      xMm: left / canvasWidth * instance.width,
      yMm: top / canvasHeight * instance.height,
    );
    _updateMapping(mapping.fieldKey, nextMapping);
  }

  Future<void> _openTestPrint({
    required int itemCount,
    List<ChallanTemplateMapping>? mappingsOverride,
  }) async {
    if (!_layoutValidity.isValid) {
      setState(() => _error = _layoutValidity.message);
      return;
    }
    final provider = context.read<DeliveryChallanProvider>();
    final templateId = _selectedTemplate?.id ?? 0;
    if (templateId <= 0) {
      return;
    }
    final handled = await _printPdfFromRepository(
      provider: provider,
      templateId: templateId,
      itemCount: itemCount,
      mappingsOverride: mappingsOverride,
      fallbackFileName: 'challan-template-test-$itemCount-items.pdf',
    );
    if (!handled && !Platform.isWindows && !Platform.isMacOS) {
      final uri = provider.repository.templateTestPrintUri(
        templateId: templateId,
        mode: 'digital',
        itemCount: itemCount,
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openFullTableTestPrint() async {
    final owner = _mappingForField(_tableOwnerKey);
    if (owner == null) {
      await _openTestPrint(itemCount: _testPrintMaxItemCount);
      return;
    }
    final printMappings = _syncStructuredBlockMappings(
      _requireBlock(_tableOwnerKey),
      owner.copyWith(
        fieldType: 'TABLE',
        fieldValue: _tableFieldValueForColumns(_tableColumnKeys),
      ),
      _mappings,
    );
    await _openTestPrint(
      itemCount: _testPrintMaxItemCount,
      mappingsOverride: printMappings,
    );
  }

  Future<void> _loadUploadedScans() async {
    if (!mounted) {
      return;
    }
    setState(() => _isLoadingScans = true);
    final scans = await context
        .read<DeliveryChallanProvider>()
        .loadTemplateScans();
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadedScans = scans;
      if (_localBackgroundBytes == null && _backgroundObjectKey.isNotEmpty) {
        final matchingScan = _scanForObjectKey(_backgroundObjectKey);
        _backgroundImageUrl = matchingScan?.imageUrl ?? _backgroundImageUrl;
      }
      _isLoadingScans = false;
    });
  }

  Future<bool> _printPdfFromRepository({
    required DeliveryChallanProvider provider,
    required int templateId,
    required int itemCount,
    List<ChallanTemplateMapping>? mappingsOverride,
    required String fallbackFileName,
  }) async {
    try {
      final bytes = await provider.repository.fetchTemplateTestPrintPdf(
        templateId: templateId,
        mode: 'digital',
        itemCount: itemCount,
        mappings: mappingsOverride,
      );
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fallbackFileName');
      await file.writeAsBytes(bytes, flush: true);

      if (Platform.isWindows) {
        await Printing.layoutPdf(
          name: fallbackFileName,
          onLayout: (_) async => bytes,
        );
        return true;
      }

      if (Platform.isMacOS) {
        final printed =
            await _nativePrintingChannel.invokeMethod<bool>('printPdfFile', {
              'filePath': file.path,
            }) ??
            false;
        return printed;
      }
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      setState(() => _error = error.message ?? error.code);
      return false;
    } catch (error) {
      setState(() => _error = error.toString());
      return false;
    }
    return false;
  }

  void _finishElementGesture() {}

  _TemplateLayoutValidity _resolveTemplateLayout(
    String stockSize,
    String paperSize,
    int nUpLayout,
  ) {
    final sheet = _paperSizeDimensionsMm(paperSize);
    final stock = _paperSizeDimensionsMm(stockSize);
    final slot = switch (nUpLayout) {
      2 => Size(sheet.width, sheet.height / 2),
      4 => Size(sheet.width / 2, sheet.height / 2),
      _ => sheet,
    };
    if (stock.width <= slot.width && stock.height <= slot.height) {
      return _TemplateLayoutValidity(
        isValid: true,
        resolvedStockFrameMm: stock,
        message:
            '$stockSize stock on $paperSize sheet at $nUpLayout-up. Frame ${stock.width.toStringAsFixed(1)} x ${stock.height.toStringAsFixed(1)} mm.',
      );
    }
    if (stock.height <= slot.width && stock.width <= slot.height) {
      return _TemplateLayoutValidity(
        isValid: true,
        resolvedStockFrameMm: Size(stock.height, stock.width),
        message:
            '$stockSize stock auto-rotates to fit $paperSize sheet at $nUpLayout-up. Frame ${stock.height.toStringAsFixed(1)} x ${stock.width.toStringAsFixed(1)} mm.',
      );
    }
    return _TemplateLayoutValidity(
      isValid: false,
      resolvedStockFrameMm: stock,
      message:
          '$stockSize stock does not fit on $paperSize sheet at $nUpLayout-up.',
    );
  }

  Size _paperSizeDimensionsMm(String size) {
    switch (size.toUpperCase()) {
      case 'A3':
        return const Size(297, 420);
      case 'A5':
        return const Size(148, 210);
      case 'A6':
        return const Size(105, 148);
      default:
        return const Size(210, 297);
    }
  }

  Widget _presetButton({
    required String label,
    required String stockSize,
    required String paperSize,
    required int nUpLayout,
  }) {
    final selected =
        _stockSize == stockSize &&
        _paperSize == paperSize &&
        _nUpLayout == nUpLayout;
    return KeyedSubtree(
      key: ValueKey<String>('template-preset-$label'),
      child: SoftPill(
        label: label,
        foreground: selected ? Colors.white : SoftErpTheme.textPrimary,
        background: selected
            ? SoftErpTheme.accent
            : SoftErpTheme.cardSurfaceAlt,
        onTap: () {
          setState(() {
            _stockSize = stockSize;
            _paperSize = paperSize;
            _nUpLayout = nUpLayout;
          });
        },
      ),
    );
  }

  List<ChallanTemplateMapping> get _canvasMappings => _mappings
      .where(
        (mapping) =>
            !_structuredCompanionFieldKeys.contains(mapping.fieldKey) ||
            _structuredOwnerFieldKeys.contains(mapping.fieldKey),
      )
      .toList(growable: false);

  bool _isTableColumnEnabled(String fieldKey) {
    final owner = _mappingForField(_tableOwnerKey);
    if (owner == null) {
      return false;
    }
    return _tableColumnsForOwner(owner).contains(fieldKey);
  }

  List<String> _tableColumnsForOwner(
    ChallanTemplateMapping owner, {
    List<ChallanTemplateMapping>? source,
  }) {
    return _tableRailConfigsForOwner(owner, source: source)
        .map((rail) => rail.fieldKey)
        .where((fieldKey) => fieldKey != _tableOwnerKey)
        .toList(growable: false);
  }

  List<_TableRailConfig> _tableRailConfigsForOwner(
    ChallanTemplateMapping owner, {
    List<ChallanTemplateMapping>? source,
  }) {
    final raw = owner.fieldValue.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        final columns = decoded is Map<String, dynamic>
            ? decoded['columns']
            : null;
        if (columns is List) {
          final rails = columns
              .map((column) => _parseTableRail(column, owner.widthMm))
              .whereType<_TableRailConfig>()
              .toList(growable: false);
          if (rails.isNotEmpty) {
            return _normalizeTableRails(rails, owner.widthMm);
          }
        }
      } catch (_) {
        // Legacy templates used separate hidden companion mappings.
      }
    }
    final fallbackSource = source ?? _mappings;
    final fields = <String>[
      _tableOwnerKey,
      ..._tableColumnKeys.where(
        (fieldKey) => fallbackSource.any((entry) => entry.fieldKey == fieldKey),
      ),
    ];
    return _normalizeTableRails(
      fields
          .map(
            (fieldKey) => _TableRailConfig(
              fieldKey: fieldKey,
              xMm: _defaultTableRailX(fieldKey, owner.widthMm),
            ),
          )
          .toList(growable: false),
      owner.widthMm,
    );
  }

  _TableRailConfig? _parseTableRail(Object? rawColumn, double tableWidthMm) {
    if (rawColumn is String) {
      final fieldKey = rawColumn.trim();
      if (fieldKey != _tableOwnerKey && !_tableColumnKeys.contains(fieldKey)) {
        return null;
      }
      return _TableRailConfig(
        fieldKey: fieldKey,
        xMm: _defaultTableRailX(fieldKey, tableWidthMm),
      );
    }
    if (rawColumn is Map<String, dynamic>) {
      final fieldKey =
          '${rawColumn['fieldKey'] ?? rawColumn['field_key'] ?? ''}'.trim();
      if (fieldKey != _tableOwnerKey && !_tableColumnKeys.contains(fieldKey)) {
        return null;
      }
      final xMm = (rawColumn['xMm'] as num? ?? rawColumn['x_mm'] as num?)
          ?.toDouble();
      return _TableRailConfig(
        fieldKey: fieldKey,
        xMm: xMm ?? _defaultTableRailX(fieldKey, tableWidthMm),
      );
    }
    return null;
  }

  List<_TableRailConfig> _normalizeTableRails(
    List<_TableRailConfig> rails,
    double tableWidthMm,
  ) {
    final normalized = <_TableRailConfig>[];
    void addRail(String fieldKey, double xMm) {
      if (normalized.any((rail) => rail.fieldKey == fieldKey)) {
        return;
      }
      normalized.add(
        _TableRailConfig(
          fieldKey: fieldKey,
          xMm: xMm.clamp(0.0, tableWidthMm).toDouble(),
        ),
      );
    }

    final itemRail = rails
        .where((rail) => rail.fieldKey == _tableOwnerKey)
        .firstOrNull;
    addRail(_tableOwnerKey, itemRail?.xMm ?? 0);
    for (final fieldKey in _tableColumnKeys) {
      final rail = rails
          .where((entry) => entry.fieldKey == fieldKey)
          .firstOrNull;
      if (rail != null) {
        addRail(fieldKey, rail.xMm);
      }
    }
    return normalized;
  }

  double _defaultTableRailX(String fieldKey, double widthMm) {
    return switch (fieldKey) {
      _tableOwnerKey => 0,
      'hsn' => widthMm * 0.58,
      'qty_pcs' => widthMm * 0.76,
      'weight' => widthMm * 0.88,
      'note' => 0,
      _ => 0,
    };
  }

  String _tableRailLabel(String fieldKey) {
    return switch (fieldKey) {
      _tableOwnerKey => 'Name',
      'hsn' => 'HSN',
      'qty_pcs' => 'Qty',
      'weight' => 'Weight',
      'note' => 'Note',
      _ => fieldKey,
    };
  }

  String _tableFieldValueForRails(List<_TableRailConfig> rails) {
    return jsonEncode(<String, dynamic>{
      'columns':
          _normalizeTableRails(
                rails,
                _mappingForField(_tableOwnerKey)?.widthMm ?? 150,
              )
              .map(
                (rail) => <String, dynamic>{
                  'fieldKey': rail.fieldKey,
                  'xMm': double.parse(rail.xMm.toStringAsFixed(2)),
                },
              )
              .toList(growable: false),
      'printNotes': rails.any((rail) => rail.fieldKey == 'note'),
    });
  }

  void _moveTableRailByDelta(
    ChallanTemplateMapping owner,
    String fieldKey,
    double deltaMm,
  ) {
    final rails = _tableRailConfigsForOwner(owner)
        .map(
          (rail) => rail.fieldKey == fieldKey
              ? _TableRailConfig(
                  fieldKey: rail.fieldKey,
                  xMm: (rail.xMm + deltaMm)
                      .clamp(0.0, owner.widthMm)
                      .toDouble(),
                )
              : rail,
        )
        .toList(growable: false);
    _updateMapping(
      owner.fieldKey,
      owner.copyWith(fieldValue: _tableFieldValueForRails(rails)),
    );
  }

  void _setTableRailX(
    ChallanTemplateMapping owner,
    String fieldKey,
    double xMm,
  ) {
    final rails = _tableRailConfigsForOwner(owner)
        .map(
          (rail) => rail.fieldKey == fieldKey
              ? _TableRailConfig(
                  fieldKey: rail.fieldKey,
                  xMm: xMm.clamp(0.0, owner.widthMm).toDouble(),
                )
              : rail,
        )
        .toList(growable: false);
    _updateMapping(
      owner.fieldKey,
      owner.copyWith(fieldValue: _tableFieldValueForRails(rails)),
    );
  }

  String _tableFieldValueForColumns(List<String> columns) {
    final owner = _mappingForField(_tableOwnerKey);
    final currentRails = owner == null
        ? const <_TableRailConfig>[]
        : _tableRailConfigsForOwner(owner);
    final nextRails = <_TableRailConfig>[];
    _TableRailConfig railFor(String fieldKey) {
      return currentRails
              .where((rail) => rail.fieldKey == fieldKey)
              .firstOrNull ??
          _TableRailConfig(
            fieldKey: fieldKey,
            xMm: _defaultTableRailX(fieldKey, owner?.widthMm ?? 150),
          );
    }

    nextRails.add(railFor(_tableOwnerKey));
    for (final column in columns) {
      if (_tableColumnKeys.contains(column) &&
          !nextRails.any((rail) => rail.fieldKey == column)) {
        nextRails.add(railFor(column));
      }
    }
    return _tableFieldValueForRails(nextRails);
  }

  int _computedTableMaxRows(ChallanTemplateMapping owner) {
    final pitch = math.max(owner.rowHeightMm, 0.1);
    return math.max(1, (owner.tableHeightMm / pitch).floor());
  }

  int get _testPrintMaxItemCount {
    final owner = _mappingForField(_tableOwnerKey);
    if (owner == null) {
      return 1;
    }
    final computedRows = _computedTableMaxRows(owner);
    if (owner.maxRows <= 0) {
      return computedRows;
    }
    return math.max(1, math.min(owner.maxRows, computedRows));
  }

  void _toggleTableColumn(String fieldKey, bool enabled) {
    final owner = _mappingForField(_tableOwnerKey);
    if (owner == null) {
      return;
    }
    setState(() {
      final columns = _tableColumnsForOwner(owner).toList();
      if (enabled && !columns.contains(fieldKey)) {
        columns.add(fieldKey);
      } else if (!enabled) {
        columns.remove(fieldKey);
      }
      _mappings = _syncStructuredBlockMappings(
        _requireBlock(_tableOwnerKey),
        owner.copyWith(fieldValue: _tableFieldValueForColumns(columns)),
        _mappings,
      );
    });
  }

  void _updateStructuredBlockFont(
    ChallanTemplateMapping owner,
    double fontSize,
  ) {
    final block = _blockForOwnerField(owner.fieldKey);
    if (block == null) {
      _updateMapping(owner.fieldKey, owner.copyWith(fontSize: fontSize));
      return;
    }
    setState(() {
      final current = _syncStructuredBlockMappings(block, owner, _mappings);
      _mappings = current
          .map((entry) {
            if (entry.fieldKey == block.ownerFieldKey ||
                block.companionFieldKeys.contains(entry.fieldKey)) {
              return entry.copyWith(fontSize: fontSize, minFontSize: fontSize);
            }
            return entry;
          })
          .toList(growable: false);
    });
  }

  List<ChallanTemplateMapping> _normalizeStructuredMappings(
    List<ChallanTemplateMapping> mappings,
  ) {
    var next = mappings
        .map((mapping) => _withMmPosition(mapping))
        .toList(growable: true);
    for (final block in _blocks) {
      ChallanTemplateMapping? owner;
      for (final entry in next) {
        if (entry.fieldKey == block.ownerFieldKey) {
          owner = entry;
          break;
        }
      }
      if (owner == null) {
        for (final entry in next) {
          if (block.companionFieldKeys.contains(entry.fieldKey)) {
            owner = _coerceOwnerMapping(block, entry);
            break;
          }
        }
      }
      if (owner == null) {
        continue;
      }
      next = _syncStructuredBlockMappings(block, owner, next);
    }
    return next;
  }

  List<ChallanTemplateMapping> _syncStructuredBlockMappings(
    _TemplateBlockSpec block,
    ChallanTemplateMapping owner,
    List<ChallanTemplateMapping> source,
  ) {
    final next = <ChallanTemplateMapping>[];
    for (final entry in source) {
      if (entry.fieldKey == block.ownerFieldKey ||
          block.companionFieldKeys.contains(entry.fieldKey)) {
        continue;
      }
      next.add(entry);
    }
    final enabledCompanionFieldKeys = block.isTable
        ? _tableColumnsForOwner(owner, source: source)
        : block.companionFieldKeys;
    final normalizedOwner = owner.copyWith(
      fieldType: block.isTable ? 'TABLE' : 'DYNAMIC',
      fieldKey: block.ownerFieldKey,
      fieldValue: block.isTable
          ? _tableFieldValueForColumns(enabledCompanionFieldKeys)
          : owner.fieldValue,
      maxWidthMm: block.isTable ? owner.widthMm : owner.widthMm,
      tableHeightMm: block.isTable ? owner.heightMm : owner.tableHeightMm,
      maxRows: block.isTable ? _computedTableMaxRows(owner) : owner.maxRows,
    );
    next.add(normalizedOwner);
    if (block.isTable) {
      return next;
    }
    for (final fieldKey in block.companionFieldKeys) {
      final enabled =
          !block.isTable || enabledCompanionFieldKeys.contains(fieldKey);
      if (!enabled) {
        continue;
      }
      final existing = source.firstWhere(
        (entry) => entry.fieldKey == fieldKey,
        orElse: () => _buildStructuredBlockCompanion(fieldKey, owner),
      );
      next.add(
        _positionCompanionWithinBlock(
          block,
          owner,
          existing,
          enabledCompanionFieldKeys,
        ),
      );
    }
    return next;
  }

  ChallanTemplateMapping _buildStructuredBlockCompanion(
    String fieldKey,
    ChallanTemplateMapping owner,
  ) {
    return ChallanTemplateMapping(
      id: 0,
      templateId: _selectedTemplate?.id ?? owner.templateId,
      fieldType: 'DYNAMIC',
      fieldKey: fieldKey,
      fieldValue: '',
      assetObjectKey: '',
      assetImageUrl: null,
      assetWidthPx: 0,
      assetHeightPx: 0,
      widthMm: owner.widthMm,
      heightMm: owner.heightMm,
      imageWidthMm: 35,
      imageHeightMm: 20,
      lockAspectRatio: true,
      xMm: owner.xMm,
      yMm: owner.yMm,
      xPercent: owner.xPercent,
      yPercent: owner.yPercent,
      fontSize: owner.fontSize,
      fontWeight: owner.fontWeight,
      alignment: fieldKey == 'hsn' ? 'center' : 'left',
      textColor: 'black',
      letterSpacing: 0,
      maxChars: 0,
      maxWidthMm: owner.widthMm,
      minFontSize: owner.minFontSize,
      minRows: owner.minRows,
      maxRows: owner.maxRows,
      tableHeightMm: owner.tableHeightMm,
      rowHeightMm: owner.rowHeightMm,
    );
  }

  void _ensureBlock(_TemplateBlockSpec block) {
    final existing = _mappingForField(block.ownerFieldKey);
    if (existing != null) {
      _selectMapping(block.ownerFieldKey);
      return;
    }
    final owner = _defaultOwnerMapping(block);
    setState(() {
      _mappings = _syncStructuredBlockMappings(block, owner, _mappings);
      _selectedBlockOwnerFieldKey = block.ownerFieldKey;
      _selectedMappingFieldKey = block.ownerFieldKey;
      _selectedMappingFieldKeys = <String>{block.ownerFieldKey};
    });
  }

  void _toggleBlockPlacement(_TemplateBlockSpec block) {
    final existing = _mappingForField(block.ownerFieldKey);
    if (existing == null) {
      _ensureBlock(block);
      return;
    }
    setState(() {
      _removeMapping(block.ownerFieldKey);
      if (_selectedMappingFieldKey == block.ownerFieldKey) {
        _selectedMappingFieldKey = null;
        _selectedMappingFieldKeys = <String>{};
      }
      _selectedBlockOwnerFieldKey = block.ownerFieldKey;
    });
  }

  _TemplateBlockSpec? _blockForOwnerField(String fieldKey) {
    for (final block in _blocks) {
      if (block.ownerFieldKey == fieldKey) {
        return block;
      }
    }
    return null;
  }

  _TemplateBlockSpec _requireBlock(String fieldKey) =>
      _blockForOwnerField(fieldKey)!;

  Set<String> get _structuredOwnerFieldKeys =>
      _blocks.map((block) => block.ownerFieldKey).toSet();

  Set<String> get _structuredCompanionFieldKeys =>
      _blocks.expand((block) => block.companionFieldKeys).toSet();

  ChallanTemplateMapping _defaultOwnerMapping(_TemplateBlockSpec block) {
    final instance = _templateInstanceMm();
    return ChallanTemplateMapping(
      id: 0,
      templateId: _selectedTemplate?.id ?? 0,
      fieldType: block.isTable ? 'TABLE' : 'DYNAMIC',
      fieldKey: block.ownerFieldKey,
      fieldValue: block.isTable
          ? _tableFieldValueForColumns(_tableColumnKeys)
          : '',
      assetObjectKey: '',
      assetImageUrl: null,
      assetWidthPx: 0,
      assetHeightPx: 0,
      widthMm: block.defaultWidthMm,
      heightMm: block.defaultHeightMm,
      imageWidthMm: 35,
      imageHeightMm: 20,
      lockAspectRatio: true,
      xMm: block.defaultXPercent * instance.width,
      yMm: block.defaultYPercent * instance.height,
      xPercent: block.defaultXPercent,
      yPercent: block.defaultYPercent,
      fontSize: 10,
      fontWeight: 'normal',
      alignment: 'left',
      textColor: 'black',
      letterSpacing: 0,
      maxChars: 0,
      maxWidthMm: block.defaultWidthMm,
      minFontSize: 6,
      minRows: 0,
      maxRows: block.isTable ? 11 : 0,
      tableHeightMm: block.defaultHeightMm,
      rowHeightMm: 6,
    );
  }

  ChallanTemplateMapping _coerceOwnerMapping(
    _TemplateBlockSpec block,
    ChallanTemplateMapping seed,
  ) {
    final base = _defaultOwnerMapping(block);
    return base.copyWith(
      fieldType: block.isTable ? 'TABLE' : seed.fieldType,
      fieldValue: block.isTable
          ? _tableFieldValueForColumns(_tableColumnsForOwner(seed))
          : seed.fieldValue,
      xMm: _mappingOffsetMm(seed).dx,
      yMm: _mappingOffsetMm(seed).dy,
      xPercent: seed.xPercent,
      yPercent: seed.yPercent,
      widthMm: seed.widthMm > 0 ? seed.widthMm : base.widthMm,
      heightMm: seed.heightMm > 0 ? seed.heightMm : base.heightMm,
      maxWidthMm: seed.widthMm > 0 ? seed.widthMm : base.maxWidthMm,
      tableHeightMm: block.isTable
          ? (seed.tableHeightMm > 0 ? seed.tableHeightMm : seed.heightMm)
          : base.tableHeightMm,
      rowHeightMm: seed.rowHeightMm > 0 ? seed.rowHeightMm : base.rowHeightMm,
      fontSize: seed.fontSize > 0 ? seed.fontSize : base.fontSize,
      minFontSize: seed.minFontSize > 0 ? seed.minFontSize : base.minFontSize,
    );
  }

  ChallanTemplateMapping _positionCompanionWithinBlock(
    _TemplateBlockSpec block,
    ChallanTemplateMapping owner,
    ChallanTemplateMapping companion,
    List<String> enabledCompanionFieldKeys,
  ) {
    final frame = _resolveFieldFrame(
      block,
      owner,
      companion.fieldKey,
      enabledCompanionFieldKeys,
    );
    return companion.copyWith(
      fieldType: 'DYNAMIC',
      fieldKey: companion.fieldKey,
      xMm: frame.left,
      yMm: frame.top,
      xPercent: frame.left / _templateInstanceMm().width,
      yPercent: frame.top / _templateInstanceMm().height,
      widthMm: frame.width,
      heightMm: frame.height,
      maxWidthMm: frame.width,
      tableHeightMm: block.isTable ? owner.heightMm : companion.tableHeightMm,
      rowHeightMm: block.isTable ? owner.rowHeightMm : companion.rowHeightMm,
      maxRows: block.isTable ? _computedTableMaxRows(owner) : companion.maxRows,
      minFontSize: owner.minFontSize,
      fontSize: owner.fontSize,
      alignment: switch (companion.fieldKey) {
        'hsn' => 'center',
        'qty_pcs' || 'weight' => 'right',
        _ => 'left',
      },
    );
  }

  Rect _resolveFieldFrame(
    _TemplateBlockSpec block,
    ChallanTemplateMapping owner,
    String fieldKey,
    List<String> enabledCompanionFieldKeys,
  ) {
    final offset = _mappingOffsetMm(owner);
    final left = offset.dx;
    final top = offset.dy;
    if (block.isTable) {
      final enabledColumns = <String>[
        _tableOwnerKey,
        ...enabledCompanionFieldKeys,
      ];
      final columnWidth = owner.widthMm / math.max(enabledColumns.length, 1);
      final index = enabledColumns
          .indexOf(fieldKey)
          .clamp(0, enabledColumns.length - 1);
      return Rect.fromLTWH(
        left + columnWidth * index,
        top,
        columnWidth,
        owner.heightMm,
      );
    }
    return Rect.fromLTWH(left, top, owner.widthMm, owner.heightMm);
  }
}

class _TemplateBlockSpec {
  const _TemplateBlockSpec({
    required this.ownerFieldKey,
    required this.label,
    required this.description,
    required this.companionFieldKeys,
    required this.defaultXPercent,
    required this.defaultYPercent,
    required this.defaultWidthMm,
    required this.defaultHeightMm,
    this.isTable = false,
  });

  final String ownerFieldKey;
  final String label;
  final String description;
  final List<String> companionFieldKeys;
  final double defaultXPercent;
  final double defaultYPercent;
  final double defaultWidthMm;
  final double defaultHeightMm;
  final bool isTable;
}

class _TemplateField {
  const _TemplateField(
    this.key,
    this.label, {
    this.isTable = false,
    this.hiddenFromPalette = false,
  });

  final String key;
  final String label;
  final bool isTable;
  final bool hiddenFromPalette;
}

class _TableRailConfig {
  const _TableRailConfig({required this.fieldKey, required this.xMm});

  final String fieldKey;
  final double xMm;
}

class _MappedCanvasElement extends StatelessWidget {
  const _MappedCanvasElement({
    required this.mapping,
    required this.label,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.boxWidth,
    required this.boxHeight,
    required this.localImageBytes,
    required this.imageUrl,
    required this.tableRails,
    required this.selected,
    required this.showBoundingBox,
    required this.onTap,
    required this.onDrag,
    required this.onDragEnd,
    required this.onResize,
    required this.onResizeEnd,
    required this.onRailDrag,
  });

  final ChallanTemplateMapping mapping;
  final String label;
  final double canvasWidth;
  final double canvasHeight;
  final double boxWidth;
  final double boxHeight;
  final Uint8List? localImageBytes;
  final String? imageUrl;
  final List<_TableRailConfig> tableRails;
  final bool selected;
  final bool showBoundingBox;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;
  final void Function(_ResizeHandle handle, Offset delta) onResize;
  final VoidCallback onResizeEnd;
  final void Function(String fieldKey, double deltaMm) onRailDrag;

  @override
  Widget build(BuildContext context) {
    final scale = canvasWidth / 595.28;
    final textColor = switch (mapping.textColor.toLowerCase()) {
      'blue' => const Color(0xFF1D4ED8),
      'red' => const Color(0xFFB91C1C),
      _ => SoftErpTheme.textPrimary,
    };
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: (details) => onDrag(details.delta),
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragEnd,
      child: Container(
        width: boxWidth,
        height: boxHeight,
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: mapping.fieldType.toUpperCase() == 'IMAGE'
                    ? (localImageBytes != null
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
                                  )))
                    : Align(
                        alignment: switch (mapping.alignment) {
                          'center' => Alignment.topCenter,
                          'right' => Alignment.topRight,
                          _ => Alignment.topLeft,
                        },
                        child: Text(
                          label,
                          maxLines: 6,
                          overflow: TextOverflow.visible,
                          textAlign: switch (mapping.alignment) {
                            'center' => TextAlign.center,
                            'right' => TextAlign.right,
                            _ => TextAlign.left,
                          },
                          style: TextStyle(
                            color: textColor,
                            fontSize: (mapping.fontSize * scale).clamp(
                              6.0,
                              30.0,
                            ),
                            fontWeight: mapping.fontWeight == 'bold'
                                ? FontWeight.w800
                                : FontWeight.w500,
                            letterSpacing: mapping.letterSpacing * scale,
                          ),
                        ),
                      ),
              ),
            ),
            if (selected)
              ...const [_ResizeHandle.bottomRight].map(
                (handle) => _ResizeHandleWidget(
                  handle: handle,
                  onDrag: (delta) => onResize(handle, delta),
                  onDragEnd: onResizeEnd,
                ),
              ),
            if (selected && tableRails.isNotEmpty)
              ...tableRails.map(
                (rail) => _TableRailHandle(
                  rail: rail,
                  tableWidthMm: mapping.widthMm,
                  boxWidth: boxWidth,
                  boxHeight: boxHeight,
                  onDrag: (deltaMm) => onRailDrag(rail.fieldKey, deltaMm),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TableRailHandle extends StatelessWidget {
  const _TableRailHandle({
    required this.rail,
    required this.tableWidthMm,
    required this.boxWidth,
    required this.boxHeight,
    required this.onDrag,
  });

  final _TableRailConfig rail;
  final double tableWidthMm;
  final double boxWidth;
  final double boxHeight;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final left = tableWidthMm <= 0
        ? 0.0
        : (rail.xMm / tableWidthMm * boxWidth).clamp(0.0, boxWidth).toDouble();
    final label = switch (rail.fieldKey) {
      'item_particulars' => 'Name',
      'hsn' => 'HSN',
      'qty_pcs' => 'Qty',
      'weight' => 'Weight',
      'note' => 'Note',
      _ => rail.fieldKey,
    };
    return Positioned(
      left: left - 12,
      top: 0,
      width: 24,
      height: boxHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          if (boxWidth <= 0 || tableWidthMm <= 0) {
            return;
          }
          onDrag(details.delta.dx / boxWidth * tableWidthMm);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Container(
                width: 2,
                height: boxHeight,
                decoration: BoxDecoration(
                  color: SoftErpTheme.accent.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Positioned(
              top: -22,
              left: -18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: SoftErpTheme.accent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: SoftErpTheme.accent.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadedScanTile extends StatelessWidget {
  const _UploadedScanTile({
    required this.scan,
    required this.selected,
    required this.onTap,
  });

  final ChallanTemplateScan scan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fileName = scan.fileName.isNotEmpty
        ? scan.fileName
        : scan.objectKey.split('/').last;
    final dimensions = scan.canvasWidth > 0 && scan.canvasHeight > 0
        ? '${scan.canvasWidth} x ${scan.canvasHeight}'
        : 'Dimensions pending';
    return Material(
      color: selected ? const Color(0xFFEFF6FF) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 48,
                  height: 62,
                  color: const Color(0xFFF4F7FB),
                  child: scan.imageUrl == null || scan.imageUrl!.isEmpty
                      ? const Icon(
                          Icons.description_outlined,
                          color: SoftErpTheme.textSecondary,
                        )
                      : Image.network(scan.imageUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dimensions,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: SoftErpTheme.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ResizeHandle {
  topLeft(true, false, true, false),
  topCenter(false, false, true, false),
  topRight(false, true, true, false),
  centerLeft(true, false, false, false),
  centerRight(false, true, false, false),
  bottomLeft(true, false, false, true),
  bottomCenter(false, false, false, true),
  bottomRight(false, true, false, true);

  const _ResizeHandle(
    this.affectsLeft,
    this.affectsRight,
    this.affectsTop,
    this.affectsBottom,
  );

  final bool affectsLeft;
  final bool affectsRight;
  final bool affectsTop;
  final bool affectsBottom;
}

class _ResizeHandleWidget extends StatelessWidget {
  const _ResizeHandleWidget({
    required this.handle,
    required this.onDrag,
    required this.onDragEnd,
  });

  final _ResizeHandle handle;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final position = switch (handle) {
      _ResizeHandle.topLeft => const _HandlePosition(left: -12, top: -12),
      _ResizeHandle.topCenter => const _HandlePosition(top: -12),
      _ResizeHandle.topRight => const _HandlePosition(right: -12, top: -12),
      _ResizeHandle.centerLeft => const _HandlePosition(left: -12),
      _ResizeHandle.centerRight => const _HandlePosition(right: -12),
      _ResizeHandle.bottomLeft => const _HandlePosition(left: -12, bottom: -12),
      _ResizeHandle.bottomCenter => const _HandlePosition(bottom: -12),
      _ResizeHandle.bottomRight => const _HandlePosition(
        right: -12,
        bottom: -12,
      ),
    };
    return Positioned(
      left: position.left,
      right: position.right,
      top: position.top,
      bottom: position.bottom,
      child: Align(
        alignment: switch (handle) {
          _ResizeHandle.topLeft => Alignment.topLeft,
          _ResizeHandle.topCenter => Alignment.topCenter,
          _ResizeHandle.topRight => Alignment.topRight,
          _ResizeHandle.centerLeft => Alignment.centerLeft,
          _ResizeHandle.centerRight => Alignment.centerRight,
          _ResizeHandle.bottomLeft => Alignment.bottomLeft,
          _ResizeHandle.bottomCenter => Alignment.bottomCenter,
          _ResizeHandle.bottomRight => Alignment.bottomRight,
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => onDrag(details.delta),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: SoftErpTheme.accent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white, width: 1.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HandlePosition {
  const _HandlePosition({this.left, this.right, this.top, this.bottom});

  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
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

class _TemplateLayoutValidity {
  const _TemplateLayoutValidity({
    required this.isValid,
    required this.resolvedStockFrameMm,
    required this.message,
  });

  final bool isValid;
  final Size resolvedStockFrameMm;
  final String message;
}

class _TemplateLayoutHint extends StatelessWidget {
  const _TemplateLayoutHint({required this.validity});

  final _TemplateLayoutValidity validity;

  @override
  Widget build(BuildContext context) {
    final background = validity.isValid
        ? const Color(0xFFF0F7F4)
        : const Color(0xFFFFF1F0);
    final border = validity.isValid
        ? const Color(0xFFB7D6C2)
        : const Color(0xFFF3B4AF);
    final foreground = validity.isValid
        ? const Color(0xFF1F5C3F)
        : const Color(0xFF9F1D18);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text(
        validity.message,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

InputDecoration _editorInputDecoration({
  String? label,
  String? helper,
  String? hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF6049E3)),
    ),
    helperStyle: const TextStyle(
      color: SoftErpTheme.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ),
  );
}

class _DecimalInputField extends StatefulWidget {
  const _DecimalInputField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onSubmitted,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onSubmitted;

  @override
  State<_DecimalInputField> createState() => _DecimalInputFieldState();
}

class _DecimalInputFieldState extends State<_DecimalInputField> {
  late final TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(covariant _DecimalInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.value != widget.value) {
      _controller.text = _format(widget.value);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  void _commit(String input, {bool finishEditing = false}) {
    final parsed = double.tryParse(input.trim());
    if (parsed != null) {
      widget.onSubmitted(parsed.clamp(widget.min, widget.max).toDouble());
    }
    if (finishEditing) {
      setState(() => _isEditing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      decoration: _editorInputDecoration(
        label: widget.label,
        helper:
            'Range: ${widget.min.toStringAsFixed(widget.min == widget.min.roundToDouble() ? 0 : 1)} - ${widget.max.toStringAsFixed(widget.max == widget.max.roundToDouble() ? 0 : 1)}${widget.suffix.isEmpty ? '' : ' ${widget.suffix}'}',
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onTap: () => setState(() => _isEditing = true),
      onChanged: (input) => _commit(input),
      onFieldSubmitted: (input) => _commit(input, finishEditing: true),
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
