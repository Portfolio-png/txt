import 'package:flutter/widgets.dart';

/// Sent to a field that Tab has just moved onto. A dropdown opens its list;
/// anything else (a text box) has no handler and ignores it.
///
/// Sent only by a keyboard flow (the item sheet's [SheetStep]) going forward
/// — not by a click, not by focus coming back after a pick, not by Shift+Tab —
/// so a list never reopens by itself after it closes.
class OpenDropdownIntent extends Intent {
  const OpenDropdownIntent();
}

/// Tab (or Shift+Tab) pressed inside an open list: the list closes, keeping
/// what the field had, and the field asks whatever holds it to move on — the
/// same as Tab on the closed field would.
class TabOutIntent extends Intent {
  const TabOutIntent({required this.from, this.back = false});

  /// The field the list belonged to. Named rather than read from the focus
  /// manager: focus asked for a moment ago has not landed yet.
  final FocusNode from;
  final bool back;
}

/// Moves on from [field] after its list closed on Tab: the keyboard flow
/// holding it when there is one, else plain focus traversal.
void tabOutFrom(FocusNode field, {required bool back}) {
  final context = field.context;
  if (context == null) return;
  if (Actions.maybeInvoke(context, TabOutIntent(from: field, back: back)) != null) return;
  back ? field.previousFocus() : field.nextFocus();
}
