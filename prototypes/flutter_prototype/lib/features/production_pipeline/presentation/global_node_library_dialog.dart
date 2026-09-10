import 'package:flutter/material.dart';
import '../../../app/shell/prototype_theme.dart';
import '../../sheet_planning/domain/sheet_plan.dart';
import '../domain/process_node.dart';

class NodeTemplateItem {
  final String id;
  final String title;
  final String category;
  final String description;
  final String defaultMachine;
  final String? defaultDie;
  final String materialIn;
  final String itemOut;
  final String? scrapItem;
  final SheetPlan? sheetPlan;

  const NodeTemplateItem({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.defaultMachine,
    this.defaultDie,
    required this.materialIn,
    required this.itemOut,
    this.scrapItem,
    this.sheetPlan,
  });
}

final List<NodeTemplateItem> globalNodePresets = [
  NodeTemplateItem(
    id: 'tpl-slitting-8',
    title: 'Rotary Slitting (8 Strips)',
    category: 'Shearing & Slitting',
    description: 'Slits 48" wide master coils/sheets into 8 equal strips with 10mm edge trim.',
    defaultMachine: 'RS-1250',
    materialIn: 'MS Sheet 1.2mm',
    itemOut: 'MS Slit Strips (8)',
    scrapItem: 'Edge Trim Scrap',
    sheetPlan: SheetPlan.empty().copyWith(
      sheetWidthInches: 48,
      sheetHeightInches: 96,
      sheetThicknessMm: 1.2,
      edgeTrimMm: 10,
      kerfMm: 2,
      materialName: 'Steel / MS',
      bands: [const Band(sizeMm: 145, count: 8)],
    ),
  ),
  NodeTemplateItem(
    id: 'tpl-blanking-72',
    title: 'Guillotine Blanking (72 Blanks)',
    category: 'Blanking & Stamping',
    description: 'Cross-cuts slit strips into 72 precision rectangular blanks (145×260mm).',
    defaultMachine: 'G-300',
    defaultDie: 'D-G9-BLANK-01',
    materialIn: 'MS Slit Strips (8)',
    itemOut: 'Enclosure Blank 145×260',
    scrapItem: 'Offcut Tail Scrap',
    sheetPlan: SheetPlan.empty().copyWith(
      sheetWidthInches: 48,
      sheetHeightInches: 96,
      sheetThicknessMm: 1.2,
      edgeTrimMm: 10,
      kerfMm: 2,
      materialName: 'Steel / MS',
      bands: [const Band(sizeMm: 145, count: 8)],
      subCuts: {
        0: [const SubCut(sizeMm: 260, count: 9)],
      },
      plannedPartName: 'Enclosure Blank 145×260',
    ),
  ),
  const NodeTemplateItem(
    id: 'tpl-pierce-cnc',
    title: 'CNC Turret Piercing & Notch',
    category: 'Blanking & Stamping',
    description: 'High-speed cluster punch operation for screw clearances and ventilation slots.',
    defaultMachine: 'PP-40T-01',
    defaultDie: 'D-SE-PIERCE-01',
    materialIn: 'Enclosure Blank 145×260',
    itemOut: 'Pierced Enclosure Blank',
    scrapItem: 'Slug Scrap (MS)',
  ),
  const NodeTemplateItem(
    id: 'tpl-press-brake',
    title: 'Hydraulic Press Forming / Bending',
    category: 'Forming',
    description: '4-axis CNC brake bend forming 90° enclosure side flanges.',
    defaultMachine: 'PP-63T-01',
    defaultDie: 'D-SE-FORM-01',
    materialIn: 'Pierced Enclosure Blank',
    itemOut: 'Formed Enclosure Body',
  ),
  const NodeTemplateItem(
    id: 'tpl-zinc-plating',
    title: 'Zinc Electroplating & Blue Passivation',
    category: 'Surface Finishing',
    description: 'Electrolytic zinc coating 8-12 microns with trivalent chromium passivation.',
    defaultMachine: 'PL-ZN-01',
    materialIn: 'Formed Enclosure Body',
    itemOut: 'Plated Enclosure Body',
  ),
  const NodeTemplateItem(
    id: 'tpl-sub-assembly',
    title: 'Bench Sub-Assembly & Fastening',
    category: 'Assembly & Packaging',
    description: 'Pneumatic clinch nut insertion and gasket assembly.',
    defaultMachine: 'AB-01',
    materialIn: 'Plated Enclosure Body',
    itemOut: 'Precision Enclosure Sub-Assy',
  ),
  const NodeTemplateItem(
    id: 'tpl-final-qc-pack',
    title: 'Final QC & Bulk Corrugated Packing',
    category: 'Assembly & Packaging',
    description: '100% Go/No-Go gauge check and protective foam packing.',
    defaultMachine: 'AB-02',
    materialIn: 'Precision Enclosure Sub-Assy',
    itemOut: 'Finished Packaged Box',
  ),
];

class GlobalNodeLibraryDialog extends StatefulWidget {
  final Function(NodeTemplateItem item) onSelectTemplate;
  final ProcessNode? currentNodeToSave;
  final Function(NodeTemplateItem savedItem)? onSaveCurrentNode;

  const GlobalNodeLibraryDialog({
    super.key,
    required this.onSelectTemplate,
    this.currentNodeToSave,
    this.onSaveCurrentNode,
  });

  @override
  State<GlobalNodeLibraryDialog> createState() => _GlobalNodeLibraryDialogState();
}

class _GlobalNodeLibraryDialogState extends State<GlobalNodeLibraryDialog> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  NodeTemplateItem? _selectedItem;

  bool _isSaveMode = false;
  final _saveTitleController = TextEditingController();
  final _saveDescController = TextEditingController();

  final List<String> _categories = [
    'All',
    'Shearing & Slitting',
    'Blanking & Stamping',
    'Forming',
    'Surface Finishing',
    'Assembly & Packaging',
  ];

  @override
  void initState() {
    super.initState();
    if (globalNodePresets.isNotEmpty) {
      _selectedItem = globalNodePresets.first;
    }
    if (widget.currentNodeToSave != null) {
      _saveTitleController.text = widget.currentNodeToSave!.name;
      _saveDescController.text = 'Custom MES template configured from ${widget.currentNodeToSave!.name}';
    }
  }

  @override
  void dispose() {
    _saveTitleController.dispose();
    _saveDescController.dispose();
    super.dispose();
  }

  List<NodeTemplateItem> get _filteredPresets {
    return globalNodePresets.where((p) {
      final matchesCat = _selectedCategory == 'All' || p.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          p.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.defaultMachine.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        width: 820,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accentLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.hub_outlined, color: AppColors.accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isSaveMode ? 'Save Node to Global Library' : 'Global Process Node Library',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              _isSaveMode
                                  ? 'Publish this node configuration to reusable company templates'
                                  : 'Select from standardized manufacturing operations or reusable templates',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.currentNodeToSave != null)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _isSaveMode = !_isSaveMode;
                          });
                        },
                        icon: Icon(_isSaveMode ? Icons.list_alt : Icons.bookmark_add_outlined, size: 16),
                        label: Text(_isSaveMode ? 'Browse Library' : 'Save Current Node'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 16),

            // Main Content Area
            Expanded(
              child: _isSaveMode ? _buildSaveCurrentNodeView() : _buildBrowsePresetsView(),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 16),

            // Footer Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    _isSaveMode
                        ? 'Saved templates are accessible across all line pipelines'
                        : '${_filteredPresets.length} standard operations available',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 12),
                    if (_isSaveMode)
                      ElevatedButton.icon(
                        onPressed: _handleSaveCurrentNode,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Save to Library'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          elevation: 0,
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _selectedItem != null
                            ? () {
                                widget.onSelectTemplate(_selectedItem!);
                                Navigator.of(context).pop();
                              }
                            : null,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Insert Node into Pipeline'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          elevation: 0,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowsePresetsView() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Search + Category Filter + List
        Expanded(
          flex: 4,
          child: Column(
            children: [
              // Search Field
              TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search templates, machines, materials...',
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Categories Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.map((cat) {
                    final isSel = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(cat, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.w600 : FontWeight.normal)),
                        selected: isSel,
                        onSelected: (_) => setState(() => _selectedCategory = cat),
                        selectedColor: AppColors.accentLight,
                        labelStyle: TextStyle(
                          color: isSel ? AppColors.accentDark : AppColors.textSecondary,
                        ),
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: isSel ? AppColors.accent : AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),

              // Preset Items List
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    itemCount: _filteredPresets.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final item = _filteredPresets[index];
                      final isSel = _selectedItem?.id == item.id;
                      return ListTile(
                        selected: isSel,
                        selectedTileColor: AppColors.accentLight.withValues(alpha: 0.5),
                        dense: true,
                        title: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                            color: isSel ? AppColors.accentDark : AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${item.category} • ${item.defaultMachine}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        trailing: item.sheetPlan != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'CAD Plan',
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                                ),
                              )
                            : null,
                        onTap: () => setState(() => _selectedItem = item),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // Right Column: Template Detail & Inspector Preview
        Expanded(
          flex: 5,
          child: _selectedItem == null
              ? const Center(child: Text('Select a template to preview details', style: TextStyle(color: AppColors.textMuted)))
              : Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _selectedItem!.title,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.borderStrong),
                              ),
                              child: Text(
                                _selectedItem!.category,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedItem!.description,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'PRE-CONFIGURED MES ATTACHMENTS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 8),

                        // Machine & Die Box
                        _buildPreviewEntityRow(
                          icon: Icons.precision_manufacturing_outlined,
                          label: 'Workstation & Tooling',
                          value: '${_selectedItem!.defaultMachine}${_selectedItem!.defaultDie != null ? ' • Die: ${_selectedItem!.defaultDie}' : ''}',
                        ),
                        const SizedBox(height: 6),

                        // Material In & Item Out Box
                        _buildPreviewEntityRow(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Inflow → Outflow Part',
                          value: '${_selectedItem!.materialIn}  →  ${_selectedItem!.itemOut}',
                        ),
                        const SizedBox(height: 6),

                        if (_selectedItem!.scrapItem != null)
                          _buildPreviewEntityRow(
                            icon: Icons.delete_outline,
                            label: 'Process Scrap Disposition',
                            value: _selectedItem!.scrapItem!,
                          ),

                        if (_selectedItem!.sheetPlan != null) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'EMBEDDED CAD CUTTING ENGINE',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.grid_on_outlined, size: 20, color: Color(0xFF4F46E5)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_selectedItem!.sheetPlan!.sheetWidthInches.toStringAsFixed(0)}" × ${_selectedItem!.sheetPlan!.sheetHeightInches.toStringAsFixed(0)}" Sheet Plan',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                      ),
                                      Text(
                                        '${_selectedItem!.sheetPlan!.bands.first.count} Bands • ${_selectedItem!.sheetPlan!.bands.first.sizeMm.toStringAsFixed(0)}mm Band Width',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPreviewEntityRow({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                Text(value, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveCurrentNodeView() {
    final node = widget.currentNodeToSave!;
    final machine = node.firstOf(AllocKind.machine) ?? 'None';
    final material = node.firstOf(AllocKind.material) ?? 'None';
    final item = node.firstOf(AllocKind.item) ?? 'None';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Template Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _saveTitleController,
                decoration: const InputDecoration(hintText: 'e.g. 8-Strip Precision Slitting'),
              ),
              const SizedBox(height: 14),
              const Text('Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _categories[1],
                items: _categories
                    .where((c) => c != 'All')
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {},
                decoration: const InputDecoration(),
              ),
              const SizedBox(height: 14),
              const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _saveDescController,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Provide guidelines for shop-floor operators using this template...'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CAPTURED NODE ATTRIBUTES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                _buildPreviewEntityRow(icon: Icons.settings, label: 'Assigned Workstation', value: machine),
                const SizedBox(height: 8),
                _buildPreviewEntityRow(icon: Icons.input, label: 'Feed Material', value: material),
                const SizedBox(height: 8),
                _buildPreviewEntityRow(icon: Icons.output, label: 'Target Part Yield', value: item),
                const SizedBox(height: 8),
                if (node.sheetPlan != null)
                  _buildPreviewEntityRow(
                    icon: Icons.architecture,
                    label: 'CAD Cutting Plan',
                    value: '${node.sheetPlan!.bands.length} Bands • ${node.sheetPlan!.sheetThicknessMm}mm MS',
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _handleSaveCurrentNode() {
    final node = widget.currentNodeToSave!;
    final newItem = NodeTemplateItem(
      id: 'tpl-${DateTime.now().millisecondsSinceEpoch}',
      title: _saveTitleController.text.trim().isNotEmpty ? _saveTitleController.text.trim() : node.name,
      category: 'Shearing & Slitting',
      description: _saveDescController.text.trim(),
      defaultMachine: node.firstOf(AllocKind.machine) ?? 'PP-40T-01',
      defaultDie: node.firstOf(AllocKind.die),
      materialIn: node.firstOf(AllocKind.material) ?? 'MS Sheet',
      itemOut: node.firstOf(AllocKind.item) ?? 'Yield Blank',
      scrapItem: node.firstOf(AllocKind.scrap),
      sheetPlan: node.sheetPlan,
    );

    globalNodePresets.add(newItem);
    widget.onSaveCurrentNode?.call(newItem);
    Navigator.of(context).pop();
  }
}
