import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CartItem {
  final int itemId;
  final String itemName;
  final double quantity;

  CartItem({required this.itemId, required this.itemName, required this.quantity});
}

class CartProvider extends ChangeNotifier {
  List<CartItem> _items = [];
  bool _isLoading = false;

  List<CartItem> get items => _items;
  bool get isLoading => _isLoading;

  int get itemCount => _items.length;

  Future<void> addToCart(int userId, int itemId, String itemName, double quantity) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final url = Uri.parse('http://localhost:3000/api/portal/cart');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'portal_user_id': userId,
          'item_id': itemId,
          'quantity': quantity,
        }),
      );
      
      if (res.statusCode == 200) {
        final existingIndex = _items.indexWhere((i) => i.itemId == itemId);
        if (existingIndex >= 0) {
          _items[existingIndex] = CartItem(
            itemId: itemId,
            itemName: itemName,
            quantity: _items[existingIndex].quantity + quantity,
          );
        } else {
          _items.add(CartItem(itemId: itemId, itemName: itemName, quantity: quantity));
        }
      }
    } catch (e) {
      // In dev environment, just update local state
      final existingIndex = _items.indexWhere((i) => i.itemId == itemId);
      if (existingIndex >= 0) {
        _items[existingIndex] = CartItem(
          itemId: itemId,
          itemName: itemName,
          quantity: _items[existingIndex].quantity + quantity,
        );
      } else {
        _items.add(CartItem(itemId: itemId, itemName: itemName, quantity: quantity));
      }
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
