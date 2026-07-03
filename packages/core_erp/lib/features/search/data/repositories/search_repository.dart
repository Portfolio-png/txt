import '../../domain/search_result.dart';

abstract class SearchRepository {
  Future<List<SearchResult>> search(String query);
  Future<List<String>> getSearchHistory();
  Future<void> logSearchQuery(String query);
  Future<void> logSearchClick(String query, SearchResult result);
}
