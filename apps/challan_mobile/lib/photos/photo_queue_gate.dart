import 'package:core_erp/core/services/photo_requests.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/socket_service.dart';
import 'capture_source.dart';
import 'photo_capture_screen.dart';

/// Opens the camera by itself when the desktop sends a photo to take.
///
/// Wraps the signed-in app. A job that is new since last looked at opens
/// [PhotoCaptureScreen] over whatever tab is showing; jobs still waiting after
/// the camera is closed stay in a strip at the top ("3 photos to take"), so
/// closing it never loses them. The queue is read again whenever the app comes
/// back to the front, for a job sent while the phone was in a pocket.
class PhotoQueueGate extends StatefulWidget {
  const PhotoQueueGate({super.key, required this.child, this.sourceFactory});

  final Widget child;

  /// Builds the camera for each capture session; the phone's own when null.
  final CaptureSource Function()? sourceFactory;

  @override
  State<PhotoQueueGate> createState() => _PhotoQueueGateState();
}

class _PhotoQueueGateState extends State<PhotoQueueGate> with WidgetsBindingObserver {
  late final PhotoRequestsProvider _requests = context.read<PhotoRequestsProvider>();
  final Set<int> _seen = {};
  bool _open = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Reading it starts the live connection the queue is announced over; it
    // was only started once the Scan Area screen asked for it.
    context.read<SocketService>();
    _requests.addListener(_onQueue);
    _requests.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requests.removeListener(_onQueue);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _requests.refresh();
  }

  void _onQueue() {
    if (!mounted) return;
    final fresh = [for (final r in _requests.pending) if (!_seen.contains(r.id)) r];
    _seen.addAll(_requests.pending.map((r) => r.id));
    setState(() {});
    if (fresh.isNotEmpty && !_open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
    }
  }

  Future<void> _openCamera() async {
    if (_open || !mounted) return;
    _open = true;
    setState(() {});
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoCaptureScreen(source: widget.sourceFactory?.call()),
      ),
    );
    if (!mounted) return;
    _open = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final waiting = context.watch<PhotoRequestsProvider>().pending.length;
    return Column(
      children: [
        if (waiting > 0 && !_open)
          Material(
            key: const ValueKey<String>('photo-queue-strip'),
            color: SoftErpTheme.accent,
            child: SafeArea(
              bottom: false,
              child: InkWell(
                onTap: _openCamera,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.photo_camera_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$waiting ${waiting == 1 ? 'photo' : 'photos'} to take',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Text(
                        'Open camera',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
