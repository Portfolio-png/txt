import '../../domain/factory.dart';
import '../../domain/shop_floor.dart';

abstract class ProductionRepository {
  Future<List<Factory>> getFactories();
  Future<Factory> createFactory(Factory factory);
  Future<void> deleteFactory(String id);

  Future<List<ShopFloor>> getShopFloors(String factoryId);
  Future<ShopFloor> createShopFloor(ShopFloor shopFloor);
  Future<void> deleteShopFloor(String id);
}
