/// Every material the system ships knowing, with its handbook density.
///
/// Global, and deliberately not the material master: the master is what this
/// shop cuts, at the densities its suppliers quote. This is the catalogue it
/// was seeded from, kept so a material that was archived can be put back with
/// one tick rather than a handbook, and so the whole table can be handed to
/// someone as a file.
///
/// Mirrors backend/migrations/034-material-master.sql. Densities are in g/cm³
/// because that is how a materials table is written and how anyone checking a
/// figure will look it up.
library;

import 'package:flutter/foundation.dart';

import 'material_definition.dart';

/// One catalogue entry: what a material is called and what it weighs.
@immutable
class GlobalMaterial {
  const GlobalMaterial({
    required this.name,
    required this.densityGCm3,
    this.category = 'metal',
    this.notes = '',
  });

  final String name;
  final double densityGCm3;
  final String category;
  final String notes;

  /// Two decimals: the precision a handbook quotes, and more would imply a
  /// certainty alloys do not have.
  String get densityLabel => '${densityGCm3.toStringAsFixed(2)} g/cm³';

  /// A master record for this entry, ready to be created.
  MaterialDefinition toDefinition() => MaterialDefinition(
    id: 0,
    name: name,
    densityGCm3: densityGCm3,
    category: category,
    notes: notes,
  );
}

/// The categories, in the order someone scanning the list expects them.
const List<String> globalMaterialCategories = <String>[
  'metal',
  'plastic',
  'other',
];

String globalMaterialCategoryLabel(String category) => switch (category) {
  'metal' => 'Metals',
  'plastic' => 'Plastics',
  _ => 'Other',
};

/// The catalogue. The common shop metals come first, then the rest
/// alphabetically — the order the seed migration writes them in.
const List<GlobalMaterial> globalMaterials = <GlobalMaterial>[
  GlobalMaterial(
    name: 'MS',
    densityGCm3: 7.85,
    notes: 'Mild steel — the common shop default',
  ),
  GlobalMaterial(
    name: 'Stainless Steel',
    densityGCm3: 7.90,
    notes: '304 is nearer 8.00, 430 nearer 7.70',
  ),
  GlobalMaterial(name: 'Aluminium', densityGCm3: 2.70),
  GlobalMaterial(
    name: 'Brass',
    densityGCm3: 8.50,
    notes: 'Varies 8.40-8.70 by grade',
  ),
  GlobalMaterial(name: 'Copper', densityGCm3: 8.96),
  GlobalMaterial(
    name: 'Bronze',
    densityGCm3: 8.80,
    notes: 'Varies 8.70-8.90 by grade',
  ),
  GlobalMaterial(
    name: 'Cast Iron',
    densityGCm3: 7.20,
    notes: 'Grey iron; ductile runs nearer 7.10',
  ),
  GlobalMaterial(
    name: 'Acrylic',
    densityGCm3: 1.18,
    category: 'plastic',
    notes: 'PMMA',
  ),
  GlobalMaterial(name: 'Beryllium', densityGCm3: 1.85),
  GlobalMaterial(name: 'Chrome', densityGCm3: 7.19, notes: 'Chromium'),
  GlobalMaterial(
    name: 'Columbium',
    densityGCm3: 8.57,
    notes: 'Also called niobium',
  ),
  GlobalMaterial(
    name: 'Duralumin',
    densityGCm3: 2.79,
    notes: 'Aluminium-copper alloy',
  ),
  GlobalMaterial(
    name: 'Glass',
    densityGCm3: 2.50,
    category: 'other',
    notes: 'Soda-lime; varies 2.40-2.80',
  ),
  GlobalMaterial(name: 'Gold', densityGCm3: 19.32),
  GlobalMaterial(name: 'Lead', densityGCm3: 11.34),
  GlobalMaterial(name: 'Magnesium', densityGCm3: 1.74),
  GlobalMaterial(
    name: 'Mercury',
    densityGCm3: 13.53,
    category: 'other',
    notes: 'Liquid at room temperature',
  ),
  GlobalMaterial(name: 'Molybdenum', densityGCm3: 10.22),
  GlobalMaterial(name: 'Nickel', densityGCm3: 8.90),
  GlobalMaterial(
    name: 'Nylon',
    densityGCm3: 1.15,
    category: 'plastic',
    notes: 'Nylon 6/6',
  ),
  GlobalMaterial(
    name: 'PB / Gunmetal',
    densityGCm3: 8.80,
    notes: 'Phosphor bronze / gunmetal',
  ),
  GlobalMaterial(name: 'Platinum', densityGCm3: 21.45),
  GlobalMaterial(name: 'Polycarbonate', densityGCm3: 1.20, category: 'plastic'),
  GlobalMaterial(
    name: 'Polyethylene',
    densityGCm3: 0.95,
    category: 'plastic',
    notes: 'HDPE; LDPE is nearer 0.92',
  ),
  GlobalMaterial(name: 'Polypropylene', densityGCm3: 0.90, category: 'plastic'),
  GlobalMaterial(name: 'Potassium', densityGCm3: 0.86),
  GlobalMaterial(name: 'PVDF', densityGCm3: 1.78, category: 'plastic'),
  GlobalMaterial(name: 'Silver', densityGCm3: 10.49),
  GlobalMaterial(name: 'Tantalum', densityGCm3: 16.65),
  GlobalMaterial(
    name: 'Teflon',
    densityGCm3: 2.20,
    category: 'plastic',
    notes: 'PTFE',
  ),
  GlobalMaterial(name: 'Tin', densityGCm3: 7.31),
  GlobalMaterial(name: 'Titanium', densityGCm3: 4.51),
  GlobalMaterial(name: 'Tungsten', densityGCm3: 19.25),
  GlobalMaterial(
    name: 'Water',
    densityGCm3: 1.00,
    category: 'other',
    notes: 'The reference every density is against',
  ),
  GlobalMaterial(name: 'Zinc', densityGCm3: 7.14),
  GlobalMaterial(name: 'Zirconium', densityGCm3: 6.52),
];

/// The catalogue grouped by category, categories in display order. Every
/// category is present even when empty, so the dialog's sections are stable.
Map<String, List<GlobalMaterial>> get globalMaterialsByCategory => {
  for (final category in globalMaterialCategories)
    category: globalMaterials
        .where((material) => material.category == category)
        .toList(growable: false),
};

/// The catalogue as rows for a CSV, sheet or PDF — one per material, in
/// catalogue order, with whether it is in this shop's master.
///
/// [masterNames] is compared case-insensitively, because "brass" and "Brass"
/// are the same material to everyone on the floor.
List<Map<String, dynamic>> globalMaterialExportRows({
  Iterable<String> masterNames = const <String>[],
}) {
  final inMaster = masterNames.map((name) => name.trim().toLowerCase()).toSet();
  return globalMaterials
      .map(
        (material) => <String, dynamic>{
          'Material': material.name,
          'Density (g/cm³)': material.densityGCm3.toStringAsFixed(2),
          'Category': globalMaterialCategoryLabel(material.category),
          'Notes': material.notes,
          'In your master': inMaster.contains(material.name.toLowerCase())
              ? 'Yes'
              : 'No',
        },
      )
      .toList(growable: false);
}
