import 'package:flutter/material.dart';

import '../../../../core/app_flow_hooks.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../domain/entity_link.dart';

/// A linked record, looked at without being opened for editing.
///
/// The slide-over shell is the one `showGroupViewDialog` established: right
/// edge, 560 wide, 220ms slide, so the panel it came from stays visible behind
/// it and walking a cluster is one tap per record.
///
/// **Pivoting is pop-then-reopen**, the same way the group dialog and the
/// barcode inspector already do it. `showGeneralDialog` is not re-entrant —
/// opening one from inside another stacks routes and the back button then has
/// to be pressed once per hop.
///
/// The body comes from the host through `AppFlowHooks.dieInspector` /
/// `machineInspector`, because a die's or machine's specs live on types
/// `core_erp` cannot see. An unregistered hook means the chip does not open at
/// all, which is this seam's documented degrade.
Future<void> showEcosystemInspector(
  BuildContext context, {
  required LinkRef subject,
}) {
  final body = AppFlowHooks.inspectorFor(context, subject.type, subject.id);
  if (body == null) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: subject.label,
    barrierColor: const Color(0x66100D1F),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, minWidth: 420),
            child: body,
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Walks from one inspector sheet to another in the linked cluster.
///
/// Pops the current sheet first so routes do not stack, then opens the
/// destination sheet.
Future<void> pivotEcosystemInspector(
  BuildContext context,
  LinkRef target,
) async {
  if (!AppFlowHooks.canInspect(target.type)) return;
  final navigator = Navigator.of(context);
  final rootContext = navigator.context;
  navigator.maybePop();
  await showEcosystemInspector(rootContext, subject: target);
}

/// The chrome every inspector shares: a title, the facts the host supplies, the
/// record's own ribbon, and one explicit way to edit.
///
/// Hosts build this from their own type so `core_erp` never needs to know what
/// a die is.
class EcosystemInspectorSheet extends StatelessWidget {
  const EcosystemInspectorSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.facts,
    required this.ribbon,
    this.extra,
    this.onEdit,
    this.missing = false,
  });

  final String title;
  final String subtitle;

  /// Label/value pairs. An absent fact is left out rather than shown empty —
  /// a blank row says "this is unset", which is usually not what is meant.
  final List<(String, String)> facts;

  /// The record's own `LinkedEcosystemRibbon`, so the cluster is walkable from
  /// either end.
  final Widget ribbon;

  /// Anything this record has that is neither a fact nor a link — a part's
  /// process route, for instance. Sits between the facts and the ribbon, and
  /// null means the record has nothing of the kind. A widget that renders
  /// `SizedBox.shrink()` is the same as null here, which is how a route the
  /// caller may not read disappears without leaving a heading behind.
  final Widget? extra;

  /// Null hides the button entirely. Editing is a deliberate second step, and
  /// a viewer with no editor behind it should not offer one.
  final Future<void> Function()? onEdit;

  /// The id resolved to nothing — a stale link, or a record deleted since.
  final bool missing;

  @override
  Widget build(BuildContext context) {
    return ErpFormScaffold(
      title: title,
      subtitle: subtitle,
      onClose: () => Navigator.of(context).maybePop(),
      body: missing
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  'This record is no longer there.',
                  style: TextStyle(
                    fontSize: 15,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (facts.isNotEmpty) ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final (label, value) in facts)
                        _InspectorFact(label: label, value: value),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                if (extra != null) ...[
                  extra!,
                  const SizedBox(height: 18),
                ],
                ribbon,
              ],
            ),
      footer: Row(
        children: [
          const Spacer(),
          if (onEdit != null)
            TextButton.icon(
              key: const ValueKey<String>('inspector_edit'),
              onPressed: () async {
                // Pop first: the editor is a dialog too, and leaving this one
                // underneath would stack them.
                Navigator.of(context).maybePop();
                await onEdit!();
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit', style: TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }
}

/// One labelled fact, mirroring the group view's `_Fact` so the two read alike.
class _InspectorFact extends StatelessWidget {
  const _InspectorFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
