import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/soft_erp_theme.dart';
import '../sheet_binding.dart';
import '../sheet_controller.dart';
import '../sheet_draft.dart';
import 'key_tip_badge.dart';
import 'sheet_step.dart';

/// Which colour each part on the sheet is drawn in.
///
/// A part takes the next colour the first time it is seen and keeps it until
/// its tab is closed: closing another tab, or one before it, recolours
/// nothing. Past the last colour the first comes round again.
class PartTabColors {
  final Map<Object, int> _taken = <Object, int>{};
  int _next = 0;

  /// The place of [rowKey]'s colour in [SoftErpTheme.partTabGradients].
  int indexOf(Object rowKey) => _taken.putIfAbsent(rowKey, () {
    final index = _next % SoftErpTheme.partTabGradients.length;
    _next += 1;
    return index;
  });

  LinearGradient of(Object rowKey) =>
      SoftErpTheme.partTabGradients[indexOf(rowKey)];

  /// Hands out colours in the order the rows stand, and forgets rows that are
  /// gone. Called with the sheet's rows before they are drawn.
  ///
  /// A row that takes another's place in one step — a saved part loading onto
  /// the blank first row — keeps that row's colour: it is the same tab. A tab
  /// closed and another opened later are two steps, and the new one moves on.
  void sync(Iterable<Object> rowKeys) {
    final live = rowKeys.toSet();
    final freed = <int>[];
    _taken.removeWhere((key, index) {
      if (live.contains(key)) return false;
      freed.add(index);
      return true;
    });
    for (final key in rowKeys) {
      if (_taken.containsKey(key)) continue;
      if (freed.isNotEmpty) {
        _taken[key] = freed.removeAt(0);
      } else {
        indexOf(key);
      }
    }
  }
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

/// The frame's margin from the screen at the sides and the bottom.
const double _margin = 8;

/// The parts on the sheet as tabs, a browser's way, and under them the open
/// part's sheet: one per part, + for another.
///
/// The open tab and the sheet are one outline in the part's colour — the line
/// runs up round the tab and back down into the frame, with a white coat
/// inside it, and nothing filled. The other tabs are grey pills carrying a
/// swatch of their own colour. The line fades to the next part's colour when
/// the tab changes, so a change of part is seen.
class PartTabs extends StatefulWidget {
  const PartTabs({
    super.key,
    required this.sheet,
    required this.colors,
    required this.onAddPart,
    required this.onClose,
    required this.child,
    this.showShortcuts = false,
  });

  final SheetController sheet;
  final PartTabColors colors;
  final VoidCallback onAddPart;

  /// Closes the tab at a row. The host asks first when the part holds work.
  final Future<void> Function(int row) onClose;

  /// The open part's sheet, drawn inside the frame.
  final Widget child;
  final bool showShortcuts;

  /// What a tab calls its part: the name, or "New part" until it has one.
  static String titleOf(SheetController sheet, SheetDraft draft) {
    final def = sheet.sheetDef;
    final column = def.columnBoundTo(SheetBindsTo.name) ?? def.itemColumn;
    final value = column == null ? null : draft.get(column.id);
    final name = (value?.optionLabel ?? value?.textValue ?? '').trim();
    return name.isEmpty ? 'New part' : name;
  }

  static String codeOf(SheetController sheet, SheetDraft draft) {
    final column = sheet.sheetDef.columnBoundTo(SheetBindsTo.partCode);
    return column == null ? '' : (draft.get(column.id)?.textValue ?? '').trim();
  }

  @override
  State<PartTabs> createState() => _PartTabsState();
}

class _PartTabsState extends State<PartTabs>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _paintKey = GlobalKey();
  final GlobalKey _frameKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();
  final Map<int, GlobalKey> _tabKeys = {};

  GlobalKey _tabKeyFor(int row) =>
      _tabKeys.putIfAbsent(row, () => GlobalKey(debugLabel: 'part_tab_key_$row'));

  static const double _gap = 6;
  static const double _tabHeight = 44;
  int _shownRow = -1;
  int _activeRow = 0;
  int? _previousRow;

  late final AnimationController _shiftController;
  late final Animation<double> _shiftAnimation;
  late final Animation<double> _focusOpacity;
  late final Animation<Offset> _focusSlide;

  @override
  void initState() {
    super.initState();
    _activeRow = widget.sheet.row;
    _shiftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _shiftAnimation = CurvedAnimation(
      parent: _shiftController,
      curve: Curves.easeInOutCubic,
    );
    _focusOpacity = Tween<double>(begin: 0.70, end: 1.0).animate(
      CurvedAnimation(
        parent: _shiftController,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _focusSlide = Tween<Offset>(
      begin: const Offset(0, 0.008),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _shiftController,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _shiftController.value = 1.0;
    widget.sheet.addListener(_onSheetChanged);
  }

  @override
  void didUpdateWidget(covariant PartTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sheet != widget.sheet) {
      oldWidget.sheet.removeListener(_onSheetChanged);
      widget.sheet.addListener(_onSheetChanged);
      _activeRow = widget.sheet.row;
    }
  }

  void _onSheetChanged() {
    final currentRow = widget.sheet.row;
    if (currentRow != _activeRow) {
      _previousRow = _activeRow;
      _activeRow = currentRow;
      _shiftController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    widget.sheet.removeListener(_onSheetChanged);
    _shiftController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the chosen tab into view when the cursor lands on it by some
  /// other way than a click on it (Ctrl+Tab, +, a save that moves on).
  void _reveal(int row, double tabWidth, [int? totalCount]) {
    if (row == _shownRow) return;
    _shownRow = row;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final start = row * (tabWidth + _gap);
      final isLast = totalCount != null && row >= totalCount - 1;
      final end = start +
          tabWidth +
          (isLast ? (widget.showShortcuts ? 84.0 : 44.0) : 0.0);
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
    final sheet = widget.sheet;
    return ListenableBuilder(
      listenable: sheet,
      builder: (context, _) {
        final drafts = sheet.drafts;
        widget.colors.sync(drafts.map((d) => d.rowKey));
        final gradient = widget.colors.of(sheet.draft.rowKey);
        return TweenAnimationBuilder<LinearGradient>(
          tween: _GradientTween(end: gradient),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          builder: (context, shown, child) => AnimatedBuilder(
            animation: _shiftAnimation,
            builder: (context, _) => CustomPaint(
              key: const ValueKey<String>('part_frame'),
              painter: PartFramePainter(
                gradient: shown,
                paintKey: _paintKey,
                frameKey: _frameKey,
                tabKey: _tabKeyFor(_activeRow),
                previousTabKey:
                    _previousRow != null ? _tabKeyFor(_previousRow!) : null,
                shiftProgress: _shiftAnimation.value,
                viewportKey: _viewportKey,
                repaint: _scroll,
              ),
              child: child,
            ),
          ),
          child: Column(
            key: _paintKey,
            children: [
              SheetStep.noTab(
                SizedBox(height: _tabHeight + 8, child: _strip(drafts)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _margin,
                    0,
                    _margin,
                    _margin,
                  ),
                  child: Padding(
                    key: _frameKey,
                    padding: const EdgeInsets.all(_ring + _coat),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        math.max(0, _frameRadius - _ring - _coat),
                      ),
                      child: FadeTransition(
                        opacity: _focusOpacity,
                        child: SlideTransition(
                          position: _focusSlide,
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _strip(List<SheetDraft> drafts) {
    final sheet = widget.sheet;
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
          if (drafts.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _tabsOverviewMenu(drafts),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: LayoutBuilder(
              key: _viewportKey,
              builder: (context, box) {
                final count = drafts.length;
                final addBtnWidth = widget.showShortcuts ? 76.0 : 36.0;
                final availableForTabs =
                    math.max(0.0, box.maxWidth - addBtnWidth - _gap);
                // Tabs share the strip until they are too narrow to read,
                // then the strip scrolls.
                final width = ((availableForTabs - _gap * (count - 1)) / count)
                    .clamp(150.0, 260.0);
                _reveal(sheet.row, width, count);
                return SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var row = 0; row < count; row += 1) ...[
                        if (row > 0) const SizedBox(width: _gap),
                        SizedBox(width: width, child: _tab(row, drafts[row])),
                      ],
                      const SizedBox(width: _gap),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _addPartButton(),
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

  Widget _addPartButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Tooltip(
          message: 'Add a part',
          child: IconButton(
            key: const ValueKey<String>('part_add_row'),
            onPressed: widget.onAddPart,
            splashRadius: 16,
            style: IconButton.styleFrom(
              backgroundColor: SoftErpTheme.cardSurface.withValues(alpha: 0.85),
              side: BorderSide(
                color: SoftErpTheme.border.withValues(alpha: 0.7),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              fixedSize: const Size(32, 32),
            ),
            icon: const Icon(
              Icons.add_rounded,
              size: 20,
              color: SoftErpTheme.textSecondary,
            ),
          ),
        ),
        if (widget.showShortcuts) ...[
          const SizedBox(width: 4),
          const KeyTipBadge(label: 'Alt+1'),
        ],
      ],
    );
  }

  Widget _tabsOverviewMenu(List<SheetDraft> drafts) {
    final sheet = widget.sheet;
    return PopupMenuButton<int>(
      tooltip: 'All open parts (${drafts.length})',
      offset: const Offset(0, 38),
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: SoftErpTheme.border),
      ),
      color: SoftErpTheme.cardSurface,
      elevation: 8,
      onSelected: (row) {
        sheet.selectRow(row);
      },
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          enabled: false,
          height: 32,
          child: SizedBox(
            width: 260,
            child: Text(
              'OPEN PARTS (${drafts.length})',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: SoftErpTheme.textMuted,
              ),
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        for (var i = 0; i < drafts.length; i += 1)
          PopupMenuItem<int>(
            key: ValueKey<String>('parts_menu_item_$i'),
            value: i,
            height: 42,
            child: _menuItemRow(i, drafts[i]),
          ),
      ],
      child: Container(
        key: const ValueKey<String>('parts_overflow_menu'),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SoftErpTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: SoftErpTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              '${drafts.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItemRow(int row, SheetDraft draft) {
    final sheet = widget.sheet;
    final selected = sheet.row == row;
    final saved = draft.entityId != null;
    final gradient = widget.colors.of(draft.rowKey);
    final title = PartTabs.titleOf(sheet, draft);
    final code = PartTabs.codeOf(sheet, draft);

    return SizedBox(
      width: 260,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
          ),
          const SizedBox(width: 8),
          Text(
            'Part ${row + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? SoftErpTheme.textPrimary
                    : SoftErpTheme.textSecondary,
              ),
            ),
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: SoftErpTheme.cardSurfaceAlt,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Icon(
            saved ? Icons.check_circle_rounded : Icons.edit_note_rounded,
            size: 15,
            color: saved ? SoftErpTheme.successText : SoftErpTheme.textMuted,
          ),
          if (selected) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check_rounded, size: 16, color: SoftErpTheme.accent),
          ],
        ],
      ),
    );
  }

  Widget _tab(int row, SheetDraft draft) {
    final sheet = widget.sheet;
    final selected = sheet.row == row;
    final saved = draft.entityId != null;
    final gradient = widget.colors.of(draft.rowKey);
    final title = PartTabs.titleOf(sheet, draft);
    final code = PartTabs.codeOf(sheet, draft);
    // The line's own rule: a saved part is not taken off the sheet by an ×.
    final String? closeWhy = saved
        ? 'Saved parts stay in the catalogue — use Archive part'
        : (sheet.rowCount <= 1 ? 'A sheet always keeps one part' : null);

    final inside = Row(
      children: [
        if (!selected) ...[
          Container(
            key: ValueKey<String>('part_tab_swatch_$row'),
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
            color: saved
                ? SoftErpTheme.successText
                : SoftErpTheme.textMuted.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 6),
        // Name and code apart: the name gives way first, the code stays whole.
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? SoftErpTheme.textPrimary
                        : SoftErpTheme.textSecondary,
                  ),
                ),
              ),
              if (code.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? SoftErpTheme.accentSoft.withValues(alpha: 0.5)
                        : SoftErpTheme.cardSurfaceAlt.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    code,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? SoftErpTheme.accent
                          : SoftErpTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Tooltip(
          message: closeWhy ?? 'Close this part',
          child: InkResponse(
            key: ValueKey<String>('part_tab_close_$row'),
            radius: 14,
            onTap: closeWhy == null ? () => widget.onClose(row) : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: closeWhy == null
                    ? (selected
                          ? SoftErpTheme.textSecondary
                          : SoftErpTheme.textMuted)
                    : SoftErpTheme.border,
              ),
            ),
          ),
        ),
      ],
    );

    final tabPill = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: selected ? _tabHeight : _tabHeight - 7,
      margin: selected ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
      padding: selected
          ? const EdgeInsets.fromLTRB(16, 2, 10, 0)
          : const EdgeInsets.fromLTRB(12, 0, 8, 0),
      decoration: BoxDecoration(
        color: selected
            ? Colors.transparent
            : SoftErpTheme.cardSurface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? Colors.transparent
              : SoftErpTheme.border.withValues(alpha: 0.55),
        ),
        boxShadow: selected
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: selected
          ? KeyedSubtree(
              key: const ValueKey<String>('part_tab_selected'),
              child: inside,
            )
          : inside,
    );

    return Semantics(
      selected: selected,
      button: true,
      label: 'Part ${row + 1}: $title',
      child: GestureDetector(
        key: ValueKey<String>('part_tab_$row'),
        behavior: HitTestBehavior.opaque,
        onTap: () => sheet.selectRow(row),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            tabPill,
            Positioned.fill(
              child: IgnorePointer(
                child: SizedBox(key: _tabKeyFor(row)),
              ),
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

/// The frame and the open tab as one line: up the tab's side, over its top,
/// down the other side and on round the sheet.
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
    super.repaint,
  });

  final LinearGradient gradient;
  final GlobalKey paintKey;
  final GlobalKey frameKey;
  final GlobalKey tabKey;
  final GlobalKey? previousTabKey;
  final double shiftProgress;
  final GlobalKey viewportKey;

  static Rect? _lastRenderedTab;

  Rect? _rectOf(GlobalKey key, RenderBox within) {
    final context = key.currentContext;
    if (context == null || !context.mounted) return null;
    try {
      final box = context.findRenderObject();
      if (box is! RenderBox ||
          !box.hasSize ||
          !box.attached ||
          !within.attached) {
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

      final currentTabBox = _rectOf(tabKey, within);
      final prevTabBox =
          previousTabKey != null ? _rectOf(previousTabKey!, within) : null;
      final Rect? effectiveTab;
      if (currentTabBox != null && shiftProgress < 1.0) {
        final from = prevTabBox ?? _lastRenderedTab ?? currentTabBox;
        effectiveTab = Rect.lerp(from, currentTabBox, shiftProgress);
      } else {
        effectiveTab = currentTabBox;
      }
      if (effectiveTab != null) {
        _lastRenderedTab = effectiveTab;
      }

      final path = outline(
        frame: frame,
        tab: effectiveTab,
        viewport: _rectOf(viewportKey, within),
      );
      final bounds = path.getBounds();
      final shader = gradient.createShader(bounds);

      // Layer 1: Ambient chromatic glow (neon atmospheric halo, like modern AI UIs)
      final glowColor = gradient.colors[gradient.colors.length ~/ 2];
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
          ..color = glowColor.withValues(alpha: 0.30),
      );

      // Layer 2: Solid crisp card surface fill inside the tab and container
      canvas.drawPath(path, Paint()..color = SoftErpTheme.cardSurface);

      // Layer 3: Vibrant chromatic gradient core outline
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ring + _coat
          ..strokeJoin = StrokeJoin.round
          ..shader = shader,
      );

      // Layer 4: Ultra-crisp thin white coating core line down the center
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _coat
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    } catch (_) {
      // Guard against layout/paint race conditions during element deactivation
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
          // Smooth bell-curve shoulder: leaves frame.top horizontally and meets tab.left with soft taper
          ..cubicTo(
            left - _flare * 0.45,
            frame.top,
            left,
            frame.top - _flare * 0.45,
            left + _taper * 0.25,
            frame.top - _flare,
          )
          ..lineTo(left + _taper, top + _tabRadius)
          ..cubicTo(
            left + _taper,
            top + _tabRadius * 0.45,
            left + _taper + _tabRadius * 0.45,
            top,
            left + _taper + _tabRadius,
            top,
          )
          ..lineTo(right - _taper - _tabRadius, top)
          ..cubicTo(
            right - _taper - _tabRadius * 0.45,
            top,
            right - _taper,
            top + _tabRadius * 0.45,
            right - _taper,
            top + _tabRadius,
          )
          ..lineTo(right - _taper * 0.25, frame.top - _flare)
          ..cubicTo(
            right,
            frame.top - _flare * 0.45,
            right + _flare * 0.45,
            frame.top,
            right + _flare,
            frame.top,
          );
      }
    }

    path
      ..lineTo(frame.right - r, frame.top)
      ..arcToPoint(
        Offset(frame.right, frame.top + r),
        radius: const Radius.circular(r),
      )
      ..lineTo(frame.right, frame.bottom - r)
      ..arcToPoint(
        Offset(frame.right - r, frame.bottom),
        radius: const Radius.circular(r),
      )
      ..lineTo(frame.left + r, frame.bottom)
      ..arcToPoint(
        Offset(frame.left, frame.bottom - r),
        radius: const Radius.circular(r),
      )
      ..lineTo(frame.left, frame.top + r)
      ..arcToPoint(
        Offset(frame.left + r, frame.top),
        radius: const Radius.circular(r),
      )
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(PartFramePainter old) => true;
}
