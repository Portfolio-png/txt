import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/production_run_provider.dart';

void main() {
  test('resilient timer derives elapsed time from startedAt timestamp', () {
    var now = DateTime(2026, 5, 21, 10);
    final provider = ProductionRunProvider(now: () => now);
    addTearDown(provider.dispose);

    provider.startRun(runId: 'RUN-1');
    now = now.add(const Duration(minutes: 5, seconds: 7));

    expect(provider.elapsedSeconds, 307);
    expect(provider.elapsedDisplay, '00:05:07');
  });

  test(
    'yield and scrap buffers stay local until pause or completion',
    () async {
      var now = DateTime(2026, 5, 21, 10);
      final commits = <ProductionRunCommit>[];
      final provider = ProductionRunProvider(
        now: () => now,
        bufferCommitter: (commit) async => commits.add(commit),
      );
      addTearDown(provider.dispose);

      provider.startRun(runId: 'RUN-2');
      provider.incrementYield(3);
      provider.addScrap(2);

      expect(provider.goodYield, 3);
      expect(provider.setupScrap, 2);
      expect(commits, isEmpty);

      now = now.add(const Duration(seconds: 30));
      await provider.pauseRun();

      expect(provider.isPaused, isTrue);
      expect(commits, hasLength(1));
      expect(commits.single.goodYield, 3);
      expect(commits.single.setupScrap, 2);
      expect(commits.single.state, ProductionState.paused);
    },
  );

  test(
    'remote paused state locks kiosk input and banks elapsed time',
    () async {
      var now = DateTime(2026, 5, 21, 10);
      var remoteState = ProductionState.running;
      final commits = <ProductionRunCommit>[];
      final provider = ProductionRunProvider(
        now: () => now,
        statusFetcher: (_) async => remoteState,
        bufferCommitter: (commit) async => commits.add(commit),
      );
      addTearDown(provider.dispose);

      provider.startRun(runId: 'RUN-3');
      provider.incrementYield(10);
      now = now.add(const Duration(minutes: 2));
      remoteState = ProductionState.paused;

      await provider.syncOnce();

      expect(provider.isPaused, isTrue);
      expect(provider.isInputLocked, isTrue);
      expect(provider.elapsedDisplay, '00:02:00');
      expect(commits, hasLength(1));

      provider.incrementYield();
      provider.addScrap();
      expect(provider.goodYield, 10);
      expect(provider.setupScrap, 0);
    },
  );

  test('completion commits the latest local buffers', () async {
    final commits = <ProductionRunCommit>[];
    final provider = ProductionRunProvider(
      bufferCommitter: (commit) async => commits.add(commit),
    );
    addTearDown(provider.dispose);

    provider.startRun(runId: 'RUN-4');
    provider.incrementYield(12);
    provider.addScrap(4);
    await provider.completeRun();

    expect(provider.isCompleted, isTrue);
    expect(provider.isInputLocked, isTrue);
    expect(commits, hasLength(1));
    expect(commits.single.goodYield, 12);
    expect(commits.single.setupScrap, 4);
    expect(commits.single.state, ProductionState.completed);
  });
}
