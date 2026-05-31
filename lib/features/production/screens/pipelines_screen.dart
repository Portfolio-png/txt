import 'package:flutter/material.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:provider/provider.dart';

import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';
import '../../production_pipelines/domain/pipeline_template.dart';
import '../../production_pipelines/domain/process_node.dart';
import '../domain/default_floor_context.dart';
import '../providers/pipeline_editor_provider.dart';
import '../providers/production_provider.dart';
import 'live_production_monitor_screen.dart';
import 'pipeline_builder_screen.dart';

class PipelinesScreen extends StatefulWidget {
  const PipelinesScreen({
    super.key,
    this.factoryId = defaultProductionFactoryId,
    this.shopFloorId = defaultProductionShopFloorId,
  });

  final String factoryId;
  final String shopFloorId;

  @override
  State<PipelinesScreen> createState() => _PipelinesScreenState();
}

class _PipelinesScreenState extends State<PipelinesScreen> {
  bool _isLoading = true;
  List<PipelineTemplate> _templates = [];
  PipelineTemplate? _editingTemplate;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void didUpdateWidget(covariant PipelinesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopFloorId != widget.shopFloorId) {
      _editingTemplate = null;
      _loadTemplates();
    }
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      final repo = context.read<PipelineRunRepository>();
      final allTemplates = await repo.getTemplates();
      final floorTemplates = allTemplates
          .where(_belongsToActiveFloor)
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _templates = floorTemplates);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createNew() async {
    final nameCtrl = TextEditingController(text: 'New Pipeline');
    final descCtrl = TextEditingController();
    
    InventoryProvider? inventoryProvider;
    try {
      inventoryProvider = context.read<InventoryProvider>();
    } catch (_) {}
    final materials = inventoryProvider?.materials ?? const [];
    final uniqueMaterialNames = materials.map((m) => m.name).toSet().toList();
    
    OrdersProvider? ordersProvider;
    try {
      ordersProvider = context.read<OrdersProvider>();
    } catch (_) {}
    final orders = ordersProvider?.orders ?? const [];
    final uniqueOrderItems = orders.map((o) => o.itemName).toSet().toList();
    
    final inputCtrl = TextEditingController(
      text: uniqueMaterialNames.isNotEmpty ? uniqueMaterialNames.first : '',
    );
    final outputCtrl = TextEditingController(
      text: uniqueOrderItems.isNotEmpty ? uniqueOrderItems.first : '',
    );

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<PipelineTemplate>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Pipeline'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Pipeline Name'),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Name is required'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                    ),
                    minLines: 2,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: uniqueMaterialNames.contains(inputCtrl.text)
                        ? inputCtrl.text
                        : (uniqueMaterialNames.isNotEmpty ? uniqueMaterialNames.first : null),
                    decoration: const InputDecoration(
                      labelText: 'Input Material',
                    ),
                    items: {
                      if (inputCtrl.text.isNotEmpty && !uniqueMaterialNames.contains(inputCtrl.text))
                        inputCtrl.text,
                      ...uniqueMaterialNames,
                    }.map((name) {
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        inputCtrl.text = val;
                      }
                    },
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Input material is required'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: uniqueOrderItems.contains(outputCtrl.text)
                        ? outputCtrl.text
                        : (uniqueOrderItems.isNotEmpty ? uniqueOrderItems.first : null),
                    decoration: const InputDecoration(
                      labelText: 'Output Material',
                    ),
                    items: {
                      if (outputCtrl.text.isNotEmpty && !uniqueOrderItems.contains(outputCtrl.text))
                        outputCtrl.text,
                      ...uniqueOrderItems,
                    }.map((name) {
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        outputCtrl.text = val;
                      }
                    },
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Output material is required'
                            : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                final name = nameCtrl.text.trim();
                final desc = descCtrl.text.trim();
                final input = inputCtrl.text.trim();
                final output = outputCtrl.text.trim();
                final id = 'tpl-${DateTime.now().microsecondsSinceEpoch}';

                final inputNode = ProcessNode(
                  id: 'node-input-${DateTime.now().microsecondsSinceEpoch}',
                  name: 'Input Stage',
                  processType: 'Input',
                  stageIndex: 0,
                  laneIndex: 0,
                  inputs: [input],
                  outputs: [input],
                  machine: 'Input Stage',
                  dieId: '',
                  durationHours: 0.25,
                  status: 'Ready',
                  isIntermediate: false,
                );

                final outputNode = ProcessNode(
                  id: 'node-output-${DateTime.now().microsecondsSinceEpoch}',
                  name: 'Output Stage',
                  processType: 'Output',
                  stageIndex: 1,
                  laneIndex: 0,
                  inputs: [output],
                  outputs: [output],
                  machine: 'Output Stage',
                  dieId: '',
                  durationHours: 0.25,
                  status: 'Queued',
                  isIntermediate: false,
                );

                Navigator.pop(
                  context,
                  PipelineTemplate(
                    id: id,
                    factoryId: widget.factoryId,
                    shopFloorId: widget.shopFloorId,
                    name: name,
                    description: desc,
                    stageLabels: const ['Input', 'Output'],
                    laneLabels: const ['Main'],
                    nodes: [inputNode, outputNode],
                    flows: const [],
                    inputMaterial: input,
                    outputMaterial: output,
                  ),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _editingTemplate = result;
      });
    }
  }

  void _edit(PipelineTemplate template) {
    setState(() => _editingTemplate = template);
  }

  void _run(PipelineTemplate template) {
    context.read<ProductionProvider>().loadTemplate(template);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LiveProductionMonitorScreen()),
    );
  }

  Future<void> _closeEditorAndReload() async {
    setState(() => _editingTemplate = null);
    await _loadTemplates();
  }

  @override
  Widget build(BuildContext context) {
    final editingTemplate = _editingTemplate;
    if (editingTemplate != null) {
      return _PipelineEditorShell(
        templateName: editingTemplate.name,
        onBack: _closeEditorAndReload,
        child: ChangeNotifierProvider(
          create: (_) => PipelineEditorProvider(template: editingTemplate),
          child: PipelineBuilderScreen(
            factoryId: widget.factoryId,
            shopFloorId: widget.shopFloorId,
          ),
        ),
      );
    }

    return _PipelineLibraryShell(
      title: 'Floor Pipelines',
      subtitle: 'Build and run production routes on the unified floor map.',
      actionLabel: 'New Pipeline',
      onAction: _createNew,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _isLoading
            ? const _PipelineLoading(label: 'Loading pipelines')
            : _templates.isEmpty
            ? _PipelineEmptyState(
                title: 'No pipelines on this map',
                message:
                    'Create a production route to connect stages, machines, and live run execution.',
                actionLabel: 'Create Pipeline',
                onAction: _createNew,
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1220
                      ? 3
                      : constraints.maxWidth >= 820
                      ? 2
                      : 1;
                  return GridView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _templates.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: columns == 1 ? 3.05 : 2.25,
                    ),
                    itemBuilder: (context, index) {
                      final template = _templates[index];
                      return _PipelineTemplateCard(
                        template: template,
                        onEdit: () => _edit(template),
                        onRun: () => _run(template),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  bool _belongsToActiveFloor(PipelineTemplate template) {
    if (widget.shopFloorId == defaultProductionShopFloorId) {
      return true;
    }
    if (template.shopFloorId == widget.shopFloorId) {
      return true;
    }
    return belongsToDefaultFloor(template.shopFloorId);
  }
}

class _PipelineEditorShell extends StatelessWidget {
  const _PipelineEditorShell({
    required this.templateName,
    required this.onBack,
    required this.child,
  });

  final String templateName;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to pipelines'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF3B82F6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    templateName.trim().isEmpty
                        ? 'Pipeline Builder'
                        : templateName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const _RouteBadge(label: 'Builder', value: 'Edit mode'),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _PipelineTemplateCard extends StatelessWidget {
  const _PipelineTemplateCard({
    required this.template,
    required this.onEdit,
    required this.onRun,
  });

  final PipelineTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final nodeCount = template.nodes.length;
    final flowCount = template.flows.length;
    final stageCount = template.stageLabels.length;
    final hasRunnableRoute = nodeCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _PipelineCardPainter(
                    nodeCount: nodeCount,
                    flowCount: flowCount,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'ROUTE',
                            style: TextStyle(
                              color: Color(0xFF3B82F6),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const Spacer(),
                        _PipelineStatusBadge(
                          label: hasRunnableRoute ? 'Ready' : 'Draft',
                          active: hasRunnableRoute,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      template.name.trim().isEmpty
                          ? 'Unnamed pipeline'
                          : template.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.description.trim().isEmpty
                          ? 'Production route for the unified floor map'
                          : template.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _RouteBadge(label: 'Stages', value: '$stageCount'),
                        const SizedBox(width: 8),
                        _RouteBadge(label: 'Nodes', value: '$nodeCount'),
                        const SizedBox(width: 8),
                        _RouteBadge(label: 'Flows', value: '$flowCount'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit_rounded, size: 17),
                            label: const Text('Edit'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF1E293B),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: hasRunnableRoute ? onRun : null,
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                            ),
                            label: const Text('Run'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFFE1E5DF),
                              disabledForegroundColor: const Color(0xFF8A948F),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineStatusBadge extends StatelessWidget {
  const _PipelineStatusBadge({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RouteBadge extends StatelessWidget {
  const _RouteBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineCardPainter extends CustomPainter {
  const _PipelineCardPainter({
    required this.nodeCount,
    required this.flowCount,
  });

  final int nodeCount;
  final int flowCount;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.34)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final routePaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final route = Path()
      ..moveTo(size.width * 0.12, size.height * 0.42)
      ..cubicTo(
        size.width * 0.30,
        size.height * 0.18,
        size.width * 0.44,
        size.height * 0.72,
        size.width * 0.62,
        size.height * 0.48,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.30,
        size.width * 0.92,
        size.height * 0.54,
      );
    canvas.drawPath(route, routePaint);

    final nodePaint = Paint()
      ..color = nodeCount > 0
          ? const Color(0xFF3B82F6)
          : const Color(0xFFCBD5E1);
    final ringPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final point in [
      Offset(size.width * 0.12, size.height * 0.42),
      Offset(size.width * 0.38, size.height * 0.48),
      Offset(size.width * 0.62, size.height * 0.48),
      Offset(size.width * 0.92, size.height * 0.54),
    ]) {
      canvas.drawCircle(point, 5, nodePaint);
      canvas.drawCircle(point, 5, ringPaint);
    }

    if (flowCount == 0) {
      final draftPaint = Paint()
        ..color = const Color(0xFFF4B860).withValues(alpha: 0.26)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size.width * 0.72, size.height * 0.30),
        16,
        draftPaint,
      );
      canvas.drawCircle(
        Offset(size.width * 0.72, size.height * 0.30),
        5,
        Paint()..color = const Color(0xFFD78D18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PipelineCardPainter oldDelegate) {
    return oldDelegate.nodeCount != nodeCount ||
        oldDelegate.flowCount != flowCount;
  }
}

class _PipelineLibraryShell extends StatelessWidget {
  const _PipelineLibraryShell({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(actionLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PipelineEmptyState extends StatelessWidget {
  const _PipelineEmptyState({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_tree_rounded,
              color: Color(0xFF3B82F6),
              size: 38,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _PipelineLoading extends StatelessWidget {
  const _PipelineLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
