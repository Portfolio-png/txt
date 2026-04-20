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

  Future<List<AuthUser>> getUsers() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/users'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load users.',
      );
    }
    return (payload['users'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AuthUser.fromJson)
        .toList(growable: false);
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

  Future<List<DeleteRequest>> getDeleteRequests() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/delete-requests?status=pending'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load delete requests.',
      );
    }
    return (payload['requests'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DeleteRequest.fromJson)
        .toList(growable: false);
  }

  Future<void> reviewDeleteRequest(int id, {required bool approve}) async {
    final action = approve ? 'approve' : 'reject';
    final response = await _client.post(
      Uri.parse('$baseUrl/api/delete-requests/$id/$action'),
      headers: _authHeaders,
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

  Future<List<AuthEvent>> getAuthEvents({int limit = 100}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/auth/events?limit=$limit'),
      headers: _authHeaders,
    );
    final payload = _decode(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw AuthApiException(
        payload['error'] as String? ?? 'Failed to load auth events.',
      );
    }
    return (payload['events'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AuthEvent.fromJson)
        .toList(growable: false);
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
