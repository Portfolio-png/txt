import 'package:flutter/material.dart';

import '../../domain/quantity.dart';
import '../../domain/units.dart';

/// One widget: the only canonical way a physical quantity reaches the screen.
/// Per `.claude/skills/units/SKILL.md` §4, §5.
class QuantityText extends StatelessWidget {
  const QuantityText(
    this.q, {
    this.display = const QtyDisplay.auto(),
    this.style,
    super.key,
  });

  final Quantity q;
  final QtyDisplay display;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      Units.format(q, display: display),
      style: style,
    );
  }
}
