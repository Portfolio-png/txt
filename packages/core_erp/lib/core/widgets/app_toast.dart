import 'dart:async';
import 'package:flutter/material.dart';

enum AppToastKind { info, success, warning, error }

/// App-wide navigator key so toasts can reach a global overlay without a
/// call-site context. Wired into MaterialApp(navigatorKey: appNavigatorKey).
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'appNavigator');

/// Shows a transient notice anchored to the TOP of the screen (SnackBars are
/// stuck to the bottom). Uses the root overlay, so it survives the dialog or
/// route it was triggered from being popped. Falls back to the global overlay
/// if the context has none (e.g. called after the context unmounted).
void showAppToast(
  BuildContext context,
  String message, {
  AppToastKind kind = AppToastKind.info,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
      appNavigatorKey.currentState?.overlay;
  _insertToast(overlay, message, kind, duration);
}

/// Context-free top toast via the global overlay — used to redirect bottom
/// SnackBars and for fire-and-forget notices after async gaps.
void showGlobalToast(
  String message, {
  AppToastKind kind = AppToastKind.info,
  Duration duration = const Duration(seconds: 3),
}) {
  _insertToast(appNavigatorKey.currentState?.overlay, message, kind, duration);
}

/// Renders an existing [SnackBar] as a top toast instead of at the bottom.
/// Message comes from the SnackBar's Text content; kind is inferred from its
/// background colour, then message keywords.
void showAppSnack(SnackBar bar) {
  final message = _snackMessage(bar);
  if (message.isEmpty) return;
  showGlobalToast(message, kind: _snackKind(bar, message));
}

String _snackMessage(SnackBar bar) {
  final content = bar.content;
  if (content is Text) return content.data ?? '';
  return '';
}

AppToastKind _snackKind(SnackBar bar, String message) {
  final bg = bar.backgroundColor;
  if (bg != null) {
    if (bg.r > 0.55 && bg.g < 0.5 && bg.b < 0.5) return AppToastKind.error;
    if (bg.g > 0.5 && bg.r < 0.55 && bg.b < 0.6) return AppToastKind.success;
  }
  final m = message.toLowerCase();
  if (m.contains('fail') ||
      m.contains('error') ||
      m.contains('could not') ||
      m.contains("couldn't") ||
      m.contains('cannot') ||
      m.contains('unable') ||
      m.contains('invalid')) {
    return AppToastKind.error;
  }
  if (m.contains('success') ||
      m.contains('saved') ||
      m.contains('created') ||
      m.contains('updated') ||
      m.contains('added') ||
      m.contains('deleted') ||
      m.contains('assigned') ||
      m.contains('completed')) {
    return AppToastKind.success;
  }
  return AppToastKind.info;
}

void _insertToast(
  OverlayState? overlay,
  String rawMessage,
  AppToastKind kind,
  Duration duration,
) {
  if (overlay == null) return;

  var message = rawMessage;
  if (message.startsWith('Exception: ')) {
    message = message.substring(11).trim();
  }
  
  if (message.contains('SQLITE_CONSTRAINT') || message.contains('FOREIGN KEY')) {
    String recordName = 'record';
    final match = RegExp(r'failed:\s*([a-zA-Z0-9_]+)\.').firstMatch(message);
    if (match != null) {
      final table = match.group(1)!;
      final words = table.split('_');
      if (words.isNotEmpty) {
        var lastWord = words.last;
        if (lastWord.endsWith('ies')) {
          lastWord = '${lastWord.substring(0, lastWord.length - 3)}y';
        } else if (lastWord.endsWith('s') && !lastWord.endsWith('ss') && !lastWord.endsWith('us')) {
          lastWord = lastWord.substring(0, lastWord.length - 1);
        }
        words[words.length - 1] = lastWord;
        words[0] = words[0].substring(0, 1).toUpperCase() + words[0].substring(1);
        recordName = words.join(' ');
      }
    }
    message = 'This $recordName is currently in use or referenced elsewhere in the system. It cannot be deleted or modified until those connections are removed.';
  }
  late OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _AppToast(
      message: message,
      kind: kind,
      duration: duration,
      onDone: remove,
    ),
  );
  overlay.insert(entry);
}

class _AppToast extends StatefulWidget {
  const _AppToast({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final AppToastKind kind;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
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
      case AppToastKind.error:
        return (
          bg: const Color(0xFFDC2626),
          fg: Colors.white,
          icon: Icons.error_outline_rounded,
        );
      case AppToastKind.success:
        return (
          bg: const Color(0xFF16A34A),
          fg: Colors.white,
          icon: Icons.check_circle_outline_rounded,
        );
      case AppToastKind.info:
        return (
          bg: const Color(0xFF2563EB),
          fg: Colors.white,
          icon: Icons.info_outline_rounded,
        );
      case AppToastKind.warning:
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
