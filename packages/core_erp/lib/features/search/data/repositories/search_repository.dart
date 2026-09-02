import '../../domain/universal_barcode_entity.dart';
import '../../domain/search_result.dart';

abstract class SearchRepository {
  Future<List<SearchResult>> search(String query);
  Future<Map<String, dynamic>?> lookupBarcode(String code);

  /// Resolves any barcode in the system to what it names, with its chain of
  /// custody. Returns a result even when nothing matched, because "not found"
  /// carries information — whether the code was one of ours at all.
  Future<UniversalBarcodeEntity> scanBarcode(String code);
  Future<List<String>> getSearchHistory();
  Future<void> logSearchQuery(String query);
  Future<void> logSearchClick(String query, SearchResult result);
}
