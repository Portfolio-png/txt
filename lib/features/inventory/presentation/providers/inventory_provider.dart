import 'package:flutter/material.dart';

import '../../data/repositories/inventory_repository.dart';
import '../../domain/create_parent_material_input.dart';
import '../../domain/group_property_draft.dart';
import '../../domain/inventory_control_tower.dart';
import '../../domain/material_activity_event.dart';
import '../../domain/material_control_tower_detail.dart';
import '../../domain/material_group_configuration.dart';
import '../../domain/material_inputs.dart';
import '../../domain/material_record.dart';

class InventoryProvider extends ChangeNotifier {
  InventoryProvider({required InventoryRepository repository})
    : _repository = repository;

  final InventoryRepository _repository;

  List<MaterialRecord> _materials = const [];
  MaterialRecord? _selectedMaterial;
  bool _isLoading = false;
  bool _isSaving = false;
  // BUG-11: Separate flag for barcode lookup so it doesn't trigger the
  // full-screen loading skeleton during barcode scan workflows.
  bool _isLookingUp = false;
  String? _errorMessage;
  String? _lastLookupBarcode;
  String _searchQuery = '';
  bool _initialized = false;
  final Map<String, List<MaterialActivityEvent>> _activityByBarcode = {};
  final Map<String, MaterialControlTowerDetail> _detailByBarcode = {};
  InventoryHealthSnapshot _healthSnapshot = const InventoryHealthSnapshot();

  List<MaterialRecord> get materials => _materials;
  MaterialRecord? get selectedMaterial => _selectedMaterial;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isLookingUp => _isLookingUp;
  String? get errorMessage => _errorMessage;
  String? get lastLookupBarcode => _lastLookupBarcode;
  String get searchQuery => _searchQuery;
  InventoryHealthSnapshot get healthSnapshot => _healthSnapshot;
  MaterialControlTowerDetail? detailFor(String barcode) =>
      _detailByBarcode[barcode];

  List<MaterialActivityEvent> activityFor(String barcode) =>
      _activityByBarcode[barcode] ?? const [];

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.init();
      await _repository.seedIfEmpty();
      await _reloadMaterials();
      await loadInventoryHealth(silent: true);
      if (_materials.isNotEmpty) {
        _selectedMaterial = _materials.first;
      }
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to load inventory data.',
        error: error,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.init();
      await _reloadMaterials();
      await loadInventoryHealth(silent: true);
      if (_selectedMaterial != null) {
        _selectedMaterial = _materials
            .where((item) => item.barcode == _selectedMaterial!.barcode)
            .firstOrNull;
      }
      _selectedMaterial ??= _materials.firstOrNull;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to refresh inventory data.',
        error: error,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addParentMaterial(CreateParentMaterialInput input) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.saveParentWithChildren(input);
      await _reloadMaterials();
      _selectedMaterial = _materials
          .where((item) => item.barcode == result.parentBarcode)
          .firstOrNull;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to save material.',
        error: error,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> addChildMaterial(CreateChildMaterialInput input) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.createChildMaterial(input);
      await _reloadMaterials();
      _selectedMaterial = _materials
          .where((item) => item.barcode == result.barcode)
          .firstOrNull;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to add sub-group.',
        error: error,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> updateMaterial(UpdateMaterialInput input) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.updateMaterial(input);
      await _reloadMaterials();
      _selectedMaterial = _materials
          .where((item) => item.barcode == result.barcode)
          .firstOrNull;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to update material.',
        error: error,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deleteMaterial(String barcode) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.deleteMaterial(barcode);
      await _reloadMaterials();
      if (_selectedMaterial?.barcode == barcode) {
        _selectedMaterial = _materials.firstOrNull;
      }
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to delete material.',
        error: error,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> linkMaterialToGroup(String barcode, int groupId) async {
    await _linkMutation(
      action: () => _repository.linkMaterialToGroup(barcode, groupId),
      fallback: 'Failed to link group inheritance.',
    );
  }

  Future<void> linkMaterialToItem(
    String barcode,
    int itemId,
  ) async {
    await _linkMutation(
      action: () => _repository.linkMaterialToItem(
        barcode,
        itemId,
      ),
      fallback: 'Failed to link item inheritance.',
    );
  }

  Future<void> unlinkMaterial(String barcode) async {
    await _linkMutation(
      action: () => _repository.unlinkMaterial(barcode),
      fallback: 'Failed to unlink inherited properties.',
    );
  }

  Future<void> selectMaterial(String barcode) async {
    _selectedMaterial = _materials
        .where((item) => item.barcode == barcode)
        .firstOrNull;
    notifyListeners();
  }

  Future<MaterialRecord?> lookupBarcode(String barcode) async {
    // BUG-11: Use _isLookingUp instead of _isLoading so the full-screen
    // loading skeleton is not triggered during barcode scan workflows.
    _isLookingUp = true;
    _errorMessage = null;
    _lastLookupBarcode = barcode;
    notifyListeners();

    try {
      final record = await _repository.getMaterialByBarcode(barcode);
      if (record == null) {
        _errorMessage = 'No material found for barcode $barcode.';
        return null;
      }

      await _reloadMaterials();
      _selectedMaterial =
          _materials
              .where((item) => item.barcode == record.barcode)
              .firstOrNull ??
          record;
      return _selectedMaterial;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to look up barcode.',
        error: error,
      );
      return null;
    } finally {
      _isLookingUp = false;
      notifyListeners();
    }
  }

  Future<void> resetScanTrace(String barcode) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final record = await _repository.resetScanTrace(barcode);
      await _reloadMaterials();
      _selectedMaterial =
          _materials.where((item) => item.barcode == barcode).firstOrNull ??
          record;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to reset scan trace.',
        error: error,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<MaterialActivityEvent>> loadMaterialActivity(
    String barcode,
  ) async {
    try {
      final activity = await _repository.getMaterialActivity(barcode);
      _activityByBarcode[barcode] = activity;
      notifyListeners();
      return activity;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to load activity history.',
        error: error,
      );
      notifyListeners();
      return _activityByBarcode[barcode] ?? const [];
    }
  }

  Future<InventoryHealthSnapshot> loadInventoryHealth({
    bool silent = false,
  }) async {
    try {
      _healthSnapshot = await _repository.getInventoryHealth();
    } catch (_) {
      // BUG-09: The original fallback used the exact same predicate
      // (pendingAlertCount > 0) for BOTH unitMismatchCount and
      // pendingReconciliationCount, making both KPIs identical.
      // Low-stock uses <=100 heuristic; reserved risk checks reserved > onHand.
      final lowStock = _materials
          .where((item) => item.availableToPromise <= 100 && item.onHand > 0)
          .length;
      final reservedRisk = _materials
          .where((item) => item.reserved > item.onHand && item.reserved > 0)
          .length;
      _healthSnapshot = InventoryHealthSnapshot(
        lowStockCount: lowStock,
        reservedRiskCount: reservedRisk,
        incomingTodayCount: _materials
            .where((item) => item.incoming > 0)
            .length,
        qualityHoldCount: _materials
            .where((item) => item.inventoryState == InventoryState.qualityHold)
            .length,
        // unitMismatch: items with any pending alert (unit-related alerts)
        unitMismatchCount: _materials
            .where((item) => item.pendingAlertCount > 0)
            .length,
        // pendingReconciliation: items with reserved > 0 but not yet reconciled
        // (distinct from reserved risk which checks reserved > onHand).
        pendingReconciliationCount: _materials
            .where((item) => item.reserved > 0 && item.availableToPromise == item.onHand)
            .length,
      );
    }
    if (!silent) {
      notifyListeners();
    }
    return _healthSnapshot;
  }

  Future<MaterialControlTowerDetail?> loadMaterialControlTowerDetail(
    String barcode,
  ) async {
    try {
      final detail = await _repository.getMaterialControlTowerDetail(barcode);
      if (detail != null) {
        _detailByBarcode[barcode] = detail;
      }
      notifyListeners();
      return detail;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to load material detail.',
        error: error,
      );
      notifyListeners();
      return _detailByBarcode[barcode];
    }
  }

  Future<MaterialControlTowerDetail?> postInventoryMovement(
    CreateInventoryMovementInput input,
  ) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final detail = await _repository.createInventoryMovement(input);
      _detailByBarcode[input.materialBarcode] = detail;
      await _reloadMaterials();
      await loadInventoryHealth(silent: true);
      _selectedMaterial = _materials
          .where((item) => item.barcode == input.materialBarcode)
          .firstOrNull;
      return detail;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to post inventory movement.',
        error: error,
      );
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<MaterialGroupConfiguration?> loadGroupConfiguration(
    String barcode,
  ) async {
    try {
      _errorMessage = null;
      notifyListeners();
      return await _repository.getGroupConfiguration(barcode);
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to load group configuration.',
        error: error,
      );
      notifyListeners();
      return null;
    }
  }

  Future<void> updateGroupConfiguration(
    String barcode, {
    required bool inheritanceEnabled,
    required List<int> selectedItemIds,
    required List<GroupPropertyDraft> propertyDrafts,
    required List<GroupUnitGovernance> unitGovernance,
    required GroupUiPreferences uiPreferences,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.updateGroupConfiguration(
        barcode,
        inheritanceEnabled: inheritanceEnabled,
        selectedItemIds: selectedItemIds,
        propertyDrafts: propertyDrafts,
        unitGovernance: unitGovernance,
        uiPreferences: uiPreferences,
      );
      await _reloadMaterials();
      _selectedMaterial = _materials
          .where((item) => item.barcode == barcode)
          .firstOrNull;
    } catch (error) {
      _errorMessage = _friendlyError(
        fallback: 'Failed to update group configuration.',
        error: error,
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    _lastLookupBarcode = null;
    notifyListeners();
  }

  void setSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }

    _searchQuery = value;
    notifyListeners();
  }

  Future<void> _reloadMaterials() async {
    _materials = await _repository.getAllMaterials();
  }

  Future<void> _linkMutation({
    required Future<MaterialRecord> Function() action,
    required String fallback,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await action();
      await _reloadMaterials();
      _selectedMaterial = _materials
          .where((item) => item.barcode == result.barcode)
          .firstOrNull;
    } catch (error) {
      _errorMessage = _friendlyError(fallback: fallback, error: error);
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  String _friendlyError({required String fallback, required Object error}) {
    final message = _sanitizeErrorMessage(error.toString());
    if (message.isEmpty || message == 'Exception') {
      return fallback;
    }
    if (message.toLowerCase().startsWith(fallback.toLowerCase())) {
      return message;
    }
    return '$fallback $message';
  }

  String _sanitizeErrorMessage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final withoutPrefix = trimmed.replaceFirst(
      RegExp(r'^Exception:\s*', caseSensitive: false),
      '',
    );
    final lower = withoutPrefix.toLowerCase();

    final cannotGetMatch = RegExp(
      r'cannot\s+get\s+([^\s<]+)',
      caseSensitive: false,
    ).firstMatch(withoutPrefix);
    if (cannotGetMatch != null) {
      return 'Endpoint unavailable: ${cannotGetMatch.group(1)}';
    }

    if (lower.contains('<!doctype html') || lower.contains('<html')) {
      return 'Server returned an unexpected HTML response.';
    }

    return withoutPrefix.replaceAll(RegExp(r'\s+'), ' ');
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
