import 'package:core_erp/features/production_pipelines/domain/pen_paper_baseline.dart';
import 'package:core_erp/features/production_pipelines/domain/raw_stock_form.dart';
import 'package:flutter_test/flutter_test.dart';

// A part can be pressed from a sheet, a strip, a coil or a roll, and keeps a
// plan for each. The sheet is the record's own fields; the other three have a
// width, a pitch, and a length that is undefined until somebody knows it.

const _mm = 1000000; // nanometres

void main() {
  group('RawStockForm', () {
    test('a length is undefined until it is typed', () {
      expect(const RawStockForm(widthNm: 50 * _mm).lengthKnown, isFalse);
      expect(const RawStockForm(lengthNm: 2000 * _mm).lengthKnown, isTrue);
    });

    test('a known length and a pitch count the parts; either missing, none', () {
      const coil = RawStockForm(lengthNm: 2000 * _mm, pitchNm: 3 * _mm);
      expect(coil.partsFromLength(), 666);
      expect(const RawStockForm(pitchNm: 3 * _mm).partsFromLength(), isNull);
      expect(const RawStockForm(lengthNm: 2000 * _mm).partsFromLength(), isNull);
    });

    test('an empty form has no data; thickness and grade alone are the part’s',
        () {
      expect(RawStockForm.empty.hasData, isFalse);
      expect(const RawStockForm(widthNm: _mm).hasData, isTrue);
      expect(const RawStockForm(pitchNm: _mm).hasData, isTrue);
      expect(const RawStockForm(grade: 'First', thicknessNm: _mm).hasData, isFalse);
    });

    test('a fresh form weighs nothing — never the 100 kg worked example', () {
      expect(RawStockForm.empty.reconciliation.inputKg, 0);
      expect(RawStockForm.empty.reconciliation.outputKg, 0);
    });

    test('round-trips through JSON, keeping the part’s grade as it was', () {
      const coil = RawStockForm(
        widthNm: 50 * _mm,
        lengthNm: 2000 * _mm,
        thicknessNm: 800000,
        pitchNm: 3 * _mm,
        widthUnit: 'in',
        lengthUnit: 'm',
        vendorId: 7,
        vendorName: 'Hindalco',
        grade: 'A',
      );
      final back = RawStockForm.fromJson(coil.toJson());
      expect(back.widthNm, 50 * _mm);
      expect(back.lengthNm, 2000 * _mm);
      expect(back.lengthUnit, 'm');
      expect(back.thicknessNm, 800000);
      expect(back.pitchNm, 3 * _mm);
      expect(back.widthUnit, 'in');
      expect(back.vendorId, 7);
      expect(back.vendorName, 'Hindalco');
      expect(back.grade, 'A', reason: 'a Grade column can hold any value');
    });

    test('edge trim and parts across are gone; an old blob still reads', () {
      final old = RawStockForm.fromJson(const {
        'widthNm': 50 * _mm,
        'edgeTrimNm': 2 * _mm,
        'lanes': 3,
      });
      expect(old.widthNm, 50 * _mm);
      expect(old.toJson().containsKey('edgeTrimNm'), isFalse);
      expect(old.toJson().containsKey('lanes'), isFalse);
    });
  });

  group('PenPaperBaseline forms', () {
    test('a plan saved before forms existed reads with none, on the sheet', () {
      final old = PenPaperBaseline.fromJson(const {
        'sheetWidthInches': 48.0,
        'sheetHeightInches': 96.0,
        'materialGrade': 'First',
        'vendorId': 4,
        'vendorName': 'Tata',
      });
      expect(old.forms, isEmpty);
      expect(old.lastForm, RawForm.sheet);
      // The sheet's own vendor and grade are where they always were.
      expect(old.materialGrade, 'First');
      expect(old.vendorName, 'Tata');
      expect(old.hasForm(RawForm.sheet), isTrue);
      expect(old.hasForm(RawForm.coil), isFalse);
    });

    test('each form keeps its own vendor and grade', () {
      final plan = const PenPaperBaseline(
        materialGrade: 'First',
        vendorName: 'Tata',
      ).withForm(
        RawForm.coil,
        const RawStockForm(widthNm: 50 * _mm, vendorName: 'Hindalco', grade: 'Third'),
      );
      expect(plan.vendorName, 'Tata');
      expect(plan.materialGrade, 'First');
      expect(plan.formOf(RawForm.coil).vendorName, 'Hindalco');
      expect(plan.formOf(RawForm.coil).grade, 'Third');
      expect(plan.formOf(RawForm.strip).hasData, isFalse);
    });

    test('forms and the last one worked on survive a round trip; empty ones do not',
        () {
      final plan = const PenPaperBaseline()
          .withForm(RawForm.coil, const RawStockForm(widthNm: 50 * _mm))
          .withForm(RawForm.strip, RawStockForm.empty)
          .copyWith(lastForm: RawForm.coil);
      final json = plan.toJson();
      expect((json['forms'] as Map).keys, ['coil']);

      final back = PenPaperBaseline.fromJson(json);
      expect(back.lastForm, RawForm.coil);
      expect(back.formOf(RawForm.coil).widthNm, 50 * _mm);
      expect(back.forms.containsKey(RawForm.strip), isFalse);
    });

    test('the sheet-wide pitch an older plan kept becomes a band’s own', () {
      final back = PenPaperBaseline.fromJson(const {
        'kerfMm': 3.0,
        'forms': {
          'coil': {'widthNm': 50000000},
          'strip': {'widthNm': 40000000, 'pitchNm': 5000000},
        },
      });
      expect(back.formOf(RawForm.coil).pitchNm, 3 * _mm);
      expect(back.formOf(RawForm.strip).pitchNm, 5 * _mm,
          reason: 'its own pitch wins');
    });

    test('a sheet is never read into forms, even if a blob names one', () {
      final back = PenPaperBaseline.fromJson(const {
        'forms': {
          'sheet': {'widthNm': 1},
          'roll': {'widthNm': 1000000},
        },
      });
      expect(back.forms.keys, [RawForm.roll]);
    });
  });
}
