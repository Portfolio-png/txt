import 'dart:convert';

void main() {
  final Map<String, dynamic> globalDefaults = {
    "purchase": {"flowV2": true},
  };

  final Map<String, dynamic> clientConfig = {
    "modules": {"orders": true}
  };

  Map<String, dynamic> deepMerge(Map<String, dynamic> target, Map<String, dynamic> source) {
    for (var key in source.keys) {
      if (source[key] is Map<String, dynamic> && target[key] is Map<String, dynamic>) {
        target[key] = deepMerge(
          Map<String, dynamic>.from(target[key] as Map<String, dynamic>),
          source[key] as Map<String, dynamic>,
        );
      } else {
        target[key] = source[key];
      }
    }
    return target;
  }

  final config = deepMerge(Map<String, dynamic>.from(globalDefaults), clientConfig);

  dynamic getNestedProperty(Map<String, dynamic> configMap, String path) {
    final keys = path.split('.');
    dynamic current = configMap;
    for (final key in keys) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  print('config: \$config');
  print('isEnabled: \${getNestedProperty(config, "purchase.flowV2")}');
}
