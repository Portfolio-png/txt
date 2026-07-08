import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';

class SocketService extends ChangeNotifier {
  bool _isConnected = false;
  String? _baseUrl;
  AuthProvider? _authProvider;

  bool get isConnected => _isConnected;

  void initAuth(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  void connect(String url) {
    _baseUrl = url;
    _isConnected = true;
    notifyListeners();
  }

  void disconnect() {
    _isConnected = false;
    notifyListeners();
  }

  Future<void> stageItem(Map<String, dynamic> itemData) async {
    if (_isConnected && _baseUrl != null) {
      try {
        final token = _authProvider?.token ?? '';
        await http.post(
          Uri.parse('$_baseUrl/api/mobile/stage-item'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(itemData),
        );
      } catch (e) {
        debugPrint('Failed to stage item via HTTP: $e');
      }
    } else {
      debugPrint('Cannot stage item, offline. Queueing locally...');
    }
  }

  Future<void> removeStagedItem(Map<String, dynamic> itemData) async {
    if (_isConnected && _baseUrl != null) {
      try {
        final token = _authProvider?.token ?? '';
        await http.post(
          Uri.parse('$_baseUrl/api/mobile/remove-staged-item'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(itemData),
        );
      } catch (e) {
        debugPrint('Failed to remove staged item via HTTP: $e');
      }
    }
  }
}
