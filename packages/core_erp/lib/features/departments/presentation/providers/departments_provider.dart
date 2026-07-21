import 'package:flutter/material.dart';

import '../../domain/department_definition.dart';
import '../../domain/employee_definition.dart';
import '../../data/repositories/departments_repository.dart';

class DepartmentsProvider extends ChangeNotifier {
  DepartmentsProvider({required DepartmentsRepository repository})
    : _repository = repository;

  final DepartmentsRepository _repository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<DepartmentDefinition> _departments = [];
  List<DepartmentDefinition> get departments => _departments;

  List<EmployeeDefinition> _employees = [];
  List<EmployeeDefinition> get employees => _employees;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  String _employmentFilter = 'all';
  String get employmentFilter => _employmentFilter;

  DepartmentDefinition? _selectedDepartment;
  DepartmentDefinition? get selectedDepartment => _selectedDepartment;

  Future<void> load() async {
    _setLoading(true);
    _clearError();
    try {
      final futures = await Future.wait([
        _repository.getDepartments(),
        _repository.getEmployees(),
      ]);
      _departments = futures[0] as List<DepartmentDefinition>;
      _employees = futures[1] as List<EmployeeDefinition>;
      _sortLists();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  void selectDepartment(DepartmentDefinition? dept) {
    _selectedDepartment = dept;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase();
    notifyListeners();
  }

  void setEmploymentFilter(String value) {
    _employmentFilter = value;
    notifyListeners();
  }

  List<DepartmentDefinition> get filteredDepartments {
    if (_searchQuery.isEmpty) return _departments;
    return _departments
        .where((d) => d.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  List<EmployeeDefinition> employeesForDepartment(int departmentId) {
    var emps = _employees.where((e) => e.departmentId == departmentId).toList();
    if (_employmentFilter != 'all') {
      emps = emps.where((e) => e.employmentType == _employmentFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      emps = emps
          .where(
            (e) =>
                e.name.toLowerCase().contains(_searchQuery) ||
                e.role.toLowerCase().contains(_searchQuery) ||
                e.barcodeId.toLowerCase().contains(_searchQuery),
          )
          .toList();
    }
    return emps;
  }

  Future<bool> createDepartment(
    String name,
    String description,
    String photoUrl,
  ) async {
    _setSaving(true);
    _clearError();
    try {
      final dept = await _repository.createDepartment(
        name,
        description,
        photoUrl,
      );
      _departments.add(dept);
      _sortLists();
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setSaving(false);
    }
  }

  Future<bool> updateDepartment(
    int id,
    String name,
    String description,
    String photoUrl,
  ) async {
    _setSaving(true);
    _clearError();
    try {
      final dept = await _repository.updateDepartment(
        id,
        name,
        description,
        photoUrl,
      );
      final index = _departments.indexWhere((d) => d.id == id);
      if (index >= 0) {
        _departments[index] = dept;
        if (_selectedDepartment?.id == id) {
          _selectedDepartment = dept;
        }
        notifyListeners();
      }
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setSaving(false);
    }
  }

  Future<bool> deleteDepartment(int id) async {
    _setSaving(true);
    _clearError();
    try {
      await _repository.deleteDepartment(id);
      _departments.removeWhere((d) => d.id == id);
      if (_selectedDepartment?.id == id) {
        _selectedDepartment = null;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setSaving(false);
    }
  }

  Future<bool> createEmployee(
    int departmentId,
    String name,
    String role,
    String phone,
    String aadharNumber,
    String aadharPhotoUrl,
    String panNumber,
    String panPhotoUrl,
    String address,
    String employeePhotoUrl,
    String employmentType,
    String barcodeId, {
    String email = '',
    String dateOfBirth = '',
  }) async {
    _setSaving(true);
    _clearError();
    try {
      final emp = await _repository.createEmployee(
        departmentId,
        name,
        role,
        phone,
        aadharNumber,
        aadharPhotoUrl,
        panNumber,
        panPhotoUrl,
        address,
        employeePhotoUrl,
        employmentType,
        barcodeId,
        email: email,
        dateOfBirth: dateOfBirth,
      );
      _employees.add(emp);
      _sortLists();
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setSaving(false);
    }
  }

  Future<bool> updateEmployee(
    int id,
    int departmentId,
    String name,
    String role,
    String phone,
    String aadharNumber,
    String aadharPhotoUrl,
    String panNumber,
    String panPhotoUrl,
    String address,
    String employeePhotoUrl,
    String employmentType,
    String barcodeId, {
    String? email,
    String? dateOfBirth,
  }) async {
    _setSaving(true);
    _clearError();
    try {
      final emp = await _repository.updateEmployee(
        id,
        departmentId,
        name,
        role,
        phone,
        aadharNumber,
        aadharPhotoUrl,
        panNumber,
        panPhotoUrl,
        address,
        employeePhotoUrl,
        employmentType,
        barcodeId,
        email: email,
        dateOfBirth: dateOfBirth,
      );
      final index = _employees.indexWhere((e) => e.id == id);
      if (index >= 0) {
        _employees[index] = emp;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setSaving(false);
    }
  }

  Future<bool> deleteEmployee(int id) async {
    _setSaving(true);
    _clearError();
    try {
      await _repository.deleteEmployee(id);
      _employees.removeWhere((e) => e.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setSaving(false);
    }
  }

  void _replaceEmployee(EmployeeDefinition emp) {
    final index = _employees.indexWhere((e) => e.id == emp.id);
    if (index >= 0) {
      _employees[index] = emp;
      notifyListeners();
    }
  }

  /// Create + link a new login/profile account for an in-house employee.
  Future<bool> createEmployeeLogin(
    int employeeId, {
    required String email,
    required String password,
    String role = 'user',
  }) async {
    _setSaving(true);
    _clearError();
    try {
      _replaceEmployee(await _repository.createEmployeeLogin(
        employeeId, email: email, password: password, role: role,
      ));
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setSaving(false);
    }
  }

  /// Link an in-house employee to an existing login account.
  Future<bool> linkEmployeeLogin(int employeeId, int userId) async {
    _setSaving(true);
    _clearError();
    try {
      _replaceEmployee(await _repository.linkEmployeeLogin(employeeId, userId));
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setSaving(false);
    }
  }

  /// Unlink an employee from its login (the account is kept).
  Future<bool> unlinkEmployeeLogin(int employeeId) async {
    _setSaving(true);
    _clearError();
    try {
      _replaceEmployee(await _repository.unlinkEmployeeLogin(employeeId));
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    } finally {
      _setSaving(false);
    }
  }

  void _sortLists() {
    _departments.sort((a, b) => a.name.compareTo(b.name));
    _employees.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setSaving(bool value) {
    _isSaving = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _errorMessage = value;
    notifyListeners();
  }

  void _clearError() => _setError(null);
}
