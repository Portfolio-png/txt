import 'package:flutter/material.dart';

import '../theme/soft_erp_theme.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final isPrimary = variant == AppButtonVariant.primary;
    final foregroundColor = isPrimary ? Colors.white : SoftErpTheme.textPrimary;
    final backgroundColor = isPrimary
        ? SoftErpTheme.accent
        : const Color(0xFFFDFDFF);
    final side = BorderSide(
      color: isPrimary ? SoftErpTheme.accentDark : const Color(0xFFE7E8F2),
    );

    return SizedBox(
      height: isTablet ? 52.0 : 44.0,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: isPrimary ? 1.5 : 0,
          shadowColor: const Color(0x146A74B8),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.7),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: side,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 24.0 : 18.0,
            vertical: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: isTablet ? 22.0 : 18.0,
                height: isTablet ? 22.0 : 18.0,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            else if (icon != null) ...[
              Icon(icon, size: isTablet ? 22.0 : 18.0),
              SizedBox(width: isTablet ? 10.0 : 8.0),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: isTablet ? 16.0 : 14.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum AppButtonVariant { primary, secondary }
