/// Aggregated stock for the v2 inventory tree, served pre-grouped by
/// `GET /api/inventory/stock`: one entry per item, each with its variation
/// leaves and on-hand totals. See `inventory.variationStockV2` feature flag.
class VariationStockEntry {
  const VariationStockEntry({
    required this.itemId,
    required this.itemName,
    required this.variations,
  });

  final int itemId;
  final String itemName;
  final List<VariationStockLeaf> variations;

  double get total =>
      variations.fold<double>(0, (sum, leaf) => sum + leaf.totalQuantity);
}

class VariationStockLeaf {
  const VariationStockLeaf({
    required this.leafNodeId,
    required this.label,
    required this.totalQuantity,
  });

  final int leafNodeId;
  final String label;
  final double totalQuantity;
}
