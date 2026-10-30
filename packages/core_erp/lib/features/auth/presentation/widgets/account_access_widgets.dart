import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';

/// One action in an Account & Access "Manage" card: an icon, what it does,
/// and a chevron. Without an [onTap] it is drawn faded and does nothing; with
/// a [disabledReason] it also says why on hover — never left out.
///
/// Shared by a person's account (People) and your own (the profile), so the
/// two read as one panel.
class AccountActionRow extends StatelessWidget {
  const AccountActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.disabledReason,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = danger ? const Color(0xFFD64545) : SoftErpTheme.textPrimary;
    final row = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: danger ? color : SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: SoftErpTheme.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
    final reason = disabledReason;
    if (enabled || reason == null) return row;
    return Tooltip(message: reason, child: row);
  }
}

/// A small fact about an account under its name: "PIN 1703", "Desktop Access".
class AccountMetaChip extends StatelessWidget {
  const AccountMetaChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5FA),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: SoftErpTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
