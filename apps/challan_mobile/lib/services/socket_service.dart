import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';

class SocketService extends ChangeNotifier {
  bool _isConnected = false;
  String? _baseUrl;
  AuthProvider? _authProvider;

  bool get isConnected => _isConnected;
  String? get baseUrl => _baseUrl;

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

  Future<Map<String, dynamic>?> fetchMaterialDetail(String barcode) async {
    if (_isConnected && _baseUrl != null) {
      try {
        final token = _authProvider?.token ?? '';
        final response = await http.get(
          Uri.parse('$_baseUrl/api/materials/$barcode/detail'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        }
      } catch (e) {
        debugPrint('Failed to fetch material detail: $e');
      }
    }
    return null;
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

  Future<String?> seedDemoManufacturing() async {
    if (_isConnected && _baseUrl != null) {
      try {
        final token = _authProvider?.token ?? '';
        final response = await http.post(
          Uri.parse('$_baseUrl/dev/seed-manufacturing-demo'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['barcode'];
        }
      } catch (e) {
        debugPrint('Failed to seed demo: $e');
      }
    }
    return null;
  }
}
