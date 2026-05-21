import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../production/providers/production_provider.dart';
import '../../../production/providers/production_run_provider.dart';
import '../../../production/screens/pipeline_builder_screen.dart';
import '../../../production/screens/shop_floor_kiosk_screen.dart';

class ProductionPipelinesScreen extends StatelessWidget {
  const ProductionPipelinesScreen({super.key, this.embeddedInShell = false});

  final bool embeddedInShell;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProductionProvider.seeded()),
        ChangeNotifierProvider(create: (_) => ProductionRunProvider()),
      ],
      child: _ProductionWorkspace(embeddedInShell: embeddedInShell),
    );
  }
}

class _ProductionWorkspace extends StatefulWidget {
  const _ProductionWorkspace({required this.embeddedInShell});

  final bool embeddedInShell;

  @override
  State<_ProductionWorkspace> createState() => _ProductionWorkspaceState();
}

class _ProductionWorkspaceState extends State<_ProductionWorkspace> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final showOverlay = widget.embeddedInShell && !isMobile;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(showOverlay ? 80 : 24, 18, 24, 0),
          child: _ProductionModeBar(
            selectedIndex: _selectedIndex,
            onChanged: (index) => setState(() => _selectedIndex = index),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            children: const [PipelineBuilderScreen(), ShopFloorKioskScreen()],
          ),
        ),
      ],
    );
  }
}

class _ProductionModeBar extends StatelessWidget {
  const _ProductionModeBar({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _ModeTab(
              icon: Icons.account_tree_outlined,
              label: 'Pipeline Builder',
              selected: selectedIndex == 0,
              onTap: () => onChanged(0),
            ),
            _ModeTab(
              icon: Icons.precision_manufacturing_outlined,
              label: 'Shop Floor Kiosk',
              selected: selectedIndex == 1,
              onTap: () => onChanged(1),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 12),
              child: Text(
                'PRODUCTION CONTROL',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFA1A1AA),
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        color: selected ? const Color(0xFF09090B) : Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : const Color(0xFF71717A),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF3F3F46),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
