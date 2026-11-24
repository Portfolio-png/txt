import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper/core/services/diagnostics_log.dart';

// The log a client's machine keeps (2026-11-25): it must write, rotate and
// never grow without bound — a diagnostics file that fills a disk would be
// the next thing that hangs a Mac.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('paper-diag-'));
  tearDown(() {
    DiagnosticsLog.instance.stopForTest();
    dir.deleteSync(recursive: true);
  });

  test('a start writes the version and a memory line', () async {
    await DiagnosticsLog.instance.start(version: '1.0.7+7', directory: dir);
    final text = File('${dir.path}/paper.log').readAsStringSync();
    expect(text, contains('START version=1.0.7+7'));
    expect(text, contains(RegExp(r'MEM rss=\d+MB')));
  });

  test('errors are one line each, with where they came from', () async {
    await DiagnosticsLog.instance.start(version: 't', directory: dir);
    DiagnosticsLog.instance.error(StateError('boom'), StackTrace.current, where: 'sheet');
    final lines = File('${dir.path}/paper.log').readAsLinesSync();
    final error = lines.singleWhere((l) => l.contains(' ERROR '));
    expect(error, contains('[sheet] Bad state: boom'));
  });

  test('the file rotates and keeps three old ones, no more', () async {
    await DiagnosticsLog.instance.start(version: 't', directory: dir);
    final chunk = 'x' * 4096;
    final lines = (DiagnosticsLog.maxBytesForTest ~/ 4096) * 5;
    for (var i = 0; i < lines; i += 1) {
      DiagnosticsLog.instance.write('FILL', chunk);
    }
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, containsAll(['paper.log', 'paper.1.log', 'paper.2.log', 'paper.3.log']));
    expect(names, isNot(contains('paper.4.log')));
    final total = dir
        .listSync()
        .whereType<File>()
        .fold<int>(0, (sum, f) => sum + f.lengthSync());
    expect(total, lessThan(DiagnosticsLog.maxBytesForTest * 5), reason: 'bounded');
  });
}
