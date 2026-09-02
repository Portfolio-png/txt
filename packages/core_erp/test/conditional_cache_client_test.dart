import 'dart:convert';
import 'dart:io';

import 'package:core_erp/core/network/conditional_cache_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// The backend issues ETags and answers 304 to a matching `If-None-Match`.
/// Nothing on the client sent one, so that machinery never fired once.
///
/// These run against a real HTTP server rather than a mock, because the whole
/// mechanism is HTTP semantics — header casing, 304 having no body, what a
/// client is allowed to replay — and a mock would only prove the test author
/// and the code agree.

class _Origin {
  _Origin({required this.body, required this.cacheControl});

  String body;
  String cacheControl;
  int requests = 0;
  int conditionalRequests = 0;
  int notModified = 0;
  late HttpServer _server;

  String get etag => '"v${body.hashCode}"';
  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      requests += 1;
      final inm = request.headers.value('if-none-match');
      if (inm != null) conditionalRequests += 1;
      request.response.headers.set('ETag', etag);
      if (cacheControl.isNotEmpty) {
        request.response.headers.set('Cache-Control', cacheControl);
      }
      if (inm == etag) {
        notModified += 1;
        request.response.statusCode = HttpStatus.notModified;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.write(body);
      await request.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late Directory temp;
  late _Origin origin;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('paper-http-cache-');
    origin = _Origin(
      body: '{"items":[1,2,3]}',
      cacheControl: 'public, max-age=0, must-revalidate',
    );
    await origin.start();
  });

  tearDown(() async {
    await origin.stop();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ConditionalCacheClient clientOn(Directory directory) =>
      ConditionalCacheClient(inner: http.Client(), storageDirectory: directory);

  test('the second request revalidates and is answered 304', () async {
    final client = clientOn(temp);
    final first = await client.get(Uri.parse('${origin.url}/api/items'));
    expect(first.statusCode, 200);
    expect(first.body, '{"items":[1,2,3]}');
    expect(origin.conditionalRequests, 0, reason: 'nothing to revalidate yet');

    final second = await client.get(Uri.parse('${origin.url}/api/items'));
    expect(origin.conditionalRequests, 1, reason: 'it sent the validator');
    expect(origin.notModified, 1, reason: 'and the server recognised it');

    // The caller cannot tell: it asked for data and got data.
    expect(second.statusCode, 200);
    expect(second.body, '{"items":[1,2,3]}');
    expect(client.hits, 1);
  });

  test('changed data comes back in full, not from the copy', () async {
    // The failure that would matter: a cache that keeps serving yesterday's
    // stock because it never asked.
    final client = clientOn(temp);
    await client.get(Uri.parse('${origin.url}/api/items'));

    origin.body = '{"items":[9,9,9]}';
    final after = await client.get(Uri.parse('${origin.url}/api/items'));
    expect(after.statusCode, 200);
    expect(after.body, '{"items":[9,9,9]}', reason: 'the validator no longer matched');
    expect(origin.notModified, 0);
  });

  test('the copy survives a restart, which is when it is worth having', () async {
    // The measured pain is cold start. An in-memory cache is empty at exactly
    // the moment the app downloads everything.
    final first = clientOn(temp);
    await first.get(Uri.parse('${origin.url}/api/items'));
    first.close();

    final relaunched = clientOn(temp);
    final response = await relaunched.get(Uri.parse('${origin.url}/api/items'));
    expect(response.statusCode, 200);
    expect(response.body, '{"items":[1,2,3]}');
    expect(origin.notModified, 1, reason: 'a fresh client still knew what it held');
    expect(relaunched.hits, 1);
  });

  test('only what the server marked revalidatable is kept', () async {
    // The decision about what may be cached stays on the server, where
    // `cacheMasterData` makes it once — rather than as a list of paths on the
    // client that drifts out of step.
    origin.cacheControl = '';
    final client = clientOn(temp);
    await client.get(Uri.parse('${origin.url}/api/live'));
    await client.get(Uri.parse('${origin.url}/api/live'));
    expect(
      origin.conditionalRequests,
      0,
      reason: 'a volatile endpoint is never revalidated from a stored copy',
    );
    expect(client.hits, 0);
  });

  test('writes are never cached', () async {
    // Replaying a POST would be a way to silently not perform someone's write.
    final client = clientOn(temp);
    await client.post(Uri.parse('${origin.url}/api/items'), body: 'x');
    await client.post(Uri.parse('${origin.url}/api/items'), body: 'x');
    expect(origin.conditionalRequests, 0);
    expect(origin.requests, 2, reason: 'both writes reached the server');
  });

  test('different urls do not share a copy', () async {
    final client = clientOn(temp);
    await client.get(Uri.parse('${origin.url}/api/items'));
    origin.body = '{"orders":[7]}';
    final other = await client.get(Uri.parse('${origin.url}/api/orders'));
    expect(other.body, '{"orders":[7]}');
  });

  test('signing out leaves nothing behind', () async {
    final client = clientOn(temp);
    await client.get(Uri.parse('${origin.url}/api/items'));
    // Written under the namespace, so one user's copies stay separable from
    // another's on a shared machine.
    expect(temp.listSync(recursive: true).whereType<File>(), isNotEmpty);

    await client.clear();
    expect(client.hits, 0);

    // And a later request genuinely refetches rather than replaying.
    final fresh = clientOn(temp);
    await fresh.get(Uri.parse('${origin.url}/api/items'));
    expect(origin.notModified, 0, reason: 'nothing was left to revalidate with');
  });

  test('one user never reads another user\'s copies', () async {
    // A shared workshop PC. Safety does not rest on this — a validator is
    // derived from the response the server built for a specific request, so a
    // foreign ETag simply fails to match — but one person's workspace should
    // not sit on disk under another's session either.
    final client = clientOn(temp);
    client.namespace = 'user-a';
    await client.get(Uri.parse('${origin.url}/api/items'));
    expect(origin.notModified, 0);

    client.namespace = 'user-b';
    await client.get(Uri.parse('${origin.url}/api/items'));
    expect(
      origin.notModified,
      0,
      reason: 'user b revalidated nothing, because it held nothing',
    );
    expect(origin.conditionalRequests, 0);
  });

  test('switching back finds the earlier user\'s copy still warm', () async {
    // Namespaced rather than cleared, because a launch begins with a sign-in
    // and clearing on sign-in would empty the cache at exactly the moment it is
    // worth having.
    final client = clientOn(temp);
    client.namespace = 'user-a';
    await client.get(Uri.parse('${origin.url}/api/items'));
    client.namespace = 'user-b';
    await client.get(Uri.parse('${origin.url}/api/items'));

    client.namespace = 'user-a';
    await client.get(Uri.parse('${origin.url}/api/items'));
    expect(origin.notModified, 1, reason: 'user a still had a validator');
  });

  test('an unreadable entry costs one refetch, not the whole cache', () async {
    final client = clientOn(temp);
    await client.get(Uri.parse('${origin.url}/api/items'));
    client.close();

    for (final file in temp.listSync(recursive: true).whereType<File>()) {
      file.writeAsStringSync('not json');
    }

    final relaunched = clientOn(temp);
    final response = await relaunched.get(Uri.parse('${origin.url}/api/items'));
    expect(response.statusCode, 200, reason: 'it recovered by asking');
    expect(response.body, '{"items":[1,2,3]}');
  });

  test('no writable directory degrades to in-memory rather than failing', () async {
    // A locked-down workshop machine must still be able to use the app.
    final client = ConditionalCacheClient(
      inner: http.Client(),
      storageDirectory: Directory('${temp.path}/does/not/exist'),
    );
    final response = await client.get(Uri.parse('${origin.url}/api/items'));
    expect(response.statusCode, 200);
    expect(response.body, '{"items":[1,2,3]}');
  });

  test('the stored body is the bytes, not a re-encoding', () async {
    // A response replayed through a lossy round-trip would corrupt anything
    // non-ASCII — a vendor name, a client address.
    origin.body = jsonEncode(<String, String>{'vendor': 'Müller & Söhne — 東京'});
    final client = clientOn(temp);
    final first = await client.get(Uri.parse('${origin.url}/api/v'));
    final second = await client.get(Uri.parse('${origin.url}/api/v'));
    expect(second.bodyBytes, first.bodyBytes);
    expect(jsonDecode(second.body)['vendor'], 'Müller & Söhne — 東京');
  });
}
