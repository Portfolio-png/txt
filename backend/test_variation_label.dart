void main() {
  final propertyName = 'var1'.trim();
  final valueName = 'val1'.trim();
  final segments = <String>[];
  if (propertyName.isNotEmpty || valueName.isNotEmpty) {
    segments.add(
      valueName.isEmpty ? propertyName : '$propertyName: $valueName',
    );
  }
  // ignore: avoid_print
  print(segments.join(' / '));
}
