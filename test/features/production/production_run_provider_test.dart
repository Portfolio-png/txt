import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper/features/production/providers/production_run_provider.dart';
import 'package:paper/features/production/data/datasources/offline_database_helper.dart';
import 'package:sqflite/sqflite.dart';

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

  test('asset verification updates expectations, verifies codes with normalization, and triggers callbacks', () {
    final provider = ProductionRunProvider();
    addTearDown(provider.dispose);

    provider.updateExpectedAssets(
      stageId: 'stage-1',
      machineId: 'MC-SLIT-01',
      dieId: 'DIE-1450-A',
    );

    expect(provider.stageId, 'stage-1');
    expect(provider.expectedMachineId, 'MC-SLIT-01');
    expect(provider.expectedDieId, 'DIE-1450-A');
    expect(provider.scannedMachineId, isNull);
    expect(provider.scannedDieId, isNull);

    // Scan wrong asset
    provider.verifyScannedAsset('WRONG-BARCODE');
    expect(provider.barcodeErrorMessage, contains('does not match expected assets'));
    expect(provider.scannedMachineId, isNull);

    // Scan machine with normalization (lowercase, prefix)
    bool callbackTriggered = false;
    provider.verifyScannedAsset('mc:mc-slit-01', onVerifiedAll: () {
      callbackTriggered = true;
    });
    expect(provider.barcodeErrorMessage, isNull);
    expect(provider.scannedMachineId, 'MC-SLIT-01');
    expect(callbackTriggered, isFalse);

    // Scan die with normalization
    provider.verifyScannedAsset('die-1450-a', onVerifiedAll: () {
      callbackTriggered = true;
    });
    expect(provider.barcodeErrorMessage, isNull);
    expect(provider.scannedDieId, 'DIE-1450-A');
    expect(callbackTriggered, isTrue);
  });

  test('offline fallback logs stage closure payload on SocketException', () async {
    final mockDb = MockDatabase();
    OfflineSyncDbHelper.setMockDatabase(mockDb);
    addTearDown(() => OfflineSyncDbHelper.setMockDatabase(null));

    final provider = ProductionRunProvider(
      bufferCommitter: (commit) async {
        throw const SocketException('No Internet');
      },
    );
    addTearDown(provider.dispose);

    provider.startRun(runId: 'RUN-OFFLINE');
    provider.incrementYield(10);
    provider.addScrap(3);

    // Expect completion succeeds on the UI side immediately
    await provider.completeStage();
    expect(provider.state, ProductionState.completed);

    // Verify it was logged locally
    final pending = mockDb.logs;
    expect(pending, hasLength(1));
    expect(pending.first['run_id'], 'RUN-OFFLINE');
    expect(pending.first['sync_status'], 'pending');
    expect(pending.first['payload'], contains('"goodYield":10'));
    expect(pending.first['payload'], contains('"setupScrap":3'));
  });

  test('periodic sync polls database and synchronizes pending logs', () async {
    final mockDb = MockDatabase();
    OfflineSyncDbHelper.setMockDatabase(mockDb);
    addTearDown(() => OfflineSyncDbHelper.setMockDatabase(null));

    // Seed mock DB with a pending log
    await OfflineSyncDbHelper.instance.insertLog(
      OfflineStageLog(
        runId: 'RUN-SYNC',
        stageId: 'stage-1',
        payload: const {'goodYield': 15, 'setupScrap': 2},
        createdAt: DateTime.now(),
        syncStatus: 'pending',
      ),
    );

    expect(mockDb.logs, hasLength(1));

    final committed = <ProductionRunCommit>[];
    final provider = ProductionRunProvider(
      offlinePollInterval: const Duration(milliseconds: 10),
      bufferCommitter: (commit) async {
        committed.add(commit);
      },
    );
    addTearDown(provider.dispose);

    // Wait a brief moment for the timer to trigger
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Verify that the pending log has been synced and removed from database
    expect(committed, hasLength(1));
    expect(committed.first.runId, 'RUN-SYNC');
    expect(committed.first.goodYield, 15);
    expect(committed.first.setupScrap, 2);
    expect(mockDb.logs, isEmpty);
  });

  test('triggerRefresh increments refreshCount and notifies listeners', () {
    final provider = ProductionRunProvider();
    addTearDown(provider.dispose);

    expect(provider.refreshCount, 0);

    int notifications = 0;
    provider.addListener(() {
      notifications++;
    });

    provider.triggerRefresh();
    expect(provider.refreshCount, 1);
    expect(notifications, 1);

    provider.triggerRefresh();
    expect(provider.refreshCount, 2);
    expect(notifications, 2);
  });
}

class MockDatabase implements Database {
  final List<Map<String, dynamic>> logs = [];
  int _nextId = 1;

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    final Map<String, dynamic> row = Map.from(values);
    if (!row.containsKey('id')) {
      row['id'] = _nextId++;
    }
    logs.add(row);
    return row['id'] as int;
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async {
    return logs;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    if (whereArgs != null && whereArgs.isNotEmpty) {
      final id = whereArgs.first as int;
      logs.removeWhere((item) => item['id'] == id);
      return 1;
    }
    logs.clear();
    return 0;
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    if (whereArgs != null && whereArgs.isNotEmpty) {
      final id = whereArgs.first as int;
      for (final item in logs) {
        if (item['id'] == id) {
          item.addAll(values);
        }
      }
      return 1;
    }
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
