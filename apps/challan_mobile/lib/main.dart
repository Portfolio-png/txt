import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
import 'package:core_erp/features/items/data/repositories/favorites_repository.dart';
import 'package:core_erp/features/items/presentation/providers/favorites_provider.dart';
import 'package:core_erp/features/orders/data/repositories/api_order_repository.dart';
import 'package:core_erp/features/orders/data/repositories/order_repository.dart';
import 'package:core_erp/features/orders/presentation/providers/orders_provider.dart';
import 'package:core_erp/features/units/data/repositories/api_unit_repository.dart';
import 'package:core_erp/features/units/data/repositories/unit_repository.dart';
import 'package:core_erp/features/units/presentation/providers/units_provider.dart';
import 'package:core_erp/features/vendors/data/repositories/api_vendor_repository.dart';
import 'package:core_erp/features/vendors/data/repositories/vendor_repository.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendors_provider.dart';
import 'package:core_erp/features/vendors/data/repositories/vendor_history_repository.dart';
import 'package:core_erp/features/vendors/presentation/providers/vendor_history_provider.dart';
import 'package:core_erp/features/search/data/repositories/api_search_repository.dart';
import 'package:core_erp/features/search/data/repositories/search_repository.dart';
import 'package:core_erp/features/search/presentation/providers/search_provider.dart';

import 'package:core_erp/core/network/conditional_cache_client.dart';
import 'package:core_erp/core/database/local_database_helper.dart';
import 'package:core_erp/core/sync/outbox_session.dart';
import 'package:core_erp/core/sync/replica_session.dart';
import 'package:core_erp/features/clients/data/repositories/local_first_client_repository.dart';
import 'package:core_erp/features/delivery_challans/data/local_first_challan_repository.dart';
import 'package:core_erp/features/groups/data/repositories/local_first_group_repository.dart';
import 'package:core_erp/features/inventory/data/repositories/local_first_inventory_repository.dart';
import 'package:core_erp/features/items/data/repositories/local_first_item_repository.dart';
import 'package:core_erp/features/orders/data/repositories/local_first_order_repository.dart';
import 'package:core_erp/features/units/data/repositories/local_first_unit_repository.dart';
import 'package:core_erp/features/vendors/data/repositories/local_first_vendor_repository.dart';

import 'package:core_erp/core/services/config_service.dart';
import 'package:core_erp/core/services/socket_service.dart' as core_socket;
import 'package:core_erp/core/services/generic_asset_service.dart';
import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/core/services/photo_requests.dart';

import 'photos/photo_queue_gate.dart';
import 'package:core_erp/core/sync/sync_health.dart';
import 'package:core_erp/core/sync/workspace_namespace.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'widgets/offline_banner.dart';
import 'widgets/phone_settings_sheet.dart';
import 'screens/home_screen.dart';
import 'package:challan_mobile/screens/passcode_screen.dart';
import 'services/network_discovery_service.dart';
import 'services/offline_unlock.dart';
import 'services/socket_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Seed feature flags with the global defaults so release builds read real
  // values instead of the empty-config `false` fallback. Without this the app
  // never populates FeatureFlags._config (it has no per-client config source),
  // so every flag — e.g. purchase.flowV2 — stays off outside debug.
  ConfigService.instance.loadDefaults();
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
  static const _configuredApiUrl = String.fromEnvironment('PAPER_API_BASE_URL');
  // Cloud/production server the app points at with one tap. manualConnect wraps
  // a bare IP as http://<ip>:18080.
  static const _onlineServerIp = '16.170.236.173';

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_configuredApiUrl.isNotEmpty) {
      return MyApp(apiUrl: _configuredApiUrl);
    }

    final discovery = context.watch<NetworkDiscoveryService>();
    
    if (discovery.discoveredUrl == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1),
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A),
                  Color(0xFF1E1B4B),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFF334155).withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF312E81),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.settings_input_component,
                            size: 40,
                            color: Color(0xFF818CF8),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Setup Connection',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Connect your mobile app to the factory server',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 32),

                        if (discovery.isSearching) ...[
                          const SizedBox(
                            height: 60,
                            width: 60,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Scanning factory Wi-Fi...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Looking for active Desktop server via mDNS',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ] else ...[
                          if (discovery.hasTimedOut) ...[
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.wifi_off, size: 20, color: Color(0xFFEF4444)),
                                SizedBox(width: 8),
                                Text(
                                  'Local discovery timed out',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFF59E0B)),
                                SizedBox(width: 8),
                                Text(
                                  'Discovery failed to start',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          // One-tap connect to the cloud/production server.
                          _ConnectionOptionCard(
                            icon: Icons.cloud_done_rounded,
                            title: 'Online Server',
                            subtitle: 'Connect to the cloud server ($_onlineServerIp)',
                            onTap: () => discovery.manualConnect(_onlineServerIp),
                          ),
                          const SizedBox(height: 20),
                          const Row(
                            children: [
                              Expanded(child: Divider(color: Color(0xFF334155))),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'or connect manually',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ),
                              Expanded(child: Divider(color: Color(0xFF334155))),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'For local testing',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _ipController,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                            decoration: InputDecoration(
                              labelText: 'IP Address or AWS URL',
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                              hintText: 'e.g. 192.168.1.100 or https://api...',
                              hintStyle: const TextStyle(color: Color(0xFF475569)),
                              prefixIcon: const Icon(Icons.link, color: Color(0xFF818CF8)),
                              filled: true,
                              fillColor: const Color(0xFF0F172A).withValues(alpha: 0.5),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFF334155)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            ),
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () {
                                if (_ipController.text.trim().isNotEmpty) {
                                  discovery.manualConnect(_ipController.text.trim());
                                }
                              },
                              child: const Text(
                                'Connect Manually',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Divider(color: Color(0xFF334155)),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF94A3B8),
                                ),
                                icon: const Icon(Icons.usb, size: 18),
                                label: const Text('Use USB (localhost)'),
                                onPressed: () => discovery.manualConnect('localhost'),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF818CF8),
                                ),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Retry Scan'),
                                onPressed: () => discovery.discoverServer(),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MyApp(
      apiUrl: discovery.discoveredUrl!,
      onChangeServer: () => discovery.forget(),
    );
  }
}

/// Tappable connection preset card (e.g. the online/cloud server).
class _ConnectionOptionCard extends StatelessWidget {
  const _ConnectionOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF312E81),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: const Color(0xFF818CF8)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF818CF8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  final String apiUrl;

  /// The connection every repository goes through. A test hands in a fake
  /// to count what the app asks for.
  final http.Client? httpClient;

  /// Signed in without a server, for tests and the demo build.
  final bool demoMode;

  /// Where the response cache keeps its copies. Null is the app-support
  /// directory; a test names a fresh one.
  final Directory? cacheDirectory;

  /// The offline unlock (B45). Null builds the app's own, on secure storage;
  /// a test hands in one on a map.
  final OfflineUnlock? offlineUnlock;

  /// Forgets the server and goes back to its setup screen.
  final VoidCallback? onChangeServer;

  const MyApp({
    super.key,
    required this.apiUrl,
    this.httpClient,
    this.demoMode = _isDemoModeBuild,
    this.cacheDirectory,
    this.offlineUnlock,
    this.onChangeServer,
  });

  static const _isDemoModeBuild = bool.fromEnvironment('PAPER_DEMO_MODE', defaultValue: false);

  /// One response cache per connection, shared by every repository, so a
  /// validator learned by one screen is reused by the next and a relaunch
  /// replays unchanged lists from disk after a 304. The desktop has had this
  /// since the wire work began; the phone, on the worse link, had none.
  static final Expando<ConditionalCacheClient> _caches = Expando<ConditionalCacheClient>();
  static final http.Client _network = http.Client();

  static ConditionalCacheClient cacheFor(http.Client? inner, {Directory? directory}) {
    final key = inner ?? _network;
    return _caches[key] ??= ConditionalCacheClient(inner: key, storageDirectory: directory);
  }

  AuthenticatedHttpClient _authClient(AuthProvider auth) {
    return AuthenticatedHttpClient(
      tokenResolver: () => auth.token,
      inner: cacheFor(httpClient, directory: cacheDirectory),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) {
            final provider = AuthProvider(
              baseUrl: apiUrl,
              demoMode: demoMode,
            )..initialize();
            
            // if (!demoMode) {
            //   // Auto-login for mobile dev if not in demo mode
            //   provider.login(
            //     email: 'super@paper.local',
            //     password: 'Paper@12345',
            //   );
            // }
            return provider;
          },
        ),
        Provider<InventoryRepository>(
          create: (context) {
            final remote = ApiInventoryRepository(
              client: _authClient(context.read<AuthProvider>()),
              baseUrl: apiUrl,
              useMockResponses: false,
            );
            if (demoMode) return remote;
            return LocalFirstInventoryRepository(
              remote: remote,
              replica: () async => LocalDatabaseHelper.instance.database,
              isHydrated: () => ReplicaSession.instance.isHydrated,
            );
          },
        ),
        Provider<UnitRepository>(
          create: (context) {
            final remote = ApiUnitRepository(
              client: _authClient(context.read<AuthProvider>()),
              baseUrl: apiUrl,
              useMockResponses: false,
            );
            if (demoMode) return remote;
            return LocalFirstUnitRepository(
              remote: remote,
              replica: () async => LocalDatabaseHelper.instance.database,
              isHydrated: () => ReplicaSession.instance.isHydrated,
            );
          },
        ),
        Provider<GroupRepository>(
          create: (context) {
            final remote = ApiGroupRepository(
              client: _authClient(context.read<AuthProvider>()),
              baseUrl: apiUrl,
              useMockResponses: false,
            );
            if (demoMode) return remote;
            return LocalFirstGroupRepository(
              remote: remote,
              replica: () async => LocalDatabaseHelper.instance.database,
              isHydrated: () => ReplicaSession.instance.isHydrated,
            );
          },
        ),
        Provider<ClientRepository>(
          create: (context) {
            final remote = ApiClientRepository(
              client: _authClient(context.read<AuthProvider>()),
              baseUrl: apiUrl,
              useMockResponses: false,
            );
            if (demoMode) return remote;
            return LocalFirstClientRepository(
              remote: remote,
              replica: () async => LocalDatabaseHelper.instance.database,
              isHydrated: () => ReplicaSession.instance.isHydrated,
            );
          },
        ),
        Provider<VendorRepository>(
          create: (context) {
            final remote = ApiVendorRepository(
              client: _authClient(context.read<AuthProvider>()),
              baseUrl: apiUrl,
              useMockResponses: false,
            );
            if (demoMode) return remote;
            return LocalFirstVendorRepository(
              remote: remote,
              replica: () async => LocalDatabaseHelper.instance.database,
              isHydrated: () => ReplicaSession.instance.isHydrated,
              fromJson: remote.vendorFromJson,
            );
          },
        ),
        Provider<VendorHistoryRepository>(
          create: (context) => VendorHistoryRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
          ),
        ),
        Provider<ItemRepository>(
          create: (context) {
            final remote = ApiItemRepository(
              client: _authClient(context.read<AuthProvider>()),
              baseUrl: apiUrl,
              useMockResponses: false,
            );
            if (demoMode) return remote;
            return LocalFirstItemRepository(
              remote: remote,
              replica: () async => LocalDatabaseHelper.instance.database,
              isHydrated: () => ReplicaSession.instance.isHydrated,
            );
          },
        ),
        Provider<FavoritesRepository>(
          create: (context) => FavoritesRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
          ),
        ),
        Provider<OrderRepository>(
          create: (context) {
            final remote = ApiOrderRepository(
              client: _authClient(context.read<AuthProvider>()),
              baseUrl: apiUrl,
              useMockResponses: false,
            );
            if (demoMode) return remote;
            return LocalFirstOrderRepository(
              remote: remote,
              replica: () async => LocalDatabaseHelper.instance.database,
              isHydrated: () => ReplicaSession.instance.isHydrated,
            );
          },
        ),
        Provider<ChallanRepository>(
          create: (context) {
            final remote = ApiChallanRepository(
              client: _authClient(context.read<AuthProvider>()),
              baseUrl: apiUrl,
              useMockResponses: false,
            );
            if (demoMode) return remote;
            return LocalFirstChallanRepository(
              remote: remote,
              replica: () async => LocalDatabaseHelper.instance.database,
              isHydrated: () => ReplicaSession.instance.isHydrated,
              // Challans made without a connection are kept and sent later.
              outbox: () => OutboxSession.instance.engine,
              // Offline, the Challan Book reads this user's challans from the copy (B53).
              currentUserId: () => context.read<AuthProvider>().user?.id,
            );
          },
        ),
        // What the Sync Health screen reads (core_erp features/sync_health).
        // After AuthProvider: a provider can read only those listed above it.
        // Listed first, the tap threw and the button did nothing.
        // Its inputs:
        // the server's status through the signed-in client, the replica's
        // cursor and last sync, and the outbox.
        Provider<SyncHealthProbe>(
          create: (context) => SyncHealthProbe(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            appVersion: () async {
              final info = await PackageInfo.fromPlatform();
              return '${info.version}+${info.buildNumber}';
            },
            localCursor: ReplicaSession.instance.cursor,
            lastSyncedAt: () => ReplicaSession.instance.lastSyncedAt.value,
            outbox: () => OutboxSession.instance.engine,
          ),
        ),
        Provider<SearchRepository>(
          create: (context) => ApiSearchRepository(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
          ),
        ),
        // Challan attachment uploads (Purchase wizard photo step, editor camera).
        // Real presigned-S3 flow via POST /api/upload/generic; requires the
        // backend to have S3 configured (PAPER_S3_BUCKET_NAME).
        Provider<GenericAssetService>(
          create: (context) => GenericAssetService(
            client: _authClient(context.read<AuthProvider>()),
            baseUrl: apiUrl,
            useMockResponses: false,
          ),
        ),
        // Photos the desktop sends here to take: the queue, and the store each
        // one uploads to (the same per-record asset routes the desktop uses).
        Provider<EntityPhotoRepository>(
          create: (context) => EntityPhotoRepository(
            baseUrl: apiUrl,
            client: _authClient(context.read<AuthProvider>()),
          ),
        ),
        ChangeNotifierProvider<PhotoRequestsProvider>(
          create: (context) => PhotoRequestsProvider(
            repository: PhotoRequestRepository(
              baseUrl: apiUrl,
              client: _authClient(context.read<AuthProvider>()),
            ),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ChallanEditorCommandProvider()),
        ChangeNotifierProxyProvider<AuthProvider, SocketService>(
          create: (context) {
            final auth = context.read<AuthProvider>();
            final localSocket = SocketService()
              ..initAuth(auth)
              ..connect(apiUrl);
            core_socket.SocketService.instance.init(apiUrl, token: auth.token);
            return localSocket;
          },
          update: (context, auth, previous) {
            final localSocket = previous ?? SocketService()..connect(apiUrl);
            localSocket.initAuth(auth);
            core_socket.SocketService.instance.init(apiUrl, token: auth.token);
            return localSocket;
          },
        ),
        ChangeNotifierProxyProvider2<AuthProvider, OrderRepository, OrdersProvider>(
          create: (context) => OrdersProvider(repository: context.read<OrderRepository>()),
          // No refresh here, nor in the providers below: `update` runs on every
          // auth or repository change, and _AuthGate already refreshes every
          // provider once per sign-in. With both, each list was fetched twice
          // at start-up.
          update: (context, auth, repository, previous) =>
              previous ?? OrdersProvider(repository: repository),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, InventoryRepository, InventoryProvider>(
          create: (context) => InventoryProvider(repository: context.read<InventoryRepository>()),
          update: (context, auth, repository, previous) =>
              previous ?? InventoryProvider(repository: repository),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, UnitRepository, UnitsProvider>(
          create: (context) => UnitsProvider(repository: context.read<UnitRepository>()),
          update: (context, auth, repository, previous) =>
              previous ?? UnitsProvider(repository: repository),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, GroupRepository, GroupsProvider>(
          create: (context) => GroupsProvider(repository: context.read<GroupRepository>()),
          update: (context, auth, repository, previous) =>
              previous ?? GroupsProvider(repository: repository),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, ClientRepository, ClientsProvider>(
          create: (context) => ClientsProvider(repository: context.read<ClientRepository>()),
          update: (context, auth, repository, previous) =>
              previous ?? ClientsProvider(repository: repository),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, VendorRepository, VendorsProvider>(
          create: (context) => VendorsProvider(repository: context.read<VendorRepository>()),
          update: (context, auth, repository, previous) =>
              previous ?? VendorsProvider(repository: repository),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, VendorHistoryRepository, VendorHistoryProvider>(
          create: (context) => VendorHistoryProvider(repository: context.read<VendorHistoryRepository>()),
          update: (context, auth, repository, previous) => previous ?? VendorHistoryProvider(repository: repository),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, ItemRepository, ItemsProvider>(
          // Follows the replica: an item changed anywhere is re-read once the
          // phone's copy holds the change (B50).
          create: (context) => ItemsProvider(
            repository: context.read<ItemRepository>(),
            replicaChanges: ReplicaSession.instance.changedTables,
          ),
          update: (context, auth, repository, previous) =>
              previous ?? ItemsProvider(repository: repository, replicaChanges: ReplicaSession.instance.changedTables),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, FavoritesRepository, FavoritesProvider>(
          create: (context) => FavoritesProvider(repository: context.read<FavoritesRepository>()),
          update: (context, auth, repository, previous) =>
              previous ?? FavoritesProvider(repository: repository),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, ChallanRepository, DeliveryChallanProvider>(
          create: (context) => DeliveryChallanProvider(repository: context.read<ChallanRepository>()),
          update: (context, auth, repository, previous) =>
              previous ?? DeliveryChallanProvider(repository: repository),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, SearchRepository, SearchProvider>(
          create: (context) => SearchProvider(repository: context.read<SearchRepository>()),
          update: (context, auth, repository, previous) => previous ?? SearchProvider(repository: repository),
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
        home: _AuthGate(
          cache: cacheFor(httpClient, directory: cacheDirectory),
          apiUrl: apiUrl,
          demoMode: demoMode,
          offlineUnlock: demoMode ? null : (offlineUnlock ?? OfflineUnlock(serverUrl: apiUrl)),
          onChangeServer: onChangeServer,
        ),
      ),
    );
  }
}

/// The server tables the phone keeps a copy of: what its screens read. The
/// desktop's machines, dies, departments and pipelines are not here, and a
/// change to one of them is not fetched.
const Set<String> kPhoneReplicaTables = <String>{
  'items',
  'order_items',
  'delivery_challans',
  'materials',
  'clients',
  'vendors',
  'units',
  'groups',
};

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.cache,
    required this.apiUrl,
    required this.demoMode,
    this.offlineUnlock,
    this.onChangeServer,
  });

  /// Opens the phone without the server for its last signed-in user (B45).
  final OfflineUnlock? offlineUnlock;

  /// Back to the server setup screen.
  final VoidCallback? onChangeServer;

  /// Pointed at the signed-in user's own copies before anything is fetched.
  final ConditionalCacheClient cache;
  final String apiUrl;
  final bool demoMode;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _lastRefreshToken;
  StreamSubscription<void>? _outboxChanges;

  @override
  void dispose() {
    _outboxChanges?.cancel();
    super.dispose();
  }

  void _refreshAfterAuthentication(String token) {
    if (_lastRefreshToken == token) return;
    _lastRefreshToken = token;
    // Namespaced, not cleared: a launch begins with a sign-in, and clearing
    // here would empty the cache at the one moment it is worth having.
    final auth = context.read<AuthProvider>();
    final identity = auth.user;
    // This server's and this user's: after Change server the same user id
    // opened the old server's copy, and its unsent writes (B64).
    final namespace = workspaceNamespace(
      baseUrl: widget.apiUrl,
      user: '${identity?.id ?? identity?.email ?? 'anonymous'}',
    );
    widget.cache.namespace = namespace;
    // The phone's own copy of what its screens read, kept current from the
    // change stream; screens read it, and the network when it is behind or
    // not there yet. Opened before the providers load so a warm copy answers
    // their first read.
    if (!widget.demoMode) {
      // Writes made without the server, kept until it is back (its own file,
      // beside the replica: a resync must never touch unsent work).
      unawaited(OutboxSession.instance.start(
        client: AuthenticatedHttpClient(tokenResolver: () => auth.token, inner: widget.cache),
        baseUrl: widget.apiUrl,
        namespace: namespace,
      ));
      _outboxChanges ??= OutboxSession.instance.changes.listen((_) {
        if (mounted) context.read<DeliveryChallanProvider>().refresh();
      });
    }
    final replica = widget.demoMode
        ? Future<void>.value()
        : ReplicaSession.instance.start(
            client: AuthenticatedHttpClient(tokenResolver: () => auth.token, inner: widget.cache),
            baseUrl: widget.apiUrl,
            namespace: namespace,
            tables: kPhoneReplicaTables,
            // Signed in offline: the server is known to be away, so the copy
            // answers at once; it catches up when the change stream is back.
            catchUp: !auth.isOffline,
          );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The first load waits for the copy to catch up — a few seconds at most.
      // Started together, the screens read the network while the catch-up
      // ran (the copy does not count as current mid-replay), and offline those
      // reads failed with the copy right there and nothing re-reading it.
      // Waited for, an online launch reads the fresh copy and an offline one
      // reads the copy as it was, after a catch-up that failed at once.
      await replica.timeout(const Duration(seconds: 3), onTimeout: () {});
      if (!mounted) return;
      await Future.wait<void>([
        context.read<OrdersProvider>().refresh(),
        context.read<InventoryProvider>().refresh(),
        context.read<UnitsProvider>().refresh(),
        context.read<GroupsProvider>().refresh(),
        context.read<ClientsProvider>().refresh(),
        context.read<VendorsProvider>().refresh(),
        context.read<ItemsProvider>().refresh(),
        context.read<FavoritesProvider>().refresh(),
        context.read<DeliveryChallanProvider>().refresh(),
      ]);
    });
  }

  /// An explicit sign-out also forgets the offline unlock: otherwise the PIN
  /// would still open this phone onto its copy without the server.
  Future<void> _signOut() => signOutPhone(context.read<AuthProvider>(), widget.offlineUnlock);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final authenticated = auth.isAuthenticated;
    // Keyed on the token, or on the user when there is none (the demo build
    // signs in without one). Before this the demo build never reached the
    // start-up refresh and relied on each provider's `update` to load.
    final token = auth.token;
    final sessionKey = (token != null && token.isNotEmpty)
        ? token
        : auth.user != null
            ? 'user:${auth.user!.id}'
            : null;
    if (authenticated && sessionKey != null) {
      _refreshAfterAuthentication(sessionKey);
    }
    
    // No separate error page any more (B44). A failed sign-in used to swap
    // the passcode screen for a bare "Auth Error" with no way back, and only
    // killing the app recovered; the passcode screen now shows the reason
    // itself, beside the keypad, with Try again.

    // Signed in, the camera opens by itself for a photo the desktop sends.
    // The gear's sheet signs out through _signOut (B55).
    return authenticated
        ? OfflineBanner(
            child: PhotoQueueGate(
              child: HomeScreen(
                session: PhoneSession(
                  serverUrl: widget.apiUrl,
                  signOut: _signOut,
                  changeServer: widget.onChangeServer == null
                      ? null
                      : () async {
                          await _signOut();
                          widget.onChangeServer!();
                        },
                ),
              ),
            ),
          )
        : PasscodeScreen(
            offlineUnlock: widget.offlineUnlock,
            onChangeServer: widget.onChangeServer,
          );
  }
}
