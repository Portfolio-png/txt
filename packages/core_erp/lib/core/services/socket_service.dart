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

  void _processEvent(String eventBlock) {
    String eventType = '';
    String data = '';

    for (var line in eventBlock.split('\n')) {
      if (line.startsWith('id:')) {
        final idStr = line.substring(3).trim();
        _lastEventId = int.tryParse(idStr) ?? _lastEventId;
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
        String emitEvent = '';

        if (tableName == 'clients') {
          if (action == 'INSERT')
            emitEvent = 'client_added';
          else if (action == 'UPDATE')
            emitEvent = 'client_updated';
          else if (action == 'DELETE')
            emitEvent = 'client_deleted';
        } else if (tableName == 'vendors') {
          if (action == 'INSERT')
            emitEvent = 'vendor_added';
          else if (action == 'UPDATE')
            emitEvent = 'vendor_updated';
          else if (action == 'DELETE')
            emitEvent = 'vendor_deleted';
        } else if (tableName == 'items') {
          if (action == 'INSERT')
            emitEvent = 'item_added';
          else if (action == 'UPDATE')
            emitEvent = 'item_updated';
          else if (action == 'DELETE')
            emitEvent = 'item_deleted';
        } else if (tableName == 'delivery_challans') {
          emitEvent = 'challan_updated';
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
    if (!_isConnected || _currentToken == null || _currentToken!.isEmpty) return;

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
