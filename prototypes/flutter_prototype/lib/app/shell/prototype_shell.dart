import 'package:flutter/material.dart';
import '../../features/production_pipeline/presentation/pipeline_designer_screen.dart';
import '../../features/sheet_planning/presentation/sheet_planning_screen.dart';
import '../../features/sheet_planning/presentation/sheet_transformation_simulator_screen.dart';
import 'prototype_theme.dart';

enum ShellNavTab {
  pipelineDesigner,
  sheetPlanning,
  transformationSimulator,
}

class PrototypeShell extends StatefulWidget {
  const PrototypeShell({super.key});

  @override
  State<PrototypeShell> createState() => _PrototypeShellState();
}

class _PrototypeShellState extends State<PrototypeShell> {
  ShellNavTab _activeTab = ShellNavTab.pipelineDesigner;
  bool _openLibraryOnDesigner = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // macOS Window Top Bar with Traffic Lights
          _buildMacosTopBar(),

          // Main Shell (Sidebar + Screen Viewport)
          Expanded(
            child: Row(
              children: [
                // Soft ERP Sidebar
                _buildSidebar(),

                // Active Workspace Screen
                Expanded(
                  child: _buildActiveScreen(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacosTopBar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // macOS Traffic Lights & Title
          Row(
            children: [
              // Traffic Light Dots
              Row(
                children: [
                  _buildTrafficDot(const Color(0xFFFF5F56)),
                  const SizedBox(width: 8),
                  _buildTrafficDot(const Color(0xFFFFBD2E)),
                  const SizedBox(width: 8),
                  _buildTrafficDot(const Color(0xFF27C93F)),
                ],
              ),
              const SizedBox(width: 20),
              Container(width: 1, height: 18, color: AppColors.border),
              const SizedBox(width: 16),

              // App Logo / Title
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'P',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Paper MES',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '/  Precision Enclosure E-102 (5-Stage Line)',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Right Status Pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 12, color: AppColors.success),
                    SizedBox(width: 6),
                    Text(
                      'Pipeline Synced • 72 Blanks/Sheet',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficDot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withValues(alpha: 0.12), width: 0.5),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'WORKBENCHES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),

          // Nav Items
          _buildSidebarNavItem(
            tab: ShellNavTab.pipelineDesigner,
            icon: Icons.account_tree_outlined,
            activeIcon: Icons.account_tree,
            label: '2D Pipeline Designer',
            badge: '5 Stages',
          ),
          _buildSidebarNavItem(
            tab: ShellNavTab.sheetPlanning,
            icon: Icons.architecture_outlined,
            activeIcon: Icons.architecture,
            label: 'CAD Sheet Planner',
            badge: '48×96"',
          ),
          _buildSidebarNavItem(
            tab: ShellNavTab.transformationSimulator,
            icon: Icons.slow_motion_video_outlined,
            activeIcon: Icons.slow_motion_video,
            label: 'Flow Transformation',
            badge: 'Live',
          ),

          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: AppColors.border),
          ),
          const SizedBox(height: 16),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'GLOBAL REPOSITORIES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),

          // Global Node Library Action
          ListTile(
            dense: true,
            leading: const Icon(Icons.hub_outlined, size: 18, color: AppColors.accent),
            title: const Text('Global Node Library', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: const Text('Slide-up Template Drawer', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
            onTap: () {
              setState(() {
                _openLibraryOnDesigner = true;
                _activeTab = ShellNavTab.pipelineDesigner;
              });
            },
          ),

          const Spacer(),

          // Bottom Version & Platform Badge
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paper ERP Native', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                SizedBox(height: 2),
                Text('Flutter Desktop macOS • v2.4.0', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required ShellNavTab tab,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    String? badge,
  }) {
    final isSelected = _activeTab == tab;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.accentLight : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
          isSelected ? activeIcon : icon,
          size: 18,
          color: isSelected ? AppColors.accent : AppColors.textSecondary,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.accentDark : AppColors.textPrimary,
          ),
        ),
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : AppColors.border,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? AppColors.accentDark : AppColors.textSecondary,
                  ),
                ),
              )
            : null,
        onTap: () => setState(() => _activeTab = tab),
      ),
    );
  }

  Widget _buildActiveScreen() {
    switch (_activeTab) {
      case ShellNavTab.pipelineDesigner:
        return PipelineDesignerScreen(
          key: ValueKey('designer_$_openLibraryOnDesigner'),
          initialOpenLibrary: _openLibraryOnDesigner,
          onNavigateToSimulator: () => setState(() {
            _openLibraryOnDesigner = false;
            _activeTab = ShellNavTab.transformationSimulator;
          }),
          onNavigateToSheetPlanner: () => setState(() {
            _openLibraryOnDesigner = false;
            _activeTab = ShellNavTab.sheetPlanning;
          }),
        );
      case ShellNavTab.sheetPlanning:
        return SheetPlanningScreen(
          onBackToPipeline: () => setState(() {
            _openLibraryOnDesigner = false;
            _activeTab = ShellNavTab.pipelineDesigner;
          }),
        );
      case ShellNavTab.transformationSimulator:
        return SheetTransformationSimulatorScreen(
          onBackToPipeline: () => setState(() {
            _openLibraryOnDesigner = false;
            _activeTab = ShellNavTab.pipelineDesigner;
          }),
        );
    }
  }
}
