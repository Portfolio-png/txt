import 'package:flutter/material.dart';

import '../../../production/screens/pipelines_screen.dart';
import '../../../production/screens/factories_screen.dart';
import '../../../production/screens/shop_floors_screen.dart';
import '../../../production/screens/floor_view_screen.dart';

class ProductionPipelinesScreen extends StatelessWidget {
  const ProductionPipelinesScreen({super.key, this.embeddedInShell = false});

  final bool embeddedInShell;

  @override
  Widget build(BuildContext context) {
    return _ProductionWorkspace(embeddedInShell: embeddedInShell);
  }
}

class _ProductionWorkspace extends StatefulWidget {
  const _ProductionWorkspace({required this.embeddedInShell});

  final bool embeddedInShell;

  @override
  State<_ProductionWorkspace> createState() => _ProductionWorkspaceState();
}

class _ProductionWorkspaceState extends State<_ProductionWorkspace>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedFactoryId;
  String? _selectedShopFloorId;
  int _selectedIndex = 0;
  int _floorMapReloadToken = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_syncSelectedIndex);
  }

  @override
  void dispose() {
    _tabController.removeListener(_syncSelectedIndex);
    _tabController.dispose();
    super.dispose();
  }

  void _syncSelectedIndex() {
    if (_selectedIndex == _tabController.index) {
      return;
    }
    setState(() {
      _selectedIndex = _tabController.index;
      if (_tabController.index == 2) {
        _floorMapReloadToken += 1;
      }
    });
  }

  void _onFactorySelected(String id) {
    setState(() {
      _selectedFactoryId = id;
      _selectedShopFloorId = null;
    });
    _tabController.animateTo(1); // Switch to Shop Floors tab
  }

  void _onShopFloorSelected(String id) {
    setState(() {
      _selectedShopFloorId = id;
    });
    _tabController.animateTo(2); // Switch to Floor Map tab
  }

  void _openPipelines() {
    if (_selectedShopFloorId == null) {
      return;
    }
    _tabController.animateTo(3);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final showOverlay = widget.embeddedInShell && !isMobile;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEEF1F2), Color(0xFFE7ECE9), Color(0xFFF3F4EF)],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(showOverlay ? 80 : 24, 16, 24, 0),
            child: Column(
              children: [
                _ProductionCommandDeck(
                  selectedIndex: _selectedIndex,
                  hasFactory: _selectedFactoryId != null,
                  hasShopFloor: _selectedShopFloorId != null,
                  onOpenFloorMap: _selectedShopFloorId == null
                      ? null
                      : () => _tabController.animateTo(2),
                  onOpenPipelines: _selectedShopFloorId == null
                      ? null
                      : () => _tabController.animateTo(3),
                ),
                const SizedBox(height: 10),
                _ProductionWayfinder(
                  selectedIndex: _selectedIndex,
                  selectedFactoryId: _selectedFactoryId,
                  selectedShopFloorId: _selectedShopFloorId,
                  onStepSelected: (index) {
                    if (index == 1 && _selectedFactoryId == null) {
                      _tabController.animateTo(0);
                      return;
                    }
                    if (index >= 2 && _selectedShopFloorId == null) {
                      _tabController.animateTo(
                        _selectedFactoryId == null ? 0 : 1,
                      );
                      return;
                    }
                    _tabController.animateTo(index);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                FactoriesScreen(onFactorySelected: _onFactorySelected),
                ShopFloorsScreen(
                  factoryId: _selectedFactoryId,
                  onShopFloorSelected: _onShopFloorSelected,
                ),
                _selectedShopFloorId == null
                    ? const _ProductionGateMessage(
                        title: 'Select a shop floor',
                        message:
                            'Choose a factory and shop floor to open the floor operations map.',
                      )
                    : FloorViewScreen(
                        shopFloorId: _selectedShopFloorId,
                        reloadToken: _floorMapReloadToken,
                        onOpenPipeline: (_) => _openPipelines(),
                      ),
                _selectedShopFloorId == null
                    ? const _ProductionGateMessage(
                        title: 'Select a shop floor',
                        message:
                            'Choose a shop floor before creating or running pipelines.',
                      )
                    : PipelinesScreen(shopFloorId: _selectedShopFloorId!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductionCommandDeck extends StatelessWidget {
  const _ProductionCommandDeck({
    required this.selectedIndex,
    required this.hasFactory,
    required this.hasShopFloor,
    this.onOpenFloorMap,
    this.onOpenPipelines,
  });

  final int selectedIndex;
  final bool hasFactory;
  final bool hasShopFloor;
  final VoidCallback? onOpenFloorMap;
  final VoidCallback? onOpenPipelines;

  @override
  Widget build(BuildContext context) {
    final briefing = _briefingForStep(selectedIndex);
    final contextText = hasShopFloor
        ? 'Factory and shop floor locked. Live map and route control are ready.'
        : hasFactory
        ? 'Factory selected. Choose a shop floor to unlock the live map.'
        : 'Start by selecting a factory. The production workspace will open level by level.';

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 128,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          border: Border.all(color: const Color(0xFFD9DEDA)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _CommandDeckPainter())),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 980;
                  return Row(
                    children: [
                      Expanded(
                        flex: compact ? 7 : 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF263130),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.precision_manufacturing_rounded,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'PRODUCTION COMMAND',
                                      style: TextStyle(
                                        color: Color(0xFF6A7572),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      child: Text(
                                        briefing.title,
                                        key: ValueKey(briefing.title),
                                        style: const TextStyle(
                                          color: Color(0xFF263130),
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              briefing.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF263130),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              contextText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF6A7572),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      if (!compact) ...[
                        const _CommandMetricCard(
                          label: 'Shift Health',
                          value: '82.4%',
                          tone: _MetricTone.good,
                          caption: 'OEE live target',
                        ),
                        const SizedBox(width: 10),
                        const _CommandMetricCard(
                          label: 'Bottleneck',
                          value: 'Press Brake',
                          tone: _MetricTone.warning,
                          caption: 'Queue +18m',
                        ),
                        const SizedBox(width: 10),
                      ],
                      _CommandActionPanel(
                        hasShopFloor: hasShopFloor,
                        onOpenFloorMap: onOpenFloorMap,
                        onOpenPipelines: onOpenPipelines,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  _ProductionBriefing _briefingForStep(int index) {
    return switch (index) {
      0 => const _ProductionBriefing(
        title: 'Factory selection',
        message: 'Pick the plant that owns today’s production run.',
      ),
      1 => const _ProductionBriefing(
        title: 'Shop-floor selection',
        message: 'Choose the physical floor before opening spatial operations.',
      ),
      2 => const _ProductionBriefing(
        title: 'Live floor map',
        message: 'Read routes, bottlenecks, and floor utilization spatially.',
      ),
      _ => const _ProductionBriefing(
        title: 'Pipeline control',
        message: 'Build route templates and start production runs from here.',
      ),
    };
  }
}

class _ProductionBriefing {
  const _ProductionBriefing({required this.title, required this.message});

  final String title;
  final String message;
}

enum _MetricTone { good, warning }

class _CommandMetricCard extends StatelessWidget {
  const _CommandMetricCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.tone,
  });

  final String label;
  final String value;
  final String caption;
  final _MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == _MetricTone.good
        ? const Color(0xFF2F8069)
        : const Color(0xFFB7791F);
    return Container(
      width: 138,
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAF7).withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9DEDA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6A7572),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6A7572),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandActionPanel extends StatelessWidget {
  const _CommandActionPanel({
    required this.hasShopFloor,
    this.onOpenFloorMap,
    this.onOpenPipelines,
  });

  final bool hasShopFloor;
  final VoidCallback? onOpenFloorMap;
  final VoidCallback? onOpenPipelines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 184,
      height: 88,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF263130),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Expanded(
            child: _CommandActionButton(
              icon: Icons.map_outlined,
              label: 'Open floor map',
              enabled: hasShopFloor,
              onTap: onOpenFloorMap,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _CommandActionButton(
              icon: Icons.account_tree_rounded,
              label: 'Pipeline control',
              enabled: hasShopFloor,
              onTap: onOpenPipelines,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandActionButton extends StatelessWidget {
  const _CommandActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled ? Colors.white : Colors.white38,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandDeckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFDADDD6).withValues(alpha: 0.36)
      ..strokeWidth = 1;
    for (var x = -20.0; x < size.width; x += 34) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = -20.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final routePaint = Paint()
      ..color = const Color(0xFF73A7A0).withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.42, size.height * 0.82)
      ..cubicTo(
        size.width * 0.52,
        size.height * 0.20,
        size.width * 0.70,
        size.height * 0.92,
        size.width * 0.86,
        size.height * 0.36,
      )
      ..quadraticBezierTo(
        size.width * 0.94,
        size.height * 0.10,
        size.width * 1.04,
        size.height * 0.26,
      );
    canvas.drawPath(path, routePaint);

    final blockPaint = Paint()
      ..color = const Color(0xFFE8EBE5).withValues(alpha: 0.56);
    for (final rect in [
      Rect.fromLTWH(size.width * 0.56, 18, 86, 34),
      Rect.fromLTWH(size.width * 0.68, 74, 112, 38),
      Rect.fromLTWH(size.width * 0.82, 24, 92, 32),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        blockPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CommandDeckPainter oldDelegate) => false;
}

class _ProductionWayfinder extends StatelessWidget {
  const _ProductionWayfinder({
    required this.selectedIndex,
    required this.selectedFactoryId,
    required this.selectedShopFloorId,
    required this.onStepSelected,
  });

  final int selectedIndex;
  final String? selectedFactoryId;
  final String? selectedShopFloorId;
  final ValueChanged<int> onStepSelected;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _ProductionStep(
        icon: Icons.domain_rounded,
        label: 'Factories',
        caption: 'Level 1',
        enabled: true,
      ),
      _ProductionStep(
        icon: Icons.grid_view_rounded,
        label: 'Shop Floors',
        caption: 'Select zone',
        enabled: selectedFactoryId != null,
      ),
      _ProductionStep(
        icon: Icons.map_outlined,
        label: 'Floor Map',
        caption: 'Operations view',
        enabled: selectedShopFloorId != null,
      ),
      _ProductionStep(
        icon: Icons.account_tree_rounded,
        label: 'Pipelines',
        caption: 'Build / run',
        enabled: selectedShopFloorId != null,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD9DEDA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var index = 0; index < steps.length; index += 1) ...[
            Expanded(
              child: _ProductionStepButton(
                step: steps[index],
                selected: selectedIndex == index,
                onTap: () => onStepSelected(index),
              ),
            ),
            if (index != steps.length - 1)
              Container(width: 18, height: 1, color: const Color(0xFFD9DEDA)),
          ],
        ],
      ),
    );
  }
}

class _ProductionStep {
  const _ProductionStep({
    required this.icon,
    required this.label,
    required this.caption,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final String caption;
  final bool enabled;
}

class _ProductionStepButton extends StatelessWidget {
  const _ProductionStepButton({
    required this.step,
    required this.selected,
    required this.onTap,
  });

  final _ProductionStep step;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = step.enabled
        ? selected
              ? const Color(0xFF256D66)
              : const Color(0xFF263130)
        : const Color(0xFF94A09C);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: step.enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE7F0EE)
                : Colors.white.withValues(alpha: 0.0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFF9BBDB8) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(step.icon, size: 20, color: foreground),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.caption,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.64),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
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

class _ProductionGateMessage extends StatelessWidget {
  const _ProductionGateMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD9DEDA)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 34, color: Color(0xFF256D66)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF263130),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6A7572),
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
