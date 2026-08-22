import 'package:flutter/foundation.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/vendors/data/repositories/vendor_history_repository.dart';

class VendorHistoryProvider extends ChangeNotifier {
  VendorHistoryProvider({required VendorHistoryRepository repository})
    : _repository = repository;

  final VendorHistoryRepository _repository;

  final Map<int, List<DeliveryChallanItem>> _vendorHistories = {};
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  List<DeliveryChallanItem> getHistoryForVendor(int vendorId) {
    return _vendorHistories[vendorId] ?? [];
  }

  Future<void> loadHistoryForVendor(int vendorId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final history = await _repository.getVendorPurchaseHistory(vendorId);
      _vendorHistories[vendorId] = history;
    } catch (e) {
      debugPrint('Failed to load vendor history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
