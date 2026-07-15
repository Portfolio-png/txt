import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';

class VendorHistoryRepository {
  VendorHistoryRepository({
    required http.Client client,
    required this.baseUrl,
  }) : _client = client;

  final http.Client _client;
  final String baseUrl;

  Future<List<DeliveryChallanItem>> getVendorPurchaseHistory(int vendorId) async {
    final uri = Uri.parse('$baseUrl/api/vendors/$vendorId/purchase-history');
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['success'] == true && json['history'] != null) {
        final rawHistory = List<Map<String, dynamic>>.from(json['history']);
        return rawHistory.map((h) {
          return DeliveryChallanItem(
            id: 0,
            orderItemId: null,
            productionRunId: null,
            itemId: h['itemId'] as int,
            variationLeafNodeId: h['variationLeafNodeId'] as int,
            variationPathLabel: h['variationPathLabel'] as String? ?? '',
            variationPathNodeIds: (h['variationPathNodeIds'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
            customVariationValues: (h['customVariationValues'] as Map<String, dynamic>?)?.map(
                  (k, v) => MapEntry(int.tryParse(k) ?? 0, v.toString()),
                ) ??
                {},
            particulars: h['particulars'] as String? ?? 'Historical Item',
            quantityPcs: '1',
            weight: '0.0',
            lineNo: 0,
            hsnCode: '',
            note: '',
          );
        }).toList();
      }
    }
    return [];
  }
}
