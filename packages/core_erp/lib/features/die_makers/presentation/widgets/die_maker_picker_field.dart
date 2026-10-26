import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/searchable_select.dart';
import '../../domain/die_maker.dart';
import '../providers/die_makers_provider.dart';
import '../screens/die_maker_editor.dart';

/// Picks who made a die, and makes one when nobody has.
///
/// A thin wrapper over [SearchableSelectField], the way `GroupPickerField`
/// wraps it — typing a name that is not in the master offers to add it, and
/// accepting opens the real die maker editor seeded with what was typed. The
/// created record comes straight back as the selection, so there is no reload
/// race between the picker's list and the row that was just written.
///
/// This replaces a plain text field with five "names used before" chips. The
/// chips were the useful half of a master without the maintenance, which was
/// migration 048's argument; what they could not do is tell you the toolroom's
/// number when a die is late.
///
/// [fallbackName] is the free text on an existing die whose maker was never a
/// record. Those dies are not broken and are not migrated, so the field has to
/// be able to show a name it cannot resolve to an id.
class DieMakerPickerField extends StatelessWidget {
  const DieMakerPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.fallbackName = '',
    this.tapTargetKey,
    this.label = 'Die Made By',
    this.helper = 'Whoever cut it — a fitter here, or an outside toolroom',
  });

  final int? value;
  final String fallbackName;

  /// The chosen maker, or null when cleared. The name rides along so the
  /// caller can keep the free text in step with the id.
  final void Function(DieMaker? maker) onChanged;

  final Key? tapTargetKey;
  final String label;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DieMakersProvider>();
    final makers = provider.selectable;
    final selected = provider.byId(value);

    // An unresolved name still has to show. Offered as a real option so the
    // field can display it, but it carries no id — picking anything else
    // replaces it, which is how a die gets attached to the master over time.
    final showsFallback =
        selected == null && fallbackName.trim().isNotEmpty;

    final options = <SearchableSelectOption<int?>>[
      if (showsFallback)
        SearchableSelectOption<int?>(
          value: -1,
          label: fallbackName.trim(),
          subtitle: 'typed on this die — not in the master',
        ),
      for (final maker in makers)
        SearchableSelectOption<int?>(
          value: maker.id,
          label: maker.displayLabel,
          subtitle: maker.pickerSubtitle.isEmpty ? null : maker.pickerSubtitle,
          searchText: maker.searchText,
        ),
    ];

    return SearchableSelectField<int?>(
      tapTargetKey: tapTargetKey,
      value: showsFallback ? -1 : value,
      options: options,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperStyle: const TextStyle(fontSize: 13),
        labelStyle: const TextStyle(fontSize: 14),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      dialogTitle: 'Who made this die?',
      searchHintText: 'Search die makers',
      emptyText: 'No die makers yet. Type a name to add the first.',
      canCreateOption: (query, _) => query.trim().isNotEmpty,
      createOptionLabelBuilder: (query) => 'Add die maker "$query"',
      onCreateOption: (query) async {
        final typed = query.trim();

        // A name already in the master is a pick, not a create. The server
        // would refuse the duplicate anyway; answering here means the shop
        // never sees an error for doing something reasonable.
        final existing = provider.byName(typed);
        if (existing != null) {
          onChanged(existing);
          return SearchableSelectOption<int?>(
            value: existing.id,
            label: existing.displayLabel,
            subtitle: existing.pickerSubtitle.isEmpty
                ? null
                : existing.pickerSubtitle,
          );
        }

        final created = await DieMakerEditor.open(context, initialName: typed);
        if (created == null) return null;
        onChanged(created);
        return SearchableSelectOption<int?>(
          value: created.id,
          label: created.displayLabel,
          subtitle: created.pickerSubtitle.isEmpty
              ? null
              : created.pickerSubtitle,
        );
      },
      onChanged: (picked) {
        if (picked == null || picked == -1) {
          // -1 is the unresolved free text; choosing it changes nothing.
          if (picked == null) onChanged(null);
          return;
        }
        onChanged(provider.byId(picked));
      },
    );
  }
}
