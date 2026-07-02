import 'package:flutter/foundation.dart';
import '../../data/hr_repository.dart';

/// Holds the shared HR masters (employees, components, runs, leave types,
/// statutory config). Per-screen detail (a structure, a month's attendance,
/// one employee's balances) is fetched on demand by the screen via [repo].
class HrProvider extends ChangeNotifier {
  HrProvider({required this.repo});

  final HrRepository repo;

  bool loading = false;
  String? error;

  List<Map<String, dynamic>> employees = [];
  List<Map<String, dynamic>> components = [];
  List<Map<String, dynamic>> runs = [];
  List<Map<String, dynamic>> leaveTypes = [];
  Map<String, dynamic>? statutory;

  Future<void> loadCore() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await Future.wait([
        repo.employees(),
        repo.components(),
        repo.runs(),
        repo.leaveTypes(),
        repo.statutory(),
      ]);
      employees = r[0] as List<Map<String, dynamic>>;
      components = r[1] as List<Map<String, dynamic>>;
      runs = r[2] as List<Map<String, dynamic>>;
      leaveTypes = r[3] as List<Map<String, dynamic>>;
      statutory = r[4] as Map<String, dynamic>?;
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  /// Set (or clear, with null) the error banner from a widget.
  void setError(String? message) {
    error = message;
    notifyListeners();
  }

  Future<void> refreshRuns() async {
    runs = await repo.runs();
    notifyListeners();
  }

  Future<void> refreshComponents() async {
    components = await repo.components();
    notifyListeners();
  }

  Future<void> refreshLeaveTypes() async {
    leaveTypes = await repo.leaveTypes();
    notifyListeners();
  }

  Future<void> refreshStatutory() async {
    statutory = await repo.statutory();
    notifyListeners();
  }

  /// Runs an action and reports failure via [error] without throwing at the UI.
  /// Returns true on success.
  Future<bool> guard(Future<void> Function() action) async {
    try {
      await action();
      error = null;
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  String employeeName(int id) {
    final e = employees.firstWhere(
      (x) => x['id'] == id,
      orElse: () => const {'name': ''},
    );
    return (e['name'] as String?) ?? '';
  }
}
