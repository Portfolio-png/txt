import 'package:flutter/material.dart';

import '../../data/repositories/unit_repository.dart';
import '../../domain/unit_definition.dart';
import '../../domain/unit_inputs.dart';

enum UnitStatusFilter { active, archived, all }

enum UnitDuplicateWarning { none, nameOnly, symbolOnly, nameAndSymbol }

class UnitDuplicateCheck {
  const UnitDuplicateCheck({
    required this.blockingDuplicate,
    required this.warning,
  });

  final bool blockingDuplicate;
  final UnitDuplicateWarning warning;
}

class UnitsProvider extends ChangeNotifier {
  UnitsProvider({required UnitRepository repository}) : _repository = repository;

  final UnitRepository _repository;

  List<UnitDefinition> _units = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _searchQuery = '';
  UnitStatusFilter _statusFilter = UnitStatusFilter.active;
  bool _initialized = false;

  List<UnitDefinition> get units => _units;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  UnitStatusFilter get statusFilter => _statusFilter;

  List<UnitDefinition> get filteredUnits {
    final query = _normalize(_searchQuery);
    return _units.where((unit) {
      final matchesStatus = switch (_statusFilter) {
        UnitStatusFilter.active => !unit.isArchived,
        UnitStatusFilter.archived => unit.isArchived,
        UnitStatusFilter.all => true,
      };
      if (!matchesStatus) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return _normalize(unit.name).contains(query) ||
          _normalize(unit.symbol).contains(query) ||
          _normalize(unit.unitGroupName ?? '').contains(query) ||
          _normalize(unit.notes).contains(query);
    }).toList(growable: false);
  }

  List<UnitDefinition> get activeUnits => _units
      .where((unit) => !unit.isArchived)
      .toList(growable: false);

  List<String> get availableGroupNames {
    final names = _units
        .map((unit) => unit.unitGroupName?.trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  UnitDefinition? findById(int? id) {
    if (id == null) {
      return null;
    }
    return _units.where((unit) => unit.id == id).firstOrNull;
  }

  UnitDefinition? findBaseUnitForGroupName(
    String groupName, {
    int? excludeId,
  }) {
    final normalized = _normalize(groupName);
    if (normalized.isEmpty) {
      return null;
    }
    return _units.where((unit) {
      if (excludeId != null && unit.id == excludeId) {
        return false;
      }
      return _normalize(unit.unitGroupName ?? '') == normalized &&
          unit.conversionBaseUnitId == null;
    }).firstOrNull;
  }

  UnitDefinition? get primaryUnit =>
      _units.where((u) => u.name == 'Primary Unit' && u.symbol == '-').firstOrNull;

  bool areUnitsCompatible(int? groupUnitId, int? candidateUnitId) {
    if (groupUnitId == null || candidateUnitId == null) {
      return false;
    }
    if (groupUnitId == candidateUnitId) {
      return true;
    }
    final primary = primaryUnit;
    if (primary != null && primary.id == groupUnitId) {
      return true;
    }
    final groupUnit = findById(groupUnitId);
    final candidate = findById(candidateUnitId);
    if (groupUnit == null || candidate == null) {
      return false;
    }
    return groupUnit.unitGroupId != null &&
        groupUnit.unitGroupId == candidate.unitGroupId;
  }

  List<UnitDefinition> compatibleActiveUnitsForGroupUnitId(int? groupUnitId) {
    if (groupUnitId == null) {
      return activeUnits;
    }
    final primary = primaryUnit;
    if (primary != null && primary.id == groupUnitId) {
      return activeUnits;
    }
    return activeUnits
        .where((unit) => areUnitsCompatible(groupUnitId, unit.id))
        .toList(growable: false);
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.init();
      final units = await _repository.getUnits();
      units.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (nameCompare != 0) {
          return nameCompare;
        }
        final groupCompare = (a.unitGroupName ?? '').toLowerCase().compareTo(
          (b.unitGroupName ?? '').toLowerCase(),
        );
        if (groupCompare != 0) {
          return groupCompare;
        }
        return a.symbol.toLowerCase().compareTo(b.symbol.toLowerCase());
      });
      _units = units;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  void setStatusFilter(UnitStatusFilter value) {
    _statusFilter = value;
    notifyListeners();
  }

  UnitDuplicateCheck checkDuplicate({
    required String name,
    required String symbol,
    int? excludeId,
  }) {
    final normalizedName = _normalize(name);
    final normalizedSymbol = _normalize(symbol);
    var nameMatch = false;
    var symbolMatch = false;
    var fullMatch = false;

    for (final unit in _units) {
      if (excludeId != null && unit.id == excludeId) {
        continue;
      }
      final sameName = _normalize(unit.name) == normalizedName;
      final sameSymbol = _normalize(unit.symbol) == normalizedSymbol;
      if (sameName && sameSymbol) {
        fullMatch = true;
        break;
      }
      if (sameName) {
        nameMatch = true;
      }
      if (sameSymbol) {
        symbolMatch = true;
      }
    }

    if (fullMatch) {
      return const UnitDuplicateCheck(
        blockingDuplicate: true,
        warning: UnitDuplicateWarning.nameAndSymbol,
      );
    }
    if (nameMatch) {
      return const UnitDuplicateCheck(
        blockingDuplicate: false,
        warning: UnitDuplicateWarning.nameOnly,
      );
    }
    if (symbolMatch) {
      return const UnitDuplicateCheck(
        blockingDuplicate: false,
        warning: UnitDuplicateWarning.symbolOnly,
      );
    }
    return const UnitDuplicateCheck(
      blockingDuplicate: false,
      warning: UnitDuplicateWarning.none,
    );
  }

  Future<UnitDefinition?> createUnit(CreateUnitInput input) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created = await _repository.createUnit(input);
      await refresh();
      return _units.where((unit) => unit.id == created.id).firstOrNull ?? created;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<UnitDefinition?> updateUnit(UpdateUnitInput input) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _repository.updateUnit(input);
      await refresh();
      return _units.where((unit) => unit.id == updated.id).firstOrNull ?? updated;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<UnitDefinition?> archiveUnit(int id) async {
    return _changeStatus(() => _repository.archiveUnit(id));
  }

  Future<UnitDefinition?> restoreUnit(int id) async {
    return _changeStatus(() => _repository.restoreUnit(id));
  }

  Future<UnitDefinition?> _changeStatus(
    Future<UnitDefinition> Function() action,
  ) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await action();
      await refresh();
      return _units.where((unit) => unit.id == updated.id).firstOrNull ?? updated;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
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
    notifyListeners();
  }

  static String normalizeValue(String value) => _normalize(value);

  static String _normalize(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
