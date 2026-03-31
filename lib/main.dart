import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/shell/app_shell.dart';
import 'app/shell/navigation_provider.dart';
import 'features/inventory/data/repositories/api_inventory_repository.dart';
import 'features/inventory/data/repositories/inventory_repository.dart';
import 'features/inventory/presentation/providers/inventory_provider.dart';
import 'features/production_pipelines/data/repositories/pipeline_run_repository.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.inventoryRepository});

  final InventoryRepository? inventoryRepository;

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
        Provider<PipelineRunRepository>(
          create: (_) => _buildPipelineRunRepository(),
        ),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProxyProvider<InventoryRepository, InventoryProvider>(
          create: (context) =>
              InventoryProvider(repository: context.read<InventoryRepository>())
                ..initialize(),
          update: (context, repository, previous) =>
              previous ?? InventoryProvider(repository: repository)
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
    const baseUrl = String.fromEnvironment(
      'PAPER_API_BASE_URL',
      defaultValue: 'https://paper-backend.fly.dev',
    );
    return ApiInventoryRepository(baseUrl: baseUrl, useMockResponses: false);
  }

  PipelineRunRepository _buildPipelineRunRepository() {
    const baseUrl = String.fromEnvironment(
      'PAPER_API_BASE_URL',
      defaultValue: 'https://paper-backend.fly.dev',
    );
    return ApiPipelineRunRepository(baseUrl: baseUrl);
  }
}
