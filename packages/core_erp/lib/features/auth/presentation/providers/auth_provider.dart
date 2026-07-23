import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/auth_api.dart';
import '../../domain/auth_user.dart';
import '../../domain/global_audit_log.dart';
import '../../domain/track_event.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required String baseUrl,
    bool demoMode = false,
    this.onUserCreated,
  }) : _demoMode = demoMode,
       _api = AuthApi(baseUrl: baseUrl);

  final AuthApi _api;
  final bool _demoMode;
  final void Function(String email, String role)? onUserCreated;

  AuthUser? _user;
  String? _token;
  bool _isLoading = false;
  String? _errorMessage;
  List<AuthUser> _users = const [];
  List<DeleteRequest> _deleteRequests = const [];
  List<AuthSession> _mySessions = const [];
  List<AuthEvent> _authEvents = const [];
  List<GlobalAuditLog> _globalAuditLogs = const [];
  List<PermissionDescriptor> _permissionDescriptors = const [];
  List<PermissionTemplate> _permissionTemplates = const [];
  String _userQuery = '';
  String _userRoleFilter = '';
  String _deleteStatusFilter = 'pending';
  String _eventTypeFilter = '';
  int _usersTotal = 0;
  int _deleteRequestsTotal = 0;
  int _authEventsTotal = 0;
  int _globalAuditLogsTotal = 0;
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
  List<GlobalAuditLog> get globalAuditLogs => _globalAuditLogs;
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
  int get globalAuditLogsTotal => _globalAuditLogsTotal;
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
      String platform;
      if (kIsWeb) {
        platform = 'web';
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
        platform = 'mobile';
      } else {
        platform = 'desktop';
      }

      final result = await _api.login(email: email, password: password, platform: platform);
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

  Future<bool> loginWithPin({required String pin}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      String platform;
      if (kIsWeb) {
        platform = 'web';
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
        platform = 'mobile';
      } else {
        platform = 'desktop';
      }

      final result = await _api.loginWithPin(pin: pin, platform: platform);
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
    _globalAuditLogsTotal = 0;
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
    refreshDeleteRequests();
  }

  /// Focused fetch of just the delete-request queue, without pulling the full
  /// user-management payload (users, audit, sessions, permissions). Used by the
  /// Action Center, which surfaces pending delete requests as actionable items.
  Future<void> refreshDeleteRequests() async {
    if (_demoMode || !can('delete_requests.review')) {
      _deleteRequests = const [];
      _deleteRequestsTotal = 0;
      _deleteRequestsHasMore = false;
      notifyListeners();
      return;
    }
    try {
      final response = await _api.getDeleteRequests(
        status: _deleteStatusFilter,
        limit: 50,
        offset: 0,
      );
      _deleteRequests = response.requests;
      _deleteRequestsTotal = response.total;
      _deleteRequestsHasMore = response.hasMore;
      notifyListeners();
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to load delete requests.',
      );
      notifyListeners();
    }
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

        final globalResponse = await _api.getGlobalAuditLogs(
          limit: 100,
          offset: 0,
        );
        _globalAuditLogs = globalResponse.logs;
        _globalAuditLogsTotal = globalResponse.total;
      } else {
        _authEvents = const [];
        _authEventsTotal = 0;
        _authEventsHasMore = false;
        _globalAuditLogs = const [];
        _globalAuditLogsTotal = 0;
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
    int? clientId,
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
        clientId: clientId,
      );

      // Sync the user to the control plane sandbox dashboard
      onUserCreated?.call(email, admin ? 'admin' : 'worker');

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

  Future<bool> deleteUser({required int userId, bool override = false}) async {
    if (!can('users.manage_permissions')) {
      _errorMessage = 'You do not have permission to delete users.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.deleteUser(userId: userId, override: override);
      await loadManagementData();
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to delete user.');
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

  Future<bool> factoryResetDatabase() async {
    if (!can('config.write')) {
      _errorMessage = 'You do not have permission to factory reset the database.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.factoryResetDatabase();
      return true;
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to factory reset database.',
      );
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clears only the current user's own data. No special permission required —
  /// every signed-in user can reset their personal favorites and search history.
  Future<bool> clearMyData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.clearMyData();
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to clear your data.');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> reseedDemoData({String scenarioId = 'default'}) async {
    if (!can('config.write')) {
      _errorMessage = 'You do not have permission to reseed demo data.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.reseedDemoData(scenarioId: scenarioId);
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to reseed demo data.');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> resetDemoData({String scenarioId = 'default'}) async {
    if (!can('config.write')) {
      _errorMessage = 'You do not have permission to reset demo data.';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _api.resetDemoData(scenarioId: scenarioId);
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to reset demo data.');
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
      await refreshDeleteRequests();
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

  /// Loads the permission descriptor catalog + templates on demand, so the
  /// permissions editor works from anywhere (e.g. the People account panel)
  /// without first opening the old user-management screen.
  Future<void> ensurePermissionCatalog() async {
    if (_demoMode || !can('users.manage_permissions')) return;
    try {
      if (_permissionDescriptors.isEmpty) {
        _permissionDescriptors = await _api.getPermissionDescriptors();
      }
      if (_permissionTemplates.isEmpty) {
        _permissionTemplates = await _api.getPermissionTemplates();
      }
      notifyListeners();
    } catch (error) {
      _errorMessage = _friendly(
        error,
        fallback: 'Failed to load the permission catalog.',
      );
      notifyListeners();
    }
  }

  Future<void> reloadPermissionTemplates() async {
    try {
      _permissionTemplates = await _api.getPermissionTemplates();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> createPermissionPreset({
    required String name,
    required String description,
    required List<String> permissions,
  }) async {
    try {
      await _api.createPermissionTemplate(
        name: name,
        description: description,
        permissions: permissions,
      );
      await reloadPermissionTemplates();
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to create preset.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updatePermissionPreset({
    required int id,
    String? name,
    String? description,
    List<String>? permissions,
  }) async {
    try {
      await _api.updatePermissionTemplate(
        id: id,
        name: name,
        description: description,
        permissions: permissions,
      );
      await reloadPermissionTemplates();
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to update preset.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deletePermissionPreset(int id) async {
    try {
      await _api.deletePermissionTemplate(id);
      await reloadPermissionTemplates();
      return true;
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to delete preset.');
      notifyListeners();
      return false;
    }
  }

  Future<List<RecordGrant>> getUserRecordPermissions(int userId) async {
    try {
      return await _api.getUserRecordPermissions(userId);
    } catch (error) {
      _errorMessage =
          _friendly(error, fallback: 'Failed to load record permissions.');
      notifyListeners();
      return const [];
    }
  }

  Future<bool> updateUserRecordPermissions(
    int userId,
    List<Map<String, String>> records,
  ) async {
    try {
      await _api.updateUserRecordPermissions(userId, records);
      return true;
    } catch (error) {
      _errorMessage =
          _friendly(error, fallback: 'Failed to save record permissions.');
      notifyListeners();
      return false;
    }
  }

  Future<List<RecordOption>> getRecordOptions(
    String entityType, {
    String query = '',
  }) async {
    try {
      return await _api.getRecordOptions(entityType, query: query);
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to load records.');
      notifyListeners();
      return const [];
    }
  }

  /// Track feed for one master record (the "Track" tab on a master screen).
  Future<List<TrackEvent>> getEntityTrack(
    String entityType,
    String entityId,
  ) async {
    try {
      return await _api.getEntityTrack(entityType, entityId);
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to load track.');
      notifyListeners();
      return const [];
    }
  }

  /// Track feed for one person — everything they changed across the app.
  Future<List<TrackEvent>> getActorTrack(int userId) async {
    try {
      return await _api.getActorTrack(userId);
    } catch (error) {
      _errorMessage = _friendly(error, fallback: 'Failed to load track.');
      notifyListeners();
      return const [];
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
