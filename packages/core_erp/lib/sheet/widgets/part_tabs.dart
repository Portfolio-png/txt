import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/soft_erp_theme.dart';
import '../sheet_binding.dart';
import '../sheet_controller.dart';
import '../sheet_draft.dart';
import 'key_tip_badge.dart';

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

/// The colour's ring and the white coat inside it — the tab's and the frame's.
const double _ring = 3;
const double _coat = 2;

/// The parts on the sheet as tabs, a browser's way: one per part, + for
/// another. The chosen tab is ringed in its part's colour; the others carry a
/// swatch of theirs.
class PartTabs extends StatefulWidget {
  const PartTabs({
    super.key,
    required this.sheet,
    required this.colors,
    required this.onAddPart,
    required this.onClose,
    this.showShortcuts = false,
  });

  final SheetController sheet;
  final PartTabColors colors;
  final VoidCallback onAddPart;

  /// Closes the tab at a row. The host asks first when the part holds work.
  final Future<void> Function(int row) onClose;
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

class _PartTabsState extends State<PartTabs> {
  final ScrollController _scroll = ScrollController();
  static const double _gap = 6;
  int _shownRow = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the chosen tab into view when the cursor lands on it by some
  /// other way than a click on it (Ctrl+Tab, +, a save that moves on).
  void _reveal(int row, double tabWidth) {
    if (row == _shownRow) return;
    _shownRow = row;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final start = row * (tabWidth + _gap);
      final end = start + tabWidth;
      double? to;
      if (start < position.pixels) {
        to = start;
      } else if (end > position.pixels + position.viewportDimension) {
        to = end - position.viewportDimension;
      }
      if (to != null) {
        _scroll.jumpTo(to.clamp(0.0, position.maxScrollExtent));
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final count = drafts.length;
                    // Tabs share the strip until they are too narrow to read,
                    // then the strip scrolls.
                    final width = ((box.maxWidth - _gap * (count - 1)) / count)
                        .clamp(150.0, 260.0);
                    _reveal(sheet.row, width);
                    return SingleChildScrollView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var row = 0; row < count; row += 1) ...[
                            if (row > 0) const SizedBox(width: _gap),
                            SizedBox(
                              width: width,
                              child: _tab(row, drafts[row]),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Add a part',
                child: IconButton(
                  key: const ValueKey<String>('part_add_row'),
                  onPressed: widget.onAddPart,
                  style: IconButton.styleFrom(
                    backgroundColor: SoftErpTheme.cardSurface,
                    side: const BorderSide(color: SoftErpTheme.borderStrong),
                    shape: const CircleBorder(),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 22),
                ),
              ),
              if (widget.showShortcuts) ...[
                const SizedBox(width: 4),
                const KeyTipBadge(label: 'Alt+1'),
              ],
            ],
          ),
        );
      },
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
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Tooltip(
          message: saved ? 'Saved' : 'Not saved yet',
          child: Icon(
            saved ? Icons.check_circle_rounded : Icons.edit_rounded,
            size: 16,
            color: saved ? SoftErpTheme.successText : SoftErpTheme.textMuted,
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
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? SoftErpTheme.textPrimary
                        : SoftErpTheme.textSecondary,
                  ),
                ),
              ),
              if (code.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  code,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SoftErpTheme.textSecondary,
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
            radius: 16,
            onTap: closeWhy == null ? () => widget.onClose(row) : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: closeWhy == null
                    ? SoftErpTheme.textSecondary
                    : SoftErpTheme.border,
              ),
            ),
          ),
        ),
      ],
    );

    const height = 42.0;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Part ${row + 1}: $title',
      child: GestureDetector(
        key: ValueKey<String>('part_tab_$row'),
        behavior: HitTestBehavior.opaque,
        onTap: () => sheet.selectRow(row),
        child: selected
            ? Container(
                key: const ValueKey<String>('part_tab_selected'),
                height: height,
                padding: const EdgeInsets.all(_ring),
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.cardSurface,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                  child: inside,
                ),
              )
            : Container(
                height: height,
                padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                decoration: BoxDecoration(
                  color: SoftErpTheme.cardSurfaceAlt,
                  borderRadius: BorderRadius.circular(height / 2),
                  border: Border.all(color: SoftErpTheme.borderStrong),
                ),
                child: inside,
              ),
      ),
    );
  }
}

/// The sheet's working area, ringed in the chosen part's colour: the colour
/// outside, a white coat inside it, then the sheet. The ring fades to the
/// next part's colour when the tab changes, so a change of part is seen.
class PartFrame extends StatelessWidget {
  const PartFrame({super.key, required this.gradient, required this.child});

  final LinearGradient gradient;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = SoftErpTheme.radiusMd;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: AnimatedContainer(
        key: const ValueKey<String>('part_frame'),
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(_ring),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Container(
          padding: const EdgeInsets.all(_coat),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius - _ring),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              math.max(0, radius - _ring - _coat),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
