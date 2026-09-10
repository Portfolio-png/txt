import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../domain/item_expression.dart';

/// Shows how the `+` line was read, as code.
///
/// The grammar has to be visible or it cannot be trusted: `Bulb + Red + Brass`
/// puts Red on a property that exists and invents one for Brass, and the only
/// honest way to say that is to show which is which before anything is saved.
class ItemExpressionView extends StatelessWidget {
  const ItemExpressionView({super.key, required this.plan, this.dense = false});

  final ItemExpressionPlan plan;
  final bool dense;

  static const Color _itemColor = Color(0xFF9A6B00);
  static const Color _itemBg = Color(0xFFFFF6E0);
  static const Color _propertyColor = Color(0xFFB3246B);
  static const Color _propertyBg = Color(0xFFFDECF4);
  static const Color _plusColor = Color(0xFF6D3BD1);

  @override
  Widget build(BuildContext context) {
    if (plan.headText.isEmpty && plan.segments.length <= 1) {
      return Text(
        'Type an item name, then + a value.',
        style: TextStyle(
          fontSize: dense ? 12 : 13,
          fontStyle: FontStyle.italic,
          color: SoftErpTheme.textSecondary,
        ),
      );
    }

    final children = <Widget>[];
    for (var i = 0; i < plan.segments.length; i++) {
      final segment = plan.segments[i];
      if (i > 0) children.add(_plus());
      children.add(_chipFor(segment));
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _plus() => Text(
    ItemExpression.separator,
    style: TextStyle(
      fontFamily: 'monospace',
      fontSize: dense ? 13 : 15,
      fontWeight: FontWeight.w800,
      color: _plusColor,
    ),
  );

  Widget _chipFor(ItemExpressionSegment segment) {
    switch (segment.kind) {
      case SegmentKind.item:
        return _CodeChip(
          dense: dense,
          foreground: _itemColor,
          background: _itemBg,
          head: plan.createsItem ? 'new item' : 'item',
          body: segment.value.isEmpty ? '?' : segment.value,
        );
      case SegmentKind.pending:
        return _CodeChip(
          dense: dense,
          foreground: SoftErpTheme.textSecondary,
          background: SoftErpTheme.sectionSurface,
          head: '',
          body: '…',
          dashed: true,
        );
      case SegmentKind.existingValue:
        // Already on the property, so this writes nothing. Solid and ticked,
        // to sit apart from the two chips that do create something.
        return _CodeChip(
          dense: dense,
          foreground: _propertyColor,
          background: _propertyBg,
          head: segment.propertyName,
          body: segment.value,
          typeMark: segment.inputType,
          isExisting: true,
        );
      case SegmentKind.boundValue:
        return _CodeChip(
          dense: dense,
          foreground: _propertyColor,
          background: _propertyBg,
          head: segment.propertyName,
          body: segment.value,
          typeMark: segment.inputType,
          dashed: true,
          isNew: true,
        );
      case SegmentKind.newProperty:
      case SegmentKind.typeOnly:
        return _CodeChip(
          dense: dense,
          foreground: _propertyColor,
          background: _propertyBg,
          head: segment.propertyName,
          body: segment.value.isEmpty ? '—' : segment.value,
          typeMark: segment.inputType,
          // The consequential case: this property does not exist yet.
          dashed: true,
          isNew: true,
        );
    }
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({
    required this.dense,
    required this.foreground,
    required this.background,
    required this.head,
    required this.body,
    this.typeMark,
    this.dashed = false,
    this.isNew = false,
    this.isExisting = false,
  });

  final bool dense;
  final Color foreground;
  final Color background;
  final String head;
  final String body;
  final String? typeMark;
  final bool dashed;
  final bool isNew;
  final bool isExisting;

  @override
  Widget build(BuildContext context) {
    final fontSize = dense ? 12.0 : 13.5;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: foreground.withValues(alpha: dashed ? 0.55 : 0.25),
          width: dashed ? 1.3 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNew) ...[
            Icon(Icons.add_circle_outline, size: fontSize, color: foreground),
            const SizedBox(width: 5),
          ] else if (isExisting) ...[
            Icon(Icons.check_circle_outline, size: fontSize, color: foreground),
            const SizedBox(width: 5),
          ],
          Text.rich(
            TextSpan(
              children: [
                if (head.isNotEmpty)
                  TextSpan(
                    text: head,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: foreground,
                    ),
                  ),
                TextSpan(
                  text: head.isEmpty ? body : '($body)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: foreground.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
            style: TextStyle(fontFamily: 'monospace', fontSize: fontSize),
          ),
          if (typeMark != null) ...[
            const SizedBox(width: 6),
            _TypeMark(inputType: typeMark!, size: fontSize),
          ],
        ],
      ),
    );
  }
}

/// The same A / 1 / G / M marker the property rows use, so the two surfaces
/// read as one language.
class _TypeMark extends StatelessWidget {
  const _TypeMark({required this.inputType, required this.size});

  final String inputType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (inputType) {
      'Numeric' => Colors.blue,
      'Gauge' => Colors.purple,
      'Material' => Colors.teal,
      _ => Colors.grey,
    };
    final label = switch (inputType) {
      'Numeric' => '1',
      'Gauge' => 'G',
      'Material' => 'M',
      _ => 'A',
    };
    return Container(
      width: size + 4,
      height: size + 4,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: size - 3,
          fontWeight: FontWeight.w800,
          color: color.shade700,
        ),
      ),
    );
  }
}
