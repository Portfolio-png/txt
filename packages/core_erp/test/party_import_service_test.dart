import 'dart:convert';
import 'dart:typed_data';

import 'package:core_erp/core/services/party_import_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a filled-in sheet the way a user's saved file looks: the template's
/// header row followed by their own rows.
Uint8List sheetWith(PartyKind kind, List<List<String>> dataRows) {
  final columns = PartyImportService.columnsFor(kind);
  final excel = Excel.createExcel();
  excel.rename(excel.getDefaultSheet()!, kind.pluralLabel);
  final sheet = excel[kind.pluralLabel];
  sheet.appendRow(
    columns
        .map(
          (c) => TextCellValue(c.required ? '${c.header} *' : c.header),
        )
        .toList(),
  );
  for (final row in dataRows) {
    sheet.appendRow(row.map((cell) => TextCellValue(cell)).toList());
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  group('template round-trip', () {
    test('a freshly downloaded template parses with no rows to import', () {
      for (final kind in PartyKind.values) {
        final bytes = PartyImportService.buildTemplate(kind);
        final result = PartyImportService.parse(
          bytes,
          kind,
          existingNames: const [],
        );
        expect(result.headerProblems, isEmpty, reason: '${kind.label} headers');
        // The example rows must not turn into real records.
        expect(result.rows, isEmpty, reason: '${kind.label} example rows');
      }
    });

    test('the template header is readable by the parser', () {
      final bytes = PartyImportService.buildTemplate(PartyKind.vendor);
      final result = PartyImportService.parse(
        bytes,
        PartyKind.vendor,
        existingNames: const [],
      );
      expect(result.headerProblems, isEmpty);
    });
  });

  group('parsing filled sheets', () {
    test('reads valid client rows', () {
      final bytes = sheetWith(PartyKind.client, [
        ['Acme Industries', 'Acme', '27AAACF1234A1ZV', 'Pune'],
        ['Borewell Co', '', '', ''],
      ]);
      final result = PartyImportService.parse(
        bytes,
        PartyKind.client,
        existingNames: const [],
      );
      expect(result.headerProblems, isEmpty);
      expect(result.importable.length, 2);
      expect(result.importable.first.values['name'], 'Acme Industries');
      expect(result.importable.first.values['alias'], 'Acme');
    });

    test('flags a missing name, bad email and short GST', () {
      final bytes = sheetWith(PartyKind.vendor, [
        ['', '', '', '', '', '', ''],
        ['Bad Email Co', '', '', '', '', '', 'not-an-email'],
        ['Short GST Co', '', '123', '', '', '', ''],
      ]);
      final result = PartyImportService.parse(
        bytes,
        PartyKind.vendor,
        existingNames: const [],
      );
      // The all-blank row is skipped as a spacer, not reported as an error.
      expect(result.rows.length, 2);
      expect(result.importable, isEmpty);
      expect(result.rejected[0].errors.single, contains('not a valid address'));
      expect(result.rejected[1].errors.single, contains('15 characters'));
    });

    test('skips names that already exist, and flags repeats within the file', () {
      final bytes = sheetWith(PartyKind.client, [
        ['Existing Client', '', '', ''],
        ['Fresh Client', '', '', ''],
        ['Fresh Client', '', '', ''],
      ]);
      final result = PartyImportService.parse(
        bytes,
        PartyKind.client,
        existingNames: const ['  existing client  '],
      );
      expect(result.rows[0].isDuplicate, isTrue);
      expect(result.rows[1].isValid, isTrue);
      expect(result.rows[2].errors.single, contains('Repeated'));
      expect(result.importable.length, 1);
    });

    test('reports a renamed required column instead of importing nothing', () {
      final excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'Clients');
      excel['Clients'].appendRow([
        TextCellValue('Company'), // should be "Name"
        TextCellValue('Alias'),
      ]);
      excel['Clients'].appendRow([
        TextCellValue('Acme'),
        TextCellValue('A'),
      ]);
      final result = PartyImportService.parse(
        Uint8List.fromList(excel.encode()!),
        PartyKind.client,
        existingNames: const [],
      );
      // Detection is by content now: with no "Name" heading anywhere, there is
      // no header row to anchor to, and that is what gets reported.
      expect(
        result.headerProblems.first,
        contains('Could not find a header row'),
      );
      expect(result.isUsable, isFalse);
    });

    test('tolerates a renamed sheet and numeric-looking cells', () {
      final excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'Sheet1');
      excel['Sheet1'].appendRow([
        TextCellValue('name'), // lower case, no asterisk
        TextCellValue('Alias'),
        TextCellValue('GST Number'),
        TextCellValue('Address'),
        TextCellValue('Contact Name'),
        TextCellValue('Phone'),
        TextCellValue('Email'),
      ]);
      excel['Sheet1'].appendRow([
        TextCellValue('Numeric Phone Co'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        IntCellValue(9820012345),
        TextCellValue(''),
      ]);
      final result = PartyImportService.parse(
        Uint8List.fromList(excel.encode()!),
        PartyKind.vendor,
        existingNames: const [],
      );
      expect(result.headerProblems, isEmpty);
      expect(result.importable.single.values['phone'], '9820012345');
    });

    test('ignores extra columns beyond the template, headed or not', () {
      final excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'Clients');
      final sheet = excel['Clients'];
      sheet.appendRow([
        TextCellValue('Name *'),
        TextCellValue('Alias'),
        TextCellValue('GST Number'),
        TextCellValue('Address'),
        TextCellValue(''), // blank header, as a previewer suggests
        TextCellValue('Notes to self'), // a column the user added
      ]);
      sheet.appendRow([
        TextCellValue('Acme Industries'),
        TextCellValue('Acme'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('scribble'),
        TextCellValue('call them Monday'),
      ]);
      // A row with content ONLY in an unmapped column must not become a record.
      sheet.appendRow([
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('stray note'),
        TextCellValue(''),
      ]);

      final result = PartyImportService.parse(
        Uint8List.fromList(excel.encode()!),
        PartyKind.client,
        existingNames: const [],
      );
      expect(result.headerProblems, isEmpty);
      expect(result.rows.length, 1, reason: 'stray-note row must be skipped');
      expect(result.importable.single.values['name'], 'Acme Industries');
      expect(result.importable.single.values.containsKey('Notes to self'), isFalse);
    });

    test('finds the data when a re-save renamed the sheet and moved tabs', () {
      // What Numbers/LibreOffice can produce: instructions first, data sheet
      // renamed, and a blank row above the header.
      final excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'Instructions');
      excel['Instructions'].appendRow([TextCellValue('How to use this')]);
      final data = excel['Sheet1 (2)'];
      data.appendRow([TextCellValue('')]); // stray blank row above the header
      data.appendRow([
        TextCellValue('Name *'),
        TextCellValue('Alias'),
        TextCellValue('GST Number'),
        TextCellValue('Address'),
      ]);
      data.appendRow([TextCellValue('Acme Industries')]);
      data.appendRow([TextCellValue('Borewell Co')]);

      final result = PartyImportService.parse(
        Uint8List.fromList(excel.encode()!),
        PartyKind.client,
        existingNames: const [],
      );
      expect(result.headerProblems, isEmpty);
      expect(result.sheetName, 'Sheet1 (2)');
      expect(result.importable.length, 2);
      // Row numbers must still match what the user sees in the sheet.
      expect(result.importable.first.rowNumber, 3);
    });

    test('picks the data sheet over an instructions sheet', () {
      final excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'Instructions');
      excel['Instructions'].appendRow([TextCellValue('Column'), TextCellValue('Notes')]);
      excel['Instructions'].appendRow([TextCellValue('Name'), TextCellValue('Required.')]);
      final data = excel['Clients'];
      data.appendRow([TextCellValue('Name *'), TextCellValue('Alias')]);
      data.appendRow([TextCellValue('Acme Industries')]);

      final result = PartyImportService.parse(
        Uint8List.fromList(excel.encode()!),
        PartyKind.client,
        existingNames: const [],
      );
      expect(result.sheetName, 'Clients');
      expect(result.importable.single.name, 'Acme Industries');
    });

    test('reports when no sheet carries a Name header', () {
      final excel = Excel.createExcel();
      excel.rename(excel.getDefaultSheet()!, 'Sheet1');
      excel['Sheet1'].appendRow([TextCellValue('Company'), TextCellValue('City')]);
      excel['Sheet1'].appendRow([TextCellValue('Acme'), TextCellValue('Pune')]);

      final result = PartyImportService.parse(
        Uint8List.fromList(excel.encode()!),
        PartyKind.client,
        existingNames: const [],
      );
      expect(result.headerProblems.first, contains('Could not find a header row'));
      expect(result.sheetNames, contains('Sheet1'));
    });

    test('reads a CSV export, including quoted commas', () {
      const csv = 'Name *,Alias,GST Number,Address\n'
          'Acme Industries,Acme,,"Plot 14, MIDC, Pune"\n'
          'Borewell Co,,,\n';
      final result = PartyImportService.parseFile(
        fileName: 'clients.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        kind: PartyKind.client,
        existingNames: const [],
      );
      expect(result.headerProblems, isEmpty);
      expect(result.importable.length, 2);
      // The comma-bearing address must survive as one field.
      expect(
        result.importable.first.values['address'],
        'Plot 14, MIDC, Pune',
      );
      expect(result.importable.last.values['name'], 'Borewell Co');
    });

    test('strips a BOM so the first header still matches', () {
      const csv = '﻿Name *,Alias,GST Number,Address\nAcme,,,\n';
      final result = PartyImportService.parseFile(
        fileName: 'clients.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        kind: PartyKind.client,
        existingNames: const [],
      );
      expect(result.headerProblems, isEmpty);
      expect(result.importable.single.name, 'Acme');
    });

    test('a .numbers file explains how to convert instead of failing', () {
      final result = PartyImportService.parseFile(
        fileName: 'clients.numbers',
        bytes: Uint8List.fromList(const [0, 1, 2, 3]),
        kind: PartyKind.client,
        existingNames: const [],
      );
      expect(result.headerProblems.first, contains('cannot be read directly'));
      expect(result.headerProblems.join(' '), contains('Export To'));
    });

    test('xlsx and csv agree on validation and duplicates', () {
      const csv = 'Name *,Alias,GST Number,Address\n'
          'Existing Client,,,\n'
          'Bad GST Co,,123,\n';
      final result = PartyImportService.parseFile(
        fileName: 'clients.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        kind: PartyKind.client,
        existingNames: const ['existing client'],
      );
      expect(result.rows[0].isDuplicate, isTrue);
      expect(result.rows[1].errors.single, contains('15 characters'));
      expect(result.importable, isEmpty);
    });

    test('a file that is not a spreadsheet is reported, not thrown', () {
      final result = PartyImportService.parse(
        Uint8List.fromList('this is not xlsx'.codeUnits),
        PartyKind.client,
        existingNames: const [],
      );
      expect(result.headerProblems, isNotEmpty);
      expect(result.isUsable, isFalse);
    });
  });
}
