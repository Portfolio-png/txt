import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class SessionReplayService {
  SessionReplayService._() {
    _sessionId = const Uuid().v4();
    _sessionStart = DateTime.now();
  }

  static final SessionReplayService instance = SessionReplayService._();

  late final String _sessionId;
  late final DateTime _sessionStart;
  final List<Map<String, dynamic>> _events = [];
  Timer? _syncTimer;
  String? _baseUrl;
  String? _clientId;
  bool _isSyncing = false;

  void initialize(String baseUrl, String clientId) {
    _baseUrl = baseUrl;
    _clientId = clientId;

    // Start sync timer every 120 seconds to prevent background HTTP churn
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 120), (_) => syncReplays());
  }

  int get _elapsedMs => DateTime.now().difference(_sessionStart).inMilliseconds;

  void recordTap(double x, double y, double width, double height) {
    _events.add({
      't': _elapsedMs,
      'type': 'tap',
      'x': x,
      'y': y,
      'w': width,
      'h': height,
    });
  }

  void recordNavigation(String screenName) {
    _events.add({
      't': _elapsedMs,
      'type': 'nav',
      'name': screenName,
    });
  }

  Future<void> syncReplays() async {
    if (_isSyncing || _baseUrl == null || _clientId == null || _events.isEmpty) return;

    _isSyncing = true;
    final batch = List<Map<String, dynamic>>.from(_events);
    try {
      final payload = {
        'sessionId': _sessionId,
        'startedAt': _sessionStart.toIso8601String(),
        'events': batch,
      };

      final jsonStr = jsonEncode(payload);
      final gzippedBytes = gzip.encode(utf8.encode(jsonStr));
      final base64Payload = base64Encode(gzippedBytes);

      final url = Uri.parse('$_baseUrl/api/session-replay/$_clientId');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': base64Payload}),
      );

      if (response.statusCode == 200) {
        // Clear events that were successfully synchronized
        _events.removeRange(0, batch.length);
        debugPrint('[SessionReplayService] Synced ${batch.length} replay events.');
      } else {
        debugPrint('[SessionReplayService] Failed to sync replays: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[SessionReplayService] Error syncing replays: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }
}

class ReplayNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final name = route.settings.name;
    if (name != null) {
      SessionReplayService.instance.recordNavigation(name);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final name = previousRoute?.settings.name;
    if (name != null) {
      SessionReplayService.instance.recordNavigation(name);
    }
  }
}
