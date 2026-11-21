import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The whole photo, as a crop: left, top, right, bottom as fractions of the
/// photo's width and height, upright as it is shown.
const Rect kWholePhoto = Rect.fromLTRB(0, 0, 1, 1);

/// Whether [crop] keeps the photo as it is.
bool isWholePhoto(Rect crop) =>
    crop.left <= 0.001 && crop.top <= 0.001 && crop.right >= 0.999 && crop.bottom >= 0.999;

/// [bytes] cut to [crop], as a JPEG.
///
/// [crop] is in fractions of the photo as it is SHOWN — upright, its EXIF
/// orientation applied (Flutter applies it when it draws the photo) — so the
/// orientation is baked in before cutting, or a portrait shot stored sideways
/// would be cut in the wrong place. The whole photo comes back untouched,
/// never re-encoded. Decoding a camera photo takes a moment, so it runs off
/// the UI thread.
Future<Uint8List> cropPhoto(Uint8List bytes, Rect crop, {int quality = 88}) async {
  if (isWholePhoto(crop)) return bytes;
  return compute(_crop, _CropJob(bytes, crop.left, crop.top, crop.right, crop.bottom, quality));
}

class _CropJob {
  const _CropJob(this.bytes, this.left, this.top, this.right, this.bottom, this.quality);

  final Uint8List bytes;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final int quality;
}

Uint8List _crop(_CropJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) throw const FormatException('That photo could not be read.');
  final upright = img.bakeOrientation(decoded);
  final width = upright.width;
  final height = upright.height;
  final x = (job.left.clamp(0.0, 1.0) * width).round().clamp(0, width - 1);
  final y = (job.top.clamp(0.0, 1.0) * height).round().clamp(0, height - 1);
  final right = (job.right.clamp(0.0, 1.0) * width).round().clamp(x + 1, width);
  final bottom = (job.bottom.clamp(0.0, 1.0) * height).round().clamp(y + 1, height);
  final cut = img.copyCrop(upright, x: x, y: y, width: right - x, height: bottom - y);
  return Uint8List.fromList(img.encodeJpg(cut, quality: job.quality));
}
