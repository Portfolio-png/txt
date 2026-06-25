import 'package:flutter/material.dart';

import '../../../production/domain/default_floor_context.dart';
import '../../../production/screens/pipelines_screen.dart';
import '../../../production/screens/production_runs_screen.dart';

enum ProductionPipelinesScreenMode { production, manage }

class ProductionPipelinesScreen extends StatelessWidget {
  const ProductionPipelinesScreen({
    super.key,
    this.embeddedInShell = false,
    this.mode = ProductionPipelinesScreenMode.manage,
  });

  final bool embeddedInShell;
  final ProductionPipelinesScreenMode mode;

  @override
  Widget build(BuildContext context) {
    if (mode == ProductionPipelinesScreenMode.production) {
      // Transparent so the shell's purple gradient shows through, matching Orders.
      return const ProductionRunsScreen();
    }

    return const PipelinesScreen(
      factoryId: defaultProductionFactoryId,
      shopFloorId: defaultProductionShopFloorId,
      mode: PipelinesScreenMode.manage,
    );
  }
}
