import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/production_repository.dart';
import '../domain/shop_floor.dart';
import '../../production_pipelines/data/repositories/pipeline_run_repository.dart';

class ShopFloorsScreen extends StatefulWidget {
  const ShopFloorsScreen({
    super.key,
    required this.factoryId,
    required this.onShopFloorSelected,
  });

  final String? factoryId;
  final ValueChanged<String> onShopFloorSelected;

  @override
  State<ShopFloorsScreen> createState() => _ShopFloorsScreenState();
}

class _ShopFloorsScreenState extends State<ShopFloorsScreen> {
  bool _isLoading = true;
  List<ShopFloor> _floors = [];
  Map<String, int> _pipelineCounts = {};
  Map<String, int> _nodeCounts = {};

  @override
  void initState() {
    super.initState();
    _loadFloors();
  }

  @override
  void didUpdateWidget(covariant ShopFloorsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.factoryId != widget.factoryId) {
      _loadFloors();
    }
  }

  Future<void> _loadFloors() async {
    if (widget.factoryId == null) {
      setState(() {
        _floors = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = context.read<ProductionRepository>();
      final pipelineRepo = context.read<PipelineRunRepository>();
      final floors = await repo.getShopFloors(widget.factoryId!);
      final allTemplates = await pipelineRepo.getTemplates();

      final pipelineCounts = <String, int>{};
      final nodeCounts = <String, int>{};

      for (final floor in floors) {
        final floorTemplates = allTemplates.where((t) => t.shopFloorId == floor.id).toList();
        pipelineCounts[floor.id] = floorTemplates.length;
        
        int nTotal = 0;
        for (final t in floorTemplates) {
          nTotal += t.nodes.length;
        }
        nodeCounts[floor.id] = nTotal;
      }
      
      if (!mounted) return;
      setState(() {
        _floors = floors;
        _pipelineCounts = pipelineCounts;
        _nodeCounts = nodeCounts;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createShopFloor() async {
    if (widget.factoryId == null) return;

    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New Shop Floor'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Floor Name'),
                ),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Floor Code'),
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
        await repo.createShopFloor(
          ShopFloor(
            id: 'floor-${DateTime.now().microsecondsSinceEpoch}',
            factoryId: widget.factoryId!,
            name: nameCtrl.text.trim().isEmpty
                ? 'Fabrication Floor'
                : nameCtrl.text.trim(),
            code: codeCtrl.text.trim().isEmpty
                ? 'FLR'
                : codeCtrl.text.trim().toUpperCase(),
          ),
        );
        await _loadFloors();
      }
    } finally {
      nameCtrl.dispose();
      codeCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.factoryId == null) {
      return const _ShopFloorGateMessage();
    }

    return _ShopFloorDirectoryShell(
      title: 'Shop Floors',
      subtitle: 'Choose the production area to open its live operations map.',
      actionLabel: 'New Floor',
      onAction: _createShopFloor,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _isLoading
            ? const _ShopFloorLoading(label: 'Loading shop floors')
            : _floors.isEmpty
            ? _ShopFloorEmptyState(
                title: 'No shop floors in this factory',
                message:
                    'Create a floor or zone before mapping pipelines and production routes.',
                actionLabel: 'Create Floor',
                onAction: _createShopFloor,
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
                    itemCount: _floors.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: columns == 1 ? 3.35 : 2.55,
                    ),
                    itemBuilder: (context, index) {
                      final floor = _floors[index];
                      return _ShopFloorMapCard(
                        floor: floor,
                        pipelineCount: _pipelineCounts[floor.id] ?? 0,
                        nodeCount: _nodeCounts[floor.id] ?? 0,
                        onTap: () => widget.onShopFloorSelected(floor.id),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _ShopFloorMapCard extends StatelessWidget {
  const _ShopFloorMapCard({required this.floor, required this.pipelineCount, required this.nodeCount, required this.onTap});

  final ShopFloor floor;
  final int pipelineCount;
  final int nodeCount;
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
              Positioned.fill(child: CustomPaint(painter: _FloorCardPainter())),
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
                            floor.code.trim().isEmpty
                                ? 'FLOOR'
                                : floor.code.trim().toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF3B82F6),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Open map',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Icon(
                          Icons.north_east_rounded,
                          size: 17,
                          color: Color(0xFF64748B),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      floor.name.trim().isEmpty ? 'Unnamed floor' : floor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Spatial floor map · routes · pipeline performance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MiniFloorStat(label: 'Pipelines', value: pipelineCount.toString()),
                        const SizedBox(width: 8),
                        _MiniFloorStat(label: 'Stations', value: nodeCount.toString()),
                        const SizedBox(width: 8),
                        const _MiniFloorStat(label: 'OEE', value: 'N/A'),
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

class _MiniFloorStat extends StatelessWidget {
  const _MiniFloorStat({required this.label, required this.value});

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

class _FloorCardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.36)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final routePaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final route = Path()
      ..moveTo(size.width * 0.10, size.height * 0.48)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.35,
        size.width * 0.50,
        size.height * 0.52,
      )
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.70,
        size.width * 0.90,
        size.height * 0.45,
      );
    canvas.drawPath(route, routePaint);

    final blockPaint = Paint()..color = const Color(0xFFF1F5F9);
    final borderPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final blocks = [
      Rect.fromLTWH(size.width * 0.14, size.height * 0.18, 80, 38),
      Rect.fromLTWH(size.width * 0.44, size.height * 0.28, 88, 42),
      Rect.fromLTWH(size.width * 0.66, size.height * 0.56, 96, 40),
    ];
    for (final block in blocks) {
      final rrect = RRect.fromRectAndRadius(block, const Radius.circular(10));
      canvas.drawRRect(rrect, blockPaint);
      canvas.drawRRect(rrect, borderPaint);
    }

    final nodePaint = Paint()..color = const Color(0xFF3B82F6);
    for (final point in [
      Offset(size.width * 0.10, size.height * 0.48),
      Offset(size.width * 0.50, size.height * 0.52),
      Offset(size.width * 0.90, size.height * 0.45),
    ]) {
      canvas.drawCircle(point, 4, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FloorCardPainter oldDelegate) => false;
}

class _ShopFloorDirectoryShell extends StatelessWidget {
  const _ShopFloorDirectoryShell({
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

class _ShopFloorEmptyState extends StatelessWidget {
  const _ShopFloorEmptyState({
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
              Icons.grid_view_rounded,
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

class _ShopFloorGateMessage extends StatelessWidget {
  const _ShopFloorGateMessage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.domain_rounded, size: 34, color: Color(0xFF3B82F6)),
            SizedBox(height: 12),
            Text(
              'Select a factory',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Choose a factory first. Its shop floors will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopFloorLoading extends StatelessWidget {
  const _ShopFloorLoading({required this.label});

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
              color: Color(0xFF6A7572),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
