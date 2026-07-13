import 'package:flutter/material.dart';

import '../../data/repositories/vendor_repository.dart';
import '../../domain/vendor_definition.dart';
import '../../domain/vendor_inputs.dart';
import '../../../../core/services/socket_service.dart';

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

  bool _initialized = false;

  List<VendorDefinition> get vendors => _vendors;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  List<VendorDefinition> get filteredVendors {
    final query = _normalize(_searchQuery);
    return _vendors
        .where((vendor) {
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

  void _sortVendors() {
    _vendors.sort((a, b) {
      final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameCompare != 0) {
        return nameCompare;
      }
      return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
    });
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    SocketService.instance.on('vendor_added', (data) async {
      if (data != null && data is Map<String, dynamic> && data['id'] != null) {
        try {
          final id = data['id'] as int;
          final newVendor = await _repository.getVendor(id);
          if (newVendor != null) {
            // Dedupe: the creator already refreshed the list, so this rail echo
            // must replace-if-present (not blindly append) to avoid a duplicate.
            final exists = _vendors.any((v) => v.id == newVendor.id);
            _vendors = exists
                ? _vendors
                      .map((v) => v.id == newVendor.id ? newVendor : v)
                      .toList(growable: false)
                : [..._vendors, newVendor];
            _sortVendors();
            notifyListeners();
          } else {
            refresh();
          }
        } catch (_) {
          refresh();
        }
      } else {
        refresh();
      }
    });

    SocketService.instance.on('vendor_updated', (data) async {
      if (data != null && data is Map<String, dynamic> && data['id'] != null) {
        try {
          final id = data['id'] as int;
          final updatedVendor = await _repository.getVendor(id);
          if (updatedVendor != null) {
            _vendors = _vendors
                .map((v) => v.id == updatedVendor.id ? updatedVendor : v)
                .toList(growable: false);
            _sortVendors();
            notifyListeners();
          } else {
            refresh();
          }
        } catch (_) {
          refresh();
        }
      } else {
        refresh();
      }
    });

    SocketService.instance.on('vendor_deleted', (data) {
      if (data != null && data is Map<String, dynamic> && data['id'] != null) {
        final id = data['id'] as int;
        _vendors = _vendors.where((v) => v.id != id).toList();
        notifyListeners();
      } else {
        refresh();
      }
    });

    await refresh();
  }

  @override
  void dispose() {
    SocketService.instance.off('vendor_added');
    SocketService.instance.off('vendor_updated');
    SocketService.instance.off('vendor_deleted');
    super.dispose();
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

  Future<void> deleteVendor(int id) async {
    if (_isSaving) return;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.deleteVendor(id);
      await refresh();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<VendorDefinition?> _saveVendor(
    Future<VendorDefinition> Function() action,
  ) async {
    if (_isSaving) return null;
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
