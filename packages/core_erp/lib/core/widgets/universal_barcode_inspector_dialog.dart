import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/barcode_label_service.dart';
import '../theme/soft_erp_theme.dart';
import '../../features/search/domain/universal_barcode_entity.dart';

/// What a scan shows: what this is, and everything that has happened to it.
///
/// One screen for every kind of code, because the scanner gun does not know
/// what it is pointed at and neither does the person holding it. A sheet, a
/// challan, a machine and a person's badge all come back in the same shape and
/// all render here.
///
/// The trail is the point. Business tables are rewritten in place and can only
/// say what is true now; the custody events say who touched this, when, on what
/// paperwork, and what it became — which is the question asked when a client
/// returns a defective part.
Future<void> showUniversalBarcodeInspector(
  BuildContext context, {
  required UniversalBarcodeEntity scan,
  void Function(String code)? onFollowBarcode,
  Future<void> Function(BarcodeLabel label, LabelStock stock)? onPrintLabel,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Scan result',
    barrierColor: const Color(0x66100D1F),
    pageBuilder: (context, animation, secondaryAnimation) => SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
          child: SizedBox(
            height: double.infinity,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580, minWidth: 420),
              child: UniversalBarcodeInspector(
                scan: scan,
                onFollowBarcode: onFollowBarcode,
                onPrintLabel: onPrintLabel,
              ),
            ),
          ),
        ),
      ),
    ),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class UniversalBarcodeInspector extends StatelessWidget {
  const UniversalBarcodeInspector({
    super.key,
    required this.scan,
    this.onFollowBarcode,
    this.onPrintLabel,
  });

  final UniversalBarcodeEntity scan;

  /// Following a barcode named inside the trail — the parent it came from, the
  /// run it went into. This is what turns a record into a walkable chain.
  final void Function(String code)? onFollowBarcode;

  /// Sending a label to the printer. Injected so the panel can be exercised
  /// without a print dialog and a platform channel; defaults to really printing.
  final Future<void> Function(BarcodeLabel label, LabelStock stock)? onPrintLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(scan: scan),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: <Widget>[
                if (!scan.found) _NotFound(scan: scan) else ...<Widget>[
                  if (scan.resolution.isMisread) _MisreadWarning(scan: scan),
                  if (scan.resolution.isLegacy) _LegacyNotice(scan: scan),
                  if (scan.facts.isNotEmpty) _Facts(facts: scan.facts),
                  const SizedBox(height: 16),
                  _Custody(scan: scan, onFollowBarcode: onFollowBarcode),
                ],
              ],
            ),
          ),
          // Reprinting is offered even when nothing resolved: the usual reason
          // to reprint is that the sticker is unreadable, which is exactly when
          // the scan comes back empty.
          if (scan.code.trim().isNotEmpty)
            _PrintBar(scan: scan, onPrintLabel: onPrintLabel),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.scan});

  final UniversalBarcodeEntity scan;

  @override
  Widget build(BuildContext context) {
    final entity = scan.entity;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entity?.title ?? 'Not recognised',
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entity == null
                      ? scan.code
                      : [entity.typeLabel, entity.subtitle]
                            .where((part) => part.trim().isNotEmpty)
                            .join('  ·  '),
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                // The code itself, selectable and copyable — someone reading a
                // damaged label needs to be able to type what they can make out.
                Row(
                  children: <Widget>[
                    Flexible(
                      child: SelectableText(
                        scan.code,
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: SoftErpTheme.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy code',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: scan.code));
                      },
                    ),
                    if (scan.resolution.isVerified)
                      const Tooltip(
                        message: 'Check character verified — this is the code '
                            'that was printed',
                        child: Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _CodeSymbol(code: scan.code),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// The code as something a scanner can actually read.
///
/// Two uses, and they want different symbologies. Holding a phone up to the
/// screen to carry a code to the floor wants the QR; checking that the sticker
/// in your hand matches the record wants the 1D bars, because that is what is
/// printed on it and the eye can compare them.
///
/// A code that will not encode renders as nothing rather than throwing. The
/// panel's job is to explain a scan, and it must not itself become the thing
/// that fails — a legacy vendor label is exactly the case someone opens this
/// panel to investigate.
class _CodeSymbol extends StatelessWidget {
  const _CodeSymbol({required this.code});

  final String code;

  static const Widget _nothing = SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    if (code.trim().isEmpty) return _nothing;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        BarcodeWidget(
          barcode: Barcode.qrCode(),
          data: code,
          width: 46,
          height: 46,
          drawText: false,
          color: SoftErpTheme.textPrimary,
          errorBuilder: (context, error) => _nothing,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: BarcodeWidget(
            barcode: Barcode.code128(),
            data: code,
            height: 44,
            drawText: false,
            color: SoftErpTheme.textPrimary,
            errorBuilder: (context, error) => _nothing,
          ),
        ),
      ],
    );
  }
}

/// Nothing resolved — and which kind of nothing.
class _NotFound extends StatelessWidget {
  const _NotFound({required this.scan});

  final UniversalBarcodeEntity scan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SoftErpTheme.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9C69A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.help_outline_rounded, size: 18, color: Color(0xFF8A4D00)),
              SizedBox(width: 8),
              Text(
                'Nothing carries this code',
                style: TextStyle(
                  color: Color(0xFF8A4D00),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            scan.notFoundMessage,
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The check character did not match what the rest of the code says it should.
class _MisreadWarning extends StatelessWidget {
  const _MisreadWarning({required this.scan});

  final UniversalBarcodeEntity scan;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.dangerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5C2C7)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, size: 18, color: SoftErpTheme.dangerText),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This code did not check out',
                  style: TextStyle(
                    color: SoftErpTheme.dangerText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'A character was misread, or the label is damaged. What is shown '
            'below is the record the code would name — check it is what you '
            'are actually holding before acting on it.',
            style: TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolved by a code printed before the scheme existed.
class _LegacyNotice extends StatelessWidget {
  const _LegacyNotice({required this.scan});

  final UniversalBarcodeEntity scan;

  @override
  Widget build(BuildContext context) {
    final canonical = scan.resolution.canonical;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Found by its old label',
            style: TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            canonical == null
                ? 'This code predates the current scheme. It still resolves.'
                : 'This code predates the current scheme. Reprinted, it would '
                      'read $canonical — which carries a check character, so a '
                      'misread would be caught.',
            style: const TextStyle(
              color: SoftErpTheme.textSecondary,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});

  final List<BarcodeFact> facts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final fact in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 120,
                    child: Text(
                      fact.label,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      fact.value,
                      style: const TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The chain of custody, oldest first.
class _Custody extends StatelessWidget {
  const _Custody({required this.scan, this.onFollowBarcode});

  final UniversalBarcodeEntity scan;
  final void Function(String code)? onFollowBarcode;

  @override
  Widget build(BuildContext context) {
    if (scan.custody.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SoftErpTheme.sectionSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: const Text(
          // Said plainly rather than shown as an empty list: nothing recorded
          // is a fact about the record, not a fault in the screen, and the two
          // look identical if the section simply renders nothing.
          'Nothing has been recorded against this yet. Events appear here as it '
          'is received, moved, worked on and shipped.',
          style: TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 12.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Chain of custody',
          style: const TextStyle(
            color: SoftErpTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${scan.custody.length} event${scan.custody.length == 1 ? '' : 's'}, oldest first',
          style: const TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < scan.custody.length; index += 1)
          _CustodyRow(
            event: scan.custody[index],
            isLast: index == scan.custody.length - 1,
            onFollowBarcode: onFollowBarcode,
          ),
      ],
    );
  }
}

class _CustodyRow extends StatelessWidget {
  const _CustodyRow({
    required this.event,
    required this.isLast,
    this.onFollowBarcode,
  });

  final CustodyEvent event;
  final bool isLast;
  final void Function(String code)? onFollowBarcode;

  @override
  Widget build(BuildContext context) {
    final metrics = event.metrics.entries
        .where((entry) => entry.value != null && '${entry.value}'.isNotEmpty)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('   ');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The spine: a dot per event and a line between them, so a long trail
          // reads as one sequence rather than a stack of cards.
          Column(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: SoftErpTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 1.5, color: SoftErpTheme.border),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          event.label,
                          style: const TextStyle(
                            color: SoftErpTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        event.at,
                        style: const TextStyle(
                          color: SoftErpTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (event.actor.isNotEmpty || metrics.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (event.actor.isNotEmpty) 'by ${event.actor}',
                        if (metrics.isNotEmpty) metrics,
                      ].join('   ·   '),
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (event.notes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      event.notes,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (event.relatedBarcodes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final code in event.relatedBarcodes)
                          _FollowChip(
                            code: code,
                            onTap: onFollowBarcode == null
                                ? null
                                : () => onFollowBarcode!(code),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A barcode mentioned by an event, and a way to walk to it.
///
/// This is what makes the trail a chain rather than a list: from a sheet you
/// reach the challan it arrived on, from there the vendor, from the run it went
/// into the machine that ran it.
class _FollowChip extends StatelessWidget {
  const _FollowChip({required this.code, this.onTap});

  final String code;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: SoftErpTheme.accentSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFC7C2FF)),
          ),
          child: Text(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: SoftErpTheme.accentDeeper,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts the scanned code back onto physical stock.
///
/// The stock defaults to what suits the entity — a sheet gets a sticker, a
/// crate gets something a courier can read — because choosing by hand every
/// time is how the wrong roll ends up loaded. It stays changeable for the
/// workshop that only owns one size.
class _PrintBar extends StatefulWidget {
  const _PrintBar({required this.scan, this.onPrintLabel});

  final UniversalBarcodeEntity scan;
  final Future<void> Function(BarcodeLabel label, LabelStock stock)? onPrintLabel;

  @override
  State<_PrintBar> createState() => _PrintBarState();
}

class _PrintBarState extends State<_PrintBar> {
  late LabelStock _stock =
      LabelStock.forEntityType(widget.scan.entity?.type ?? '');
  bool _busy = false;

  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    final label = BarcodeLabel.fromScan(widget.scan);
    final stock = _stock;
    try {
      final handler = widget.onPrintLabel;
      if (handler != null) {
        await handler(label, stock);
      } else {
        await BarcodeLabelService.printLabels(
          labels: <BarcodeLabel>[label],
          stock: stock,
        );
      }
    } catch (error) {
      // A printer that is off, out of paper or not installed is ordinary, and
      // a button that stays spinning tells nobody what went wrong.
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Could not print that label: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(top: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        children: <Widget>[
          Flexible(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<LabelStock>(
                value: _stock,
                isDense: true,
                isExpanded: true,
                borderRadius: BorderRadius.circular(10),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.textSecondary,
                ),
                items: <DropdownMenuItem<LabelStock>>[
                  for (final stock in LabelStock.all)
                    DropdownMenuItem<LabelStock>(
                      value: stock,
                      child: Text(stock.description, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (stock) {
                        if (stock != null) setState(() => _stock = stock);
                      },
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _print,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_rounded, size: 17),
            label: const Text('Print label'),
          ),
        ],
      ),
    );
  }
}
