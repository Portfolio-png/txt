import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/auth_user.dart';

class AuthApi {
  AuthApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? _token;

  set token(String? value) {
    _token = value;
  }

  Future<({AuthUser user, String token})> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(payload['error'] as String? ?? 'Login failed.');
    }
    return (
      user: AuthUser.fromJson(payload['user'] as Map<String, dynamic>),
      token: payload['token'] as String? ?? '',
    );
  }

  Future<AuthUser> me() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load user.',
      );
    }
    return AuthUser.fromJson(payload['user'] as Map<String, dynamic>);
  }

  Future<({List<AuthUser> users, int total, bool hasMore})> getUsers({
    String query = '',
    String role = '',
    bool? isActive,
    int limit = 25,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/api/users').replace(
      queryParameters: {
        if (query.trim().isNotEmpty) 'query': query.trim(),
        if (role.trim().isNotEmpty) 'role': role.trim(),
        if (isActive != null) 'isActive': isActive.toString(),
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final response = await _client.get(uri, headers: _authHeaders);
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load users.',
      );
    }
    final users = (payload['users'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AuthUser.fromJson)
        .toList(growable: false);
    final pagination =
        payload['pagination'] as Map<String, dynamic>? ?? const {};
    return (
      users: users,
      total: pagination['total'] as int? ?? users.length,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }

  Future<AuthUser> createUser({
    required String name,
    required String email,
    required String password,
    required bool admin,
  }) async {
    final path = admin ? 'admins' : 'users';
    final response = await _client.post(
      Uri.parse('$baseUrl/api/$path'),
      headers: _jsonHeaders,
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to create user.',
      );
    }
    return AuthUser.fromJson(payload['user'] as Map<String, dynamic>);
  }

  Future<void> resetPassword({
    required int userId,
    required String password,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/users/$userId/password'),
      headers: _jsonHeaders,
      body: jsonEncode({'newPassword': password}),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to reset password.',
      );
    }
  }

  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/me/password'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to change password.',
      );
    }
  }

  Future<void> setUserActive({
    required int userId,
    required bool active,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/users/$userId/status'),
      headers: _jsonHeaders,
      body: jsonEncode({'isActive': active}),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to update user status.',
      );
    }
  }

  Future<void> requestDelete({
    required String entityType,
    required String entityId,
    required String entityLabel,
    required String reason,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/delete-requests'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'entityType': entityType,
        'entityId': entityId,
        'entityLabel': entityLabel,
        'reason': reason,
      }),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to request deletion.',
      );
    }
  }

  Future<({List<DeleteRequest> requests, int total, bool hasMore})>
  getDeleteRequests({
    String status = '',
    int? requestedByUserId,
    DateTime? from,
    DateTime? to,
    int limit = 25,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/api/delete-requests').replace(
      queryParameters: {
        if (status.trim().isNotEmpty) 'status': status.trim(),
        if (requestedByUserId != null)
          'requestedByUserId': '$requestedByUserId',
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final response = await _client.get(uri, headers: _authHeaders);
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load delete requests.',
      );
    }
    final requests = (payload['requests'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DeleteRequest.fromJson)
        .toList(growable: false);
    final pagination =
        payload['pagination'] as Map<String, dynamic>? ?? const {};
    return (
      requests: requests,
      total: pagination['total'] as int? ?? requests.length,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }

  Future<void> reviewDeleteRequest(
    int id, {
    required bool approve,
    String reviewedNote = '',
  }) async {
    final action = approve ? 'approve' : 'reject';
    final response = await _client.post(
      Uri.parse('$baseUrl/api/delete-requests/$id/$action'),
      headers: _jsonHeaders,
      body: jsonEncode({'reviewedNote': reviewedNote}),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to review delete request.',
      );
    }
  }

  Future<void> logout() async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/logout'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to logout.',
      );
    }
  }

  Future<List<AuthSession>> getMySessions() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/auth/sessions'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load sessions.',
      );
    }
    return (payload['sessions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AuthSession.fromJson)
        .toList(growable: false);
  }

  Future<void> revokeMySession(String sessionId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/auth/sessions/$sessionId'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to revoke session.',
      );
    }
  }

  Future<List<AuthSession>> getUserSessions(int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/users/$userId/sessions'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load user sessions.',
      );
    }
    return (payload['sessions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AuthSession.fromJson)
        .toList(growable: false);
  }

  Future<void> revokeAllUserSessions(int userId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/users/$userId/sessions/revoke'),
      headers: _jsonHeaders,
      body: jsonEncode(const {}),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to revoke user sessions.',
      );
    }
  }

  Future<({List<AuthEvent> events, int total, bool hasMore})> getAuthEvents({
    String eventType = '',
    int? actorUserId,
    int? targetUserId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/events').replace(
      queryParameters: {
        if (eventType.trim().isNotEmpty) 'eventType': eventType.trim(),
        if (actorUserId != null) 'actorUserId': '$actorUserId',
        if (targetUserId != null) 'targetUserId': '$targetUserId',
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final response = await _client.get(uri, headers: _authHeaders);
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load auth events.',
      );
    }
    final events = (payload['events'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AuthEvent.fromJson)
        .toList(growable: false);
    final pagination =
        payload['pagination'] as Map<String, dynamic>? ?? const {};
    return (
      events: events,
      total: pagination['total'] as int? ?? events.length,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }

  Future<List<PermissionDescriptor>> getPermissionDescriptors() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/permissions'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load permission catalog.',
      );
    }
    return (payload['permissions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PermissionDescriptor.fromJson)
        .toList(growable: false);
  }

  Future<List<PermissionTemplate>> getPermissionTemplates({
    String query = '',
  }) async {
    final uri = Uri.parse('$baseUrl/api/permission-templates').replace(
      queryParameters: {if (query.trim().isNotEmpty) 'query': query.trim()},
    );
    final response = await _client.get(uri, headers: _authHeaders);
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load permission templates.',
      );
    }
    return (payload['templates'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PermissionTemplate.fromJson)
        .toList(growable: false);
  }

  Future<List<UserPermissionState>> getUserPermissions(int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/users/$userId/permissions'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load user permissions.',
      );
    }
    return (payload['permissions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UserPermissionState.fromJson)
        .toList(growable: false);
  }

  Future<List<int>> getUserPermissionTemplateIds(int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/users/$userId/permission-templates'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ??
            'Failed to load assigned permission templates.',
      );
    }
    return (payload['assignedTemplateIds'] as List<dynamic>? ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(growable: false);
  }

  Future<void> updateUserPermissionTemplates({
    required int userId,
    required List<int> templateIds,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/users/$userId/permission-templates'),
      headers: _jsonHeaders,
      body: jsonEncode({'templateIds': templateIds}),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ??
            'Failed to update assigned permission templates.',
      );
    }
  }

  Future<void> updateUserPermissions({
    required int userId,
    required List<UserPermissionState> states,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/api/users/$userId/permissions'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'overrides': states
            .map((state) => {'key': state.key, 'allowed': state.allowed})
            .toList(growable: false),
      }),
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to update user permissions.',
      );
    }
  }

  Map<String, dynamic> _decode(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('<')) {
      throw const AuthApiException(
        'The API returned HTML instead of JSON. Check PAPER_API_BASE_URL and restart the updated backend.',
      );
    }
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      throw const AuthApiException(
        'The API response was not valid JSON. Check that the Paper backend is running on the configured URL.',
      );
    }
  }

  Map<String, String> get _authHeaders {
    return {
      if (_token != null && _token!.isNotEmpty)
        'Authorization': 'Bearer $_token',
    };
  }

  Map<String, String> get _jsonHeaders {
    return {'Content-Type': 'application/json', ..._authHeaders};
  }
}

class AuthApiException implements Exception {
  const AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
