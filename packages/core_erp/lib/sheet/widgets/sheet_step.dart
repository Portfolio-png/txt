import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/soft_erp_theme.dart';
import '../../core/utils/dropdown_intents.dart';

/// The item sheet from the keyboard, one component at a time.
///
/// A step is one thing that is filled in and saved on its own: a part line,
/// the company line, a person, the die form, the machine form. Tab moves
/// through its fields only (its other controls are left out of Tab, see
/// [SheetStep.noTab]); Tab past its last field asks whether to save it —
/// Save or Discard — and then goes on to the next step. Nothing to save, and
/// it goes on without asking. Shift+Tab goes back and never asks.
/// Ctrl+Enter (Cmd+Enter on a Mac) saves and starts another of the same.
///
/// A dropdown that Tab lands on opens by itself ([OpenDropdownIntent]); Tab
/// inside its list keeps the value and goes on ([TabOutIntent]).
///
/// [SheetFlow] knows the order of the steps on the screen and moves focus
/// between them; the host builds it, the steps register with it.

/// What a step does when it is left, or saved and another started.
class SheetStepActions {
  const SheetStepActions({
    required this.title,
    required this.isDirty,
    required this.save,
    required this.discard,
    this.blockedReason,
    this.saveAndAddAnother,
    this.isLocked,
    this.unlock,
    this.nextPage,
  });

  /// The prompt's question: "Save part 2?", "Save this contact?".
  final String Function() title;

  /// Something typed here that its save has not written.
  final bool Function() isDirty;

  /// Why a save would be refused now ("Pick Type first"), or null.
  final String? Function()? blockedReason;

  /// The step's own save. True when it is written.
  final Future<bool> Function() save;

  /// Puts the step back as it was.
  final FutureOr<void> Function() discard;

  /// Saves and opens a fresh one to type into. Null: Ctrl+Enter just saves.
  final Future<void> Function()? saveAndAddAnother;

  /// A saved row, closed until its Edit: Enter on one of its fields opens it.
  final bool Function()? isLocked;
  final VoidCallback? unlock;

  /// A step drawn in pages (the raw panel's Sheet planning, Material data,
  /// Review): Tab past a page's last field turns to the next page and stays —
  /// true. False on the last page, and the step is left as any other is.
  final bool Function()? nextPage;
}

/// Where a step sits on the screen, for [SheetFlow.order].
typedef SheetStepPlace = ({Object id, String section});

/// The order of the steps, and moving between them.
class SheetFlow {
  SheetFlow({required this.order, this.reveal, this.onEnd});

  /// Every step, top to bottom, as the screen draws them now.
  final List<SheetStepPlace> Function() order;

  /// Opens [section] (unfolds it) so a step in it can take focus.
  final void Function(String section)? reveal;

  /// Tab past the last step of the screen.
  final VoidCallback? onEnd;

  final Map<Object, SheetStepState> _steps = {};

  void _register(Object id, SheetStepState step) => _steps[id] = step;

  void _unregister(Object id, SheetStepState step) {
    if (identical(_steps[id], step)) _steps.remove(id);
  }

  /// Focus [id]'s first field (or its last, going backwards). [open]: Tab
  /// brought it here, so a dropdown there opens.
  void focusStep(Object id, {bool last = false, bool open = false}) {
    final place = order().where((p) => p.id == id).firstOrNull;
    if (place != null) reveal?.call(place.section);
    // After the frame: a section just unfolded has to be built before its
    // fields can take focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _steps[id]?.focusEdge(last: last, open: open);
    });
  }

  /// From [from] to the next step that is on screen.
  void moveOn(Object from) => _move(from, 1);

  /// From [from] to the step before it, onto its last field.
  void moveBack(Object from) => _move(from, -1);

  void _move(Object from, int step) {
    final places = order();
    final at = places.indexWhere((p) => p.id == from);
    if (at < 0) return;
    // A step not on the screen (no people yet, a section switched off) is
    // passed over; one in a folded section is still there, and is unfolded.
    for (var i = at + step; i >= 0 && i < places.length; i += step) {
      if (_steps.containsKey(places[i].id)) {
        focusStep(places[i].id, last: step < 0, open: step > 0);
        return;
      }
    }
    if (step > 0) onEnd?.call();
  }

  /// The first step, as the screen opens.
  void focusFirst() {
    final first = order().firstOrNull;
    if (first != null) focusStep(first.id);
  }
}

/// One component of the sheet, its fields in the order they are built.
class SheetStep extends StatefulWidget {
  const SheetStep({
    super.key,
    required this.flow,
    required this.id,
    required this.actions,
    required this.child,
  });

  final SheetFlow? flow;
  final Object id;
  final SheetStepActions actions;
  final Widget child;

  /// Leaves [child] clickable but out of Tab: a photo, a Save button, an
  /// icon. Tab on the sheet goes through what is filled in, and only that.
  static Widget noTab(Widget child) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        descendantsAreTraversable: false,
        child: child,
      );

  @override
  State<SheetStep> createState() => SheetStepState();
}

class SheetStepState extends State<SheetStep> {
  final FocusNode _node = FocusNode(
    debugLabel: 'sheet_step',
    skipTraversal: true,
    canRequestFocus: false,
  );
  final WidgetOrderTraversalPolicy _policy = WidgetOrderTraversalPolicy();
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    widget.flow?._register(widget.id, this);
  }

  @override
  void didUpdateWidget(covariant SheetStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || !identical(oldWidget.flow, widget.flow)) {
      oldWidget.flow?._unregister(oldWidget.id, this);
      widget.flow?._register(widget.id, this);
    }
  }

  @override
  void dispose() {
    widget.flow?._unregister(widget.id, this);
    _node.dispose();
    super.dispose();
  }

  /// The fields Tab visits here, in order.
  List<FocusNode> get _fields {
    final nodes = _node.traversalDescendants.toList();
    if (nodes.isEmpty) return nodes;
    return _policy.sortDescendants(nodes, nodes.first).toList();
  }

  /// Focus the first field (or the last), and bring it into view.
  void focusEdge({bool last = false, bool open = false}) {
    final fields = _fields;
    if (fields.isEmpty) return;
    _focus(last ? fields.last : fields.first, open: open);
  }

  /// [open]: Tab moved here going forward — a dropdown opens its list, so the
  /// next keys search it. Going back, it stays closed: Shift+Tab walks past.
  void _focus(FocusNode target, {bool open = false}) {
    target.requestFocus();
    final context = target.context;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 120),
      );
    }
    if (!open) return;
    // After the frame, once focus has landed — and only if it is still there:
    // a fast typist may already have moved on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = target.context;
      if (!mounted || _asking || !target.hasPrimaryFocus || at == null) return;
      Actions.maybeInvoke(at, const OpenDropdownIntent());
    });
  }

  /// Tab (or Shift+Tab) at [node]: the next field, or past the last one the
  /// save prompt and the next step. False when [node] is not one of ours.
  bool _tabFrom(FocusNode? node, {required bool back}) {
    final fields = _fields;
    final at = node == null ? -1 : fields.indexOf(node);
    if (at < 0) return false;
    if (back) {
      if (at == 0) {
        widget.flow?.moveBack(widget.id);
      } else {
        _focus(fields[at - 1]);
      }
      return true;
    }
    if (at == fields.length - 1) {
      unawaited(_leave());
    } else {
      _focus(fields[at + 1], open: true);
    }
    return true;
  }

  bool _isLast(FocusNode? node) {
    final fields = _fields;
    return node != null && fields.isNotEmpty && identical(fields.last, node);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || _asking) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final primary = FocusManager.instance.primaryFocus;
    final enter =
        key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;

    if (enter && (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      unawaited(_saveAndAddAnother());
      return KeyEventResult.handled;
    }
    if (enter && widget.actions.isLocked?.call() == true) {
      widget.actions.unlock?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      // The step moves focus itself, field to field in its own order. The
      // platform's "next focus" did not leave a text box in the running app
      // on macOS, and the order here is the one the fields are built in.
      return _tabFrom(primary, back: keyboard.isShiftPressed)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    // Enter in the last text box is Tab: it reaches here only when the
    // field did not take it (a dropdown opens on Enter itself).
    if (enter && _isLast(primary)) {
      unawaited(_leave());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Past the last field: ask, if there is anything to ask about, then go.
  Future<void> _leave() async {
    final actions = widget.actions;
    if (actions.nextPage?.call() ?? false) {
      // On to the page's first field once it is built. A page with nothing to
      // type (a review) is passed straight through, to the save prompt.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_fields.isEmpty) {
          unawaited(_leave());
        } else {
          focusEdge(open: true);
        }
      });
      return;
    }
    if (!actions.isDirty()) {
      widget.flow?.moveOn(widget.id);
      return;
    }
    _asking = true;
    final choice = await showStepSaveDialog(
      context,
      title: actions.title(),
      blockedReason: actions.blockedReason?.call(),
    );
    _asking = false;
    if (!mounted) return;
    switch (choice) {
      case StepChoice.save:
        if (await actions.save()) {
          if (mounted) widget.flow?.moveOn(widget.id);
        } else if (mounted) {
          focusEdge();
        }
      case StepChoice.discard:
        await actions.discard();
        if (mounted) widget.flow?.moveOn(widget.id);
      case null:
        // Stay: the dialog hands focus back to the last field.
        break;
    }
  }

  Future<void> _saveAndAddAnother() async {
    final actions = widget.actions;
    final another = actions.saveAndAddAnother;
    if (another != null) {
      await another();
      return;
    }
    if (await actions.save() && mounted) widget.flow?.moveOn(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        // A dropdown's list closed on Tab: on from that field, as Tab there.
        TabOutIntent: CallbackAction<TabOutIntent>(
          // Null when the field is not one of this step's: plain traversal.
          onInvoke: (intent) =>
              _tabFrom(intent.from, back: intent.back) ? true : null,
        ),
      },
      child: Focus(
        focusNode: _node,
        onKeyEvent: _onKey,
        child: FocusTraversalGroup(policy: _policy, child: widget.child),
      ),
    );
  }
}

/// What the save prompt answered. Null: stay and keep typing.
enum StepChoice { save, discard }

/// "Save part 2?" — Save (Enter) or Discard; Esc stays.
Future<StepChoice?> showStepSaveDialog(
  BuildContext context, {
  required String title,
  String? blockedReason,
}) {
  return showDialog<StepChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey<String>('step_save_dialog'),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blockedReason != null) ...[
            Text(
              'It cannot be saved yet: $blockedReason',
              style: const TextStyle(fontSize: 14, color: SoftErpTheme.dangerText),
            ),
            const SizedBox(height: 10),
          ],
          const Text(
            'Ctrl+Enter — save and add another',
            style: TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('step_discard'),
          onPressed: () => Navigator.of(dialogContext).pop(StepChoice.discard),
          child: const Text('Discard', style: TextStyle(fontSize: 14)),
        ),
        Tooltip(
          message: blockedReason ?? 'Enter',
          child: FilledButton(
            key: const ValueKey<String>('step_save'),
            autofocus: blockedReason == null,
            onPressed: blockedReason == null
                ? () => Navigator.of(dialogContext).pop(StepChoice.save)
                : null,
            child: const Text('Save', style: TextStyle(fontSize: 14)),
          ),
        ),
      ],
    ),
  );
}
