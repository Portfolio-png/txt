import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SocketService {
  SocketService._internal();

  static final SocketService _instance = SocketService._internal();
  static SocketService get instance => _instance;

  http.Client? _client;
  bool _isConnected = false;
  int _lastEventId = 0;
  Timer? _reconnectTimer;
  
  final Map<String, List<Function(dynamic)>> _listeners = {};

  void init(String baseUrl) {
    if (_isConnected) return;
    _isConnected = true;
    _connectInternal(baseUrl);
  }

  Future<void> _connectInternal(String baseUrl) async {
    _client?.close();
    _client = http.Client();

    try {
      final url = baseUrl.isEmpty ? 'http://localhost:3000' : baseUrl;
      final uri = Uri.parse('$url/api/events?since=$_lastEventId');
      final request = http.Request('GET', uri);
      final response = await _client!.send(request);

      if (response.statusCode == 200) {
        print('SocketService: Connected to backend (SSE)');
        String buffer = '';
        response.stream.transform(utf8.decoder).listen((data) {
          buffer += data;
          int index;
          while ((index = buffer.indexOf('\n\n')) != -1) {
            String eventBlock = buffer.substring(0, index);
            buffer = buffer.substring(index + 2);
            _processEvent(eventBlock);
          }
        }, onDone: () {
          print('SocketService: Disconnected from backend (SSE stream done)');
          _scheduleReconnect(baseUrl);
        }, onError: (e) {
          print('SocketService: Disconnected from backend (SSE error)');
          _scheduleReconnect(baseUrl);
        });
      } else {
        _scheduleReconnect(baseUrl);
      }
    } catch (e) {
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
          if (action == 'INSERT') emitEvent = 'client_added';
          else if (action == 'UPDATE') emitEvent = 'client_updated';
          else if (action == 'DELETE') emitEvent = 'client_deleted';
        } else if (tableName == 'vendors') {
          if (action == 'INSERT') emitEvent = 'vendor_added';
          else if (action == 'UPDATE') emitEvent = 'vendor_updated';
          else if (action == 'DELETE') emitEvent = 'vendor_deleted';
        } else if (tableName == 'items') {
          if (action == 'INSERT') emitEvent = 'item_added';
          else if (action == 'UPDATE') emitEvent = 'item_updated';
          else if (action == 'DELETE') emitEvent = 'item_deleted';
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
    if (!_isConnected) return;
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _connectInternal(baseUrl);
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
