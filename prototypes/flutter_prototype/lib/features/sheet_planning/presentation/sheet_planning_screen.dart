import 'package:flutter/material.dart';
import '../../../app/shell/prototype_theme.dart';
import '../domain/sheet_plan.dart';
import 'sheet_figure_painter.dart';

class SheetPlanningScreen extends StatefulWidget {
  final VoidCallback? onBackToPipeline;

  const SheetPlanningScreen({super.key, this.onBackToPipeline});

  @override
  State<SheetPlanningScreen> createState() => _SheetPlanningScreenState();
}

class _SheetPlanningScreenState extends State<SheetPlanningScreen> {
  late SheetPlan _plan;
  int _activeStage = 2; // 0: Raw, 1: Slit, 2: Blanks, 3: Plated, 4: Assembled

  @override
  void initState() {
    super.initState();
    _plan = SheetPlan.empty().copyWith(
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
    );
  }

  void _updatePlan(SheetPlan newPlan) {
    setState(() {
      _plan = newPlan;
    });
  }

  @override
  Widget build(BuildContext context) {
    final weights = calculateWeight(_plan);
    final count = pieceCount(_plan);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Top Header Toolbar
          _buildHeader(),

          // 3-Column Workbench Body
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Column: Parameters & Slitting/Cutting Setup
                SizedBox(
                  width: 320,
                  child: _buildParameterControls(),
                ),

                // Center Column: Interactive CAD Viewport
                Expanded(
                  child: _buildCadViewport(),
                ),

                // Right Column: Physics, Mass Balance & Yield Breakdown
                SizedBox(
                  width: 300,
                  child: _buildPhysicsMetrics(weights, count),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                if (widget.onBackToPipeline != null) ...[
                  IconButton(
                    tooltip: 'Back to Pipeline Designer',
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: widget.onBackToPipeline,
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.architecture, size: 18, color: Color(0xFF4F46E5)),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CAD Sheet Planning & 2D Nesting Engine',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        'High-DPI parametric physical transformation visualizer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Stage Toggle Bar
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStageButton('1. Raw', 0),
                _buildStageButton('2. Slit (8)', 1),
                _buildStageButton('3. Cut (72)', 2),
                _buildStageButton('4. Plated', 3),
                _buildStageButton('5. Assembled', 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageButton(String label, int stageIndex) {
    final isSel = _activeStage == stageIndex;
    return GestureDetector(
      onTap: () => setState(() => _activeStage = stageIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSel ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            color: isSel ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildParameterControls() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('SHEET STOCK SPECIFICATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),

          // Material Dropdown
          DropdownButtonFormField<String>(
            initialValue: _plan.materialName,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Material Grade', isDense: true),
            items: materialDensities.keys.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (val) {
              if (val != null) _updatePlan(_plan.copyWith(materialName: val));
            },
          ),
          const SizedBox(height: 12),

          // Dimensions Row
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _plan.sheetWidthInches.toStringAsFixed(0),
                  decoration: const InputDecoration(labelText: 'Width (in)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final v = double.tryParse(val);
                    if (v != null && v > 0) _updatePlan(_plan.copyWith(sheetWidthInches: v));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _plan.sheetHeightInches.toStringAsFixed(0),
                  decoration: const InputDecoration(labelText: 'Height (in)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final v = double.tryParse(val);
                    if (v != null && v > 0) _updatePlan(_plan.copyWith(sheetHeightInches: v));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _plan.sheetThicknessMm.toStringAsFixed(1),
                  decoration: const InputDecoration(labelText: 'Thk (mm)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final v = double.tryParse(val);
                    if (v != null && v > 0) _updatePlan(_plan.copyWith(sheetThicknessMm: v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Edge Trim & Kerf
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _plan.edgeTrimMm.toStringAsFixed(0),
                  decoration: const InputDecoration(labelText: 'Edge Trim (mm)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final v = double.tryParse(val);
                    if (v != null && v >= 0) _updatePlan(_plan.copyWith(edgeTrimMm: v));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _plan.kerfMm.toStringAsFixed(1),
                  decoration: const InputDecoration(labelText: 'Blade Kerf (mm)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final v = double.tryParse(val);
                    if (v != null && v >= 0) _updatePlan(_plan.copyWith(kerfMm: v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          const Text('STAGE 1: ROTARY SLITTING', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),

          // Slitting Bands
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _plan.bands.isNotEmpty ? planBandsCount(_plan).toString() : '8',
                  decoration: const InputDecoration(labelText: 'Slit Bands Count', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final v = int.tryParse(val);
                    if (v != null && v > 0) {
                      final b = _plan.bands.isNotEmpty ? _plan.bands.first.copyWith(count: v) : Band(sizeMm: 145, count: v);
                      _updatePlan(_plan.copyWith(bands: [b]));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _plan.bands.isNotEmpty ? planBandsCount(_plan).toString() : '145',
                  decoration: const InputDecoration(labelText: 'Band Width (mm)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final v = double.tryParse(val);
                    if (v != null && v > 0) {
                      final b = _plan.bands.isNotEmpty ? _plan.bands.first.copyWith(sizeMm: v) : Band(sizeMm: v, count: 8);
                      _updatePlan(_plan.copyWith(bands: [b]));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          const Text('STAGE 2: GUILLOTINE BLANKING', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),

          // Sub-cuts
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _plan.subCuts[0]?.isNotEmpty == true ? _plan.subCuts[0]!.first.count.toString() : '9',
                  decoration: const InputDecoration(labelText: 'Blanks per Strip', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final v = int.tryParse(val);
                    if (v != null && v > 0) {
                      final cuts = [SubCut(sizeMm: 260, count: v)];
                      _updatePlan(_plan.copyWith(subCuts: {0: cuts}));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _plan.subCuts[0]?.isNotEmpty == true ? _plan.subCuts[0]!.first.sizeMm.toStringAsFixed(0) : '260',
                  decoration: const InputDecoration(labelText: 'Cut Length (mm)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final v = double.tryParse(val);
                    if (v != null && v > 0) {
                      final cuts = [SubCut(sizeMm: v, count: 9)];
                      _updatePlan(_plan.copyWith(subCuts: {0: cuts}));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Auto-Fit Recommendation Button
          OutlinedButton.icon(
            onPressed: () {
              final fitted = createPlanForPart(
                basePlan: _plan,
                partName: 'Enclosure Blank 145×260',
                partWidthMm: 145,
                partHeightMm: 260,
              );
              _updatePlan(fitted);
            },
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Calculate Optimal Nesting'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  int planBandsCount(SheetPlan plan) => plan.bands.isNotEmpty ? plan.bands.first.count : 8;

  Widget _buildCadViewport() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: AspectRatio(
          aspectRatio: 1.4,
          child: SheetFigureWidget(
            plan: _plan,
            width: double.infinity,
            height: double.infinity,
            highlightedStage: _activeStage,
          ),
        ),
      ),
    );
  }

  Widget _buildPhysicsMetrics(SheetPlanWeight weights, int count) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('PHYSICAL MASS BALANCE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),

          // Big Total Yield Hero Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('NET PART YIELD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFC7D2FE))),
                const SizedBox(height: 4),
                Text(
                  '$count Blanks',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${weights.yieldPercent.toStringAsFixed(1)}% Material Yield',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Mass Breakdown Rows
          _buildMassRow('Input Master Sheet', '${weights.sheetKg.toStringAsFixed(2)} kg', const Color(0xFF0F172A)),
          const SizedBox(height: 8),
          _buildMassRow('Finished Blanks Mass', '${weights.partsKg.toStringAsFixed(2)} kg', AppColors.accentDark),
          const SizedBox(height: 8),
          _buildMassRow('Total Process Scrap', '${weights.scrapKg.toStringAsFixed(2)} kg', AppColors.warning),
          const SizedBox(height: 16),

          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),

          const Text('MANUFACTURING LINE INTEGRATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 12),

          _buildLineFact('1 Raw Sheet → 8 Slit Strips (145mm) → 72 Blanks (145×260mm)'),
          const SizedBox(height: 8),
          _buildLineFact('Slitting Line: RS-1250 (10mm edge trim booked to Edge Trim Scrap)'),
          const SizedBox(height: 8),
          _buildLineFact('Guillotine Shear: G-300 (Cut sequence: 9 cuts @ 260mm/strip)'),
        ],
      ),
    );
  }

  Widget _buildMassRow(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildLineFact(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•', style: TextStyle(fontSize: 14, color: AppColors.accent, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35)),
        ),
      ],
    );
  }
}
