import 'package:flutter/material.dart';

/// Sizes a form field to what it holds, so a form of short answers reads as a
/// row of short boxes instead of a stack of page-wide empty bars.
///
/// The width is the widest of the field's label, its hint and what has been
/// typed (followed live through [controller]), plus room for the field's own
/// padding and icons, held between [minWidth] and [maxWidth]. A helper line
/// counts for half its width: it may wrap onto a second line (give the
/// decoration `helperMaxLines: 2`) rather than push the box out.
///
/// Meant for a [Wrap]: the boxes flow side by side and move to the next line
/// only when the row is full. A width larger than the space available is
/// clamped by the parent's constraints, so nothing overflows.
class FitToText extends StatefulWidget {
  const FitToText({
    super.key,
    required this.child,
    this.controller,
    this.texts = const [],
    this.helper,
    this.minWidth = 150,
    this.maxWidth = 420,
    this.chrome = 48,
  });

  final Widget child;

  /// What is typed into the field. Null for a field without one (a picker),
  /// whose current value goes in [texts] instead.
  final TextEditingController? controller;

  /// Text that must fit inside the box: the label, a hint, a picked value.
  final List<String> texts;

  final String? helper;
  final double minWidth;
  final double maxWidth;

  /// Room the field needs beyond its text — padding, a suffix icon, a border.
  final double chrome;

  @override
  State<FitToText> createState() => _FitToTextState();
}

class _FitToTextState extends State<FitToText> {
  // Label-sized, the larger of the field's two text sizes, so a label never
  // truncates when it floats back down into an empty box.
  static const TextStyle _measureStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_changed);
  }

  @override
  void didUpdateWidget(FitToText old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_changed);
      widget.controller?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  double _measure(String text, TextScaler scaler) {
    if (text.isEmpty) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _measureStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final text in [...widget.texts, widget.controller?.text ?? '']) {
      final width = _measure(text, scaler);
      if (width > widest) widest = width;
    }
    final helper = widget.helper;
    if (helper != null) {
      final half = _measure(helper, scaler) / 2;
      if (half > widest) widest = half;
    }
    final width = (widest + widget.chrome)
        .clamp(widget.minWidth, widget.maxWidth)
        .toDouble();
    return SizedBox(width: width, child: widget.child);
  }
}
