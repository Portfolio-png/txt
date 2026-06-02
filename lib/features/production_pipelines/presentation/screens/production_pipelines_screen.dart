import 'package:flutter/material.dart';

import '../../../production/domain/default_floor_context.dart';
import '../../../production/screens/pipelines_screen.dart';

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
    final pipelinesMode = switch (mode) {
      ProductionPipelinesScreenMode.production =>
        PipelinesScreenMode.production,
      ProductionPipelinesScreenMode.manage => PipelinesScreenMode.manage,
    };

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFEFF3F1)),
      child: PipelinesScreen(
        factoryId: defaultProductionFactoryId,
        shopFloorId: defaultProductionShopFloorId,
        mode: pipelinesMode,
      ),
    );
  }
}
