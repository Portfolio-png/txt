import 'package:flutter/foundation.dart';

import '../../data/repositories/sub_contractor_repository.dart';
import '../../domain/sub_contractor_definition.dart';
import '../../domain/sub_contractor_inputs.dart';

/// Sub-contractors, cached per client and in one all-clients list.
///
/// It used to hold a single list that `loadAll()` and `loadForClient()` took
/// turns overwriting, with `create()` appending only when the scope happened
/// to match. That was survivable while the clients screen was the only caller:
/// it loads, then creates, in that order. It is not survivable now that the
/// item editor picks a contractor for a part — load all of them to fill the
/// picker, create one inline, and the row came back from the server and then
/// appeared in no list, so it could not be selected.
///
/// Two caches instead, and a write lands in both.
class SubContractorsProvider extends ChangeNotifier {
  SubContractorsProvider({required SubContractorRepository repository})
    : _repository = repository;

  final SubContractorRepository _repository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  /// Which list [subContractors] is showing: null means all clients.
  int? _currentClientId;

  List<SubContractorDefinition> _all = <SubContractorDefinition>[];
  bool _allLoaded = false;
  final Map<int, List<SubContractorDefinition>> _byClient =
      <int, List<SubContractorDefinition>>{};

  /// The list the screen last asked for.
  List<SubContractorDefinition> get subContractors => List.unmodifiable(
    _currentClientId == null
        ? _all
        : (_byClient[_currentClientId] ?? const <SubContractorDefinition>[]),
  );

  /// Every contractor loaded, whatever scope is on screen. What a picker in
  /// another feature wants.
  List<SubContractorDefinition> get allSubContractors => List.unmodifiable(_all);

  /// The contractors of one client, from whichever cache has them. Falls back
  /// to filtering the all-list, so a picker that loaded everything does not
  /// have to fetch again per client.
  List<SubContractorDefinition> forClient(int clientId) {
    final cached = _byClient[clientId];
    if (cached != null) return List.unmodifiable(cached);
    return List.unmodifiable(
      _all.where((entry) => entry.clientId == clientId),
    );
  }

  List<SubContractorDefinition> filteredSubContractors(String query) {
    final source = subContractors;
    if (query.isEmpty) return source;
    final lowerQuery = query.toLowerCase();
    return source.where((s) {
      return s.name.toLowerCase().contains(lowerQuery) ||
          (s.clientName != null &&
              s.clientName!.toLowerCase().contains(lowerQuery)) ||
          s.designation.toLowerCase().contains(lowerQuery) ||
          s.phone.toLowerCase().contains(lowerQuery) ||
          s.email.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  Future<void> loadAll() async {
    _currentClientId = null;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _all = await _repository.getAllSubContractors();
      _allLoaded = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadForClient(int clientId) async {
    _currentClientId = clientId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _byClient[clientId] = await _repository.getSubContractors(clientId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load this client's contractors unless they are already cached. For a
  /// picker that opens on whichever client a part names — it must not refetch
  /// on every rebuild, and it must not show an empty list on the first frame
  /// of a client it has already seen.
  Future<void> ensureLoadedForClient(int clientId) async {
    if (_byClient.containsKey(clientId) || _allLoaded) return;
    await loadForClient(clientId);
  }

  Future<SubContractorDefinition?> create(
    int clientId,
    CreateSubContractorInput input,
  ) async {
    try {
      final created = await _repository.createSubContractor(clientId, input);
      _remember(created);
      notifyListeners();
      return created;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> update(int id, UpdateSubContractorInput input) async {
    try {
      final updated = await _repository.updateSubContractor(id, input);
      _remember(updated);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      await _repository.deleteSubContractor(id);
      _all = _all.where((s) => s.id != id).toList();
      for (final clientId in _byClient.keys.toList()) {
        _byClient[clientId] =
            _byClient[clientId]!.where((s) => s.id != id).toList();
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Put a row into both caches, replacing any earlier copy of it.
  ///
  /// The all-list is only appended to once it has actually been loaded: a
  /// single created row sitting in an otherwise empty `_all` would read as
  /// "there is one contractor in the whole factory", which is worse than
  /// reading as "not loaded yet".
  void _remember(SubContractorDefinition row) {
    if (_allLoaded) {
      _all = _replacing(_all, row);
    }
    final cached = _byClient[row.clientId];
    if (cached != null) {
      _byClient[row.clientId] = _replacing(cached, row);
    }
  }

  List<SubContractorDefinition> _replacing(
    List<SubContractorDefinition> list,
    SubContractorDefinition row,
  ) {
    final next = List.of(list);
    final index = next.indexWhere((entry) => entry.id == row.id);
    if (index == -1) {
      next.add(row);
    } else {
      next[index] = row;
    }
    return next;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
