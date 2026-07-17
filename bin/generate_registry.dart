import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('packages/core_erp/lib/core/services/feature_flags.dart');
  if (!file.existsSync()) {
    print('Error: feature_flags.dart not found.');
    return;
  }

  final content = file.readAsStringSync();
  // Matches the annotation body lazily up to the ')' that precedes the key's
  // declaration, so a ')' inside a description (e.g. "(reception)") can't end
  // the match early.
  final annotation = RegExp(
    r"@FeatureFlag\(([\s\S]*?)\)\s*static\s+const\s+String\s+[a-zA-Z0-9_]+\s*=\s*'([^']+)';",
  );

  final registry = <Map<String, dynamic>>[];
  for (final match in annotation.allMatches(content)) {
    final body = match.group(1)!;
    registry.add({
      'key': match.group(2),
      'displayName': _field(body, 'displayName'),
      'category': _field(body, 'category'),
      'description': _field(body, 'desc'),
    });
  }

  final jsonString = const JsonEncoder.withIndent('  ').convert(registry);
  
  final outDir = Directory('backend');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final outFile = File('backend/feature_registry.json');
  // A parse that finds nothing means the annotation shape drifted from the
  // pattern above, not that the flags are gone. Writing "[]" would drop every
  // per-client toggle from the dashboard, so refuse instead.
  if (registry.isEmpty) {
    stderr.writeln(
      'Error: parsed 0 feature flags from feature_flags.dart — refusing to '
      'overwrite ${outFile.path}. The @FeatureFlag annotation format has '
      'likely changed; fix the parser in bin/generate_registry.dart.',
    );
    exitCode = 1;
    return;
  }

  outFile.writeAsStringSync(jsonString);
  print('Generated ${registry.length} feature flags to backend/feature_registry.json');
}

/// Reads one annotation argument, joining Dart's adjacent string literals
/// (`desc:\n    'a'\n    'b'`) into a single value. Tolerates the trailing
/// comma `dart format` adds to multi-line annotations.
String? _field(String body, String name) {
  final match = RegExp("$name:\\s*((?:'[^']*'\\s*)+)").firstMatch(body);
  if (match == null) return null;
  return RegExp("'([^']*)'")
      .allMatches(match.group(1)!)
      .map((m) => m.group(1)!)
      .join();
}
