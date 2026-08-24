import 'package:flutter/foundation.dart';

/// What a material *is*, as opposed to a sheet of it sitting on a rack.
///
/// Distinct from the `materials` table, which holds barcoded physical stock.
/// Steel is a type; the steel on rack 3 is stock. Keeping them apart is what
/// stops a density being re-entered on every sheet that arrives.
///
/// The whole master exists for one number. Sheet planning already works out a
/// sheet's volume; density turns that into a weight, and weight is what
/// material is bought by, scrap is sold by, and a challan is weighed in.
@immutable
class MaterialDefinition {
  const MaterialDefinition({
    required this.id,
    required this.name,
    required this.densityGCm3,
    this.category = 'metal',
    this.notes = '',
    this.isArchived = false,
  });

  factory MaterialDefinition.fromJson(Map<String, dynamic> json) {
    return MaterialDefinition(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      densityGCm3: (json['densityGCm3'] as num?)?.toDouble() ?? 0,
      category: json['category']?.toString() ?? 'metal',
      notes: json['notes']?.toString() ?? '',
      isArchived: json['isArchived'] == true,
    );
  }

  final int id;
  final String name;

  /// Grams per cubic centimetre — how a materials table is written, and how
  /// anyone checking the figure will look it up.
  final double densityGCm3;
  final String category;
  final String notes;
  final bool isArchived;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'densityGCm3': densityGCm3,
    'category': category,
    'notes': notes,
  };

  /// The weight of [volumeCm3] of this material.
  ///
  ///     volume (cm³) × density (g/cm³) ÷ 1000 = weight (kg)
  double weightKg(double volumeCm3) {
    if (volumeCm3 <= 0 || densityGCm3 <= 0) return 0;
    return volumeCm3 * densityGCm3 / 1000;
  }

  /// The swatch generated for this material, by the same slug the generator
  /// writes. Served from the backend's public folder.
  String get imagePath => 'materials/${slugFor(name)}.png';

  /// Matches the slug rule in tools/generate-material-images.py, so a material
  /// and its swatch keep finding each other.
  static String slugFor(String name) {
    final kept = name
        .toLowerCase()
        .split('')
        .map((c) => RegExp(r'[a-z0-9]').hasMatch(c) ? c : '-')
        .join();
    var out = kept;
    while (out.contains('--')) {
      out = out.replaceAll('--', '-');
    }
    out = out.replaceAll(RegExp(r'^-+|-+$'), '');
    return out.length > 48 ? out.substring(0, 48) : out;
  }

  /// How a density reads on a card: two decimals is the precision a handbook
  /// quotes, and more would imply a certainty alloys do not have.
  String get densityLabel => '${densityGCm3.toStringAsFixed(2)} g/cm³';

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle) ||
        category.toLowerCase().contains(needle) ||
        notes.toLowerCase().contains(needle);
  }

  MaterialDefinition copyWith({
    String? name,
    double? densityGCm3,
    String? category,
    String? notes,
    bool? isArchived,
  }) {
    return MaterialDefinition(
      id: id,
      name: name ?? this.name,
      densityGCm3: densityGCm3 ?? this.densityGCm3,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
