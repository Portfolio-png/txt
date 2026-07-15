import 'package:flutter/foundation.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/items/data/repositories/favorites_repository.dart';

class FavoritesProvider extends ChangeNotifier {
  FavoritesProvider({required FavoritesRepository repository}) : _repository = repository;

  final FavoritesRepository _repository;
  
  List<DeliveryChallanItem> _favorites = [];
  bool _isLoading = false;
  bool _initialized = false;

  List<DeliveryChallanItem> get favorites => _favorites;
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    try {
      final rawFavs = await _repository.getFavorites();
      _favorites = rawFavs.map((f) {
        return DeliveryChallanItem(
          id: 0,
          orderItemId: null,
          productionRunId: null,
          itemId: f['itemId'] as int,
          variationLeafNodeId: f['variationLeafNodeId'] as int,
          variationPathLabel: f['variationPathLabel'] as String? ?? '',
          variationPathNodeIds: (f['variationPathNodeIds'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
          customVariationValues: (f['customVariationValues'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(int.tryParse(k) ?? 0, v.toString()),
              ) ??
              {},
          particulars: '', // UI will hydrate this if needed, or we can look it up in ItemsProvider
          quantityPcs: '1',
          weight: '0.0',
          lineNo: 0,
          hsnCode: '',
          note: '',
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to load favorites: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool isFavorite(int itemId, int variationLeafNodeId) {
    return _favorites.any((f) => f.itemId == itemId && f.variationLeafNodeId == variationLeafNodeId);
  }

  Future<void> toggleFavorite(DeliveryChallanItem item, bool isFav) async {
    if (isFav) {
      // Add
      if (!isFavorite(item.itemId ?? 0, item.variationLeafNodeId)) {
        _favorites.add(item);
        notifyListeners();
        
        final success = await _repository.addFavorite(
          itemId: item.itemId ?? 0,
          variationLeafNodeId: item.variationLeafNodeId,
          variationPathLabel: item.variationPathLabel,
          variationPathNodeIds: item.variationPathNodeIds,
          customVariationValues: item.customVariationValues,
        );
        
        if (!success) {
          _favorites.removeWhere((f) => f.itemId == item.itemId && f.variationLeafNodeId == item.variationLeafNodeId);
          notifyListeners();
        }
      }
    } else {
      // Remove
      final existingIndex = _favorites.indexWhere((f) => f.itemId == item.itemId && f.variationLeafNodeId == item.variationLeafNodeId);
      if (existingIndex >= 0) {
        final removed = _favorites.removeAt(existingIndex);
        notifyListeners();

        final success = await _repository.removeFavorite(item.itemId ?? 0, item.variationLeafNodeId);
        
        if (!success) {
          _favorites.insert(existingIndex, removed);
          notifyListeners();
        }
      }
    }
  }
}
