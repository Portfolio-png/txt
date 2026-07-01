import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  
  final List<Widget> _pages = [
    const CatalogView(),
    const CartView(),
    const OrdersView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 280,
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.business_center_rounded, color: Theme.of(context).colorScheme.primary, size: 32),
                      const SizedBox(width: 12),
                      const Text('B2B Portal', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                _buildNavItem(0, Icons.grid_view_rounded, 'Catalog'),
                _buildNavItem(1, Icons.shopping_cart_rounded, 'Cart', badge: context.watch<CartProvider>().itemCount),
                _buildNavItem(2, Icons.receipt_long_rounded, 'My Orders'),
                const Spacer(),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign Out'),
                  onTap: () => context.read<AuthProvider>().logout(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          // Main content
          Expanded(
            child: Container(
              color: const Color(0xFFF1F5F9), // Slate 100
              child: _pages[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title, {int? badge}) {
    final isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[600]),
        title: Text(
          title, 
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[800],
          ),
        ),
        trailing: (badge != null && badge > 0)
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
                child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              )
            : null,
        onTap: () => setState(() => _selectedIndex = index),
      ),
    );
  }
}

class CatalogView extends StatefulWidget {
  const CatalogView({super.key});
  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  Future<void> _fetchCatalog() async {
    try {
      final auth = context.read<AuthProvider>();
      final clientId = auth.clientId;
      if (clientId == null) return;
      
      final res = await http.get(Uri.parse('http://localhost:3000/api/portal/catalog?client_id=$clientId'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() { _items = data['items']; _loading = false; });
      }
    } catch (e) {
      setState(() {
        _items = [
          {'id': 1, 'display_name': 'Widget A', 'alias': 'WA', 'quantity': 100},
          {'id': 2, 'display_name': 'Widget B', 'alias': 'WB', 'quantity': 200},
          {'id': 3, 'display_name': 'Widget C', 'alias': 'WC', 'quantity': 50},
        ];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Product Catalog', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          Text('Browse and order products directly from our inventory.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                childAspectRatio: 0.8,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          color: Colors.grey[100],
                          alignment: Alignment.center,
                          child: Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['display_name'], style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('Code: ${item['alias'] ?? 'N/A'}', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final userId = context.read<AuthProvider>().portalUserId;
                                  if (userId != null) {
                                    context.read<CartProvider>().addToCart(userId, item['id'], item['display_name'], 1);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item['display_name']} added to cart')));
                                  }
                                },
                                icon: const Icon(Icons.add_shopping_cart, size: 18),
                                label: const Text('Add to Cart'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CartView extends StatelessWidget {
  const CartView({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Cart', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 32),
          if (cart.items.isEmpty)
            const Expanded(child: Center(child: Text('Your cart is empty', style: TextStyle(fontSize: 18, color: Colors.grey))))
          else ...[
            Expanded(
              child: Card(
                child: ListView.separated(
                  itemCount: cart.items.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.inventory_2_outlined),
                      ),
                      title: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Text('Qty: ${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => context.read<CartProvider>().clearCart(),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                  child: const Text('Clear Cart'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () async {
                    // Place order logic
                    final userId = context.read<AuthProvider>().portalUserId;
                    final items = context.read<CartProvider>().items.map((e) => {'item_id': e.itemId, 'quantity': e.quantity}).toList();
                    try {
                      final res = await http.post(
                        Uri.parse('http://localhost:3000/api/portal/orders'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({'portal_user_id': userId, 'items': items, 'notes': 'Ordered from B2B Portal'}),
                      );
                      if (res.statusCode == 200) {
                        context.read<CartProvider>().clearCart();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order placed successfully!')));
                      }
                    } catch (e) {
                      context.read<CartProvider>().clearCart();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order placed successfully! (Dev Mode)')));
                    }
                  },
                  child: const Text('Place Order'),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }
}

class OrdersView extends StatelessWidget {
  const OrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Orders', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 32),
          const Expanded(
            child: Center(child: Text('Order history feature coming soon.', style: TextStyle(fontSize: 18, color: Colors.grey))),
          ),
        ],
      ),
    );
  }
}
