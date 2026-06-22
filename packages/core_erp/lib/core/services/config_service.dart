import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ConfigService {
  ConfigService._();
  
  static final ConfigService instance = ConfigService._();

  Map<String, dynamic> _config = {};

  Map<String, dynamic> get config => _config;

  Future<void> init(String baseUrl, String clientId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/sandbox-config/$clientId'));
      if (response.statusCode == 200) {
        _config = jsonDecode(response.body);
      } else {
        _loadDefaultConfig();
      }
    } catch (e) {
      debugPrint('Failed to load remote config: $e');
      _loadDefaultConfig();
    }
  }

  void _loadDefaultConfig() {
    _config = {
      "modules": {
        "orders": true,
        "masters": true,
        "inventory": false,
        "production": false,
        "pm": false,
        "jobs": false,
        "delivery_challans": false,
      },
      "orders": {
        "statusColors": {
          "pending": "#FFA500",
          "in_progress": "#1E90FF",
          "completed": "#32CD32"
        },
        "allowCustomActions": true
      },
      "update": {
        "channel": "stable",
        "latest_version": "1.0.0"
      }
    };
  }

  bool isModuleEnabled(String moduleName) {
    if (_config.containsKey('modules')) {
      return _config['modules'][moduleName] == true;
    }
    return true; // Default to true if not specified
  }

  Map<String, String> get ordersStatusColors {
    if (_config.containsKey('orders') && _config['orders'].containsKey('statusColors')) {
      return Map<String, String>.from(_config['orders']['statusColors']);
    }
    return {
      "pending": "#FFA500",
      "in_progress": "#1E90FF",
      "completed": "#32CD32"
    };
  }

  bool get allowCustomOrderActions {
    if (_config.containsKey('orders')) {
      return _config['orders']['allowCustomActions'] == true;
    }
    return true;
  }

  bool get allowOrdersCreation {
    if (_config.containsKey('orders')) {
      return _config['orders']['allowOrdersCreation'] != false;
    }
    return true;
  }

  bool get disableMachineCustomFields {
    if (_config.containsKey('features')) {
      return _config['features']['disableMachineCustomFields'] == true;
    }
    return false;
  }
}
