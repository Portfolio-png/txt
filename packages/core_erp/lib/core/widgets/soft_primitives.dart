import 'package:flutter/material.dart';

import '../theme/soft_erp_theme.dart';

class SoftSurface extends StatelessWidget {
  const SoftSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.alignment,
    this.color = SoftErpTheme.cardSurface,
    this.radius = SoftErpTheme.radiusMd,
    this.elevated = true,
    this.strongBorder = false,
    this.showBorder = true,
    this.clipContent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final Color color;
  final double radius;
  final bool elevated;
  final bool strongBorder;
  final bool showBorder;
  final bool clipContent;

  @override
  Widget build(BuildContext context) {
    final resolvedChild = clipContent
        ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child)
        : child;

    return Container(
      margin: margin,
      width: width,
      height: height,
      alignment: alignment,
      padding: padding,
      decoration: SoftErpTheme.surfaceDecoration(
        color: color,
        radius: radius,
        elevated: elevated,
        strongBorder: strongBorder,
        showBorder: showBorder,
      ),
      child: resolvedChild,
    );
  }
}

class SoftSectionCard extends StatelessWidget {
  const SoftSectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.padding = const EdgeInsets.all(16),
    this.radius = SoftErpTheme.radiusLg,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      radius: radius,
      color: SoftErpTheme.cardSurface,
      strongBorder: false,
      elevated: true,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

class SoftPill extends StatelessWidget {
  const SoftPill({
    super.key,
    required this.label,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.background = SoftErpTheme.cardSurfaceAlt,
    this.foreground = SoftErpTheme.textSecondary,
    this.borderColor = SoftErpTheme.border,
    this.onTap,
  });

  final String label;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Color background;
  final Color foreground;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 36,
    this.iconColor = SoftErpTheme.textSecondary,
    this.background = SoftErpTheme.cardSurfaceAlt,
    this.borderColor = SoftErpTheme.border,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color iconColor;
  final Color background;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
            boxShadow: SoftErpTheme.insetShadow,
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
    if (tooltip == null || tooltip!.trim().isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class SoftMetricCard extends StatefulWidget {
  const SoftMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.isActive,
    required this.onTap,
    this.subLabel,
  });

  final String label;
  final int value;
  final bool isActive;
  final VoidCallback onTap;
  final String? subLabel;

  @override
  State<SoftMetricCard> createState() => _SoftMetricCardState();
}

class _SoftMetricCardState extends State<SoftMetricCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final lift = _isPressed ? 0.0 : (_isHovered ? -2.0 : 0.0);
    const cardRadius = 22.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, lift, 0),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (pressed) => setState(() => _isPressed = pressed),
          borderRadius: BorderRadius.circular(cardRadius),
          child: SoftSurface(
            color: isActive
                ? const Color(0xFFF0EDFF)
                : (_isHovered
                      ? const Color(0xFFFDFDFF)
                      : SoftErpTheme.cardSurface),
            radius: cardRadius,
            strongBorder: isActive || _isHovered,
            elevated: true,
            clipContent: false,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SoftErpTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.subLabel != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.subLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isActive
                                ? SoftErpTheme.accentDark
                                : SoftErpTheme.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  constraints: const BoxConstraints(minWidth: 82),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFDDD5FF)
                        : SoftErpTheme.cardSurfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isActive ? SoftErpTheme.subtleShadow : null,
                  ),
                  child: Text(
                    '${widget.value}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isActive
                          ? SoftErpTheme.accentDark
                          : SoftErpTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
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

class SoftRowCard extends StatefulWidget {
  const SoftRowCard({
    super.key,
    required this.child,
    required this.onTap,
    this.isSelected = false,
    this.baseColor,
    this.hoverColor,
    this.selectedColor,
    this.baseShadow,
    this.hoverShadow,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool isSelected;
  final Color? baseColor;
  final Color? hoverColor;
  final Color? selectedColor;
  final List<BoxShadow>? baseShadow;
  final List<BoxShadow>? hoverShadow;

  @override
  State<SoftRowCard> createState() => _SoftRowCardState();
}

class _SoftRowCardState extends State<SoftRowCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final lift = _pressed ? 0.9 : (_hovered ? -1.7 : 0.0);
    final selected = widget.isSelected;
    final defaultHoverShadow = const [
      BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 7)),
    ];
    final shadow = _hovered
        ? (widget.hoverShadow ?? defaultHoverShadow)
        : (widget.baseShadow ?? SoftErpTheme.raisedShadow);
    final baseColor = widget.baseColor ?? SoftErpTheme.cardSurface;
    final hoverColor = widget.hoverColor ?? const Color(0xFFFDFDFF);
    final selectedColor = widget.selectedColor ?? const Color(0xFFF2EFFF);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, lift, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              decoration: BoxDecoration(
                color: selected
                    ? selectedColor
                    : (_hovered ? hoverColor : baseColor),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected || _hovered
                      ? SoftErpTheme.borderStrong
                      : SoftErpTheme.border,
                ),
                boxShadow: shadow,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class SoftStatusPill extends StatelessWidget {
  const SoftStatusPill({
    super.key,
    required this.label,
    this.background = SoftErpTheme.infoBg,
    this.textColor = SoftErpTheme.infoText,
    this.borderColor = SoftErpTheme.borderStrong,
  });

  final String label;
  final Color background;
  final Color textColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
