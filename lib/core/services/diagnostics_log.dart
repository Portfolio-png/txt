import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// A log file on the machine the app runs on, for when something goes wrong
/// there and nobody is watching (2026-11-25: a client's Mac crashed and hung
/// with nothing recorded anywhere — Sentry was never given a key).
///
/// macOS: `Library/Logs/Paper/paper.log` under the app's home — the release
/// app is sandboxed, so that is
/// `~/Library/Containers/com.example.paper/Data/Library/Logs/Paper/paper.log`
/// (checked on a release build, 2026-11-25). Windows:
/// `%LOCALAPPDATA%\Paper\Logs\paper.log`. It holds:
///
///  * every launch, with the version and OS;
///  * every uncaught error;
///  * the app's memory once a minute — a Mac that "hangs" is often one this
///    app has pushed into swap, and the climb shows here;
///  * the UI thread stalling for [stallReport] or more, measured by a timer
///    that ticks late when the thread is blocked.
///
/// A memory figure over [memoryWarning] or a stall over [stallReport] is also
/// sent to Sentry as a warning, at most once per [_repeatEvery] each. The file
/// rotates at [_maxBytes] and keeps [_keep] old ones, so it never fills a
/// disk. Writing never throws: diagnostics must not be what breaks the app.
class DiagnosticsLog {
  DiagnosticsLog._();

  static final DiagnosticsLog instance = DiagnosticsLog._();

  static const int _maxBytes = 2 * 1024 * 1024;
  static const int _keep = 3;
  static const Duration _memoryEvery = Duration(minutes: 1);
  static const Duration _tick = Duration(seconds: 1);
  static const Duration stallReport = Duration(seconds: 5);
  static const int memoryWarning = 1536 * 1024 * 1024;
  static const Duration _repeatEvery = Duration(minutes: 10);

  File? _file;
  Timer? _memoryTimer;
  Timer? _stallTimer;
  DateTime? _lastTick;
  int _peakRss = 0;
  DateTime? _lastMemoryWarning;
  DateTime? _lastStallWarning;

  /// Where the log is, once started — for a Settings link or a support call.
  String? get path => _file?.path;

  /// The folder logs go in on this OS; null where there is none (web).
  static Directory? logDirectory() {
    if (kIsWeb) return null;
    final env = Platform.environment;
    if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home == null || home.isEmpty) return null;
      return Directory('$home/Library/Logs/Paper');
    }
    if (Platform.isWindows) {
      final local = env['LOCALAPPDATA'] ?? env['APPDATA'];
      if (local == null || local.isEmpty) return null;
      return Directory('$local\\Paper\\Logs');
    }
    final home = env['HOME'];
    return home == null ? null : Directory('$home/.paper/logs');
  }

  /// Opens the log and starts the memory and stall watches. Safe to call
  /// once at start-up; a second call does nothing.
  Future<void> start({required String version, Directory? directory}) async {
    if (_file != null) return;
    try {
      final dir = directory ?? logDirectory();
      if (dir == null) return;
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}paper.log');
      _rotateIfLarge(file);
      _file = file;
      write(
        'START',
        'version=$version os=${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion} cpus=${Platform.numberOfProcessors} '
            'mode=${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')}',
      );
      _sampleMemory();
      _memoryTimer = Timer.periodic(_memoryEvery, (_) => _sampleMemory());
      _lastTick = DateTime.now();
      _stallTimer = Timer.periodic(_tick, (_) => _checkStall());
    } catch (_) {
      // No log is better than no app.
    }
  }

  /// One line: time, level, message. Errors are swallowed.
  void write(String level, String message) {
    final file = _file;
    if (file == null) return;
    try {
      final line =
          '${DateTime.now().toIso8601String()} $level ${message.replaceAll('\n', ' | ')}\n';
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
      if (file.lengthSync() > _maxBytes) _rotateIfLarge(file);
    } catch (_) {}
  }

  void error(Object error, StackTrace? stack, {String where = ''}) {
    final top = stack?.toString().split('\n').take(12).join(' | ') ?? '';
    write('ERROR', '${where.isEmpty ? '' : '[$where] '}$error :: $top');
  }

  void _sampleMemory() {
    try {
      final rss = ProcessInfo.currentRss;
      if (rss > _peakRss) _peakRss = rss;
      write('MEM', 'rss=${_mb(rss)}MB peak=${_mb(_peakRss)}MB');
      if (rss >= memoryWarning && _due(_lastMemoryWarning)) {
        _lastMemoryWarning = DateTime.now();
        write('WARN', 'memory high: ${_mb(rss)}MB');
        unawaited(
          Sentry.captureMessage(
            'Memory high: ${_mb(rss)} MB',
            level: SentryLevel.warning,
            withScope: (scope) {
              scope.setTag('diagnostic', 'memory');
              scope.setContexts('memory', {
                'rss_mb': _mb(rss),
                'peak_mb': _mb(_peakRss),
              });
            },
          ),
        );
      }
    } catch (_) {}
  }

  void _checkStall() {
    final now = DateTime.now();
    final last = _lastTick ?? now;
    _lastTick = now;
    // The timer asked for a tick a second ago; the rest is time the UI
    // thread could not run it.
    final late = now.difference(last) - _tick;
    if (late < stallReport) return;
    write('STALL', 'UI thread blocked ~${late.inMilliseconds} ms');
    if (!_due(_lastStallWarning)) return;
    _lastStallWarning = now;
    unawaited(
      Sentry.captureMessage(
        'UI thread stalled ${late.inSeconds} s',
        level: SentryLevel.warning,
        withScope: (scope) {
          scope.setTag('diagnostic', 'stall');
          scope.setContexts('stall', {'ms': late.inMilliseconds});
        },
      ),
    );
  }

  /// paper.log → paper.1.log → … → paper.[_keep].log, the oldest dropped.
  void _rotateIfLarge(File file) {
    try {
      if (!file.existsSync() || file.lengthSync() <= _maxBytes) return;
      final base = file.path.substring(0, file.path.length - '.log'.length);
      final oldest = File('$base.$_keep.log');
      if (oldest.existsSync()) oldest.deleteSync();
      for (var i = _keep - 1; i >= 1; i -= 1) {
        final older = File('$base.$i.log');
        if (older.existsSync()) older.renameSync('$base.${i + 1}.log');
      }
      file.renameSync('$base.1.log');
    } catch (_) {}
  }

  bool _due(DateTime? last) =>
      last == null || DateTime.now().difference(last) >= _repeatEvery;

  static int _mb(int bytes) => bytes ~/ (1024 * 1024);

  @visibleForTesting
  static int get maxBytesForTest => _maxBytes;

  @visibleForTesting
  void stopForTest() {
    _memoryTimer?.cancel();
    _stallTimer?.cancel();
    _file = null;
  }
}
