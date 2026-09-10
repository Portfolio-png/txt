import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/shell/prototype_theme.dart';
import '../domain/sheet_plan.dart';
import 'sheet_figure_painter.dart';

class SheetTransformationSimulatorScreen extends StatefulWidget {
  final VoidCallback? onBackToPipeline;

  const SheetTransformationSimulatorScreen({super.key, this.onBackToPipeline});

  @override
  State<SheetTransformationSimulatorScreen> createState() => _SheetTransformationSimulatorScreenState();
}

class _SheetTransformationSimulatorScreenState extends State<SheetTransformationSimulatorScreen> {
  int _currentStep = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;

  late SheetPlan _plan;

  final List<StageSimulatorInfo> _stages = [
    const StageSimulatorInfo(
      stepIndex: 0,
      title: 'Stage 1: Raw Stock Inward',
      machine: 'Overhead Crane #1',
      actionVerb: 'Receiving & Inspection',
      inputSummary: '1 Master Sheet (48" × 96", 1.2mm Mild Steel)',
      outputSummary: '1 Verified Raw Sheet',
      piecesSummary: '1 Sheet (35.03 kg)',
      scrapSummary: '0.00 kg (Zero Scrap)',
      badgeLabel: 'RAW STOCK',
      badgeColor: Color(0xFF059669),
      badgeBg: Color(0xFFECFDF5),
      detail: 'Raw coil sheet is loaded into feed rack with micrometer gauge check (1.20mm nominal).',
    ),
    const StageSimulatorInfo(
      stepIndex: 1,
      title: 'Stage 2: Rotary Slitting (8 Strips)',
      machine: 'Rotary Slitter RS-1250',
      actionVerb: 'Longitudinal Slitting',
      inputSummary: '1 Raw Master Sheet (1219.2 × 2438.4 mm)',
      outputSummary: '8 Slit Strips (145mm × 2438.4mm)',
      piecesSummary: '8 Strips (33.68 kg)',
      scrapSummary: '1.35 kg (Edge Trim Scrap)',
      badgeLabel: 'SLITTING',
      badgeColor: Color(0xFF0D9488),
      badgeBg: Color(0xFFF0FDFA),
      detail: 'Gang slitter blades shear sheet into 8 equal 145mm wide strips. 10mm margins are diverted to scrap bin.',
    ),
    const StageSimulatorInfo(
      stepIndex: 2,
      title: 'Stage 3: Guillotine Blanking (72 Blanks)',
      machine: 'Hydraulic Guillotine G-300',
      actionVerb: 'Cross-Cut Blanking',
      inputSummary: '8 Slit Strips (145mm width)',
      outputSummary: '72 Precision Net Blanks (145×260mm)',
      piecesSummary: '72 Blanks (32.12 kg)',
      scrapSummary: '1.56 kg (Offcut Tail Scrap)',
      badgeLabel: 'BLANKING',
      badgeColor: Color(0xFF4F46E5),
      badgeBg: Color(0xFFEEF2FF),
      detail: 'Automated feeder indexes each strip 9 times at 260mm stroke, producing 9 blanks/strip × 8 strips = 72 net blanks.',
    ),
    const StageSimulatorInfo(
      stepIndex: 3,
      title: 'Stage 4: Zinc Electroplating Bath',
      machine: 'Plating Line PL-ZN-01',
      actionVerb: 'Surface Finishing',
      inputSummary: '72 Raw Net Blanks',
      outputSummary: '72 Plated Corrosion-Resistant Blanks',
      piecesSummary: '72 Plated Blanks (32.12 kg)',
      scrapSummary: '0.00 kg (Process Plating)',
      badgeLabel: 'FINISHING',
      badgeColor: Color(0xFF9333EA),
      badgeBg: Color(0xFFFAF5FF),
      detail: 'Parts undergo acid pickle, zinc electrodeposition (8-12 μm), and trivalent blue chromate passivation.',
    ),
    const StageSimulatorInfo(
      stepIndex: 4,
      title: 'Stage 5: Sub-Assembly Workstation',
      machine: 'Assembly Bench AB-01',
      actionVerb: 'Hardware Insertion',
      inputSummary: '72 Plated Blanks + Clinch Fasteners',
      outputSummary: '72 Precision Enclosure Sub-Assemblies',
      piecesSummary: '72 Sub-Assemblies (34.20 kg)',
      scrapSummary: '0.00 kg (Final QA Cleared)',
      badgeLabel: 'ASSEMBLY',
      badgeColor: Color(0xFFD97706),
      badgeBg: Color(0xFFFFFBEB),
      detail: 'Pneumatic clinch insertion of M4 grounding studs and gasket seal fitting. Ready for packaging.',
    ),
  ];

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

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _playbackTimer = Timer.periodic(const Duration(milliseconds: 2200), (timer) {
          setState(() {
            if (_currentStep < _stages.length - 1) {
              _currentStep++;
            } else {
              _currentStep = 0;
            }
          });
        });
      } else {
        _playbackTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeStageInfo = _stages[_currentStep];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Top Header & Stepper Controls
          _buildHeader(),

          // Main Simulator Split View
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left CAD Viewport & Realtime Physics Animation
                Expanded(
                  flex: 6,
                  child: _buildAnimatedCadCanvas(activeStageInfo),
                ),

                // Right Stage Operational Console
                Expanded(
                  flex: 4,
                  child: _buildStageConsole(activeStageInfo),
                ),
              ],
            ),
          ),

          // Bottom Step Timeline & Playback Bar
          _buildPlaybackTimeline(),
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
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.slow_motion_video_rounded, size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Physical Sheet Transformation Simulator',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        '1 Sheet → 8 Strips → 72 Blanks → 72 Plated → 72 Sub-Assemblies',
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

          // Playback Action Controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous Step',
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: _currentStep > 0
                    ? () {
                        setState(() {
                          _currentStep--;
                          _isPlaying = false;
                          _playbackTimer?.cancel();
                        });
                      }
                    : null,
              ),
              ElevatedButton.icon(
                onPressed: _togglePlay,
                icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 18),
                label: Text(_isPlaying ? 'Pause' : 'Auto Play Simulation'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isPlaying ? AppColors.warning : AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 0,
                ),
              ),
              IconButton(
                tooltip: 'Next Step',
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: _currentStep < _stages.length - 1
                    ? () {
                        setState(() {
                          _currentStep++;
                          _isPlaying = false;
                          _playbackTimer?.cancel();
                        });
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedCadCanvas(StageSimulatorInfo info) {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Top Viewport Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'TRANSFORMATION CAD VIEWPORT • ${info.badgeLabel}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Flexible(
                child: Text(
                  'Mass Balance: 35.03 kg In → 32.12 kg Part + 2.91 kg Scrap',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main CAD Rendering
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1.4,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: SheetFigureWidget(
                    key: ValueKey(_currentStep),
                    plan: _plan,
                    width: double.infinity,
                    height: double.infinity,
                    highlightedStage: _currentStep,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageConsole(StageSimulatorInfo info) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Stage Title Card
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: info.badgeBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: info.badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  info.badgeLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: info.badgeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                'Step ${_currentStep + 1} of ${_stages.length}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            info.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            info.detail,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),

          // Station & Equipment Card
          _buildConsoleCard(
            title: 'Operating Workstation',
            icon: Icons.precision_manufacturing_outlined,
            accent: AppColors.accent,
            child: Text(
              info.machine,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 12),

          // Inflow & Outflow Card
          _buildConsoleCard(
            title: 'Material Flow & Conversion',
            icon: Icons.swap_horiz_rounded,
            accent: const Color(0xFF10B981),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFlowLine('Feed Inflow', info.inputSummary),
                const SizedBox(height: 6),
                _buildFlowLine('Product Yield', info.outputSummary),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Yield & Scrap Disposition Card
          _buildConsoleCard(
            title: 'Mass Balance & Disposition',
            icon: Icons.scale_outlined,
            accent: const Color(0xFF6366F1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFlowLine('Net Pieces Mass', info.piecesSummary),
                const SizedBox(height: 6),
                _buildFlowLine('Scrap Logged', info.scrapSummary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsoleCard({
    required String title,
    required IconData icon,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildFlowLine(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _buildPlaybackTimeline() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: List.generate(_stages.length, (index) {
          final isDone = index < _currentStep;
          final isCurrent = index == _currentStep;
          final stage = _stages[index];

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _currentStep = index;
                  _isPlaying = false;
                  _playbackTimer?.cancel();
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppColors.accentLight
                      : (isDone ? AppColors.surface : AppColors.cardAlt),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent ? AppColors.accent : (isDone ? AppColors.success : AppColors.border),
                    width: isCurrent ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCurrent
                            ? AppColors.accent
                            : (isDone ? AppColors.success : AppColors.borderStrong),
                      ),
                      alignment: Alignment.center,
                      child: isDone
                          ? const Icon(Icons.check, size: 12, color: Colors.white)
                          : Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stage.badgeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                          color: isCurrent ? AppColors.accentDark : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class StageSimulatorInfo {
  final int stepIndex;
  final String title;
  final String machine;
  final String actionVerb;
  final String inputSummary;
  final String outputSummary;
  final String piecesSummary;
  final String scrapSummary;
  final String badgeLabel;
  final Color badgeColor;
  final Color badgeBg;
  final String detail;

  const StageSimulatorInfo({
    required this.stepIndex,
    required this.title,
    required this.machine,
    required this.actionVerb,
    required this.inputSummary,
    required this.outputSummary,
    required this.piecesSummary,
    required this.scrapSummary,
    required this.badgeLabel,
    required this.badgeColor,
    required this.badgeBg,
    required this.detail,
  });
}
