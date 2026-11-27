import 'package:flutter/material.dart';

import '../../core/widgets/app_button.dart';
import 'coloured_tabs.dart';

/// The one Save on the item sheet — every section's (part, company, die,
/// machine, route, raw sheet) is this, so they read alike: "Save <Thing>",
/// the save icon, outlined, the compact size.
///
/// Owner, 2026-11-25: "keep save button consistency, let it be uniform".
///
/// Outlined, never filled, on purpose: Cmd/Ctrl+Enter fires the last enabled
/// FILLED button on the screen, and on the sheet that must stay Done. A filled
/// Save route or Save raw sheet drawn inside the sheet would take it.
///
/// [tooltip] says what this save does beyond its label — a die held until the
/// part exists, a die linked rather than made — or why it is off.
class SheetSaveButton extends StatelessWidget {
  const SheetSaveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.isLoading = false,
    this.tooltip,
  });

  /// "Save Part", "Save Die" … — always starting "Save".
  final String label;
  final VoidCallback? onPressed;

  /// The key the button itself carries (tests and the keyboard find it).
  final Key? buttonKey;
  final bool isLoading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => SheetActionButton(
    buttonKey: buttonKey,
    label: label,
    icon: Icons.save_outlined,
    tooltip: tooltip,
    isLoading: isLoading,
    onPressed: onPressed,
  );
}

/// Every other button in a section's save row — Cancel, Edit, Next,
/// Minimise — drawn exactly as [SheetSaveButton] is: outlined, compact, an
/// icon and a label, the same height. Owner, 2026-11-25: "keep consistency
/// in UI buttons" — a purple text-link Cancel beside an outlined Save Die
/// read as two kinds of thing.
class SheetActionButton extends StatelessWidget {
  const SheetActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.buttonKey,
    this.isLoading = false,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Key? buttonKey;
  final bool isLoading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = AppButton(
      key: buttonKey,
      label: label,
      icon: icon,
      variant: AppButtonVariant.secondary,
      dense: true,
      isLoading: isLoading,
      onPressed: onPressed,
    );
    final message = tooltip?.trim() ?? '';
    return message.isEmpty ? button : Tooltip(message: message, child: button);
  }
}

/// A section's buttons at the sheet's save column: right-aligned, ending where
/// the part line's Save Part does (owner, 2026-11-25: "the way Save Part is
/// placed … in that same column place Save Company … Save Machine, Save Die
/// and Save Route").
///
/// The part line ends Save Part with its × (an [IconButton]); every other
/// section has no ×, so an invisible one of the same size holds the place and
/// their Saves stop at the same x.
class SheetSaveRow extends StatelessWidget {
  const SheetSaveRow({
    super.key,
    required this.children,
    this.unframed = false,
    this.shrinkWrap = false,
  });

  /// As wide as its buttons, not the whole width — for a [TuckedSaveRow],
  /// which puts it at the right edge itself.
  final bool shrinkWrap;

  /// True for a section with no [ColouredTabs] frame round it (Routing): its
  /// row ends [unframedInset] further in, where the framed ones' Saves end.
  final bool unframed;

  /// What ends a save row after its last button: the part line's × held
  /// but not drawn, and, [unframed], the frame's room. For a row that is not
  /// a [SheetSaveRow] — the Routing card's — so its button ends in line too.
  static List<Widget> end({bool unframed = false}) => [
    ExcludeSemantics(
      child: Visibility(
        visible: false,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: IconButton(
          onPressed: null,
          icon: const Icon(Icons.close, size: 18),
        ),
      ),
    ),
    if (unframed) const SizedBox(width: unframedInset),
  ];

  /// What a section framed in [ColouredTabs] (Developed For, Dies, Machines)
  /// pads its form by inside the frame. One value, so their Saves line up.
  static const EdgeInsets framedPadding = EdgeInsets.fromLTRB(14, 12, 14, 12);

  /// How far in from a section's edge a framed section's Save ends: the
  /// frame, then [framedPadding]. A section with no frame round its row —
  /// the part line — ends its row this far in, so Save Part / Edit stands
  /// in the same column as Save Company, Save Die and Save Machine (owner,
  /// 2026-11-25, a line drawn down the screen: they were 25 px apart).
  static const double unframedInset =
      ColouredTabs.contentInset + 14; // framedPadding.right

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ...children,
        ...end(unframed: unframed),
      ],
    );
  }
}
