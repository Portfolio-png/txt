import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';

class BentoCard extends StatelessWidget {
  const BentoCard({
    super.key,
    required this.title,
    required this.child,
    required this.summary,
    required this.isFocused,
    required this.isContext,
    required this.onTap,
    this.headerActions,
  });

  final String title;
  final Widget child;
  final Widget summary;
  final bool isFocused;
  final bool isContext;
  final VoidCallback onTap;
  final Widget? headerActions;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      padding: EdgeInsets.all(isContext ? 12 : 18),
      decoration: BoxDecoration(
        color: isFocused ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isFocused ? SoftErpTheme.accent : const Color(0xFFE2E8F0),
          width: isFocused ? 2 : 1,
        ),
        boxShadow: isFocused ? const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isFocused ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: isContext ? 12 : 16,
                        fontWeight: FontWeight.w700,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (headerActions != null) headerActions!,
                  if (isContext)
                    const Icon(Icons.open_in_full, size: 14, color: SoftErpTheme.textSecondary),
                ],
              ),
              SizedBox(height: isContext ? 8 : 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    // Add some bottom padding so it doesn't cut off abruptly
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: (isFocused || !isContext) ? child : summary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
