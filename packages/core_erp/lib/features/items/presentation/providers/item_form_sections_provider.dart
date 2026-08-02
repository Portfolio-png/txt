import 'package:flutter/foundation.dart';

import '../../../../core/services/user_preferences_service.dart';
import '../../domain/item_form_sections.dart';

/// Holds the signed-in user's item-editor section layout and keeps it in sync
/// with the backend, so the choice is the default everywhere the item editor
/// opens rather than per-dialog state.
class ItemFormSectionsProvider extends ChangeNotifier {
  ItemFormSectionsProvider({required UserPreferencesService service})
    : _service = service;

  static const String preferenceKey = 'item_form_sections';

  final UserPreferencesService _service;

  ItemFormSections _sections = const ItemFormSections();
  bool _isLoaded = false;
  bool _isLoading = false;
  String? _errorMessage;

  ItemFormSections get sections => _sections;
  bool get isLoaded => _isLoaded;
  String? get errorMessage => _errorMessage;

  /// Safe to call on every editor open — the fetch only happens once.
  Future<void> ensureLoaded() async {
    if (_isLoaded || _isLoading) {
      return;
    }
    _isLoading = true;
    try {
      final stored = await _service.read(preferenceKey);
      if (stored != null) {
        _sections = ItemFormSections.fromJson(stored);
      }
      _errorMessage = null;
    } catch (error) {
      // A preference read failure must never block item creation — fall back to
      // the defaults and let the user carry on.
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// Applies the change immediately so the form reacts, then persists. On a
  /// write failure the value is rolled back so the UI never claims a default
  /// that was not saved.
  Future<bool> setSection(ItemFormSectionKey key, bool value) async {
    final previous = _sections;
    _sections = key.applyTo(_sections, value);
    _errorMessage = null;
    notifyListeners();

    try {
      await _service.write(preferenceKey, _sections.toJson());
      return true;
    } catch (error) {
      _sections = previous;
      _errorMessage = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetToDefaults() async {
    final previous = _sections;
    _sections = const ItemFormSections();
    notifyListeners();
    try {
      await _service.write(preferenceKey, _sections.toJson());
      return true;
    } catch (error) {
      _sections = previous;
      _errorMessage = error.toString();
      notifyListeners();
      return false;
    }
  }
}
