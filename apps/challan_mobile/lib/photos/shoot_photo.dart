import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart' show XFile;
import 'package:core_erp/core/media/photo_crop_screen.dart';
import 'package:flutter/material.dart';

import 'capture_source.dart';
import 'zoom_preview.dart';

/// Takes one photo with the app's camera — zoomable — and lets it be cropped
/// before it is used. Null when nothing was taken.
///
/// The purchase wizard's challan photo and the challan editor's attachments
/// use this instead of the phone's own camera app, so the zoom and the crop
/// are the same everywhere a photo is taken.
Future<XFile?> shootPhoto(BuildContext context, {CaptureSource? source}) {
  // The root navigator: called from a tab's own navigator (the purchase
  // wizard), the camera otherwise opened inside the tab — under the app bar,
  // above the tab bar — instead of over the whole screen.
  return Navigator.of(context, rootNavigator: true).push<XFile>(
    MaterialPageRoute<XFile>(
      fullscreenDialog: true,
      builder: (_) => ShootPhotoScreen(source: source),
    ),
  );
}

/// [cropped] as the photo to use: [shot] itself when the crop kept the whole
/// photo, otherwise a new JPEG beside it — a file, because the screens that
/// list photos draw them from their path.
Future<XFile> photoFromCrop(XFile shot, Uint8List original, Uint8List cropped) async {
  if (identical(cropped, original)) return shot;
  final stem0 = shot.name.contains('.') ? shot.name.substring(0, shot.name.lastIndexOf('.')) : shot.name;
  if (shot.path.isEmpty) {
    // A photo held in memory (no file behind it): the crop stays in memory.
    return XFile.fromData(cropped, name: '$stem0-crop.jpg', mimeType: 'image/jpeg');
  }
  final source = File(shot.path);
  final dir = source.parent.path;
  final stem = shot.name.contains('.') ? shot.name.substring(0, shot.name.lastIndexOf('.')) : shot.name;
  final name = '$stem-crop-${DateTime.now().millisecondsSinceEpoch}.jpg';
  final file = File('$dir/$name');
  await file.writeAsBytes(cropped, flush: true);
  return XFile(file.path, name: name, mimeType: 'image/jpeg', length: cropped.length);
}

/// The photo's media type as the server checks it: `image/jpeg` for a .jpg.
/// Building it as `image/<extension>` gave `image/jpg`, which is not a media
/// type — the server's local store refused every .jpg with 415 (S3 took it,
/// which is why it went unnoticed).
String photoContentType(XFile photo) {
  final declared = photo.mimeType;
  if (declared != null && declared.startsWith('image/') && declared != 'image/jpg') return declared;
  final name = photo.name.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

class ShootPhotoScreen extends StatefulWidget {
  const ShootPhotoScreen({super.key, this.source});

  final CaptureSource? source;

  @override
  State<ShootPhotoScreen> createState() => _ShootPhotoScreenState();
}

class _ShootPhotoScreenState extends State<ShootPhotoScreen> {
  late final CaptureSource _source = widget.source ?? CameraCaptureSource();
  bool _opening = true;
  bool _busy = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _source.open().then((problem) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _problem = problem;
      });
    });
  }

  @override
  void dispose() {
    _source.close();
    super.dispose();
  }

  Future<void> _shoot() async {
    setState(() => _busy = true);
    try {
      final shot = await _source.take();
      if (shot == null || !mounted) return;
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      // The crop is the review: Retake comes back here, Use photo returns it.
      final kept = await PhotoCropScreen.open(context, bytes);
      if (kept == null || !mounted) return;
      final photo = await photoFromCrop(shot, bytes, kept);
      if (mounted) Navigator.of(context).pop(photo);
    } catch (error) {
      if (mounted) setState(() => _problem = 'The photo was not taken: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canShoot = !_opening && !_busy && _problem == null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_opening)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_problem != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _problem!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            )
          else
            ZoomablePreview(source: _source),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(
                  children: [
                    Expanded(
                      // heightFactor 1: an Align with room to grow takes the
                      // screen's whole height, and the row — shutter and all —
                      // sat in the middle of the screen.
                      child: Align(
                        alignment: Alignment.centerLeft,
                        heightFactor: 1,
                        child: IconButton(
                          key: const ValueKey<String>('shoot-close'),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Take photo',
                      child: GestureDetector(
                        key: const ValueKey<String>('shoot-shutter'),
                        onTap: canShoot ? _shoot : null,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          padding: const EdgeInsets.all(5),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: canShoot ? Colors.white : Colors.white38,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
