import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/variation_node.dart';

class VariationTreeException implements Exception {
  VariationTreeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The server refused a save because it would have changed what is already in
/// the tree, and the owner is still on the version that describes it.
///
/// Carries the changes it would have made, because "declare a new version"
/// is only a reasonable thing to ask of someone who can see what for.
class VariationLockedException extends VariationTreeException {
  VariationLockedException(super.message, this.changes);

  final List<String> changes;
}

/// The client for /api/variations — a property/value tree on any master.
class VariationTreeService {
  VariationTreeService({
    http.Client? client,
    required this.baseUrl,
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final bool useMockResponses;

  /// Demo builds keep the tree in memory, so the editor works with no backend.
  final Map<String, VariationTree> _mock = {};

  String _key(String type, String id) => '$type:$id';

  Future<VariationTree> fetch(String type, String id) async {
    if (useMockResponses) return _mock[_key(type, id)] ?? VariationTree.empty;
    return VariationTree.fromJson(await _get('/api/variations/$type/$id'));
  }

  Future<VariationTree> save(
    String type,
    String id,
    List<VariationNode> nodes,
  ) async {
    if (useMockResponses) {
      final before = _mock[_key(type, id)] ?? VariationTree.empty;
      final saved = VariationTree(
        version: before.version,
        label: before.label,
        nodes: [
          for (final node in nodes) _stamp(node.copy(), before.version),
        ],
      );
      _mock[_key(type, id)] = saved;
      return saved;
    }
    return VariationTree.fromJson(
      await _send('PUT', '/api/variations/$type/$id', {
        'nodes': [for (final node in nodes) node.toJson()],
      }),
    );
  }

  /// Declares the next version, which is what unlocks changing what is already
  /// there. Returns the new version number.
  Future<int> declareVersion(
    String type,
    String id, {
    String label = '',
    String note = '',
  }) async {
    if (useMockResponses) {
      final before = _mock[_key(type, id)] ?? VariationTree.empty;
      final next = before.version + 1;
      _mock[_key(type, id)] = VariationTree(
        version: next,
        label: label,
        nodes: before.nodes,
      );
      return next;
    }
    final payload = await _send(
      'POST',
      '/api/variations/$type/$id/versions',
      {'label': label, 'note': note},
    );
    return (payload['version'] as num?)?.toInt() ?? 1;
  }

  /// Gives ids to what the mock just "stored", so a second save reads as a
  /// change rather than as a fresh addition — which is what makes the lock
  /// observable without a backend.
  VariationNode _stamp(VariationNode node, int version) {
    node.id ??= _mockSeq++;
    node.version = version;
    for (final child in node.children) {
      _stamp(child, version);
    }
    return node;
  }

  int _mockSeq = 1;

  Future<Map<String, dynamic>> _get(String path) =>
      _request(() => _client.get(Uri.parse('$baseUrl$path')));

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic> body,
  ) {
    final uri = Uri.parse('$baseUrl$path');
    return _request(() {
      final request = http.Request(method, uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
      return _client.send(request).then(http.Response.fromStream);
    });
  }

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send,
  ) async {
    late final http.Response response;
    try {
      response = await send();
    } catch (error) {
      throw VariationTreeException('Could not reach the server. ($error)');
    }
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } catch (_) {
      // No readable body — handled as a plain failure below.
    }
    final message = (payload?['error'] as String?)?.trim();
    if (response.statusCode == 409) {
      throw VariationLockedException(
        message?.isNotEmpty == true
            ? message!
            : 'This is fixed until a new version is declared.',
        [
          for (final change in (payload?['changes'] as List?) ?? const [])
            '$change',
        ],
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VariationTreeException(
        message?.isNotEmpty == true
            ? message!
            : 'The server refused that (${response.statusCode}).',
      );
    }
    if (payload == null || payload['success'] != true) {
      throw VariationTreeException(
        message?.isNotEmpty == true
            ? message!
            : 'The server sent an answer we could not read.',
      );
    }
    return payload;
  }
}
