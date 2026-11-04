import 'package:flutter/material.dart';

/// KeyTip badge overlay — displayed beside buttons and field labels when Alt
/// or a modifier key is pressed/held to announce quick keyboard jump shortcuts.
class KeyTipBadge extends StatelessWidget {
  const KeyTipBadge({
    super.key,
    required this.label,
    this.visible = true,
  });

  final String label;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.5,
          fontFamily: 'monospace',
          height: 1.1,
        ),
      ),
    );
  }
}
