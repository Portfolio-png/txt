import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ExportService {
  /// Fields that should be ignored when exporting data
  static const Set<String> _ignoredFields = {
    'id',
    'uuid',
    'created_at',
    'updated_at',
    'createdAt',
    'updatedAt',
    '_id',
  };

  /// Scrubs ignored fields from the data
  static List<Map<String, dynamic>> scrubData(List<Map<String, dynamic>> data) {
    return data.map((row) {
      final newRow = Map<String, dynamic>.from(row);
      newRow.removeWhere((key, value) => _ignoredFields.contains(key));
      return newRow;
    }).toList();
  }

  /// Exports data to JSON
  static Future<void> exportToJson(String fileName, List<Map<String, dynamic>> data) async {
    final scrubbed = scrubData(data);
    final jsonString = const JsonEncoder.withIndent('  ').convert(scrubbed);
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    await _saveFile('$fileName.json', bytes, 'application/json');
  }

  /// Exports data to CSV
  static Future<void> exportToCsv(String fileName, List<Map<String, dynamic>> data) async {
    if (data.isEmpty) return;
    final scrubbed = scrubData(data);
    
    final headers = scrubbed.first.keys.toList();
    final buffer = StringBuffer();
    
    // Add headers
    buffer.writeln(headers.map(_escapeCsv).join(','));
    
    // Add rows
    for (final row in scrubbed) {
      final values = headers.map((h) => _escapeCsv(row[h]?.toString() ?? '')).join(',');
      buffer.writeln(values);
    }
    
    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    await _saveFile('$fileName.csv', bytes, 'text/csv');
  }

  /// Exports data to Excel
  static Future<void> exportToExcel(String fileName, List<Map<String, dynamic>> data) async {
    if (data.isEmpty) return;
    final scrubbed = scrubData(data);
    
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    excel.setDefaultSheet('Sheet1');

    final headers = scrubbed.first.keys.toList();
    
    // Add headers
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    
    // Add rows
    for (final row in scrubbed) {
      sheet.appendRow(headers.map((h) => TextCellValue(row[h]?.toString() ?? '')).toList());
    }
    
    final bytes = Uint8List.fromList(excel.encode()!);
    await _saveFile('$fileName.xlsx', bytes, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }

  /// Prints data to PDF
  static Future<void> printToPdf(String title, List<Map<String, dynamic>> data) async {
    if (data.isEmpty) return;
    final scrubbed = scrubData(data);
    
    final headers = scrubbed.first.keys.toList();
    
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final doc = pw.Document();
        
        doc.addPage(
          pw.MultiPage(
            pageFormat: format,
            build: (context) => [
              pw.Header(level: 0, child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: scrubbed.map((row) => headers.map((h) => row[h]?.toString() ?? '').toList()).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                cellHeight: 30,
                cellAlignments: {
                  for (var i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft,
                },
              ),
            ],
          ),
        );
        
        return doc.save();
      },
    );
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static Future<void> _saveFile(String suggestedName, Uint8List bytes, String mimeType) async {
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location != null) {
      final file = XFile.fromData(bytes, mimeType: mimeType);
      await file.saveTo(location.path);
    }
  }
}
