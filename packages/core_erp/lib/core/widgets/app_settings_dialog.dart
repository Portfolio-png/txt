import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/app/preferences/preferences_provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';

class AppSettingsDialog extends StatefulWidget {
  const AppSettingsDialog();

  @override
  State<AppSettingsDialog> createState() =>
      AppSettingsDialogState();
}

class AppSettingsDialogState
    extends State<AppSettingsDialog> {
  bool _isResetting = false;

  Future<void> _handleClear() async {
    setState(() {
      _isResetting = true;
    });
    final auth = context.read<AuthProvider>();
    final success = await auth.clearBackendDatabase();
    if (!mounted) {
      return;
    }
    if (!success) {
      setState(() {
        _isResetting = false;
      });
      showAppSnack(
        SnackBar(
          content: Text(
            auth.errorMessage ?? 'Failed to clear backend database.',
          ),
        ),
      );
      return;
    }

    await Future.wait<void>(<Future<void>>[
      context.read<GroupsProvider>().refresh(),
      context.read<UnitsProvider>().refresh(),
      context.read<ClientsProvider>().refresh(),
      context.read<VendorsProvider>().refresh(),
      context.read<ItemsProvider>().refresh(),
      context.read<OrdersProvider>().refresh(),
      context.read<InventoryProvider>().refresh(),
      context.read<DeliveryChallanProvider>().refresh(),
    ]);

    if (!mounted) {
      return;
    }
    setState(() {
      _isResetting = false;
    });
    showAppSnack(
      const SnackBar(content: Text('Backend database cleared successfully.')),
    );
  }

  Future<void> _handleResetAndReseed(String scenarioId) async {
    // Loading a scenario wipes all business data first — always confirm.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Load demo scenario?'),
        content: const Text(
          'This wipes all business data (orders, challans, inventory, items, '
          'vendors) and loads the selected demo. Users are kept. Cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Wipe & load'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _isResetting = true;
    });
    final auth = context.read<AuthProvider>();
    final success = await auth.resetDemoData(scenarioId: scenarioId);
    if (!mounted) {
      return;
    }
    if (!success) {
      setState(() {
        _isResetting = false;
      });
      showAppSnack(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Failed to reset demo data.'),
        ),
      );
      return;
    }

    await Future.wait<void>(<Future<void>>[
      context.read<GroupsProvider>().refresh(),
      context.read<UnitsProvider>().refresh(),
      context.read<ClientsProvider>().refresh(),
      context.read<VendorsProvider>().refresh(),
      context.read<ItemsProvider>().refresh(),
      context.read<OrdersProvider>().refresh(),
      context.read<InventoryProvider>().refresh(),
      context.read<DeliveryChallanProvider>().refresh(),
    ]);

    if (!mounted) {
      return;
    }
    setState(() {
      _isResetting = false;
    });
    showAppSnack(
      const SnackBar(
        content: Text('Demo data reset and reseeded successfully.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings & Preferences',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Clear operational data or rebuild a fresh demo workspace. Users, sessions, permissions, and track data stay intact.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SoftErpTheme.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Consumer<PreferencesProvider>(
                builder: (context, preferences, _) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: SoftErpTheme.cardSurfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: SoftErpTheme.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: preferences.maintainStocks,
                          onChanged: preferences.toggleMaintainStocks,
                          title: const Text(
                            'Maintain Stocks',
                            style: TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Turn off for typewriter challans that print documents without touching inventory.',
                            style: TextStyle(color: SoftErpTheme.textSecondary),
                          ),
                        ),
                        const Divider(height: 24),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: preferences.enableTrading,
                          onChanged: preferences.toggleTrading,
                          title: const Text(
                            'Trading Mode',
                            style: TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Enable direct buy/sell flow and standard retail/wholesale inventory stock.',
                            style: TextStyle(color: SoftErpTheme.textSecondary),
                          ),
                        ),

                        const Divider(height: 24),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: preferences.enableManufacturing,
                          onChanged: preferences.toggleManufacturing,
                          title: const Text(
                            'Manufacturing Mode',
                            style: TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Enable linkage to production runs, tracking raw material vs. finished goods.',
                            style: TextStyle(color: SoftErpTheme.textSecondary),
                          ),
                        ),
                        const Divider(height: 24),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: preferences.enableServiceMode,
                          onChanged: preferences.toggleServiceMode,
                          title: const Text(
                            'Service (Job Work) Mode',
                            style: TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text(
                            'Enable customer-owned stock receipt (Inward), printing/processing, and return.',
                            style: TextStyle(color: SoftErpTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Test Scenarios',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SoftErpTheme.cardSurfaceAlt,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SoftErpTheme.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Electrical Variations', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Default 13 items with color & module variations.', style: TextStyle(fontSize: 12)),
                      trailing: ElevatedButton(
                        onPressed: _isResetting ? null : () => _handleResetAndReseed('default'),
                        child: const Text('Seed Scenario'),
                      ),
                    ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Manufacturing Processes', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Intermediate items with processing stages (RAW-MLL-ANO).', style: TextStyle(fontSize: 12)),
                      trailing: ElevatedButton(
                        onPressed: _isResetting ? null : () => _handleResetAndReseed('manufacturing'),
                        child: const Text('Seed Scenario'),
                      ),
                    ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mobiles', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Smartphone item with 5 properties, 5 values each.', style: TextStyle(fontSize: 12)),
                      trailing: ElevatedButton(
                        onPressed: _isResetting ? null : () => _handleResetAndReseed('mobiles'),
                        child: const Text('Seed Scenario'),
                      ),
                    ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Scenario A · Decoupled Stock', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Bulk vendor stock-in, two orders consume the shared pool (500 → 350).', style: TextStyle(fontSize: 12)),
                      trailing: ElevatedButton(
                        onPressed: _isResetting ? null : () => _handleResetAndReseed('scenario_a'),
                        child: const Text('Seed Scenario'),
                      ),
                    ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Scenario B · On-Demand Procurement', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Reception challan procured for a specific client order (reception→order link).', style: TextStyle(fontSize: 12)),
                      trailing: ElevatedButton(
                        onPressed: _isResetting ? null : () => _handleResetAndReseed('scenario_b'),
                        child: const Text('Seed Scenario'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isResetting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _isResetting ? null : _handleClear,
                    child: _isResetting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Clear DB (Empty)'),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
