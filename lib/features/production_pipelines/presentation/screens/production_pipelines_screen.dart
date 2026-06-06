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
      return const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFFEFF3F1)),
        child: ProductionRunsScreen(),
      );
    }

    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFFEFF3F1)),
      child: PipelinesScreen(
        factoryId: defaultProductionFactoryId,
        shopFloorId: defaultProductionShopFloorId,
        mode: PipelinesScreenMode.manage,
      ),
    );
  }
}
