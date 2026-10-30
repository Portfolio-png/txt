import 'dart:convert';

import 'package:camera/camera.dart' show XFile;
import 'package:challan_mobile/photos/capture_source.dart';
import 'package:challan_mobile/photos/photo_capture_screen.dart';
import 'package:challan_mobile/photos/photo_queue_gate.dart';
import 'package:challan_mobile/services/socket_service.dart';
import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/core/services/photo_requests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The photos the desktop sends to the phone: the camera opens by itself, the
// record's details sit over it, and the queue walks forward shot by shot.

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _Camera implements CaptureSource {
  int shots = 0;

  @override
  Future<String?> open() async => null;

  @override
  Widget preview(BuildContext context) => const ColoredBox(
        key: ValueKey<String>('fake-preview'),
        color: Colors.black,
      );

  @override
  Future<XFile?> take() async {
    shots += 1;
    return XFile.fromData(_png, name: 'shot$shots.png', mimeType: 'image/png');
  }

  @override
  Future<void> close() async {}
}

class _Queue extends PhotoRequestRepository {
  _Queue(this.jobs) : super(baseUrl: 'http://x');

  final List<PhotoRequest> jobs;
  final List<(int, int?)> completed = [];
  final List<int> skipped = [];

  @override
  Future<List<PhotoRequest>> pending() async => List.of(jobs);

  @override
  Future<void> complete(int requestId, {int? assetId}) async {
    completed.add((requestId, assetId));
    jobs.removeWhere((j) => j.id == requestId);
  }

  @override
  Future<void> skip(int requestId) async {
    skipped.add(requestId);
    jobs.removeWhere((j) => j.id == requestId);
  }
}

const _die = PhotoRequest(
  id: 1,
  owner: 'die',
  entityId: '31',
  context: 'for part HH1',
  kind: 'Die',
  title: 'CDHH1',
  lines: [
    PhotoRequestLine('Type', 'Cutting'),
    PhotoRequestLine('Made by', 'Ashok Dies'),
  ],
);

const _logo = PhotoRequest(
  id: 2,
  owner: 'client',
  entityId: '5',
  kind: 'Company logo',
  title: 'Gold Medal',
  lines: [PhotoRequestLine('GST', '27ABCDE1234F1Z5')],
);

void main() {
  late _Queue queue;
  late PhotoRequestsProvider requests;
  late EntityPhotoRepository store;

  setUp(() {
    queue = _Queue([_die, _logo]);
    requests = PhotoRequestsProvider(repository: queue, listen: false);
    store = EntityPhotoRepository(baseUrl: 'http://x', useMockResponses: true);
  });
  tearDown(() => requests.dispose());

  Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<PhotoRequestsProvider>.value(value: requests),
          Provider<EntityPhotoRepository>.value(value: store),
          ChangeNotifierProvider<SocketService>(create: (_) => SocketService()),
        ],
        child: MaterialApp(home: child),
      );

  testWidgets('the record\'s details sit over the camera, and the queue walks on', (tester) async {
    await requests.refresh();
    final camera = _Camera();
    await tester.pumpWidget(host(PhotoCaptureScreen(source: camera)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('fake-preview')), findsOneWidget);
    expect(find.text('Die'), findsOneWidget);
    expect(find.text('CDHH1'), findsOneWidget);
    expect(find.text('for part HH1'), findsOneWidget);
    expect(find.textContaining('Ashok Dies'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    // Shoot, check, use: uploaded to the die, the job closed with its asset.
    await tester.tap(find.byKey(const ValueKey<String>('photo-shutter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('photo-use')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('photo-use')));
    await tester.pumpAndSettle();
    expect(queue.completed.single.$1, 1);
    expect(queue.completed.single.$2, isNotNull);
    expect((await store.primaryPhotos('die', ['31'])).keys, ['31']);

    // The next job opens straight away.
    expect(find.text('Gold Medal'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);

    // Retake throws the shot away; Use sends the second.
    await tester.tap(find.byKey(const ValueKey<String>('photo-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('photo-retake')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('photo-shutter')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('photo-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('photo-use')));
    await tester.pumpAndSettle();

    expect(camera.shots, 3);
    expect(find.text('All done — 2 photos sent'), findsOneWidget);
  });

  testWidgets('Skip closes the job without a photo', (tester) async {
    await requests.refresh();
    await tester.pumpWidget(host(PhotoCaptureScreen(source: _Camera())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('photo-skip')));
    await tester.pumpAndSettle();
    expect(queue.skipped, [1]);
    expect(find.text('Gold Medal'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget, reason: 'a skipped job is not counted as taken');
  });

  testWidgets('a job arriving opens the camera by itself; closed, it waits in a strip', (tester) async {
    queue.jobs.clear();
    await tester.pumpWidget(host(PhotoQueueGate(
      sourceFactory: _Camera.new,
      child: const Scaffold(body: Text('home')),
    )));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('photo-request-card')), findsNothing);

    // The desktop sends one: the event makes the queue read again.
    queue.jobs.add(_die);
    await requests.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('photo-request-card')), findsOneWidget);
    expect(find.text('CDHH1'), findsOneWidget);

    // Closed with the job still there: the strip offers it back, and the
    // camera does not reopen on its own for a job already seen.
    await tester.tap(find.byKey(const ValueKey<String>('photo-close')));
    await tester.pumpAndSettle();
    expect(find.text('1 photo to take'), findsOneWidget);
    await requests.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('photo-request-card')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('photo-queue-strip')));
    await tester.pumpAndSettle();
    expect(find.text('CDHH1'), findsOneWidget);
  });
}
