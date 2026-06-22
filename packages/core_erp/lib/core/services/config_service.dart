import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'feature_flags.dart';

class ConfigService {
  ConfigService._();
  
  static final ConfigService instance = ConfigService._();

  Map<String, dynamic> _config = {};
  Timer? _pollingTimer;

  Map<String, dynamic> get config => _config;

  static const Map<String, dynamic> _globalDefaults = {
    "modules": {
      "orders": true,
      "masters": true,
      "inventory": true,
      "production": true,
      "pm": true,
      "jobs": true,
      "delivery_challans": true,
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

  Future<void> init(String baseUrl, String clientId) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cached_config_$clientId';
    
    // 1. Instantly load from cache
    final cachedStr = prefs.getString(cacheKey);
    if (cachedStr != null) {
      try {
        final clientConfig = jsonDecode(cachedStr) as Map<String, dynamic>;
        _config = _deepMerge(Map<String, dynamic>.from(_globalDefaults), clientConfig);
        FeatureFlags.setConfig(_config);
      } catch (e) {
        _loadDefaultConfig();
      }
    } else {
      _loadDefaultConfig();
    }

    // 2. Fetch asynchronously
    await _fetchRemote(baseUrl, clientId, prefs, cacheKey);

    // 3. Start 15-minute polling
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _fetchRemote(baseUrl, clientId, prefs, cacheKey);
    });
  }

  Future<void> _fetchRemote(String baseUrl, String clientId, SharedPreferences prefs, String cacheKey) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/sandbox-config/$clientId'));
      if (response.statusCode == 200) {
        final clientConfig = jsonDecode(response.body) as Map<String, dynamic>;
        await prefs.setString(cacheKey, response.body);
        _config = _deepMerge(Map<String, dynamic>.from(_globalDefaults), clientConfig);
        FeatureFlags.setConfig(_config);
      }
    } catch (e) {
      debugPrint('Failed to load remote config in polling: $e');
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
  }

  void _loadDefaultConfig() {
    _config = Map<String, dynamic>.from(_globalDefaults);
    FeatureFlags.setConfig(_config);
  }

  Map<String, dynamic> _deepMerge(Map<String, dynamic> target, Map<String, dynamic> source) {
    for (var key in source.keys) {
      if (source[key] is Map<String, dynamic> && target[key] is Map<String, dynamic>) {
        target[key] = _deepMerge(
            Map<String, dynamic>.from(target[key] as Map<String, dynamic>),
            source[key] as Map<String, dynamic>);
      } else {
        target[key] = source[key];
      }
    }
    return target;
  }

  bool isModuleEnabled(String moduleName) {
    switch (moduleName) {
      case 'orders': return FeatureFlags.isEnabled(FeatureKeys.modulesOrders);
      case 'masters': return FeatureFlags.isEnabled(FeatureKeys.modulesMasters);
      case 'inventory': return FeatureFlags.isEnabled(FeatureKeys.modulesInventory);
      case 'production': return FeatureFlags.isEnabled(FeatureKeys.modulesProduction);
      case 'pm': return FeatureFlags.isEnabled(FeatureKeys.modulesPm);
      case 'jobs': return FeatureFlags.isEnabled(FeatureKeys.modulesJobs);
      case 'delivery_challans': return FeatureFlags.isEnabled(FeatureKeys.modulesChallans);
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

  bool get allowCustomOrderActions => FeatureFlags.isEnabled(FeatureKeys.ordersAllowCustomActions);

  bool get allowOrdersCreation => FeatureFlags.isEnabled(FeatureKeys.ordersAllowOrdersCreation);

  bool get disableMachineCustomFields => FeatureFlags.isEnabled(FeatureKeys.featuresDisableMachineCustomFields);
}
