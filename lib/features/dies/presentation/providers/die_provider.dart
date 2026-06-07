import 'package:flutter/material.dart';

import '../../data/die_repository.dart';
import '../../domain/die.dart';

class DiesProvider extends ChangeNotifier {
  DiesProvider({required DieRepository repository}) : _repository = repository;

  final DieRepository _repository;


  List<Die> _dies = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isAssetUploading = false;
  String? _errorMessage;
  String _searchQuery = '';
  bool _initialized = false;

  List<Die> get dies => _dies;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isAssetUploading => _isAssetUploading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  List<Die> filteredDiesWithGroups(Map<int, String> groupNames) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _dies;
    return _dies.where((d) {
      final compatibleNames = d.compatibleMachineGroupIds
          .map((id) => groupNames[id] ?? '')
          .join(' ');
      return d.toolCode.toLowerCase().contains(query) ||
             d.name.toLowerCase().contains(query) ||
             compatibleNames.toLowerCase().contains(query);
    }).toList();
  }

  List<Die> get filteredDies {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _dies;
    return _dies.where((d) {
      return d.toolCode.toLowerCase().contains(query) ||
             d.name.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _dies = await _repository.fetchDies();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String val) {
    _searchQuery = val;
    notifyListeners();
  }

  Future<Die?> createDie(Die die) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final savedDie = await _repository.saveDie(die);
      await refresh();
      return savedDie;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<Die?> updateDie(Die die) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final savedDie = await _repository.saveDie(die);
      await refresh();
      return savedDie;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deleteDie(String id) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.deleteDie(id);
      await refresh();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<DieAssetUploadIntent?> createAssetUploadIntent(DieAssetUploadIntentInput input) async {
    _isAssetUploading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _repository.createAssetUploadIntent(input);
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isAssetUploading = false;
      notifyListeners();
    }
  }

  Future<String?> completeAssetUpload(CompleteDieAssetUploadInput input) async {
    _isAssetUploading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _repository.completeAssetUpload(input);
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isAssetUploading = false;
      notifyListeners();
    }
  }
}
