import 'package:flutter/material.dart';

import '../pipelines_screen.dart';

class ProductionPipelinesScreen extends StatelessWidget {
  const ProductionPipelinesScreen({super.key, this.embeddedInShell = false});

  final bool embeddedInShell;

  @override
  Widget build(BuildContext context) {
    return const PipelinesScreen();
  }
}
