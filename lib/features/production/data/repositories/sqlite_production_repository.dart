import '../../domain/factory.dart';
import '../../domain/shop_floor.dart';
import '../datasources/offline_database_helper.dart';
import 'production_repository.dart';

class SqliteProductionRepository implements ProductionRepository {
  final OfflineSyncDbHelper _dbHelper;

  SqliteProductionRepository({OfflineSyncDbHelper? dbHelper})
      : _dbHelper = dbHelper ?? OfflineSyncDbHelper.instance;

  @override
  Future<List<Factory>> getFactories() async {
    final db = await _dbHelper.database;
    final results = await db.query('factories', orderBy: 'created_at DESC');
    return results.map((e) => Factory.fromJson(e)).toList();
  }

  @override
  Future<Factory> createFactory(Factory factory) async {
    final db = await _dbHelper.database;
    final newFactory = factory.copyWith(createdAt: DateTime.now());
    await db.insert('factories', newFactory.toJson());
    return newFactory;
  }

  @override
  Future<void> deleteFactory(String id) async {
    final db = await _dbHelper.database;
    await db.delete('factories', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<ShopFloor>> getShopFloors(String factoryId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'shop_floors',
      where: 'factory_id = ?',
      whereArgs: [factoryId],
      orderBy: 'created_at DESC',
    );
    return results.map((e) => ShopFloor.fromJson(e)).toList();
  }

  @override
  Future<ShopFloor> createShopFloor(ShopFloor shopFloor) async {
    final db = await _dbHelper.database;
    final newShopFloor = shopFloor.copyWith(createdAt: DateTime.now());
    await db.insert('shop_floors', newShopFloor.toJson());
    return newShopFloor;
  }

  @override
  Future<void> deleteShopFloor(String id) async {
    final db = await _dbHelper.database;
    await db.delete('shop_floors', where: 'id = ?', whereArgs: [id]);
  }
}
