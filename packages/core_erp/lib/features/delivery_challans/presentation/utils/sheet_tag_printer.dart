import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// One printable sheet tag: the physical sheet's index, its allocated weight,
/// and the parent/child barcode codes minted on the wizard's Done step.
class SheetTag {
  const SheetTag({
    required this.index,
    required this.weight,
    required this.parentCode,
    required this.childCode,
  });

  final int index;
  final double weight;
  final String parentCode;
  final String childCode;
}

/// Renders sheet barcode tags to a PDF and hands them to the OS print pipeline
/// (`Printing.layoutPdf` → any installed/network/Bluetooth printer, or Save as
/// PDF). Models the existing `JobCardPrinter` pattern. One 100×50 mm label per
/// page so thermal label printers get one label per tag; office printers scale.
class SheetTagPrinter {
  static const _ink = PdfColor.fromInt(0xFF303646);
  static const _muted = PdfColor.fromInt(0xFF6C7386);
  static const _accent = PdfColor.fromInt(0xFF5E49E6);
  static const _border = PdfColor.fromInt(0xFFE6E8F4);

  static const _labelFormat = PdfPageFormat(
    100 * PdfPageFormat.mm,
    50 * PdfPageFormat.mm,
    marginAll: 4 * PdfPageFormat.mm,
  );

  /// Prints [tags] for one item. [itemName] is the item's short code/name shown
  /// on every tag (e.g. "alloy"); [challanNo] identifies the source challan.
  static Future<void> printTags({
    required String itemName,
    required String challanNo,
    required List<SheetTag> tags,
    String weightUnit = 'kg',
  }) async {
    if (tags.isEmpty) return;
    final doc = pw.Document();
    for (final tag in tags) {
      doc.addPage(
        pw.Page(
          pageFormat: _labelFormat,
          build: (context) => _buildTag(itemName, challanNo, tag, weightUnit),
        ),
      );
    }
    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: tags.length == 1
          ? 'Tag_${_safe(itemName)}_${challanNo}_${tags.first.index}.pdf'
          : 'Tags_${_safe(itemName)}_$challanNo.pdf',
    );
  }

  static pw.Widget _buildTag(
    String itemName,
    String challanNo,
    SheetTag tag,
    String weightUnit,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  itemName.isEmpty ? '—' : itemName,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                challanNo,
                style: const pw.TextStyle(color: _muted, fontSize: 8),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Sheet ${tag.index}',
                style: const pw.TextStyle(color: _muted, fontSize: 10),
              ),
              pw.Text(
                '${_formatWeight(tag.weight)} $weightUnit',
                style: pw.TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Expanded(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: tag.parentCode,
              drawText: false,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            tag.childCode,
            textAlign: pw.TextAlign.center,
            maxLines: 1,
            style: pw.TextStyle(
              color: _ink,
              fontSize: 9,
              letterSpacing: 0.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatWeight(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  static String _safe(String value) {
    final cleaned = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.isEmpty ? 'ITEM' : cleaned;
  }
}
