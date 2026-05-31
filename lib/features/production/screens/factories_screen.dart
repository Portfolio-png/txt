import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/production_repository.dart';
import '../domain/factory.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';

class FactoriesScreen extends StatefulWidget {
  const FactoriesScreen({super.key, required this.onFactorySelected});

  final ValueChanged<String> onFactorySelected;

  @override
  State<FactoriesScreen> createState() => _FactoriesScreenState();
}

class _FactoriesScreenState extends State<FactoriesScreen> {
  bool _isLoading = true;
  List<Factory> _factories = [];
  Map<String, int> _floorCounts = {};
  Map<String, int> _pipelineCounts = {};

  @override
  void initState() {
    super.initState();
    _loadFactories();
  }

  Future<void> _loadFactories() async {
    setState(() => _isLoading = true);
    try {
      final repo = context.read<ProductionRepository>();
      final pipelineRepo = context.read<PipelineRunRepository>();
      final factories = await repo.getFactories();
      final allTemplates = await pipelineRepo.getTemplates();
      
      final floorCounts = <String, int>{};
      final pipelineCounts = <String, int>{};
      
      for (final f in factories) {
        final floors = await repo.getShopFloors(f.id);
        floorCounts[f.id] = floors.length;
        int pCount = 0;
        for (final floor in floors) {
           pCount += allTemplates.where((t) => t.shopFloorId == floor.id).length;
        }
        pipelineCounts[f.id] = pCount;
      }
      if (!mounted) return;
      setState(() {
        _factories = factories;
        _floorCounts = floorCounts;
        _pipelineCounts = pipelineCounts;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createFactory() async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New Factory'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Factory Name'),
                ),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Factory Code'),
                ),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      );

      if (result == true && mounted) {
        final repo = context.read<ProductionRepository>();
        await repo.createFactory(
          Factory(
            id: 'fac-${DateTime.now().microsecondsSinceEpoch}',
            name: nameCtrl.text.trim().isEmpty
                ? 'New Factory'
                : nameCtrl.text.trim(),
            code: codeCtrl.text.trim().isEmpty
                ? 'FAC'
                : codeCtrl.text.trim().toUpperCase(),
            location: locationCtrl.text.trim().isEmpty
                ? 'Unassigned location'
                : locationCtrl.text.trim(),
          ),
        );
        await _loadFactories();
      }
    } finally {
      nameCtrl.dispose();
      codeCtrl.dispose();
      locationCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ProductionDirectoryShell(
      title: 'Factory Directory',
      subtitle: 'Choose the factory before moving into shop-floor operations.',
      actionLabel: 'New Factory',
      onAction: _createFactory,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _isLoading
            ? const _ProductionLoading(label: 'Loading factories')
            : _factories.isEmpty
                ? _ProductionEmptyState(
                    title: 'No factories yet',
                    message:
                        'Create your first factory to unlock floor maps and pipeline routes.',
                    actionLabel: 'Create Factory',
                    onAction: _createFactory,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1180
                          ? 3
                          : constraints.maxWidth >= 760
                              ? 2
                              : 1;
                      return GridView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: _factories.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: columns == 1 ? 3.2 : 2.45,
                        ),
                        itemBuilder: (context, index) {
                          final factory = _factories[index];
                          return _FactoryMapCard(
                            factory: factory,
                            floorCount: _floorCounts[factory.id] ?? 0,
                            pipelineCount: _pipelineCounts[factory.id] ?? 0,
                            onTap: () => widget.onFactorySelected(factory.id),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

class _FactoryMapCard extends StatelessWidget {
  const _FactoryMapCard({required this.factory, required this.floorCount, required this.pipelineCount, required this.onTap});

  final Factory factory;
  final int floorCount;
  final int pipelineCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
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
              Positioned.fill(child: CustomPaint(painter: _FactoryCardPainter())),
              Padding(
                padding: const EdgeInsets.all(18),
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
                          child: Text(
                            factory.code.isEmpty ? 'FACTORY' : factory.code,
                            style: const TextStyle(
                              color: Color(0xFF3B82F6),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.north_east_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      factory.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      factory.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MiniFactoryStat(label: 'Floors', value: floorCount.toString()),
                        const SizedBox(width: 8),
                        _MiniFactoryStat(label: 'Pipelines', value: pipelineCount.toString()),
                        const SizedBox(width: 8),
                        const _MiniFactoryStat(label: 'OEE', value: 'N/A'),
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

class _MiniFactoryStat extends StatelessWidget {
  const _MiniFactoryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9).withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
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

class _FactoryCardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFFDADDD6).withValues(alpha: 0.42)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 34) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 0.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    final blockPaint = Paint()..color = const Color(0xFFE8EBE5);
    final borderPaint = Paint()
      ..color = const Color(0xFFCDD3CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final blocks = [
      Rect.fromLTWH(size.width * 0.58, size.height * 0.14, 72, 42),
      Rect.fromLTWH(size.width * 0.70, size.height * 0.44, 92, 46),
      Rect.fromLTWH(size.width * 0.44, size.height * 0.55, 78, 38),
    ];
    for (final block in blocks) {
      final rrect = RRect.fromRectAndRadius(block, const Radius.circular(10));
      canvas.drawRRect(rrect, blockPaint);
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FactoryCardPainter oldDelegate) => false;
}

class _ProductionDirectoryShell extends StatelessWidget {
  const _ProductionDirectoryShell({
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

class _ProductionEmptyState extends StatelessWidget {
  const _ProductionEmptyState({
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
        width: 440,
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
              Icons.map_outlined,
              color: Color(0xFF3B82F6),
              size: 38,
            ),
            const SizedBox(height: 14),
            Text(
              title,
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

class _ProductionLoading extends StatelessWidget {
  const _ProductionLoading({required this.label});

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
