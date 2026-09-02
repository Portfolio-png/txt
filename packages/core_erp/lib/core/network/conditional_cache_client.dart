import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Makes the server's 304s actually happen.
///
/// The backend issues an `ETag` on its high-volume read endpoints and answers
/// `304 Not Modified` to a request carrying a matching `If-None-Match`. Nothing
/// sent one, so that machinery never fired: every launch re-downloaded the whole
/// workspace, and every refresh paid full price for data that had not changed.
///
/// **Why this is safe against a stale or foreign body.** The client never
/// decides that its copy is current — the server does. Express derives the ETag
/// from the response it just built *for this request*, so if the answer would
/// differ (different user, different permissions, changed data) the validator
/// differs and a full 200 comes back. A 304 is the server saying "what you are
/// holding is exactly what I would send you", which is the only circumstance in
/// which the stored body is replayed.
///
/// **What gets stored is the server's decision too.** Only responses carrying
/// `must-revalidate` are kept — the marker `cacheMasterData` puts on the
/// endpoints that were chosen as cacheable. An RPC-ish or volatile route is
/// never cached here, and that judgement stays in one place rather than being
/// duplicated as a list of paths on the client.
class ConditionalCacheClient extends http.BaseClient {
  ConditionalCacheClient({
    required http.Client inner,
    Directory? storageDirectory,
    int maxEntries = 64,
  }) : _inner = inner,
       _storageDirectory = storageDirectory,
       _maxEntries = maxEntries;

  final http.Client _inner;
  final Directory? _storageDirectory;
  final int _maxEntries;

  final Map<String, _CachedResponse> _memory = <String, _CachedResponse>{};
  Directory? _resolvedDirectory;
  bool _loaded = false;
  Future<void>? _loading;
  String _namespace = 'anonymous';

  /// Which user's copies these are.
  ///
  /// Namespaced rather than cleared on sign-out, because clearing would empty
  /// the cache at every launch — a launch begins with a sign-in — and cold
  /// start is the exact thing this exists to fix. Each user keeps their own
  /// warm copy and never reads anyone else's.
  ///
  /// Safety does not rest on this. A validator is derived from the response the
  /// server built for a specific request, so one user's ETag simply fails to
  /// match another's response and a full 200 comes back. The namespace is about
  /// not leaving one person's workspace on disk under another's session, not
  /// about correctness.
  set namespace(String value) {
    final next = value.trim().isEmpty ? 'anonymous' : value.trim();
    if (next == _namespace) return;
    _namespace = next;
    _memory.clear();
    _resolvedDirectory = null;
    _loaded = false;
    _loading = null;
    hits = 0;
    misses = 0;
  }

  /// How many responses were served from the local copy rather than the wire.
  int hits = 0;
  int misses = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Only GET. A conditional POST is meaningless, and caching one would be a
    // way to silently not perform someone's write.
    if (request.method != 'GET') {
      return _inner.send(request);
    }

    await _ensureLoaded();
    final key = _keyFor(request);
    final cached = _memory[key];
    if (cached != null && cached.etag.isNotEmpty) {
      request.headers['If-None-Match'] = cached.etag;
    }

    final response = await _inner.send(request);

    if (response.statusCode == 304 && cached != null) {
      hits += 1;
      // A 304 carries no body, so the stored one is replayed as though it had
      // arrived. Callers must not be able to tell the difference — they were
      // told 200 and given bytes, which is exactly what happened logically.
      return http.StreamedResponse(
        Stream<List<int>>.value(cached.body),
        200,
        contentLength: cached.body.length,
        request: response.request,
        headers: <String, String>{...cached.headers, 'x-paper-cache': 'hit'},
        reasonPhrase: 'OK (not modified)',
      );
    }

    if (response.statusCode != 200) {
      return response;
    }

    final etag = response.headers['etag'] ?? '';
    final cacheControl = response.headers['cache-control'] ?? '';
    if (etag.isEmpty || !cacheControl.contains('must-revalidate')) {
      return response;
    }

    misses += 1;
    // The body has to be buffered to be stored, so it is handed back as a
    // fresh stream rather than the consumed one.
    final bytes = await response.stream.toBytes();
    _remember(key, _CachedResponse(etag: etag, body: bytes, headers: response.headers));
    unawaited(_persist(key));

    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Forgets everything. Called when the signed-in user changes, so one
  /// person's workspace is not left sitting on disk for the next.
  Future<void> clear() async {
    _memory.clear();
    hits = 0;
    misses = 0;
    final directory = await _directory();
    if (directory != null && directory.existsSync()) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        // A cache that cannot be deleted is not worth failing a sign-out over.
      }
    }
  }

  void _remember(String key, _CachedResponse entry) {
    _memory[key] = entry;
    // Bounded, and oldest-first: an unbounded cache of whole list responses on
    // a workshop PC is a slow memory leak.
    while (_memory.length > _maxEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  String _keyFor(http.BaseRequest request) =>
      md5.convert(utf8.encode('${request.method} ${request.url}')).toString();

  Future<Directory?> _directory() async {
    if (_resolvedDirectory != null) return _resolvedDirectory;
    // The namespace is always a subdirectory, including under an explicitly
    // supplied base. Applying it only to the resolved location would mean the
    // separation quietly did not exist wherever the directory was injected —
    // which is exactly where it gets tested.
    Directory? base = _storageDirectory;
    if (base == null) {
      try {
        final support = await getApplicationSupportDirectory();
        base = Directory('${support.path}/http-cache');
      } catch (_) {
        // No writable location (a locked-down machine). In-memory only, which
        // still helps within a session.
        return null;
      }
    }
    _resolvedDirectory = Directory('${base.path}/$_namespace');
    return _resolvedDirectory;
  }

  /// Reads the cache from disk once.
  ///
  /// This is the part that matters on a slow link: without it the cache is
  /// empty at launch, which is exactly when the app downloads everything.
  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final directory = await _directory();
      if (directory == null || !directory.existsSync()) return;
      for (final file in directory.listSync().whereType<File>()) {
        if (_memory.length >= _maxEntries) break;
        try {
          final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          _memory[file.uri.pathSegments.last] = _CachedResponse(
            etag: decoded['etag'] as String? ?? '',
            body: base64Decode(decoded['body'] as String? ?? ''),
            headers: (decoded['headers'] as Map?)?.cast<String, String>() ??
                const <String, String>{},
          );
        } catch (_) {
          // One unreadable entry must not cost the whole cache. Skipping it
          // costs a single refetch.
        }
      }
    } catch (_) {
      // Same reasoning, one level up.
    } finally {
      _loaded = true;
    }
  }

  Future<void> _persist(String key) async {
    final entry = _memory[key];
    if (entry == null) return;
    try {
      final directory = await _directory();
      if (directory == null) return;
      if (!directory.existsSync()) directory.createSync(recursive: true);
      await File('${directory.path}/$key').writeAsString(
        jsonEncode(<String, dynamic>{
          'etag': entry.etag,
          'body': base64Encode(entry.body),
          'headers': entry.headers,
        }),
      );
    } catch (_) {
      // Persistence is an optimisation. Failing to write must never fail the
      // request that produced the data.
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class _CachedResponse {
  const _CachedResponse({
    required this.etag,
    required this.body,
    required this.headers,
  });

  final String etag;
  final List<int> body;
  final Map<String, String> headers;
}
