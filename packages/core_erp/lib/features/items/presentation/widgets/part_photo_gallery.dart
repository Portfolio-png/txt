import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/entity_photos.dart';
import '../../../../core/services/photo_requests.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/mini_photo.dart';

/// A part's photos — its views: front, side, a section, a detail — up to
/// [maxPartPhotos]. The main one, big; the others in a grid of slots; an
/// empty slot takes a photo on the phone or a file from this computer.
///
/// Nothing changes until Save. A file picked here is held in memory and
/// shown from it; Save uploads it (shrunk, with its thumbnail), removes what
/// was crossed out and sets the main photo, in that order. × or Esc leaves
/// everything as it was. A shot from the phone is a real upload the moment
/// it is taken: it appears here live, marked "From phone", and its own ×
/// removes it.
///
/// Answers true when something was saved.
Future<bool> showPartPhotoGallery(
  BuildContext context, {
  required String itemId,
  required String partName,
  int? openOn,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PartPhotoGallery(itemId: itemId, partName: partName, openOn: openOn),
  );
  return saved == true;
}

class PartPhotoGallery extends StatefulWidget {
  const PartPhotoGallery({
    super.key,
    required this.itemId,
    required this.partName,
    this.openOn,
  });

  final String itemId;
  final String partName;

  /// The photo to show big as it opens, by id; the main one otherwise.
  final int? openOn;

  /// Overrides the file picker, for tests.
  @visibleForTesting
  static Future<List<XFile>> Function()? debugPickFiles;

  @override
  State<PartPhotoGallery> createState() => _PartPhotoGalleryState();
}

class _PartPhotoGalleryState extends State<PartPhotoGallery> {
  late final EntityPhotosProvider _store = context.read<EntityPhotosProvider>();

  /// The photos as they will be saved, first to last.
  List<GalleryPhoto> _photos = [];

  /// Photos the part keeps that Save will remove.
  final List<int> _removed = [];
  GalleryPhoto? _main;

  /// The one shown big.
  GalleryPhoto? _shown;

  /// The main photo as the gallery opened (or as the server last made it),
  /// to tell whether it was changed here.
  int? _openedMain;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _revision = _store.revisionOf(PhotoOwner.item, widget.itemId);
    _store.addListener(_onStoreChanged);
    unawaited(_load(first: true));
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  /// A photo stored elsewhere — the phone, mostly — while this is open.
  void _onStoreChanged() {
    final revision = _store.revisionOf(PhotoOwner.item, widget.itemId);
    if (revision == _revision || _saving) return;
    _revision = revision;
    unawaited(_load(first: false));
  }

  Future<void> _load({required bool first}) async {
    try {
      final fresh = await _store.partPhotos(widget.itemId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        if (first) {
          _photos = [for (final photo in fresh) StoredGalleryPhoto(photo)];
          _main = _photos.whereType<StoredGalleryPhoto>().where((p) => p.photo.isPrimary).firstOrNull ??
              _photos.firstOrNull;
          _openedMain = _idOf(_main);
          _shown = _photos.whereType<StoredGalleryPhoto>().where((p) => p.photo.id == widget.openOn).firstOrNull ??
              _main;
          return;
        }
        _merge(fresh);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  /// What the server keeps now, folded into what is on screen: a photo gone
  /// elsewhere leaves, a new one (from the phone) joins at the end, and
  /// everything typed here stays.
  void _merge(List<PartPhoto> fresh) {
    // Not changed here: the main photo follows the server's (a first photo
    // from the phone becomes the main one there).
    final mainUntouched = _main is! StagedGalleryPhoto && _idOf(_main) == _openedMain;
    final freshIds = {for (final photo in fresh) photo.id};
    final kept = <GalleryPhoto>[
      for (final photo in _photos)
        if (photo is! StoredGalleryPhoto || freshIds.contains(photo.photo.id)) photo,
    ];
    final known = {
      for (final photo in kept)
        if (photo is StoredGalleryPhoto) photo.photo.id,
      ..._removed,
    };
    for (final photo in fresh) {
      if (known.contains(photo.id)) continue;
      kept.add(StoredGalleryPhoto(photo, fromPhone: true));
    }
    _photos = kept;
    final serverMain = fresh.where((p) => p.isPrimary).firstOrNull?.id;
    if (mainUntouched && serverMain != null) {
      _main = _photos.whereType<StoredGalleryPhoto>().where((p) => p.photo.id == serverMain).firstOrNull ?? _main;
      _openedMain = serverMain;
    }
    if (!_photos.contains(_main)) {
      _main = _photos.whereType<StoredGalleryPhoto>().where((p) => p.photo.isPrimary).firstOrNull ??
          _photos.firstOrNull;
    }
    if (!_photos.contains(_shown)) _shown = _main;
  }

  static int? _idOf(GalleryPhoto? photo) =>
      photo is StoredGalleryPhoto ? photo.photo.id : null;

  bool get _changed =>
      _removed.isNotEmpty ||
      _photos.any((photo) => photo is StagedGalleryPhoto) ||
      _idOf(_main) != _openedMain ||
      (_main is StagedGalleryPhoto);

  int get _room => maxPartPhotos - _photos.length;

  // --- what a click does ----------------------------------------------------

  void _makeMain(GalleryPhoto photo) => setState(() {
    _main = photo;
    _shown = photo;
  });

  void _remove(GalleryPhoto photo) => setState(() {
    final at = _photos.indexOf(photo);
    _photos = [..._photos]..remove(photo);
    if (photo is StoredGalleryPhoto) _removed.add(photo.photo.id);
    if (identical(_main, photo)) _main = _photos.firstOrNull;
    if (identical(_shown, photo)) {
      _shown = _photos.isEmpty ? null : _photos[at.clamp(0, _photos.length - 1)];
    }
  });

  Future<void> _add() async {
    final requests = _requestsOf(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        key: const ValueKey<String>('gallery_add_choice'),
        title: const Text('Add a view of the part'),
        children: [
          PhotoChoiceTile(
            key: const ValueKey<String>('gallery_take_on_phone'),
            icon: Icons.phone_iphone_rounded,
            title: 'Take on phone',
            detail: requests == null
                ? 'Phone photos are not set up in this app.'
                : 'Your phone opens the camera with this part\'s details. '
                      'The shot appears here as soon as it is taken.',
            onTap: requests == null ? null : () => Navigator.of(dialogContext).pop('phone'),
          ),
          PhotoChoiceTile(
            key: const ValueKey<String>('gallery_from_computer'),
            icon: Icons.folder_open_rounded,
            title: 'From this computer',
            detail: _room > 1
                ? 'PNG, JPG or WebP — up to $_room at once.'
                : 'PNG, JPG or WebP.',
            onTap: () => Navigator.of(dialogContext).pop('file'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'phone') await _askPhone(requests!);
    if (choice == 'file') await _pickFiles();
  }

  Future<void> _askPhone(PhotoRequestsProvider requests) async {
    final error = await requests.ask(
      PhotoOwner.item,
      widget.itemId,
      context: 'a view of ${widget.partName}',
    );
    if (!mounted) return;
    showAppToast(
      context,
      error ?? 'Sent to your phone — the shot will appear here.',
      kind: error == null ? AppToastKind.success : AppToastKind.error,
    );
  }

  Future<void> _pickFiles() async {
    final override = PartPhotoGallery.debugPickFiles;
    final files = override != null
        ? await override()
        // Extensions only: declaring mimeTypes too makes the macOS picker
        // refuse the type group outright.
        : await openFiles(
            acceptedTypeGroups: const [
              XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp']),
            ],
          );
    if (files.isEmpty || !mounted) return;
    final taken = files.take(_room).toList();
    final staged = [
      for (final file in taken) StagedGalleryPhoto(file, await file.readAsBytes()),
    ];
    if (!mounted) return;
    setState(() {
      _photos = [..._photos, ...staged];
      _main ??= staged.firstOrNull;
      _shown = staged.firstOrNull ?? _shown;
    });
    if (files.length > taken.length) {
      showAppToast(
        context,
        'Only ${taken.length} added — a part keeps up to $maxPartPhotos photos.',
        kind: AppToastKind.warning,
      );
    }
  }

  Future<void> _takeBackFromPhone(PhotoRequestsProvider requests) async {
    final error = await requests.cancel(PhotoOwner.item, widget.itemId);
    if (!mounted || error == null) return;
    showAppToast(context, error, kind: AppToastKind.error);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await _store.saveGallery(
      widget.itemId,
      removed: List.of(_removed),
      order: List.of(_photos),
      main: _main,
    );
    if (!mounted) return;
    if (error == null) {
      showAppToast(context, 'Photos saved.', kind: AppToastKind.success);
      Navigator.of(context).pop(true);
      return;
    }
    // Some of it may have landed: start again from what the part keeps,
    // with the error said — and the photos picked here still held, so Save
    // again sends them (one already stored is matched, not stored twice).
    final staged = _photos.whereType<StagedGalleryPhoto>().toList();
    final stagedMain = _main is StagedGalleryPhoto ? _main : null;
    _removed.clear();
    setState(() {
      _saving = false;
      _loading = true;
    });
    await _load(first: true);
    if (!mounted) return;
    setState(() {
      _photos = [..._photos, ...staged];
      if (stagedMain != null) _main = stagedMain;
      _error = error;
    });
  }

  Future<void> _close() async {
    if (_saving) return;
    if (_changed) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard the changes to these photos?',
        message: 'Nothing picked, removed or made main here has been saved.',
        confirmLabel: 'Discard',
        cancelLabel: 'Keep editing',
      );
      if (!discard || !mounted) return;
    }
    Navigator.of(context).pop(false);
  }

  Future<void> _zoom(GalleryPhoto photo) => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      key: const ValueKey<String>('gallery_zoom'),
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InteractiveViewer(
            maxScale: 6,
            child: Center(child: _picture(photo, big: true, fit: BoxFit.contain)),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filledTonal(
              tooltip: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    ),
  );

  static PhotoRequestsProvider? _requestsOf(BuildContext context, {bool listen = false}) {
    try {
      return Provider.of<PhotoRequestsProvider>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  // --- drawing --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final requests = _requestsOf(context, listen: true);
    final onPhone = requests?.pendingFor(PhotoOwner.item, widget.itemId) != null;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: Dialog(
          key: const ValueKey<String>('part_photo_gallery'),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: SoftErpTheme.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 16),
                  Flexible(
                    child: _loading
                        ? const SizedBox(
                            height: 240,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : _body(requests, onPhone),
                  ),
                  const SizedBox(height: 16),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Photos of ${widget.partName}',
              key: const ValueKey<String>('gallery_title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: SoftErpTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Each view of the part — front, side, a section. The main one is '
              'shown wherever the part is.',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            ),
          ],
        ),
      ),
      IconButton(
        key: const ValueKey<String>('gallery_close'),
        tooltip: _changed ? 'Close without saving' : 'Close',
        onPressed: _saving ? null : _close,
        icon: const Icon(Icons.close_rounded),
      ),
    ],
  );

  Widget _body(PhotoRequestsProvider? requests, bool onPhone) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      final big = _bigView(wide ? 380 : 280);
      final grid = _grid(requests, onPhone);
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 380, child: big),
            const SizedBox(width: 24),
            Expanded(child: grid),
          ],
        );
      }
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [big, const SizedBox(height: 16), grid],
        ),
      );
    },
  );

  Widget _bigView(double height) {
    final shown = _shown;
    final isMain = shown != null && identical(shown, _main);
    return Container(
      key: const ValueKey<String>('gallery_main'),
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: shown == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined, size: 44, color: SoftErpTheme.textMuted),
                  SizedBox(height: 8),
                  Text(
                    'No photos yet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SoftErpTheme.textSecondary),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Add one with a + slot',
                    style: TextStyle(fontSize: 14, color: SoftErpTheme.textMuted),
                  ),
                ],
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Tooltip(
                  message: 'Click to see it full size',
                  child: InkWell(
                    onTap: () => _zoom(shown),
                    child: _picture(shown, big: true, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: isMain
                      ? _pill('Main photo', Icons.star_rounded, SoftErpTheme.accent, Colors.white)
                      : FilledButton.tonalIcon(
                          key: const ValueKey<String>('gallery_make_main'),
                          onPressed: _saving ? null : () => _makeMain(shown),
                          icon: const Icon(Icons.star_outline_rounded, size: 18),
                          label: const Text('Make main', style: TextStyle(fontSize: 14)),
                        ),
                ),
                if (_tagOf(shown) case final tag?)
                  Positioned(right: 10, top: 10, child: tag),
              ],
            ),
    );
  }

  Widget _grid(PhotoRequestsProvider? requests, bool onPhone) {
    final cells = <Widget>[
      for (final (index, photo) in _photos.indexed) _slot(index, photo),
      for (var index = _photos.length; index < maxPartPhotos; index += 1)
        // The first empty slot shows the job while the phone has it.
        if (onPhone && index == _photos.length)
          _phoneSlot(index, requests!)
        else
          _addSlot(index),
      _countCell(),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final side = ((constraints.maxWidth - gap * 2) / 3).clamp(96.0, 156.0);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final cell in cells) SizedBox(width: side, height: side, child: cell),
          ],
        );
      },
    );
  }

  Widget _slot(int index, GalleryPhoto photo) {
    final selected = identical(photo, _shown);
    final isMain = identical(photo, _main);
    return Stack(
      fit: StackFit.expand,
      children: [
        Material(
          color: SoftErpTheme.sectionSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
            side: BorderSide(
              color: selected ? SoftErpTheme.accent : SoftErpTheme.border,
              width: selected ? 2.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey<String>('gallery_slot_$index'),
            onTap: () => setState(() => _shown = photo),
            child: _picture(photo, big: false, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          left: 4,
          top: 4,
          child: _roundButton(
            key: ValueKey<String>('gallery_star_$index'),
            icon: isMain ? Icons.star_rounded : Icons.star_outline_rounded,
            color: isMain ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
            tooltip: isMain ? 'The main photo' : 'Make this the main photo',
            onTap: isMain || _saving ? null : () => _makeMain(photo),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: _roundButton(
            key: ValueKey<String>('gallery_remove_$index'),
            icon: Icons.close_rounded,
            color: SoftErpTheme.dangerText,
            tooltip: photo is StagedGalleryPhoto ? 'Take this one out' : 'Remove this view',
            onTap: _saving ? null : () => _remove(photo),
          ),
        ),
        if (_tagOf(photo) case final tag?)
          Positioned(left: 6, bottom: 6, child: tag),
      ],
    );
  }

  /// "New" for a file held here until Save; "From phone" for a shot that
  /// arrived while the gallery was open.
  Widget? _tagOf(GalleryPhoto photo) => switch (photo) {
    StagedGalleryPhoto() => _pill('New — saved on Save', null, SoftErpTheme.warningBg, SoftErpTheme.warningText),
    StoredGalleryPhoto(fromPhone: true) =>
      _pill('From phone', Icons.phone_iphone_rounded, SoftErpTheme.infoBg, SoftErpTheme.infoText),
    _ => null,
  };

  Widget _addSlot(int index) {
    final enabled = !_saving;
    return Tooltip(
      message: 'Add a view — on your phone or from this computer',
      child: Material(
        color: SoftErpTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          side: const BorderSide(color: SoftErpTheme.borderStrong, width: 1.5),
        ),
        child: InkWell(
          key: ValueKey<String>('gallery_add_$index'),
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          ),
          onTap: enabled ? _add : null,
          child: const Center(
            child: Icon(Icons.add_rounded, size: 36, color: SoftErpTheme.accent),
          ),
        ),
      ),
    );
  }

  Widget _phoneSlot(int index, PhotoRequestsProvider requests) => Tooltip(
    message: 'Waiting for your phone — click to take it back',
    child: Material(
      color: SoftErpTheme.warningBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        side: const BorderSide(color: SoftErpTheme.warningBorder, width: 1.5),
      ),
      child: InkWell(
        key: ValueKey<String>('gallery_on_phone_$index'),
        onTap: () => _takeBackFromPhone(requests),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone_iphone_rounded, size: 28, color: SoftErpTheme.warningText),
            SizedBox(height: 4),
            Text(
              'On phone',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: SoftErpTheme.warningText),
            ),
          ],
        ),
      ),
    ),
  );

  /// "3 of 5". Full, it says so — the place to add one is drawn, disabled,
  /// rather than gone.
  Widget _countCell() {
    final full = _room <= 0;
    return Container(
      key: const ValueKey<String>('gallery_count'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SoftErpTheme.shellSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${_photos.length} of $maxPartPhotos',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          if (full)
            Tooltip(
              message: 'A part keeps up to $maxPartPhotos photos',
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: SoftErpTheme.textMuted),
                  SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      'Remove one to add',
                      key: ValueKey<String>('gallery_full'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: SoftErpTheme.textMuted),
                    ),
                  ),
                ],
              ),
            )
          else
            const Text(
              'photos',
              style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final error = _error;
    return Row(
      children: [
        Expanded(
          child: error != null
              ? Text(
                  error,
                  key: const ValueKey<String>('gallery_error'),
                  style: const TextStyle(fontSize: 14, color: SoftErpTheme.dangerText),
                )
              : const Text(
                  'Click a photo to see it big · ★ makes it the main one',
                  style: TextStyle(fontSize: 14, color: SoftErpTheme.textMuted),
                ),
        ),
        const SizedBox(width: 12),
        TextButton(
          key: const ValueKey<String>('gallery_cancel'),
          onPressed: _saving ? null : _close,
          child: const Text('Cancel', style: TextStyle(fontSize: 14)),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: _changed ? 'Save the photos' : 'Nothing has changed',
          child: FilledButton.icon(
            key: const ValueKey<String>('gallery_save'),
            onPressed: _changed && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_saving ? 'Saving…' : 'Save', style: const TextStyle(fontSize: 14)),
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, IconData? icon, Color background, Color foreground) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: foreground),
        ),
      ],
    ),
  );

  Widget _roundButton({
    required Key key,
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(side: BorderSide(color: SoftErpTheme.border)),
      child: InkWell(
        key: key,
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    ),
  );

  /// A photo kept by the part loads its thumbnail in a slot and the photo
  /// big; one picked here is drawn from memory.
  static Widget _picture(GalleryPhoto photo, {required bool big, required BoxFit fit}) {
    Widget broken(BuildContext context, Object error, StackTrace? stack) => const Center(
      child: Icon(Icons.broken_image_outlined, size: 32, color: SoftErpTheme.textMuted),
    );
    return switch (photo) {
      StagedGalleryPhoto(:final bytes) => Image.memory(bytes, fit: fit, errorBuilder: broken),
      StoredGalleryPhoto(:final photo) => Image.network(
        big ? photo.viewUrl : photo.thumbUrl,
        fit: fit,
        errorBuilder: broken,
        // The thumbnail, already fetched for the slot, stands in while the
        // photo arrives.
        frameBuilder: big
            ? (context, child, frame, sync) => frame == null && !sync
                  ? Image.network(photo.thumbUrl, fit: fit, errorBuilder: broken)
                  : child
            : null,
      ),
    };
  }
}
