import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/network/authenticated_http_client.dart';
import 'package:core_erp/core/navigation/app_navigation.dart';
import 'package:core_erp/app/preferences/preferences_provider.dart';
import 'package:core_erp/features/auth/presentation/providers/auth_provider.dart';
import 'package:core_erp/features/auth/presentation/screens/login_screen.dart';
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

import 'shell/app_shell.dart';
import 'shell/navigation_provider.dart';

const _isDemoMode = bool.fromEnvironment(
  'PAPER_DEMO_MODE',
  defaultValue: false,
);
const _localApiBaseUrl = 'http://localhost:18080';
const _configuredApiBaseUrl = String.fromEnvironment('PAPER_API_BASE_URL');

final _apiBaseUrl = _resolveApiBaseUrl();

String _resolveApiBaseUrl() {
  final configured = _configuredApiBaseUrl.trim();
  if (configured.isNotEmpty) {
    return configured.replaceFirst(RegExp(r'/$'), '');
  }
  if (kIsWeb && (Uri.base.scheme == 'http' || Uri.base.scheme == 'https')) {
    return Uri.base.origin.replaceFirst(RegExp(r'/$'), '');
  }
  return _localApiBaseUrl;
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.authProvider,
    this.inventoryRepository,
    this.groupRepository,
    this.unitRepository,
    this.clientRepository,
    this.deliveryChallanRepository,
    this.vendorRepository,
    this.itemRepository,
    this.orderRepository,
    this.demoModeOverride,
  });

  final AuthProvider? authProvider;
  final InventoryRepository? inventoryRepository;
  final GroupRepository? groupRepository;
  final UnitRepository? unitRepository;
  final ClientRepository? clientRepository;
  final DeliveryChallanRepository? deliveryChallanRepository;
  final VendorRepository? vendorRepository;
  final ItemRepository? itemRepository;
  final OrderRepository? orderRepository;
  final bool? demoModeOverride;

  bool get _effectiveDemoMode => demoModeOverride ?? _isDemoMode;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: SoftErpTheme.accent),
      scaffoldBackgroundColor: SoftErpTheme.canvas,
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontSize: 16),
        bodyMedium: TextStyle(fontSize: 14),
        bodySmall: TextStyle(fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SoftErpTheme.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SoftErpTheme.dangerBg),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SoftErpTheme.dangerText, width: 1.5),
        ),
        labelStyle: const TextStyle(
          color: SoftErpTheme.textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        hintStyle: const TextStyle(
          color: SoftErpTheme.textSecondary,
          fontSize: 14,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: SoftErpTheme.border),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: SoftErpTheme.textPrimary,
          fontFamily: 'Segoe UI',
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: SoftErpTheme.textSecondary,
          fontFamily: 'Segoe UI',
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          shadowColor: const Color(0x146A74B8),
          backgroundColor: SoftErpTheme.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: SoftErpTheme.accentDark),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Segoe UI'),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SoftErpTheme.accent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Segoe UI'),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SoftErpTheme.textPrimary,
          side: const BorderSide(color: SoftErpTheme.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Segoe UI'),
        ),
      ),
    );

    return MultiProvider(
      providers: [
        if (authProvider != null)
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider!)
        else
          ChangeNotifierProvider<AuthProvider>(
            create: (_) =>
                AuthProvider(baseUrl: _apiBaseUrl, demoMode: _effectiveDemoMode)
                  ..initialize(),
          ),
        Provider<InventoryRepository>(
          create: (context) =>
              inventoryRepository ??
              _buildInventoryRepository(context.read<AuthProvider>()),
        ),
        Provider<UnitRepository>(
          create: (context) =>
              unitRepository ??
              _buildUnitRepository(context.read<AuthProvider>()),
        ),
        Provider<GroupRepository>(
          create: (context) =>
              groupRepository ??
              _buildGroupRepository(context.read<AuthProvider>()),
        ),
        Provider<ClientRepository>(
          create: (context) =>
              clientRepository ??
              _buildClientRepository(context.read<AuthProvider>()),
        ),
        Provider<VendorRepository>(
          create: (context) =>
              vendorRepository ??
              _buildVendorRepository(context.read<AuthProvider>()),
        ),
        Provider<ItemRepository>(
          create: (context) =>
              itemRepository ??
              _buildItemRepository(context.read<AuthProvider>()),
        ),
        Provider<OrderRepository>(
          create: (context) =>
              orderRepository ??
              _buildOrderRepository(context.read<AuthProvider>()),
        ),
        Provider<ChallanRepository>(
          create: (context) =>
              deliveryChallanRepository ??
              _buildDeliveryChallanRepository(context.read<AuthProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        Provider<AppNavigation>(create: (context) => AppNavigationWrapper(context.read<NavigationProvider>())),
        ChangeNotifierProvider(create: (_) => ChallanEditorCommandProvider()),
        ChangeNotifierProxyProvider<OrderRepository, OrdersProvider>(
          create: (context) =>
              OrdersProvider(repository: context.read<OrderRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? OrdersProvider(repository: repository)
                ..initialize(),
        ),
        ChangeNotifierProxyProvider<InventoryRepository, InventoryProvider>(
          create: (context) =>
              InventoryProvider(repository: context.read<InventoryRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? InventoryProvider(repository: repository)
                ..initialize(),
        ),
        ChangeNotifierProxyProvider<UnitRepository, UnitsProvider>(
          create: (context) =>
              UnitsProvider(repository: context.read<UnitRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? UnitsProvider(repository: repository)
                ..initialize(),
        ),
        ChangeNotifierProxyProvider<GroupRepository, GroupsProvider>(
          create: (context) =>
              GroupsProvider(repository: context.read<GroupRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? GroupsProvider(repository: repository)
                ..initialize(),
        ),
        ChangeNotifierProxyProvider<ClientRepository, ClientsProvider>(
          create: (context) =>
              ClientsProvider(repository: context.read<ClientRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? ClientsProvider(repository: repository)
                ..initialize(),
        ),
        ChangeNotifierProxyProvider<VendorRepository, VendorsProvider>(
          create: (context) =>
              VendorsProvider(repository: context.read<VendorRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? VendorsProvider(repository: repository)
                ..initialize(),
        ),
        ChangeNotifierProxyProvider<ItemRepository, ItemsProvider>(
          create: (context) =>
              ItemsProvider(repository: context.read<ItemRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? ItemsProvider(repository: repository)
                ..initialize(),
        ),
        ChangeNotifierProxyProvider<ChallanRepository, ChallanProvider>(
          create: (context) =>
              ChallanProvider(repository: context.read<ChallanRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? ChallanProvider(repository: repository)
                ..initialize(),
        ),
      ],
      child: MaterialApp(
        title: 'Challan Book',
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          textTheme: base.textTheme.apply(
            bodyColor: SoftErpTheme.textPrimary,
            displayColor: SoftErpTheme.textPrimary,
          ),
        ),
        home: const _AuthGate(),
      ),
    );
  }

  AuthenticatedHttpClient _authClient(AuthProvider auth) {
    return AuthenticatedHttpClient(tokenResolver: () => auth.token);
  }

  InventoryRepository _buildInventoryRepository(AuthProvider auth) {
    return ApiInventoryRepository(
      client: _authClient(auth),
      baseUrl: _apiBaseUrl,
      useMockResponses: _effectiveDemoMode,
    );
  }

  UnitRepository _buildUnitRepository(AuthProvider auth) {
    return ApiUnitRepository(
      client: _authClient(auth),
      baseUrl: _apiBaseUrl,
      useMockResponses: _effectiveDemoMode,
    );
  }

  GroupRepository _buildGroupRepository(AuthProvider auth) {
    return ApiGroupRepository(
      client: _authClient(auth),
      baseUrl: _apiBaseUrl,
      useMockResponses: _effectiveDemoMode,
    );
  }

  ClientRepository _buildClientRepository(AuthProvider auth) {
    return ApiClientRepository(
      client: _authClient(auth),
      baseUrl: _apiBaseUrl,
      useMockResponses: _effectiveDemoMode,
    );
  }

  VendorRepository _buildVendorRepository(AuthProvider auth) {
    return ApiVendorRepository(
      client: _authClient(auth),
      baseUrl: _apiBaseUrl,
      useMockResponses: _effectiveDemoMode,
    );
  }

  ItemRepository _buildItemRepository(AuthProvider auth) {
    return ApiItemRepository(
      client: _authClient(auth),
      baseUrl: _apiBaseUrl,
      useMockResponses: _effectiveDemoMode,
    );
  }

  OrderRepository _buildOrderRepository(AuthProvider auth) {
    return ApiOrderRepository(
      client: _authClient(auth),
      baseUrl: _apiBaseUrl,
      useMockResponses: _effectiveDemoMode,
    );
  }

  ChallanRepository _buildDeliveryChallanRepository(AuthProvider auth) {
    return ApiChallanRepository(
      client: _authClient(auth),
      baseUrl: _apiBaseUrl,
      useMockResponses: _effectiveDemoMode,
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
    if (_lastRefreshToken == token) {
      return;
    }
    _lastRefreshToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Future.wait<void>([
        context.read<OrdersProvider>().refresh(),
        context.read<InventoryProvider>().refresh(),
        context.read<UnitsProvider>().refresh(),
        context.read<GroupsProvider>().refresh(),
        context.read<ClientsProvider>().refresh(),
        context.read<VendorsProvider>().refresh(),
        context.read<ItemsProvider>().refresh(),
        context.read<DeliveryChallanProvider>().refresh(),
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
    return authenticated ? const AppShell() : const LoginScreen();
  }
}
