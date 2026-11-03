import 'dart:typed_data';

import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/core/services/photo_requests.dart';
import 'package:core_erp/core/services/socket_service.dart';
import 'package:core_erp/features/items/presentation/widgets/part_photo_gallery.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// A part's photos in their gallery: the main one big, the views in slots,
// nothing changed until Save — and then in one pass: removals, uploads (as
// views, not the main photo), then one request for the order and the main.

class _Repo extends EntityPhotoRepository {
  _Repo(int count) : super(baseUrl: 'http://x') {
    for (var id = 1; id <= count; id += 1) {
      photos.add(_photo(id, primary: id == 1));
    }
  }

  static PartPhoto _photo(int id, {bool primary = false}) => PartPhoto(
    id: id,
    thumbUrl: 'http://x/t/$id.jpg',
    viewUrl: 'http://x/v/$id.jpg',
    isPrimary: primary,
    position: id,
  );

  final List<PartPhoto> photos = [];
  final List<int> removed = [];
  final List<(String, bool)> stored = [];
  final List<(String, int?)> arranged = [];
  int _ids = 100;

  @override
  Future<Map<String, EntityPhoto>> primaryPhotos(String owner, List<String> ids) async => {};

  @override
  Future<List<PartPhoto>> partPhotos(String itemId) async => List.of(photos);

  @override
  Future<List<PartPhoto>> arrangePartPhotos(
    String itemId, {
    required List<int> order,
    int? primaryId,
  }) async {
    arranged.add((order.join(','), primaryId));
    return List.of(photos);
  }

  @override
  Future<Map<String, dynamic>> store(
    String owner,
    String id,
    XFile file, {
    String? documentTitle,
    bool isPrimary = true,
  }) async {
    stored.add((file.name, isPrimary));
    return {'id': _ids++};
  }

  @override
  Future<void> remove(String owner, String id, int assetId) async => removed.add(assetId);
}

void main() {
  late _Repo repo;
  late EntityPhotosProvider photos;
  late PhotoRequestsProvider requests;
  late bool? saved;

  Future<void> open(WidgetTester tester, {int count = 3}) async {
    repo = _Repo(count);
    photos = EntityPhotosProvider(repository: repo);
    requests = PhotoRequestsProvider(
      repository: PhotoRequestRepository(baseUrl: 'http://x', useMockResponses: true),
      listen: false,
    );
    addTearDown(() {
      photos.dispose();
      requests.dispose();
      PartPhotoGallery.debugPickFiles = null;
    });
    saved = null;
    tester.view.physicalSize = const Size(1300, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EntityPhotosProvider>.value(value: photos),
          ChangeNotifierProvider<PhotoRequestsProvider>.value(value: requests),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await showPartPhotoGallery(context, itemId: '7', partName: 'Patti');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(key('gallery_save')).onPressed != null;

  testWidgets('the main photo big, the views in slots, the count beside them', (tester) async {
    await open(tester);
    expect(find.text('Photos of Patti'), findsOneWidget);
    expect(key('gallery_main'), findsOneWidget);
    expect(find.text('Main photo'), findsOneWidget);
    for (final index in [0, 1, 2]) {
      expect(key('gallery_slot_$index'), findsOneWidget);
    }
    expect(key('gallery_add_3'), findsOneWidget);
    expect(key('gallery_add_4'), findsOneWidget);
    expect(find.text('3 of 5'), findsOneWidget);
    expect(saveEnabled(tester), isFalse, reason: 'nothing changed yet');

    // A slot shows its photo big; that one is not the main one.
    await tester.tap(key('gallery_slot_1'));
    await tester.pump();
    expect(find.text('Main photo'), findsNothing);
    expect(key('gallery_make_main'), findsOneWidget);
  });

  testWidgets('★ makes a view the main one — only on Save, in one request', (tester) async {
    await open(tester);
    await tester.tap(key('gallery_star_2'));
    await tester.pump();
    expect(repo.arranged, isEmpty, reason: 'nothing is sent before Save');
    expect(saveEnabled(tester), isTrue);

    await tester.tap(key('gallery_save'));
    await tester.pumpAndSettle();
    expect(repo.arranged, [('1,2,3', 3)]);
    expect(repo.removed, isEmpty);
    expect(repo.stored, isEmpty);
    expect(saved, isTrue);
    expect(key('part_photo_gallery'), findsNothing);
  });

  testWidgets('× takes a view out on Save, not before; the main one moves on', (tester) async {
    await open(tester);
    await tester.tap(key('gallery_remove_0'));
    await tester.pump();
    expect(repo.removed, isEmpty);
    expect(find.text('2 of 5'), findsOneWidget);
    // The next one is the main one now.
    expect(find.byIcon(Icons.star_rounded), findsWidgets);

    await tester.tap(key('gallery_save'));
    await tester.pumpAndSettle();
    expect(repo.removed, [1]);
    expect(repo.arranged, [('2,3', 2)]);
  });

  testWidgets('a file from this computer is held until Save, then stored as a view', (tester) async {
    await open(tester);
    PartPhotoGallery.debugPickFiles = () async => [
      XFile.fromData(Uint8List.fromList(const [1, 2, 3]), path: '/tmp/side.jpg'),
    ];
    await tester.tap(key('gallery_add_3'));
    await tester.pumpAndSettle();
    expect(find.text('Take on phone'), findsOneWidget);
    await tester.tap(key('gallery_from_computer'));
    await tester.pumpAndSettle();

    expect(repo.stored, isEmpty, reason: 'nothing is uploaded until Save');
    expect(find.text('4 of 5'), findsOneWidget);
    expect(find.text('New — saved on Save'), findsWidgets);

    await tester.tap(key('gallery_save'));
    await tester.pumpAndSettle();
    expect(repo.stored, [('side.jpg', false)], reason: 'one more view, not the main photo');
    expect(repo.arranged, [('1,2,3,100', 1)]);
  });

  testWidgets('Cancel with something staged asks first, and changes nothing', (tester) async {
    await open(tester);
    await tester.tap(key('gallery_remove_1'));
    await tester.pump();
    await tester.tap(key('gallery_cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard the changes to these photos?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(key('part_photo_gallery'), findsNothing);
    expect(saved, isFalse);
    expect(repo.removed, isEmpty);
    expect(repo.arranged, isEmpty);
  });

  testWidgets('at five there is no room: the place to add says so', (tester) async {
    await open(tester, count: 5);
    expect(find.text('5 of 5'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('gallery_add_')), findsNothing);
    expect(key('gallery_full'), findsOneWidget);
  });

  testWidgets('Take on phone sends the job; the shot appears live, from the phone', (tester) async {
    await open(tester);
    await tester.tap(key('gallery_add_3'));
    await tester.pumpAndSettle();
    await tester.tap(key('gallery_take_on_phone'));
    await tester.pumpAndSettle();
    expect(requests.pendingFor('item', '7'), isNotNull);
    expect(key('gallery_on_phone_3'), findsOneWidget);

    // The phone stored it: the server says so, and the gallery looks again.
    repo.photos.add(_Repo._photo(4));
    SocketService.instance.processEventForTest(
      'event: custom-event\ndata: {"event":"asset_changed","data":{"entityType":"item","entityId":7}}',
    );
    await tester.pumpAndSettle();
    expect(key('gallery_slot_3'), findsOneWidget);
    expect(find.text('From phone'), findsOneWidget);
    // It is the part's already: nothing to save.
    expect(saveEnabled(tester), isFalse);
  });
}
