import 'package:flutter/foundation.dart';

import '../../../../core/services/socket_service.dart';
import '../../data/sheet_property_repository.dart';
import '../../domain/sheet_property.dart';

/// The item sheet's property columns, shared by every window.
///
/// Follows the server: a column added, renamed, given an option or removed in
/// another window arrives as `item_sheet_properties_changed`.
class SheetPropertiesProvider extends ChangeNotifier {
  SheetPropertiesProvider({required SheetPropertyRepository repository})
      : _repository = repository {
    SocketService.instance.on('item_sheet_properties_changed', _onRemoteChange);
  }

  final SheetPropertyRepository _repository;

  List<SheetProperty> _properties = const [];
  bool _loaded = false;
  bool _loading = false;
  bool _disposed = false;
  String? _errorMessage;

  List<SheetProperty> get properties => _properties;
  bool get isLoaded => _loaded;
  String? get errorMessage => _errorMessage;

  SheetProperty? byKey(String key) {
    final wanted = key.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return _properties.where((p) => p.key == wanted).firstOrNull;
  }

  void _onRemoteChange(dynamic _) {
    if (_loaded && !_loading) refresh();
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    try {
      _properties = await _repository.list();
      _loaded = true;
      _errorMessage = null;
    } catch (error) {
      _errorMessage = '$error';
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Adds a column; a name already on the sheet answers with that column.
  Future<SheetProperty?> create({
    required String name,
    required String kind,
    List<String> options = const [],
  }) async {
    try {
      final made = await _repository.create(name: name, kind: kind, options: options);
      _put(made);
      return made;
    } on SheetPropertyException catch (error) {
      if (error.code == 'property_exists' && error.existing != null) {
        _put(error.existing!);
        return error.existing;
      }
      return _failed(error);
    } catch (error) {
      return _failed(error);
    }
  }

  Future<SheetProperty?> rename(int id, String name) =>
      _write(() => _repository.update(id, name: name));

  Future<SheetProperty?> replaceOptions(int id, List<String> options) =>
      _write(() => _repository.update(id, options: options));

  /// A value typed into the column joins its list for everyone.
  Future<SheetProperty?> addOption(int id, String label) =>
      _write(() => _repository.addOption(id, label));

  Future<bool> remove(int id) async {
    try {
      await _repository.remove(id);
      _properties = [for (final p in _properties) if (p.id != id) p];
      _notify();
      return true;
    } catch (error) {
      _failed(error);
      return false;
    }
  }

  Future<SheetProperty?> _write(Future<SheetProperty> Function() action) async {
    try {
      final saved = await action();
      _put(saved);
      return saved;
    } catch (error) {
      return _failed(error);
    }
  }

  void _put(SheetProperty property) {
    final at = _properties.indexWhere((p) => p.id == property.id);
    _properties = at < 0
        ? ([..._properties, property]..sort((a, b) => a.position.compareTo(b.position)))
        : [for (final p in _properties) p.id == property.id ? property : p];
    _errorMessage = null;
    _notify();
  }

  T? _failed<T>(Object error) {
    _errorMessage = '$error';
    _notify();
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    SocketService.instance.off('item_sheet_properties_changed', _onRemoteChange);
    super.dispose();
  }
}
