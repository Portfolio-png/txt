import 'package:flutter/material.dart';
import 'package:core_erp/core/services/export_service.dart';

class PrintIntent extends Intent {
  const PrintIntent();
}

class ExportPreviewDialog extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> data;

  const ExportPreviewDialog({
    super.key,
    required this.title,
    required this.data,
  });

  static Future<void> show(BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> data,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ExportPreviewDialog(title: title, data: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    // We only preview the first 5 rows, and we scrub them so the preview matches the export
    final scrubbedData = ExportService.scrubData(data);
    final previewData = scrubbedData.take(5).toList();
    final hasData = previewData.isNotEmpty;
    final headers = hasData ? previewData.first.keys.toList() : <String>[];

    return AlertDialog(
      title: Text('Export $title'),
      content: SizedBox(
        width: 800,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Preview (First 5 rows):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (!hasData)
              const Text('No data to export.')
            else
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
                        columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
                        rows: previewData.map((row) {
                          return DataRow(
                            cells: headers.map((h) => DataCell(Text(row[h]?.toString() ?? ''))).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            const Text('Select export format:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text('Print / PDF'),
                  onPressed: hasData ? () {
                    Navigator.of(context).pop();
                    ExportService.printToPdf(title, data);
                  } : null,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Excel'),
                  onPressed: hasData ? () {
                    Navigator.of(context).pop();
                    ExportService.exportToExcel(title, data);
                  } : null,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.list_alt),
                  label: const Text('CSV'),
                  onPressed: hasData ? () {
                    Navigator.of(context).pop();
                    ExportService.exportToCsv(title, data);
                  } : null,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.data_object),
                  label: const Text('JSON'),
                  onPressed: hasData ? () {
                    Navigator.of(context).pop();
                    ExportService.exportToJson(title, data);
                  } : null,
                ),
              ],
            )
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
