import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A photo made ready for the store: the photo, no longer than [photoEdge] on
/// its long side, and a small copy for lists and grids.
///
/// A phone shot is 3–8 MB; shrunk it is a few hundred KB, and its thumbnail a
/// few KB. Everything that shows a part in a list loads the thumbnail; only
/// the big view loads the photo. That is most of what the store costs — the
/// bytes kept and the bytes sent — cut by ten or more.
@immutable
class ShrunkPhoto {
  const ShrunkPhoto({
    required this.photo,
    required this.thumb,
    required this.width,
    required this.height,
    required this.contentType,
  });

  final Uint8List photo;
  final Uint8List thumb;
  final int width;
  final int height;

  /// `image/jpeg`, unless the photo was passed through as it came.
  final String contentType;
}

/// The long side of a stored photo: sharp on any screen, at a zoom.
const int photoEdge = 2048;

/// The long side of a thumbnail: a grid cell, a list's slot.
const int thumbEdge = 320;

const int _photoQuality = 82;
const int _thumbQuality = 72;

/// Shrinks [bytes] away from the UI thread. Null when they are not a picture
/// this can read (the caller uploads them as they are, as before).
Future<ShrunkPhoto?> shrinkPhoto(Uint8List bytes, {String? contentType}) =>
    compute(_shrink, (bytes: bytes, contentType: contentType));

/// The same, on this thread — for tests, and callers already off the UI.
@visibleForTesting
ShrunkPhoto? shrinkPhotoNow(Uint8List bytes, {String? contentType}) =>
    _shrink((bytes: bytes, contentType: contentType));

ShrunkPhoto? _shrink(({Uint8List bytes, String? contentType}) input) {
  final decoded = img.decodeImage(input.bytes);
  if (decoded == null) return null;
  // A phone's JPEG says which way up it was held; turned here, so the
  // stored photo needs no reader to know.
  final exif = decoded.exif.imageIfd;
  final turned = exif.hasOrientation && exif.orientation != 1;
  final upright = turned ? img.bakeOrientation(decoded) : decoded;
  final small = _fit(upright, thumbEdge);
  final thumb = img.encodeJpg(_flat(small), quality: _thumbQuality);

  final isJpeg = input.contentType == 'image/jpeg' ||
      (input.bytes.length > 2 && input.bytes[0] == 0xff && input.bytes[1] == 0xd8);
  final longSide = upright.width > upright.height ? upright.width : upright.height;
  // Already small and already a JPEG: re-encoding only loses quality.
  if (isJpeg && !turned && longSide <= photoEdge && input.bytes.length <= 600 * 1024) {
    return ShrunkPhoto(
      photo: input.bytes,
      thumb: thumb,
      width: upright.width,
      height: upright.height,
      contentType: 'image/jpeg',
    );
  }
  final fitted = _fit(upright, photoEdge);
  return ShrunkPhoto(
    photo: img.encodeJpg(_flat(fitted), quality: _photoQuality),
    thumb: thumb,
    width: fitted.width,
    height: fitted.height,
    contentType: 'image/jpeg',
  );
}

img.Image _fit(img.Image image, int edge) {
  if (image.width <= edge && image.height <= edge) return image;
  return image.width >= image.height
      ? img.copyResize(image, width: edge, interpolation: img.Interpolation.average)
      : img.copyResize(image, height: edge, interpolation: img.Interpolation.average);
}

/// A JPEG has no transparency: a cut-out PNG goes onto white, not black.
img.Image _flat(img.Image image) {
  if (!image.hasAlpha) return image;
  final white = img.Image(width: image.width, height: image.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  return img.compositeImage(white, image);
}
