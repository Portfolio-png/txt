import 'package:flutter/material.dart';

import '../../data/auth_api.dart';
import '../../domain/auth_user.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({required String baseUrl, bool demoMode = false})
    : _demoMode = demoMode,
      _api = AuthApi(baseUrl: baseUrl);

  final AuthApi _api;
  final bool _demoMode;

  AuthUser? _user;
  String? _token;
  bool _isLoading = false;
  String? _errorMessage;
  List<AuthUser> _users = const [];
  List<DeleteRequest> _deleteRequests = const [];
  List<AuthSession> _mySessions = const [];
  List<AuthEvent> _authEvents = const [];
  List<PermissionDescriptor> _permissionDescriptors = const [];

  AuthUser? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<AuthUser> get users => _users;
  List<DeleteRequest> get deleteRequests => _deleteRequests;
  List<AuthSession> get mySessions => _mySessions;
  List<AuthEvent> get authEvents => _authEvents;
  List<PermissionDescriptor> get permissionDescriptors =>
      _permissionDescriptors;
  bool get isAuthenticated => _user != null || _demoMode;
  bool get isAdmin => _demoMode || (_user?.isAdmin ?? false);
  bool get isSuperAdmin => _user?.isSuperAdmin ?? _demoMode;
  bool get isRegularUser => !_demoMode && (_user?.isRegularUser ?? false);
  bool get canAccessUserManagement =>
      can('users.read') ||
      can('delete_requests.review') ||
      can('audit.read') ||
      can('sessions.manage') ||
      can('users.manage_permissions');

  bool can(String permissionKey) {
    if (_demoMode) {
      return true;
    }
    return _user?.can(permissionKey) ?? false;
  }

  Future<void> initialize() async {
    if (_demoMode) {
      _user = const AuthUser(
        id: 0,
        name: 'Demo Admin',
        email: 'demo@paper.local',
        role: 'super_admin',
        permissions: <String>[],
        isActive: true,
      );
      notifyListeners();
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _api.login(email: email, password: password);
      _user = result.user;
      _token = result.token;
      _api.token = _token;
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Login failed.');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void logout() {
    _user = null;
    _token = null;
    _api.token = null;
    _users = const [];
    _deleteRequests = const [];
    _mySessions = const [];
    _authEvents = const [];
    _permissionDescriptors = const [];
    notifyListeners();
  }

  Future<void> logoutRemote() async {
    if (_token != null && _token!.isNotEmpty) {
      try {
        await _api.logout();
      } catch (_) {}
    }
    logout();
  }

  Future<void> loadManagementData() async {
    if (!canAccessUserManagement || _demoMode) {
      return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (can('users.read')) {
        _users = await _api.getUsers();
      } else {
        _users = const [];
      }
      if (can('delete_requests.review')) {
        _deleteRequests = await _api.getDeleteRequests();
      } else {
        _deleteRequests = const [];
      }
      if (can('audit.read')) {
        _authEvents = await _api.getAuthEvents();
      } else {
        _authEvents = const [];
      }
      if (can('sessions.manage')) {
        _mySessions = await _api.getMySessions();
      } else {
        _mySessions = const [];
      }
      if (can('users.manage_permissions')) {
        _permissionDescriptors = await _api.getPermissionDescriptors();
      } else {
        _permissionDescriptors = const [];
      }
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to load user management data.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createUser({
    required String name,
    required String email,
    required String password,
    required bool admin,
  }) async {
    if (admin && !can('users.create_admin')) {
      _errorMessage = 'You do not have permission to create admins.';
      notifyListeners();
      return false;
    }
    if (!admin && !can('users.create_user')) {
      _errorMessage = 'You do not have permission to create users.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.createUser(
        name: name,
        email: email,
        password: password,
        admin: admin,
      );
      await loadManagementData();
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to create user.');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> resetPassword({
    required int userId,
    required String password,
  }) async {
    if (!can('users.reset_password')) {
      _errorMessage = 'You do not have permission to reset passwords.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.resetPassword(userId: userId, password: password);
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to reset password.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> setUserActive({
    required int userId,
    required bool active,
  }) async {
    if (!can('users.update_status')) {
      _errorMessage = 'You do not have permission to update user status.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.setUserActive(userId: userId, active: active);
      await loadManagementData();
      return true;
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to update user status.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.changeOwnPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to change password.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestDelete({
    required String entityType,
    required String entityId,
    required String entityLabel,
    required String reason,
  }) async {
    if (!can('inventory.request_delete')) {
      _errorMessage = 'You do not have permission to request deletion.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.requestDelete(
        entityType: entityType,
        entityId: entityId,
        entityLabel: entityLabel,
        reason: reason,
      );
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to request deletion.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> reviewDeleteRequest(int id, {required bool approve}) async {
    if (!can('delete_requests.review')) {
      _errorMessage = 'You do not have permission to review delete requests.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.reviewDeleteRequest(id, approve: approve);
      await loadManagementData();
      return true;
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to review delete request.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<List<AuthSession>> getUserSessions(int userId) async {
    if (!can('sessions.manage')) {
      _errorMessage = 'You do not have permission to view sessions.';
      notifyListeners();
      return const [];
    }
    try {
      return await _api.getUserSessions(userId);
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to load sessions.');
      notifyListeners();
      return const [];
    }
  }

  Future<bool> revokeAllUserSessions(int userId) async {
    if (!can('sessions.manage')) {
      _errorMessage = 'You do not have permission to revoke sessions.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.revokeAllUserSessions(userId);
      await loadManagementData();
      return true;
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to revoke user sessions.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<List<UserPermissionState>> getUserPermissions(int userId) async {
    if (!can('users.manage_permissions')) {
      _errorMessage = 'You do not have permission to manage permissions.';
      notifyListeners();
      return const [];
    }
    try {
      return await _api.getUserPermissions(userId);
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to load user permissions.',
      );
      notifyListeners();
      return const [];
    }
  }

  Future<bool> updateUserPermissions({
    required int userId,
    required List<UserPermissionState> states,
  }) async {
    if (!can('users.manage_permissions')) {
      _errorMessage = 'You do not have permission to manage permissions.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.updateUserPermissions(userId: userId, states: states);
      return true;
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to update user permissions.',
      );
      notifyListeners();
      return false;
    }
  }

  String _friendly(Object error, {required String fallback}) {
    if (error is AuthApiException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    final text = error.toString();
    return text.trim().isEmpty ? fallback : text;
  }
}
