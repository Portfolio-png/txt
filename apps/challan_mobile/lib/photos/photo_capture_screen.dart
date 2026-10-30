import 'dart:typed_data';

import 'package:camera/camera.dart' show XFile;
import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/core/services/photo_requests.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'capture_source.dart';

/// The phone's camera for the photos the desktop asked for, one after another.
///
/// What the photo is for — a part, a company's logo, a person, a die, a
/// machine — sits over the live view, so the person holding the phone frames
/// the right thing without looking back at the desktop. A shot is checked
/// (Retake / Use photo) before it uploads; after it, the next job opens.
class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key, this.source});

  /// Where the photos come from; the phone's back camera when not given.
  final CaptureSource? source;

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  late final CaptureSource _source = widget.source ?? CameraCaptureSource();
  bool _opening = true;
  String? _cameraError;

  XFile? _shot;
  Uint8List? _shotBytes;
  int? _shotFor;
  bool _working = false;
  String? _error;
  int _taken = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final error = await _source.open();
    if (!mounted) return;
    setState(() {
      _opening = false;
      _cameraError = error;
    });
  }

  @override
  void dispose() {
    _source.close();
    super.dispose();
  }

  Future<void> _take(PhotoRequest request) async {
    setState(() => _working = true);
    try {
      final shot = await _source.take();
      if (shot == null || !mounted) return;
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      setState(() {
        _shot = shot;
        _shotBytes = bytes;
        _shotFor = request.id;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'The photo was not taken: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _retake() => setState(() {
        _shot = null;
        _shotBytes = null;
        _shotFor = null;
        _error = null;
      });

  Future<void> _use(PhotoRequest request) async {
    final shot = _shot;
    if (shot == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final requests = context.read<PhotoRequestsProvider>();
    try {
      final photo = await context
          .read<EntityPhotoRepository>()
          .upload(request.owner, request.entityId, shot);
      final error = await requests.complete(request, assetId: photo.assetId);
      // The photo is on the record either way; a job the desktop closed in the
      // meantime only needs the queue read again.
      if (error != null) await requests.refresh();
      if (!mounted) return;
      setState(() {
        _taken += 1;
        _shot = null;
        _shotBytes = null;
        _shotFor = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Not uploaded: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _skip(PhotoRequest request) async {
    setState(() => _working = true);
    final error = await context.read<PhotoRequestsProvider>().skip(request);
    if (!mounted) return;
    setState(() {
      _working = false;
      _error = error;
      _shot = null;
      _shotBytes = null;
      _shotFor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<PhotoRequestsProvider>().pending;
    final request = queue.isEmpty ? null : queue.first;
    // The desktop took back the job this shot was for.
    if (_shotFor != null && (request == null || request.id != _shotFor)) {
      _shot = null;
      _shotBytes = null;
      _shotFor = null;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: request == null
          ? _AllDone(taken: _taken)
          : Stack(
              fit: StackFit.expand,
              children: [
                if (_shotBytes != null)
                  Image.memory(_shotBytes!, fit: BoxFit.cover)
                else if (_opening)
                  const Center(child: CircularProgressIndicator(color: Colors.white))
                else if (_cameraError != null)
                  _CameraProblem(message: _cameraError!)
                else
                  _source.preview(context),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: PhotoRequestCard(
                        request: request,
                        position: _taken + 1,
                        total: _taken + queue.length,
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_error != null) _ErrorStrip(message: _error!),
                        _shotBytes == null
                            ? _ShootBar(
                                busy: _working,
                                canShoot: !_opening && _cameraError == null,
                                onShoot: () => _take(request),
                                onSkip: () => _skip(request),
                                onClose: () => Navigator.of(context).maybePop(),
                              )
                            : _ReviewBar(
                                busy: _working,
                                onRetake: _retake,
                                onUse: () => _use(request),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// What the photo is for, over the camera: the kind, the record, where its
/// slot sits on the desktop, and the few facts that tell it apart.
class PhotoRequestCard extends StatelessWidget {
  const PhotoRequestCard({
    super.key,
    required this.request,
    required this.position,
    required this.total,
  });

  final PhotoRequest request;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('photo-request-card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: SoftErpTheme.accent,
                  borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
                ),
                child: Text(
                  request.kind.isEmpty ? 'Photo' : request.kind,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              Text(
                '$position of $total',
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            request.title.isEmpty ? 'Untitled' : request.title,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (request.context.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              request.context,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
          if (request.lines.isNotEmpty) const SizedBox(height: 8),
          for (final line in request.lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${line.label}  ',
                    style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: line.value,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ]),
                style: const TextStyle(fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShootBar extends StatelessWidget {
  const _ShootBar({
    required this.busy,
    required this.canShoot,
    required this.onShoot,
    required this.onSkip,
    required this.onClose,
  });

  final bool busy;
  final bool canShoot;
  final VoidCallback onShoot;
  final VoidCallback onSkip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                key: const ValueKey<String>('photo-close'),
                tooltip: 'Close — the photos wait here',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Take photo',
            child: GestureDetector(
              key: const ValueKey<String>('photo-shutter'),
              onTap: busy || !canShoot ? null : onShoot,
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
                    color: busy || !canShoot ? Colors.white38 : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey<String>('photo-skip'),
                onPressed: busy ? null : onSkip,
                child: const Text(
                  'Skip',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewBar extends StatelessWidget {
  const _ReviewBar({required this.busy, required this.onRetake, required this.onUse});

  final bool busy;
  final VoidCallback onRetake;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey<String>('photo-retake'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: busy ? null : onRetake,
              child: const Text('Retake', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const ValueKey<String>('photo-use'),
              style: FilledButton.styleFrom(
                backgroundColor: SoftErpTheme.accent,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: busy ? null : onUse,
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Use photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('photo-error'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SoftErpTheme.dangerText.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
      ),
      child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 14)),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllDone extends StatelessWidget {
  const _AllDone({required this.taken});

  final int taken;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 64),
            const SizedBox(height: 12),
            Text(
              taken == 0 ? 'No photos waiting' : 'All done — $taken ${taken == 1 ? 'photo' : 'photos'} sent',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey<String>('photo-done-close'),
              style: FilledButton.styleFrom(backgroundColor: SoftErpTheme.accent),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
