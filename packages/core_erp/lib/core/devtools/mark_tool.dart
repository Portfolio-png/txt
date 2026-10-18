import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// One place someone pointed at and said what it is.
@immutable
class Mark {
  const Mark({
    required this.n,
    required this.session,
    required this.label,
    required this.screen,
    required this.keys,
    required this.text,
    required this.widgets,
    required this.position,
    required this.at,
  });

  /// Its number in this sitting, which is what the badge shows.
  final int n;

  /// Which sitting it came from. The file is appended to across runs and the
  /// numbering starts again each time, so without this a later read cannot
  /// tell two marks apart or say which pass over the app they belong to.
  final String session;

  /// What the person says this is — 'unit' to begin with.
  final String label;

  /// The nearest enclosing Screen / Dialog / Panel, which is how a human says
  /// where something is.
  final String screen;

  /// Every ValueKey on the way down to what was clicked. These are what make a
  /// mark actionable later: the codebase keys its widgets, so a key is a
  /// durable address where a coordinate is not.
  final List<String> keys;

  /// The nearest text under the pointer — the label a human would read.
  final String text;

  /// The widget types from the hit outwards, noise dropped.
  final List<String> widgets;

  final Offset position;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'n': n,
    'session': session,
    'label': label,
    'screen': screen,
    'keys': keys,
    'text': text,
    'widgets': widgets,
    'at': [position.dx.round(), position.dy.round()],
    'ts': at.toIso8601String(),
  };

  /// What a person reads in the terminal, before the JSON.
  String get summary {
    final where = screen.isEmpty ? '?' : screen;
    final what = text.isNotEmpty
        ? '"$text"'
        : keys.isNotEmpty
        ? keys.first
        : widgets.isNotEmpty
        ? widgets.first
        : '?';
    return '#$n $label · $where · $what';
  }
}

/// Where marks go so they outlive the terminal scrollback.
///
/// A fixed path on purpose: a mark is only useful if it can be read back
/// afterwards, and a path that has to be hunted for is one nobody reads.
/// Override with --dart-define=PAPER_MARKS_PATH=/somewhere/else.jsonl
String get markFilePath {
  const override = String.fromEnvironment('PAPER_MARKS_PATH');
  if (override.isNotEmpty) return override;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  return '$home/.paper/marks.jsonl';
}

/// Sends each mark to the backend, which writes it into the repo.
///
/// The app cannot keep the file itself. A Flutter macOS build is sandboxed, so
/// its HOME is a container under `Library/Containers/<bundle>/Data` — the first
/// version of this wrote to `HOME/.paper/marks.jsonl`, which meant a path
/// nobody could find and, in the event, a write that failed outright while the
/// badge counter happily went on counting. Eight marks were lost that way.
///
/// So the backend owns the file (POST /api/dev/marks → `<repo>/.paper-marks.jsonl`)
/// and the local copy is only a fallback for a run with no server. Failures are
/// reported EVERY time and counted, because the one thing a note-taking tool
/// must never do quietly is fail to take the note.
class MarkSink {
  MarkSink({String? path, this.baseUrl, http.Client? client})
    : path = path ?? markFilePath,
      _client = client;

  /// The fallback file, used when there is no backend to post to.
  final String path;

  /// Where the backend is. Null falls back to the local file alone.
  final String? baseUrl;

  final http.Client? _client;

  /// Marks that reached neither the server nor the file. Shown in the bar, so
  /// a broken sink is visible without reading the terminal.
  int lost = 0;

  /// Where marks are actually going, for the bar to say.
  String get destination =>
      baseUrl == null ? path : '$baseUrl/api/dev/marks';

  /// Completes once the mark has landed somewhere, or been counted as lost.
  /// The caller awaits it so the bar can show a dropped mark — the counter
  /// moving in silence is the failure this whole class is shaped around.
  Future<void> write(Mark mark) async {
    final line = jsonEncode(mark.toJson());
    // The terminal copy, which is what you watch while marking.
    debugPrint('PAPER-MARK ${mark.summary}');
    debugPrint('PAPER-MARK $line');
    await _post(mark, line);
  }

  Future<void> _post(Mark mark, String line) async {
    final client = _client;
    final url = baseUrl;
    if (client != null && url != null) {
      try {
        final response = await client.post(
          Uri.parse('$url/api/dev/marks'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'marks': [mark.toJson()]}),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) return;
        debugPrint(
          'PAPER-MARK server refused mark #${mark.n} '
          '(${response.statusCode}); trying the local file',
        );
      } catch (error) {
        debugPrint('PAPER-MARK could not reach the server: $error');
      }
    }
    if (_writeLocally(line)) return;
    lost++;
    debugPrint('PAPER-MARK LOST mark #${mark.n} — nowhere to put it');
  }

  bool _writeLocally(String line) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      return true;
    } catch (error) {
      debugPrint('PAPER-MARK could not write $path: $error');
      return false;
    }
  }

  void clear() {
    lost = 0;
    final client = _client;
    final url = baseUrl;
    if (client != null && url != null) {
      unawaited(
        client.delete(Uri.parse('$url/api/dev/marks')).catchError((error) {
          debugPrint('PAPER-MARK could not clear on the server: $error');
          return http.Response('', 500);
        }),
      );
    }
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Nothing depends on the fallback file being gone.
    }
  }
}

/// Widget types that say nothing about what was clicked.
const Set<String> _noise = {
  'Padding', 'Center', 'Align', 'SizedBox', 'ConstrainedBox', 'DecoratedBox',
  'ColoredBox', 'Container', 'Semantics', 'RepaintBoundary', 'Opacity',
  'ClipRect', 'ClipRRect', 'MouseRegion', 'Listener', 'IgnorePointer',
  'AbsorbPointer', 'Positioned', 'Expanded', 'Flexible', 'LayoutBuilder',
  'Builder', 'SafeArea', 'Material', 'InkWell', 'InkResponse', 'DefaultTextStyle',
  'AnimatedOpacity', 'AnimatedContainer', 'FadeTransition', 'SlideTransition',
  'Transform', 'Offstage', 'TickerMode', 'KeyedSubtree', 'Directionality',
  'MediaQuery', 'Theme', 'IconTheme', 'Overlay', 'Stack', 'Row', 'Column',
  'Flex', 'Wrap', 'SingleChildScrollView', 'Scrollable', 'Viewport', 'Scrollbar',
  // Everything a TextField or a button drags in with it. Without these a mark
  // on a field reports ten names from inside EditableText and never reaches
  // the field itself.
  'SizeChangedLayoutNotifier', 'CompositedTransformTarget', 'RawGestureDetector',
  'NotificationListener', 'Focus', 'FocusScope', 'FocusTraversalGroup',
  'Actions', 'Shortcuts', 'TapRegion', 'TextFieldTapRegion', 'ExcludeSemantics',
  'UnmanagedRestorationScope', 'RestorationScope', 'AnimatedBuilder',
  'ValueListenableBuilder', 'ListenableBuilder', 'CompositedTransformFollower',
  'TextSelectionGestureDetectorBuilder', 'ScrollNotificationObserver',
  'PrimaryScrollController', 'ScrollConfiguration', 'GestureDetector',
  'ConstrainedLayoutBuilder', 'CustomPaint', 'CustomSingleChildLayout',
};

/// Names are compared without their type arguments, so one entry covers
/// NotificationListener&lt;ScrollNotification&gt; and every other instantiation.
String _bareName(Widget widget) {
  final name = widget.runtimeType.toString();
  final generic = name.indexOf('<');
  return generic == -1 ? name : name.substring(0, generic);
}

/// A widget type that reads like a place rather than a part.
///
/// Private names are kept: half this app's places are private widgets
/// (_VariationPanel, _UnitFieldScreen), and "which panel" is exactly what a
/// mark needs to say. The suffix list is narrow on purpose — Card, Tab and
/// Form are Material's own and would name the place after the furniture.
final RegExp _placeLike = RegExp(
  r'(Screen|Dialog|Sheet|Panel|Workspace|Editor)$',
);

/// Reads what sits under a pointer out of the render tree.
///
/// Hit testing gives render objects; in a debug build each one knows the
/// element that created it ([DebugCreator]), and an element is a BuildContext
/// with a widget and a key. That is the whole trick, and it is the same one the
/// Flutter inspector uses — which is why this is debug-only and says so.
Mark? describeHit({
  required RenderBox root,
  required Offset globalPosition,
  required String label,
  required int n,
  String session = 'adhoc',
}) {
  final result = BoxHitTestResult();
  if (!root.hitTest(result, position: root.globalToLocal(globalPosition))) {
    return null;
  }

  final widgets = <String>[];
  final keys = <String>[];
  var screen = '';
  var text = '';

  for (final entry in result.path) {
    final target = entry.target;
    if (target is! RenderObject) continue;
    // Only a debug build fills this in, which is the whole reason this tool is
    // debug-only rather than merely discouraged in release.
    final creator = target.debugCreator;
    if (creator is! DebugCreator) continue;
    final element = creator.element;

    // Two budgets, not one. Collecting stops early so a mark describes what
    // was clicked rather than the whole app shell — but the walk itself keeps
    // going, because the enclosing screen is usually far above the widget and
    // stopping at the collection budget was why `screen` came back empty.
    var steps = 0;
    element.visitAncestorElements((ancestor) {
      // Keys are collected the whole way up even after the type budget is
      // spent: the key is the part of a mark that still means something after
      // the layout around it is rewritten, and it usually sits on a widget
      // well above the one the pointer actually hit.
      _collectKey(ancestor.widget, keys);
      if (widgets.length < 40) _collectType(ancestor.widget, widgets);
      if (screen.isEmpty) {
        final name = _bareName(ancestor.widget);
        if (_placeLike.hasMatch(name)) screen = name;
      }
      return ++steps < 120 && screen.isEmpty;
    });

    _collectKey(element.widget, keys);
    _collectType(element.widget, widgets);
    if (text.isEmpty) text = _nearestText(element);
    if (keys.isNotEmpty && text.isNotEmpty && screen.isNotEmpty) break;
  }

  return Mark(
    n: n,
    session: session,
    label: label,
    screen: screen,
    keys: keys.toSet().toList(),
    text: text,
    widgets: widgets.take(10).toList(),
    position: globalPosition,
    at: DateTime.now(),
  );
}

void _collectType(Widget widget, List<String> widgets) {
  final name = _bareName(widget);
  // Private names are dropped here, not because they are uninteresting but
  // because the framework has far more of them than the app does and they
  // crowd out the name you were looking for. A private widget that names a
  // PLACE still comes through as `screen`, which is where it matters.
  if (name.startsWith('_')) return;
  if (!_noise.contains(name) && !widgets.contains(name)) widgets.add(name);
}

void _collectKey(Widget widget, List<String> keys) {
  if (keys.length >= 12) return;
  final key = widget.key;
  if (key is! ValueKey || key.value == null) return;
  final value = '${key.value}';
  if (value.isNotEmpty && !keys.contains(value)) keys.add(value);
}

/// The first readable text at or under [element]. Breadth-limited: the point
/// is the label someone would read, not an inventory of the subtree.
String _nearestText(Element element, {int budget = 60}) {
  var found = '';
  var seen = 0;
  void walk(Element node) {
    if (found.isNotEmpty || seen++ > budget) return;
    final widget = node.widget;
    if (widget is Text) {
      final data = (widget.data ?? '').trim();
      if (data.isNotEmpty) {
        found = data;
        return;
      }
    }
    if (widget is EditableText) {
      final value = widget.controller.text.trim();
      if (value.isNotEmpty) found = value;
    }
    node.visitChildren(walk);
  }

  walk(element);
  return found;
}

/// Hold a modifier and right-click anything to say what it is.
///
/// Wrap the app in it in debug builds. It adds nothing to a release build —
/// the inspector machinery it reads is not there — so it is gated at the call
/// site rather than pretending to work.
class MarkTool extends StatefulWidget {
  const MarkTool({
    super.key,
    required this.child,
    this.labels = const ['unit', 'item', 'die', 'machine', 'client', 'order'],
    this.sink,
  });

  final Widget child;

  /// What a mark can say. The first is where it starts.
  final List<String> labels;

  /// Injected by tests; the real one appends to [markFilePath].
  final MarkSink? sink;

  @override
  State<MarkTool> createState() => MarkToolState();
}

class MarkToolState extends State<MarkTool> {
  final GlobalKey _appKey = GlobalKey(debugLabel: 'markToolApp');
  late final MarkSink _sink = widget.sink ?? MarkSink();

  final List<Mark> _marks = [];

  /// Stamped on every mark this run, so a file holding several passes over the
  /// app can still be read apart.
  final String _session = DateTime.now()
      .toIso8601String()
      .substring(5, 16)
      .replaceAll(RegExp(r'[-:T]'), '');

  late String _label = widget.labels.first;
  bool _armed = false;

  @visibleForTesting
  List<Mark> get marks => List.unmodifiable(_marks);

  @visibleForTesting
  bool get armed => _armed;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    scheduleMicrotask(() {
      debugPrint(
        'PAPER-MARK ready · session $_session · ⌘⇧M (or F2) arms marking · '
        'then right-click anything · writing to ${_sink.path}',
      );
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// ⌘⇧M arms and disarms. F2 does the same, for a keyboard where the first is
  /// already taken by something else.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final shift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final isM = event.logicalKey == LogicalKeyboardKey.keyM;
    if ((meta && shift && isM) || event.logicalKey == LogicalKeyboardKey.f2) {
      _toggle();
      return true;
    }
    return false;
  }

  void _toggle() {
    setState(() => _armed = !_armed);
    debugPrint('PAPER-MARK ${_armed ? 'armed · marking "$_label"' : 'off'}');
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_armed) return;
    if (event.buttons & kSecondaryMouseButton == 0) return;
    final root = _appKey.currentContext?.findRenderObject();
    if (root is! RenderBox) return;
    final mark = describeHit(
      root: root,
      globalPosition: event.position,
      label: _label,
      n: _marks.length + 1,
      session: _session,
    );
    if (mark == null) return;
    setState(() => _marks.add(mark));
    unawaited(
      _sink.write(mark).whenComplete(() {
        if (mounted) setState(() {});
      }),
    );
  }

  void _printAll() {
    debugPrint('PAPER-MARK —— ${_marks.length} marks this sitting ——');
    for (final mark in _marks) {
      debugPrint('PAPER-MARK ${mark.summary}');
    }
    debugPrint('PAPER-MARK —— file: ${_sink.path} ——');
  }

  void _clear() {
    setState(_marks.clear);
    _sink.clear();
    debugPrint('PAPER-MARK cleared, including ${_sink.path}');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        KeyedSubtree(key: _appKey, child: widget.child),
        // Translucent on purpose: the app underneath still gets the pointer,
        // so arming the tool does not make the app unusable. A right-click
        // does little in this app, and reading one is all this needs.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            child: const SizedBox.expand(),
          ),
        ),
        for (final mark in _marks)
          Positioned(
            left: mark.position.dx - 11,
            top: mark.position.dy - 11,
            child: IgnorePointer(child: _MarkBadge(mark: mark)),
          ),
        if (_armed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: false,
              child: _MarkBar(
                label: _label,
                labels: widget.labels,
                count: _marks.length,
                path: _sink.destination,
                lost: _sink.lost,
                onLabel: (value) => setState(() => _label = value),
                onPrint: _printAll,
                onClear: _clear,
                onClose: _toggle,
              ),
            ),
          ),
      ],
    );
  }
}

class _MarkBadge extends StatelessWidget {
  const _MarkBadge({required this.mark});

  final Mark mark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Text(
        '${mark.n}',
        style: const TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _MarkBar extends StatelessWidget {
  const _MarkBar({
    required this.label,
    required this.labels,
    required this.count,
    required this.path,
    required this.lost,
    required this.onLabel,
    required this.onPrint,
    required this.onClear,
    required this.onClose,
  });

  final String label;
  final List<String> labels;
  final int count;
  final String path;
  final int lost;
  final ValueChanged<String> onLabel;
  final VoidCallback onPrint;
  final VoidCallback onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // Nothing in here may need an Overlay.
    //
    // This bar is wrapped around MaterialApp.builder's child, which puts it
    // ABOVE the Navigator — so there is no Overlay above it to float anything
    // in. PopupMenuButton and Tooltip both quietly require one, and the first
    // frame in the real app threw "No Overlay widget found" because of it. The
    // labels are a handful, so they are laid out as chips rather than hidden
    // behind a menu that cannot open.
    return Material(
      color: const Color(0xFF14161F),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          // The whole bar scrolls sideways, and nothing in it is flexible.
          //
          // Sharing the width between flexible children still overflowed at
          // 460pt, because the fixed parts alone are wider than that. A debug
          // bar that paints a yellow overflow stripe across the app it exists
          // to help you look at is worse than useless, so it gives way
          // completely instead: everything keeps its natural size and the bar
          // scrolls to whatever will not fit.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(Icons.adjust, size: 20, color: Color(0xFFFF3B30)),
                const SizedBox(width: 10),
                const Text(
                  'Marking',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                for (final option in labels) ...[
                  _LabelChip(
                    label: option,
                    selected: option == label,
                    onTap: () => onLabel(option),
                  ),
                  const SizedBox(width: 6),
                ],
                const SizedBox(width: 10),
                Text(
                  // A dropped mark is shouted about here, not left to a line
                  // of terminal nobody was watching. The counter moving while
                  // nothing was stored is the exact failure this bar exists
                  // to make impossible to miss.
                  lost > 0
                      ? '$count marked · $lost LOST — see terminal'
                      : '$count marked · right-click to mark · ${_short(path)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: lost > 0 ? FontWeight.w800 : FontWeight.w400,
                    color: lost > 0
                        ? const Color(0xFFFF8A80)
                        : Colors.white60,
                  ),
                ),
                const SizedBox(width: 10),
                _BarAction(label: 'Print', onTap: onPrint),
                _BarAction(label: 'Clear', onTap: onClear, danger: true),
                _BarAction(label: 'Stop ⌘⇧M', onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The marks file with $HOME folded back to ~, so the bar says where it is
/// without spending half the window on it. The terminal prints it in full.
String _short(String path) {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty || !path.startsWith(home)) return path;
  return '~${path.substring(home.length)}';
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('mark_label_$label'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF3B30) : const Color(0xFF2A2E3D),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('mark_action_${label.split(' ').first.toLowerCase()}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: danger ? const Color(0xFFFF8A80) : Colors.white,
          ),
        ),
      ),
    );
  }
}
