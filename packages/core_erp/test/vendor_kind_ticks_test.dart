import 'package:core_erp/features/vendors/data/repositories/api_vendor_repository.dart';
import 'package:core_erp/features/vendors/domain/vendor_definition.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:core_erp/features/vendors/presentation/screens/vendors_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

// The vendor form says what a vendor is for (user, 2026-11-24): a raw
// material vendor, an outsourcing vendor, or both — two ticks.

Future<VendorsProvider> _pumpEditor(
  WidgetTester tester, {
  required ValueChanged<VendorDefinition> onSaved,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = VendorsProvider(
    repository: ApiVendorRepository(
      client: http.Client(),
      baseUrl: '',
      useMockResponses: true,
    ),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<VendorsProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VendorsScreen.editorPanel(onSaved: onSaved, onCancel: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return provider;
}

Checkbox _tick(WidgetTester tester, String key) => tester.widget<Checkbox>(
  find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: find.byType(Checkbox),
  ),
);

void main() {
  testWidgets('a new vendor ticks raw material, outsourcing, or both', (
    tester,
  ) async {
    VendorDefinition? saved;
    await _pumpEditor(tester, onSaved: (v) => saved = v);

    expect(find.text('Raw material vendor'), findsOneWidget);
    expect(find.text('Outsourcing vendor'), findsOneWidget);
    expect(_tick(tester, 'vendor_supplies_raw_material').value, isFalse);
    expect(_tick(tester, 'vendor_does_outsourcing').value, isFalse);

    // Its words are a target too, not only the box.
    await tester.tap(find.text('Raw material vendor'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('vendor_does_outsourcing')));
    await tester.pump();
    expect(_tick(tester, 'vendor_supplies_raw_material').value, isTrue);
    expect(_tick(tester, 'vendor_does_outsourcing').value, isTrue);

    await tester.enterText(find.byType(TextField).first, 'Tick Test Metals');
    await tester.pump();
    final create = find.text('Create Vendor').last;
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(saved, isNotNull, reason: 'the vendor should save');
    expect(saved!.suppliesRawMaterial, isTrue);
    expect(saved!.doesOutsourcing, isTrue);
    // Let the toast fade before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });
}
