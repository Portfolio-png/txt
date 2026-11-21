import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart' show XFile;
import 'package:challan_mobile/photos/capture_source.dart';
import 'package:challan_mobile/photos/shoot_photo.dart';
import 'package:challan_mobile/photos/zoom_preview.dart';
import 'package:core_erp/core/media/photo_crop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Zoom before the shot, crop after it — the app's camera, used by the purchase
// wizard, the challan editor and the desktop's photo requests.

class _Camera implements CaptureSource {
  _Camera({this.range, this.shotFile});

  final ({double min, double max})? range;
  final File? shotFile;
  final List<double> zooms = [];

  @override
  Future<String?> open() async => null;
  @override
  Widget preview(BuildContext context) => const ColoredBox(key: ValueKey<String>('fake-preview'), color: Colors.black);
  @override
  Future<XFile?> take() async => XFile(shotFile!.path, name: 'CAP001.jpg');
  @override
  Future<({double min, double max})?> zoomRange() async => range;
  @override
  Future<void> setZoom(double level) async => zooms.add(level);
  @override
  Future<void> close() async {}
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('zoom', () {
    testWidgets('1×, 2× and the lens\'s most; a tap zooms there', (tester) async {
      _phone(tester);
      final camera = _Camera(range: (min: 1.0, max: 8.0));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ZoomablePreview(source: camera))));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('camera-zoom-1×')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('camera-zoom-2×')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('camera-zoom-8×')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('camera-zoom-2×')));
      await tester.pump();
      expect(camera.zooms.last, 2);
      expect(tester.state<ZoomablePreviewState>(find.byType(ZoomablePreview)).zoom, 2);
    });

    testWidgets('a pinch zooms, and stays inside what the lens can do', (tester) async {
      _phone(tester);
      final camera = _Camera(range: (min: 1.0, max: 4.0));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ZoomablePreview(source: camera))));
      await tester.pump();
      final centre = tester.getCenter(find.byType(ZoomablePreview));
      final a = await tester.startGesture(centre - const Offset(40, 0), pointer: 41);
      final b = await tester.startGesture(centre + const Offset(40, 0), pointer: 42);
      await tester.pump();
      for (var i = 1; i <= 10; i += 1) {
        await a.moveTo(centre - Offset(40.0 + i * 8, 0));
        await b.moveTo(centre + Offset(40.0 + i * 8, 0));
        await tester.pump();
      }
      final zoomed = tester.state<ZoomablePreviewState>(find.byType(ZoomablePreview)).zoom;
      expect(zoomed, greaterThan(1.5), reason: 'fingers twice as far apart');
      for (var i = 1; i <= 30; i += 1) {
        await a.moveTo(centre - Offset(120.0 + i * 10, 0));
        await b.moveTo(centre + Offset(120.0 + i * 10, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      expect(tester.state<ZoomablePreviewState>(find.byType(ZoomablePreview)).zoom, 4, reason: 'the lens\'s most');
      expect(camera.zooms.every((z) => z >= 1 && z <= 4), isTrue);
    });

    testWidgets('a camera that cannot zoom shows no zoom buttons', (tester) async {
      _phone(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ZoomablePreview(source: _Camera()))));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('camera-zoom-1×')), findsNothing);
    });
  });

  group('shoot, then crop', () {
    late Directory dir;
    late File shot;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('paper-shoot-');
      final image = img.Image(width: 400, height: 200);
      shot = File('${dir.path}/CAP001.jpg')..writeAsBytesSync(img.encodeJpg(image));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Future<XFile?>> open(WidgetTester tester, _Camera camera) async {
      _phone(tester);
      late Future<XFile?> result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = shootPhoto(context, source: camera),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await _settle(tester);
      // The shot is read from disk: real I/O, which only finishes in runAsync.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey<String>('shoot-shutter')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      // Built in that frame, the crop screen then measures the photo: real
      // decoding, given real time.
      await _settle(tester);
      await _settle(tester);
      expect(find.byType(PhotoCropScreen), findsOneWidget, reason: 'the shot opens in the crop, which is its review');
      return result;
    }

    testWidgets('the shutter is at the bottom of the screen', (tester) async {
      _phone(tester);
      await tester.pumpWidget(MaterialApp(home: ShootPhotoScreen(source: _Camera(shotFile: shot))));
      await tester.pump();
      final shutter = tester.getCenter(find.byKey(const ValueKey<String>('shoot-shutter')));
      expect(shutter.dy, greaterThan(960 * 0.8), reason: 'it sat in the middle once (at ${shutter.dy})');
    });

    testWidgets('used as taken: the shot itself comes back', (tester) async {
      final result = await open(tester, _Camera(shotFile: shot));
      await tester.tap(find.byKey(const ValueKey<String>('crop-use')));
      await _settle(tester);
      expect((await tester.runAsync(() => result.timeout(const Duration(seconds: 5))))!.path, shot.path);
    });

    testWidgets('cropped: a new JPEG beside the shot, smaller, on disk', (tester) async {
      final result = await open(tester, _Camera(shotFile: shot));
      await tester.drag(find.byKey(const ValueKey<String>('crop-handle-tl')), const Offset(200, 0));
      await tester.pump();
      // The crop runs in an isolate and the file is written to disk: both real.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey<String>('crop-use')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      // Until the crop (an isolate) and the file write (disk) are done and
      // both screens have closed — not a fixed time.
      for (var i = 0; i < 60 && find.byType(PhotoCropScreen).evaluate().isNotEmpty; i += 1) {
        await _settle(tester);
      }
      await _settle(tester);
      final photo = (await tester.runAsync(() => result.timeout(const Duration(seconds: 5))))!;
      expect(photo.path, isNot(shot.path));
      expect(File(photo.path).parent.path, dir.path, reason: 'beside the shot');
      final Uint8List bytes = await tester.runAsync(() => File(photo.path).readAsBytes()) as Uint8List;
      expect(img.decodeImage(bytes)!.width, lessThan(400));
    });

    testWidgets('Retake goes back to the camera, and nothing is returned yet', (tester) async {
      final result = await open(tester, _Camera(shotFile: shot));
      await tester.tap(find.byKey(const ValueKey<String>('crop-back')));
      await _settle(tester);
      expect(find.byKey(const ValueKey<String>('shoot-shutter')), findsOneWidget);
      var done = false;
      result.then((_) => done = true);
      await tester.pump();
      expect(done, isFalse);
    });
  });

  test('a .jpg is image/jpeg — "image/jpg" was refused by the server\'s local store', () {
    expect(photoContentType(XFile('/x/CAP1.jpg', name: 'CAP1.jpg')), 'image/jpeg');
    expect(photoContentType(XFile('/x/CAP1-crop-9.jpg', name: 'CAP1-crop-9.jpg', mimeType: 'image/jpeg')), 'image/jpeg');
    expect(photoContentType(XFile('/x/a.JPEG', name: 'a.JPEG')), 'image/jpeg');
    expect(photoContentType(XFile('/x/a.png', name: 'a.png')), 'image/png');
    expect(photoContentType(XFile('/x/a.jpg', name: 'a.jpg', mimeType: 'image/jpg')), 'image/jpeg');
  });
}
