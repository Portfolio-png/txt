import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';

class AutoUpdaterService {
  AutoUpdaterService._();

  static final AutoUpdaterService instance = AutoUpdaterService._();
  bool _isUpdating = false;

  /// Asks the server which desktop version is current and where its Windows
  /// build is (`GET /api/app/latest`), and installs it if it differs from this
  /// one. Called once a user is signed in, because the feed is behind the
  /// login. It used to read the sandbox configuration, which no longer exists.
  Future<void> checkWithServer(String baseUrl, http.Client client) async {
    if (kIsWeb || !Platform.isWindows || _isUpdating) return;
    try {
      final response = await client.get(
        Uri.parse('${baseUrl.replaceFirst(RegExp(r'/$'), '')}/api/app/latest'),
      );
      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return;
      final targetVersion = body['latestVersion'] as String?;
      final downloadUrl = body['downloadUrl'] as String?;
      if (targetVersion == null || targetVersion.isEmpty) return;
      if (downloadUrl == null || downloadUrl.isEmpty) return;

      final packageInfo = await PackageInfo.fromPlatform();
      if (_isNewerVersion(packageInfo.version, targetVersion)) {
        await _performSilentUpdate(downloadUrl);
      }
    } catch (e) {
      debugPrint('Silent auto-update failed: $e');
    }
  }

  /// The version the server names is the one to run: a different version is
  /// installed whether it is newer or older, so an operator can roll back by
  /// naming the older one.
  bool _isNewerVersion(String current, String target) {
    // Simple naive check
    return current != target; 
  }

  Future<void> _performSilentUpdate(String url) async {
    if (kIsWeb || _isUpdating || !Platform.isWindows) return;
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
