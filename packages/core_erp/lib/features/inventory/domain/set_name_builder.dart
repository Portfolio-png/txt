/// A set's name built from its members, the way an item's name is built from
/// its parts: offered while nobody has typed one, and never over a typed one.
///
/// Each item once, in the order its rows stand ("Patti" twice in two
/// variants is still one Patti). Past [shown] names the rest are counted, so
/// a big kit does not get a name a line long.
String buildSetName(Iterable<String> itemLabels, {int shown = 3}) {
  final seen = <String>{};
  final names = <String>[];
  for (final raw in itemLabels) {
    final label = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (label.isEmpty) continue;
    if (seen.add(label.toLowerCase())) names.add(label);
  }
  if (names.length <= shown) return names.join(' + ');
  return '${names.take(shown).join(' + ')} + ${names.length - shown} more';
}

/// How someone arranged a set's name: its items in their order, what joins
/// each to the next — " + " here, ", " there, like the terms of an equation
/// — and which items are left out of the name (user, 2026-11-24).
///
/// Until [touched], the name is [buildSetName]'s. The separators belong to
/// the gaps, not the items: moving an item keeps "A + B, C" reading as
/// "B + A, C", as an equation's operators stay where they are.
class SetNameArrangement {
  /// What can join two names. The first is the default.
  static const List<String> separators = [' + ', ', ', ' & ', ' / ', ' × '];

  final List<String> _order = [];
  final List<String> _joins = [];
  final Set<String> _leftOut = {};

  /// Whether anyone has arranged it: then the name follows it in full.
  bool touched = false;

  static String _key(String name) => name.toLowerCase();

  /// The names in the name, in order.
  List<String> get included => [
    for (final name in _order)
      if (!_leftOut.contains(_key(name))) name,
  ];

  List<String> get leftOut => [
    for (final name in _order)
      if (_leftOut.contains(_key(name))) name,
  ];

  /// What joins included name [gap] to the one after it.
  String joinAt(int gap) => gap < _joins.length ? _joins[gap] : separators.first;

  /// Brings the names in line with the set's items, distinct and in row
  /// order: ones already placed keep their place, new ones go at the end,
  /// gone ones go.
  void sync(Iterable<String> itemLabels) {
    final seen = <String>{};
    final names = <String>[];
    for (final raw in itemLabels) {
      final label = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (label.isEmpty) continue;
      if (seen.add(_key(label))) names.add(label);
    }
    _order.removeWhere((name) => !seen.contains(_key(name)));
    _leftOut.removeWhere((key) => !seen.contains(key));
    final placed = {for (final name in _order) _key(name)};
    for (final name in names) {
      if (!placed.contains(_key(name))) _order.add(name);
    }
    // Joins are kept past the names in use: a name left out and put back
    // finds the separator that was chosen for its gap.
    final gaps = included.length - 1;
    while (_joins.length < gaps) {
      _joins.add(separators.first);
    }
  }

  /// Included name [index] one place left (-1) or right (+1).
  void move(int index, int by) {
    final names = included;
    final to = index + by;
    if (to < 0 || to >= names.length) return;
    final a = _order.indexOf(names[index]);
    final b = _order.indexOf(names[to]);
    final kept = _order[a];
    _order[a] = _order[b];
    _order[b] = kept;
    touched = true;
  }

  void setJoin(int gap, String separator) {
    while (_joins.length <= gap) {
      _joins.add(separators.first);
    }
    _joins[gap] = separator;
    touched = true;
  }

  void leaveOut(String name) {
    if (included.length <= 1) return;
    _leftOut.add(_key(name));
    touched = true;
    sync(_order);
  }

  void putBack(String name) {
    _leftOut.remove(_key(name));
    touched = true;
    sync(_order);
  }

  /// The name as arranged.
  String compose() {
    final names = included;
    final out = StringBuffer();
    for (var i = 0; i < names.length; i += 1) {
      if (i > 0) out.write(joinAt(i - 1));
      out.write(names[i]);
    }
    return out.toString();
  }
}
