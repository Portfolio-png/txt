import '../../../../features/items/presentation/providers/items_provider.dart';
import '../../../../features/units/domain/unit_definition.dart';
import '../../../../features/units/presentation/providers/units_provider.dart';

class ChallanItemLabels {
  static bool isWeightUnit(UnitDefinition u) {
    final s = u.symbol.toLowerCase();
    final n = u.name.toLowerCase();
    return s == 'kg' ||
        s == 'kgs' ||
        s == 'g' ||
        s == 'gms' ||
        s == 'gram' ||
        s == 'grams' ||
        s == 'kilogram' ||
        s == 'kilograms' ||
        n.contains('weight');
  }

  static bool isQtyUnit(UnitDefinition u) {
    final s = u.symbol.toLowerCase();
    final n = u.name.toLowerCase();
    return s == 'pcs' ||
        s == 'pc' ||
        s == 'piece' ||
        s == 'pieces' ||
        s == 'unit' ||
        s == 'units' ||
        n.contains('quantity') ||
        n.contains('count');
  }

  /// Returns a tuple of (qtyLabel, weightLabel)
  static (String, String) getDynamicLabels({
    required int? itemId,
    required ItemsProvider itemsProv,
    required UnitsProvider unitsProv,
  }) {
    String qtyLabel = 'Qty';
    String wtLabel = 'Weight';

    if (itemId == null) return (qtyLabel, wtLabel);
    final item = itemsProv.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return (qtyLabel, wtLabel);

    final primary = unitsProv.findById(item.unitId);
    final convs = item.unitConversions
        .map((c) => unitsProv.findById(c.unitId))
        .whereType<UnitDefinition>()
        .toList();

    final allDefs = <UnitDefinition>[];
    if (primary != null) allDefs.add(primary);
    allDefs.addAll(convs);

    final qtyDef = allDefs.where(isQtyUnit).firstOrNull;
    final wtDef = allDefs.where(isWeightUnit).firstOrNull;

    if (qtyDef != null) {
      final group = qtyDef.unitGroupName?.trim() ?? '';
      qtyLabel = group.isNotEmpty ? group : qtyDef.name;
    } else {
      if (primary != null && !isWeightUnit(primary)) {
        final group = primary.unitGroupName?.trim() ?? '';
        qtyLabel = group.isNotEmpty ? group : primary.name;
      }
    }

    if (wtDef != null) {
      final group = wtDef.unitGroupName?.trim() ?? '';
      wtLabel = group.isNotEmpty ? group : wtDef.name;
    }

    return (qtyLabel, wtLabel);
  }
}
