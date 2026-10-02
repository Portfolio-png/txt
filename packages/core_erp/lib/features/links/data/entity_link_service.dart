import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/entity_link.dart';

/// Thrown when the link API refuses or fails; carries the server's own
/// sentence, which is written for the person reading it ("You do not have
/// update access to Dies.").
class EntityLinkException implements Exception {
  EntityLinkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The client for /api/links — the link graph between masters.
///
/// One service for every master, because the graph has one shape for every
/// master. Dies and machines are owned by the host app rather than by
/// `core_erp`, and items by `core_erp`; neither fact matters here, because
/// nothing below names a type. That is what lets the column view live in this
/// package and still list both.
class EntityLinkService {
  EntityLinkService({
    http.Client? client,
    required this.baseUrl,
    this.useMockResponses = false,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// Demo builds answer from [mockTypes] and an in-memory graph, so the column
  /// view is explorable without a backend.
  final bool useMockResponses;

  static const List<LinkableType> mockTypes = [
    LinkableType(type: 'item', label: 'Item', plural: 'Items', icon: 'item', canLink: true),
    LinkableType(type: 'die', label: 'Die', plural: 'Dies', icon: 'die', canLink: true),
    LinkableType(
      type: 'machine',
      label: 'Machine',
      plural: 'Machines',
      icon: 'machine',
      canLink: true,
    ),
  ];

  /// The demo graph: pair key -> the links on it. Symmetric, like the store.
  final Map<String, Set<String>> _mockGraph = {};

  /// What can be linked, and what this user may attach.
  Future<List<LinkableType>> fetchTypes() async {
    if (useMockResponses) return mockTypes;
    final payload = await _get('/api/links/schema');
    return [
      for (final raw in (payload['types'] as List?) ?? const [])
        if (raw is Map<String, dynamic>) ?LinkableType.fromJson(raw),
    ];
  }

  /// The records of one master — the first column, which has no record to
  /// start from.
  Future<List<LinkRef>> browse(String type, {String query = '', int limit = 50}) async {
    if (useMockResponses) return _mockRecords(type);
    final payload = await _get(
      '/api/links/$type${_queryString({'q': query, 'limit': '$limit'})}',
    );
    return _refs(payload['records']);
  }

  /// One record and everything it is linked to, grouped by master. The same
  /// call whichever end you hold: a die answers with its items, an item with
  /// its dies.
  Future<EntityLinks> fetchLinks(String type, String id) async {
    if (useMockResponses) return _mockLinks(type, id);
    final payload = await _get('/api/links/$type/$id');
    final parsed = EntityLinks.fromJson(payload);
    if (parsed == null) {
      throw EntityLinkException('The server sent a link list we could not read.');
    }
    return parsed;
  }

  /// Records of [otherType] that ([type], [id]) is not linked to yet.
  Future<List<LinkRef>> fetchCandidates({
    required String type,
    required String id,
    required String otherType,
    String query = '',
    int limit = 50,
  }) async {
    if (useMockResponses) {
      final taken = _mockGraph[_mockKey(type, id)] ?? const {};
      return _mockRecords(otherType)
          .where((ref) => !taken.contains(ref.key))
          .where((ref) => !(ref.type == type && ref.id == id))
          .toList(growable: false);
    }
    final payload = await _get(
      '/api/links/$type/$id/candidates'
      '${_queryString({'type': otherType, 'q': query, 'limit': '$limit'})}',
    );
    return _refs(payload['candidates']);
  }

  /// Links two records. Direction is not stored, so calling this from either
  /// side is the same call, and calling it twice is not an error.
  Future<void> link({
    required String fromType,
    required String fromId,
    required String toType,
    required String toId,
    String? relation,
  }) async {
    if (useMockResponses) {
      _mockLink(fromType, fromId, toType, toId);
      return;
    }
    await _send(
      'POST',
      '/api/links',
      body: {
        'from': {'type': fromType, 'id': fromId},
        'to': {'type': toType, 'id': toId},
        if (relation != null && relation.isNotEmpty) 'relation': relation,
      },
    );
  }

  Future<void> unlink({
    required String fromType,
    required String fromId,
    required String toType,
    required String toId,
  }) async {
    if (useMockResponses) {
      _mockGraph[_mockKey(fromType, fromId)]?.remove('$toType:$toId');
      _mockGraph[_mockKey(toType, toId)]?.remove('$fromType:$fromId');
      return;
    }
    await _send('DELETE', '/api/links/$fromType/$fromId/$toType/$toId');
  }

  // ---------------------------------------------------------------------------

  String _queryString(Map<String, String> params) {
    final kept = params.entries.where((entry) => entry.value.isNotEmpty);
    if (kept.isEmpty) return '';
    return '?${kept.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  }

  List<LinkRef> _refs(Object? raw) => [
    for (final entry in (raw as List?) ?? const [])
      if (entry is Map<String, dynamic>) ?LinkRef.fromJson(entry),
  ];

  Future<Map<String, dynamic>> _get(String path) =>
      _request(() => _client.get(Uri.parse('$baseUrl$path')));

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) {
    final uri = Uri.parse('$baseUrl$path');
    return _request(() {
      final request = http.Request(method, uri)
        ..headers['Content-Type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);
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
      throw EntityLinkException('Could not reach the server. ($error)');
    }
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } catch (_) {
      // Left null: handled as "no readable body" below, which is what an HTML
      // error page or an empty 502 amounts to.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The server's own sentence where there is one — it names the master and
      // the right that was missing, which no message written here could.
      throw EntityLinkException(
        (payload?['error'] as String?)?.trim().isNotEmpty == true
            ? (payload!['error'] as String).trim()
            : 'The server refused that (${response.statusCode}).',
      );
    }
    if (payload == null || payload['success'] != true) {
      throw EntityLinkException(
        (payload?['error'] as String?)?.trim().isNotEmpty == true
            ? (payload!['error'] as String).trim()
            : 'The server sent an answer we could not read.',
      );
    }
    return payload;
  }

  // --- demo mode ---

  String _mockKey(String type, String id) => '$type:$id';

  List<LinkRef> _mockRecords(String type) => switch (type) {
    'item' => const [
      LinkRef(type: 'item', id: '1', label: 'Hinge Plate', subtitle: 'HP-01'),
      LinkRef(type: 'item', id: '2', label: 'Latch Body', subtitle: 'LB-02'),
      LinkRef(type: 'item', id: '3', label: 'Cover Bracket', subtitle: 'CB-03'),
    ],
    'die' => const [
      LinkRef(type: 'die', id: '1', label: 'DIE-100', subtitle: 'Rack 2'),
      LinkRef(type: 'die', id: '2', label: 'DIE-200', subtitle: 'Rack 2'),
      LinkRef(type: 'die', id: '3', label: 'DIE-300', subtitle: 'Rack 7'),
    ],
    'machine' => const [
      LinkRef(type: 'machine', id: '1', label: 'Press A', subtitle: 'MC-001'),
      LinkRef(type: 'machine', id: '2', label: 'Press B', subtitle: 'MC-002'),
    ],
    _ => const [],
  };

  void _mockLink(String fromType, String fromId, String toType, String toId) {
    (_mockGraph[_mockKey(fromType, fromId)] ??= {}).add('$toType:$toId');
    (_mockGraph[_mockKey(toType, toId)] ??= {}).add('$fromType:$fromId');
  }

  EntityLinks _mockLinks(String type, String id) {
    final self = _mockRecords(type).firstWhere(
      (ref) => ref.id == id,
      orElse: () => LinkRef(type: type, id: id, label: '$type $id'),
    );
    final keys = _mockGraph[_mockKey(type, id)] ?? const <String>{};
    final groups = <LinkGroup>[];
    for (final candidate in mockTypes) {
      final links = _mockRecords(candidate.type)
          .where((ref) => keys.contains(ref.key))
          .toList(growable: false);
      if (links.isEmpty) continue;
      groups.add(
        LinkGroup(
          type: candidate.type,
          label: candidate.label,
          plural: candidate.plural,
          links: links,
        ),
      );
    }
    return EntityLinks(entity: self, groups: groups);
  }
}
