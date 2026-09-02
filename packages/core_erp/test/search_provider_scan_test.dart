import 'package:core_erp/features/search/data/repositories/search_repository.dart';
import 'package:core_erp/features/search/domain/search_result.dart';
import 'package:core_erp/features/search/domain/universal_barcode_entity.dart';
import 'package:core_erp/features/search/presentation/providers/search_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubRepository implements SearchRepository {
  int historyCalls = 0;

  @override
  Future<List<String>> getSearchHistory() async {
    historyCalls += 1;
    return const <String>[];
  }

  @override
  Future<UniversalBarcodeEntity> scanBarcode(String code) async =>
      UniversalBarcodeEntity(
        code: code,
        found: false,
        resolution: const BarcodeResolution(),
      );

  @override
  Future<Map<String, dynamic>?> lookupBarcode(String code) async => null;

  @override
  Future<List<SearchResult>> search(String query) async =>
      const <SearchResult>[];

  @override
  Future<void> logSearchQuery(String query) async {}

  @override
  Future<void> logSearchClick(String query, SearchResult result) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SearchProvider provider;

  setUp(() {
    provider = SearchProvider(repository: _StubRepository());
  });

  test('the scan action opens the overlay ready for a code', () {
    expect(provider.isOverlayVisible, isFalse);
    provider.openBarcodeLookup();
    expect(provider.isOverlayVisible, isTrue);
    expect(provider.barcodeFocusRequested, isTrue);
  });

  test('the focus request is honoured once and then spent', () {
    // Left standing, the request would drag the caret back to the barcode field
    // on every rebuild — which is every keystroke of a search typed afterwards.
    provider.openBarcodeLookup();
    expect(provider.consumeBarcodeFocusRequest(), isTrue);
    expect(provider.consumeBarcodeFocusRequest(), isFalse);
    expect(provider.barcodeFocusRequested, isFalse);
  });

  test('opening plain search does not ask for the barcode field', () {
    provider.toggleOverlay();
    expect(provider.isOverlayVisible, isTrue);
    expect(provider.consumeBarcodeFocusRequest(), isFalse);
  });

  test('scanning while the overlay is already open refocuses it, not closes it', () {
    // Ctrl+K then Ctrl+B is an ordinary sequence: open search, realise you have
    // the code in hand. Toggling shut here would be maddening.
    provider.toggleOverlay();
    provider.openBarcodeLookup();
    expect(provider.isOverlayVisible, isTrue);
    expect(provider.consumeBarcodeFocusRequest(), isTrue);
  });

  test('an unspent request does not survive the overlay closing', () {
    // Otherwise it fires against the next thing that opens the overlay, which
    // may well be a search.
    provider.openBarcodeLookup();
    provider.hideOverlay();
    expect(provider.barcodeFocusRequested, isFalse);

    provider.openBarcodeLookup();
    provider.toggleOverlay(); // toggles shut
    expect(provider.barcodeFocusRequested, isFalse);
  });

  test('it notifies, or nothing on screen would move', () {
    var notifications = 0;
    provider.addListener(() => notifications += 1);
    provider.openBarcodeLookup();
    expect(notifications, greaterThan(0));
  });
}
