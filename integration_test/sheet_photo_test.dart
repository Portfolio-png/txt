import 'dart:convert';

import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/features/items/presentation/widgets/part_photo_gallery.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/harness.dart';

// A part's photos, through its gallery, against the real server with NO S3
// bucket — the store this machine actually has: two views picked from this
// computer, the second made the main one, saved; then one removed.
//
// `scripts/e2e-ui.sh sheet_photo` reads the rows back out of SQLite — one
// kept with its thumbnail, one deleted — finds the files on disk, and runs
// the sweep a day on to see the deleted one's files go.

const _seededGroup = 'Primary Group';
const _newPart = 'E2E Photo Part';

// Two small real PNGs, different bytes: two views, not one twice.
final _front = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAGCAIAAABxZ0isAAAAEUlEQVR4nGM4oaGBFTEMpAQAgPc0gUXKIv0AAAAASUVORK5CYII=',
);
final _side = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAYAAAAICAIAAABVpBlvAAAAEUlEQVR4nGPQ0DiBhhgGgxAAeXk0gfi/cm4AAAAASUVORK5CYII=',
);

Finder _partPhoto() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('photo-item-') &&
      key.value != 'photo-item-none';
});

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<void> _openGallery(WidgetTester tester) async {
  await tester.tap(_partPhoto().first);
  await pumpUntil(tester, _key('gallery_count'), reason: 'the part photo should open its gallery');
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(_key('gallery_save'));
  await pumpUntil(tester, find.text('Photos saved.'), reason: 'Save should upload and arrange');
  await pumpUntilGone(tester, _key('part_photo_gallery'), timeout: const Duration(seconds: 10));
}

void main() {
  ensureBinding();

  testWidgets('a part keeps its views: two added, the second made main, one removed', (
    tester,
  ) async {
    PartPhotoGallery.debugPickFiles = () async => [
      XFile.fromData(_front, path: '/tmp/e2e-front.png', mimeType: 'image/png'),
      XFile.fromData(_side, path: '/tmp/e2e-side.png', mimeType: 'image/png'),
    ];
    addTearDown(() => PartPhotoGallery.debugPickFiles = null);

    await bootApp(tester);
    await openItemSheet(tester);

    // A part, not a development deal: the deal's required columns would
    // otherwise hold the save.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await pickInCell(tester, column: 1, label: _seededGroup);
    await typeNewInCell(tester, column: 3, value: _newPart);
    await tester.tap(find.byKey(const ValueKey<String>('save_item_sheet_btn')));
    await pumpUntil(
      tester,
      find.textContaining('SAVED #'),
      reason: 'the part has to exist before it can hold a photo',
    );
    await pumpUntil(tester, _partPhoto(), reason: 'a saved row should offer its photos');

    // --- two views from this computer, the second the main one ---------------
    await _openGallery(tester);
    expect(find.text('0 of 5'), findsOneWidget);
    await tester.tap(_key('gallery_add_0'));
    await pumpUntil(tester, _key('gallery_from_computer'), reason: 'a + slot asks how');
    await tester.tap(_key('gallery_from_computer'));
    await pumpUntil(tester, find.text('2 of 5'), reason: 'both files should be held');
    await tester.tap(_key('gallery_star_1'));
    await tester.pump(const Duration(milliseconds: 200));
    dumpVisibleText(tester, 'E2E gallery before Save');
    await _save(tester);

    final key = tester.widget(_partPhoto().first).key! as ValueKey<String>;
    final partId = key.value.substring('photo-item-'.length);
    final photos = Provider.of<EntityPhotosProvider>(
      tester.element(_partPhoto().first),
      listen: false,
    );
    final saved = (await tester.runAsync(() => photos.partPhotos(partId)))!;
    expect(saved, hasLength(2));
    expect(saved.map((p) => p.isPrimary), [false, true], reason: 'the second is the main one');

    // The thumbnail's permanent link leads to a small JPEG.
    final thumb = await tester.runAsync(() => http.get(Uri.parse(saved.first.thumbUrl)));
    expect(thumb!.statusCode, 200, reason: saved.first.thumbUrl);
    expect(thumb.headers['content-type'], 'image/jpeg');

    // --- one removed ----------------------------------------------------------
    await _openGallery(tester);
    expect(find.text('2 of 5'), findsOneWidget);
    await tester.tap(_key('gallery_remove_0'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('1 of 5'), findsOneWidget);
    await _save(tester);

    final left = (await tester.runAsync(() => photos.partPhotos(partId)))!;
    expect(left, hasLength(1));
    expect(left.single.isPrimary, isTrue);
    expect(left.single.id, saved.last.id);
    dumpVisibleText(tester, 'E2E after the gallery');
  });
}
