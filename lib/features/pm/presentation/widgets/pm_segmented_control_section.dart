import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';

enum PMFigmaSegmentedControlVariant { gradient, soft }

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
    final Color foreground;
    if (isSelected) {
      foreground = usesGradient ? Colors.white : const Color(0xFF4C49ED);
    } else {
      foreground = const Color(0xFF6B7280);
    }

    final textStyle = TextStyle(
      color: foreground,
      fontSize: labelFontSize,
      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      letterSpacing: -0.2,
    );

    return Semantics(
      button: true,
      selected: isSelected,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: width,
            height: height,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: textStyle),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (usesGradient
                              ? Colors.white.withValues(alpha: 0.18)
                              : const Color(0xFFEEEDFF))
                          : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count!.toString(),
                      style: textStyle.copyWith(
                        fontSize: labelFontSize - 3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FigmaSegmentSection extends StatelessWidget {
  const FigmaSegmentSection({
    super.key,
    required this.selectedValue,
    required this.onChanged,
  });

  final String selectedValue;
  final ValueChanged<String> onChanged;

  static const List<PMFigmaSegmentOption> _options = [
    PMFigmaSegmentOption(key: 'group', label: 'Groups'),
    PMFigmaSegmentOption(key: 'item', label: 'Items'),
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Figma custom button',
            subtitle:
                'Translated from node 15289:6503 in Funnel Reborn and added to PM as a reusable segmented control.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 720;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Live preview',
                            style: Theme.of(
                              context,
                            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This keeps the compact pill shape, active gradient fill, and tight label tracking from the design.',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PMFigmaSegmentedControl(
                              value: selectedValue,
                              onChanged: onChanged,
                              segments: _options,
                              variant: PMFigmaSegmentedControlVariant.gradient,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: isNarrow ? 0 : 20, height: isNarrow ? 20 : 0),
                  const Expanded(child: _FigmaSpecPanel()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class FigmaSoftSegmentSection extends StatelessWidget {
  const FigmaSoftSegmentSection({
    super.key,
    required this.selectedValue,
    required this.onChanged,
  });

  final String selectedValue;
  final ValueChanged<String> onChanged;

  static const List<PMFigmaSegmentOption> _options = [
    PMFigmaSegmentOption(key: 'group', label: 'Groups'),
    PMFigmaSegmentOption(key: 'item', label: 'Items'),
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Figma custom button alt',
            subtitle:
                'Translated from node 15289:6480 in Funnel Reborn as the softer selected state with a white chip and blue active text.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 720;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alternate state preview',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This version keeps the same shell but swaps the selected chip to a white surface with a shadow and bright blue label.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PMFigmaSegmentedControl(
                              value: selectedValue,
                              onChanged: onChanged,
                              segments: _options,
                              variant: PMFigmaSegmentedControlVariant.soft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: isNarrow ? 0 : 20, height: isNarrow ? 20 : 0),
                  const Expanded(child: _FigmaSoftSpecPanel()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FigmaSpecPanel extends StatelessWidget {
  const _FigmaSpecPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mapped details',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          const _SpecRow(
            label: 'Container',
            value: '20px radius, 2px outer padding',
          ),
          const _SpecRow(
            label: 'Active state',
            value: 'Vertical violet gradient + subtle drop shadow',
          ),
          const _SpecRow(
            label: 'Typography',
            value: '12px label size with compact line-height and tracking',
          ),
          const _SpecRow(
            label: 'Options',
            value: 'Group and Item, with reusable toggle behavior',
          ),
        ],
      ),
    );
  }
}

class _FigmaSoftSpecPanel extends StatelessWidget {
  const _FigmaSoftSpecPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mapped details',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          const _SpecRow(
            label: 'Container',
            value: 'Same light shell, same 2px padding, same chip spacing',
          ),
          const _SpecRow(
            label: 'Active state',
            value: 'White selected chip, subtle shadow, blue active label',
          ),
          const _SpecRow(
            label: 'Typography',
            value: '12px text, semibold when active and medium when idle',
          ),
          const _SpecRow(
            label: 'Reuse',
            value:
                'Implemented as a second visual variant of the same reusable segmented control',
          ),
        ],
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF93C5FD),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFE5E7EB),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
