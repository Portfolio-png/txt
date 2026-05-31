const defaultProductionFactoryId = '1';
const defaultProductionShopFloorId = '1';

bool belongsToDefaultFloor(String? shopFloorId) {
  final normalized = shopFloorId?.trim();
  return normalized == null ||
      normalized.isEmpty ||
      normalized == defaultProductionShopFloorId;
}
