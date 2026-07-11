import 'package:flutter/foundation.dart';

import '../../data/repositories/sub_contractor_repository.dart';
import '../../domain/sub_contractor_definition.dart';
import '../../domain/sub_contractor_inputs.dart';

class SubContractorsProvider extends ChangeNotifier {
  SubContractorsProvider({
    required SubContractorRepository repository,
  }) : _repository = repository;

  final SubContractorRepository _repository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  int? _currentClientId;
  List<SubContractorDefinition> _subContractors = [];
  List<SubContractorDefinition> get subContractors => List.unmodifiable(_subContractors);

  List<SubContractorDefinition> filteredSubContractors(String query) {
    if (query.isEmpty) return _subContractors;
    final lowerQuery = query.toLowerCase();
    return _subContractors.where((s) {
      return s.name.toLowerCase().contains(lowerQuery) ||
             (s.clientName != null && s.clientName!.toLowerCase().contains(lowerQuery)) ||
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
      _subContractors = await _repository.getAllSubContractors();
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
      _subContractors = await _repository.getSubContractors(clientId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<SubContractorDefinition?> create(int clientId, CreateSubContractorInput input) async {
    try {
      final created = await _repository.createSubContractor(clientId, input);
      if (_currentClientId == clientId) {
        _subContractors = List.of(_subContractors)..add(created);
        notifyListeners();
      }
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
      final index = _subContractors.indexWhere((s) => s.id == id);
      if (index != -1) {
        final list = List.of(_subContractors);
        list[index] = updated;
        _subContractors = list;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      await _repository.deleteSubContractor(id);
      _subContractors = _subContractors.where((s) => s.id != id).toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
