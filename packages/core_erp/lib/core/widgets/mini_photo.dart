import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/entity_photos.dart';
import '../services/photo_requests.dart';
import '../theme/soft_erp_theme.dart';

/// A record's photo, small: a part, a die, a machine, a company's logo, a
/// person. Empty, a tap asks how to add one — take it on the phone, or pick a
/// file from this PC; with one, a tap shows it large with Retake on phone,
/// Replace and Remove. While the phone has the job the slot says so, and a tap
/// takes it back. A record that does not exist yet has nowhere to keep a
/// photo, so the button is drawn disabled and says why.
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
    this.label,
    this.note,
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

  /// Words under the camera while there is no photo ("Photo"), for a row
  /// where a bare 36px icon went unnoticed. Needs a [size] of about 48 or
  /// more.
  final String? label;

  /// Where this slot sits, shown on the phone above the camera ("for part
  /// HH1") — the record's own details come from the server.
  final String? note;

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

  static PhotoRequestsProvider? _requestsOf(BuildContext context) {
    try {
      return Provider.of<PhotoRequestsProvider>(context);
    } on ProviderNotFoundException {
      return null;
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
          // Muted, not border-faint: a slot that is not usable yet still has
          // to be seen, or nobody knows photos are kept here at all.
          child: _empty(SoftErpTheme.textMuted),
        ),
      );
    }

    photos.request(owner, id);
    final photo = photos.photoOf(owner, id);
    final url = photo?.url ?? _fallback;
    final busy = photos.isBusy(owner, id);
    final requests = _requestsOf(context);
    final onPhone = requests?.pendingFor(owner, id) != null;

    Future<void> upload() async {
      final file = await _pick();
      if (file == null || !context.mounted) return;
      final error = await photos.upload(owner, id, file);
      if (!context.mounted) return;
      _say(context, error ?? 'Photo saved.', error: error != null);
    }

    Future<void> sendToPhone() async {
      final error = await requests!.ask(owner, id, context: note ?? '');
      if (!context.mounted) return;
      _say(
        context,
        error ?? 'Sent to your phone — it opens the camera with this $what.',
        error: error != null,
      );
    }

    Future<void> takeBack() async {
      final error = await requests!.cancel(owner, id);
      if (!context.mounted) return;
      _say(context, error ?? 'Taken back from your phone.', error: error != null);
    }

    return Tooltip(
      message: onPhone
          ? 'Waiting for your phone — click to take it back'
          : (url == null ? 'Add $what' : 'Open $what'),
      child: InkWell(
        key: ValueKey<String>('photo-$owner-$id'),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
        onTap: busy
            ? null
            : onPhone
            ? takeBack
            : url == null
            ? () => _choose(context, requests, upload, sendToPhone)
            : () => _open(context, photos, requests, id, url, upload, sendToPhone),
        child: _frame(
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : onPhone
              ? _waiting()
              : url == null
              ? _empty(SoftErpTheme.accent)
              : _image(url, size),
        ),
      ),
    );
  }

  /// The job is on the phone: a phone, and "On phone" where there is room.
  Widget _waiting() {
    const icon = Icons.phone_iphone_rounded;
    const colour = SoftErpTheme.warningText;
    if (label == null) return const Icon(icon, size: 18, color: colour);
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: colour),
        SizedBox(height: 2),
        Text(
          'On phone',
          maxLines: 1,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colour),
        ),
      ],
    );
  }

  /// How to add the photo: on the phone, or a file from this PC. Asked every
  /// time — bulk entry is mostly the phone, but a file already on the PC
  /// should not need a phone at all.
  Future<void> _choose(
    BuildContext context,
    PhotoRequestsProvider? requests,
    Future<void> Function() upload,
    Future<void> Function() sendToPhone,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Add the $what'),
        children: [
          _ChoiceTile(
            key: const ValueKey<String>('photo-take-on-phone'),
            icon: Icons.phone_iphone_rounded,
            title: 'Take on phone',
            detail: requests == null
                ? 'Phone photos are not set up in this app.'
                : 'Your phone opens the camera, with this record\'s details on it.',
            onTap: requests == null ? null : () => Navigator.of(dialogContext).pop('phone'),
          ),
          _ChoiceTile(
            key: const ValueKey<String>('photo-choose-file'),
            icon: Icons.folder_open_rounded,
            title: 'Choose a file from this PC',
            detail: 'PNG, JPG or WebP.',
            onTap: () => Navigator.of(dialogContext).pop('file'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'phone') await sendToPhone();
    if (choice == 'file') await upload();
  }

  String? get _fallback {
    final url = fallbackUrl?.trim() ?? '';
    return url.startsWith('http') ? url : null;
  }

  /// The camera, and the [label] under it when there is one.
  Widget _empty(Color color) {
    const icon = Icons.add_a_photo_outlined;
    final label = this.label;
    if (label == null) return Icon(icon, size: 18, color: color);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
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
    PhotoRequestsProvider? requests,
    String id,
    String url,
    Future<void> Function() upload,
    Future<void> Function() sendToPhone,
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
          if (requests != null)
            TextButton.icon(
              key: const ValueKey<String>('photo-retake-on-phone'),
              onPressed: () => Navigator.of(dialogContext).pop('phone'),
              icon: const Icon(Icons.phone_iphone_rounded),
              label: const Text('Retake on phone', style: TextStyle(fontSize: 14)),
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
    } else if (choice == 'phone') {
      await sendToPhone();
    } else if (choice == 'remove') {
      final error = await photos.remove(owner, id);
      if (!context.mounted) return;
      _say(context, error ?? 'Photo removed.', error: error != null);
    }
  }
}

/// One way to add a photo, in [MiniPhoto]'s chooser: drawn disabled with the
/// reason when it cannot be used, never left out.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(icon, color: enabled ? SoftErpTheme.accent : SoftErpTheme.textMuted),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      subtitle: Text(detail, style: const TextStyle(fontSize: 14)),
    );
  }
}
