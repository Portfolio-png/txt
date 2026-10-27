/// A property column added to the item sheet with its "+", kept for the whole
/// workspace until it is removed (backend migration 061).
///
/// [key] is the normalised name — also the variation property name the sheet
/// writes onto each part — and does not change on a rename; [name] is the
/// label shown. [options] are what the column's dropdown offers, in order.
class SheetProperty {
  const SheetProperty({
    required this.id,
    required this.key,
    required this.propertyName,
    required this.name,
    required this.kind,
    this.position = 0,
    this.options = const <String>[],
  });

  factory SheetProperty.fromJson(Map<String, dynamic> json) => SheetProperty(
        id: (json['id'] as num).toInt(),
        key: json['key'] as String? ?? '',
        propertyName: json['propertyName'] as String? ??
            json['name'] as String? ??
            '',
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'list',
        position: (json['position'] as num?)?.toInt() ?? 0,
        options: [
          for (final option in (json['options'] as List? ?? const []))
            '$option',
        ],
      );

  final int id;
  final String key;

  /// The name as first typed — what parts carry as the property's name, and
  /// what the column binds to. Unchanged by a rename.
  final String propertyName;
  final String name;

  /// 'list', 'text', 'material' or 'gauge' — what the user picked.
  final String kind;
  final int position;
  final List<String> options;

  SheetProperty copyWith({String? name, List<String>? options}) =>
      SheetProperty(
        id: id,
        key: key,
        propertyName: propertyName,
        name: name ?? this.name,
        kind: kind,
        position: position,
        options: options ?? this.options,
      );
}

/// A refusal from the sheet-properties routes, with the column that already
/// holds the name when that was the reason.
class SheetPropertyException implements Exception {
  const SheetPropertyException(this.message, {this.code, this.existing});

  final String message;
  final String? code;
  final SheetProperty? existing;

  @override
  String toString() => message;
}
