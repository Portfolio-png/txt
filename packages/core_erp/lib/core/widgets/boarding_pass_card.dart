import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../theme/soft_erp_theme.dart';

/// A label/value pair rendered in the boarding-pass detail strip.
class BoardingPassDetail {
  const BoardingPassDetail(this.label, this.value);
  final String label;
  final String value;
}

/// Boarding-pass / ticket style card: a large hero image, the item's headline
/// details, and an optional scannable barcode. It is fully responsive — it
/// switches between a vertical (hero on top) and a horizontal (hero on the left,
/// barcode on the right) layout, and drops the subtitle / details / barcode as
/// space tightens, so the same card reads well from a full-width 1-column hero
/// down to a dense 10-column tile.
class BoardingPassCard extends StatelessWidget {
  const BoardingPassCard({
    super.key,
    required this.title,
    this.subtitle = '',
    this.imageUrl,
    this.details = const <BoardingPassDetail>[],
    this.barcode,
    this.token = 'IT',
    this.caption = 'No image',
    this.accent = const Color(0xFFE4C17C),
    this.isScrap = false,
    this.cardColor,
    this.borderColor,
    this.badge,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final List<BoardingPassDetail> details;

  /// When null/empty, no barcode is rendered (e.g. item master). The design
  /// stays consistent — the details strip simply omits the barcode block.
  final String? barcode;
  final String token;
  final String caption;
  final Color accent;
  final bool isScrap;
  final Color? cardColor;
  final Color? borderColor;
  final Widget? badge;
  final VoidCallback? onTap;

  bool get _hasBarcode => (barcode ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final effectiveCardColor =
        cardColor ?? (isScrap ? const Color(0xFFFFFDF8) : Colors.white);
    final effectiveBorderColor =
        borderColor ??
        (isScrap ? const Color(0xFFFED7AA) : const Color(0xFFE9EBF2));

    return Material(
      color: effectiveCardColor,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: effectiveCardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: effectiveBorderColor),
            boxShadow: [
              BoxShadow(
                color: isScrap
                    ? const Color(0x12B45309)
                    : const Color(0x0F1B1F3B),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final h = c.maxHeight.isFinite ? c.maxHeight : w * 1.35;
              // Wide + short cell (e.g. 1-2 columns) -> horizontal ticket layout.
              final horizontal = w > h * 1.3 && w > 360;
              return horizontal
                  ? _horizontal(context, w, h)
                  : _vertical(context, w, h);
            },
          ),
        ),
      ),
    );
  }

  // ---- vertical layout (hero on top) ---------------------------------------
  // Overflow-safe: the hero is Expanded (absorbs all slack) and the details
  // block is intrinsic (MainAxisSize.min); rows are only added when the card is
  // tall enough for them, so the details block can never exceed the card height.
  Widget _vertical(BuildContext context, double w, double h) {
    final tiny = w < 140;
    final compact = w < 200;
    final pad = compact ? 10.0 : 13.0;
    final showSub = subtitle.isNotEmpty && h > 150;
    final showDetails = details.isNotEmpty && !tiny && h > 210;
    final showBarcode = _hasBarcode && !tiny && h > 252;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _hero(context)),
        Padding(
          padding: EdgeInsets.fromLTRB(
            pad,
            compact ? 8 : 10,
            pad,
            compact ? 9 : 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: tiny ? 12 : (compact ? 14 : 17),
                  letterSpacing: -0.3,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
              if (showSub) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12.5,
                    fontWeight: FontWeight.w600,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
              ],
              if (showDetails) ...[
                const SizedBox(height: 10),
                const _Perforation(),
                const SizedBox(height: 9),
                SizedBox(height: 34, child: _detailRow(compact ? 2 : 3)),
              ],
              if (showBarcode) ...[
                const SizedBox(height: 9),
                SizedBox(height: 30, child: _barcodeStrip(height: 30)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---- horizontal layout (hero left, barcode right) ------------------------
  Widget _horizontal(BuildContext context, double w, double h) {
    final showBarcode = _hasBarcode && w > 520;
    final showSub = subtitle.isNotEmpty && h > 120;
    final showDetails = details.isNotEmpty && h > 188;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: (w * 0.4).clamp(160.0, 360.0), child: _hero(context)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 23,
                    letterSpacing: -0.4,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                if (showSub) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                ],
                if (showDetails) ...[
                  const SizedBox(height: 14),
                  const _Perforation(),
                  const SizedBox(height: 14),
                  SizedBox(height: 42, child: _detailRow(3)),
                ],
              ],
            ),
          ),
        ),
        if (showBarcode)
          Container(
            width: 128,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFFE9EBF2))),
            ),
            child: Center(
              child: _barcodeStrip(height: double.infinity, vertical: true),
            ),
          ),
      ],
    );
  }

  // ---- pieces --------------------------------------------------------------
  Widget _hero(BuildContext context) {
    final url = (imageUrl ?? '').trim();
    Widget imageWidget;
    if (url.isNotEmpty) {
      imageWidget = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(context),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(context, shimmer: true),
      );
    } else {
      imageWidget = _placeholder(context);
    }

    if (isScrap || badge != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          imageWidget,
          Positioned(top: 8, right: 8, child: badge ?? _scrapBadge()),
        ],
      );
    }
    return imageWidget;
  }

  Widget _scrapBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14B45309),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.recycling_rounded, size: 12, color: Color(0xFFD97706)),
          SizedBox(width: 4),
          Text(
            'SCRAP',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFFB45309),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context, {bool shimmer = false}) {
    final effectiveAccent = isScrap ? const Color(0xFFD97706) : accent;
    final tokenBg = isScrap ? const Color(0xFFFEF3C7) : SoftErpTheme.accentSoft;
    final tokenColor = isScrap
        ? const Color(0xFFB45309)
        : SoftErpTheme.accentDark;
    final gradientColors = isScrap
        ? const [Color(0xFFFFFDF8), Color(0xFFFEF3C7)]
        : const [Color(0xFFFDFBF6), Color(0xFFEFF1F8)];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final s = (c.biggest.shortestSide * 0.42).clamp(34.0, 84.0);
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: s,
                  height: s,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokenBg,
                    borderRadius: BorderRadius.circular(s * 0.3),
                    border: Border.all(
                      color: effectiveAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        token,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: tokenColor,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                ),
                if (c.maxHeight > 96 && caption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isScrap
                            ? const Color(0xFF92400E)
                            : SoftErpTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _detailRow(int maxCols) {
    final shown = details.take(maxCols).toList(growable: false);
    final cells = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      if (i > 0) {
        cells.add(
          const SizedBox(
            height: 30,
            child: VerticalDivider(
              width: 13,
              thickness: 1,
              color: Color(0xFFEDEFF5),
            ),
          ),
        );
      }
      cells.add(Expanded(child: _detailCell(shown[i])));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: cells);
  }

  Widget _detailCell(BoardingPassDetail d) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          d.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: Color(0xFF9AA1B2),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          d.value.isEmpty ? '—' : d.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _barcodeStrip({required double height, bool vertical = false}) {
    final code = (barcode ?? '').trim();
    final bar = BarcodeWidget(
      barcode: Barcode.code128(),
      data: code,
      drawText: false,
      color: const Color(0xFF111827),
      backgroundColor: Colors.white,
    );
    if (vertical) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: RotatedBox(quarterTurns: 1, child: bar)),
          const SizedBox(height: 6),
          Text(
            code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textSecondary,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: SizedBox(height: height, child: bar),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: SoftErpTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The dashed "tear line" that gives the ticket its boarding-pass character.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          const dash = 5.0;
          const gap = 4.0;
          final count = (c.maxWidth / (dash + gap)).floor().clamp(0, 400);
          return Row(
            children: List<Widget>.generate(
              count,
              (_) => Container(
                width: dash,
                height: 1,
                margin: const EdgeInsets.only(right: gap),
                color: const Color(0xFFDFE2EC),
              ),
            ),
          );
        },
      ),
    );
  }
}
