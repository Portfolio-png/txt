import 'package:flutter/material.dart';

import '../../core/theme/soft_erp_theme.dart';

// The status bar is the sheet's one dark surface, on purpose: it reads as the
// window's chrome rather than as content. Its shades are named here because
// the theme has no dark palette to draw them from.
const Color _barFill = Color(0xFF1E293B);
const Color _barRule = Color(0xFF334155);
const Color _barDivider = Color(0xFF475569);
const Color _barText = Color(0xFFE2E8F0);
const Color _barMuted = Color(0xFF94A3B8);
const Color _barFaint = Color(0xFF64748B);
const Color _barError = Color(0xFFFCA5A5);
const Color _barErrorIcon = Color(0xFFF87171);

class SheetStatusBar extends StatelessWidget {
  const SheetStatusBar({
    super.key,
    required this.isEditing,
    required this.location,
    required this.message,
    this.isError = false,
  });

  final bool isEditing;
  final String location;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _barFill,
        border: Border(top: BorderSide(color: _barRule)),
      ),
      child: Row(
        children: [
          // Mode chip (Ready / Editing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: isEditing
                  ? SoftErpTheme.warningText
                  : SoftErpTheme.successText,
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
            ),
            child: Text(
              isEditing ? 'EDITING' : 'READY',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Cell location
          Flexible(
            child: Text(
              location,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _barMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Vertical divider
          Container(width: 1, height: 18, color: _barDivider),
          const SizedBox(width: 12),

          // Message (error or contextual hint)
          Expanded(
            child: Row(
              children: [
                if (isError) ...[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 13,
                    color: _barErrorIcon,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    message,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isError ? FontWeight.w700 : FontWeight.w500,
                      color: isError ? _barError : _barText,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Shortcuts hint on far right. Flexible because it is the least
          // important thing in the bar — it gives way before the message does.
          const Flexible(
            child: Text(
              'Enter: ➔   Alt+↓: list   Esc: restore   Ctrl+S: save',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _barFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
