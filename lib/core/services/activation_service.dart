import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

class ActivationService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'activation_token';
  static const _clientIdKey = 'activation_client_id';

  static Future<String> generateFingerprint() async {
    final deviceInfo = DeviceInfoPlugin();
    String identifier = '';
    
    if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      identifier = '${info.computerName}-${info.numberOfCores}-${info.systemMemoryInMegabytes}';
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      identifier = '${info.computerName}-${info.model}-${info.systemGUID}';
    } else if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      identifier = '${info.id}-${info.model}-${info.board}';
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      identifier = '${info.identifierForVendor}-${info.model}';
    } else {
      identifier = 'unknown-device';
    }

    // Hash it for privacy and consistency
    return sha256.convert(utf8.encode(identifier)).toString();
  }

  static Future<bool> isActivated() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null;
  }

  static Future<String?> getClientId() async {
    return await _storage.read(key: _clientIdKey);
  }

  static Future<Map<String, dynamic>> activate(String baseUrl, String clientId, String pin) async {
    final fingerprint = await generateFingerprint();
    
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/activation/activate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'client_id': clientId,
          'activation_pin': pin,
          'fingerprint': fingerprint,
        }),
      );
      
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await _storage.write(key: _tokenKey, value: data['token']);
        await _storage.write(key: _clientIdKey, value: clientId);
        return {'success': true, 'isFirstActivation': data['isFirstActivation'] == true};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Activation failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error during activation'};
    }
  }

  static Future<void> deactivate() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _clientIdKey);
  }
}
