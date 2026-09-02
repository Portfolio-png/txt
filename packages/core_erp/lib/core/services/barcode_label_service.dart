import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:core_erp/features/search/domain/universal_barcode_entity.dart';

// `BarcodeLabel.lines` is a list of these, so anyone building a label has to be
// able to name the type. Re-exported rather than left for each caller to hunt
// down in the search feature, which is not where a label belongs.
export 'package:core_erp/features/search/domain/universal_barcode_entity.dart'
    show BarcodeFact;

/// Puts a scannable code onto physical stock.
///
/// Until this existed the codes were real but invisible: the resolver could
/// answer for any of them and nothing could put one on a sheet of steel. A
/// barcode nobody can stick to the thing it names is bookkeeping, not tracking.
///
/// The layout arithmetic is kept apart from the PDF drawing because that is
/// where the money is. Label stock is bought in rolls and a run that puts every
/// label half a millimetre off the edge is a bin full of waste discovered after
/// the fact — so [SheetLayout] is plain arithmetic that can be checked without
/// rendering anything.

/// Which symbology goes on the label.
///
/// A scanner gun reads 1D fastest and that is what the floor uses, so Code 128
/// is the default. QR is added where there is room because a phone camera reads
/// it and a phone is what someone reaching a machine in a corner actually has.
enum LabelSymbology { code128, qr, both }

/// A physical label size.
@immutable
class LabelStock {
  const LabelStock({
    required this.name,
    required this.widthMm,
    required this.heightMm,
  });

  final String name;
  final double widthMm;
  final double heightMm;

  /// Direct-thermal roll sizes, the common ones a small workshop buys.
  static const LabelStock materialSticker =
      LabelStock(name: 'Material sticker', widthMm: 50, heightMm: 25);
  static const LabelStock materialStickerLarge =
      LabelStock(name: 'Material sticker (large)', widthMm: 75, heightMm: 50);
  static const LabelStock shipping =
      LabelStock(name: 'Shipping label', widthMm: 100, heightMm: 75);
  static const LabelStock shippingTall =
      LabelStock(name: 'Shipping label (tall)', widthMm: 100, heightMm: 150);
  static const LabelStock assetPlate =
      LabelStock(name: 'Asset plate', widthMm: 70, heightMm: 35);
  static const LabelStock idBadge =
      LabelStock(name: 'ID badge', widthMm: 85, heightMm: 54);

  static const List<LabelStock> all = <LabelStock>[
    materialSticker,
    materialStickerLarge,
    assetPlate,
    idBadge,
    shipping,
    shippingTall,
  ];

  /// The stock that suits what was scanned.
  ///
  /// A sheet of steel gets a sticker, a crate going to a client gets something
  /// a courier can read across a loading bay, a machine gets a plate that
  /// survives being wiped down, a person gets something that fits a lanyard.
  /// Picking by hand every time is how the wrong roll ends up in the printer.
  static LabelStock forEntityType(String type) {
    return switch (type.toUpperCase()) {
      'MAT' || 'MOV' => materialSticker,
      'DC' || 'RC' || 'DCL' => shipping,
      'MCH' || 'DIE' => assetPlate,
      'EMP' => idBadge,
      _ => materialStickerLarge,
    };
  }

  /// Big enough to carry a QR alongside the 1D code without crowding either.
  bool get hasRoomForBoth => widthMm >= 70 && heightMm >= 35;

  /// Shown when choosing a roll, so the size is visible rather than implied by
  /// a name.
  String get description => '$name · ${_mm(widthMm)}×${_mm(heightMm)}mm';

  static String _mm(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  // Const instances are compared by a dropdown and by callers picking a stock;
  // value equality keeps that from depending on canonicalisation.
  @override
  bool operator ==(Object other) =>
      other is LabelStock &&
      other.name == name &&
      other.widthMm == widthMm &&
      other.heightMm == heightMm;

  @override
  int get hashCode => Object.hash(name, widthMm, heightMm);

  PdfPageFormat get pageFormat => PdfPageFormat(
    widthMm * PdfPageFormat.mm,
    heightMm * PdfPageFormat.mm,
    marginAll: 2.5 * PdfPageFormat.mm,
  );
}

/// How many labels fit on a sheet, and how many sheets that takes.
///
/// Pure arithmetic on purpose. The failure this guards against is silent: a
/// column count that rounds up rather than down puts the last label off the
/// edge of every page, and nobody finds out until the run is printed.
@immutable
class SheetLayout {
  const SheetLayout({
    required this.columns,
    required this.rows,
    required this.pages,
    required this.fitsOnPage,
  });

  /// [labelCount] labels of [stock] onto pages of the given size, all in mm.
  factory SheetLayout.fit({
    required LabelStock stock,
    required int labelCount,
    double pageWidthMm = 210, // A4
    double pageHeightMm = 297,
    double marginMm = 8,
    double gutterMm = 3,
  }) {
    // n labels across occupy n*w + (n-1)*gutter, so n <= (usable+g)/(w+g).
    // Floored, never rounded: a label that overhangs is a wasted sheet.
    int fitAcross(double usable, double size) {
      if (size <= 0) return 0;
      return ((usable + gutterMm) / (size + gutterMm)).floor();
    }

    final columns = fitAcross(pageWidthMm - marginMm * 2, stock.widthMm);
    final rows = fitAcross(pageHeightMm - marginMm * 2, stock.heightMm);
    final fits = columns >= 1 && rows >= 1;

    // Stock wider than the page is a real configuration — a 100x150 shipping
    // label has no business being tiled onto A4. Falling back to one per page
    // keeps the caller from dividing by zero to find that out.
    final perPage = fits ? columns * rows : 1;
    return SheetLayout(
      columns: fits ? columns : 1,
      rows: fits ? rows : 1,
      pages: labelCount <= 0 ? 0 : (labelCount / perPage).ceil(),
      fitsOnPage: fits,
    );
  }

  final int columns;
  final int rows;
  final int pages;

  /// False when the stock is larger than the page, meaning multi-up is not
  /// sensible and the label should go to its own roll.
  final bool fitsOnPage;

  int get perPage => columns * rows;
}

/// One label's worth of content.
@immutable
class BarcodeLabel {
  const BarcodeLabel({
    required this.code,
    required this.title,
    this.subtitle = '',
    this.lines = const <BarcodeFact>[],
    this.footer = '',
  });

  /// A label for whatever was just scanned, so the inspector can reprint the
  /// thing in your hand when its sticker has been rubbed illegible.
  ///
  /// A legacy code reprints as its **canonical** form. The panel already tells
  /// you a code was found by its old label and shows what it ought to say;
  /// printing the old one back would make that notice permanent, and the label
  /// would stay outside the scheme — unverifiable — forever. Reprinting is the
  /// one moment the upgrade is free, because the sticker is being replaced
  /// anyway.
  factory BarcodeLabel.fromScan(UniversalBarcodeEntity scan) {
    final entity = scan.entity;
    final canonical = scan.resolution.canonical?.trim() ?? '';
    return BarcodeLabel(
      code: canonical.isNotEmpty ? canonical : scan.code,
      title: entity?.title ?? scan.code,
      subtitle: entity?.subtitle ?? '',
      // Three facts is what fits before a 50x25 sticker becomes unreadable.
      lines: scan.facts.take(3).toList(growable: false),
      footer: entity?.typeLabel ?? '',
    );
  }

  final String code;
  final String title;
  final String subtitle;
  final List<BarcodeFact> lines;
  final String footer;

  /// Code 128 covers ASCII and nothing else. Our codes are uppercase
  /// alphanumeric so they always encode — but a legacy label carried over from
  /// a vendor need not be, and a symbology that throws mid-render would take
  /// the whole print run with it.
  bool get isCode128Safe =>
      code.isNotEmpty && code.codeUnits.every((unit) => unit >= 32 && unit < 127);

  LabelSymbology symbologyOn(LabelStock stock) {
    if (!isCode128Safe) return LabelSymbology.qr;
    return stock.hasRoomForBoth ? LabelSymbology.both : LabelSymbology.code128;
  }
}

class BarcodeLabelService {
  static const PdfColor _ink = PdfColor.fromInt(0xFF111827);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _border = PdfColor.fromInt(0xFFD1D5DB);

  /// One label per page, sized to the stock — what a thermal roll printer wants.
  static Future<Uint8List> buildLabelPdf({
    required List<BarcodeLabel> labels,
    required LabelStock stock,
    int copies = 1,
  }) async {
    final doc = pw.Document();
    for (final label in labels) {
      for (var copy = 0; copy < copies; copy += 1) {
        doc.addPage(
          pw.Page(
            pageFormat: stock.pageFormat,
            build: (context) => _label(label, stock),
          ),
        );
      }
    }
    return doc.save();
  }

  /// Many labels tiled onto plain paper — for a workshop without a label
  /// printer, which is most of them on day one.
  static Future<Uint8List> buildSheetPdf({
    required List<BarcodeLabel> labels,
    required LabelStock stock,
    PdfPageFormat page = PdfPageFormat.a4,
    double gutterMm = 3,
    double marginMm = 8,
  }) async {
    final layout = SheetLayout.fit(
      stock: stock,
      labelCount: labels.length,
      pageWidthMm: page.width / PdfPageFormat.mm,
      pageHeightMm: page.height / PdfPageFormat.mm,
      marginMm: marginMm,
      gutterMm: gutterMm,
    );

    final doc = pw.Document();
    for (var pageIndex = 0; pageIndex < layout.pages; pageIndex += 1) {
      final start = pageIndex * layout.perPage;
      final slice = labels.skip(start).take(layout.perPage).toList();
      doc.addPage(
        pw.Page(
          pageFormat: page.copyWith(
            marginLeft: marginMm * PdfPageFormat.mm,
            marginTop: marginMm * PdfPageFormat.mm,
            marginRight: marginMm * PdfPageFormat.mm,
            marginBottom: marginMm * PdfPageFormat.mm,
          ),
          build: (context) => pw.Wrap(
            spacing: gutterMm * PdfPageFormat.mm,
            runSpacing: gutterMm * PdfPageFormat.mm,
            children: <pw.Widget>[
              for (final label in slice)
                pw.SizedBox(
                  width: stock.widthMm * PdfPageFormat.mm,
                  height: stock.heightMm * PdfPageFormat.mm,
                  child: _label(label, stock, bordered: true),
                ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Hands the labels to the OS print pipeline.
  static Future<void> printLabels({
    required List<BarcodeLabel> labels,
    LabelStock? stock,
    bool multiUp = false,
    int copies = 1,
  }) async {
    if (labels.isEmpty) return;
    final target = stock ?? LabelStock.materialStickerLarge;
    final bytes = multiUp
        ? await buildSheetPdf(labels: labels, stock: target)
        : await buildLabelPdf(labels: labels, stock: target, copies: copies);
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: labels.length == 1
          ? 'Label_${_safe(labels.first.code)}.pdf'
          : 'Labels_${labels.length}.pdf',
    );
  }

  /// Drawn with the PDF built-in fonts, as every other document in this app is.
  /// Those are Latin-1, so a title outside it loses characters — but the code
  /// is uppercase ASCII by construction, so the label still scans and the trail
  /// is intact. Degrading to an ugly label beats degrading to an unscannable one.
  static pw.Widget _label(
    BarcodeLabel label,
    LabelStock stock, {
    bool bordered = false,
  }) {
    final symbology = label.symbologyOn(stock);
    // Type scales with the stock: 8pt on a 25mm sticker is the smallest a
    // thermal head prints legibly, and a shipping label wants to be read from
    // across a loading bay.
    final titleSize = stock.heightMm >= 70 ? 16.0 : (stock.heightMm >= 50 ? 12.0 : 9.0);
    final bodySize = stock.heightMm >= 70 ? 10.0 : 7.0;
    final barHeight = stock.heightMm * PdfPageFormat.mm * 0.30;

    return pw.Container(
      decoration: bordered
          ? pw.BoxDecoration(border: pw.Border.all(color: _border, width: 0.5))
          : null,
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                label.title.isEmpty ? label.code : label.title,
                maxLines: 2,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(
                  color: _ink,
                  fontSize: titleSize,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (label.subtitle.isNotEmpty)
                pw.Text(
                  label.subtitle,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(color: _muted, fontSize: bodySize),
                ),
              for (final line in label.lines)
                pw.Text(
                  '${line.label}: ${line.value}',
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(color: _muted, fontSize: bodySize),
                ),
            ],
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Expanded(
                child: symbology == LabelSymbology.qr
                    ? pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: label.code,
                          width: barHeight,
                          height: barHeight,
                          color: _ink,
                        ),
                      )
                    : pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: label.code,
                        drawText: true,
                        height: barHeight,
                        textStyle: pw.TextStyle(fontSize: bodySize),
                        color: _ink,
                      ),
              ),
              if (symbology == LabelSymbology.both) ...<pw.Widget>[
                pw.SizedBox(width: 6),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: label.code,
                  width: barHeight,
                  height: barHeight,
                  color: _ink,
                ),
              ],
            ],
          ),
          if (label.footer.isNotEmpty)
            pw.Text(
              label.footer,
              style: pw.TextStyle(color: _muted, fontSize: bodySize - 1),
            ),
        ],
      ),
    );
  }

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
