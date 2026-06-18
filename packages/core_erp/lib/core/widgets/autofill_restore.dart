import 'package:flutter/widgets.dart';

/// Restores a text field to a default value when the user types a trailing
/// double space — a quick "give me the obvious value back" gesture for
/// auto-fill fields (challan/order numbers, dates) the user may have fiddled
/// with.
///
/// The value captured when this is attached is the restore target (i.e. the
/// value the dialog opened with). Pass [defaultValue] to override.
///
/// ponytail: triggers only on a trailing "  "; these fields never legitimately
/// hold double spaces, so that's a safe, predictable signal.
void attachDoubleSpaceRestore(
  TextEditingController controller, {
  String Function()? defaultValue,
}) {
  final captured = controller.text;
  controller.addListener(() {
    final text = controller.text;
    if (!text.endsWith('  ')) return;
    final restored = defaultValue?.call() ?? captured;
    if (text == restored) return;
    controller.value = TextEditingValue(
      text: restored,
      selection: TextSelection.collapsed(offset: restored.length),
    );
  });
}
