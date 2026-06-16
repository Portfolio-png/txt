import 'dart:async';
import 'package:flutter/material.dart';

enum FloorToastKind { info, warning, error }

/// Shows a transient notice anchored to the TOP of the screen (SnackBars are
/// stuck to the bottom). Used for floor warnings/errors on the production
/// monitor so they appear above the canvas, near the controls.
void showFloorToast(
  BuildContext context,
  String message, {
  FloorToastKind kind = FloorToastKind.warning,
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _FloorToast(
      message: message,
      kind: kind,
      duration: duration,
      onDone: remove,
    ),
  );
  overlay.insert(entry);
}

class _FloorToast extends StatefulWidget {
  const _FloorToast({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final FloorToastKind kind;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_FloorToast> createState() => _FloorToastState();
}

class _FloorToastState extends State<_FloorToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  ({Color bg, Color fg, IconData icon}) get _style {
    switch (widget.kind) {
      case FloorToastKind.error:
        return (
          bg: const Color(0xFFDC2626),
          fg: Colors.white,
          icon: Icons.error_outline_rounded,
        );
      case FloorToastKind.info:
        return (
          bg: const Color(0xFF2563EB),
          fg: Colors.white,
          icon: Icons.info_outline_rounded,
        );
      case FloorToastKind.warning:
        return (
          bg: const Color(0xFFF59E0B),
          fg: Colors.white,
          icon: Icons.warning_amber_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _controller,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.4),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
              ),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: _dismiss,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 560),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: s.bg,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(s.icon, color: s.fg, size: 20),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: s.fg,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
