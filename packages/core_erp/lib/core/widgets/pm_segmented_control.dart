import 'dart:math' as math;
import 'package:flutter/material.dart';

class PMFigmaSegmentedControl extends StatelessWidget {
  const PMFigmaSegmentedControl({
    super.key,
    required this.value,
    required this.onChanged,
    required this.segments,
    this.variant = PMFigmaSegmentedControlVariant.gradient,
    this.segmentWidth = 108,
    this.segmentHeight = 42,
    this.shellPadding = 4,
    this.labelFontSize = 16,
    this.semanticLabel,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final List<PMFigmaSegmentOption> segments;
  final PMFigmaSegmentedControlVariant variant;
  final double segmentWidth;
  final double segmentHeight;
  final double shellPadding;
  final double labelFontSize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    const gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF5E5BF9), Color(0xFF413F9C)],
      stops: [0, 1],
    );
    final usesGradient = variant == PMFigmaSegmentedControlVariant.gradient;
    final effectiveSegments = segments.isEmpty
        ? const <PMFigmaSegmentOption>[
            PMFigmaSegmentOption(key: 'group', label: 'Groups'),
            PMFigmaSegmentOption(key: 'item', label: 'Items'),
          ]
        : segments;
    final selectedIndex = math.max(
      0,
      effectiveSegments.indexWhere((segment) => segment.key == value),
    );

    return Semantics(
      container: true,
      label: semanticLabel ?? 'Segmented control',
      child: Container(
        width: (segmentWidth * effectiveSegments.length) + (shellPadding * 2),
        height: segmentHeight + (shellPadding * 2),
        padding: EdgeInsets.all(shellPadding),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Stack(
          children: [
            AnimatedPositionedDirectional(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubicEmphasized,
              start: selectedIndex * segmentWidth,
              top: 0,
              child: Container(
                width: segmentWidth,
                height: segmentHeight,
                decoration: BoxDecoration(
                  color: usesGradient ? null : Colors.white,
                  gradient: usesGradient ? gradient : null,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x24000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: effectiveSegments
                  .map(
                    (segment) => _PMFigmaSegmentChip(
                      width: segmentWidth,
                      height: segmentHeight,
                      label: segment.label,
                      count: segment.count,
                      isSelected: value == segment.key,
                      onTap: () => onChanged(segment.key),
                      variant: variant,
                      labelFontSize: labelFontSize,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class PMFigmaSegmentOption {
  const PMFigmaSegmentOption({
    required this.key,
    required this.label,
    this.count,
  });

  final String key;
  final String label;
  final int? count;
}

class _PMFigmaSegmentChip extends StatelessWidget {
  const _PMFigmaSegmentChip({
    required this.width,
    required this.height,
    required this.label,
    this.count,
    required this.isSelected,
    required this.onTap,
    required this.variant,
    required this.labelFontSize,
  });

  final double width;
  final double height;
  final String label;
  final int? count;
  final bool isSelected;
  final VoidCallback onTap;
  final PMFigmaSegmentedControlVariant variant;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    final usesGradient = variant == PMFigmaSegmentedControlVariant.gradient;
    final activeTextColor = usesGradient
        ? Colors.white
        : const Color(0xFF1100FF);
    final inactiveTextColor = const Color(0xFF1C2632);
    final hasCount = count != null;
    final countBackground = isSelected
        ? (usesGradient ? const Color(0x24FFFFFF) : const Color(0xFFE8E7FF))
        : const Color(0xFFF0F2F8);
    final countForeground = isSelected ? activeTextColor : inactiveTextColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: isSelected ? activeTextColor : inactiveTextColor,
                  fontSize: labelFontSize,
                  height: 1,
                  letterSpacing: 0,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label),
                      if (hasCount) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: countBackground,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: countForeground,
                              fontSize: math.max(10, labelFontSize - 2),
                              fontWeight: FontWeight.w600,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum PMFigmaSegmentedControlVariant { gradient, soft }
