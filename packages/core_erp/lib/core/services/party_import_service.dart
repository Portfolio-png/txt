import 'dart:convert';
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
    this.sheetName = '',
    this.sheetNames = const <String>[],
    this.headersFound = const <String>[],
    this.dataRowsSeen = 0,
    this.blankRowsSkipped = 0,
    this.exampleRowsSkipped = 0,
  });

  final List<PartyImportRow> rows;

  /// What the parser actually read, so "nothing to import" can explain itself
  /// instead of leaving the user guessing.
  final String sheetName;
  final List<String> sheetNames;
  final List<String> headersFound;
  final int dataRowsSeen;
  final int blankRowsSkipped;
  final int exampleRowsSkipped;

  /// Plain-language account of what the parser saw. Shown when a file yields
  /// no importable rows.
  String get diagnostics {
    final parts = <String>[
      'Read sheet "$sheetName"'
          '${sheetNames.length > 1 ? ' (of: ${sheetNames.join(', ')})' : ''}.',
      'Columns found: ${headersFound.isEmpty ? 'none' : headersFound.join(' | ')}.',
      '$dataRowsSeen row(s) below the header.',
      if (blankRowsSkipped > 0) '$blankRowsSkipped blank row(s) skipped.',
      if (exampleRowsSkipped > 0)
        '$exampleRowsSkipped example row(s) skipped.',
    ];
    return parts.join(' ');
  }

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

    // One example row, and nothing else. An explanatory marker row used to sit
    // underneath, but it read as a stray half-filled record in Excel; the
    // Instructions sheet says the same thing without cluttering the grid.
    // An untouched example is recognised on import and skipped.
    sheet.appendRow(
      columns.map((column) => TextCellValue(column.example)).toList(),
    );

    final help = excel['Instructions'];
    help.appendRow([TextCellValue('How to use this template')]);
    help.appendRow([TextCellValue('')]);
    for (final line in <String>[
      '1. Fill one ${kind.label.toLowerCase()} per row on the "$dataSheetName" sheet.',
      '2. Do not rename, reorder or delete the header row — the importer reads it.',
      '3. Columns marked * are required.',
      '4. Row 2 is an example. Overwrite it or delete it — if left untouched it is ignored on import.',
      '   Only the columns listed below are read; anything you add to the right is ignored.',
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

  /// Extensions the picker should offer.
  ///
  /// `.numbers` is listed on purpose even though it cannot be parsed: a Mac user
  /// whose file is a Numbers document otherwise sees an empty picker and no
  /// explanation. Choosing one produces instructions instead of silence.
  static const List<String> acceptedExtensions = <String>[
    'xlsx',
    'csv',
    'numbers',
  ];

  /// Reads a filled-in template, dispatching on the file's format.
  static PartyImportResult parseFile({
    required String fileName,
    required Uint8List bytes,
    required PartyKind kind,
    required Iterable<String> existingNames,
  }) {
    final lower = fileName.trim().toLowerCase();

    if (lower.endsWith('.numbers')) {
      // Numbers documents are a proprietary bundle of compressed protobufs;
      // there is no reader for them outside Apple's own frameworks. Say so, and
      // point at the two-click way out.
      return const PartyImportResult(
        rows: [],
        headerProblems: [
          'Numbers files cannot be read directly.',
          'In Numbers choose File → Export To → Excel (or CSV), then import '
              'that file.',
        ],
      );
    }

    if (lower.endsWith('.csv')) {
      return parseCsv(bytes, kind, existingNames: existingNames);
    }

    return parse(bytes, kind, existingNames: existingNames);
  }

  /// Reads a CSV export. Numbers, Excel and Sheets all produce these, so it is
  /// the common fallback when the .xlsx path is not available.
  static PartyImportResult parseCsv(
    Uint8List bytes,
    PartyKind kind, {
    required Iterable<String> existingNames,
  }) {
    String text;
    try {
      // Excel on Windows writes a BOM; strip it so the first header does not
      // arrive as "﻿Name".
      text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('﻿')) {
        text = text.substring(1);
      }
    } catch (_) {
      return const PartyImportResult(
        rows: [],
        headerProblems: ['This file could not be read as text.'],
      );
    }

    final grid = _parseCsvGrid(text);
    if (grid.isEmpty) {
      return const PartyImportResult(
        rows: [],
        headerProblems: ['The file has no rows.'],
      );
    }
    return _resultFromGrids(
      {'CSV': grid},
      kind,
      existingNames: existingNames,
    );
  }

  /// RFC 4180-ish reader: honours quoted fields, escaped quotes and newlines
  /// inside quotes, which matter because addresses routinely contain commas.
  static List<List<String>> _parseCsvGrid(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }
      if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        row.add(field.toString());
        field.clear();
      } else if (char == '\n' || char == '\r') {
        // Swallow the \n of a \r\n pair.
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i++;
        }
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(char);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

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
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      return const PartyImportResult(
        rows: [],
        headerProblems: ['This file could not be read as a spreadsheet.'],
      );
    }

    if (excel.tables.isEmpty) {
      return const PartyImportResult(
        rows: [],
        headerProblems: ['The file has no sheets.'],
      );
    }

    /// Text of a cell, whatever type the producing app chose.
    ///
    /// Excel, Numbers and LibreOffice each pick different cell types for the
    /// same visible content — a phone becomes an int, a blank becomes a null or
    /// an empty shared string — so every case funnels to a trimmed string.
    String cellText(Data? cell) {
      final value = cell?.value;
      if (value == null) return '';
      if (value is TextCellValue) return value.value.toString().trim();
      if (value is IntCellValue) return value.value.toString();
      if (value is DoubleCellValue) {
        final d = value.value;
        return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();
      }
      if (value is BoolCellValue) return value.value ? 'true' : 'false';
      if (value is FormulaCellValue) return value.formula.trim();
      return value.toString().trim();
    }

    final grids = <String, List<List<String>>>{
      for (final entry in excel.tables.entries)
        entry.key: entry.value.rows
            .map((row) => row.map(cellText).toList(growable: false))
            .toList(growable: false),
    };
    return _resultFromGrids(grids, kind, existingNames: existingNames);
  }

  /// Turns one or more sheets of plain text into a parse result.
  ///
  /// Shared by the .xlsx and .csv readers so validation, duplicate handling and
  /// header detection cannot diverge between formats.
  ///
  /// The data is located by content, not by sheet name or a fixed header row:
  /// files come back from Excel, Numbers, Sheets and LibreOffice, any of which
  /// may rename a sheet, reorder tabs or leave filler rows above the header.
  static PartyImportResult _resultFromGrids(
    Map<String, List<List<String>>> grids,
    PartyKind kind, {
    required Iterable<String> existingNames,
  }) {
    final columns = columnsFor(kind);
    final rows = <PartyImportRow>[];
    final sheetNames = grids.keys.toList(growable: false);

    String normalizeHeader(String raw) => raw
        .replaceAll('*', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    String cellAt(List<String> row, int index) =>
        (index < 0 || index >= row.length) ? '' : row[index].trim();

    List<List<String>>? bestGrid;
    var bestSheetName = '';
    var bestHeaderRow = -1;
    var bestHeaderIndex = <String, int>{};
    var bestScore = -1;

    for (final entry in grids.entries) {
      final grid = entry.value;
      final scanLimit = grid.length < 10 ? grid.length : 10;
      for (var r = 0; r < scanLimit; r++) {
        final found = <String, int>{};
        for (var i = 0; i < grid[r].length; i++) {
          final text = normalizeHeader(grid[r][i]);
          if (text.isNotEmpty) found.putIfAbsent(text, () => i);
        }
        if (!found.containsKey('name')) {
          continue; // without the required column this row is not a header
        }
        final matched = columns
            .where((c) => found.containsKey(c.header.toLowerCase()))
            .length;
        // Prefer more matched columns, then more rows underneath to import.
        final score = matched * 1000 + (grid.length - r - 1);
        if (score > bestScore) {
          bestScore = score;
          bestGrid = grid;
          bestSheetName = entry.key;
          bestHeaderRow = r;
          bestHeaderIndex = found;
        }
      }
    }

    if (bestGrid == null) {
      return PartyImportResult(
        rows: const [],
        headerProblems: const [
          'Could not find a header row containing "Name".',
          'Use the downloaded template and keep its header row intact.',
        ],
        sheetNames: sheetNames,
      );
    }

    final grid = bestGrid;
    final headerIndex = bestHeaderIndex;
    final headersFound = headerIndex.keys.toList(growable: false);

    var dataRowsSeen = 0;
    var blankRowsSkipped = 0;
    var exampleRowsSkipped = 0;
    final seenNames = <String>{};
    final existing = existingNames
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();

    for (var r = bestHeaderRow + 1; r < grid.length; r++) {
      final row = grid[r];
      final values = <String, String>{
        for (final column in columns)
          column.field: cellAt(row, headerIndex[column.header.toLowerCase()] ?? -1),
      };

      dataRowsSeen++;
      if (values.values.every((value) => value.isEmpty)) {
        blankRowsSkipped++;
        continue; // blank spacer row
      }
      final name = values['name'] ?? '';
      if (name == _exampleMarker || name.startsWith('↑ example')) {
        exampleRowsSkipped++;
        continue;
      }
      // The sample row ships with the documented example values; treat an
      // untouched one as a leftover rather than real data.
      if (columns.every((column) => values[column.field] == column.example)) {
        exampleRowsSkipped++;
        continue;
      }

      final errors = <String>[];
      if (name.isEmpty) {
        errors.add('Name is required.');
      }
      final email = values['email'] ?? '';
      if (email.isNotEmpty &&
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
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

    return PartyImportResult(
      rows: rows,
      headerProblems: const [],
      sheetName: bestSheetName,
      sheetNames: sheetNames,
      headersFound: headersFound,
      dataRowsSeen: dataRowsSeen,
      blankRowsSkipped: blankRowsSkipped,
      exampleRowsSkipped: exampleRowsSkipped,
    );
  }
}
