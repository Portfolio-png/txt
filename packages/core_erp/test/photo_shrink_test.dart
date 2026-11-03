import 'dart:convert';
import 'dart:typed_data';

import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/core/services/photo_shrink.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

// A photo is shrunk before it is stored, and sent with a small copy for
// lists: what keeps the store's bytes — kept and sent — down.

Uint8List _jpeg(int width, int height) => img.encodeJpg(
  img.Image(width: width, height: height)..clear(img.ColorRgb8(90, 120, 200)),
  quality: 95,
);

void main() {
  test('a big photo comes down to 2048 on its long side, its thumbnail to 320', () {
    final shrunk = shrinkPhotoNow(_jpeg(4000, 3000))!;
    expect(shrunk.width, 2048);
    expect(shrunk.height, 1536);
    expect(shrunk.contentType, 'image/jpeg');
    final photo = img.decodeJpg(shrunk.photo)!;
    expect((photo.width, photo.height), (2048, 1536));
    final thumb = img.decodeJpg(shrunk.thumb)!;
    expect((thumb.width, thumb.height), (320, 240));
    expect(shrunk.thumb.length, lessThan(shrunk.photo.length));
  });

  test('a tall photo is fitted by its height', () {
    final shrunk = shrinkPhotoNow(_jpeg(1000, 3000))!;
    expect((shrunk.width, shrunk.height), (683, 2048));
  });

  test('a small JPEG is kept as it is; a PNG becomes a JPEG on white', () {
    final small = _jpeg(800, 600);
    final kept = shrinkPhotoNow(small, contentType: 'image/jpeg')!;
    expect(identical(kept.photo, small), isTrue);
    expect((kept.width, kept.height), (800, 600));

    final cutOut = img.Image(width: 400, height: 300, numChannels: 4)
      ..clear(img.ColorRgba8(0, 0, 0, 0));
    final png = shrinkPhotoNow(img.encodePng(cutOut), contentType: 'image/png')!;
    expect(png.contentType, 'image/jpeg');
    final pixel = img.decodeJpg(png.photo)!.getPixel(10, 10);
    expect(pixel.r, greaterThan(240), reason: 'transparent goes white, not black');
  });

  test('what is not a picture is left alone', () {
    expect(shrinkPhotoNow(Uint8List.fromList(utf8.encode('not a picture'))), isNull);
  });

  test('a JPEG the decoder chokes on is sent as it is, not a failure', () {
    final whole = _jpeg(400, 300);
    final cut = Uint8List.sublistView(whole, 0, whole.length ~/ 3);
    expect(() => shrinkPhotoNow(cut, contentType: 'image/jpeg'), returnsNormally);
  });

  test('store sends the shrunk photo and its thumbnail, each to its own URL', () async {
    final calls = <String, http.Request>{};
    Map<String, dynamic>? intent;
    final api = MockClient((request) async {
      calls[request.url.path] = request;
      switch (request.url.path) {
        case '/api/assets/upload-intent':
          intent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'intent': {
                'alreadyUploaded': false,
                'upload': {
                  'uploadSessionId': 's1',
                  'objectKey': 'items/item-7/p.jpg',
                  'uploadUrl': 'http://store/p',
                  'headers': {'Content-Type': 'image/jpeg', 'Cache-Control': 'immutable'},
                  'thumbnail': {
                    'objectKey': 'items/item-7/thumbs/p.jpg',
                    'uploadUrl': 'http://store/t',
                    'headers': {'Content-Type': 'image/jpeg', 'Cache-Control': 'immutable'},
                  },
                },
              },
            }),
            201,
          );
        case '/api/assets/upload-complete':
          return http.Response(
            jsonEncode({'success': true, 'asset': {'id': 41, 'readUrl': 'http://store/p?sig'}}),
            200,
          );
      }
      return http.Response('{}', 404);
    });
    final puts = <String, http.Request>{};
    final store = MockClient((request) async {
      puts[request.url.path] = request;
      return http.Response('', 200);
    });
    final repository = EntityPhotoRepository(baseUrl: 'http://api', client: api, uploadClient: store);

    final asset = await repository.store(
      PhotoOwner.item,
      '7',
      XFile.fromData(_jpeg(3000, 2000), path: '/tmp/front view.png'),
      isPrimary: false,
    );
    expect(asset['id'], 41);

    expect(intent!['isPrimary'], isFalse);
    expect(intent!['fileName'], 'front view.jpg');
    expect(intent!['contentType'], 'image/jpeg');
    expect((intent!['width'], intent!['height']), (2048, 1365));
    final thumbnail = intent!['thumbnail'] as Map<String, dynamic>;

    final photo = puts['/p']!;
    final thumb = puts['/t']!;
    expect(intent!['sizeBytes'], photo.bodyBytes.length);
    expect(thumbnail['sizeBytes'], thumb.bodyBytes.length);
    expect(img.decodeJpg(thumb.bodyBytes)!.width, 320);
    // The headers the URLs were signed for go with each PUT.
    expect(photo.headers['Cache-Control'], 'immutable');
    expect(thumb.headers['Cache-Control'], 'immutable');
    expect(calls.keys, contains('/api/assets/upload-complete'));
  });

  test('the limit comes back as its code', () async {
    final api = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'success': false,
          'error': 'A part keeps up to 5 photos - remove one first.',
          'code': 'photo_limit',
        }),
        409,
      ),
    );
    final repository = EntityPhotoRepository(baseUrl: 'http://api', client: api);
    await expectLater(
      repository.store(PhotoOwner.item, '7', XFile.fromData(_jpeg(100, 100), name: 'a.jpg')),
      throwsA(isA<EntityPhotoException>().having((e) => e.code, 'code', 'photo_limit')),
    );
  });
}
