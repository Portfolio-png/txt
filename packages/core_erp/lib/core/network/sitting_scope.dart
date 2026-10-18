import 'dart:math';

/// Which opening of a window the writes happening right now belong to.
///
/// A "sitting" is one opening of one window — the Express bench, say, where
/// somebody fills a group, a unit, an item and a die side by side. The server
/// already records who changed what and never recorded what else was changed at
/// the same time, so "where did the die I just made go?" had no answer. This
/// holds the id that answers it: [AuthenticatedHttpClient] stamps it on every
/// non-GET while it is set, and the server stores it against each activity row.
///
/// **Process-wide on purpose.** `AuthenticatedHttpClient` is built about
/// twenty-five times (once per repository, in `main.dart`), so the id cannot be
/// constructor state on the client — every repository would need threading. A
/// holder read at send time is the one shape that reaches all of them from a
/// single wiring point.
///
/// It follows that this is ambient: anything that writes while a window is open
/// is counted as part of that window, including a nested editor opened from
/// inside it. That is the intended reading — it did happen there — but it does
/// mean a background write would be attributed too, which is why [begin] is
/// called from a window's `initState` and not from, say, app start.
class SittingScope {
  const SittingScope._();

  static final Random _random = Random();

  /// Open windows, outermost first.
  ///
  /// A stack rather than one slot because windows nest: Add Item can open over
  /// Express. With a single slot the inner window closing cleared the sitting
  /// outright and every write the outer window made afterwards went
  /// unattributed — so the inner one has to pop back to the outer, not to
  /// nothing.
  static final List<String> _stack = <String>[];

  /// The sitting in progress, or null when no window is open.
  static String? get current => _stack.isEmpty ? null : _stack.last;

  /// Starts a sitting and returns its id.
  ///
  /// The caller keeps the id and hands it back to [end]. Ids are
  /// microseconds-since-epoch plus a short random tail: the timestamp alone is
  /// the idiom used elsewhere in this folder, but two clients can open a window
  /// in the same microsecond and these ids meet on one server.
  ///
  /// `core_erp` has no `uuid` dependency (it is in the host app's pubspec only),
  /// and adding one for this would be a heavier change than the problem needs.
  static String begin() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tail = _random.nextInt(1 << 20).toRadixString(36);
    final id = 's$stamp-$tail';
    _stack.add(id);
    return id;
  }

  /// Ends [id] and falls back to whatever window was under it.
  ///
  /// By id, not by popping blindly: disposal order is not guaranteed to be the
  /// reverse of opening order, and ending the wrong window's sitting is worse
  /// than ending none. Ending an id that was never begun does nothing.
  static void end(String id) => _stack.remove(id);

  /// Drops every sitting in progress. For tests, and for a hard reset.
  static void reset() => _stack.clear();
}
