import 'dart:convert';
import 'dart:io';
import 'package:core_erp/core/services/feature_flags.dart';

void main() {
  final registry = FeatureKey.values.map((f) => {
    'key': f.key,
    'displayName': f.displayName,
    'category': f.category,
    'description': f.description,
  }).toList();

  final jsonString = const JsonEncoder.withIndent('  ').convert(registry);
  
  final file = File('backend/feature_registry.json');
  file.writeAsStringSync(jsonString);
  print('Exported ${registry.length} feature flags to backend/feature_registry.json');
}
