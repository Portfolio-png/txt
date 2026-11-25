import 'package:flutter/material.dart';

import '../../core/widgets/app_button.dart';

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
  Widget build(BuildContext context) {
    final button = AppButton(
      key: buttonKey,
      label: label,
      icon: Icons.save_outlined,
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
  const SheetSaveRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ...children,
        // The × the part line has after Save Part, held but not drawn.
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
      ],
    );
  }
}
