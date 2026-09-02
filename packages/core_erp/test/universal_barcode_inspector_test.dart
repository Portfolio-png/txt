import 'package:barcode_widget/barcode_widget.dart';
import 'package:core_erp/core/services/barcode_label_service.dart';
import 'package:core_erp/core/widgets/universal_barcode_inspector_dialog.dart';
import 'package:core_erp/features/search/domain/universal_barcode_entity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One screen for every kind of code, because the scanner gun does not know
/// what it is pointed at and neither does the person holding it.
///
/// What is asserted here is mostly about *honesty*: a scan that failed its check
/// character, one found by an old label, and one that matched nothing all look
/// superficially similar, and the whole value of the resolver is lost if the
/// screen renders them the same way.

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

UniversalBarcodeEntity scanOf({
  bool found = true,
  String via = 'structured',
  bool hasCheck = true,
  bool checkValid = true,
  bool looksLikeOurs = true,
  String? canonical,
  List<CustodyEvent> custody = const <CustodyEvent>[],
}) {
  return UniversalBarcodeEntity(
    code: 'MAT-REC-1-L1-K',
    found: found,
    resolution: BarcodeResolution(
      via: found ? via : null,
      looksLikeOurs: looksLikeOurs,
      hasCheck: hasCheck,
      checkValid: checkValid,
      canonical: canonical,
    ),
    entity: found
        ? const BarcodeEntity(
            type: 'MAT',
            typeLabel: 'Material',
            id: 'REC-1-L1',
            title: 'Steel Sheet 2mm',
            subtitle: 'steel · IS2062',
          )
        : null,
    facts: found
        ? const <BarcodeFact>[BarcodeFact(label: 'Type', value: 'Material')]
        : const <BarcodeFact>[],
    custody: custody,
  );
}

void main() {
  testWidgets('a scan shows what it is and how it resolved', (tester) async {
    await tester.pumpWidget(host(UniversalBarcodeInspector(scan: scanOf())));
    await tester.pumpAndSettle();

    expect(find.text('Steel Sheet 2mm'), findsOneWidget);
    expect(find.textContaining('Material'), findsWidgets);
    // Verified by its check character — the tick says the code on the label is
    // the code that was printed.
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
  });

  testWidgets('a failed check character is called out, not glossed over', (
    tester,
  ) async {
    // The record is still shown — refusing outright is less useful than saying
    // "this is what it would be, check it is what you are holding".
    await tester.pumpWidget(
      host(UniversalBarcodeInspector(scan: scanOf(checkValid: false))),
    );
    await tester.pumpAndSettle();

    expect(find.text('This code did not check out'), findsOneWidget);
    expect(find.textContaining('check it is what you are actually holding'),
        findsOneWidget);
    expect(find.text('Steel Sheet 2mm'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsNothing);
  });

  testWidgets('a code found by its old label says so, and offers the new one', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        UniversalBarcodeInspector(
          scan: scanOf(via: 'legacy-code', hasCheck: false, canonical: 'MAT-X-9'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Found by its old label'), findsOneWidget);
    expect(find.textContaining('MAT-X-9'), findsOneWidget);
  });

  testWidgets('not-found distinguishes ours from a stranger\'s label', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(UniversalBarcodeInspector(scan: scanOf(found: false))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('This is one of ours'), findsOneWidget);

    await tester.pumpWidget(
      host(
        UniversalBarcodeInspector(
          scan: scanOf(found: false, looksLikeOurs: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The distinction the old lookup could not draw, and the reason scanning a
    // sheet you were holding was indistinguishable from scanning gibberish.
    expect(find.textContaining("supplier's own label"), findsOneWidget);
  });

  testWidgets('an empty trail says so rather than showing nothing', (
    tester,
  ) async {
    await tester.pumpWidget(host(UniversalBarcodeInspector(scan: scanOf())));
    await tester.pumpAndSettle();
    // Nothing recorded is a fact about the record. A section that simply
    // renders nothing looks identical to one that is broken.
    expect(find.textContaining('Nothing has been recorded'), findsOneWidget);
  });

  testWidgets('the trail reads in order and can be walked', (tester) async {
    final followed = <String>[];
    await tester.pumpWidget(
      host(
        UniversalBarcodeInspector(
          onFollowBarcode: followed.add,
          scan: scanOf(
            custody: const <CustodyEvent>[
              CustodyEvent(
                eventId: 'e1',
                eventType: 'INWARD_RECEIVED',
                at: '2026-08-01T10:00:00Z',
                actor: 'Ramesh',
                documentBarcode: 'RC-00012-A',
                metrics: <String, dynamic>{'qty': 500},
              ),
              CustodyEvent(
                eventId: 'e2',
                eventType: 'ISSUED_TO_PIPELINE',
                at: '2026-08-02T09:00:00Z',
                actor: 'Sunil',
                children: <String>['RUN-42-B'],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Event names in words, not the raw constant.
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Issued to production'), findsOneWidget);
    expect(find.textContaining('by Ramesh'), findsOneWidget);
    expect(find.textContaining('qty: 500'), findsOneWidget);

    // And every barcode the trail mentions is a step you can take — this is
    // what makes it a chain rather than a list.
    await tester.tap(find.text('RC-00012-A'));
    await tester.pumpAndSettle();
    expect(followed, <String>['RC-00012-A']);
  });

  test('an unknown event type is shown, not dropped', () {
    // A workshop will record something this build has never heard of. Showing
    // it verbatim beats hiding it because it did not parse.
    const event = CustodyEvent(
      eventId: 'e',
      eventType: 'QUARANTINE_HELD',
      at: '2026-08-01',
    );
    expect(event.label, 'Quarantine held');
  });

  testWidgets('the code is rendered as something a scanner can read', (
    tester,
  ) async {
    await tester.pumpWidget(host(UniversalBarcodeInspector(scan: scanOf())));
    await tester.pumpAndSettle();
    // QR to carry the code to a phone, 1D to compare against the sticker in
    // your hand — which is what is actually printed on it.
    expect(find.byType(BarcodeWidget), findsNWidgets(2));
  });

  testWidgets('a code that will not encode does not take the panel down', (
    tester,
  ) async {
    // A legacy vendor label outside Code 128 is precisely the case someone
    // opens this panel to investigate. The panel explaining a scan must not
    // itself be the thing that fails.
    await tester.pumpWidget(
      host(
        UniversalBarcodeInspector(
          scan: UniversalBarcodeEntity(
            code: 'VENDOR-ÜBER-99',
            found: false,
            resolution: const BarcodeResolution(looksLikeOurs: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining("supplier's own label"), findsOneWidget);
  });

  testWidgets('a scan can be put back onto physical stock', (tester) async {
    // The loop that makes any of this usable: scan a rubbed-out sticker, see
    // what it was, print a fresh one.
    final printed = <(String, LabelStock)>[];
    await tester.pumpWidget(
      host(
        UniversalBarcodeInspector(
          scan: scanOf(),
          onPrintLabel: (label, stock) async {
            printed.add((label.code, stock));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Defaulted to the stock that suits a material, not to whatever is first in
    // the list — picking the roll by hand every time is how the wrong one gets
    // loaded.
    expect(find.text(LabelStock.materialSticker.description), findsOneWidget);

    await tester.tap(find.text('Print label'));
    await tester.pumpAndSettle();
    expect(printed, <(String, LabelStock)>[
      ('MAT-REC-1-L1-K', LabelStock.materialSticker),
    ]);
  });

  testWidgets('a code that resolved to nothing can still be reprinted', (
    tester,
  ) async {
    // The reason to reprint is usually that the label is unreadable, which is
    // exactly when the scan fails. Hiding the button here would be backwards.
    final printed = <String>[];
    await tester.pumpWidget(
      host(
        UniversalBarcodeInspector(
          scan: scanOf(found: false),
          onPrintLabel: (label, stock) async => printed.add(label.code),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print label'));
    await tester.pumpAndSettle();
    expect(printed, <String>['MAT-REC-1-L1-K']);
  });

  test('upstream and downstream are gathered across the whole trail', () {
    final scan = scanOf(
      custody: const <CustodyEvent>[
        CustodyEvent(
          eventId: 'a',
          eventType: 'INWARD_RECEIVED',
          at: '1',
          parents: <String>['MAT-RAW-1'],
        ),
        CustodyEvent(
          eventId: 'b',
          eventType: 'OUTPUT_MINTED',
          at: '2',
          children: <String>['LOT-9', 'LOT-9'],
        ),
      ],
    );
    expect(scan.upstream, <String>['MAT-RAW-1']);
    expect(scan.downstream, <String>['LOT-9'], reason: 'deduplicated');
  });
}
