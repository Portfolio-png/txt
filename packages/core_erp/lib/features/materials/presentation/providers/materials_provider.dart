import 'package:flutter/foundation.dart';

import '../../data/material_repository.dart';
import '../../domain/material_definition.dart';

/// Holds the material master for the screens that read densities.
///
/// The catalogue is small and rarely edited, so it is loaded once and kept —
/// sheet planning asks it for a density on every keystroke and cannot wait on a
/// request each time.
class MaterialsProvider extends ChangeNotifier {
  MaterialsProvider({required MaterialRepository repository})
    : _repository = repository;

  final MaterialRepository _repository;

  List<MaterialDefinition> _materials = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _searchQuery = '';
  bool _initialized = false;

  List<MaterialDefinition> get materials => _materials;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  List<MaterialDefinition> get filteredMaterials =>
      _materials.where((material) => material.matches(_searchQuery)).toList();

  String imageUrl(MaterialDefinition material) =>
      _repository.imageUrl(material);

  /// The density to weigh a sheet with, or null when the material is unknown.
  ///
  /// Returns null rather than a default because a wrong density is worse than
  /// no weight at all: it is a plausible-looking number nobody re-checks.
  MaterialDefinition? byName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final needle = name.trim().toLowerCase();
    for (final material in _materials) {
      if (material.name.toLowerCase() == needle) return material;
    }
    return null;
  }

  Future<void> ensureLoaded() async {
    if (_initialized || _isLoading) return;
    await load();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _materials = _sorted(await _repository.list());
      _initialized = true;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  /// Resolves to the saved material, or null on failure ([errorMessage]).
  Future<MaterialDefinition?> save(MaterialDefinition material) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final saved = material.id > 0
          ? await _repository.update(material)
          : await _repository.create(material);
      final next = _materials.where((m) => m.id != saved.id).toList()
        ..add(saved);
      _materials = _sorted(next);
      return saved;
    } catch (error) {
      _errorMessage = error.toString();
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> archive(MaterialDefinition material) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.archive(material.id);
      _materials = _materials.where((m) => m.id != material.id).toList();
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// Grouped by category, then alphabetical. Metals sit together because that
  /// is how someone scanning for one thinks about the list.
  static List<MaterialDefinition> _sorted(List<MaterialDefinition> input) {
    const order = <String, int>{'metal': 0, 'plastic': 1, 'other': 2};
    final out = [...input];
    out.sort((a, b) {
      final rank = (order[a.category] ?? 3).compareTo(order[b.category] ?? 3);
      return rank != 0
          ? rank
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }
}
