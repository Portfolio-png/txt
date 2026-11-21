import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Writes made where the server could not be reached, kept until it can be.
///
/// A worker on the shop floor creates a challan with no signal. The write is
/// recorded here with an id of its own, the screen shows it as pending, and it
/// is sent when the connection is back — with that id as its
/// `X-Idempotency-Key`, so however many times a lost answer makes it be sent,
/// the server applies it once (backend kernel/idempotency.js).
///
/// **Its own database file, not the replica's.** The replica is disposable —
/// a resync deletes it and the server rebuilds it — and the outbox holds the
/// only copy of work nobody has sent yet. In the same file, a routine resync
/// would have thrown unsent challans away.
///
/// States: `pending` (waiting its turn), `in_flight` (being sent; reset to
/// pending when the app reopens — safe, the key makes a resend harmless),
/// `synced` (the server has it; its answer is kept), `conflict` (the server
/// refused it, or whether it landed cannot be known — a person decides, nothing
/// is retried on its own).
class OutboxStatus {
  static const pending = 'pending';
  static const inFlight = 'in_flight';
  static const synced = 'synced';
  static const conflict = 'conflict';
}

class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.seq,
    required this.operationType,
    required this.method,
    required this.endpoint,
    required this.payloadJson,
    required this.status,
    required this.createdAt,
    this.previewJson,
    this.retryCount = 0,
    this.nextAttemptAt,
    this.lastError,
    this.serverResponseJson,
    this.serverId,
  });

  final String id;

  /// Order of recording; the queue is sent strictly in this order.
  final int seq;
  final String operationType;
  final String method;

  /// May name another entry's server id as `{ref:<entry id>}`, filled in when
  /// this one is sent — an issue queued for a challan that was itself queued.
  final String endpoint;
  final String payloadJson;
  final String status;
  final DateTime createdAt;

  /// What a screen shows for this write until the server's answer replaces it.
  final String? previewJson;
  final int retryCount;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final String? serverResponseJson;
  final int? serverId;

  Map<String, dynamic>? get preview =>
      previewJson == null ? null : (jsonDecode(previewJson!) as Map).cast<String, dynamic>();

  static OutboxEntry fromRow(Map<String, Object?> row) => OutboxEntry(
        id: row['id']! as String,
        seq: row['seq']! as int,
        operationType: row['operation_type']! as String,
        method: row['method']! as String,
        endpoint: row['endpoint']! as String,
        payloadJson: row['payload_json']! as String,
        status: row['status']! as String,
        createdAt: DateTime.parse(row['created_at']! as String),
        previewJson: row['preview_json'] as String?,
        retryCount: (row['retry_count'] as int?) ?? 0,
        nextAttemptAt: row['next_attempt_at'] == null ? null : DateTime.parse(row['next_attempt_at']! as String),
        lastError: row['last_error'] as String?,
        serverResponseJson: row['server_response_json'] as String?,
        serverId: row['server_id'] as int?,
      );
}

class OutboxStore {
  OutboxStore(this.db);

  final Database db;

  static const List<String> schemaStatements = <String>[
    '''
    CREATE TABLE IF NOT EXISTS client_outbox (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      id TEXT NOT NULL UNIQUE,
      operation_type TEXT NOT NULL,
      endpoint TEXT NOT NULL,
      method TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      preview_json TEXT,
      status TEXT NOT NULL CHECK (status IN ('pending', 'in_flight', 'synced', 'conflict')),
      created_at TEXT NOT NULL,
      retry_count INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT,
      last_error TEXT,
      server_response_json TEXT,
      server_id INTEGER
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_outbox_status ON client_outbox(status, seq)',
  ];

  /// This user's outbox, beside (not inside) their replica.
  static Future<OutboxStore> open(String namespace) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final directory = await getApplicationSupportDirectory();
    final path = p.join(directory.path, 'outbox', namespace, 'paper_outbox.db');
    await Directory(p.dirname(path)).create(recursive: true);
    final db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      for (final statement in schemaStatements) {
        await db.execute(statement);
      }
    });
    final store = OutboxStore(db);
    await store.recover();
    return store;
  }

  /// A send cut off by the app closing goes back in the queue. Sending it again
  /// is safe: its key makes the server answer, not apply, a second time.
  Future<void> recover() async {
    await db.update('client_outbox', <String, Object?>{'status': OutboxStatus.pending},
        where: 'status = ?', whereArgs: <Object?>[OutboxStatus.inFlight]);
  }

  Future<OutboxEntry> add({
    required String id,
    required String operationType,
    required String method,
    required String endpoint,
    required String payloadJson,
    String? previewJson,
    required DateTime now,
  }) async {
    await db.insert('client_outbox', <String, Object?>{
      'id': id,
      'operation_type': operationType,
      'method': method,
      'endpoint': endpoint,
      'payload_json': payloadJson,
      'preview_json': previewJson,
      'status': OutboxStatus.pending,
      'created_at': now.toUtc().toIso8601String(),
    });
    return (await entry(id))!;
  }

  Future<OutboxEntry?> entry(String id) async {
    final rows = await db.query('client_outbox', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.first);
  }

  /// The oldest entry still to send, or null.
  Future<OutboxEntry?> head() async {
    final rows = await db.query('client_outbox',
        where: 'status IN (?, ?)', whereArgs: <Object?>[OutboxStatus.pending, OutboxStatus.inFlight],
        orderBy: 'seq ASC', limit: 1);
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.first);
  }

  /// Everything a person still needs to see: waiting, or refused.
  Future<List<OutboxEntry>> unsettled({String? operationType}) async {
    final rows = await db.query('client_outbox',
        where: 'status != ?${operationType == null ? '' : ' AND operation_type = ?'}',
        whereArgs: <Object?>[OutboxStatus.synced, if (operationType != null) operationType],
        orderBy: 'seq ASC');
    return rows.map(OutboxEntry.fromRow).toList(growable: false);
  }

  Future<void> update(String id, Map<String, Object?> values) =>
      db.update('client_outbox', values, where: 'id = ?', whereArgs: <Object?>[id]);

  Future<void> delete(String id) => db.delete('client_outbox', where: 'id = ?', whereArgs: <Object?>[id]);

  /// Synced entries are kept a day for their answers, then dropped.
  Future<void> prune(DateTime now) => db.delete('client_outbox',
      where: 'status = ? AND created_at < ?',
      whereArgs: <Object?>[OutboxStatus.synced, now.subtract(const Duration(days: 1)).toUtc().toIso8601String()]);
}

/// Sends the outbox, oldest first, one at a time.
class OutboxSyncEngine {
  OutboxSyncEngine({
    required this.store,
    required http.Client client,
    required String baseUrl,
    DateTime Function()? now,
    Duration requestTimeout = const Duration(seconds: 20),
  })  : _client = client,
        _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
        _now = now ?? DateTime.now,
        _timeout = requestTimeout;

  final OutboxStore store;
  final http.Client _client;
  final String _baseUrl;
  final DateTime Function() _now;
  final Duration _timeout;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Timer? _retryTimer;
  Future<void>? _draining;
  bool _again = false;

  /// Something in the outbox moved — a screen showing pending work re-reads.
  Stream<void> get changes => _changes.stream;

  static final Random _random = Random.secure();

  /// A version 4 UUID.
  static String newId() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  /// Exponential: 1, 2, 4, 8, 16, then 30 seconds.
  static Duration backoff(int attempt) =>
      Duration(seconds: min(30, 1 << max(0, min(attempt - 1, 5))));

  /// Records a write and tries to send it (and anything older) at once.
  /// Returns the entry as it stands after that try: synced if the server took
  /// it, pending if it could not be reached, conflict if it refused.
  Future<OutboxEntry> submit({
    required String operationType,
    required String method,
    required String endpoint,
    required Object? body,
    Map<String, dynamic>? preview,
    String? id,
  }) async {
    final entry = await store.add(
      id: id ?? newId(),
      operationType: operationType,
      method: method,
      endpoint: endpoint,
      payloadJson: jsonEncode(body),
      previewJson: preview == null ? null : jsonEncode(preview),
      now: _now(),
    );
    _changes.add(null);
    await drain();
    return (await store.entry(entry.id))!;
  }

  /// Sends what is due, oldest first. One drain at a time; a call during one
  /// asks for another pass after it.
  Future<void> drain() {
    final running = _draining;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _drainLoop().whenComplete(() => _draining = null);
    _draining = run;
    return run;
  }

  Future<void> _drainLoop() async {
    do {
      _again = false;
      while (true) {
        final head = await store.head();
        if (head == null) break;
        final due = head.nextAttemptAt;
        if (due != null && due.isAfter(_now())) {
          // The head is backing off. Nothing behind it may go first: that would
          // send writes out of the order they were made.
          _scheduleRetry(due.difference(_now()));
          break;
        }
        final carryOn = await _send(head);
        _changes.add(null);
        if (!carryOn) break;
      }
    } while (_again);
  }

  void _scheduleRetry(Duration after) {
    _retryTimer?.cancel();
    _retryTimer = Timer(after, () => drain());
  }

  /// Sends one entry. Returns whether the queue may move on to the next.
  Future<bool> _send(OutboxEntry entry) async {
    final endpoint = await _resolve(entry);
    if (endpoint == null) return true; // marked conflict by _resolve
    await store.update(entry.id, <String, Object?>{'status': OutboxStatus.inFlight});

    http.Response response;
    try {
      final request = http.Request(entry.method, Uri.parse('$_baseUrl$endpoint'))
        ..headers['Content-Type'] = 'application/json'
        ..headers['X-Idempotency-Key'] = entry.id
        ..body = entry.payloadJson;
      response = await http.Response.fromStream(await _client.send(request).timeout(_timeout));
    } catch (error) {
      // Never reached the server, or its answer never reached us. Either way
      // the same key goes again later, and the server sorts out which.
      await _later(entry, 'The server could not be reached.');
      return false;
    }

    final status = response.statusCode;
    final answer = _decode(response.body);
    final code = answer is Map ? '${answer['code'] ?? ''}' : '';
    if (status >= 200 && status < 300) {
      await store.update(entry.id, <String, Object?>{
        'status': OutboxStatus.synced,
        'server_response_json': response.body,
        'server_id': serverIdOf(answer),
        'last_error': null,
      });
      return true;
    }
    if (status == 409 && code == 'idempotency_already_applied') {
      // Applied once; its answer was lost in a server restart. It is done —
      // but nothing queued after it can learn its id.
      await store.update(entry.id, <String, Object?>{
        'status': OutboxStatus.synced,
        'last_error': 'Applied on the server; its answer was not kept.',
      });
      return true;
    }
    if (status == 409 && code == 'idempotency_in_progress') {
      await _later(entry, 'The server is still applying this.');
      return false;
    }
    if (status == 401 || status >= 500) {
      // A server failure, or a session to renew: not this write's fault, and
      // nothing behind it should overtake it.
      await _later(entry, status == 401 ? 'Signed out; waiting for a sign-in.' : 'The server failed ($status).');
      return false;
    }
    // Refused: insufficient stock, a rule broken, a key reused, an outcome the
    // server cannot vouch for. A person decides; it is never retried alone.
    await store.update(entry.id, <String, Object?>{
      'status': OutboxStatus.conflict,
      'last_error': answer is Map ? '${answer['error'] ?? 'Refused ($status).'}' : 'Refused ($status).',
      'server_response_json': response.body,
    });
    return true;
  }

  Future<void> _later(OutboxEntry entry, String reason) async {
    final attempt = entry.retryCount + 1;
    final wait = backoff(attempt);
    await store.update(entry.id, <String, Object?>{
      'status': OutboxStatus.pending,
      'retry_count': attempt,
      'next_attempt_at': _now().add(wait).toUtc().toIso8601String(),
      'last_error': reason,
    });
    _scheduleRetry(wait);
  }

  static final RegExp _ref = RegExp(r'\{ref:([^}]+)\}');

  /// Fills in `{ref:<entry>}` with that entry's server id. Null — and this
  /// entry marked conflict — when the entry it depends on was refused or its
  /// id is not known.
  Future<String?> _resolve(OutboxEntry entry) async {
    final match = _ref.firstMatch(entry.endpoint);
    if (match == null) return entry.endpoint;
    final parent = await store.entry(match.group(1)!);
    final id = parent?.serverId;
    if (parent == null || parent.status == OutboxStatus.conflict || id == null) {
      await store.update(entry.id, <String, Object?>{
        'status': OutboxStatus.conflict,
        'last_error': parent?.status == OutboxStatus.conflict
            ? 'Depends on a write the server refused.'
            : 'Depends on a write whose server id is not known.',
      });
      return null;
    }
    return entry.endpoint.replaceFirst(match.group(0)!, '$id');
  }

  /// Sends a refused entry again — after the worker has seen why.
  Future<void> retry(String id) async {
    await store.update(id, <String, Object?>{
      'status': OutboxStatus.pending, 'next_attempt_at': null, 'last_error': null,
    });
    _changes.add(null);
    await drain();
  }

  /// "Flush now": what is waiting is sent at once instead of when its backoff
  /// ends — a person has just seen the connection is back. Conflicts are left
  /// alone: those wait for a person's decision about each one, not a button.
  Future<void> flushNow() async {
    await store.db.update(
      'client_outbox',
      <String, Object?>{'next_attempt_at': null},
      where: 'status = ?',
      whereArgs: <Object?>[OutboxStatus.pending],
    );
    _retryTimer?.cancel();
    _retryTimer = null;
    await drain();
  }

  /// Gives a write up. Its id is never sent again.
  Future<void> discard(String id) async {
    await store.delete(id);
    _changes.add(null);
  }

  void dispose() {
    _retryTimer?.cancel();
    _changes.close();
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// The id of the record a write made, from the usual envelopes:
  /// `{challan: {id}}`, `{data: {id}}`, `{order: {id}}`, or the first object
  /// value that has one.
  static int? serverIdOf(Object? answer) {
    if (answer is! Map) return null;
    for (final value in answer.values) {
      if (value is Map && value['id'] is num) return (value['id'] as num).toInt();
    }
    return null;
  }
}
