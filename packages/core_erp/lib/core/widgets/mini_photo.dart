import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/entity_photos.dart';
import '../theme/soft_erp_theme.dart';

/// A record's photo, small: a part, a die, a machine, a company's logo, a
/// person. Empty, it is the button that adds one; with one, a tap shows it
/// large with Replace and Remove. A record that does not exist yet has
/// nowhere to keep a photo, so the button is drawn disabled and says why.
///
/// Drawn only where an [EntityPhotosProvider] is provided; elsewhere it takes
/// no space.
class MiniPhoto extends StatelessWidget {
  const MiniPhoto({
    super.key,
    required this.owner,
    required this.id,
    this.size = 36,
    this.what = 'photo',
    this.fallbackUrl,
    this.disabledReason,
  });

  /// [PhotoOwner] — what kind of record.
  final String owner;

  /// The record, or null when it is not saved yet.
  final String? id;
  final double size;

  /// What the photo is, for the tooltips: "logo", "die photo".
  final String what;

  /// A photo kept the old way (a URL on the record), shown until one is
  /// uploaded here.
  final String? fallbackUrl;

  /// Why there is no record yet ("Save the part first").
  final String? disabledReason;

  /// Overrides the file picker, for tests.
  @visibleForTesting
  static Future<XFile?> Function()? debugPickFile;

  /// Whether photos are kept here — for a header that must leave a photo's
  /// width only when the rows below draw one.
  static bool isAvailable(BuildContext context) {
    try {
      Provider.of<EntityPhotosProvider>(context, listen: false);
      return true;
    } on ProviderNotFoundException {
      return false;
    }
  }

  static EntityPhotosProvider? _photosOf(BuildContext context) {
    try {
      return Provider.of<EntityPhotosProvider>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  static Future<XFile?> _pick() {
    final override = debugPickFile;
    if (override != null) return override();
    // Extensions only: declaring mimeTypes too makes the macOS picker refuse
    // the type group outright.
    return openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp']),
      ],
    );
  }

  static void _say(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        backgroundColor: error ? SoftErpTheme.dangerText : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photosOf(context);
    if (photos == null) return const SizedBox.shrink();
    final id = this.id;
    final keyId = id ?? 'none';
    if (id == null) {
      return Tooltip(
        message: disabledReason ?? 'Save it first to add a $what',
        child: _frame(
          key: ValueKey<String>('photo-$owner-$keyId'),
          child: const Icon(
            Icons.add_a_photo_outlined,
            size: 18,
            color: SoftErpTheme.borderStrong,
          ),
        ),
      );
    }

    photos.request(owner, id);
    final photo = photos.photoOf(owner, id);
    final url = photo?.url ?? _fallback;
    final busy = photos.isBusy(owner, id);

    Future<void> upload() async {
      final file = await _pick();
      if (file == null || !context.mounted) return;
      final error = await photos.upload(owner, id, file);
      if (!context.mounted) return;
      _say(context, error ?? 'Photo saved.', error: error != null);
    }

    return Tooltip(
      message: url == null ? 'Add $what' : 'Open $what',
      child: InkWell(
        key: ValueKey<String>('photo-$owner-$id'),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
        onTap: busy
            ? null
            : url == null
            ? upload
            : () => _open(context, photos, id, url, upload),
        child: _frame(
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : url == null
              ? const Icon(
                  Icons.add_a_photo_outlined,
                  size: 18,
                  color: SoftErpTheme.accent,
                )
              : _image(url, size),
        ),
      ),
    );
  }

  String? get _fallback {
    final url = fallbackUrl?.trim() ?? '';
    return url.startsWith('http') ? url : null;
  }

  Widget _frame({Key? key, required Widget child}) => Container(
    key: key,
    width: size,
    height: size,
    alignment: Alignment.center,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: SoftErpTheme.shellSurface,
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
      border: Border.all(color: SoftErpTheme.border),
    ),
    child: child,
  );

  static Widget _image(String url, double size, {BoxFit fit = BoxFit.cover}) {
    return Image.network(
      url,
      width: size,
      height: size,
      fit: fit,
      // A link that no longer works is an empty slot, not a red box.
      errorBuilder: (context, error, stack) => Icon(
        Icons.broken_image_outlined,
        size: size < 60 ? 18 : 40,
        color: SoftErpTheme.textMuted,
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    EntityPhotosProvider photos,
    String id,
    String url,
    Future<void> Function() upload,
  ) async {
    final hasStored = photos.photoOf(owner, id) != null;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SizedBox(
          width: 420,
          height: 420,
          child: _image(url, 420, fit: BoxFit.contain),
        ),
        actions: [
          if (hasStored)
            TextButton.icon(
              key: const ValueKey<String>('photo-remove'),
              onPressed: () => Navigator.of(dialogContext).pop('remove'),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Remove', style: TextStyle(fontSize: 14)),
            ),
          TextButton.icon(
            key: const ValueKey<String>('photo-replace'),
            onPressed: () => Navigator.of(dialogContext).pop('replace'),
            icon: const Icon(Icons.upload_rounded),
            label: const Text('Replace', style: TextStyle(fontSize: 14)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'replace') {
      await upload();
    } else if (choice == 'remove') {
      final error = await photos.remove(owner, id);
      if (!context.mounted) return;
      _say(context, error ?? 'Photo removed.', error: error != null);
    }
  }
}
