import 'inventory_control_tower.dart';
import 'material_record.dart';

class MaterialControlTowerDetail {
  const MaterialControlTowerDetail({
    required this.material,
    this.stockPositions = const <StockPosition>[],
    this.movements = const <InventoryMovement>[],
    this.reservations = const <InventoryReservation>[],
    this.alerts = const <InventoryAlert>[],
    this.linkedOrderDemand = 0,
    this.linkedPipelineDemand = 0,
    this.pendingAlertsCount = 0,
  });

  final MaterialRecord material;
  final List<StockPosition> stockPositions;
  final List<InventoryMovement> movements;
  final List<InventoryReservation> reservations;
  final List<InventoryAlert> alerts;
  final double linkedOrderDemand;
  final double linkedPipelineDemand;
  final int pendingAlertsCount;
}
