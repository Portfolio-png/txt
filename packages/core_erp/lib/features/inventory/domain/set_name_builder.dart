/// A set's name built from its members, the way an item's name is built from
/// its parts: offered while nobody has typed one, and never over a typed one.
///
/// Each item once, in the order its rows stand ("Patti" twice in two
/// variants is still one Patti). Past [shown] names the rest are counted, so
/// a big kit does not get a name a line long.
String buildSetName(Iterable<String> itemLabels, {int shown = 3}) {
  final seen = <String>{};
  final names = <String>[];
  for (final raw in itemLabels) {
    final label = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (label.isEmpty) continue;
    if (seen.add(label.toLowerCase())) names.add(label);
  }
  if (names.length <= shown) return names.join(' + ');
  return '${names.take(shown).join(' + ')} + ${names.length - shown} more';
}
