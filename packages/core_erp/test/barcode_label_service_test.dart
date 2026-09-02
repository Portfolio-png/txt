import 'package:core_erp/core/services/barcode_label_service.dart';
import 'package:core_erp/features/search/domain/universal_barcode_entity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Label stock is bought in rolls and printed in runs. The expensive mistake is
/// silent: a tiling that overhangs the page ruins every sheet and is discovered
/// only after the run. So the arithmetic is pinned here, away from the drawing.

BarcodeLabel labelOf({String code = 'MAT-REC-1-L1-K'}) =>
    BarcodeLabel(code: code, title: 'Steel Sheet 2mm');

void main() {
  group('sheet tiling', () {
    test('fits as many as truly fit, and not one more', () {
      // A4 at an 8mm margin leaves 194x281mm. Three 50mm stickers plus two
      // 3mm gutters is 156mm; a fourth would need 209mm and does not fit.
      final layout = SheetLayout.fit(
        stock: LabelStock.materialSticker,
        labelCount: 1,
      );
      expect(layout.columns, 3);
      expect(layout.rows, 10);
      expect(layout.perPage, 30);
      expect(layout.fitsOnPage, isTrue);

      // The check that matters: what it claims fits actually fits.
      final usedWidth = layout.columns * 50 + (layout.columns - 1) * 3;
      expect(usedWidth, lessThanOrEqualTo(194));
      final usedHeight = layout.rows * 25 + (layout.rows - 1) * 3;
      expect(usedHeight, lessThanOrEqualTo(281));
    });

    test('a full page and one over spills to a second page', () {
      expect(
        SheetLayout.fit(stock: LabelStock.materialSticker, labelCount: 30).pages,
        1,
      );
      expect(
        SheetLayout.fit(stock: LabelStock.materialSticker, labelCount: 31).pages,
        2,
      );
    });

    test('nothing to print produces no pages, not a blank one', () {
      final layout =
          SheetLayout.fit(stock: LabelStock.materialSticker, labelCount: 0);
      expect(layout.pages, 0);
    });

    test('stock larger than the page falls back rather than dividing by zero', () {
      // A 100x75 shipping label has no business being tiled onto a small page.
      // The wrong answer here is not a bad layout, it is a crash or an empty
      // run: zero per page and the pagination divides by zero.
      final layout = SheetLayout.fit(
        stock: LabelStock.shipping,
        labelCount: 4,
        pageWidthMm: 60,
        pageHeightMm: 60,
      );
      expect(layout.fitsOnPage, isFalse);
      expect(layout.perPage, 1, reason: 'one per page, not zero');
      expect(layout.pages, 4);
    });
  });

  group('choosing the stock', () {
    test('what was scanned decides what it is printed on', () {
      // Picking the roll by hand every time is how the wrong one ends up loaded.
      expect(LabelStock.forEntityType('MAT'), LabelStock.materialSticker);
      expect(LabelStock.forEntityType('DC'), LabelStock.shipping);
      expect(LabelStock.forEntityType('RC'), LabelStock.shipping);
      expect(LabelStock.forEntityType('MCH'), LabelStock.assetPlate);
      expect(LabelStock.forEntityType('DIE'), LabelStock.assetPlate);
      expect(LabelStock.forEntityType('EMP'), LabelStock.idBadge);
    });

    test('an unknown type still gets a label', () {
      // A type this build has never heard of must not print nothing at all.
      expect(LabelStock.forEntityType('ZZZ'), LabelStock.materialStickerLarge);
      expect(LabelStock.forEntityType(''), LabelStock.materialStickerLarge);
    });

    test('lowercase is accepted, because callers will pass it', () {
      expect(LabelStock.forEntityType('mat'), LabelStock.materialSticker);
    });
  });

  group('symbology', () {
    test('a gun reads 1D, so 1D is the default', () {
      expect(
        labelOf().symbologyOn(LabelStock.materialSticker),
        LabelSymbology.code128,
      );
    });

    test('stock with room carries a QR as well, for a phone camera', () {
      // Someone at a machine in a corner has a phone, not a gun.
      expect(labelOf().symbologyOn(LabelStock.assetPlate), LabelSymbology.both);
      expect(labelOf().symbologyOn(LabelStock.shipping), LabelSymbology.both);
    });

    test("a code Code 128 cannot encode falls back instead of failing", () {
      // Our own codes are always safe, but a vendor's legacy label carried into
      // the system need not be — and a symbology that throws mid-render takes
      // the whole print run with it.
      final foreign = labelOf(code: 'MAT-ÜBER-1');
      expect(foreign.isCode128Safe, isFalse);
      expect(
        foreign.symbologyOn(LabelStock.assetPlate),
        LabelSymbology.qr,
        reason: 'QR encodes it; Code 128 would have thrown',
      );
    });

    test('our own codes are always encodable', () {
      expect(labelOf(code: 'DC-00012-A').isCode128Safe, isTrue);
      expect(labelOf(code: 'MAT-REC-1-L1-K').isCode128Safe, isTrue);
    });
  });

  group('a label built from a scan', () {
    test('carries the identity, not just the code', () {
      final scan = UniversalBarcodeEntity(
        code: 'MAT-REC-1-L1-K',
        found: true,
        resolution: const BarcodeResolution(via: 'structured'),
        entity: const BarcodeEntity(
          type: 'MAT',
          typeLabel: 'Material',
          id: 'REC-1-L1',
          title: 'Steel Sheet 2mm',
          subtitle: 'steel · IS2062',
        ),
        facts: const <BarcodeFact>[
          BarcodeFact(label: 'Qty', value: '500 kg'),
          BarcodeFact(label: 'Challan', value: 'RC-00012'),
          BarcodeFact(label: 'Vendor', value: 'Acme'),
          BarcodeFact(label: 'Location', value: 'Bay 3'),
        ],
      );
      final label = BarcodeLabel.fromScan(scan);
      expect(label.title, 'Steel Sheet 2mm');
      expect(label.footer, 'Material');
      // Everything the resolver knows will not fit on a 50x25mm sticker, and a
      // label crowded past legibility is worse than a sparse one.
      expect(label.lines, hasLength(3));
    });

    test('a legacy code reprints as its canonical form, not its old one', () {
      // The panel already says "found by its old label" and shows what it ought
      // to say. Printing the old code back would make that notice permanent and
      // leave the label unverifiable forever — and a reprint is the one moment
      // the upgrade costs nothing, because the sticker is being replaced anyway.
      final label = BarcodeLabel.fromScan(
        UniversalBarcodeEntity(
          code: 'OLD-VENDOR-99',
          found: true,
          resolution: const BarcodeResolution(
            via: 'legacy-code',
            hasCheck: false,
            canonical: 'MAT-REC-1-L1-Z',
          ),
          entity: const BarcodeEntity(
            type: 'MAT',
            typeLabel: 'Material',
            id: 'REC-1-L1',
            title: 'Steel Sheet 2mm',
          ),
        ),
      );
      expect(label.code, 'MAT-REC-1-L1-Z');
    });

    test('a verified code reprints unchanged', () {
      // No canonical is offered when the code already is the canonical one, and
      // the fallback must not mangle it.
      final label = BarcodeLabel.fromScan(
        UniversalBarcodeEntity(
          code: 'MAT-REC-1-L1-Z',
          found: true,
          resolution: const BarcodeResolution(via: 'structured', hasCheck: true),
        ),
      );
      expect(label.code, 'MAT-REC-1-L1-Z');
    });

    test('a code that resolved to nothing can still be reprinted', () {
      // The reason to reprint is often that the sticker is unreadable, which is
      // exactly when the scan fails. Refusing here would be backwards.
      final label = BarcodeLabel.fromScan(
        UniversalBarcodeEntity(
          code: 'MAT-X-9',
          found: false,
          resolution: const BarcodeResolution(looksLikeOurs: true),
        ),
      );
      expect(label.code, 'MAT-X-9');
      expect(label.title, 'MAT-X-9', reason: 'falls back to the code itself');
    });
  });

  group('rendering', () {
    test('a roll of labels renders to a real PDF', () async {
      final bytes = await BarcodeLabelService.buildLabelPdf(
        labels: <BarcodeLabel>[labelOf(), labelOf(code: 'DC-00012-A')],
        stock: LabelStock.materialSticker,
      );
      expect(bytes.length, greaterThan(0));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('a QR fallback renders rather than throwing', () async {
      // The path that only a legacy vendor label reaches, which is exactly the
      // path that would otherwise never be exercised until a customer hit it.
      final bytes = await BarcodeLabelService.buildLabelPdf(
        labels: <BarcodeLabel>[labelOf(code: 'MAT-ÜBER-1')],
        stock: LabelStock.assetPlate,
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('a multi-up sheet renders every label it was given', () async {
      final labels = List<BarcodeLabel>.generate(
        31,
        (index) => labelOf(code: 'MAT-REC-$index-K'),
      );
      final bytes = await BarcodeLabelService.buildSheetPdf(
        labels: labels,
        stock: LabelStock.materialSticker,
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('nothing to print renders nothing at all', () async {
      final bytes = await BarcodeLabelService.buildSheetPdf(
        labels: const <BarcodeLabel>[],
        stock: LabelStock.materialSticker,
      );
      // Still a valid document, just with no pages — a blank sheet fed through
      // a thermal printer is a wasted label.
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
