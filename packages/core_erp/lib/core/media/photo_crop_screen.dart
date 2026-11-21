import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/soft_erp_theme.dart';
import 'photo_crop.dart';

/// Crop a photo just taken: a frame over it, dragged by its corners or moved
/// whole. Answers the photo to use — cropped, or the very bytes given when the
/// frame was left on the whole photo — or null for [backLabel] (Retake).
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({
    super.key,
    required this.bytes,
    this.useLabel = 'Use photo',
    this.backLabel = 'Retake',
  });

  final Uint8List bytes;
  final String useLabel;
  final String backLabel;

  static Future<Uint8List?> open(
    BuildContext context,
    Uint8List bytes, {
    String useLabel = 'Use photo',
    String backLabel = 'Retake',
  }) {
    // Over the whole screen, whichever navigator it is asked from.
    return Navigator.of(context, rootNavigator: true).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        fullscreenDialog: true,
        builder: (_) => PhotoCropScreen(bytes: bytes, useLabel: useLabel, backLabel: backLabel),
      ),
    );
  }

  @override
  State<PhotoCropScreen> createState() => PhotoCropScreenState();
}

/// The smallest the frame goes, as a share of each side.
const double _minSide = 0.1;

class PhotoCropScreenState extends State<PhotoCropScreen> {
  Rect _crop = kWholePhoto;
  Size? _imageSize;
  bool _working = false;
  String? _error;

  /// The frame, in fractions of the photo — for tests.
  Rect get crop => _crop;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _imageSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble()));
      frame.image.dispose();
    } catch (_) {
      if (mounted) setState(() => _error = 'That photo could not be shown.');
    }
  }

  Future<void> _use() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final out = await cropPhoto(widget.bytes, _crop);
      if (mounted) Navigator.of(context).pop(out);
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = 'Could not crop it: $error';
        });
      }
    }
  }

  /// Moves one corner by a drag of [delta] across a photo shown at [shown].
  void _dragCorner(Alignment corner, Offset delta, Size shown) {
    final dx = delta.dx / shown.width;
    final dy = delta.dy / shown.height;
    var left = _crop.left;
    var top = _crop.top;
    var right = _crop.right;
    var bottom = _crop.bottom;
    if (corner.x < 0) {
      left = (left + dx).clamp(0.0, right - _minSide);
    } else {
      right = (right + dx).clamp(left + _minSide, 1.0);
    }
    if (corner.y < 0) {
      top = (top + dy).clamp(0.0, bottom - _minSide);
    } else {
      bottom = (bottom + dy).clamp(top + _minSide, 1.0);
    }
    setState(() => _crop = Rect.fromLTRB(left, top, right, bottom));
  }

  /// Moves the whole frame, kept on the photo.
  void _dragFrame(Offset delta, Size shown) {
    final dx = (delta.dx / shown.width).clamp(-_crop.left, 1.0 - _crop.right);
    final dy = (delta.dy / shown.height).clamp(-_crop.top, 1.0 - _crop.bottom);
    setState(() => _crop = _crop.shift(Offset(dx, dy)));
  }

  @override
  Widget build(BuildContext context) {
    final cropped = !isWholePhoto(_crop);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Drag the corners to crop',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: _imageSize == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 15)),
                    )
                  : LayoutBuilder(builder: (context, constraints) => _editor(constraints.biggest)),
            ),
            if (_error != null && _imageSize != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 14)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey<String>('crop-back'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _working ? null : () => Navigator.of(context).pop(),
                      child: Text(widget.backLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Drawn always, disabled with nothing to undo — not hidden.
                  TextButton(
                    key: const ValueKey<String>('crop-reset'),
                    onPressed: _working || !cropped ? null : () => setState(() => _crop = kWholePhoto),
                    child: Text(
                      'Reset',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _working || !cropped ? Colors.white38 : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey<String>('crop-use'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SoftErpTheme.accent,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _working || _imageSize == null ? null : _use,
                      child: _working
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(widget.useLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The photo fitted to [space], with the frame over it.
  Widget _editor(Size space) {
    final image = _imageSize!;
    // Inset from the screen's edges so every corner handle is wholly on
    // screen — and off the edge, where Android's back swipe starts.
    const inset = 28.0;
    final room = Size(space.width - 2 * inset, space.height - 2 * inset);
    final scale = (room.width / image.width) < (room.height / image.height)
        ? room.width / image.width
        : room.height / image.height;
    final shown = Size(image.width * scale, image.height * scale);
    final origin = Offset((space.width - shown.width) / 2, (space.height - shown.height) / 2);
    final frame = Rect.fromLTRB(
      origin.dx + _crop.left * shown.width,
      origin.dy + _crop.top * shown.height,
      origin.dx + _crop.right * shown.width,
      origin.dy + _crop.bottom * shown.height,
    );
    const handle = 48.0;

    Widget corner(Alignment at, String key) {
      final point = Offset(
        at.x < 0 ? frame.left : frame.right,
        at.y < 0 ? frame.top : frame.bottom,
      );
      return Positioned(
        left: point.dx - handle / 2,
        top: point.dy - handle / 2,
        width: handle,
        height: handle,
        child: GestureDetector(
          key: ValueKey<String>(key),
          behavior: HitTestBehavior.opaque,
          onPanUpdate: _working ? null : (d) => _dragCorner(at, d.delta, shown),
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: SoftErpTheme.accent, width: 3),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fromRect(
          rect: origin & shown,
          child: Image.memory(widget.bytes, fit: BoxFit.fill, gaplessPlayback: true),
        ),
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _FramePainter(photo: origin & shown, frame: frame))),
        ),
        Positioned.fromRect(
          rect: frame.deflate(handle / 2 < frame.shortestSide / 2 ? handle / 2 : 0),
          child: GestureDetector(
            key: const ValueKey<String>('crop-frame'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: _working ? null : (d) => _dragFrame(d.delta, shown),
          ),
        ),
        corner(Alignment.topLeft, 'crop-handle-tl'),
        corner(Alignment.topRight, 'crop-handle-tr'),
        corner(Alignment.bottomLeft, 'crop-handle-bl'),
        corner(Alignment.bottomRight, 'crop-handle-br'),
      ],
    );
  }
}

/// Dims the photo outside the frame, draws the frame and its thirds.
class _FramePainter extends CustomPainter {
  const _FramePainter({required this.photo, required this.frame});

  final Rect photo;
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(photo)
      ..addRect(frame);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.55));
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(frame, line);
    final thin = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i += 1) {
      final x = frame.left + frame.width * i / 3;
      final y = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), thin);
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), thin);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.photo != photo || old.frame != frame;
}
