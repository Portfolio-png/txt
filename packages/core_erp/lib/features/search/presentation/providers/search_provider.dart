import 'package:flutter/material.dart';
import '../../domain/search_result.dart';
import '../../data/repositories/search_repository.dart';

class SearchProvider extends ChangeNotifier {
  SearchProvider({required SearchRepository repository}) : _repository = repository;

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

  void toggleOverlay() {
    _isOverlayVisible = !_isOverlayVisible;
    if (_isOverlayVisible && _history.isEmpty) {
      _loadHistory();
    }
    if (!_isOverlayVisible) {
      _query = '';
      _results = const [];
    }
    notifyListeners();
  }

  void hideOverlay() {
    if (_isOverlayVisible) {
      _isOverlayVisible = false;
      _query = '';
      _results = const [];
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

  Future<void> recordClick(SearchResult result) async {
    try {
      await _repository.logSearchClick(_query, result);
    } catch (_) {}
    hideOverlay();
  }
}
