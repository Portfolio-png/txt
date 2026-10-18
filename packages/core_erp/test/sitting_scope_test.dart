import 'package:core_erp/core/network/authenticated_http_client.dart';
import 'package:core_erp/core/network/sitting_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// The sitting seam: one holder, and one header on writes.
///
/// `AuthenticatedHttpClient` is built about twenty-five times in `main.dart`,
/// so the sitting cannot be constructor state — these cover the holder that
/// stands in for it and the single `send` override that reads it.

/// Records what it was asked to send, and answers 200.
class _RecordingClient extends http.BaseClient {
  final List<http.BaseRequest> sent = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request);
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}

void main() {
  group('SittingScope', () {
    setUp(SittingScope.reset);
    tearDown(SittingScope.reset);

    test('nothing is in progress until a window opens', () {
      expect(SittingScope.current, isNull);
    });

    test('begin returns the id it set', () {
      final id = SittingScope.begin();
      expect(id, isNotEmpty);
      expect(SittingScope.current, id);
    });

    test('two sittings never share an id', () {
      // Microseconds alone would collide across two clients opening together,
      // and these ids meet on one server.
      final ids = {for (var i = 0; i < 200; i++) SittingScope.begin()};
      expect(ids, hasLength(200));
    });

    test('ending the sitting in progress clears it', () {
      final id = SittingScope.begin();
      SittingScope.end(id);
      expect(SittingScope.current, isNull);
    });

    test('an inner window closing falls back to the outer one', () {
      // Add Item can open over Express. A single slot cleared outright here,
      // so every write the outer window made afterwards was unattributed —
      // which is what made this a stack.
      final outer = SittingScope.begin();
      final inner = SittingScope.begin();
      expect(SittingScope.current, inner);

      SittingScope.end(inner);
      expect(
        SittingScope.current,
        outer,
        reason: 'the outer window is still open, so its sitting resumes',
      );

      SittingScope.end(outer);
      expect(SittingScope.current, isNull);
    });

    test('windows closing out of order still end the right one', () {
      // Disposal order is not guaranteed to be the reverse of opening order.
      final outer = SittingScope.begin();
      final inner = SittingScope.begin();

      SittingScope.end(outer);
      expect(
        SittingScope.current,
        inner,
        reason: 'the inner window is still open and still writing',
      );

      SittingScope.end(inner);
      expect(SittingScope.current, isNull);
    });

    test('ending an id that is not current changes nothing', () {
      final current = SittingScope.begin();
      SittingScope.end('s-some-other-window');
      expect(SittingScope.current, current);
    });
  });

  group('the header on the wire', () {
    setUp(SittingScope.reset);
    tearDown(SittingScope.reset);

    _RecordingClient inner = _RecordingClient();
    AuthenticatedHttpClient build() => AuthenticatedHttpClient(
      tokenResolver: () => 'tok',
      sittingResolver: () => SittingScope.current,
      inner: inner = _RecordingClient(),
    );

    test('a write carries the sitting', () async {
      final client = build();
      final id = SittingScope.begin();

      await client.post(Uri.parse('http://x/api/clients'));

      expect(inner.sent.single.headers[kSittingHeader], id);
      expect(inner.sent.single.headers['Authorization'], 'Bearer tok');
    });

    test('every writing method carries it, not just POST', () async {
      final client = build();
      final id = SittingScope.begin();
      final url = Uri.parse('http://x/api/clients/1');

      await client.patch(url);
      await client.put(url);
      await client.delete(url);

      expect(
        inner.sent.map((r) => r.headers[kSittingHeader]),
        [id, id, id],
      );
    });

    test('a GET does not', () async {
      // A read changes nothing, so it does not belong in a record of what was
      // done — and a varying header is the one thing the conditional cache
      // underneath must not see.
      final client = build();
      SittingScope.begin();

      await client.get(Uri.parse('http://x/api/clients'));

      expect(inner.sent.single.headers.containsKey(kSittingHeader), isFalse);
    });

    test('with no window open the header is absent, not empty', () async {
      // The server treats absent as "not in a sitting"; an empty string would
      // be a value it then has to special-case.
      final client = build();

      await client.post(Uri.parse('http://x/api/clients'));

      expect(inner.sent.single.headers.containsKey(kSittingHeader), isFalse);
    });

    test('a client given no resolver never sends it', () async {
      // Other apps build their own clients; they must keep working untouched.
      final recording = _RecordingClient();
      final client = AuthenticatedHttpClient(
        tokenResolver: () => 'tok',
        inner: recording,
      );
      SittingScope.begin();

      await client.post(Uri.parse('http://x/api/clients'));

      expect(recording.sent.single.headers.containsKey(kSittingHeader), isFalse);
    });
  });
}
