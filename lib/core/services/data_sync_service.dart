import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:paper/features/production/data/datasources/offline_database_helper.dart';

class DataSyncService {
  DataSyncService._();

  static final DataSyncService instance = DataSyncService._();

  Timer? _syncTimer;
  String? _baseUrl;
  String? _clientId;
  bool _isSyncing = false;

  void initialize(String baseUrl, String clientId) {
    _baseUrl = baseUrl;
    _clientId = clientId;

    // Cancel any existing timer to avoid multiple polling loops
    _syncTimer?.cancel();

    // Periodically sync every 30 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => syncState());
    
    // Trigger initial sync in background after a short delay
    Future.delayed(const Duration(seconds: 5), () => syncState());
  }

  Future<void> syncUser(String email, String role) async {
    if (_baseUrl == null || _clientId == null) return;
    try {
      final url = Uri.parse('$_baseUrl/api/sandbox-dashboard/client/$_clientId/users');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'role': role,
        }),
      );
    } catch (e) {
      debugPrint('Failed to sync user to dashboard: $e');
    }
  }

  Future<void> syncState() async {
    if (_isSyncing || _baseUrl == null || _clientId == null) return;
    
    _isSyncing = true;
    try {
      final db = await OfflineSyncDbHelper.instance.database;
      
      // Query all relevant offline tables
      final runs = await db.query('pipeline_runs');
      final templates = await db.query('pipeline_templates');
      final stageLogs = await db.query('offline_stage_logs');
      final factories = await db.query('factories');
      final shopFloors = await db.query('shop_floors');

      final payload = {
        'pipeline_runs': runs,
        'pipeline_templates': templates,
        'offline_stage_logs': stageLogs,
        'factories': factories,
        'shop_floors': shopFloors,
      };

      // JSON Encode -> GZIP Compress -> Base64 Encode
      final jsonStr = jsonEncode(payload);
      final gzippedBytes = gzip.encode(utf8.encode(jsonStr));
      final base64Payload = base64Encode(gzippedBytes);

      final url = Uri.parse('$_baseUrl/api/sandbox-sync/$_clientId');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': base64Payload}),
      );

      if (response.statusCode == 200) {
        debugPrint('[DataSyncService] Successfully synchronized SQLite state to backend.');
      } else {
        debugPrint('[DataSyncService] Failed to sync: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[DataSyncService] Error during SQLite state sync: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }
}
