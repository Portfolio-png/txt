import '../domain/delivery_challan.dart';

abstract class ChallanRepository {
  Future<void> init();

  Future<CompanyProfile> getCompanyProfile();

  Future<CompanyProfile> updateCompanyProfile(CompanyProfile profile);

  Future<List<DeliveryChallan>> getChallans({
    ChallanType? type,
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

typedef DeliveryChallanRepository = ChallanRepository;

class ChallanDraftInput {
  const ChallanDraftInput({
    required this.type,
    required this.orderId,
    required this.vendorId,
    required this.date,
    required this.location,
    required this.sourceReference,
    required this.notes,
    required this.items,
  });

  final ChallanType type;
  final int orderId;
  final int vendorId;
  final DateTime date;
  final String location;
  final String sourceReference;
  final String notes;
  final List<DeliveryChallanItem> items;

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      if (orderId > 0) 'order_id': orderId,
      if (vendorId > 0) 'vendor_id': vendorId,
      'date': date.toIso8601String().substring(0, 10),
      'location': location.trim(),
      'source_reference': sourceReference.trim(),
      'notes': notes.trim(),
      'items': items
          .map(
            (item) => {
              if (item.orderItemId != null) 'order_item_id': item.orderItemId,
              if (item.itemId != null) 'item_id': item.itemId,
              'variation_leaf_node_id': item.variationLeafNodeId,
              'particulars': item.particulars,
              'variation_path_label': item.variationPathLabel,
              'quantity_pcs': item.quantityPcs.trim(),
              'weight': item.weight.trim(),
            },
          )
          .toList(growable: false),
    };
  }
}

typedef DeliveryChallanDraftInput = ChallanDraftInput;

class ChallanApiException implements Exception {
  const ChallanApiException(this.message, {this.debugMessage});

  final String message;
  final String? debugMessage;

  @override
  String toString() => message;
}

typedef DeliveryChallanApiException = ChallanApiException;
