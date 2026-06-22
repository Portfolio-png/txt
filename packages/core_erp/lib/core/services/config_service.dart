import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'feature_flags.dart';

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
        FeatureFlags.setConfig(_config);
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
    FeatureFlags.setConfig(_config);
  }

  bool isModuleEnabled(String moduleName) {
    switch (moduleName) {
      case 'orders': return FeatureFlags.isEnabled(FeatureKey.modulesOrders);
      case 'masters': return FeatureFlags.isEnabled(FeatureKey.modulesMasters);
      case 'inventory': return FeatureFlags.isEnabled(FeatureKey.modulesInventory);
      case 'production': return FeatureFlags.isEnabled(FeatureKey.modulesProduction);
      case 'pm': return FeatureFlags.isEnabled(FeatureKey.modulesPm);
      case 'jobs': return FeatureFlags.isEnabled(FeatureKey.modulesJobs);
      case 'delivery_challans': return FeatureFlags.isEnabled(FeatureKey.modulesChallans);
      default: return true;
    }
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

  bool get allowCustomOrderActions => FeatureFlags.isEnabled(FeatureKey.ordersAllowCustomActions);

  bool get allowOrdersCreation => FeatureFlags.isEnabled(FeatureKey.ordersAllowOrdersCreation);

  bool get disableMachineCustomFields => FeatureFlags.isEnabled(FeatureKey.featuresDisableMachineCustomFields);
}
