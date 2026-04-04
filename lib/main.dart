import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'app/shell/app_shell.dart';
import 'app/shell/navigation_provider.dart';
import 'features/groups/data/repositories/api_group_repository.dart';
import 'features/groups/data/repositories/group_repository.dart';
import 'features/groups/presentation/providers/groups_provider.dart';
import 'features/inventory/data/repositories/api_inventory_repository.dart';
import 'features/inventory/data/repositories/inventory_repository.dart';
import 'features/inventory/presentation/providers/inventory_provider.dart';
import 'features/clients/data/repositories/api_client_repository.dart';
import 'features/clients/data/repositories/client_repository.dart';
import 'features/clients/presentation/providers/clients_provider.dart';
import 'features/items/data/repositories/api_item_repository.dart';
import 'features/items/data/repositories/item_repository.dart';
import 'features/items/presentation/providers/items_provider.dart';
import 'features/orders/data/repositories/api_order_repository.dart';
import 'features/orders/data/repositories/order_repository.dart';
import 'features/orders/presentation/providers/orders_provider.dart';
import 'features/production_pipelines/data/repositories/pipeline_run_repository.dart';
import 'features/units/data/repositories/api_unit_repository.dart';
import 'features/units/data/repositories/unit_repository.dart';
import 'features/units/presentation/providers/units_provider.dart';

const _defaultApiBaseUrl = kDebugMode
    ? 'http://localhost:18080'
    : 'https://paper-backend.fly.dev';
const _apiBaseUrl = String.fromEnvironment(
  'PAPER_API_BASE_URL',
  defaultValue: _defaultApiBaseUrl,
);

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
    this.itemRepository,
    this.orderRepository,
  });

  final InventoryRepository? inventoryRepository;
  final GroupRepository? groupRepository;
  final UnitRepository? unitRepository;
  final ClientRepository? clientRepository;
  final ItemRepository? itemRepository;
  final OrderRepository? orderRepository;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
      scaffoldBackgroundColor: const Color(0xFFF1F1F1),
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
        Provider<InventoryRepository>(
          create: (_) => inventoryRepository ?? _buildInventoryRepository(),
        ),
        Provider<UnitRepository>(
          create: (_) => unitRepository ?? _buildUnitRepository(),
        ),
        Provider<GroupRepository>(
          create: (_) => groupRepository ?? _buildGroupRepository(),
        ),
        Provider<ClientRepository>(
          create: (_) => clientRepository ?? _buildClientRepository(),
        ),
        Provider<ItemRepository>(
          create: (_) => itemRepository ?? _buildItemRepository(),
        ),
        Provider<OrderRepository>(
          create: (_) => orderRepository ?? _buildOrderRepository(),
        ),
        Provider<PipelineRunRepository>(
          create: (_) => _buildPipelineRunRepository(),
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
      ],
      child: MaterialApp(
        title: 'Paper',
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          textTheme: base.textTheme.apply(
            bodyColor: const Color(0xFF3C3C3C),
            displayColor: const Color(0xFF3C3C3C),
          ),
        ),
        home: const AppShell(),
      ),
    );
  }

  InventoryRepository _buildInventoryRepository() {
    return ApiInventoryRepository(
      baseUrl: _apiBaseUrl,
      useMockResponses: false,
    );
  }

  UnitRepository _buildUnitRepository() {
    return ApiUnitRepository(baseUrl: _apiBaseUrl, useMockResponses: false);
  }

  GroupRepository _buildGroupRepository() {
    return ApiGroupRepository(baseUrl: _apiBaseUrl, useMockResponses: false);
  }

  ClientRepository _buildClientRepository() {
    return ApiClientRepository(baseUrl: _apiBaseUrl, useMockResponses: false);
  }

  ItemRepository _buildItemRepository() {
    return ApiItemRepository(baseUrl: _apiBaseUrl, useMockResponses: false);
  }

  OrderRepository _buildOrderRepository() {
    return ApiOrderRepository(baseUrl: _apiBaseUrl, useMockResponses: false);
  }

  PipelineRunRepository _buildPipelineRunRepository() {
    return ApiPipelineRunRepository(baseUrl: _apiBaseUrl);
  }
}
