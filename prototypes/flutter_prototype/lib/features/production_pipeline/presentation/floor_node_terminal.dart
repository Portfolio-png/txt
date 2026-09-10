import 'package:flutter/material.dart';
import '../../../app/shell/prototype_theme.dart';
import '../../sheet_planning/domain/sheet_plan.dart';
import '../../sheet_planning/presentation/sheet_figure_painter.dart';
import '../domain/process_node.dart';
import '../domain/seed_data.dart';
import 'global_node_library_dialog.dart';

class FloorNodeTerminal extends StatefulWidget {
  final ProcessNode node;
  final ValueChanged<ProcessNode> onUpdateNode;
  final VoidCallback onDeleteNode;
  final VoidCallback onClose;
  final VoidCallback? onOpenGlobalLibrary;

  const FloorNodeTerminal({
    super.key,
    required this.node,
    required this.onUpdateNode,
    required this.onDeleteNode,
    required this.onClose,
    this.onOpenGlobalLibrary,
  });

  @override
  State<FloorNodeTerminal> createState() => _FloorNodeTerminalState();
}

class _FloorNodeTerminalState extends State<FloorNodeTerminal> {
  late TextEditingController _nameController;
  late TextEditingController _intakeQtyController;
  bool _isScrapProcessMode = true; // true = Process Scrap (kg), false = Defect Rejection (PPM)

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.node.name);
    _intakeQtyController = TextEditingController(text: widget.node.intakeQty.toString());
  }

  @override
  void didUpdateWidget(covariant FloorNodeTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _nameController.text = widget.node.name;
      _intakeQtyController.text = widget.node.intakeQty.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _intakeQtyController.dispose();
    super.dispose();
  }

  void _setAllocation(AllocKind kind, String value) {
    final currentAlloc = List<Alloc>.from(widget.node.allocations);
    final existingIdx = currentAlloc.indexWhere((a) => a.kind == kind);

    if (value.isEmpty) {
      if (existingIdx >= 0) currentAlloc.removeAt(existingIdx);
    } else {
      if (existingIdx >= 0) {
        currentAlloc[existingIdx] = currentAlloc[existingIdx].copyWith(value: value);
      } else {
        currentAlloc.add(Alloc(id: 'a_${DateTime.now().microsecondsSinceEpoch}', kind: kind, value: value));
      }
    }

    widget.onUpdateNode(widget.node.copyWith(allocations: currentAlloc));
  }

  @override
  Widget build(BuildContext context) {
    final cat = getProcessCategory(widget.node);
    final currentMachine = widget.node.firstOf(AllocKind.machine);
    final currentDie = widget.node.firstOf(AllocKind.die);
    final currentMaterial = widget.node.firstOf(AllocKind.material);
    final currentItem = widget.node.firstOf(AllocKind.item);
    final currentScrap = widget.node.firstOf(AllocKind.scrap);

    return Container(
      width: 400,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      child: Column(
        children: [
          // Inspector Header Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cat.badgeBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: cat.borderColor),
                        ),
                        child: Text(
                          cat.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: cat.badgeColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Stage ${widget.node.stageIndex + 1} Inspector',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Save to library button
                    IconButton(
                      tooltip: 'Save as Reusable Template',
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18, color: AppColors.accent),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => GlobalNodeLibraryDialog(
                            currentNodeToSave: widget.node,
                            onSelectTemplate: (_) {},
                          ),
                        );
                      },
                    ),
                    // Delete node button
                    IconButton(
                      tooltip: 'Delete Stage Node',
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                      onPressed: widget.onDeleteNode,
                    ),
                    // Close button
                    IconButton(
                      tooltip: 'Close Terminal',
                      icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Node Name Field
                TextField(
                  controller: _nameController,
                  onChanged: (val) => widget.onUpdateNode(widget.node.copyWith(name: val)),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Operation Name',
                    hintText: 'e.g. Rotary Slitting (8 Strips)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),

                // CARD 1: Workstation & Tooling
                _buildCard(
                  title: '1. Workstation & Tooling',
                  icon: Icons.precision_manufacturing_outlined,
                  accentColor: const Color(0xFF0284C7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Machine Station', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        key: ValueKey('mach_${widget.node.id}_$currentMachine'),
                        initialValue: seedMachineGroups.expand((g) => g.machines).contains(currentMachine) ? currentMachine : null,
                        hint: const Text('Select Workstation', style: TextStyle(fontSize: 12)),
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: seedMachineGroups.expand((g) {
                          return g.machines.map((m) => DropdownMenuItem(
                                value: m,
                                child: Text('$m (${g.name})', style: const TextStyle(fontSize: 12)),
                              ));
                        }).toList(),
                        onChanged: (val) => _setAllocation(AllocKind.machine, val ?? ''),
                      ),
                      const SizedBox(height: 12),
                      const Text('Tooling / Punch Die', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        key: ValueKey('die_${widget.node.id}_$currentDie'),
                        initialValue: seedDies.contains(currentDie) ? currentDie : null,
                        hint: const Text('None (Standard Shear)', style: TextStyle(fontSize: 12)),
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('None / Standard Tooling', style: TextStyle(fontSize: 12))),
                          ...seedDies.map((d) => DropdownMenuItem(
                                value: d,
                                child: Text(d, style: const TextStyle(fontSize: 12)),
                              )),
                        ],
                        onChanged: (val) => _setAllocation(AllocKind.die, val ?? ''),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // CARD 2: Material Inflow & Product Outflow
                _buildCard(
                  title: '2. Material Inflow & Outflow',
                  icon: Icons.swap_horiz_rounded,
                  accentColor: const Color(0xFF10B981),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Feed Inflow Stock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        key: ValueKey('mat_${widget.node.id}_$currentMaterial'),
                        initialValue: seedItems.contains(currentMaterial) ? currentMaterial : null,
                        hint: const Text('Select Input Feed', style: TextStyle(fontSize: 12)),
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: seedItems.map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(item, style: const TextStyle(fontSize: 12)),
                            )).toList(),
                        onChanged: (val) => _setAllocation(AllocKind.material, val ?? ''),
                      ),
                      const SizedBox(height: 12),
                      const Text('Target Output Part Yield', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        key: ValueKey('item_${widget.node.id}_$currentItem'),
                        initialValue: seedItems.contains(currentItem) ? currentItem : null,
                        hint: const Text('Select Output Part', style: TextStyle(fontSize: 12)),
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: seedItems.map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(item, style: const TextStyle(fontSize: 12)),
                            )).toList(),
                        onChanged: (val) => _setAllocation(AllocKind.item, val ?? ''),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // CARD 3: Sheet Cutting Plan Engine
                _buildCard(
                  title: '3. Sheet Cutting Plan Engine',
                  icon: Icons.architecture_outlined,
                  accentColor: const Color(0xFF6366F1),
                  child: widget.node.sheetPlan != null
                      ? _buildSheetPlanSection(widget.node.sheetPlan!)
                      : Column(
                          children: [
                            const Text(
                              'No CAD cutting plan attached. This stage performs 1:1 part transfer.',
                              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                widget.onUpdateNode(widget.node.copyWith(
                                  sheetPlan: SheetPlan.empty().copyWith(
                                    bands: [const Band(sizeMm: 145, count: 8)],
                                  ),
                                ));
                              },
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('Attach Sheet Cutting Plan', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accent,
                                side: const BorderSide(color: AppColors.accent),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),

                // CARD 4: Scrap & Quality Disposition
                _buildCard(
                  title: '4. Scrap & Quality Disposition',
                  icon: Icons.delete_sweep_outlined,
                  accentColor: const Color(0xFFF59E0B),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Intent Toggle
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isScrapProcessMode = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _isScrapProcessMode ? AppColors.surface : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: _isScrapProcessMode
                                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Process Scrap (kg)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: _isScrapProcessMode ? FontWeight.w700 : FontWeight.w500,
                                      color: _isScrapProcessMode ? AppColors.textPrimary : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isScrapProcessMode = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: !_isScrapProcessMode ? AppColors.surface : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: !_isScrapProcessMode
                                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Quality Defect (PPM)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: !_isScrapProcessMode ? FontWeight.w700 : FontWeight.w500,
                                      color: !_isScrapProcessMode ? AppColors.textPrimary : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      const Text('Scrap Item Master', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        key: ValueKey('scrap_${widget.node.id}_$currentScrap'),
                        initialValue: seedScrapItems.contains(currentScrap) ? currentScrap : null,
                        hint: const Text('None / Zero Scrap', style: TextStyle(fontSize: 12)),
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('None / Zero Scrap', style: TextStyle(fontSize: 12))),
                          ...seedScrapItems.map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s, style: const TextStyle(fontSize: 12)),
                              )),
                        ],
                        onChanged: (val) => _setAllocation(AllocKind.scrap, val ?? ''),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isScrapProcessMode
                            ? 'Calculated process scrap (edge trims & punch slugs) is booked automatically against this item master.'
                            : 'Floor rejection defects are logged against batch QA defect pools.',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: accentColor.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildSheetPlanSection(SheetPlan plan) {
    final weights = calculateWeight(plan);
    final count = pieceCount(plan);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mini CAD Preview
        AspectRatio(
          aspectRatio: 2.1,
          child: SheetFigureWidget(
            plan: plan,
            highlightedStage: plan.subCuts.isNotEmpty ? 2 : 1,
          ),
        ),
        const SizedBox(height: 12),

        // Live Yield Metric Grid
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniMetric('Total Yield', '$count Pcs', const Color(0xFF4338CA)),
              _buildMiniMetric('Efficiency', '${weights.yieldPercent.toStringAsFixed(1)}%', AppColors.success),
              _buildMiniMetric('Scrap', '${weights.scrapKg.toStringAsFixed(2)} kg', AppColors.warning),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Quick Band Config
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: plan.bands.isNotEmpty ? plan.bands.first.count.toString() : '8',
                decoration: const InputDecoration(labelText: 'Bands Count', isDense: true),
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  final parsed = int.tryParse(val);
                  if (parsed != null && parsed > 0) {
                    final currentBands = List<Band>.from(plan.bands);
                    if (currentBands.isNotEmpty) {
                      currentBands[0] = currentBands[0].copyWith(count: parsed);
                    } else {
                      currentBands.add(Band(sizeMm: 145, count: parsed));
                    }
                    widget.onUpdateNode(widget.node.copyWith(sheetPlan: plan.copyWith(bands: currentBands)));
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: plan.bands.isNotEmpty ? plan.bands.first.sizeMm.toStringAsFixed(0) : '145',
                decoration: const InputDecoration(labelText: 'Band Width (mm)', isDense: true),
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  if (parsed != null && parsed > 0) {
                    final currentBands = List<Band>.from(plan.bands);
                    if (currentBands.isNotEmpty) {
                      currentBands[0] = currentBands[0].copyWith(sizeMm: parsed);
                    } else {
                      currentBands.add(Band(sizeMm: parsed, count: 8));
                    }
                    widget.onUpdateNode(widget.node.copyWith(sheetPlan: plan.copyWith(bands: currentBands)));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                widget.onUpdateNode(widget.node.copyWith(sheetPlan: null));
              },
              child: const Text('Detach Plan', style: TextStyle(fontSize: 11, color: AppColors.error)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}
