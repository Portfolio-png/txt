import 'package:flutter/material.dart';

import '../../../production/domain/default_floor_context.dart';
import '../../../production/screens/pipelines_screen.dart';

class ProductionPipelinesScreen extends StatelessWidget {
  const ProductionPipelinesScreen({super.key, this.embeddedInShell = false});

  final bool embeddedInShell;

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFFEFF3F1)),
      child: PipelinesScreen(
        factoryId: defaultProductionFactoryId,
        shopFloorId: defaultProductionShopFloorId,
      ),
    );
  }
}
