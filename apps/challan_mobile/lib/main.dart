import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/network/authenticated_http_client.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/groups/data/repositories/api_group_repository.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/inventory/data/repositories/api_inventory_repository.dart';
import 'package:core_erp/features/inventory/data/repositories/inventory_repository.dart';
import 'package:core_erp/features/inventory/presentation/providers/inventory_provider.dart';
import 'package:core_erp/features/clients/data/repositories/api_client_repository.dart';
import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/delivery_challans/data/api_delivery_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/data/delivery_challan_repository.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/challan_editor_command_provider.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:core_erp/features/items/data/repositories/api_item_repository.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/features/orders/data/repositories/api_order_repository.dart';
import 'package:core_erp/features/orders/data/repositories/order_repository.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/units/data/repositories/api_unit_repository.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/vendors/data/repositories/api_vendor_repository.dart';
import 'package:core_erp/features/vendors/data/repositories/vendor_repository.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:core_erp/features/search/data/repositories/api_search_repository.dart';
import 'package:core_erp/features/search/data/repositories/search_repository.dart';
import 'package:core_erp/features/search/presentation/providers/search_provider.dart';

import 'screens/home_screen.dart';
import 'services/network_discovery_service.dart';
import 'services/socket_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PaperMobileBootstrap());
}

class PaperMobileBootstrap extends StatelessWidget {
  const PaperMobileBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkDiscoveryService()..discoverServer(),
      child: const BootstrapGate(),
    );
  }
}

class BootstrapGate extends StatefulWidget {
  const BootstrapGate({super.key});

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate> {
  final TextEditingController _ipController = TextEditingController();

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final discovery = context.watch<NetworkDiscoveryService>();
    
    if (discovery.discoveredUrl == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: SoftErpTheme.accent,
            surface: SoftErpTheme.canvas,
            primary: SoftErpTheme.accent,
            onPrimary: Colors.white,
            secondary: SoftErpTheme.accentDark,
          ),
          scaffoldBackgroundColor: SoftErpTheme.canvas,
          cardTheme: CardThemeData(
            color: SoftErpTheme.cardSurface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
              side: const BorderSide(color: SoftErpTheme.border),
            ),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: SoftErpTheme.cardSurface,
            foregroundColor: SoftErpTheme.textPrimary,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: SoftErpTheme.textPrimary),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: SoftErpTheme.cardSurface,
            indicatorColor: SoftErpTheme.accentSoft,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(color: SoftErpTheme.accent, fontWeight: FontWeight.bold);
              }
              return const TextStyle(color: SoftErpTheme.textSecondary);
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: SoftErpTheme.accent);
              }
              return const IconThemeData(color: SoftErpTheme.textSecondary);
            }),
          ),
          useMaterial3: true,
        ),
        home: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (discovery.isSearching) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    const Text('Scanning factory Wi-Fi for Desktop...', style: TextStyle(fontSize: 18)),
                  ] else if (discovery.hasTimedOut) ...[
                    const Icon(Icons.wifi_off, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('No Local Server found via mDNS.', style: TextStyle(fontSize: 18, color: Colors.red)),
                    const SizedBox(height: 8),
                    const Text('Your Wi-Fi router might be blocking discovery.', textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'Owner Mac IP Address',
                        hintText: 'e.g. 192.168.1.100',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (_ipController.text.trim().isNotEmpty) {
                          discovery.manualConnect(_ipController.text.trim());
                        }
                      },
                      child: const Text('Connect Manually'),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => discovery.manualConnect('localhost'),
                      child: const Text('Use USB Debugging (localhost)'),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => discovery.discoverServer(),
                      child: const Text('Scan Again'),
                    ),
                  ] else ...[
                    const Icon(Icons.error_outline, size: 64, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text('Discovery failed to start.', style: TextStyle(fontSize: 18, color: Colors.orange)),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'Owner Mac IP Address',
                        hintText: 'e.g. 192.168.1.100',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (_ipController.text.trim().isNotEmpty) {
                          discovery.manualConnect(_ipController.text.trim());
                        }
                      },
                      child: const Text('Connect Manually'),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => discovery.manualConnect('localhost'),
                      child: const Text('Use USB Debugging (localhost)'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MyApp(apiUrl: discovery.discoveredUrl!);
  }
}

class MyApp extends StatelessWidget {
  final String apiUrl;
  const MyApp({super.key, required this.apiUrl});

  AuthenticatedHttpClient _authClient(AuthProvider auth) {
    return AuthenticatedHttpClient(tokenResolver: () => auth.token);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) {
            final provider = AuthProvider(
              baseUrl: apiUrl,
              demoMode: false,
            )..initialize();
            
            // Auto-login for mobile dev
            provider.login(
              email: 'super@paper.local',
              password: 'Paper@12345',
            );
            return provider;
          },
        ),
        Provider<InventoryRepository>(
          create: (context) => ApiInventoryRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            useMockResponses: false,
          ),
        ),
        Provider<UnitRepository>(
          create: (context) => ApiUnitRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            useMockResponses: false,
          ),
        ),
        Provider<GroupRepository>(
          create: (context) => ApiGroupRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            useMockResponses: false,
          ),
        ),
        Provider<ClientRepository>(
          create: (context) => ApiClientRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            useMockResponses: false,
          ),
        ),
        Provider<VendorRepository>(
          create: (context) => ApiVendorRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            useMockResponses: false,
          ),
        ),
        Provider<ItemRepository>(
          create: (context) => ApiItemRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            useMockResponses: false,
          ),
        ),
        Provider<OrderRepository>(
          create: (context) => ApiOrderRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            useMockResponses: false,
          ),
        ),
        Provider<ChallanRepository>(
          create: (context) => ApiChallanRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            useMockResponses: false,
          ),
        ),
        Provider<SearchRepository>(
          create: (context) => ApiSearchRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
          ),
        ),
        ChangeNotifierProvider(create: (_) => ChallanEditorCommandProvider()),
        ChangeNotifierProvider(
          create: (_) => SocketService()..connect(apiUrl),
        ),
        ChangeNotifierProxyProvider<OrderRepository, OrdersProvider>(
          create: (context) => OrdersProvider(repository: context.read<OrderRepository>())..initialize(),
          update: (context, repository, previous) => previous ?? OrdersProvider(repository: repository)..initialize(),
        ),
        ChangeNotifierProxyProvider<InventoryRepository, InventoryProvider>(
          create: (context) => InventoryProvider(repository: context.read<InventoryRepository>())..initialize(),
          update: (context, repository, previous) => previous ?? InventoryProvider(repository: repository)..initialize(),
        ),
        ChangeNotifierProxyProvider<UnitRepository, UnitsProvider>(
          create: (context) => UnitsProvider(repository: context.read<UnitRepository>())..initialize(),
          update: (context, repository, previous) => previous ?? UnitsProvider(repository: repository)..initialize(),
        ),
        ChangeNotifierProxyProvider<GroupRepository, GroupsProvider>(
          create: (context) => GroupsProvider(repository: context.read<GroupRepository>())..initialize(),
          update: (context, repository, previous) => previous ?? GroupsProvider(repository: repository)..initialize(),
        ),
        ChangeNotifierProxyProvider<ClientRepository, ClientsProvider>(
          create: (context) => ClientsProvider(repository: context.read<ClientRepository>())..initialize(),
          update: (context, repository, previous) => previous ?? ClientsProvider(repository: repository)..initialize(),
        ),
        ChangeNotifierProxyProvider<VendorRepository, VendorsProvider>(
          create: (context) => VendorsProvider(repository: context.read<VendorRepository>())..initialize(),
          update: (context, repository, previous) => previous ?? VendorsProvider(repository: repository)..initialize(),
        ),
        ChangeNotifierProxyProvider<ItemRepository, ItemsProvider>(
          create: (context) => ItemsProvider(repository: context.read<ItemRepository>())..initialize(),
          update: (context, repository, previous) => previous ?? ItemsProvider(repository: repository)..initialize(),
        ),
        ChangeNotifierProxyProvider<ChallanRepository, DeliveryChallanProvider>(
          create: (context) => DeliveryChallanProvider(repository: context.read<ChallanRepository>())..initialize(),
          update: (context, repository, previous) => previous ?? DeliveryChallanProvider(repository: repository)..initialize(),
        ),
        ChangeNotifierProxyProvider<SearchRepository, SearchProvider>(
          create: (context) => SearchProvider(repository: context.read<SearchRepository>()),
          update: (context, repository, previous) => previous ?? SearchProvider(repository: repository),
        ),
      ],
      child: MaterialApp(
        title: 'Challan Mobile',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: SoftErpTheme.accent,
            surface: SoftErpTheme.canvas,
            primary: SoftErpTheme.accent,
            onPrimary: Colors.white,
            secondary: SoftErpTheme.accentDark,
          ),
          scaffoldBackgroundColor: SoftErpTheme.canvas,
          cardTheme: CardThemeData(
            color: SoftErpTheme.cardSurface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
              side: const BorderSide(color: SoftErpTheme.border),
            ),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: SoftErpTheme.cardSurface,
            foregroundColor: SoftErpTheme.textPrimary,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: SoftErpTheme.textPrimary),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: SoftErpTheme.cardSurface,
            indicatorColor: SoftErpTheme.accentSoft,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(color: SoftErpTheme.accent, fontWeight: FontWeight.bold);
              }
              return const TextStyle(color: SoftErpTheme.textSecondary);
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: SoftErpTheme.accent);
              }
              return const IconThemeData(color: SoftErpTheme.textSecondary);
            }),
          ),
          useMaterial3: true,
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _lastRefreshToken;

  void _refreshAfterAuthentication(String token) {
    if (_lastRefreshToken == token) return;
    _lastRefreshToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.wait<void>([
        context.read<OrdersProvider>().refresh(),
        context.read<InventoryProvider>().refresh(),
        context.read<UnitsProvider>().refresh(),
        context.read<GroupsProvider>().refresh(),
        context.read<ClientsProvider>().refresh(),
        context.read<VendorsProvider>().refresh(),
        context.read<ItemsProvider>().refresh(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final authenticated = auth.isAuthenticated;
    final token = auth.token;
    if (authenticated && token != null && token.isNotEmpty) {
      _refreshAfterAuthentication(token);
    }
    
    if (auth.errorMessage != null && !authenticated) {
      return Scaffold(
        body: Center(
          child: Text(
            "Auth Error: ${auth.errorMessage}",
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
    
    return authenticated ? const HomeScreen() : const Scaffold(body: Center(child: Text("Authenticating...")));
  }
}
