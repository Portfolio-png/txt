import '../domain/delivery_challan.dart';

abstract class DeliveryChallanRepository {
  Future<void> init();

  Future<CompanyProfile> getCompanyProfile();

  Future<CompanyProfile> updateCompanyProfile(CompanyProfile profile);

  Future<List<DeliveryChallan>> getChallans({
    DeliveryChallanStatus? status,
    String search = '',
    DateTime? dateFrom,
    DateTime? dateTo,
    int? orderId,
  });

  Future<List<DeliveryChallan>> getOrderChallans(int orderId);

  Future<DeliveryChallan> getChallan(int id);

  Future<DeliveryChallan> createChallan(DeliveryChallanDraftInput input);

  Future<DeliveryChallan> updateChallan(
    int id,
    DeliveryChallanDraftInput input,
  );

  Future<DeliveryChallan> issueChallan(int id);

  Future<DeliveryChallan> cancelChallan(int id);

  Future<void> deleteChallan(int id);

  Future<void> recordPrint(int id);
}

class DeliveryChallanDraftInput {
  const DeliveryChallanDraftInput({
    required this.orderId,
    required this.date,
    required this.notes,
    required this.items,
  });

  final int orderId;
  final DateTime date;
  final String notes;
  final List<DeliveryChallanItem> items;

  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
      'date': date.toIso8601String().substring(0, 10),
      'notes': notes.trim(),
      'items': items
          .map(
            (item) => {
              if (item.orderItemId != null) 'order_item_id': item.orderItemId,
              if (item.itemId != null) 'item_id': item.itemId,
              'quantity_pcs': item.quantityPcs.trim(),
              'weight': item.weight.trim(),
            },
          )
          .toList(growable: false),
    };
  }
}

class DeliveryChallanApiException implements Exception {
  const DeliveryChallanApiException(this.message, {this.debugMessage});

  final String message;
  final String? debugMessage;

  @override
  String toString() => message;
}
