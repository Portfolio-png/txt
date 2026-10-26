import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/utils/stamp_format.dart';
import '../../domain/developed_for.dart';

/// What was made on a part's development job, as a badge that explains itself.
///
/// A part's quotation is what was quoted for **making its dies**; its cost is
/// what that die making cost us. Those two numbers are the whole input — there
/// is deliberately no material rate, no batch weight and no tooling-count
/// arithmetic here, because raw material for a production run is a different
/// figure against a different quantity, and mixing the two gives a margin that
/// compares a per-job price with a per-batch cost.
///
/// **A missing cost is not a cost of zero.** That distinction is the reason
/// this widget exists rather than a `toStringAsFixed` in a build method: zero
/// cost reads as a 100% margin, so a catalogue nobody has costed would show
/// every part as pure profit. When either half is absent the badge says it is
/// not costed and shows no number at all.
///
/// It also claims no provenance. An earlier version of this badge labelled its
/// lines `Cell #25 · Quotation` and `Cells #6, #7`, pointing at spreadsheet
/// cells for figures that came from hardcoded constants. A wrong number is bad;
/// a wrong number wearing a citation is worse.
class MarginHealthBadge extends StatefulWidget {
  const MarginHealthBadge({
    super.key,
    required this.quotation,
    required this.cost,
  });

  /// Rupees quoted for the development job. Null means never quoted.
  final double? quotation;

  /// Rupees that job cost. Null means never costed.
  final double? cost;

  /// Reads both halves off a part's Developed For block.
  factory MarginHealthBadge.from(DevelopedFor developedFor, {Key? key}) {
    return MarginHealthBadge(
      key: key,
      quotation: developedFor.quotationAmount,
      cost: developedFor.costAmount,
    );
  }

  @override
  State<MarginHealthBadge> createState() => _MarginHealthBadgeState();
}

class _MarginHealthBadgeState extends State<MarginHealthBadge> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final LayerLink _link = LayerLink();

  bool get _known =>
      widget.quotation != null && widget.cost != null && widget.quotation! > 0;

  double get _net => widget.quotation! - widget.cost!;
  double get _percent => (_net / widget.quotation!) * 100;

  /// Three bands, as the badge this replaces had them.
  Color get _tone {
    if (!_known) return SoftErpTheme.textSecondary;
    if (_percent >= 20) return const Color(0xFF15803D);
    if (_percent >= 10) return const Color(0xFFB45309);
    return const Color(0xFFB91C1C);
  }

  Color get _fill {
    if (!_known) return SoftErpTheme.sectionSurface;
    if (_percent >= 20) return const Color(0xFFDCFCE7);
    if (_percent >= 10) return const Color(0xFFFEF3C7);
    return const Color(0xFFFEE2E2);
  }

  String get _label {
    if (!_known) return 'Not costed';
    final sign = _percent >= 0 ? '+' : '';
    return '$sign${_percent.toStringAsFixed(1)}% margin';
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) => _buildPopover(context),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey<String>('margin_health_indicator'),
            onTap: () => _overlay.toggle(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: _fill,
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                border: Border.all(color: _tone.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _known ? Icons.trending_up_rounded : Icons.help_outline_rounded,
                    size: 16,
                    color: _tone,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _tone,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopover(BuildContext context) {
    return Stack(
      children: [
        // Tapping away closes it, the way the badge itself toggles it.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _overlay.hide,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
                border: Border.all(color: SoftErpTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: _known ? _knownLines() : _unknownLines(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _knownLines() => [
        const Text(
          'Development margin',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'What was quoted for making this part’s dies, against what that '
          'cost.',
          style: TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        _line('Quoted', rupeeStamp(widget.quotation!)),
        _line('Cost', rupeeStamp(widget.cost!)),
        const Divider(height: 18),
        _line(
          _net >= 0 ? 'Made' : 'Lost',
          rupeeStamp(_net.abs()),
          tone: _tone,
          bold: true,
        ),
      ];

  List<Widget> _unknownLines() => [
        const Text(
          'Not costed',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.quotation == null
              ? 'No quotation recorded for this part’s development, so '
                  'there is nothing to measure against.'
              : widget.quotation! <= 0
                  ? 'The quotation is zero, so a percentage would divide by '
                      'nothing.'
                  : 'A quotation of ${rupeeStamp(widget.quotation!)} is '
                      'recorded, but what the die making cost has not been '
                      'entered. An unknown cost is not a cost of nothing.',
          style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
        ),
      ];

  Widget _line(String label, String value, {Color? tone, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: tone ?? SoftErpTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: tone ?? SoftErpTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
