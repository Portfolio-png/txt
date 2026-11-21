import 'package:flutter/material.dart';

import 'capture_source.dart';

/// The live camera, zoomable: pinch it, or tap 1× / 2× / the lens's most.
/// The zoom in use is shown, so a close-up is not mistaken for the lens being
/// that close.
class ZoomablePreview extends StatefulWidget {
  const ZoomablePreview({super.key, required this.source, this.bottomInset = 128});

  final CaptureSource source;

  /// Room left below the zoom buttons, for the shutter bar.
  final double bottomInset;

  @override
  State<ZoomablePreview> createState() => ZoomablePreviewState();
}

class ZoomablePreviewState extends State<ZoomablePreview> {
  ({double min, double max})? _range;
  double _zoom = 1;
  double _pinchStart = 1;

  /// Where the zoom is now — for tests.
  double get zoom => _zoom;

  @override
  void initState() {
    super.initState();
    widget.source.zoomRange().then((range) {
      if (!mounted || range == null) return;
      setState(() {
        _range = range;
        _zoom = _zoom.clamp(range.min, range.max);
      });
    });
  }

  void _zoomTo(double level) {
    final range = _range;
    if (range == null) return;
    final next = level.clamp(range.min, range.max);
    if ((next - _zoom).abs() < 0.01) return;
    setState(() => _zoom = next);
    widget.source.setZoom(next);
  }

  /// 1×, 2× when the lens reaches it, and the lens's most when that is more.
  List<double> get _stops {
    final range = _range;
    if (range == null) return const [];
    final cap = range.max > 10 ? 10.0 : range.max;
    return [
      range.min < 1 ? 1.0 : range.min,
      if (cap >= 2) 2.0,
      if (cap > 2.5) (cap * 10).floorToDouble() / 10,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey<String>('camera-zoom-area'),
      behavior: HitTestBehavior.opaque,
      onScaleStart: (_) => _pinchStart = _zoom,
      onScaleUpdate: (details) {
        if (details.pointerCount < 2) return;
        _zoomTo(_pinchStart * details.scale);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.source.preview(context),
          if (_range != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: widget.bottomInset,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final stop in _stops) _ZoomStop(
                        level: stop,
                        selected: (_zoom - stop).abs() < 0.05,
                        onTap: () => _zoomTo(stop),
                      ),
                      // The zoom pinched to, when it is between the stops.
                      if (!_stops.any((stop) => (_zoom - stop).abs() < 0.05))
                        _ZoomStop(level: _zoom, selected: true, onTap: () {}),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _label(double level) {
  final rounded = (level * 10).round() / 10;
  return rounded == rounded.roundToDouble() ? '${rounded.round()}×' : '$rounded×';
}

class _ZoomStop extends StatelessWidget {
  const _ZoomStop({required this.level, required this.selected, required this.onTap});

  final double level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Zoom ${_label(level)}',
      child: GestureDetector(
        key: ValueKey<String>('camera-zoom-${_label(level)}'),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _label(level),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
