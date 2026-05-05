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
  List<PermissionTemplate> _permissionTemplates = const [];
  String _userQuery = '';
  String _userRoleFilter = '';
  String _deleteStatusFilter = 'pending';
  String _eventTypeFilter = '';
  int _usersTotal = 0;
  int _deleteRequestsTotal = 0;
  int _authEventsTotal = 0;
  bool _usersHasMore = false;
  bool _deleteRequestsHasMore = false;
  bool _authEventsHasMore = false;

  static const String passwordPolicyMessage =
      'Use at least 10 characters with letters and numbers. Avoid names or common words.';

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
  List<PermissionTemplate> get permissionTemplates => _permissionTemplates;
  String get userQuery => _userQuery;
  String get userRoleFilter => _userRoleFilter;
  String get deleteStatusFilter => _deleteStatusFilter;
  String get eventTypeFilter => _eventTypeFilter;
  int get usersTotal => _usersTotal;
  int get deleteRequestsTotal => _deleteRequestsTotal;
  int get authEventsTotal => _authEventsTotal;
  bool get usersHasMore => _usersHasMore;
  bool get deleteRequestsHasMore => _deleteRequestsHasMore;
  bool get authEventsHasMore => _authEventsHasMore;
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
    _permissionTemplates = const [];
    _usersTotal = 0;
    _deleteRequestsTotal = 0;
    _authEventsTotal = 0;
    _usersHasMore = false;
    _deleteRequestsHasMore = false;
    _authEventsHasMore = false;
    notifyListeners();
  }

  void updateUserFilters({String? query, String? role}) {
    _userQuery = query ?? _userQuery;
    _userRoleFilter = role ?? _userRoleFilter;
    loadManagementData();
  }

  void updateDeleteRequestFilter(String status) {
    _deleteStatusFilter = status.trim();
    loadManagementData();
  }

  void updateEventTypeFilter(String eventType) {
    _eventTypeFilter = eventType.trim();
    loadManagementData();
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
        final response = await _api.getUsers(
          query: _userQuery,
          role: _userRoleFilter,
          limit: 50,
          offset: 0,
        );
        _users = response.users;
        _usersTotal = response.total;
        _usersHasMore = response.hasMore;
      } else {
        _users = const [];
        _usersTotal = 0;
        _usersHasMore = false;
      }
      if (can('delete_requests.review')) {
        final response = await _api.getDeleteRequests(
          status: _deleteStatusFilter,
          limit: 50,
          offset: 0,
        );
        _deleteRequests = response.requests;
        _deleteRequestsTotal = response.total;
        _deleteRequestsHasMore = response.hasMore;
      } else {
        _deleteRequests = const [];
        _deleteRequestsTotal = 0;
        _deleteRequestsHasMore = false;
      }
      if (can('audit.read')) {
        final response = await _api.getAuthEvents(
          eventType: _eventTypeFilter,
          limit: 100,
          offset: 0,
        );
        _authEvents = response.events;
        _authEventsTotal = response.total;
        _authEventsHasMore = response.hasMore;
      } else {
        _authEvents = const [];
        _authEventsTotal = 0;
        _authEventsHasMore = false;
      }
      if (can('sessions.manage')) {
        _mySessions = await _api.getMySessions();
      } else {
        _mySessions = const [];
      }
      if (can('users.manage_permissions')) {
        _permissionDescriptors = await _api.getPermissionDescriptors();
        _permissionTemplates = await _api.getPermissionTemplates();
      } else {
        _permissionDescriptors = const [];
        _permissionTemplates = const [];
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

  Future<bool> clearBackendDatabase() async {
    if (!can('config.write')) {
      _errorMessage = 'You do not have permission to clear backend data.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.clearBackendDatabase();
      return true;
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to clear backend database.',
      );
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> reseedDemoData() async {
    if (!can('config.write')) {
      _errorMessage = 'You do not have permission to reseed demo data.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.reseedDemoData();
      return true;
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to reseed demo data.',
      );
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
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

  Future<bool> reviewDeleteRequest(
    int id, {
    required bool approve,
    String reviewedNote = '',
  }) async {
    if (!can('delete_requests.review')) {
      _errorMessage = 'You do not have permission to review delete requests.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.reviewDeleteRequest(
        id,
        approve: approve,
        reviewedNote: reviewedNote,
      );
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

  Future<List<int>> getUserPermissionTemplateIds(int userId) async {
    if (!can('users.manage_permissions')) {
      _errorMessage = 'You do not have permission to manage permissions.';
      notifyListeners();
      return const [];
    }
    try {
      return await _api.getUserPermissionTemplateIds(userId);
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to load assigned templates.',
      );
      notifyListeners();
      return const [];
    }
  }

  Future<bool> updateUserPermissionTemplates({
    required int userId,
    required List<int> templateIds,
  }) async {
    if (!can('users.manage_permissions')) {
      _errorMessage = 'You do not have permission to manage permissions.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.updateUserPermissionTemplates(
        userId: userId,
        templateIds: templateIds,
      );
      return true;
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to update assigned templates.',
      );
      notifyListeners();
      return false;
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
