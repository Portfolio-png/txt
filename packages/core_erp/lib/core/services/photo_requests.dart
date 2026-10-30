import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'socket_service.dart';

/// One line of what the phone shows over the camera: "Made by · Ashok Dies".
@immutable
class PhotoRequestLine {
  const PhotoRequestLine(this.label, this.value);

  final String label;
  final String value;
}

/// A photo the desktop asked the phone to take: which record, where its slot
/// sits, and what to show the person holding the camera.
@immutable
class PhotoRequest {
  const PhotoRequest({
    required this.id,
    required this.owner,
    required this.entityId,
    this.context = '',
    this.kind = '',
    this.title = '',
    this.lines = const [],
  });

  factory PhotoRequest.fromJson(Map<String, dynamic> json) {
    final details = json['details'] as Map<String, dynamic>? ?? const {};
    return PhotoRequest(
      id: (json['id'] as num).toInt(),
      owner: json['entityType'] as String? ?? '',
      entityId: '${json['entityId']}',
      context: json['context'] as String? ?? '',
      kind: details['kind'] as String? ?? '',
      title: details['title'] as String? ?? '',
      lines: [
        for (final line in details['lines'] as List<dynamic>? ?? const [])
          if (line is Map<String, dynamic>)
            PhotoRequestLine(
              line['label'] as String? ?? '',
              line['value'] as String? ?? '',
            ),
      ],
    );
  }

  final int id;

  /// [PhotoOwner] — what kind of record.
  final String owner;
  final String entityId;

  /// Where the slot sits on the desktop ("for part HH1").
  final String context;

  /// "Part", "Company logo", "Person", "Die", "Machine".
  final String kind;
  final String title;
  final List<PhotoRequestLine> lines;
}

/// The server's photo-request queue (backend migrations/062): owner-only, so
/// every call is about the signed-in person's own jobs.
class PhotoRequestRepository {
  PhotoRequestRepository({
    required this.baseUrl,
    http.Client? client,
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final bool useMockResponses;
  final http.Client _client;

  final List<PhotoRequest> _mock = [];
  int _mockIds = 1;

  Future<List<PhotoRequest>> pending() async {
    if (useMockResponses) return List.of(_mock);
    final payload = await _send('GET', '/api/photo-requests?status=pending', null);
    return [
      for (final row in payload['requests'] as List<dynamic>? ?? const [])
        if (row is Map<String, dynamic>) PhotoRequest.fromJson(row),
    ];
  }

  /// Asks the signed-in person's phone for [owner] [id]'s photo. Asking again
  /// for the same record returns the same job.
  Future<PhotoRequest> create(String owner, String id, {String context = ''}) async {
    if (useMockResponses) {
      final existing = _mock.where((r) => r.owner == owner && r.entityId == id);
      if (existing.isNotEmpty) return existing.first;
      final request = PhotoRequest(id: _mockIds++, owner: owner, entityId: id, context: context);
      _mock.add(request);
      return request;
    }
    final payload = await _send('POST', '/api/photo-requests', {
      'entityType': owner,
      'entityId': int.tryParse(id) ?? id,
      if (context.trim().isNotEmpty) 'context': context.trim(),
    });
    return PhotoRequest.fromJson(payload['request'] as Map<String, dynamic>);
  }

  Future<void> complete(int requestId, {int? assetId}) =>
      _close(requestId, 'POST', '/api/photo-requests/$requestId/complete', {
        'assetId': ?assetId,
      });

  Future<void> skip(int requestId) =>
      _close(requestId, 'POST', '/api/photo-requests/$requestId/skip', const {});

  Future<void> cancel(int requestId) =>
      _close(requestId, 'DELETE', '/api/photo-requests/$requestId', null);

  Future<void> _close(
    int requestId,
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    if (useMockResponses) {
      _mock.removeWhere((r) => r.id == requestId);
      return;
    }
    await _send(method, path, body);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await _client.send(request));
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      payload = const {};
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] == false) {
      throw PhotoRequestException(
        payload['error'] as String? ?? 'The server answered ${response.statusCode}.',
      );
    }
    return payload;
  }
}

class PhotoRequestException implements Exception {
  const PhotoRequestException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The signed-in person's photo jobs, kept current live.
///
/// The desktop uses it to ask and to show a slot as "on the phone"; the phone
/// uses it as its queue. Both hear `photo_requests_changed`, which the server
/// sends only to this person's own connections.
class PhotoRequestsProvider extends ChangeNotifier {
  PhotoRequestsProvider({
    required PhotoRequestRepository repository,
    bool listen = true,
  }) : _repository = repository,
       _listening = listen {
    if (listen) {
      SocketService.instance.on('photo_requests_changed', _onChanged);
      SocketService.instance.on('realtime:reconnected', _onChanged);
    }
  }

  final PhotoRequestRepository _repository;
  final bool _listening;
  List<PhotoRequest> _pending = const [];
  bool _disposed = false;

  PhotoRequestRepository get repository => _repository;

  /// Oldest first — the order the phone takes them in.
  List<PhotoRequest> get pending => _pending;

  PhotoRequest? pendingFor(String owner, String id) {
    for (final request in _pending) {
      if (request.owner == owner && request.entityId == id) return request;
    }
    return null;
  }

  void _onChanged(dynamic _) => refresh();

  Future<void> refresh() async {
    try {
      final latest = await _repository.pending();
      if (_disposed) return;
      _pending = latest;
      notifyListeners();
    } catch (_) {
      // Kept as it was; the next change or reconnect asks again.
    }
  }

  /// Sends [owner] [id] to the phone. Answers why not, or null when it went.
  Future<String?> ask(String owner, String id, {String context = ''}) async {
    try {
      final request = await _repository.create(owner, id, context: context);
      if (_disposed) return null;
      if (pendingFor(owner, id) == null) {
        _pending = [..._pending, request];
        notifyListeners();
      }
      return null;
    } catch (error) {
      return '$error';
    }
  }

  Future<String?> cancel(String owner, String id) async {
    final request = pendingFor(owner, id);
    if (request == null) return null;
    return _close(request, () => _repository.cancel(request.id));
  }

  Future<String?> complete(PhotoRequest request, {int? assetId}) =>
      _close(request, () => _repository.complete(request.id, assetId: assetId));

  Future<String?> skip(PhotoRequest request) =>
      _close(request, () => _repository.skip(request.id));

  Future<String?> _close(PhotoRequest request, Future<void> Function() call) async {
    try {
      await call();
      if (_disposed) return null;
      _pending = [for (final r in _pending) if (r.id != request.id) r];
      notifyListeners();
      return null;
    } catch (error) {
      return '$error';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_listening) {
      SocketService.instance.off('photo_requests_changed', _onChanged);
      SocketService.instance.off('realtime:reconnected', _onChanged);
    }
    super.dispose();
  }
}
