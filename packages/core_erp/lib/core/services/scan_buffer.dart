/// Tells a barcode scanner apart from a person typing.
///
/// A scanner gun is a keyboard. It types the code and presses Enter, which
/// makes it indistinguishable from a human by content — only by speed. No one
/// types eight characters at under 50ms apart; a gun emits at roughly 5–15ms.
///
/// That discrimination is the whole job, and getting it wrong is expensive in
/// both directions: too eager and the listener fights every text field in the
/// app (type "hello", press Enter, a dialog opens over your work); too strict
/// and a real scan silently does nothing.
///
/// Kept as a plain object rather than living inside the widget so the timing
/// can be tested without pumping frames or faking a keyboard — the logic is
/// what is delicate here, not the wiring.
class ScanBuffer {
  ScanBuffer({
    this.scannerGapMs = 50,
    this.minimumLength = 4,
  });

  /// Keystrokes further apart than this came from a person.
  final int scannerGapMs;

  /// Shorter than this and a human could plausibly have typed it, so Enter
  /// probably means something else — submit a form, confirm a dialog.
  final int minimumLength;

  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeystroke;
  bool _machineSpeed = true;

  String get value => _buffer.toString();
  bool get isEmpty => _buffer.isEmpty;

  /// Records one character. [at] is the moment it arrived, passed in rather
  /// than read from the clock so a test can describe a scan without waiting
  /// for one.
  void add(String character, DateTime at) {
    final last = _lastKeystroke;
    if (last != null) {
      final gap = at.difference(last).inMilliseconds;
      if (gap > scannerGapMs) {
        // Too slow to be a scanner. Whatever came before was someone typing,
        // so start again rather than gluing the two together — otherwise a
        // scan that follows typing inherits the typed prefix.
        _buffer.clear();
        _machineSpeed = true;
      } else {
        _machineSpeed = _machineSpeed && gap <= scannerGapMs;
      }
    }
    _lastKeystroke = at;
    _buffer.write(character);
  }

  /// Enter was pressed. Returns what was scanned, or null when this was a
  /// person typing and the app should have its Enter back.
  ///
  /// Always clears, whichever it was: a buffer left behind would prefix the
  /// next scan.
  String? complete() {
    final text = _buffer.toString().trim();
    final wasScan = _machineSpeed && text.length >= minimumLength;
    reset();
    return wasScan ? text : null;
  }

  void reset() {
    _buffer.clear();
    _lastKeystroke = null;
    _machineSpeed = true;
  }
}
