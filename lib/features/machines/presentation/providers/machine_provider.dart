import 'package:flutter/material.dart';

import '../../data/machine_repository.dart';
import '../../domain/machine.dart';

class MachinesProvider extends ChangeNotifier {
  MachinesProvider({required MachineRepository repository})
    : _repository = repository;

  final MachineRepository _repository;

  List<Machine> _machines = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isAssetUploading = false;
  String? _errorMessage;

  /// What KIND of refusal the last save was, when the server named one.
  /// `machine_asset_id_duplicate` is the one callers act on.
  String? _errorCode;
  String? _suggestedAssetId;
  String _searchQuery = '';
  bool _initialized = false;

  List<Machine> get machines => _machines;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isAssetUploading => _isAssetUploading;
  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;

  /// The next free number in the series, when a save was refused for a clash.
  String? get suggestedAssetId => _suggestedAssetId;
  String get searchQuery => _searchQuery;

  List<Machine> filteredMachinesWithGroups(Map<int, String> groupNames) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _machines;
    return _machines.where((m) {
      final groupName = m.groupId != null ? (groupNames[m.groupId!] ?? '') : '';
      final matchesCustom = m.customProperties.any(
        (p) =>
            p.key.toLowerCase().contains(query) ||
            p.value.toLowerCase().contains(query),
      );
      return m.name.toLowerCase().contains(query) ||
          m.assetId.toLowerCase().contains(query) ||
          m.makeModel.toLowerCase().contains(query) ||
          groupName.toLowerCase().contains(query) ||
          matchesCustom;
    }).toList();
  }

  List<Machine> get filteredMachines {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _machines;
    return _machines.where((m) {
      final matchesCustom = m.customProperties.any(
        (p) =>
            p.key.toLowerCase().contains(query) ||
            p.value.toLowerCase().contains(query),
      );
      return m.name.toLowerCase().contains(query) ||
          m.assetId.toLowerCase().contains(query) ||
          m.makeModel.toLowerCase().contains(query) ||
          matchesCustom;
    }).toList();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await refresh();
  }

  /// True once this provider is gone, so a fetch that outlives it stops short
  /// of notifying.
  ///
  /// `initialize()` is one of thirteen fired concurrently in a post-frame
  /// callback after auth, and each one awaits HTTP. If the provider is disposed
  /// while that request is in flight — navigating away, or an integration test
  /// ending — the response lands on a disposed `ChangeNotifier` and throws
  /// "A MachinesProvider was used after being disposed". Found by the first
  /// integration test that ran the real app against a real server.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _machines = await _repository.fetchMachines();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void setSearchQuery(String val) {
    _searchQuery = val;
    notifyListeners();
  }

  Future<Machine?> createMachine(Machine machine) async {
    _isSaving = true;
    _errorMessage = null;
    _errorCode = null;
    _suggestedAssetId = null;
    notifyListeners();
    try {
      final savedMachine = await _repository.saveMachine(machine);
      await refresh();
      return savedMachine;
    } on MachineSaveException catch (e) {
      _errorMessage = e.message;
      _errorCode = e.code;
      _suggestedAssetId = e.suggestedAssetId;
      notifyListeners();
      return null;
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
    _errorCode = null;
    _suggestedAssetId = null;
    notifyListeners();
    try {
      final savedMachine = await _repository.saveMachine(machine);
      await refresh();
      return savedMachine;
    } on MachineSaveException catch (e) {
      _errorMessage = e.message;
      _errorCode = e.code;
      _suggestedAssetId = e.suggestedAssetId;
      notifyListeners();
      return null;
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

  Future<MachineAssetUploadIntent?> createAssetUploadIntent(
    MachineAssetUploadIntentInput input,
  ) async {
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

  Future<String?> completeAssetUpload(
    CompleteMachineAssetUploadInput input,
  ) async {
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

  /// Pending production runs queued on a machine (machine queue popup).
  Future<List<MachineQueueItem>> fetchMachineQueue(String machineId) {
    return _repository.fetchMachineQueue(machineId);
  }
}
