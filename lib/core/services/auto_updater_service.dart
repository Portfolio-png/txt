import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:auto_updater/auto_updater.dart';
import 'package:core_erp/core/services/config_service.dart';

class AutoUpdaterService {
  AutoUpdaterService._();

  static final AutoUpdaterService instance = AutoUpdaterService._();

  Future<void> initialize() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS)) {
      return;
    }

    try {
      final config = ConfigService.instance.config;
      final updateConfig = config['update'] as Map<String, dynamic>?;
      
      // Default fallback feed URL if remote config doesn't specify one
      String feedURL = String.fromEnvironment(
        'PAPER_APPCAST_URL',
        defaultValue: 'https://update.example.com/appcast.xml',
      );

      if (updateConfig != null && updateConfig.containsKey('appcast_url')) {
        feedURL = updateConfig['appcast_url'];
      }

      await autoUpdater.setFeedURL(feedURL);
      await autoUpdater.checkForUpdates(inBackground: true);
      await autoUpdater.setScheduledCheckInterval(3600); // Check every hour
    } catch (e) {
      debugPrint('AutoUpdaterService initialization failed: $e');
    }
  }
}
