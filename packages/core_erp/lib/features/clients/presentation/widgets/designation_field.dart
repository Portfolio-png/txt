import 'package:flutter/material.dart';

/// What a contact is at their company.
///
/// A suggestion list, not an enum. The sketch this came from ends its own list
/// with "Others", and a vocabulary with an escape hatch is not a vocabulary —
/// so the column is free text, exactly like `employees.role`, and the only
/// near-enum in this repo is a Dart-side map the server never enforces.
const List<String> kDesignationSuggestions = <String>[
  'Proprietor',
  'Partner',
  'Director',
  'Managing Director',
  'Manager',
  'Purchase Manager',
  'Engineer',
  'Supervisor',
  'Accountant',
];

/// A designation field: type anything, or pick one of the usual answers.
class DesignationField extends StatelessWidget {
  const DesignationField({
    super.key,
    required this.controller,
    this.label = 'Designation',
    this.helper = 'What they are at their company',
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String helper;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(fontSize: 14),
      onChanged: (_) => onChanged?.call(),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
        // Drawn even when disabled rather than hidden, so the affordance is
        // never something someone has to be told exists.
        suffixIcon: PopupMenuButton<String>(
          enabled: enabled,
          tooltip: 'Common designations',
          icon: const Icon(Icons.arrow_drop_down_rounded),
          itemBuilder: (context) => [
            for (final suggestion in kDesignationSuggestions)
              PopupMenuItem<String>(
                value: suggestion,
                child: Text(suggestion, style: const TextStyle(fontSize: 14)),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: '',
              child: Text(
                'Something else…',
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
              ),
            ),
          ],
          onSelected: (value) {
            controller.text = value;
            controller.selection = TextSelection.collapsed(
              offset: value.length,
            );
            onChanged?.call();
          },
        ),
      ),
    );
  }
}
