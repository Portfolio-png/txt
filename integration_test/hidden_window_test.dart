import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// A covered window must not stop the run.
//
// The engine says `AppLifecycleState.hidden` when the test window is covered
// — someone using the Mac is enough — and the scheduler stops drawing, so
// every pump waited for a frame that never came (18-minute steps, a toast that
// never cleared). This sends that exact message down the engine's own path
// and pumps through it.
//
// With E2E_ALLOW_HIDDEN=true the harness's guard is off, and this is expected
// to fail as HOST STARVED within ten seconds, not hang.
void main() {
  ensureBinding();

  testWidgets('a hidden window still gets frames', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('drawing')));

    ui.channelBuffers.push(
      SystemChannels.lifecycle.name,
      SystemChannels.lifecycle.codec.encodeMessage('AppLifecycleState.hidden'),
      (_) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final watch = Stopwatch()..start();
    for (var i = 0; i < 10; i += 1) {
      await pumpUntil(tester, find.text('drawing'), timeout: const Duration(seconds: 20));
    }
    expect(SchedulerBinding.instance.framesEnabled, isTrue);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)),
        reason: 'ten pumps through a hidden window should take about a second');
  });
}
