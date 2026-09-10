import 'package:flutter/material.dart';
import '../../../app/shell/prototype_theme.dart';
import '../domain/pipeline_template.dart';
import '../domain/process_node.dart';
import '../domain/seed_data.dart';
import 'floor_node_terminal.dart';
import 'global_node_library_dialog.dart';
import 'global_node_library_slider.dart';
import 'pipeline_canvas.dart';

class PipelineDesignerScreen extends StatefulWidget {
  final VoidCallback? onNavigateToSimulator;
  final VoidCallback? onNavigateToSheetPlanner;
  final bool initialOpenLibrary;

  const PipelineDesignerScreen({
    super.key,
    this.onNavigateToSimulator,
    this.onNavigateToSheetPlanner,
    this.initialOpenLibrary = false,
  });

  @override
  State<PipelineDesignerScreen> createState() => _PipelineDesignerScreenState();
}

class _PipelineDesignerScreenState extends State<PipelineDesignerScreen> {
  late PipelineTemplate _template;
  late PipelineRun _run;
  String? _selectedNodeId;
  bool _isInspectorOpen = true;
  bool _isNodeLibrarySliderOpen = false;

  @override
  void initState() {
    super.initState();
    _template = create5StagePipelineTemplate();
    _run = create5StagePipelineRun();
    if (_template.nodes.isNotEmpty) {
      _selectedNodeId = _template.nodes[1].id; // default select Stage 2 (Slating)
    }
    _isNodeLibrarySliderOpen = widget.initialOpenLibrary;
  }

  void _handleSelectNode(String? nodeId) {
    setState(() {
      _selectedNodeId = nodeId;
      if (nodeId != null) {
        _isInspectorOpen = true;
      }
    });
  }

  void _handleUpdateNode(ProcessNode updatedNode) {
    setState(() {
      final idx = _template.nodes.indexWhere((n) => n.id == updatedNode.id);
      if (idx >= 0) {
        final newNodes = List<ProcessNode>.from(_template.nodes);
        newNodes[idx] = updatedNode;
        _template = _template.copyWith(nodes: newNodes);
      }
    });
  }

  void _handleDeleteNode(String nodeId) {
    setState(() {
      final newNodes = _template.nodes.where((n) => n.id != nodeId).toList();
      final newFlows = _template.flows.where((f) => f.fromNodeId != nodeId && f.toNodeId != nodeId).toList();
      _template = _template.copyWith(nodes: newNodes, flows: newFlows);
      if (_selectedNodeId == nodeId) {
        _selectedNodeId = newNodes.isNotEmpty ? newNodes.first.id : null;
      }
    });
  }

  void _handleAddFlow(String fromId, String toId) {
    final exists = _template.flows.any((f) => f.fromNodeId == fromId && f.toNodeId == toId);
    if (!exists) {
      setState(() {
        final newFlows = List<PipelineFlow>.from(_template.flows)..add(PipelineFlow(fromNodeId: fromId, toNodeId: toId));
        _template = _template.copyWith(flows: newFlows);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flow connection established successfully'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _handleAddStage() {
    final nextStageIndex = _template.nodes.isEmpty
        ? 0
        : _template.nodes.map((n) => n.stageIndex).reduce((a, b) => a > b ? a : b) + 1;

    final newNodeId = 'node_${DateTime.now().millisecondsSinceEpoch}';
    final newNode = ProcessNode(
      id: newNodeId,
      name: 'New Manufacturing Operation',
      stageIndex: nextStageIndex,
      laneIndex: 0,
      allocations: const [
        Alloc(id: 'a_m', kind: AllocKind.machine, value: 'PP-40T-01'),
      ],
    );

    final newStageLabels = List<String>.from(_template.stageLabels);
    if (nextStageIndex >= newStageLabels.length) {
      newStageLabels.add('Stage ${nextStageIndex + 1}');
    }

    // Auto connect from last node if available
    final newFlows = List<PipelineFlow>.from(_template.flows);
    if (_template.nodes.isNotEmpty) {
      final prevNode = _template.nodes.last;
      newFlows.add(PipelineFlow(fromNodeId: prevNode.id, toNodeId: newNodeId));
    }

    setState(() {
      _template = _template.copyWith(
        nodes: [..._template.nodes, newNode],
        stageLabels: newStageLabels,
        flows: newFlows,
      );
      _selectedNodeId = newNodeId;
      _isInspectorOpen = true;
    });
  }

  void _handleInsertTemplateFromLibrary(NodeTemplateItem tpl) {
    final nextStageIndex = _template.nodes.isEmpty
        ? 0
        : _template.nodes.map((n) => n.stageIndex).reduce((a, b) => a > b ? a : b) + 1;

    final newNodeId = 'node_${DateTime.now().millisecondsSinceEpoch}';
    final allocs = <Alloc>[
      Alloc(id: 'a1', kind: AllocKind.machine, value: tpl.defaultMachine),
      Alloc(id: 'a2', kind: AllocKind.material, value: tpl.materialIn),
      Alloc(id: 'a3', kind: AllocKind.item, value: tpl.itemOut),
    ];
    if (tpl.defaultDie != null) {
      allocs.add(Alloc(id: 'a4', kind: AllocKind.die, value: tpl.defaultDie!));
    }
    if (tpl.scrapItem != null) {
      allocs.add(Alloc(id: 'a5', kind: AllocKind.scrap, value: tpl.scrapItem!));
    }

    final newNode = ProcessNode(
      id: newNodeId,
      name: tpl.title,
      stageIndex: nextStageIndex,
      laneIndex: 0,
      allocations: allocs,
      sheetPlan: tpl.sheetPlan,
    );

    final newStageLabels = List<String>.from(_template.stageLabels);
    if (nextStageIndex >= newStageLabels.length) {
      newStageLabels.add(tpl.title);
    }

    final newFlows = List<PipelineFlow>.from(_template.flows);
    if (_template.nodes.isNotEmpty) {
      newFlows.add(PipelineFlow(fromNodeId: _template.nodes.last.id, toNodeId: newNodeId));
    }

    setState(() {
      _template = _template.copyWith(
        nodes: [..._template.nodes, newNode],
        stageLabels: newStageLabels,
        flows: newFlows,
      );
      _selectedNodeId = newNodeId;
      _isInspectorOpen = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Inserted "${tpl.title}" from Global Library'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedNode = _selectedNodeId != null
        ? _template.nodes.cast<ProcessNode?>().firstWhere((n) => n?.id == _selectedNodeId, orElse: () => null)
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Workbench Top Toolbar
          _buildToolbar(),

          // Main Interactive Workspace (Canvas + Inspector Panel + Slider)
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PipelineCanvas(
                        template: _template,
                        run: _run,
                        selectedNodeId: _selectedNodeId,
                        onSelectNode: _handleSelectNode,
                        onUpdateNode: _handleUpdateNode,
                        onAddFlow: _handleAddFlow,
                        onAddNodeToStage: (stageIdx) => _handleAddStage(),
                        onAddStage: _handleAddStage,
                      ),
                    ),

                    // Docked MES Floor Node Terminal Inspector
                    if (_isInspectorOpen && selectedNode != null)
                      FloorNodeTerminal(
                        node: selectedNode,
                        onUpdateNode: _handleUpdateNode,
                        onDeleteNode: () => _handleDeleteNode(selectedNode.id),
                        onClose: () => setState(() => _isInspectorOpen = false),
                        onOpenGlobalLibrary: () {
                          setState(() {
                            _isNodeLibrarySliderOpen = true;
                          });
                        },
                      ),
                  ],
                ),

                // Floating Bottom Notch & Slide-Up Node Library Drawer
                GlobalNodeLibrarySlider(
                  isOpen: _isNodeLibrarySliderOpen,
                  onOpen: () => setState(() => _isNodeLibrarySliderOpen = true),
                  onClose: () => setState(() => _isNodeLibrarySliderOpen = false),
                  currentNodeToSave: selectedNode,
                  onSelectTemplate: _handleInsertTemplateFromLibrary,
                ),
              ],
            ),
          ),

          // Bottom Metric & Line Status Bar
          _buildBottomStatusBar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: Pipeline Title & Tags
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_tree_outlined, size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _template.name,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Text(
                            'PHYSICAL CAD ACTIVE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'Order #ORD-9001 • Siemens Precision Enclosure Line',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(width: 24),

            // Right: Action Buttons
            Row(
              children: [
                // Global Node Library Slider Toggle Button
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isNodeLibrarySliderOpen = !_isNodeLibrarySliderOpen;
                    });
                  },
                  icon: const Icon(Icons.hub_outlined, size: 16),
                  label: Text(_isNodeLibrarySliderOpen ? 'Hide Library' : 'Node Library'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _isNodeLibrarySliderOpen ? AppColors.accentDark : AppColors.textPrimary,
                    backgroundColor: _isNodeLibrarySliderOpen ? AppColors.accentLight : Colors.transparent,
                    side: BorderSide(color: _isNodeLibrarySliderOpen ? AppColors.accent : AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),

                // Add Stage Button
                OutlinedButton.icon(
                  onPressed: _handleAddStage,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Stage'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),

                // Run Stage Simulation Button
                ElevatedButton.icon(
                  onPressed: widget.onNavigateToSimulator,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Simulate Transformation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _buildStatusPill('Stages: ${_template.nodes.length}', Icons.layers_outlined),
                const SizedBox(width: 16),
                _buildStatusPill('Flow Links: ${_template.flows.length}', Icons.alt_route_rounded),
                const SizedBox(width: 16),
                _buildStatusPill('1 Sheet → 8 Strips → 72 Blanks', Icons.trending_up),
              ],
            ),
            const SizedBox(width: 24),
            Row(
              children: [
                const Text(
                  'Mass Balance:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '35.03 kg In → 32.12 kg Part (91.7% Yield) + 2.91 kg Scrap',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
