import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

class SocketService {
  SocketService._internal();

  static final SocketService _instance = SocketService._internal();
  static SocketService get instance => _instance;

  http.Client? _client;
  bool _isConnected = false;
  int _lastEventId = 0;

  /// Where to read and write the replay position.
  ///
  /// Held in memory alone the cursor resets to 0 on every launch, so the app
  /// asks for the whole workspace again — which is exactly what it used to do.
  /// Injected rather than reached for, so this stays testable and so the
  /// service does not force a database open before anyone has signed in.
  Future<int> Function()? loadCursor;
  Future<void> Function(int id)? saveCursor;

  /// Reads the persisted position. Call once before connecting.
  Future<void> restoreCursor() async {
    final load = loadCursor;
    if (load == null) return;
    try {
      final stored = await load();
      if (stored > _lastEventId) _lastEventId = stored;
    } catch (_) {
      // A cursor that cannot be read means starting from zero: a full sync,
      // which is correct, just expensive.
    }
  }

  void _rememberCursor(int id) {
    if (id <= 0) return;
    final save = saveCursor;
    if (save == null) return;
    // Deliberately not awaited: the stream must keep draining. A lost write
    // only costs replaying a few events after a crash.
    save(id).catchError((_) {});
  }
  Timer? _reconnectTimer;
  String? _currentToken;
  bool _hasConnectedBefore = false;

  final Map<String, List<Function(dynamic)>> _listeners = {};

  void init(String baseUrl, {String? token}) {
    final cleanToken = token?.trim();
    if (cleanToken == null || cleanToken.isEmpty) {
      disconnect();
      return;
    }

    bool tokenChanged = _currentToken != cleanToken;
    _currentToken = cleanToken;

    if (_isConnected && !tokenChanged) return;

    _isConnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectInternal(baseUrl);
  }

  /// Disconnects SSE stream and cancels any active reconnect attempts.
  void disconnect() {
    _isConnected = false;
    _currentToken = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _client?.close();
    _client = null;
  }

  /// Ask all subscribers to resync their data. Used when the app returns to the
  /// foreground — desktop App Nap can suspend the SSE and silently drop change
  /// events — so the UI refreshes without the user manually toggling a filter.
  /// Reuses the same signal providers already handle on reconnect.
  void requestResync() {
    _emit('realtime:reconnected', null);
  }

  Future<void> _connectInternal(String baseUrl) async {
    if (_currentToken == null || _currentToken!.isEmpty) {
      _isConnected = false;
      return;
    }

    _client?.close();
    _client = http.Client();

    try {
      final url = baseUrl.isEmpty ? 'http://localhost:3000' : baseUrl;
      final uri = Uri.parse('$url/api/events?since=$_lastEventId');
      final request = http.Request('GET', uri);
      request.headers['Authorization'] = 'Bearer $_currentToken';
      print(
        'SocketService: Connecting with token... ${_currentToken!.substring(0, math.min(10, _currentToken!.length))}...',
      );
      final response = await _client!.send(request);

      if (response.statusCode == 200) {
        print('SocketService: Connected to backend (SSE)');
        // On a *re*connect (e.g. after the app backgrounded and the stream
        // dropped) we may have missed change events during the gap. Tell
        // listeners to resync so nothing is left stale — this does NOT depend on
        // the server-side changelog replay being correct.
        if (_hasConnectedBefore) {
          _emit('realtime:reconnected', null);
        }
        _hasConnectedBefore = true;
        String buffer = '';
        response.stream
            .transform(utf8.decoder)
            .listen(
              (data) {
                buffer += data;
                int index;
                while ((index = buffer.indexOf('\n\n')) != -1) {
                  String eventBlock = buffer.substring(0, index);
                  buffer = buffer.substring(index + 2);
                  _processEvent(eventBlock);
                }
              },
              onDone: () {
                print(
                  'SocketService: Disconnected from backend (SSE stream done)',
                );
                _scheduleReconnect(baseUrl);
              },
              onError: (e) {
                print('SocketService: Disconnected from backend (SSE error)');
                _scheduleReconnect(baseUrl);
              },
            );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        print(
          'SocketService: Unauthorized (status ${response.statusCode}), disconnecting and emitting event.',
        );
        disconnect();
        _emit('unauthorized', null);
      } else {
        print(
          'SocketService: Failed to connect, status code: ${response.statusCode}',
        );
        _scheduleReconnect(baseUrl);
      }
    } catch (e) {
      print('SocketService: Exception during connect: $e');
      _scheduleReconnect(baseUrl);
    }
  }

  /// Feeds one raw SSE block through the dispatcher.
  ///
  /// Exposed for tests: what this does with a block is the delicate part —
  /// twelve of seventeen tables used to be dropped here — and it should be
  /// checkable without standing up a server and a live stream.
  @visibleForTesting
  void processEventForTest(String eventBlock) => _processEvent(eventBlock);

  void _processEvent(String eventBlock) {
    String eventType = '';
    String data = '';

    for (var line in eventBlock.split('\n')) {
      if (line.startsWith('id:')) {
        final idStr = line.substring(3).trim();
        _lastEventId = int.tryParse(idStr) ?? _lastEventId;
        _rememberCursor(_lastEventId);
      } else if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data = line.substring(5).trim();
      }
    }

    if (eventType == 'table-change') {
      try {
        final parsedData = jsonDecode(data);
        final tableName = parsedData['table_name'];
        final recordId = parsedData['record_id'];
        final action = parsedData['event_type']; // INSERT, UPDATE, DELETE

        final payload = {'id': recordId};

        // Every replicated table, not the five that happened to be wired.
        //
        // Twelve of the seventeen tables the server logs had no branch here, so
        // their events arrived and were dropped: a machine renamed, a unit
        // added, a pipeline template edited, an order line's status moving —
        // all invisible until someone reloaded. Two of the five that were wired
        // named tables that do not exist.
        //
        // The generic event goes out for everything, so a delta engine can
        // replicate a table without anyone adding a case. The named events stay
        // for the providers that already listen for them.
        _emit('table-change', {
          'table': tableName,
          'id': recordId,
          'action': action,
        });

        String emitEvent = '';
        const named = <String, String>{
          'clients': 'client',
          'vendors': 'vendor',
          'items': 'item',
        };
        final prefix = named[tableName];
        if (prefix != null) {
          if (action == 'INSERT') {
            emitEvent = '${prefix}_added';
          } else if (action == 'UPDATE') {
            emitEvent = '${prefix}_updated';
          } else if (action == 'DELETE') {
            emitEvent = '${prefix}_deleted';
          }
        } else if (tableName == 'groups' || tableName == 'item_variation_nodes') {
          // Coarse on purpose: the group list is small and a refresh is one
          // query, so created / renamed / deleted / filled all say the same
          // thing — "the groups you are holding are out of date". A variation
          // node changing means the same for whoever is rendering the tree.
          emitEvent = 'groups_changed';
        } else if (tableName == 'delivery_challans' ||
            tableName == 'delivery_challan_items') {
          emitEvent = 'challan_updated';
        } else if (tableName == 'order_items' || tableName == 'order_headers') {
          emitEvent = 'orders_changed';
        } else if (tableName == 'materials' ||
            tableName == 'inventory_stock_positions') {
          emitEvent = 'inventory_updated';
        } else if (tableName == 'machines') {
          emitEvent = 'machines_changed';
        } else if (tableName == 'dies') {
          emitEvent = 'dies_changed';
        } else if (tableName == 'units') {
          emitEvent = 'units_changed';
        } else if (tableName == 'departments') {
          emitEvent = 'departments_changed';
        } else if (tableName == 'pipeline_templates' ||
            tableName == 'pipeline_runs') {
          emitEvent = 'production_changed';
        }

        if (emitEvent.isNotEmpty) {
          _emit(emitEvent, payload);
        }
      } catch (e) {
        // ignore JSON parse errors
      }
    } else if (eventType == 'custom-event') {
      try {
        final parsedData = jsonDecode(data);
        final emitEvent = parsedData['event'];
        final payload = parsedData['data'];
        if (emitEvent != null && emitEvent is String) {
          _emit(emitEvent, payload);
        }
      } catch (e) {
        // ignore JSON parse errors
      }
    } else if (eventType.isEmpty && data.isNotEmpty) {
      // Initial-state / head-position message: {"lastChangeId": N}. Anchor our
      // position to head so the next reconnect only replays events missed after
      // this point (rather than re-sending since=0 and losing them).
      try {
        final parsedData = jsonDecode(data);
        final head = parsedData is Map ? parsedData['lastChangeId'] : null;
        if (head is int && head > _lastEventId) {
          _lastEventId = head;
        }
      } catch (e) {
        // ignore JSON parse errors
      }
    }
  }

  void _emit(String event, dynamic data) {
    final callbacks = _listeners[event];
    if (callbacks != null) {
      for (final callback in callbacks) {
        callback(data);
      }
    }
  }

  void _scheduleReconnect(String baseUrl) {
    _client?.close();
    if (!_isConnected || _currentToken == null || _currentToken!.isEmpty)
      return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_isConnected && _currentToken != null && _currentToken!.isNotEmpty) {
        _connectInternal(baseUrl);
      }
    });
  }

  void on(String event, Function(dynamic) callback) {
    if (!_listeners.containsKey(event)) {
      _listeners[event] = [];
    }
    _listeners[event]!.add(callback);
  }

  void off(String event, [Function(dynamic)? callback]) {
    if (callback == null) {
      _listeners.remove(event);
    } else {
      _listeners[event]?.remove(callback);
    }
  }
}
