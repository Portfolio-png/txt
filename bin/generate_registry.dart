import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('packages/core_erp/lib/core/services/feature_flags.dart');
  if (!file.existsSync()) {
    print('Error: feature_flags.dart not found.');
    return;
  }

  final content = file.readAsStringSync();
  final regex = RegExp(
    r"@FeatureFlag\(\s*category:\s*'([^']+)',\s*displayName:\s*'([^']+)',\s*desc:\s*'([^']+)'\s*\)\s*static const String [a-zA-Z0-9_]+\s*=\s*'([^']+)';",
    multiLine: true,
  );

  final registry = <Map<String, dynamic>>[];
  for (final match in regex.allMatches(content)) {
    registry.add({
      'key': match.group(4),
      'displayName': match.group(2),
      'category': match.group(1),
      'description': match.group(3),
    });
  }

  final jsonString = const JsonEncoder.withIndent('  ').convert(registry);
  
  final outDir = Directory('backend');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final outFile = File('backend/feature_registry.json');
  outFile.writeAsStringSync(jsonString);
  print('Generated ${registry.length} feature flags to backend/feature_registry.json');
}
