import 'dart:typed_data';

import 'package:core_erp/core/services/entity_photos.dart';
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

  group('MiniPhoto', () {
    late _Repo repo;
    late EntityPhotosProvider photos;

    setUp(() {
      repo = _Repo();
      photos = EntityPhotosProvider(repository: repo);
    });
    tearDown(() {
      photos.dispose();
      MiniPhoto.debugPickFile = null;
    });

    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      bool provide = true,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: provide
                ? ChangeNotifierProvider<EntityPhotosProvider>.value(
                    value: photos,
                    child: child,
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

    testWidgets('empty, a tap picks a file and stores it', (tester) async {
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
      await tester.pump();
      await tester.pump();
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
  });
}
