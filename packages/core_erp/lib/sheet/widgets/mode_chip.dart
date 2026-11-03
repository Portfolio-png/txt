import 'package:flutter/material.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../column_def.dart';
import '../sheet_controller.dart';

/// Auto / Edit / OK beside a derived value (Part No, Part Code): what the
/// figure is, and the menu that changes it.
class ModeChip extends StatelessWidget {
  const ModeChip({
    super.key,
    required this.controller,
    required this.columnId,
    required this.row,
    required this.mode,
  });

  final SheetController controller;
  final int columnId;
  final int row;
  final ValueMode mode;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (mode) {
      ValueMode.auto => (
        'Auto',
        SoftErpTheme.infoBg,
        SoftErpTheme.infoText,
      ),
      ValueMode.edit => (
        'Edit',
        SoftErpTheme.warningBg,
        SoftErpTheme.warningText,
      ),
      ValueMode.ok => ('OK', SoftErpTheme.successBg, SoftErpTheme.successText),
    };

    return PopupMenuButton<ValueMode>(
      tooltip: 'Value mode: $label',
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
          border: Border.all(color: fg.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: ValueMode.auto,
          child: Text('Auto (Derived proposal)'),
        ),
        const PopupMenuItem(
          value: ValueMode.edit,
          child: Text('Edit (Person entered)'),
        ),
        const PopupMenuItem(
          value: ValueMode.ok,
          child: Text('OK (Frozen confirmed)'),
        ),
      ],
      onSelected: (m) => controller.setMode(columnId, m, row: row),
    );
  }
}
