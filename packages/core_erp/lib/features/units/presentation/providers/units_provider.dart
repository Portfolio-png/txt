import 'package:flutter/material.dart';

import '../../../../core/services/config_service.dart';
import '../../data/repositories/unit_repository.dart';
import '../../domain/unit_definition.dart';
import '../../domain/unit_inputs.dart';

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
  UnitsProvider({required UnitRepository repository})
    : _repository = repository;

  final UnitRepository _repository;

  List<UnitDefinition> _units = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _searchQuery = '';

  bool _initialized = false;

  List<UnitDefinition> get units => _units;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  List<UnitDefinition> get filteredUnits {
    final query = _normalize(_searchQuery);
    return _units
        .where((unit) {
          if (query.isEmpty) {
            return true;
          }
          return _normalize(unit.name).contains(query) ||
              _normalize(unit.symbol).contains(query) ||
              _normalize(unit.unitGroupName ?? '').contains(query) ||
              _normalize(unit.notes).contains(query);
        })
        .toList(growable: false);
  }

  List<UnitDefinition> get activeUnits =>
      _units.where((unit) => !unit.isArchived).toList(growable: false);

  List<String> get availableGroupNames {
    final names =
        _units
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

  UnitDefinition? findBaseUnitForGroupName(String groupName, {int? excludeId}) {
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

  UnitDefinition? get primaryUnit => _units
      .where((u) => u.name == 'Primary Unit' && u.symbol == '-')
      .firstOrNull;

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
    final groupBaseId = groupUnit.conversionBaseUnitId ?? groupUnit.id;
    final candidateBaseId = candidate.conversionBaseUnitId ?? candidate.id;
    return groupBaseId == candidateBaseId;
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

  List<UnitDefinition> includedUnitsFor(
    int? familyBaseUnitId,
    String context, {
    int? currentUnitId,
  }) {
    if (familyBaseUnitId == null) {
      return activeUnits;
    }

    final familyBase = findById(familyBaseUnitId);
    if (familyBase == null) return activeUnits;
    final dimension = familyBase.unitGroupDimension?.toLowerCase() ?? '';

    final config = ConfigService.instance.config;
    final familiesConfig = config['units']?['families'];

    if (familiesConfig == null || familiesConfig is! Map) {
      return compatibleActiveUnitsForGroupUnitId(familyBaseUnitId);
    }

    final dimensionConfig = familiesConfig[dimension];
    if (dimensionConfig == null || dimensionConfig is! Map) {
      return compatibleActiveUnitsForGroupUnitId(familyBaseUnitId);
    }

    final contextList = dimensionConfig[context];
    if (contextList == null || contextList is! List) {
      return compatibleActiveUnitsForGroupUnitId(familyBaseUnitId);
    }

    final includedIds = contextList.map((e) => e as int).toSet();

    final candidates = compatibleActiveUnitsForGroupUnitId(familyBaseUnitId);
    return candidates
        .where((unit) {
          if (currentUnitId != null && unit.id == currentUnitId) {
            return true;
          }
          return includedIds.contains(unit.id);
        })
        .toList(growable: false);
  }

  String? convertValue(dynamic value, int? fromUnitId, int? toUnitId) {
    if (fromUnitId == null || toUnitId == null || value == null) return null;
    if (fromUnitId == toUnitId) return value.toString();

    final from = findById(fromUnitId);
    final to = findById(toUnitId);

    if (from == null || to == null) return null;

    final fromBaseId = from.conversionBaseUnitId ?? from.id;
    final toBaseId = to.conversionBaseUnitId ?? to.id;
    if (fromBaseId != toBaseId) {
      return null;
    }

    double valInBase = 0.0;
    final valStr = value.toString().trim();

    if (from.conversionType == 'table') {
      final point = from.conversionPoints
          .where((p) => p.pointKey.toLowerCase() == valStr.toLowerCase())
          .firstOrNull;
      if (point != null) {
        valInBase = point.baseValue;
      } else {
        valInBase = double.tryParse(valStr) ?? 0.0;
      }
    } else {
      final numVal = double.tryParse(valStr) ?? 0.0;
      valInBase = numVal * from.conversionFactor;
    }

    if (to.conversionType == 'table') {
      final tolerance = 0.0005; // 0.0005 mm tolerance as per spec
      // assuming table values are exact within tolerance
      final point = to.conversionPoints
          .where((p) => (p.baseValue - valInBase).abs() < tolerance)
          .firstOrNull;
      if (point != null) {
        return point.pointKey;
      }
      return valInBase.toString();
    } else {
      return (valInBase / to.conversionFactor).toString();
    }
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
      final gaugePoints = await _repository.getGaugePoints();

      final pointsByUnitId = <int, List<ConversionPoint>>{};
      for (final p in gaugePoints) {
        pointsByUnitId.putIfAbsent(p.unitId, () => []).add(p);
      }

      for (var i = 0; i < units.length; i++) {
        if (units[i].conversionType == 'table') {
          final points = pointsByUnitId[units[i].id] ?? [];
          units[i] = UnitDefinition(
            id: units[i].id,
            name: units[i].name,
            symbol: units[i].symbol,
            notes: units[i].notes,
            unitGroupId: units[i].unitGroupId,
            unitGroupName: units[i].unitGroupName,
            conversionFactor: units[i].conversionFactor,
            conversionBaseUnitId: units[i].conversionBaseUnitId,
            conversionBaseUnitName: units[i].conversionBaseUnitName,
            conversionType: units[i].conversionType,
            precision: units[i].precision,
            unitGroupDimension: units[i].unitGroupDimension,
            unitGroupBaseUnitId: units[i].unitGroupBaseUnitId,
            conversionPoints: points,
            isArchived: units[i].isArchived,
            usageCount: units[i].usageCount,
            createdAt: units[i].createdAt,
            updatedAt: units[i].updatedAt,
          );
        }
      }

      units.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        final nameCompare = a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        );
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
      return _units.where((unit) => unit.id == created.id).firstOrNull ??
          created;
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
      return _units.where((unit) => unit.id == updated.id).firstOrNull ??
          updated;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deleteUnit(int id) async {
    if (_isSaving) return;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.deleteUnit(id);
      await refresh();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
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
