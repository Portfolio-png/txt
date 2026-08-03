import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Which master an import targets. Clients and vendors share the flow and
/// differ only in their columns.
enum PartyKind { client, vendor }

extension PartyKindX on PartyKind {
  String get label => this == PartyKind.client ? 'Client' : 'Vendor';
  String get pluralLabel => this == PartyKind.client ? 'Clients' : 'Vendors';
  String get templateFileName =>
      this == PartyKind.client ? 'clients-import-template' : 'vendors-import-template';
}

/// One spreadsheet column, mapped to a field on the create input.
class PartyColumn {
  const PartyColumn({
    required this.header,
    required this.field,
    this.required = false,
    this.hint = '',
    this.example = '',
  });

  final String header;
  final String field;
  final bool required;
  final String hint;
  final String example;
}

/// A parsed spreadsheet row, with whatever is wrong with it.
class PartyImportRow {
  PartyImportRow({
    required this.rowNumber,
    required this.values,
    required this.errors,
    required this.isDuplicate,
  });

  /// 1-based row number as it appears in Excel, so messages match what the user
  /// sees in the sheet.
  final int rowNumber;
  final Map<String, String> values;
  final List<String> errors;

  /// Matches the name of a record that already exists.
  final bool isDuplicate;

  String get name => values['name'] ?? '';
  bool get isValid => errors.isEmpty && !isDuplicate;
}

class PartyImportResult {
  const PartyImportResult({
    required this.rows,
    required this.headerProblems,
  });

  final List<PartyImportRow> rows;

  /// Problems with the sheet itself (missing/renamed columns), which make the
  /// whole file unusable rather than a single row.
  final List<String> headerProblems;

  List<PartyImportRow> get importable =>
      rows.where((row) => row.isValid).toList(growable: false);
  List<PartyImportRow> get rejected =>
      rows.where((row) => !row.isValid).toList(growable: false);
  bool get isUsable => headerProblems.isEmpty && rows.isNotEmpty;
}

/// Builds the import templates and reads filled-in ones back.
///
/// The template a user downloads and the parser that reads it are defined from
/// one column list, so a renamed or added column cannot drift between them.
class PartyImportService {
  static const List<PartyColumn> clientColumns = <PartyColumn>[
    PartyColumn(
      header: 'Name',
      field: 'name',
      required: true,
      hint: 'Required. Must be unique.',
      example: 'Fibrous Pvt. Ltd.',
    ),
    PartyColumn(
      header: 'Alias',
      field: 'alias',
      hint: 'Optional short name used in lists.',
      example: 'Fibrous',
    ),
    PartyColumn(
      header: 'GST Number',
      field: 'gstNumber',
      hint: 'Optional. 15 characters.',
      example: '27AAACF1234A1ZV',
    ),
    PartyColumn(
      header: 'Address',
      field: 'address',
      hint: 'Optional.',
      example: 'Plot 14, MIDC, Pune',
    ),
  ];

  static const List<PartyColumn> vendorColumns = <PartyColumn>[
    PartyColumn(
      header: 'Name',
      field: 'name',
      required: true,
      hint: 'Required. Must be unique.',
      example: 'Shree Steel Traders',
    ),
    PartyColumn(
      header: 'Alias',
      field: 'alias',
      hint: 'Optional short name used in lists.',
      example: 'Shree Steel',
    ),
    PartyColumn(
      header: 'GST Number',
      field: 'gstNumber',
      hint: 'Optional. 15 characters.',
      example: '27AABCS9876B1Z3',
    ),
    PartyColumn(
      header: 'Address',
      field: 'address',
      hint: 'Optional.',
      example: 'Gat 22, Chakan, Pune',
    ),
    PartyColumn(
      header: 'Contact Name',
      field: 'contactName',
      hint: 'Optional.',
      example: 'R. Kulkarni',
    ),
    PartyColumn(
      header: 'Phone',
      field: 'phone',
      hint: 'Optional. Digits, spaces and + only.',
      example: '+91 98200 12345',
    ),
    PartyColumn(
      header: 'Email',
      field: 'email',
      hint: 'Optional.',
      example: 'sales@shreesteel.example',
    ),
  ];

  static List<PartyColumn> columnsFor(PartyKind kind) =>
      kind == PartyKind.client ? clientColumns : vendorColumns;

  /// Builds the downloadable .xlsx.
  ///
  /// Two sheets: the data sheet the user fills in, and an instructions sheet
  /// explaining each column. Example rows are included because a blank grid
  /// leaves people guessing at the format — they are marked and the parser
  /// ignores them, so forgetting to delete them costs nothing.
  static Uint8List buildTemplate(PartyKind kind) {
    final columns = columnsFor(kind);
    final excel = Excel.createExcel();

    final dataSheetName = kind.pluralLabel;
    excel.rename(excel.getDefaultSheet()!, dataSheetName);
    final sheet = excel[dataSheetName];

    sheet.appendRow(
      columns
          .map(
            (column) => TextCellValue(
              column.required ? '${column.header} *' : column.header,
            ),
          )
          .toList(),
    );
    for (final column in columns) {
      sheet.setColumnWidth(columns.indexOf(column), 26);
    }

    sheet.appendRow(
      columns.map((column) => TextCellValue(column.example)).toList(),
    );
    sheet.appendRow(
      columns
          .map(
            (column) => TextCellValue(
              column.field == 'name' ? _exampleMarker : '',
            ),
          )
          .toList(),
    );

    final help = excel['Instructions'];
    help.appendRow([TextCellValue('How to use this template')]);
    help.appendRow([TextCellValue('')]);
    for (final line in <String>[
      '1. Fill one ${kind.label.toLowerCase()} per row on the "$dataSheetName" sheet.',
      '2. Do not rename, reorder or delete the header row — the importer reads it.',
      '3. Columns marked * are required.',
      '4. The grey example rows can be left in place; they are ignored on import.',
      '5. Names that already exist in the app are reported and skipped, never duplicated.',
      '6. Save as .xlsx and import from the ${kind.pluralLabel} screen.',
    ]) {
      help.appendRow([TextCellValue(line)]);
    }
    help.appendRow([TextCellValue('')]);
    help.appendRow([TextCellValue('Column'), TextCellValue('Notes')]);
    for (final column in columns) {
      help.appendRow([TextCellValue(column.header), TextCellValue(column.hint)]);
    }
    help.setColumnWidth(0, 24);
    help.setColumnWidth(1, 54);

    return Uint8List.fromList(excel.encode()!);
  }

  /// Rows whose name cell is this are template samples, not real data.
  static const String _exampleMarker = '↑ example row — delete or leave, it is ignored';

  /// Reads a filled-in template.
  ///
  /// [existingNames] is used to flag rows that would duplicate a record that is
  /// already there; those are reported and skipped rather than creating a
  /// second copy.
  static PartyImportResult parse(
    Uint8List bytes,
    PartyKind kind, {
    required Iterable<String> existingNames,
  }) {
    final columns = columnsFor(kind);
    final headerProblems = <String>[];
    final rows = <PartyImportRow>[];

    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (error) {
      return PartyImportResult(
        rows: const [],
        headerProblems: ['This file could not be read as a spreadsheet.'],
      );
    }

    // Prefer the sheet the template ships with; otherwise take the first one
    // with content, so a re-saved or renamed file still imports.
    final sheet =
        excel.tables[kind.pluralLabel] ??
        excel.tables.values
            .where((table) => table.maxRows > 0)
            .firstOrNull;
    if (sheet == null || sheet.maxRows == 0) {
      return PartyImportResult(
        rows: const [],
        headerProblems: ['The file has no rows.'],
      );
    }

    String cellText(List<Data?> row, int index) {
      if (index < 0 || index >= row.length) return '';
      final value = row[index]?.value;
      if (value == null) return '';
      if (value is TextCellValue) return value.value.toString().trim();
      if (value is IntCellValue) return value.value.toString();
      if (value is DoubleCellValue) {
        final d = value.value;
        return d == d.roundToDouble()
            ? d.toStringAsFixed(0)
            : d.toString();
      }
      return value.toString().trim();
    }

    // Map headers by normalized text, so "Name *", "name" and " NAME " all match.
    final headerRow = sheet.rows.first;
    final headerIndex = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final text = cellText(headerRow, i)
          .replaceAll('*', '')
          .trim()
          .toLowerCase();
      if (text.isNotEmpty) {
        headerIndex.putIfAbsent(text, () => i);
      }
    }
    for (final column in columns.where((c) => c.required)) {
      if (!headerIndex.containsKey(column.header.toLowerCase())) {
        headerProblems.add('Missing required column "${column.header}".');
      }
    }
    if (headerProblems.isNotEmpty) {
      return PartyImportResult(rows: const [], headerProblems: headerProblems);
    }

    final seenNames = <String>{};
    final existing = existingNames
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();

    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final values = <String, String>{};
      for (final column in columns) {
        values[column.field] =
            cellText(row, headerIndex[column.header.toLowerCase()] ?? -1);
      }

      if (values.values.every((value) => value.isEmpty)) {
        continue; // blank spacer row
      }
      final name = values['name'] ?? '';
      if (name == _exampleMarker || name.startsWith('↑ example')) {
        continue;
      }
      // The sample row ships with the documented example name; treat an
      // untouched one as a leftover rather than real data.
      final isUntouchedSample = columns.every(
        (column) => values[column.field] == column.example,
      );
      if (isUntouchedSample) {
        continue;
      }

      final errors = <String>[];
      if (name.isEmpty) {
        errors.add('Name is required.');
      }
      final email = values['email'] ?? '';
      if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        errors.add('Email "$email" is not a valid address.');
      }
      final gst = values['gstNumber'] ?? '';
      if (gst.isNotEmpty && gst.length != 15) {
        errors.add('GST number should be 15 characters (got ${gst.length}).');
      }

      final normalized = name.toLowerCase();
      var duplicate = false;
      if (name.isNotEmpty) {
        if (existing.contains(normalized)) {
          duplicate = true;
        } else if (!seenNames.add(normalized)) {
          errors.add('Repeated in this file.');
        }
      }

      rows.add(
        PartyImportRow(
          rowNumber: r + 1,
          values: values,
          errors: errors,
          isDuplicate: duplicate,
        ),
      );
    }

    return PartyImportResult(rows: rows, headerProblems: headerProblems);
  }
}
