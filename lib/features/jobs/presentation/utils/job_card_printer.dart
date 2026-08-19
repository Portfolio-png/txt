import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:core_erp/features/departments/domain/employee_definition.dart';
import '../../domain/freelancer_job.dart';

class JobCardPrinter {
  static const String _secretKey = 'my-very-secret-key-32charslong!!';
  static const String _portalBaseUrl = String.fromEnvironment(
    'PAPER_PORTAL_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static String generateEncryptedToken(String barcodeId) {
    final key = encrypt.Key.fromUtf8(_secretKey);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc),
    );

    final encrypted = encrypter.encrypt(barcodeId, iv: iv);

    // Format: iv_hex:encrypted_hex
    return '${iv.bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}:${encrypted.bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}';
  }

  static Future<void> printJobCard(
    EmployeeDefinition freelancer,
    String batchNumber,
    List<FreelancerJob> jobs,
  ) async {
    final doc = pw.Document();

    final token = generateEncryptedToken(
      freelancer.barcodeId.isNotEmpty
          ? freelancer.barcodeId
          : freelancer.id.toString(),
    );
    final portalRoot = _portalBaseUrl.replaceFirst(RegExp(r'/$'), '');
    final portalUrl =
        '$portalRoot/#/freelancer-portal?token=${Uri.encodeQueryComponent(token)}';
    final totalUnits = jobs.fold<int>(0, (sum, job) => sum + job.quantity);
    final totalReward = jobs.fold<double>(
      0,
      (sum, job) => sum + job.payoutBalance,
    );
    const ink = PdfColor.fromInt(0xFF303646);
    const muted = PdfColor.fromInt(0xFF6C7386);
    const accent = PdfColor.fromInt(0xFF5E49E6);
    const accentSoft = PdfColor.fromInt(0xFFECEBFF);
    const border = PdfColor.fromInt(0xFFE6E8F4);
    const surface = PdfColor.fromInt(0xFFF7F7FB);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(24),
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: pw.BorderRadius.circular(18),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PAPER ERP  /  FREELANCER WORK ORDER',
                            style: const pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 10,
                              letterSpacing: 1.1,
                            ),
                          ),
                          pw.SizedBox(height: 12),
                          pw.Text(
                            'Job card',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 28,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text(
                            batchNumber,
                            style: const pw.TextStyle(
                              color: PdfColor.fromInt(0xFFDCD8FF),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Container(
                      width: 92,
                      height: 92,
                      padding: const pw.EdgeInsets.all(7),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: portalUrl,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 22),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(18),
                      decoration: pw.BoxDecoration(
                        color: surface,
                        border: pw.Border.all(color: border),
                        borderRadius: pw.BorderRadius.circular(14),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'ASSIGNED TO',
                            style: const pw.TextStyle(
                              color: muted,
                              fontSize: 9,
                              letterSpacing: 1,
                            ),
                          ),
                          pw.SizedBox(height: 7),
                          pw.Text(
                            freelancer.name,
                            style: pw.TextStyle(
                              color: ink,
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (freelancer.phone.isNotEmpty) ...[
                            pw.SizedBox(height: 5),
                            pw.Text(
                              freelancer.phone,
                              style: const pw.TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          pw.SizedBox(height: 10),
                          pw.Text(
                            'Freelancer ID: ${freelancer.barcodeId.isNotEmpty ? freelancer.barcodeId : freelancer.id}',
                            style: const pw.TextStyle(
                              color: muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(18),
                      decoration: pw.BoxDecoration(
                        color: accentSoft,
                        borderRadius: pw.BorderRadius.circular(14),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            'ISSUED ON',
                            style: const pw.TextStyle(
                              color: muted,
                              fontSize: 9,
                              letterSpacing: 1,
                            ),
                          ),
                          pw.SizedBox(height: 7),
                          pw.Text(
                            DateTime.now().toLocal().toString().split(' ')[0],
                            style: pw.TextStyle(
                              color: ink,
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 22),
              pw.Row(
                children: [
                  _summaryBox(
                    'JOBS',
                    jobs.length.toString(),
                    ink,
                    muted,
                    border,
                  ),
                  pw.SizedBox(width: 10),
                  _summaryBox(
                    'TOTAL UNITS',
                    totalUnits.toString(),
                    ink,
                    muted,
                    border,
                  ),
                  pw.SizedBox(width: 10),
                  _summaryBox(
                    'CURRENT REWARD',
                    'Rs. ${totalReward.toStringAsFixed(2)}',
                    ink,
                    muted,
                    border,
                  ),
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Text(
                'Assigned jobs',
                style: pw.TextStyle(
                  color: ink,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                context: context,
                headers: const [
                  'Job',
                  'Assembly output',
                  'Assigned',
                  'Rejected',
                  'Accepted',
                  'Status',
                ],
                data: jobs
                    .map(
                      (job) => [
                        '#${job.id}',
                        'Item #${job.itemId}',
                        job.quantity.toString(),
                        // Pieces the assembler rejected off this job — the
                        // assembly-line equivalent of a stage's scrap.
                        job.rejectedQuantity == 0
                            ? '—'
                            : job.rejectedQuantity
                                .toStringAsFixed(
                                  job.rejectedQuantity % 1 == 0 ? 0 : 2,
                                ),
                        job.acceptedQuantity.toString(),
                        _statusLabel(job.status),
                      ],
                    )
                    .toList(growable: false),
                headerDecoration: const pw.BoxDecoration(color: accentSoft),
                headerStyle: pw.TextStyle(
                  color: ink,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(color: ink, fontSize: 10),
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                border: pw.TableBorder.all(color: border, width: 0.7),
              ),
              pw.Spacer(),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: pw.BoxDecoration(
                  color: surface,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Scan the QR code to view live progress, assigned items, and reward balance.',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(color: muted, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Job_Card_$batchNumber.pdf',
    );
  }

  static pw.Widget _summaryBox(
    String label,
    String value,
    PdfColor ink,
    PdfColor muted,
    PdfColor border,
  ) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: border),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                color: muted,
                fontSize: 8.5,
                letterSpacing: 0.7,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: ink,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String status) {
    final normalized = status.replaceAll('-', ' ').replaceAll('_', ' ').trim();
    if (normalized.isEmpty) return 'Unknown';
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
