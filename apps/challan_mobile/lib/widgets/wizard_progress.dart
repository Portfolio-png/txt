import 'package:flutter/material.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';

/// Step rail for a multi-step flow: ●———●———○———○———○
///
/// Completed steps show a tick, the current step a filled ring, and the rest
/// stay hollow. When [onStepTapped] is given, each node whose index passes
/// [canTap] becomes a shortcut to jump straight to that step.
class WizardProgress extends StatelessWidget {
  const WizardProgress({
    super.key,
    required this.labels,
    required this.currentIndex,
    this.onStepTapped,
    this.canTap,
  });

  final List<String> labels;
  final int currentIndex;

  /// Called with the tapped step index. Null makes the rail display-only.
  final ValueChanged<int>? onStepTapped;

  /// Whether a given step index may be jumped to. Defaults to "any step".
  final bool Function(int index)? canTap;

  @override
  Widget build(BuildContext context) {
    bool tappable(int i) =>
        onStepTapped != null && i != currentIndex && (canTap?.call(i) ?? true);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Padding(
                  // Aligns the connector with the centre of the 28px nodes
                  // rather than the label text below them.
                  padding: const EdgeInsets.only(top: 13),
                  child: Container(
                    height: 2,
                    color: i <= currentIndex
                        ? SoftErpTheme.accent
                        : const Color(0xFFE1E5EE),
                  ),
                ),
              ),
            _Node(
              label: labels[i],
              index: i,
              isDone: i < currentIndex,
              isCurrent: i == currentIndex,
              onTap: tappable(i) ? () => onStepTapped!(i) : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({
    required this.label,
    required this.index,
    required this.isDone,
    required this.isCurrent,
    this.onTap,
  });

  final String label;
  final int index;
  final bool isDone;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = isDone || isCurrent;
    final node = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? SoftErpTheme.accent : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? SoftErpTheme.accent : const Color(0xFFD7DCE8),
              width: 2,
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isCurrent ? Colors.white : const Color(0xFF9AA3B5),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
            color: active ? SoftErpTheme.accent : const Color(0xFF9AA3B5),
          ),
        ),
      ],
    );

    return SizedBox(
      width: 58,
      child: onTap == null
          ? node
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: node,
            ),
    );
  }
}
