import 'package:flutter/material.dart';

import '../group_type_style.dart';

class GroupTypeIcons extends StatelessWidget {
  const GroupTypeIcons({
    super.key,
    required this.isCombination,
    required this.isComponent,
    required this.onTypeChanged,
  });

  final bool isCombination;
  final bool isComponent;
  final void Function(bool isCombination, bool isComponent) onTypeChanged;

  @override
  Widget build(BuildContext context) {
    Widget buildIcon({
      required bool isSelected,
      required String tooltipMessage,
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Tooltip(
        message: tooltipMessage,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
              border: Border.all(
                color: isSelected ? color.withOpacity(0.5) : const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isSelected ? color : const Color(0xFF94A3B8),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildIcon(
          isSelected: !isCombination && !isComponent,
          tooltipMessage: 'Hierarchy Group\nA standard group for organizing items.',
          icon: Icons.account_tree_outlined,
          color: GroupTypeStyle.hierarchical.folder,
          onTap: () => onTypeChanged(false, false),
        ),
        const SizedBox(width: 8),
        buildIcon(
          isSelected: isComponent,
          tooltipMessage: 'Component Group\nDefines a configurable item structure.',
          icon: Icons.extension_outlined,
          color: GroupTypeStyle.component.folder,
          onTap: () => onTypeChanged(false, true),
        ),
        const SizedBox(width: 8),
        buildIcon(
          isSelected: isCombination,
          tooltipMessage: 'Combination Group\nA group of variant sets.',
          icon: Icons.layers_outlined,
          color: GroupTypeStyle.combination.folder,
          onTap: () => onTypeChanged(true, false),
        ),
      ],
    );
  }
}
