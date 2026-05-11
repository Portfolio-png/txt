import 'package:flutter/material.dart';

import '../../data/repositories/vendor_repository.dart';
import '../../domain/vendor_definition.dart';
import '../../domain/vendor_inputs.dart';

enum VendorStatusFilter { active, archived, all }

enum VendorDuplicateWarning { none, nameOnly, gstOnly, nameAndGst }

class VendorDuplicateCheck {
  const VendorDuplicateCheck({
    required this.blockingDuplicate,
    required this.warning,
  });

  final bool blockingDuplicate;
  final VendorDuplicateWarning warning;
}

class VendorsProvider extends ChangeNotifier {
  VendorsProvider({required VendorRepository repository})
    : _repository = repository;

  final VendorRepository _repository;

  List<VendorDefinition> _vendors = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _searchQuery = '';
  VendorStatusFilter _statusFilter = VendorStatusFilter.active;
  bool _initialized = false;

  List<VendorDefinition> get vendors => _vendors;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  VendorStatusFilter get statusFilter => _statusFilter;

  List<VendorDefinition> get filteredVendors {
    final query = _normalize(_searchQuery);
    return _vendors
        .where((vendor) {
          final matchesStatus = switch (_statusFilter) {
            VendorStatusFilter.active => !vendor.isArchived,
            VendorStatusFilter.archived => vendor.isArchived,
            VendorStatusFilter.all => true,
          };
          if (!matchesStatus) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return _normalize(vendor.name).contains(query) ||
              _normalize(vendor.alias).contains(query) ||
              _normalize(vendor.gstNumber).contains(query) ||
              _normalize(vendor.contactName).contains(query) ||
              _normalize(vendor.phone).contains(query) ||
              _normalize(vendor.email).contains(query) ||
              _normalize(vendor.address).contains(query);
        })
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
      final vendors = await _repository.getVendors();
      vendors.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        final nameCompare = a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        );
        if (nameCompare != 0) {
          return nameCompare;
        }
        return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
      });
      _vendors = vendors;
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

  void setStatusFilter(VendorStatusFilter value) {
    _statusFilter = value;
    notifyListeners();
  }

  VendorDefinition? findById(int? id) {
    if (id == null) {
      return null;
    }
    for (final vendor in _vendors) {
      if (vendor.id == id) {
        return vendor;
      }
    }
    return null;
  }

  VendorDuplicateCheck checkDuplicate({
    required String name,
    required String gstNumber,
    int? excludeId,
  }) {
    final normalizedName = _normalize(name);
    final normalizedGst = _normalizeGstNumber(gstNumber);
    var nameMatch = false;
    var gstMatch = false;
    for (final vendor in _vendors) {
      if (excludeId != null && vendor.id == excludeId) {
        continue;
      }
      if (_normalize(vendor.name) == normalizedName) {
        nameMatch = true;
      }
      if (normalizedGst.isNotEmpty &&
          _normalizeGstNumber(vendor.gstNumber) == normalizedGst) {
        gstMatch = true;
      }
    }
    if (nameMatch && gstMatch) {
      return const VendorDuplicateCheck(
        blockingDuplicate: true,
        warning: VendorDuplicateWarning.nameAndGst,
      );
    }
    if (nameMatch) {
      return const VendorDuplicateCheck(
        blockingDuplicate: true,
        warning: VendorDuplicateWarning.nameOnly,
      );
    }
    if (gstMatch) {
      return const VendorDuplicateCheck(
        blockingDuplicate: true,
        warning: VendorDuplicateWarning.gstOnly,
      );
    }
    return const VendorDuplicateCheck(
      blockingDuplicate: false,
      warning: VendorDuplicateWarning.none,
    );
  }

  Future<VendorDefinition?> createVendor(CreateVendorInput input) =>
      _saveVendor(() => _repository.createVendor(input));

  Future<VendorDefinition?> updateVendor(UpdateVendorInput input) =>
      _saveVendor(() => _repository.updateVendor(input));

  Future<VendorDefinition?> archiveVendor(int id) =>
      _saveVendor(() => _repository.archiveVendor(id));

  Future<VendorDefinition?> restoreVendor(int id) =>
      _saveVendor(() => _repository.restoreVendor(id));

  Future<VendorDefinition?> _saveVendor(
    Future<VendorDefinition> Function() action,
  ) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final saved = await action();
      await refresh();
      return findById(saved.id) ?? saved;
    } catch (error) {
      _errorMessage = error.toString();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  static String normalizeGstNumber(String value) => _normalizeGstNumber(value);

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static String _normalizeGstNumber(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
}
