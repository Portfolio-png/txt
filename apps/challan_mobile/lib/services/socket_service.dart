import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService extends ChangeNotifier {
  io.Socket? _socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  void connect(String url) {
    if (_socket != null) {
      _socket!.disconnect();
    }

    _socket = io.io(url, io.OptionBuilder()
      .setTransports(['websocket']) // for Flutter or Web
      .disableAutoConnect()  // disable auto-connection
      .build());

    _socket!.onConnect((_) {
      debugPrint('WebSocket Connected to $url');
      _isConnected = true;
      notifyListeners();
      
      // We could trigger a flush of local buffer here
    });

    _socket!.onDisconnect((_) {
      debugPrint('WebSocket Disconnected');
      _isConnected = false;
      notifyListeners();
    });

    _socket!.onConnectError((err) {
      debugPrint('WebSocket Connect Error: $err');
      _isConnected = false;
      notifyListeners();
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _isConnected = false;
    notifyListeners();
  }

  void stageItem(Map<String, dynamic> itemData) {
    if (_socket != null && _isConnected) {
      _socket!.emit('stage_item', itemData);
    } else {
      // TODO: Add to local buffer if offline
      debugPrint('Cannot stage item, WebSocket offline. Queueing locally...');
    }
  }
}
