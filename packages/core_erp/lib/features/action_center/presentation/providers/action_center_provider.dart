import 'package:flutter/foundation.dart';

import '../../data/action_center_repository.dart';
import '../../domain/action_center_models.dart';

class ActionCenterProvider extends ChangeNotifier {
  ActionCenterProvider({required ActionCenterRepository repository})
      : _repository = repository;

  final ActionCenterRepository _repository;

  List<ActionCenterIssue> _issues = const <ActionCenterIssue>[];
  List<TrashedRecord> _trash = const <TrashedRecord>[];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  final Set<String> _restoring = <String>{};

  List<ActionCenterIssue> get issues => _issues;
  List<TrashedRecord> get trash => _trash;
  bool get isLoading => _isLoading;

  /// True once the first load has completed (success or failure). Used to show
  /// the full-screen spinner only on the very first load.
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

  int get errorCount => _issues.where((i) => i.isError).length;
  int get warningCount => _issues.where((i) => !i.isError).length;

  static String _key(String tableName, int recordId) => '$tableName#$recordId';

  bool isRestoring(String tableName, int recordId) =>
      _restoring.contains(_key(tableName, recordId));

  /// Re-fetch issues + trash. Called every time the screen opens so the data is
  /// never stale across a logout/login. The two endpoints are fetched
  /// independently: a failure of one still shows the other's results.
  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final errors = <String>[];
    try {
      _issues = await _repository.getIssues();
    } catch (error) {
      errors.add(error.toString());
    }
    try {
      _trash = await _repository.listTrash();
    } catch (error) {
      errors.add(error.toString());
    }

    _errorMessage = errors.isEmpty ? null : errors.join('\n');
    _isLoading = false;
    _hasLoaded = true;
    notifyListeners();
  }

  /// Restore a record from the trash. Returns true on success, after which the
  /// issues + trash lists are refreshed so a resolved reference disappears.
  Future<bool> restore(String tableName, int recordId) async {
    final key = _key(tableName, recordId);
    if (_restoring.contains(key)) return false;
    _restoring.add(key);
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.restore(tableName, recordId);
      _restoring.remove(key);
      await refresh();
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      _restoring.remove(key);
      notifyListeners();
      return false;
    }
  }
}
