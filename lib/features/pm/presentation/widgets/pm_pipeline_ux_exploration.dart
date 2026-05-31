import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_info_panel.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';

// --- DATA STRUCTURES ---

class PipelineNode {
  PipelineNode({
    required this.id,
    required this.name,
    required this.stage,
    required this.machine,
    required this.status,
    required this.throughput,
    this.x = 0.0,
    this.y = 0.0,
  });

  final String id;
  String name;
  String stage;
  String machine;
  String status;
  double throughput; // in metric tons / hr
  double x;
  double y;
}

class PipelineConnection {
  PipelineConnection(this.fromId, this.toId);
  final String fromId;
  final String toId;
}

// --- MAIN UX EXPLORATION SECTION ---

class PMPipelineUxExplorationSection extends StatefulWidget {
  const PMPipelineUxExplorationSection({super.key});

  @override
  State<PMPipelineUxExplorationSection> createState() =>
      _PMPipelineUxExplorationSectionState();
}

class _PMPipelineUxExplorationSectionState
    extends State<PMPipelineUxExplorationSection> {
  String _selectedParadigm = 'canvas';

  // State for Canvas Paradigm
  final List<PipelineNode> _canvasNodes = [
    PipelineNode(id: 'n1', name: 'Raw Mixing', stage: 'Preparation', machine: 'Mixer M-02', status: 'Running', throughput: 12.5, x: 50, y: 100),
    PipelineNode(id: 'n2', name: 'Extrusion', stage: 'Forming', machine: 'Extruder E-08', status: 'Running', throughput: 10.0, x: 220, y: 100),
    PipelineNode(id: 'n3', name: 'Slitting & Cut', stage: 'Finishing', machine: 'Slitter S-04', status: 'Idle', throughput: 15.0, x: 390, y: 50),
    PipelineNode(id: 'n4', name: 'Winding Roll', stage: 'Packaging', machine: 'Winder W-10', status: 'Setup', throughput: 8.5, x: 560, y: 100),
  ];
  final List<PipelineConnection> _canvasConnections = [
    PipelineConnection('n1', 'n2'),
    PipelineConnection('n2', 'n3'),
    PipelineConnection('n3', 'n4'),
  ];
  String? _selectedNodeId;
  bool _isLinkingMode = false;
  String? _linkSourceId;

  // State for Kanban Paradigm
  final List<PipelineNode> _kanbanNodes = [
    PipelineNode(id: 'k1', name: 'Pulping Feed', stage: 'Feed/Prep', machine: 'Pulper P-1', status: 'Running', throughput: 25.0),
    PipelineNode(id: 'k2', name: 'Chemical Add', stage: 'Feed/Prep', machine: 'Mixer MX-5', status: 'Running', throughput: 22.0),
    PipelineNode(id: 'k3', name: 'Hot Pressing', stage: 'Forming', machine: 'Press HP-2', status: 'Running', throughput: 18.0),
    PipelineNode(id: 'k4', name: 'Oven Drying', stage: 'Forming', machine: 'Dryer D-12', status: 'Idle', throughput: 15.0),
    PipelineNode(id: 'k5', name: 'Precision Slit', stage: 'Finishing', machine: 'Slitter S-9', status: 'Running', throughput: 20.0),
    PipelineNode(id: 'k6', name: 'Visual Check', stage: 'Quality Control', machine: 'Cam QC-1', status: 'Running', throughput: 30.0),
  ];
  final List<String> _stages = ['Feed/Prep', 'Forming', 'Finishing', 'Quality Control'];
  String? _selectedKanbanNodeId;

  // State for Timeline Paradigm
  final List<PipelineNode> _timelineNodes = [
    PipelineNode(id: 't1', name: 'Pulp Intake', stage: 'Preparation', machine: 'Feed Conveyor C-1', status: 'Active', throughput: 40.0),
    PipelineNode(id: 't2', name: 'Hydraulic Pressing', stage: 'Forming', machine: 'Hydraulic Press H-4', status: 'Active', throughput: 35.0),
    PipelineNode(id: 't3', name: 'Moisture Control Check', stage: 'QC Decision', machine: 'Moisture Sensor MS-2', status: 'Active', throughput: 35.0),
  ];
  final List<PipelineNode> _timelinePassBranch = [
    PipelineNode(id: 'tb1', name: 'Standard Packaging', stage: 'Packaging', machine: 'Packer PK-8', status: 'Pending', throughput: 35.0),
  ];
  final List<PipelineNode> _timelineFailBranch = [
    PipelineNode(id: 'tb2', name: 'Slurry Repulping', stage: 'Recycle', machine: 'Beater B-2', status: 'Inactive', throughput: 10.0),
  ];

  // State for AI Prompt Builder
  final TextEditingController _promptController = TextEditingController(
    text: 'Create a high-speed cardboard pipeline with pulping, pressing, edge-trimming, winding and automated quality check.',
  );
  List<PipelineNode> _aiGeneratedNodes = [];
  bool _aiGenerating = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _runAIPipelineGenerator(String prompt) async {
    setState(() {
      _aiGenerating = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 900));

    final nodes = <PipelineNode>[];
    final text = prompt.toLowerCase();

    if (text.contains('pulp') || text.contains('cardboard') || text.contains('paper')) {
      nodes.add(PipelineNode(id: 'ai1', name: 'Hydro-Pulping', stage: 'Preparation', machine: 'HP-Pulper 500', status: 'Ready', throughput: 50.0));
    } else {
      nodes.add(PipelineNode(id: 'ai1', name: 'Raw Material Feed', stage: 'Preparation', machine: 'Feeder F-100', status: 'Ready', throughput: 30.0));
    }

    if (text.contains('press') || text.contains('mold')) {
      nodes.add(PipelineNode(id: 'ai2', name: 'Thermo-Press Molding', stage: 'Forming', machine: 'Press-Grid X', status: 'Ready', throughput: 45.0));
    } else {
      nodes.add(PipelineNode(id: 'ai2', name: 'Extrusion Forming', stage: 'Forming', machine: 'Extruder Ex-2', status: 'Ready', throughput: 28.0));
    }

    if (text.contains('trim') || text.contains('slit') || text.contains('cut')) {
      nodes.add(PipelineNode(id: 'ai3', name: 'Laser Edge-Trimming', stage: 'Finishing', machine: 'Laser Cutter L-20', status: 'Ready', throughput: 60.0));
    }

    if (text.contains('wind') || text.contains('roll')) {
      nodes.add(PipelineNode(id: 'ai4', name: 'High-Tension Winding', stage: 'Finishing', machine: 'Reeler R-40', status: 'Ready', throughput: 42.0));
    }

    if (text.contains('check') || text.contains('qc') || text.contains('quality')) {
      nodes.add(PipelineNode(id: 'ai5', name: 'Automated Vision QC', stage: 'Quality Control', machine: 'OptiCheck V3', status: 'Ready', throughput: 100.0));
    }

    setState(() {
      _aiGeneratedNodes = nodes;
      _aiGenerating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Production Pipeline builder UX/UI explorations',
            subtitle: 'Different frontend paradigms for structuring factory routing sequences, designed to make pipeline creation fast and intuitive.',
          ),
          const SizedBox(height: 20),
          // Paradigm Selection Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ParadigmTabButton(
                  id: 'canvas',
                  label: 'Interactive Canvas',
                  icon: Icons.hub_outlined,
                  isSelected: _selectedParadigm == 'canvas',
                  onTap: () => setState(() => _selectedParadigm = 'canvas'),
                ),
                const SizedBox(width: 8),
                _ParadigmTabButton(
                  id: 'kanban',
                  label: 'Stage Board (Kanban)',
                  icon: Icons.view_week_outlined,
                  isSelected: _selectedParadigm == 'kanban',
                  onTap: () => setState(() => _selectedParadigm = 'kanban'),
                ),
                const SizedBox(width: 8),
                _ParadigmTabButton(
                  id: 'timeline',
                  label: 'Linear Branching Flow',
                  icon: Icons.alt_route_outlined,
                  isSelected: _selectedParadigm == 'timeline',
                  onTap: () => setState(() => _selectedParadigm = 'timeline'),
                ),
                const SizedBox(width: 8),
                _ParadigmTabButton(
                  id: 'ai',
                  label: 'Conversational Gen-AI',
                  icon: Icons.psychology_outlined,
                  isSelected: _selectedParadigm == 'ai',
                  onTap: () {
                    setState(() => _selectedParadigm = 'ai');
                    if (_aiGeneratedNodes.isEmpty) {
                      _runAIPipelineGenerator(_promptController.text);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Sandbox Container
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 420),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _buildActiveParadigm(),
          ),
          const SizedBox(height: 20),
          // App Info Panel summarizing features
          AppInfoPanel(
            title: 'UX Paradigm Matrix',
            subtitle: 'Choose the visual paradigm that matches the operator\'s cognitive load and factory complexity.',
            rows: [
              AppInfoRow(
                label: 'Interactive Canvas',
                value: 'Best for complex pipelines with non-linear paths, multiple sub-branches, and circular loops. High interaction flexibility.',
              ),
              AppInfoRow(
                label: 'Stage Board (Kanban)',
                value: 'Best for structured factories organized by departments or cost centers. Highly structured, prevents messy wiring diagrams.',
              ),
              AppInfoRow(
                label: 'Linear Branching',
                value: 'Best for single-product setups with simple Pass/Fail loops. Very fast to audit and sequential.',
              ),
              AppInfoRow(
                label: 'Conversational Gen-AI',
                value: 'Best for rapid drafting and onboarding. Converts natural text or operational specs into a complete routing layout.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveParadigm() {
    switch (_selectedParadigm) {
      case 'canvas':
        return _buildCanvasParadigm();
      case 'kanban':
        return _buildKanbanParadigm();
      case 'timeline':
        return _buildTimelineParadigm();
      case 'ai':
        return _buildAIPromptParadigm();
      default:
        return const Center(child: Text('Unknown Paradigm'));
    }
  }

  // --- 1. CANVAS PARADIGM BUILDER ---

  Widget _buildCanvasParadigm() {
    final selectedNode = _canvasNodes.where((n) => n.id == _selectedNodeId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Visual Node Grid Canvas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                Text(
                  _isLinkingMode
                      ? 'Select the target node to link from ${_canvasNodes.firstWhere((n) => n.id == _linkSourceId).name}'
                      : 'Drag elements or tap them to view properties, link inputs, or edit configurations.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  final newId = 'n${_canvasNodes.length + 1}';
                  _canvasNodes.add(
                    PipelineNode(
                      id: newId,
                      name: 'Stage Node ${_canvasNodes.length + 1}',
                      stage: 'Finishing',
                      machine: 'Cutter C-01',
                      status: 'Setup',
                      throughput: 5.0,
                      x: 100 + (_canvasNodes.length * 20.0) % 200,
                      y: 160 + (_canvasNodes.length * 15.0) % 100,
                    ),
                  );
                });
              },
              icon: const Icon(Icons.add, size: 18, color: Color(0xFF3B82F6)),
              label: const Text('Add Step Node', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.grey),
              tooltip: 'Reset Grid',
              onPressed: () {
                setState(() {
                  _canvasNodes.clear();
                  _canvasNodes.addAll([
                    PipelineNode(id: 'n1', name: 'Raw Mixing', stage: 'Preparation', machine: 'Mixer M-02', status: 'Running', throughput: 12.5, x: 50, y: 100),
                    PipelineNode(id: 'n2', name: 'Extrusion', stage: 'Forming', machine: 'Extruder E-08', status: 'Running', throughput: 10.0, x: 220, y: 100),
                    PipelineNode(id: 'n3', name: 'Slitting & Cut', stage: 'Finishing', machine: 'Slitter S-04', status: 'Idle', throughput: 15.0, x: 390, y: 50),
                    PipelineNode(id: 'n4', name: 'Winding Roll', stage: 'Packaging', machine: 'Winder W-10', status: 'Setup', throughput: 8.5, x: 560, y: 100),
                  ]);
                  _canvasConnections.clear();
                  _canvasConnections.addAll([
                    PipelineConnection('n1', 'n2'),
                    PipelineConnection('n2', 'n3'),
                    PipelineConnection('n3', 'n4'),
                  ]);
                  _selectedNodeId = null;
                  _isLinkingMode = false;
                  _linkSourceId = null;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Canvas Board
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Dots Grid Background
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DotGridPainter(),
                  ),
                ),
                // Draw connection lines
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CanvasConnectionsPainter(
                      nodes: _canvasNodes,
                      connections: _canvasConnections,
                    ),
                  ),
                ),
                // Render Nodes
                ..._canvasNodes.map((node) {
                  final isSelected = node.id == _selectedNodeId;
                  final isLinkSource = node.id == _linkSourceId;
                  return Positioned(
                    left: node.x,
                    top: node.y,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_isLinkingMode) {
                            if (_linkSourceId != null && _linkSourceId != node.id) {
                              // Create connection
                              _canvasConnections.add(PipelineConnection(_linkSourceId!, node.id));
                            }
                            _isLinkingMode = false;
                            _linkSourceId = null;
                          } else {
                            _selectedNodeId = node.id;
                          }
                        });
                      },
                      onPanUpdate: (details) {
                        setState(() {
                          node.x += details.delta.dx;
                          node.y += details.delta.dy;
                          if (node.x < 10) node.x = 10;
                          if (node.y < 10) node.y = 10;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isLinkSource
                                ? Colors.orange
                                : (isSelected ? const Color(0xFF3B82F6) : const Color(0xFFCBD5E1)),
                            width: isSelected || isLinkSource ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isSelected
                                  ? const Color(0x223B82F6)
                                  : Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: node.status == 'Running'
                                    ? Colors.green
                                    : (node.status == 'Idle' ? Colors.orange : Colors.grey),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  node.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                Text(
                                  node.machine,
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Selected Node Details & Operations
        if (selectedNode != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Node: ${selectedNode.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Badge(label: selectedNode.stage, color: Colors.blue.shade100, textColor: Colors.blue.shade800),
                          const SizedBox(width: 6),
                          _Badge(label: selectedNode.machine, color: Colors.grey.shade200, textColor: Colors.black87),
                          const SizedBox(width: 6),
                          _Badge(
                            label: '${selectedNode.throughput} t/h',
                            color: Colors.green.shade100,
                            textColor: Colors.green.shade800,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        setState(() {
                          _isLinkingMode = true;
                          _linkSourceId = selectedNode.id;
                        });
                      },
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('Connect Output', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        setState(() {
                          _canvasConnections.removeWhere((c) => c.fromId == selectedNode.id || c.toId == selectedNode.id);
                          _canvasNodes.remove(selectedNode);
                          _selectedNodeId = null;
                        });
                      },
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Delete Node', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            child: const Text(
              'Select a node to link connections or edit physical attributes.',
              style: TextStyle(color: Color(0xFF64748B), fontStyle: FontStyle.italic, fontSize: 13),
            ),
          ),
      ],
    );
  }

  // --- 2. KANBAN / STAGE BOARD PARADIGM ---

  Widget _buildKanbanParadigm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stage Swimlane Board',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const Text(
          'Pipeline broken down by department or physical stages. Click arrows to shift process steps or tap cards to configure.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        // Columns view
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _stages.map((stage) {
            final stageNodes = _kanbanNodes.where((n) => n.stage == stage).toList();
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          stage,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF475569)),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${stageNodes.length}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...stageNodes.map((node) {
                      final isSelected = node.id == _selectedKanbanNodeId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: InkWell(
                          onTap: () => setState(() => _selectedKanbanNodeId = node.id),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1E293B)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                node.machine,
                                style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    '${node.throughput} t/h',
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                                  ),
                                  const Spacer(),
                                  // Left Arrow
                                  if (_stages.indexOf(stage) > 0)
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          final currentIdx = _stages.indexOf(stage);
                                          node.stage = _stages[currentIdx - 1];
                                        });
                                      },
                                      child: const Icon(Icons.arrow_back_ios, size: 10, color: Color(0xFF94A3B8)),
                                    ),
                                  const SizedBox(width: 6),
                                  // Right Arrow
                                  if (_stages.indexOf(stage) < _stages.length - 1)
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          final currentIdx = _stages.indexOf(stage);
                                          node.stage = _stages[currentIdx + 1];
                                        });
                                      },
                                      child: const Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFF94A3B8)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    // Add Card inline button
                    InkWell(
                      onTap: () {
                        setState(() {
                          final newId = 'k${_kanbanNodes.length + 1}';
                          _kanbanNodes.add(
                            PipelineNode(
                              id: newId,
                              name: 'New Custom Process',
                              stage: stage,
                              machine: 'Standard M-1',
                              status: 'Running',
                              throughput: 10.0,
                            ),
                          );
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add, size: 12, color: Color(0xFF64748B)),
                            SizedBox(width: 4),
                            Text('Add process', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Kanban Info Panel
        if (_selectedKanbanNodeId != null)
          ...[
            (() {
              final node = _kanbanNodes.firstWhere((n) => n.id == _selectedKanbanNodeId);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configure: ${node.name}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Department: ${node.stage}  |  Machine: ${node.machine}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    const Spacer(),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        setState(() {
                          _kanbanNodes.removeWhere((n) => n.id == _selectedKanbanNodeId);
                          _selectedKanbanNodeId = null;
                        });
                      },
                      child: const Text('Delete', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ],
                ),
              );
            })(),
          ],
      ],
    );
  }

  // --- 3. TIMELINE / LINEAR BRANCHING PARADIGM ---

  Widget _buildTimelineParadigm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Linear Flow with Decision Branches',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const Text(
          'Clean, top-to-bottom procedural workflow sequence. Shows conditional paths dynamically.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 20),
        // Sequence layout
        Column(
          children: [
            // Standard nodes
            ..._timelineNodes.asMap().entries.map((entry) {
              final idx = entry.key;
              final node = entry.value;

              return Column(
                children: [
                  _buildTimelineStepCard(node, idx + 1),
                  // Draw connecting line or add button
                  if (idx < _timelineNodes.length - 1)
                    _buildInsertTimelineStepButton(idx),
                ],
              );
            }),
            // Connection line to branch
            _buildBranchingDivider(),
            // Branches Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pass Branch (Left)
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: const Text('PASS ROUTE (Quality Target Met)', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      ..._timelinePassBranch.map((node) => _buildTimelineStepCard(node, null, color: Colors.green.shade50)),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Fail Branch (Right)
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: const Text('RE-ROUTE (Target Not Met)', style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      ..._timelineFailBranch.map((node) => _buildTimelineStepCard(node, null, color: Colors.red.shade50)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimelineStepCard(PipelineNode node, int? number, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          if (number != null) ...[
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$number',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                ),
                Text(
                  'Machine: ${node.machine} | ${node.stage}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Text(
            '${node.throughput} t/h',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }

  Widget _buildInsertTimelineStepButton(int idx) {
    return SizedBox(
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 2, height: 36, color: const Color(0xFFE2E8F0)),
          Positioned(
            child: InkWell(
              onTap: () {
                setState(() {
                  _timelineNodes.insert(
                    idx + 1,
                    PipelineNode(
                      id: 't_inserted_${_timelineNodes.length}',
                      name: 'Inline Inspection',
                      stage: 'Interim QA',
                      machine: 'Sensor S-3',
                      status: 'Active',
                      throughput: 35.0,
                    ),
                  );
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 10, color: Colors.blue),
                    SizedBox(width: 4),
                    Text('Insert step', style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchingDivider() {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 2, height: 48, color: const Color(0xFFE2E8F0)),
          const Positioned(
            bottom: 0,
            child: Icon(Icons.keyboard_arrow_down, color: Color(0xFF94A3B8), size: 16),
          ),
        ],
      ),
    );
  }

  // --- 4. CONVERSATIONAL / AI PROMPT BUILDER ---

  Widget _buildAIPromptParadigm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Natural Language Generator (Gen-AI Router)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const Text(
          'Specify your operational requirements, and watch the system construct the stages, configure the physical assets, and trace the routing layout.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        // Interactive prompt input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promptController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter routing prompt...',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _runAIPipelineGenerator(_promptController.text),
              child: const Text('Generate Route', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Sample prompts choices
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PromptSuggestionChip(
              text: 'Eco Cardboard pulp press QC line',
              onTap: () {
                _promptController.text = 'Generate an eco cardboard line with pulping, hot pressing, and vision QC sensor.';
                _runAIPipelineGenerator(_promptController.text);
              },
            ),
            _PromptSuggestionChip(
              text: 'Standard Paper Tube route',
              onTap: () {
                _promptController.text = 'Create a paper tube production line containing reel unwind, tube winding, cut-off and inspection.';
                _runAIPipelineGenerator(_promptController.text);
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Results/Output section
        if (_aiGenerating)
          Container(
            height: 150,
            alignment: Alignment.center,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF0F172A)),
                SizedBox(height: 12),
                Text('AI generating optimal machine routing stages...', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
              ],
            ),
          )
        else if (_aiGeneratedNodes.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Router Output (Generated Layout)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  children: _aiGeneratedNodes.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final node = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Color(0xFF16A34A),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${idx + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                Text('Department: ${node.stage}  |  Assigned Machine: ${node.machine}', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                              ],
                            ),
                          ),
                          Text('${node.throughput} t/h', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          )
        else
          Container(
            height: 120,
            alignment: Alignment.center,
            child: const Text(
              'Click Generate Route to test natural language parsing.',
              style: TextStyle(color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }
}

// --- UTILITY WIDGETS & PAINTERS ---

class _ParadigmTabButton extends StatelessWidget {
  const _ParadigmTabButton({
    required this.id,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : const Color(0xFF334155),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptSuggestionChip extends StatelessWidget {
  const _PromptSuggestionChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, required this.textColor});

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: textColor, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.4)
      ..strokeWidth = 2;

    const space = 20.0;
    for (double x = 0; x < size.width; x += space) {
      for (double y = 0; y < size.height; y += space) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CanvasConnectionsPainter extends CustomPainter {
  _CanvasConnectionsPainter({required this.nodes, required this.connections});

  final List<PipelineNode> nodes;
  final List<PipelineConnection> connections;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final arrowPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.fill;

    for (final conn in connections) {
      final fromNode = nodes.where((n) => n.id == conn.fromId).firstOrNull;
      final toNode = nodes.where((n) => n.id == conn.toId).firstOrNull;

      if (fromNode != null && toNode != null) {
        // Find center of right side of fromNode and center of left side of toNode
        // Width estimation of node widget is around 130, height around 45
        final start = Offset(fromNode.x + 130, fromNode.y + 22);
        final end = Offset(toNode.x, toNode.y + 22);

        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + 50, start.dy,
            end.dx - 50, end.dy,
            end.dx, end.dy,
          );

        canvas.drawPath(path, paint);

        // Draw a small arrow indicator at the end point
        final arrowPath = Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(end.dx - 6, end.dy - 4)
          ..lineTo(end.dx - 6, end.dy + 4)
          ..close();
        canvas.drawPath(arrowPath, arrowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
