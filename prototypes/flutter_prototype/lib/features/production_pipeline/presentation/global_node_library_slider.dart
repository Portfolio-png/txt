import 'package:flutter/material.dart';
import '../../../app/shell/prototype_theme.dart';
import '../domain/process_node.dart';
import 'global_node_library_dialog.dart';

class GlobalNodeLibrarySlider extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final Function(NodeTemplateItem item) onSelectTemplate;
  final ProcessNode? currentNodeToSave;
  final Function(NodeTemplateItem savedItem)? onSaveCurrentNode;

  const GlobalNodeLibrarySlider({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.onOpen,
    required this.onSelectTemplate,
    this.currentNodeToSave,
    this.onSaveCurrentNode,
  });

  @override
  State<GlobalNodeLibrarySlider> createState() => _GlobalNodeLibrarySliderState();
}

class _GlobalNodeLibrarySliderState extends State<GlobalNodeLibrarySlider> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _selectedCategory = 'All';
  String _searchQuery = '';
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
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    if (widget.isOpen) {
      _animController.value = 1.0;
    }

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });

    if (widget.currentNodeToSave != null) {
      _saveTitleController.text = widget.currentNodeToSave!.name;
      _saveDescController.text = 'Custom MES template configured from ${widget.currentNodeToSave!.name}';
    }
  }

  @override
  void didUpdateWidget(covariant GlobalNodeLibrarySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _animController.forward();
      } else {
        _animController.reverse();
        _searchFocusNode.unfocus();
      }
    }
    if (widget.currentNodeToSave != oldWidget.currentNodeToSave && widget.currentNodeToSave != null) {
      _saveTitleController.text = widget.currentNodeToSave!.name;
      _saveDescController.text = 'Custom MES template configured from ${widget.currentNodeToSave!.name}';
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
          p.defaultMachine.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.materialIn.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.itemOut.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesSearch;
    }).toList();
  }

  void _handleSelect(NodeTemplateItem item) {
    widget.onSelectTemplate(item);
    widget.onClose();
  }

  void _handleSave() {
    if (widget.currentNodeToSave == null) return;
    final node = widget.currentNodeToSave!;
    final newItem = NodeTemplateItem(
      id: 'tpl-${DateTime.now().millisecondsSinceEpoch}',
      title: _saveTitleController.text.trim().isNotEmpty ? _saveTitleController.text.trim() : node.name,
      category: _selectedCategory != 'All' ? _selectedCategory : 'Shearing & Slitting',
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
    setState(() {
      _isSaveMode = false;
    });
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        final double progress = _slideAnimation.value;
        final bool isExpanded = progress > 0.05;

        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1100),
            margin: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: isExpanded ? 0 : 8,
            ),
            child: Material(
              color: Colors.transparent,
              child: isExpanded ? _buildExpandedDrawer(progress) : _buildFloatingNotch(),
            ),
          ),
        );
      },
    );
  }

  /// Compact floating Notch bar anchored at the bottom of the canvas
  Widget _buildFloatingNotch() {
    return InkWell(
      onTap: () {
        widget.onOpen();
        _searchFocusNode.requestFocus();
      },
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search Icon with accent pulse
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.accentLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search, size: 16, color: AppColors.accent),
            ),
            const SizedBox(width: 10),

            // Search Prompt
            const Text(
              'Search or insert process nodes...',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),

            // Shortcut / Preset Count Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined, size: 12, color: AppColors.accentDark),
                  const SizedBox(width: 4),
                  Text(
                    '${globalNodePresets.length} Templates',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Expand Chevron Notch Icon
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Expanded Sliding Drawer Panel with integrated Notch Search Header
  Widget _buildExpandedDrawer(double progress) {
    const double targetHeight = 420;
    final double currentHeight = 56 + (targetHeight - 56) * progress;

    return Container(
      height: currentHeight,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. Top Notch Bar & Drag Handle
          _buildSliderNotchHeader(),

          const Divider(height: 1, color: AppColors.border),

          // 2. Main Content Area (Preset Grid or Save Form)
          Expanded(
            child: _isSaveMode ? _buildSaveModeContent() : _buildPresetCatalogContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderNotchHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Center Drag Pill Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Search Bar + Category Pills + Actions
          Row(
            children: [
              // Search Field Capsule
              Expanded(
                flex: 4,
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search operations, machines, feed materials...',
                      hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.accent),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16, color: AppColors.textMuted),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Mode Toggle (Save Node vs Browse)
              if (widget.currentNodeToSave != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isSaveMode = !_isSaveMode;
                    });
                  },
                  icon: Icon(_isSaveMode ? Icons.list_alt : Icons.bookmark_add_outlined, size: 16),
                  label: Text(_isSaveMode ? 'Browse Library' : 'Save Selected Node'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),

              const SizedBox(width: 8),

              // Collapse / Close Slider Chevron
              IconButton(
                tooltip: 'Collapse Library Slider',
                onPressed: widget.onClose,
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),

          if (!_isSaveMode) ...[
            const SizedBox(height: 8),
            // Category Filter Pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final isSel = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500)),
                      selected: isSel,
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                      selectedColor: AppColors.accentLight,
                      labelStyle: TextStyle(
                        color: isSel ? AppColors.accentDark : AppColors.textSecondary,
                      ),
                      backgroundColor: AppColors.surface,
                      side: BorderSide(color: isSel ? AppColors.accent : AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Preset Cards Grid
  Widget _buildPresetCatalogContent() {
    final items = _filteredPresets;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 8),
            Text(
              'No process nodes match "$_searchQuery"',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Try changing your category filter or search terms.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(14),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 340,
          mainAxisExtent: 146,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildPresetNodeCard(item);
        },
      ),
    );
  }

  Widget _buildPresetNodeCard(NodeTemplateItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Category Pill & Machine
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: AppColors.accentLight,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
                child: Text(
                  item.category.toUpperCase(),
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.accentDark, letterSpacing: 0.4),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.precision_manufacturing_outlined, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    item.defaultMachine,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Title
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 3),

          // Description
          Text(
            item.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary, height: 1.25),
          ),
          const Spacer(),

          // Bottom Bar: Flow Pill & Insert Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${item.materialIn} → ${item.itemOut}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _handleSelect(item),
                icon: const Icon(Icons.add, size: 13),
                label: const Text('Insert', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Save Current Canvas Node View
  Widget _buildSaveModeContent() {
    final node = widget.currentNodeToSave!;
    final machine = node.firstOf(AllocKind.machine) ?? 'None';
    final material = node.firstOf(AllocKind.material) ?? 'None';
    final item = node.firstOf(AllocKind.item) ?? 'None';

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Form
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Template Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _saveTitleController,
                    decoration: const InputDecoration(hintText: 'e.g. 8-Strip Rotary Slitting'),
                  ),
                  const SizedBox(height: 10),
                  const Text('Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: _categories[1],
                    items: _categories
                        .where((c) => c != 'All')
                        .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                    decoration: const InputDecoration(),
                  ),
                  const SizedBox(height: 10),
                  const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _saveDescController,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'Provide guidelines for shop-floor operators...'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Right: Captured Attributes & Save Action
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CAPTURED NODE ATTACHMENTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
                  const SizedBox(height: 10),
                  _buildCapturedRow(Icons.precision_manufacturing_outlined, 'Machine', machine),
                  const SizedBox(height: 6),
                  _buildCapturedRow(Icons.input, 'Input Feed', material),
                  const SizedBox(height: 6),
                  _buildCapturedRow(Icons.output, 'Output Part', item),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => setState(() => _isSaveMode = false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _handleSave,
                        icon: const Icon(Icons.check, size: 14),
                        label: const Text('Save to Library'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapturedRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.accent),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
