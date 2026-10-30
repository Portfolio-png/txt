import 'dart:convert';

import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/core/widgets/mini_photo.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'support/harness.dart';

// A part's photo, uploaded through the sheet's own thumbnail, against the real
// server with NO S3 bucket — the store this machine actually has. Before the
// local store, this upload answered 503 on every machine without a bucket.
//
// `scripts/e2e-ui.sh` reads the asset row back out of SQLite and finds the
// file on disk; this file asserts the UI could be driven to put it there and
// that the signed link it shows really serves the picture.

const _seededGroup = 'Primary Group';
const _newPart = 'E2E Photo Part';

// A real 1x1 PNG, standing in for the file the picker would return.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Finder _partPhoto() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('photo-item-') &&
      key.value != 'photo-item-none';
});

void main() {
  ensureBinding();

  testWidgets('a part photo is uploaded from the sheet and served back', (
    tester,
  ) async {
    MiniPhoto.debugPickFile = () async =>
        XFile.fromData(_png, name: 'e2e-part.png', mimeType: 'image/png');
    addTearDown(() => MiniPhoto.debugPickFile = null);

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

    // Before the save the row's photo was the disabled kind; now it is the
    // part's own button.
    await pumpUntil(
      tester,
      _partPhoto(),
      reason: 'a saved row should offer an upload for its photo',
    );
    await tester.tap(_partPhoto().first);
    // An empty slot asks how: the phone, or a file from this PC.
    await pumpUntil(tester, find.byKey(const ValueKey<String>('photo-choose-file')),
        reason: 'an empty photo slot should offer a file');
    await tester.tap(find.byKey(const ValueKey<String>('photo-choose-file')));
    await pumpUntil(
      tester,
      find.text('Photo saved.'),
      reason: 'the upload should go through the local store and complete',
    );
    dumpVisibleText(tester, 'E2E after the photo upload');

    // What the thumbnail shows is a signed link; fetch it as the image would.
    final key = tester.widget(_partPhoto().first).key! as ValueKey<String>;
    final partId = key.value.substring('photo-item-'.length);
    final photos = Provider.of<EntityPhotosProvider>(
      tester.element(_partPhoto().first),
      listen: false,
    );
    final photo = photos.photoOf(PhotoOwner.item, partId);
    expect(photo, isNotNull, reason: 'the provider should hold the new photo');
    final served = await tester.runAsync(
      () => http.get(Uri.parse(photo!.url)),
    );
    expect(served!.statusCode, 200, reason: photo!.url);
    expect(served.headers['content-type'], 'image/png');
    expect(served.bodyBytes, _png);
  });
}
