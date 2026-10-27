import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../materials/domain/material_definition.dart';
import '../../../units/domain/quantity.dart';
import '../../../units/domain/unit_family.dart';
import '../../../units/domain/units.dart';
import '../../domain/pen_paper_baseline.dart';

/// One block of the Raw sheet review: a heading and its label–value lines.
class RawSheetReviewSection {
  const RawSheetReviewSection(this.title, this.rows);

  final String title;
  final List<(String label, String value)> rows;
}

/// The Raw sheet review, as the sections both the screen and the printed
/// sheet show — one template, so what is printed is what was reviewed.
///
/// [partName] is the part being made, [sheetLabel] the sheet it is cut from
/// ("Steel / MS · 48 × 96 in · 1.6 mm"). Weights need [material]; without
/// it the plan is stated in pieces and millimetres alone.
List<RawSheetReviewSection> rawSheetReviewSections({
  required PenPaperBaseline baseline,
  required String partName,
  required String sheetLabel,
  MaterialDefinition? material,
  UnitFamily? countFamily,
}) {
  String kg(double value) => '${_kg(value)} kg';
  String mm(double value) => '${_trim(value)} mm';

  final parts = baseline.yields.where((entry) => !entry.isOffcut).toList();
  final sheetAreaMm2 = baseline.sheetWidthMm * baseline.sheetHeightMm;
  final partsAreaMm2 = parts.fold<double>(0, (sum, e) => sum + e.areaMm2);
  final yieldPct = sheetAreaMm2 > 0 ? partsAreaMm2 / sheetAreaMm2 * 100 : 0.0;

  final sections = <RawSheetReviewSection>[
    RawSheetReviewSection('Part', [
      ('Part', partName.trim().isEmpty ? '—' : partName.trim()),
      if (baseline.pipelineName.trim().isNotEmpty)
        ('Pipeline', baseline.pipelineName.trim()),
    ]),
    RawSheetReviewSection('Sheet', [
      ('Sheet', sheetLabel),
      (
        'Material',
        material == null
            ? (baseline.materialName.trim().isEmpty
                  ? 'Not set — no weight'
                  : '${baseline.materialName.trim()} (not in the master)')
            : '${material.name} · ${material.densityLabel}',
      ),
    ]),
    RawSheetReviewSection('Cut plan', [
      if (parts.isEmpty) ('Pieces', 'Nothing planned on the sheet yet'),
      for (final entry in parts)
        (entry.label, '${entry.count} × ${entry.sizeLabel}'),
      if (baseline.kerfMm > 0) ('Part gap', mm(baseline.kerfMm)),
      if (baseline.edgeTrimMm > 0) ('Edge trim', mm(baseline.edgeTrimMm)),
      ('Pieces per sheet', _pieces(baseline.pieceCount, countFamily)),
      if (sheetAreaMm2 > 0) ('Yield', '${yieldPct.toStringAsFixed(1)}%'),
    ]),
  ];

  if (material != null) {
    final weights = baseline.weighAt(material.densityGCm3);
    sections.add(
      RawSheetReviewSection('Weights per sheet', [
        ('Sheet in', kg(weights.sheetKg)),
        ('Parts out', kg(weights.partsKg)),
        ('Offcut', kg(weights.offcutKg)),
        ('Blade and trim', kg(weights.lostKg)),
      ]),
    );
  }

  final rows = baseline.stageReconciliations;
  if (!baseline.isGranular && rows.isNotEmpty) {
    final row = rows.first;
    sections.add(
      RawSheetReviewSection('Material in and out', [
        (
          'In',
          '${row.sheetsIn} × ${row.inputName.isEmpty ? 'sheet' : row.inputName}',
        ),
        ('Weight in', kg(row.inputKg)),
        ('Out', _pieces(row.piecesOut, countFamily)),
        ('Weight out', kg(row.outputKg)),
        if (row.recordScrap) ('Scrap', kg(row.scrapKg)),
        if (row.recordRejection) ('Rejection', kg(row.rejectionKg)),
        if (row.recordWeightLoss) ('Weight loss', kg(row.weightLossKg)),
        (
          'Balance',
          // The tolerance the balance strip in Material data uses.
          row.balanceDeltaKg.abs() < 0.05
              ? 'Balances'
              : '${kg(row.balanceDeltaKg.abs())} '
                    '${row.balanceDeltaKg > 0 ? 'unaccounted' : 'over'}',
        ),
      ]),
    );
  } else if (baseline.isGranular && rows.isNotEmpty) {
    sections.add(
      RawSheetReviewSection('Material stage by stage', [
        for (final row in rows)
          (row.stageName, '${kg(row.inputKg)} in · ${kg(row.outputKg)} out'),
      ]),
    );
  }

  final notes = baseline.notes.trim().isNotEmpty
      ? baseline.notes.trim()
      : (rows.isEmpty ? '' : rows.first.notes.trim());
  if (notes.isNotEmpty) {
    sections.add(RawSheetReviewSection('Notes', [('', notes)]));
  }
  return sections;
}

/// A count through the units module, spelt down the ladder once it reaches a
/// dozen: "2900 Pc (20 gro · 1 doz · 8 Pc)".
String _pieces(int count, UnitFamily? family) {
  if (family == null) return '$count pcs';
  final q = Quantity(count, family);
  final shown = Units.format(q, display: const QtyDisplay.base());
  return count.abs() >= 12 ? '$shown (${Units.formatBreakdown(q)})' : shown;
}

String _kg(double value) {
  final text = value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  return text.endsWith('.') ? '${text}0' : text;
}

String _trim(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

/// The review on screen: each section a heading over its lines.
class RawSheetReviewCard extends StatelessWidget {
  const RawSheetReviewCard({super.key, required this.sections});

  final List<RawSheetReviewSection> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const Divider(height: 22, color: Color(0xFFE2E8F0)),
          Text(
            section.title.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          for (final (label, value) in section.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: label.isEmpty
                  ? Text(value, style: const TextStyle(fontSize: 14))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            value,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ],
    );
  }
}

/// The PDF's built-in Helvetica has Latin-1 only: × · ³ print, a dash or an
/// arrow would come out as a missing glyph, so those are spelt plainly.
String _latin1(String text) {
  const plain = {'—': '-', '–': '-', '→': '->', '…': '...', '‘': "'", '’': "'"};
  final out = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    out.write(rune <= 0xFF ? char : (plain[char] ?? '?'));
  }
  return out.toString();
}

/// The same review as a printable A4 page, with the cut plan drawn to scale.
Future<Uint8List> buildRawSheetReviewPdf({
  required PenPaperBaseline baseline,
  required List<RawSheetReviewSection> sections,
  required String partName,
}) {
  final doc = pw.Document(title: _latin1('Raw sheet - $partName'));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Text(
          'RAW SHEET & STRIPS',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          _latin1(partName.trim().isEmpty ? 'Part' : partName.trim()),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        if (baseline.sheetWidthMm > 0 && baseline.sheetHeightMm > 0) ...[
          _pdfCutPlan(baseline),
          pw.SizedBox(height: 12),
        ],
        for (final section in sections) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
            child: pw.Text(
              _latin1(section.title.toUpperCase()),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          for (final (label, value) in section.rows)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: label.isEmpty
                  ? pw.Text(
                      _latin1(value),
                      style: const pw.TextStyle(fontSize: 10),
                    )
                  : pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(
                          width: 130,
                          child: pw.Text(
                            _latin1(label),
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            _latin1(value),
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          pw.Divider(color: PdfColors.grey300, height: 10),
        ],
      ],
    ),
  );
  return doc.save();
}

/// The sheet as a scaled outline: each strip, and each piece cut from it.
/// Capped, so a plan of thousands of tiny blanks still prints quickly.
pw.Widget _pdfCutPlan(PenPaperBaseline baseline) {
  const maxWidth = 380.0;
  const maxHeight = 240.0;
  final sheetW = baseline.sheetWidthMm;
  final sheetH = baseline.sheetHeightMm;
  final scale = math.min(maxWidth / sheetW, maxHeight / sheetH);
  final primary = baseline.primaryAxis;
  final secondary = baseline.secondaryAxis;
  final columns = primary == SheetCutAxis.columns;

  final boxes = <pw.Widget>[];
  void box(
    double along,
    double alongSize,
    double across,
    double acrossSize,
    PdfColor fill,
  ) {
    if (boxes.length > 600) return;
    final x = columns ? along : across;
    final y = columns ? across : along;
    final w = columns ? alongSize : acrossSize;
    final h = columns ? acrossSize : alongSize;
    boxes.add(
      pw.Positioned(
        left: x * scale,
        top: y * scale,
        child: pw.Container(
          width: math.max(0.5, w * scale),
          height: math.max(0.5, h * scale),
          decoration: pw.BoxDecoration(
            color: fill,
            border: pw.Border.all(color: PdfColors.blueGrey600, width: 0.4),
          ),
        ),
      ),
    );
  }

  final acrossStart = baseline.trimMm(secondary);
  final acrossSpan = baseline.usableSpanMm(secondary);
  final gap = math.max(0.0, baseline.kerfMm);
  for (final span in baseline.bandSpansMm(primary)) {
    var at = span.startMm;
    for (var i = 0; i < span.count; i++) {
      final cuts = baseline.subCutsFor(span.index);
      if (cuts.isEmpty) {
        box(at, span.sizeMm, acrossStart, acrossSpan, PdfColors.blue50);
      } else {
        // The strip blanked: its pieces walked along it, a gap between each.
        final limit =
            acrossStart + baseline.regionExtentMm(span.index, secondary);
        var across = acrossStart;
        var first = true;
        for (final group in cuts) {
          if (!group.isComplete) continue;
          for (var n = 0; n < group.count; n++) {
            final step = (first ? 0.0 : gap) + group.sizeMm;
            if (across + step > limit + 0.001) break;
            box(
              at,
              span.sizeMm,
              across + step - group.sizeMm,
              group.sizeMm,
              PdfColors.green50,
            );
            across += step;
            first = false;
          }
        }
      }
      at += span.sizeMm + gap;
    }
  }

  return pw.Container(
    width: sheetW * scale,
    height: sheetH * scale,
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      border: pw.Border.all(color: PdfColors.grey800, width: 0.8),
    ),
    child: pw.Stack(children: boxes),
  );
}

/// Opens the printed review in a preview that prints or saves a PDF.
Future<void> showRawSheetReviewPrint(
  BuildContext context, {
  required PenPaperBaseline baseline,
  required List<RawSheetReviewSection> sections,
  required String partName,
}) {
  final safeName = partName.trim().isEmpty
      ? 'part'
      : partName.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 860,
        height: math.min(MediaQuery.of(context).size.height - 40, 820),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Raw sheet review',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: PdfPreview(
                build: (_) => buildRawSheetReviewPdf(
                  baseline: baseline,
                  sections: sections,
                  partName: partName,
                ),
                allowPrinting: true,
                allowSharing: true,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                pdfFileName: 'raw-sheet-$safeName.pdf',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
