import 'dart:typed_data';

import 'package:core_erp/core/media/photo_crop.dart';
import 'package:core_erp/core/media/photo_crop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Cropping a photo just taken on the phone.

/// 400 × 200: red on the left half, blue on the right.
Uint8List _halves({int? orientation}) {
  final image = img.Image(width: 400, height: 200);
  for (var y = 0; y < 200; y += 1) {
    for (var x = 0; x < 400; x += 1) {
      image.setPixelRgb(x, y, x < 200 ? 255 : 0, 0, x < 200 ? 0 : 255);
    }
  }
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

img.Image _decode(Uint8List bytes) => img.bakeOrientation(img.decodeImage(bytes)!);

void main() {
  group('cropPhoto', () {
    test('the right half is the right half', () async {
      final out = _decode(await cropPhoto(_halves(), const Rect.fromLTRB(0.5, 0, 1, 1)));
      expect(out.width, 200);
      expect(out.height, 200);
      final centre = out.getPixel(100, 100);
      expect(centre.b, greaterThan(200), reason: 'blue');
      expect(centre.r, lessThan(60));
    });

    test('the whole photo comes back untouched, not re-encoded', () async {
      final bytes = _halves();
      expect(identical(await cropPhoto(bytes, kWholePhoto), bytes), isTrue);
    });

    test('a photo stored sideways (EXIF 6) is cut as it is shown, upright', () async {
      // Shown upright it is 200 wide and 400 tall: red on top, blue below.
      final bytes = _halves(orientation: 6);
      final out = _decode(await cropPhoto(bytes, const Rect.fromLTRB(0, 0, 1, 0.5)));
      expect(out.width, 200);
      expect(out.height, 200);
      expect(out.getPixel(100, 100).r, greaterThan(200), reason: 'the top half, which is red');
    });
  });

  group('PhotoCropScreen', () {
    Future<(PhotoCropScreenState, Future<Uint8List?>)> open(WidgetTester tester, Uint8List bytes) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      late Future<Uint8List?> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = PhotoCropScreen.open(context, bytes),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      // The photo is measured before the frame can be drawn; the page
      // transition is waited out, or a drag lands on the page below.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      return (tester.state<PhotoCropScreenState>(find.byType(PhotoCropScreen)), result);
    }

    testWidgets('a corner dragged in crops; Reset puts the whole photo back', (tester) async {
      final (screen, _) = await open(tester, _halves());
      expect(find.byKey(const ValueKey<String>('crop-handle-tl')), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey<String>('crop-reset'))).onPressed, isNull,
          reason: 'drawn, disabled, with nothing to undo');

      await tester.drag(find.byKey(const ValueKey<String>('crop-handle-tl')), const Offset(100, 40));
      await tester.pump();
      expect(screen.crop.left, greaterThan(0.1));
      expect(screen.crop.top, greaterThan(0.1));
      expect(screen.crop.right, 1);

      await tester.tap(find.byKey(const ValueKey<String>('crop-reset')));
      await tester.pump();
      expect(screen.crop, kWholePhoto);
    });

    testWidgets('the frame moves whole and stays on the photo; it never shrinks below a tenth', (tester) async {
      final (screen, _) = await open(tester, _halves());
      await tester.drag(find.byKey(const ValueKey<String>('crop-handle-br')), const Offset(-2000, -2000));
      await tester.pump();
      expect(screen.crop.width, closeTo(0.1, 0.001));
      expect(screen.crop.height, closeTo(0.1, 0.001));

      await tester.drag(find.byKey(const ValueKey<String>('crop-frame')), const Offset(5000, 5000));
      await tester.pump();
      expect(screen.crop.right, closeTo(1, 0.001));
      expect(screen.crop.bottom, closeTo(1, 0.001));
    });

    testWidgets('Use photo answers the cropped photo; uncropped, the very bytes', (tester) async {
      final bytes = _halves();
      var (_, result) = await open(tester, bytes);
      await tester.tap(find.byKey(const ValueKey<String>('crop-use')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(identical(await result, bytes), isTrue);

      (_, result) = await open(tester, bytes);
      await tester.drag(find.byKey(const ValueKey<String>('crop-handle-tl')), const Offset(200, 0));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('crop-use')));
      // The crop runs in an isolate: wait until the screen has closed, not a
      // fixed time — a busy machine (the whole suite at once) is slower.
      for (var i = 0; i < 60 && find.byType(PhotoCropScreen).evaluate().isNotEmpty; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump(const Duration(milliseconds: 500));
      }
      final cropped = await result;
      expect(cropped, isNotNull);
      expect(_decode(cropped!).width, lessThan(400));
    });

    testWidgets('Retake answers nothing', (tester) async {
      final (_, result) = await open(tester, _halves());
      await tester.tap(find.byKey(const ValueKey<String>('crop-back')));
      await tester.pump();
      expect(await result, isNull);
    });
  });
}
