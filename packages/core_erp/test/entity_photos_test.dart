import 'dart:typed_data';

import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/core/services/photo_requests.dart';
import 'package:core_erp/core/services/socket_service.dart';
import 'package:core_erp/core/widgets/mini_photo.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Photos for parts, dies, machines, companies and people: asked for in
// batches, kept fresh, and offered as a small picture that adds, shows,
// replaces and removes.

class _Repo extends EntityPhotoRepository {
  _Repo() : super(baseUrl: 'http://x');

  final List<(String, List<String>)> asked = [];
  final Map<String, EntityPhoto> stored = {};
  final List<int> removed = [];
  int _ids = 1;

  @override
  Future<Map<String, EntityPhoto>> primaryPhotos(
    String owner,
    List<String> ids,
  ) async {
    asked.add((owner, List.of(ids)));
    return {
      for (final id in ids)
        if (stored['$owner:$id'] case final photo?) id: photo,
    };
  }

  @override
  Future<EntityPhoto> upload(String owner, String id, XFile file) async {
    final photo = EntityPhoto(
      assetId: _ids++,
      url: 'http://x/$owner/$id/${file.name}',
      fetchedAt: DateTime.now(),
    );
    stored['$owner:$id'] = photo;
    return photo;
  }

  @override
  Future<void> remove(String owner, String id, int assetId) async {
    removed.add(assetId);
    stored.remove('$owner:$id');
  }
}

void main() {
  test('one frame of asks is one request per kind of record', () async {
    final repo = _Repo()
      ..stored['item:7'] = EntityPhoto(
        assetId: 3,
        url: 'http://x/7.png',
        fetchedAt: DateTime.now(),
      );
    final photos = EntityPhotosProvider(repository: repo);
    addTearDown(photos.dispose);

    photos
      ..request(PhotoOwner.item, '7')
      ..request(PhotoOwner.item, '8')
      ..request(PhotoOwner.client, '5')
      ..request(PhotoOwner.item, '7');
    await Future<void>.delayed(Duration.zero);

    expect(repo.asked, hasLength(2));
    expect(repo.asked.firstWhere((a) => a.$1 == 'item').$2, ['7', '8']);
    expect(photos.photoOf(PhotoOwner.item, '7')!.url, 'http://x/7.png');
    expect(photos.photoOf(PhotoOwner.item, '8'), isNull);

    // Known — with a photo or without — and fresh: not asked again.
    photos
      ..request(PhotoOwner.item, '7')
      ..request(PhotoOwner.item, '8');
    await Future<void>.delayed(Duration.zero);
    expect(repo.asked, hasLength(2));
  });

  test('a photo older than its signed link is asked for again', () async {
    final repo = _Repo();
    final photos = EntityPhotosProvider(
      repository: repo,
      maxAge: Duration.zero,
    );
    addTearDown(photos.dispose);
    photos.request(PhotoOwner.die, '4');
    await Future<void>.delayed(Duration.zero);
    photos.request(PhotoOwner.die, '4');
    await Future<void>.delayed(Duration.zero);
    expect(repo.asked, hasLength(2));
  });

  test('upload and remove keep what is shown in step', () async {
    final repo = _Repo();
    final photos = EntityPhotosProvider(repository: repo);
    addTearDown(photos.dispose);
    final file = XFile.fromData(
      Uint8List.fromList(const [1, 2, 3]),
      name: 'logo.png',
    );

    expect(await photos.upload(PhotoOwner.client, '5', file), isNull);
    expect(photos.photoOf(PhotoOwner.client, '5')!.url, startsWith('http://x/client/5/'));

    expect(await photos.remove(PhotoOwner.client, '5'), isNull);
    expect(photos.photoOf(PhotoOwner.client, '5'), isNull);
    expect(repo.removed, [1]);
  });

  test('a photo stored elsewhere is asked for again when the server says so', () async {
    // The phone (or another desktop) stored it: the server's asset_changed
    // drops what is known, instead of the slot waiting out its 4 minutes.
    final repo = _Repo();
    final photos = EntityPhotosProvider(repository: repo);
    addTearDown(photos.dispose);
    photos.request(PhotoOwner.die, '31');
    await Future<void>.delayed(Duration.zero);
    expect(photos.photoOf(PhotoOwner.die, '31'), isNull);

    repo.stored['die:31'] = EntityPhoto(assetId: 9, url: 'http://x/d.png', fetchedAt: DateTime.now());
    SocketService.instance.processEventForTest(
      'event: custom-event\ndata: {"event":"asset_changed","data":{"entityType":"die","entityId":31}}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(photos.photoOf(PhotoOwner.die, '31')!.url, 'http://x/d.png');
    expect(repo.asked, hasLength(2));

    // A record nothing on screen asked about is left alone.
    SocketService.instance.processEventForTest(
      'event: custom-event\ndata: {"event":"asset_changed","data":{"entityType":"die","entityId":99}}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(repo.asked, hasLength(2));
  });

  group('MiniPhoto', () {
    late _Repo repo;
    late EntityPhotosProvider photos;
    late PhotoRequestsProvider requests;

    setUp(() {
      repo = _Repo();
      photos = EntityPhotosProvider(repository: repo);
      requests = PhotoRequestsProvider(
        repository: PhotoRequestRepository(baseUrl: 'http://x', useMockResponses: true),
        listen: false,
      );
    });
    tearDown(() {
      photos.dispose();
      requests.dispose();
      MiniPhoto.debugPickFile = null;
    });

    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      bool provide = true,
      bool phone = true,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: provide
                ? ChangeNotifierProvider<EntityPhotosProvider>.value(
                    value: photos,
                    child: phone
                        ? ChangeNotifierProvider<PhotoRequestsProvider>.value(
                            value: requests,
                            child: child,
                          )
                        : child,
                  )
                : child,
          ),
        ),
      ),
    );

    testWidgets('takes no space where photos are not kept', (tester) async {
      await pump(
        tester,
        const MiniPhoto(owner: PhotoOwner.item, id: '7'),
        provide: false,
      );
      expect(find.byType(InkWell), findsNothing);
      expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
    });

    testWidgets('a record not saved yet says why, and does nothing', (
      tester,
    ) async {
      await pump(
        tester,
        const MiniPhoto(
          owner: PhotoOwner.item,
          id: null,
          disabledReason: 'Save the part first',
        ),
      );
      expect(find.byTooltip('Save the part first'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('empty, a tap asks how; a file from this PC is stored', (tester) async {
      MiniPhoto.debugPickFile = () async => XFile.fromData(
        Uint8List.fromList(const [1, 2, 3]),
        name: 'patti.png',
      );
      await pump(
        tester,
        const MiniPhoto(owner: PhotoOwner.item, id: '7', what: 'part photo'),
      );
      await tester.pump();
      expect(find.byTooltip('Add part photo'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('photo-item-7')));
      await tester.pumpAndSettle();
      expect(find.text('Take on phone'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('photo-choose-file')));
      await tester.pumpAndSettle();
      expect(repo.stored['item:7'], isNotNull);
      expect(find.byTooltip('Open part photo'), findsOneWidget);
      expect(find.text('Photo saved.'), findsOneWidget);
    });

    testWidgets('with a photo, a tap shows it large; Remove takes it off', (
      tester,
    ) async {
      repo.stored['machine:9'] = EntityPhoto(
        assetId: 41,
        url: 'http://x/m.png',
        fetchedAt: DateTime.now(),
      );
      await pump(tester, const MiniPhoto(owner: PhotoOwner.machine, id: '9'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('photo-machine-9')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('photo-replace')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('photo-remove')));
      await tester.pumpAndSettle();
      expect(repo.removed, [41]);
      expect(photos.photoOf(PhotoOwner.machine, '9'), isNull);
    });

    testWidgets('Take on phone sends the job; the slot waits, and a tap takes it back', (
      tester,
    ) async {
      await pump(
        tester,
        const MiniPhoto(
          owner: PhotoOwner.die,
          id: '31',
          what: 'die photo',
          label: 'Photo',
          size: 52,
          note: 'for part HH1',
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('photo-die-31')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('photo-take-on-phone')));
      await tester.pumpAndSettle();

      final sent = requests.pendingFor(PhotoOwner.die, '31');
      expect(sent, isNotNull);
      expect(sent!.context, 'for part HH1');
      expect(find.text('On phone'), findsOneWidget);
      expect(find.byTooltip('Waiting for your phone — click to take it back'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('photo-die-31')));
      await tester.pumpAndSettle();
      expect(requests.pendingFor(PhotoOwner.die, '31'), isNull);
      expect(find.text('On phone'), findsNothing);
      expect(find.text('Photo'), findsOneWidget);
    });

    testWidgets('without phone photos, Take on phone is there but disabled', (tester) async {
      await pump(
        tester,
        const MiniPhoto(owner: PhotoOwner.client, id: '5', what: 'company logo'),
        phone: false,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('photo-client-5')));
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(find.descendant(
        of: find.byKey(const ValueKey<String>('photo-take-on-phone')),
        matching: find.byType(ListTile),
      ));
      expect(tile.enabled, isFalse);
      expect(find.text('Phone photos are not set up in this app.'), findsOneWidget);
    });

    testWidgets('with a photo, Retake on phone sends a job', (tester) async {
      repo.stored['item:7'] = EntityPhoto(assetId: 3, url: 'http://x/7.png', fetchedAt: DateTime.now());
      await pump(tester, const MiniPhoto(owner: PhotoOwner.item, id: '7'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('photo-item-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('photo-retake-on-phone')));
      await tester.pumpAndSettle();
      expect(requests.pendingFor(PhotoOwner.item, '7'), isNotNull);
    });
  });
}
