import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:core_erp/core/services/config_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';

class AutoUpdaterService {
  AutoUpdaterService._();

  static final AutoUpdaterService instance = AutoUpdaterService._();
  bool _isUpdating = false;

  Future<void> initialize() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS)) return;

    // Check periodically
    Future.delayed(const Duration(seconds: 10), _checkForUpdates);
  }

  Future<void> _checkForUpdates() async {
    if (_isUpdating) return;
    
    try {
      final config = ConfigService.instance.config;
      final updateConfig = config['update'] as Map<String, dynamic>?;
      if (updateConfig == null) return;

      final targetVersion = updateConfig['latest_version'] as String?;
      final downloadUrl = updateConfig['appcast_url'] as String?; // Reusing this field for the binary URL

      if (targetVersion == null || downloadUrl == null || downloadUrl.isEmpty) return;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Basic version check
      if (_isNewerVersion(currentVersion, targetVersion)) {
        await _performSilentUpdate(downloadUrl);
      }
    } catch (e) {
      debugPrint('Silent auto-update failed: $e');
    }
  }

  bool _isNewerVersion(String current, String target) {
    // Simple naive check
    return current != target; 
  }

  Future<void> _performSilentUpdate(String url) async {
    if (_isUpdating || !Platform.isWindows) return;
    _isUpdating = true;

    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final exeName = path.basename(exePath);
      
      final tempDir = await getTemporaryDirectory();
      final downloadPath = path.join(tempDir.path, 'update_$exeName');

      // 1. Download new binary
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        _isUpdating = false;
        return;
      }
      
      final file = File(downloadPath);
      await file.writeAsBytes(response.bodyBytes);

      // 2. Create BAT script
      final batPath = path.join(exeDir, 'updater.bat');
      final batContent = '''
@echo off
ping -n 4 127.0.0.1 > NUL
rename "$exeName" "$exeName.old"
move /y "${downloadPath}" "$exeName"
start "" "$exeName"
del "%~f0"
''';
      
      await File(batPath).writeAsString(batContent);

      // 3. Execute BAT and exit
      await Process.start('cmd', ['/c', 'start', '/b', batPath], workingDirectory: exeDir);
      exit(0);
      
    } catch (e) {
      debugPrint('Update execution failed: $e');
      _isUpdating = false;
    }
  }
}
