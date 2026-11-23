import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/soft_erp_theme.dart';
import 'key_tip_badge.dart';
import 'sheet_step.dart';

/// Which colour each tab is drawn in.
///
/// A tab takes the next colour the first time it is seen and keeps it until
/// it is closed: closing another tab, or one before it, recolours nothing.
/// Past the last colour the first comes round again.
class PartTabColors {
  /// [offset] starts the turn further along the colours — a strip drawn
  /// inside another's frame starts past that frame's colour.
  PartTabColors({int offset = 0}) : _next = offset;

  final Map<Object, int> _taken = <Object, int>{};
  int _next;

  /// The place of [key]'s colour in [SoftErpTheme.partTabGradients].
  int indexOf(Object key) => _taken.putIfAbsent(key, () {
    final index = _next % SoftErpTheme.partTabGradients.length;
    _next += 1;
    return index;
  });

  LinearGradient of(Object key) => SoftErpTheme.partTabGradients[indexOf(key)];

  /// Hands out colours in the order the tabs stand, and forgets tabs that are
  /// gone. Called with the tabs' keys before they are drawn.
  ///
  /// A tab that takes another's place in one step — a saved part loading onto
  /// the blank first row — keeps that tab's colour: it is the same tab. A tab
  /// closed and another opened later are two steps, and the new one moves on.
  void sync(Iterable<Object> keys) {
    final live = keys.toSet();
    final freed = <int>[];
    _taken.removeWhere((key, index) {
      if (live.contains(key)) return false;
      freed.add(index);
      return true;
    });
    for (final key in keys) {
      if (_taken.containsKey(key)) continue;
      if (freed.isNotEmpty) {
        _taken[key] = freed.removeAt(0);
      } else {
        indexOf(key);
      }
    }
  }
}

/// What a strip of [ColouredTabs] shows: so many tabs, one of them open.
///
/// A strip over a [Listenable] (a sheet's rows) repaints when it changes; a
/// strip handed a fresh [TabList] each build repaints with its host.
abstract class TabStrip implements Listenable {
  int get count;
  int get selected;

  /// Stable per tab, for its colour: a row key, a die's id.
  Object keyAt(int i);
  String titleAt(int i);

  /// A short second label beside the title — a code, a quotation. '' for none.
  String codeAt(int i);
  bool savedAt(int i);

  /// Why this tab's × cannot close it, or null when it can.
  String? closeWhyAt(int i);

  /// What the × does when it can — "Take off this part". Null: "Close this …".
  String? closeTipAt(int i);

  /// The tab's key by what it holds (`die_tab_31`), so it is found the same
  /// wherever it stands. Null: by its place (`<prefix>_tab_<i>`).
  String? keyNameAt(int i);
  void select(int i);
}

/// One tab of a [TabList].
class TabSpec {
  const TabSpec({
    required this.key,
    required this.title,
    this.code = '',
    this.saved = false,
    this.closeWhy,
    this.closeTip,
    this.keyName,
  });

  final Object key;
  final String title;
  final String code;
  final bool saved;
  final String? closeWhy;
  final String? closeTip;
  final String? keyName;
}

/// A [TabStrip] built from a list each time the host builds.
class TabList implements TabStrip {
  TabList({required this.tabs, required this.selected, required this.onSelect});

  final List<TabSpec> tabs;
  @override
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  int get count => tabs.length;
  @override
  Object keyAt(int i) => tabs[i].key;
  @override
  String titleAt(int i) => tabs[i].title;
  @override
  String codeAt(int i) => tabs[i].code;
  @override
  bool savedAt(int i) => tabs[i].saved;
  @override
  String? closeWhyAt(int i) => tabs[i].closeWhy;
  @override
  String? closeTipAt(int i) => tabs[i].closeTip;
  @override
  String? keyNameAt(int i) => tabs[i].keyName;
  @override
  void select(int i) => onSelect(i);
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// The colour's line, and the white coat inside it.
const double _ring = 2.4;
const double _coat = 0.8;

/// The frame's corners, the open tab's top corners, and the curve where the
/// tab's sides run out into the frame's top edge.
const double _frameRadius = 16;
const double _tabRadius = 14;
const double _flare = 16;
const double _taper = 3;

/// The frame's margin at the sides and the bottom.
const double _margin = 8;

/// Tabs a browser's way, and under them the open tab's content: one tab per
/// thing — a part, a company, a die, a machine — and + for another.
///
/// The open tab and its content are one outline in the tab's colour — the
/// line runs up round the tab and back down into the frame, with a white coat
/// inside it. The other tabs are grey pills carrying a swatch of their own
/// colour. The line fades to the next tab's colour when the tab changes, so a
/// change is seen.
class ColouredTabs extends StatefulWidget {
  const ColouredTabs({
    super.key,
    required this.strip,
    required this.colors,
    required this.onAdd,
    required this.onClose,
    required this.child,
    required this.noun,
    required this.plural,
    required this.keyPrefix,
    this.addKey,
    this.addWhy,
    this.addShortcut,
    this.fillHeight = false,
    this.showShortcuts = false,
  });

  final TabStrip strip;
  final PartTabColors colors;
  final VoidCallback onAdd;

  /// Closes the tab at [i]. The host asks first when it holds work.
  final Future<void> Function(int i) onClose;

  /// The open tab's content, drawn inside the frame.
  final Widget child;

  /// What a tab is, for the words round it: "part" / "parts".
  final String noun;
  final String plural;

  /// Keys: `<prefix>_tab_<i>`, `<prefix>_tab_close_<i>`, `<prefix>_frame`,
  /// `<plural>_overflow_menu`; + is [addKey] or `<prefix>_add`.
  final String keyPrefix;
  final String? addKey;

  /// Why + cannot add one now, or null when it can. Drawn disabled, not hidden.
  final String? addWhy;

  /// The key tip shown on + while Alt is held.
  final String? addShortcut;

  /// True: the content fills the height left (the sheet's parts). False: as
  /// tall as the content, for a strip inside a scrolling section.
  final bool fillHeight;
  final bool showShortcuts;

  @override
  State<ColouredTabs> createState() => _ColouredTabsState();
}

class _ColouredTabsState extends State<ColouredTabs>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _paintKey = GlobalKey();
  final GlobalKey _frameKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();
  final Map<int, GlobalKey> _tabKeys = {};
  final FrameTrail _trail = FrameTrail();

  GlobalKey _tabKeyFor(int i) => _tabKeys.putIfAbsent(
    i,
    () => GlobalKey(debugLabel: '${widget.keyPrefix}_tab_key_$i'),
  );

  static const double _gap = 6;
  static const double _tabHeight = 44;
  int _shown = -1;
  int _active = 0;
  int? _previous;

  late final AnimationController _shiftController;
  late final Animation<double> _shiftAnimation;
  late final Animation<double> _focusOpacity;
  late final Animation<Offset> _focusSlide;

  String get _nounTitle =>
      widget.noun.isEmpty ? '' : widget.noun[0].toUpperCase() + widget.noun.substring(1);

  @override
  void initState() {
    super.initState();
    _active = widget.strip.selected;
    _shiftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _shiftAnimation = CurvedAnimation(
      parent: _shiftController,
      curve: Curves.easeInOutCubic,
    );
    _focusOpacity = Tween<double>(begin: 0.70, end: 1.0).animate(
      CurvedAnimation(parent: _shiftController, curve: Curves.easeOutCubic),
    );
    _focusSlide = Tween<Offset>(
      begin: const Offset(0, 0.008),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _shiftController, curve: Curves.easeOutCubic));
    _shiftController.value = 1.0;
    widget.strip.addListener(_onStripChanged);
  }

  @override
  void didUpdateWidget(covariant ColouredTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.strip != widget.strip) {
      oldWidget.strip.removeListener(_onStripChanged);
      widget.strip.addListener(_onStripChanged);
    }
    _onStripChanged();
  }

  void _onStripChanged() {
    final now = widget.strip.selected;
    if (now != _active) {
      _previous = _active;
      _active = now;
      _shiftController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    widget.strip.removeListener(_onStripChanged);
    _shiftController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the open tab into view when it is opened some other way than a
  /// click on it (a shortcut, +, a save that moves on).
  void _reveal(int i, double tabWidth, int total) {
    if (i == _shown) return;
    _shown = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || i < 0) return;
      final position = _scroll.position;
      final start = i * (tabWidth + _gap);
      final isLast = i >= total - 1;
      final end = start + tabWidth + (isLast ? (widget.showShortcuts ? 84.0 : 44.0) : 0.0);
      double? to;
      if (start < position.pixels) {
        to = start;
      } else if (end > position.pixels + position.viewportDimension) {
        to = end - position.viewportDimension;
      }
      if (to != null) {
        _scroll.animateTo(
          to.clamp(0.0, position.maxScrollExtent),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.strip,
      builder: (context, _) {
        final strip = widget.strip;
        final keys = [for (var i = 0; i < strip.count; i += 1) strip.keyAt(i)];
        widget.colors.sync(keys);
        final open = strip.selected;
        final gradient = open >= 0 && open < keys.length
            ? widget.colors.of(keys[open])
            : SoftErpTheme.partTabGradients.first;
        final content = Padding(
          padding: const EdgeInsets.fromLTRB(_margin, 0, _margin, _margin),
          child: Padding(
            key: _frameKey,
            padding: const EdgeInsets.all(_ring + _coat),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                math.max(0, _frameRadius - _ring - _coat),
              ),
              child: FadeTransition(
                opacity: _focusOpacity,
                child: SlideTransition(position: _focusSlide, child: widget.child),
              ),
            ),
          ),
        );
        return TweenAnimationBuilder<LinearGradient>(
          tween: _GradientTween(end: gradient),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          builder: (context, shown, child) => AnimatedBuilder(
            animation: _shiftAnimation,
            builder: (context, _) => CustomPaint(
              key: ValueKey<String>('${widget.keyPrefix}_frame'),
              painter: PartFramePainter(
                gradient: shown,
                paintKey: _paintKey,
                frameKey: _frameKey,
                tabKey: _tabKeyFor(_active),
                previousTabKey: _previous != null ? _tabKeyFor(_previous!) : null,
                shiftProgress: _shiftAnimation.value,
                viewportKey: _viewportKey,
                trail: _trail,
                repaint: _scroll,
              ),
              child: child,
            ),
          ),
          child: Column(
            key: _paintKey,
            mainAxisSize: widget.fillHeight ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetStep.noTab(SizedBox(height: _tabHeight + 8, child: _strip())),
              if (widget.fillHeight) Expanded(child: content) else content,
            ],
          ),
        );
      },
    );
  }

  Widget _strip() {
    final strip = widget.strip;
    final count = strip.count;
    return Padding(
      // The first tab starts clear of the frame's corner, with room for the
      // curve that runs out of its side.
      padding: const EdgeInsets.fromLTRB(
        _margin + _frameRadius + _flare,
        8,
        _margin + _frameRadius + _flare,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (count >= 2) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _overviewMenu(),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: LayoutBuilder(
              key: _viewportKey,
              builder: (context, box) {
                final addWidth = widget.showShortcuts ? 76.0 : 36.0;
                final room = math.max(0.0, box.maxWidth - addWidth - _gap);
                // Tabs share the strip until they are too narrow to read,
                // then the strip scrolls.
                final width = count == 0
                    ? 150.0
                    : ((room - _gap * (count - 1)) / count).clamp(150.0, 260.0);
                _reveal(strip.selected, width, count);
                return SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < count; i += 1) ...[
                        if (i > 0) const SizedBox(width: _gap),
                        SizedBox(width: width, child: _tab(i)),
                      ],
                      const SizedBox(width: _gap),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _addButton(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _addButton() {
    final why = widget.addWhy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: why ?? 'Add a ${widget.noun}',
          child: IconButton(
            key: ValueKey<String>(widget.addKey ?? '${widget.keyPrefix}_add'),
            onPressed: why == null ? widget.onAdd : null,
            style: IconButton.styleFrom(
              backgroundColor: SoftErpTheme.cardSurface.withValues(alpha: 0.85),
              side: BorderSide(color: SoftErpTheme.border.withValues(alpha: 0.7)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              fixedSize: const Size(32, 32),
            ),
            icon: const Icon(Icons.add_rounded, size: 20, color: SoftErpTheme.textSecondary),
          ),
        ),
        if (widget.showShortcuts && widget.addShortcut != null) ...[
          const SizedBox(width: 4),
          KeyTipBadge(label: widget.addShortcut!),
        ],
      ],
    );
  }

  Widget _overviewMenu() {
    final strip = widget.strip;
    final count = strip.count;
    return PopupMenuButton<int>(
      tooltip: 'All open ${widget.plural} ($count)',
      offset: const Offset(0, 38),
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: SoftErpTheme.border),
      ),
      color: SoftErpTheme.cardSurface,
      elevation: 8,
      onSelected: strip.select,
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          enabled: false,
          height: 32,
          child: SizedBox(
            width: 280,
            child: Text(
              'OPEN ${widget.plural.toUpperCase()} ($count)',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: SoftErpTheme.textMuted,
              ),
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        for (var i = 0; i < count; i += 1)
          PopupMenuItem<int>(
            key: ValueKey<String>('${widget.plural}_menu_item_$i'),
            value: i,
            height: 42,
            child: _menuItemRow(i),
          ),
      ],
      child: Container(
        key: ValueKey<String>('${widget.plural}_overflow_menu'),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.more_vert_rounded, size: 18, color: SoftErpTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItemRow(int i) {
    final strip = widget.strip;
    final selected = strip.selected == i;
    final saved = strip.savedAt(i);
    final gradient = widget.colors.of(strip.keyAt(i));
    final code = strip.codeAt(i);
    return SizedBox(
      width: 280,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
          ),
          const SizedBox(width: 8),
          Text(
            '$_nounTitle ${i + 1}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              strip.titleAt(i),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? SoftErpTheme.textPrimary : SoftErpTheme.textSecondary,
              ),
            ),
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              code,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Icon(
            saved ? Icons.check_circle_rounded : Icons.edit_note_rounded,
            size: 16,
            color: saved ? SoftErpTheme.successText : SoftErpTheme.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _tab(int i) {
    final strip = widget.strip;
    final p = widget.keyPrefix;
    final selected = strip.selected == i;
    final saved = strip.savedAt(i);
    final gradient = widget.colors.of(strip.keyAt(i));
    final title = strip.titleAt(i);
    final code = strip.codeAt(i);
    final closeWhy = strip.closeWhyAt(i);
    final named = strip.keyNameAt(i);
    final tabKey = named ?? '${p}_tab_$i';

    final inside = Row(
      children: [
        if (!selected) ...[
          Container(
            key: ValueKey<String>('${p}_tab_swatch_$i'),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              boxShadow: [
                BoxShadow(
                  color: gradient.colors.first.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        Tooltip(
          message: saved ? 'Saved' : 'Not saved yet',
          child: Icon(
            saved ? Icons.check_circle_rounded : Icons.edit_rounded,
            size: 15,
            color: saved ? SoftErpTheme.successText : SoftErpTheme.textMuted.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 6),
        // Title and code apart; both cut with … rather than run past the tab.
        Expanded(
          child: Row(
            children: [
              Flexible(
                flex: 2,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? SoftErpTheme.textPrimary : SoftErpTheme.textSecondary,
                  ),
                ),
              ),
              if (code.isNotEmpty) ...[
                const SizedBox(width: 6),
                // Gives way too once the title is down to a few letters, so a
                // long type ("Power Press") never pushes past the tab's edge.
                Flexible(
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: selected
                        ? SoftErpTheme.accentSoft.withValues(alpha: 0.5)
                        : SoftErpTheme.cardSurfaceAlt.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
                    ),
                  ),
                ),
                ),
              ],
            ],
          ),
        ),
        Tooltip(
          message: closeWhy ?? strip.closeTipAt(i) ?? 'Close this ${widget.noun}',
          child: InkResponse(
            key: ValueKey<String>(named == null ? '${p}_tab_close_$i' : '${named}_close'),
            radius: 14,
            onTap: closeWhy == null ? () => widget.onClose(i) : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: closeWhy == null
                    ? (selected ? SoftErpTheme.textSecondary : SoftErpTheme.textMuted)
                    : SoftErpTheme.border,
              ),
            ),
          ),
        ),
      ],
    );

    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: selected ? _tabHeight : _tabHeight - 7,
      margin: selected ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
      padding: selected
          ? const EdgeInsets.fromLTRB(16, 2, 10, 0)
          : const EdgeInsets.fromLTRB(12, 0, 8, 0),
      decoration: BoxDecoration(
        color: selected ? Colors.transparent : SoftErpTheme.cardSurface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? Colors.transparent : SoftErpTheme.border.withValues(alpha: 0.55),
        ),
      ),
      child: selected
          ? KeyedSubtree(key: ValueKey<String>('${p}_tab_selected'), child: inside)
          : inside,
    );

    return Semantics(
      selected: selected,
      button: true,
      label: '$_nounTitle ${i + 1}: $title',
      child: GestureDetector(
        key: ValueKey<String>(tabKey),
        behavior: HitTestBehavior.opaque,
        onTap: () => strip.select(i),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            pill,
            // The painter finds the open tab through this key. It sits on an
            // empty box, never round the tab's content: a GlobalKey moved
            // mid-layout carries its tooltips along, and the overlay refuses
            // them (B66).
            Positioned.fill(
              child: IgnorePointer(child: SizedBox(key: _tabKeyFor(i))),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientTween extends Tween<LinearGradient> {
  _GradientTween({required LinearGradient end}) : super(end: end);

  @override
  LinearGradient lerp(double t) {
    final from = begin ?? end!;
    if (t >= 1) return end!;
    if (t <= 0) return from;
    return LinearGradient.lerp(from, end, t) ?? end!;
  }
}

/// Where the open tab was last drawn, kept by each strip for its own painter.
/// It used to be one static for every strip, so two strips on one screen
/// slid their tabs from each other's place.
class FrameTrail {
  Rect? lastTab;
}

/// The frame and the open tab as one line: up the tab's side, over its top,
/// down the other side and on round the content.
///
/// Where the tab and the frame are is read at paint time from the laid-out
/// boxes, so the line follows the tab as the strip scrolls with no frame of
/// lag.
class PartFramePainter extends CustomPainter {
  PartFramePainter({
    required this.gradient,
    required this.paintKey,
    required this.frameKey,
    required this.tabKey,
    this.previousTabKey,
    this.shiftProgress = 1.0,
    required this.viewportKey,
    FrameTrail? trail,
    super.repaint,
  }) : trail = trail ?? FrameTrail();

  final LinearGradient gradient;
  final GlobalKey paintKey;
  final GlobalKey frameKey;
  final GlobalKey tabKey;
  final GlobalKey? previousTabKey;
  final double shiftProgress;
  final GlobalKey viewportKey;
  final FrameTrail trail;

  Rect? _rectOf(GlobalKey key, RenderBox within) {
    final context = key.currentContext;
    if (context == null || !context.mounted) return null;
    try {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached || !within.attached) {
        return null;
      }
      return box.localToGlobal(Offset.zero, ancestor: within) & box.size;
    } catch (_) {
      return null;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final context = paintKey.currentContext;
    if (context == null || !context.mounted) return;
    try {
      final within = context.findRenderObject();
      if (within is! RenderBox || !within.hasSize || !within.attached) return;
      final frameBox = _rectOf(frameKey, within);
      if (frameBox == null) return;
      // The line's centre: half its width in from the frame's edge.
      final frame = frameBox.deflate((_ring + _coat) / 2);

      final current = _rectOf(tabKey, within);
      final before = previousTabKey != null ? _rectOf(previousTabKey!, within) : null;
      final Rect? tab;
      if (current != null && shiftProgress < 1.0) {
        tab = Rect.lerp(before ?? trail.lastTab ?? current, current, shiftProgress);
      } else {
        tab = current;
      }
      if (tab != null) trail.lastTab = tab;

      final path = outline(frame: frame, tab: tab, viewport: _rectOf(viewportKey, within));
      final shader = gradient.createShader(path.getBounds());

      // A soft halo in the middle colour.
      final glow = gradient.colors[gradient.colors.length ~/ 2];
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
          ..color = glow.withValues(alpha: 0.30),
      );
      // The card's own surface inside — white, not the colour.
      canvas.drawPath(path, Paint()..color = SoftErpTheme.cardSurface);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ring + _coat
          ..strokeJoin = StrokeJoin.round
          ..shader = shader,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _coat
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    } catch (_) {
      // A box can be mid-deactivation while painting; the next frame draws it.
    }
  }

  /// The outline of [frame] with [tab] standing on its top edge. A tab that
  /// is scrolled out of [viewport], or too narrow to draw, leaves the frame
  /// plain.
  static Path outline({required Rect frame, Rect? tab, Rect? viewport}) {
    const r = _frameRadius - _ring / 2;
    final path = Path()..moveTo(frame.left + r, frame.top);

    if (tab != null) {
      var left = tab.left;
      var right = tab.right;
      if (viewport != null) {
        left = math.max(left, viewport.left);
        right = math.min(right, viewport.right);
      }
      left = math.max(left, frame.left + r + _flare);
      right = math.min(right, frame.right - r - _flare);
      final top = tab.top + _ring / 2;
      if (right - left >= 2 * _tabRadius + 24 && frame.top - top > _tabRadius) {
        path
          ..lineTo(left - _flare, frame.top)
          ..cubicTo(left - _flare * 0.45, frame.top, left, frame.top - _flare * 0.45,
              left + _taper * 0.25, frame.top - _flare)
          ..lineTo(left + _taper, top + _tabRadius)
          ..cubicTo(left + _taper, top + _tabRadius * 0.45, left + _taper + _tabRadius * 0.45,
              top, left + _taper + _tabRadius, top)
          ..lineTo(right - _taper - _tabRadius, top)
          ..cubicTo(right - _taper - _tabRadius * 0.45, top, right - _taper,
              top + _tabRadius * 0.45, right - _taper, top + _tabRadius)
          ..lineTo(right - _taper * 0.25, frame.top - _flare)
          ..cubicTo(right, frame.top - _flare * 0.45, right + _flare * 0.45, frame.top,
              right + _flare, frame.top);
      }
    }

    path
      ..lineTo(frame.right - r, frame.top)
      ..arcToPoint(Offset(frame.right, frame.top + r), radius: const Radius.circular(r))
      ..lineTo(frame.right, frame.bottom - r)
      ..arcToPoint(Offset(frame.right - r, frame.bottom), radius: const Radius.circular(r))
      ..lineTo(frame.left + r, frame.bottom)
      ..arcToPoint(Offset(frame.left, frame.bottom - r), radius: const Radius.circular(r))
      ..lineTo(frame.left, frame.top + r)
      ..arcToPoint(Offset(frame.left + r, frame.top), radius: const Radius.circular(r))
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(PartFramePainter old) => true;
}
