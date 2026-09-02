import '../../domain/universal_barcode_entity.dart';
import 'package:flutter/material.dart';
import '../../domain/search_result.dart';
import '../../data/repositories/search_repository.dart';

class SearchProvider extends ChangeNotifier {
  SearchProvider({required SearchRepository repository})
    : _repository = repository;

  final SearchRepository _repository;

  bool _isOverlayVisible = false;
  bool _isLoading = false;
  String _query = '';
  List<SearchResult> _results = const [];
  List<String> _history = const [];

  bool get isOverlayVisible => _isOverlayVisible;
  bool get isLoading => _isLoading;
  String get query => _query;
  List<SearchResult> get results => _results;
  List<String> get history => _history;

  bool _barcodeFocusRequested = false;

  /// Whether the overlay should open with the barcode field ready rather than
  /// the search field.
  bool get barcodeFocusRequested => _barcodeFocusRequested;

  /// Opens the overlay for someone holding a code rather than thinking of a
  /// search. The scanner gun needs no entry point — it types wherever it is
  /// pointed — but a code read off a smudged label by eye has to be typed
  /// somewhere, and until now that meant opening search and knowing which of
  /// the two fields was the right one.
  void openBarcodeLookup() {
    _barcodeFocusRequested = true;
    if (!_isOverlayVisible) {
      _isOverlayVisible = true;
      if (_history.isEmpty) {
        _loadHistory();
      }
    }
    notifyListeners();
  }

  /// Read once. Left standing it would drag focus back to the barcode field
  /// every time the overlay rebuilt, which is most keystrokes of a search.
  bool consumeBarcodeFocusRequest() {
    if (!_barcodeFocusRequested) return false;
    _barcodeFocusRequested = false;
    return true;
  }

  void toggleOverlay() {
    _isOverlayVisible = !_isOverlayVisible;
    if (_isOverlayVisible && _history.isEmpty) {
      _loadHistory();
    }
    if (!_isOverlayVisible) {
      _query = '';
      _results = const [];
      _barcodeFocusRequested = false;
    }
    notifyListeners();
  }

  void hideOverlay() {
    if (_isOverlayVisible) {
      _isOverlayVisible = false;
      _query = '';
      _results = const [];
      _barcodeFocusRequested = false;
      notifyListeners();
    }
  }

  Future<void> _loadHistory() async {
    try {
      _history = await _repository.getSearchHistory();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> search(String query) async {
    _query = query;
    if (query.trim().isEmpty) {
      _results = const [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _results = await _repository.search(query);
      if (query.length > 2) {
        await _repository.logSearchQuery(query);
      }
    } catch (_) {
      _results = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resolves any barcode to what it names, with its chain of custody.
  ///
  /// Returns a result even when nothing matched — "not found" carries whether
  /// the code was one of ours, which is the difference between a deleted record
  /// and a supplier's own label, and the caller has to be able to say which.
  Future<UniversalBarcodeEntity> scanBarcode(String code) async {
    _isLoading = true;
    notifyListeners();
    try {
      return await _repository.scanBarcode(code);
    } catch (_) {
      return UniversalBarcodeEntity(
        code: code,
        found: false,
        resolution: const BarcodeResolution(),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> lookupBarcode(String code) async {
    _isLoading = true;
    notifyListeners();
    try {
      return await _repository.lookupBarcode(code);
    } catch (_) {
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> recordClick(SearchResult result) async {
    try {
      await _repository.logSearchClick(_query, result);
    } catch (_) {}
    hideOverlay();
  }
}
