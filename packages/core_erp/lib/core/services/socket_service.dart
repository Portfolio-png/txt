import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  SocketService._internal();

  static final SocketService _instance = SocketService._internal();
  static SocketService get instance => _instance;

  io.Socket? _socket;

  io.Socket? get socket => _socket;

  void init(String baseUrl) {
    if (_socket != null) {
      _socket!.disconnect();
    }

    final url = baseUrl.isEmpty ? 'http://localhost:3000' : baseUrl;

    _socket = io.io(
        url,
        io.OptionBuilder()
            .disableAutoConnect() // disable auto-connection
            .build());

    _socket!.onConnect((_) {
      print('SocketService: Connected to backend');
    });

    _socket!.onDisconnect((_) {
      print('SocketService: Disconnected from backend');
    });

    _socket!.connect();
  }

  void on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
  }

  void off(String event, [Function(dynamic)? callback]) {
    _socket?.off(event, callback);
  }
}
