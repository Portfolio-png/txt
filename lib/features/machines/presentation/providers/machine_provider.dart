import 'package:flutter/material.dart';

import '../../data/machine_repository.dart';
import '../../domain/machine.dart';

class MachinesProvider extends ChangeNotifier {
  MachinesProvider({required MachineRepository repository}) : _repository = repository;

  final MachineRepository _repository;


  List<Machine> _machines = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _searchQuery = '';
  bool _initialized = false;

  List<Machine> get machines => _machines;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  List<Machine> filteredMachinesWithGroups(Map<int, String> groupNames) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _machines;
    return _machines.where((m) {
      final groupName = m.groupId != null ? (groupNames[m.groupId!] ?? '') : '';
      return m.name.toLowerCase().contains(query) ||
             m.assetId.toLowerCase().contains(query) ||
             m.makeModel.toLowerCase().contains(query) ||
             groupName.toLowerCase().contains(query);
    }).toList();
  }

  List<Machine> get filteredMachines {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _machines;
    return _machines.where((m) {
      return m.name.toLowerCase().contains(query) ||
             m.assetId.toLowerCase().contains(query) ||
             m.makeModel.toLowerCase().contains(query);
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
      _machines = await _repository.fetchMachines();
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

  Future<Machine?> createMachine(Machine machine) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.saveMachine(machine);
      await refresh();
      return machine;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<Machine?> updateMachine(Machine machine) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.saveMachine(machine);
      await refresh();
      return machine;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deleteMachine(String id) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.deleteMachine(id);
      await refresh();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
