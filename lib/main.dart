import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'core/theme/soft_erp_theme.dart';
import 'core/network/authenticated_http_client.dart';
import 'app/shell/app_shell.dart';
import 'app/shell/navigation_provider.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/groups/data/repositories/api_group_repository.dart';
import 'features/groups/data/repositories/group_repository.dart';
import 'features/groups/presentation/providers/groups_provider.dart';
import 'features/inventory/data/repositories/api_inventory_repository.dart';
import 'features/inventory/data/repositories/inventory_repository.dart';
import 'features/inventory/presentation/providers/inventory_provider.dart';
import 'features/clients/data/repositories/api_client_repository.dart';
import 'features/clients/data/repositories/client_repository.dart';
import 'features/clients/presentation/providers/clients_provider.dart';
import 'features/delivery_challans/data/api_delivery_challan_repository.dart';
import 'features/delivery_challans/data/delivery_challan_repository.dart';
import 'features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'features/items/data/repositories/api_item_repository.dart';
import 'features/items/data/repositories/item_repository.dart';
import 'features/items/presentation/providers/items_provider.dart';
import 'features/orders/data/repositories/api_order_repository.dart';
import 'features/orders/data/repositories/order_repository.dart';
import 'features/orders/presentation/providers/orders_provider.dart';
import 'features/production_pipelines/data/repositories/mock_pipeline_run_repository.dart';
import 'features/production_pipelines/data/repositories/pipeline_run_repository.dart';
import 'features/units/data/repositories/api_unit_repository.dart';
import 'features/units/data/repositories/unit_repository.dart';
import 'features/units/presentation/providers/units_provider.dart';

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
    this.inventoryRepository,
    this.groupRepository,
    this.unitRepository,
    this.clientRepository,
    this.deliveryChallanRepository,
    this.itemRepository,
    this.orderRepository,
    this.pipelineRunRepository,
    this.demoModeOverride,
  });

  final InventoryRepository? inventoryRepository;
  final GroupRepository? groupRepository;
  final UnitRepository? unitRepository;
  final ClientRepository? clientRepository;
  final DeliveryChallanRepository? deliveryChallanRepository;
  final ItemRepository? itemRepository;
  final OrderRepository? orderRepository;
  final PipelineRunRepository? pipelineRunRepository;
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
    );

    return MultiProvider(
      providers: [
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
        Provider<DeliveryChallanRepository>(
          create: (context) =>
              deliveryChallanRepository ??
              _buildDeliveryChallanRepository(context.read<AuthProvider>()),
        ),
        Provider<PipelineRunRepository>(
          create: (context) =>
              pipelineRunRepository ??
              _buildPipelineRunRepository(context.read<AuthProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
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
        ChangeNotifierProxyProvider<ItemRepository, ItemsProvider>(
          create: (context) =>
              ItemsProvider(repository: context.read<ItemRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? ItemsProvider(repository: repository)
                ..initialize(),
        ),
        ChangeNotifierProxyProvider<
          DeliveryChallanRepository,
          DeliveryChallanProvider
        >(
          create: (context) => DeliveryChallanProvider(
            repository: context.read<DeliveryChallanRepository>(),
          )..initialize(),
          update: (context, repository, previous) =>
              previous ?? DeliveryChallanProvider(repository: repository)
                ..initialize(),
        ),
      ],
      child: MaterialApp(
        title: 'Paper',
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

  DeliveryChallanRepository _buildDeliveryChallanRepository(AuthProvider auth) {
    return ApiDeliveryChallanRepository(
      client: _authClient(auth),
      baseUrl: _apiBaseUrl,
      useMockResponses: _effectiveDemoMode,
    );
  }

  PipelineRunRepository _buildPipelineRunRepository(AuthProvider auth) {
    if (_effectiveDemoMode) {
      final injectedInventoryRepository = inventoryRepository;
      final resolvedInventoryRepository =
          injectedInventoryRepository ?? _buildInventoryRepository(auth);
      return MockPipelineRunRepository(
        inventoryRepository: resolvedInventoryRepository,
      );
    }
    return ApiPipelineRunRepository(
      baseUrl: _apiBaseUrl,
      client: _authClient(auth),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final authenticated = context.select<AuthProvider, bool>(
      (auth) => auth.isAuthenticated,
    );
    return authenticated ? const AppShell() : const LoginScreen();
  }
}
