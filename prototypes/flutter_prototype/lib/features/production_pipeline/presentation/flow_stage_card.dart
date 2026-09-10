import 'package:flutter/material.dart';
import '../../../app/shell/prototype_theme.dart';
import '../domain/carry_forward.dart';
import '../domain/process_node.dart';

class FlowStageCard extends StatelessWidget {
  final ProcessNode node;
  final Carry? carry;
  final bool isSelected;
  final bool isConnecting;
  final String status;
  final bool showAllocations;
  final VoidCallback onTap;

  const FlowStageCard({
    super.key,
    required this.node,
    this.carry,
    this.isSelected = false,
    this.isConnecting = false,
    this.status = 'pending',
    this.showAllocations = false,
    required this.onTap,
  });

  static const double cardWidth = 224;
  static const double cardHeight = 112;

  @override
  Widget build(BuildContext context) {
    final cat = getProcessCategory(node);
    final machine = node.firstOf(AllocKind.machine);
    final materialIn = node.firstOf(AllocKind.material);
    final itemOut = node.firstOf(AllocKind.item);

    Color borderColor = AppColors.border;
    if (isSelected) {
      borderColor = AppColors.accent;
    } else if (isConnecting) {
      borderColor = AppColors.warning;
    }

    final isDone = status == 'done';
    final isActive = status == 'active';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.18),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isDone
                      ? AppColors.success
                      : (isActive ? AppColors.accent : Colors.transparent),
                  width: (isDone || isActive) ? 4.0 : 0.0,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Header Strip
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cat.badgeBg,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: cat.borderColor),
                      ),
                      child: Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: cat.badgeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Stage ${node.stageIndex + 1}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone
                                ? AppColors.success
                                : (isActive ? AppColors.accent : AppColors.borderStrong),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: AppColors.accent.withValues(alpha: 0.4),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    )
                                  ]
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Card Title & Workstation
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      node.name.isNotEmpty ? node.name : node.processType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.settings_outlined, size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            machine != null && machine.isNotEmpty ? machine : 'Unassigned Workstation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Flow / Yield Metric Strip
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: node.sheetPlan != null
                      ? Row(
                          children: [
                            const Text('⚡', style: TextStyle(fontSize: 10)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                node.sheetPlan!.bands.isNotEmpty
                                    ? (node.sheetPlan!.subCuts.isNotEmpty
                                        ? '72 Blanks / Sheet'
                                        : '8 Strips / Sheet')
                                    : 'Custom Cutting Plan',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF4338CA),
                                ),
                              ),
                            ),
                            if (carry != null && carry!.yieldPct > 0)
                              Text(
                                '${carry!.yieldPct.toStringAsFixed(0)}% yield',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF4338CA),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text(
                                materialIn ?? 'Feed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.arrow_forward_rounded, size: 10, color: AppColors.textMuted),
                            ),
                            Expanded(
                              child: Text(
                                itemOut ?? 'Yield',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
