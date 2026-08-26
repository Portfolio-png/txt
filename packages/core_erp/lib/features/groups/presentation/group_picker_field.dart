import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/searchable_select.dart';
import '../domain/group_definition.dart';
import 'group_type_style.dart';
import 'providers/groups_provider.dart';

/// Which groups a picker is allowed to offer.
enum GroupPickerScope {
  /// Anywhere an item can live — hierarchical groups and combination groups
  /// alike. An item filed under a combination group shows up in its overview
  /// beside the members curated into it.
  filable,

  /// Containers only. Nesting inside a combination group is not a tree anyone
  /// reads, so parent pickers use this.
  hierarchical,

  /// Everything of the type, whatever its structure. For filters, where the
  /// question is "show me things in X" rather than "put this in X".
  all,
}

/// The one group picker.
///
/// There were seven, and no two agreed: three widget types, four sources, four
/// label formats. Two offered archived groups, one was filtered by whatever was
/// typed in the Groups screen's search box, and only one showed that groups
/// nest at all. Which groups you could choose — and what they were called —
/// depended on where you happened to be standing.
///
/// What this settles, in one place:
///
///   * **Archived groups never appear** — except the one already selected,
///     because hiding a record's current group would silently re-file it on the
///     next save.
///   * **The list is never search-filtered.** It reads the provider's full
///     list rather than `filteredGroupsByType`, whose query state belongs to
///     the Groups screen and has nothing to do with what a field may offer.
///   * **Hierarchy is visible.** Options come out in tree order, indented by
///     depth, and the search text carries the whole lineage — so typing a
///     parent's name finds its children.
///   * **A combination group says so**, in the same words everywhere.
class GroupPickerField extends StatelessWidget {
  const GroupPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.decoration,
    this.scope = GroupPickerScope.filable,
    this.groupType = 'item',
    this.dialogTitle = 'Group',
    this.searchHintText = 'Search group',
    this.nullOptionLabel,
    this.excludeGroupId,
    this.excludeDescendantsOfSelf = false,
    this.fieldEnabled = true,
    this.validator,
    this.tapTargetKey,
    this.onCreateOption,
    this.createOptionLabelBuilder,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final InputDecoration decoration;
  final GroupPickerScope scope;
  final String groupType;
  final String dialogTitle;
  final String searchHintText;

  /// When set, a "no group" choice is offered under this label — "Primary" for
  /// a parent field, "All groups" for a filter. Null means the field must hold
  /// a group.
  final String? nullOptionLabel;

  /// A group that cannot be chosen — itself, when picking its own parent.
  final int? excludeGroupId;

  /// Also hide everything beneath [excludeGroupId]. The server rejects a move
  /// under one's own descendant with a 409, so offering it is a dead end.
  final bool excludeDescendantsOfSelf;

  final bool fieldEnabled;
  final String? Function(int?)? validator;
  final Key? tapTargetKey;
  final Future<SearchableSelectOption<int?>?> Function(String query)?
  onCreateOption;
  final String Function(String query)? createOptionLabelBuilder;

  /// The groups this picker may offer, in tree order with the depth each sits
  /// at. A group whose parent is not in the list — archived, or out of scope —
  /// is treated as a root so it stays reachable rather than disappearing along
  /// with its parent.
  static List<(GroupDefinition, int)> optionsFor(
    GroupsProvider provider, {
    GroupPickerScope scope = GroupPickerScope.filable,
    String groupType = 'item',
    int? keepSelected,
    int? excludeGroupId,
    bool excludeDescendants = false,
  }) {
    bool inScope(GroupDefinition group) {
      if (group.groupType != groupType) return false;
      return switch (scope) {
        GroupPickerScope.filable => true,
        GroupPickerScope.hierarchical => !group.isCombination,
        GroupPickerScope.all => true,
      };
    }

    final blocked = <int>{};
    if (excludeGroupId != null) {
      blocked.add(excludeGroupId);
      if (excludeDescendants) {
        blocked.addAll(provider.descendantIdsOf(excludeGroupId));
      }
    }

    // Archived groups are out, with one exception: the group already selected.
    // Dropping that would leave the field looking empty and re-file the record
    // the next time it was saved.
    final candidates = provider.groups
        .where(inScope)
        .where((group) => !group.isArchived || group.id == keepSelected)
        .where((group) => !blocked.contains(group.id))
        .toList(growable: false);

    final present = <int>{for (final group in candidates) group.id};
    final childrenOf = <int?, List<GroupDefinition>>{};
    for (final group in candidates) {
      final parentId =
          group.parentGroupId != null &&
              group.parentGroupId != group.id &&
              present.contains(group.parentGroupId)
          ? group.parentGroupId
          : null;
      childrenOf.putIfAbsent(parentId, () => <GroupDefinition>[]).add(group);
    }
    for (final siblings in childrenOf.values) {
      siblings.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    final ordered = <(GroupDefinition, int)>[];
    // Stored parent links are cycle-checked server-side; a walk that trusts
    // that and is wrong would hang the field, so it is guarded here too.
    final visited = <int>{};
    void walk(int? parentId, int depth) {
      for (final group in childrenOf[parentId] ?? const <GroupDefinition>[]) {
        if (!visited.add(group.id)) continue;
        ordered.add((group, depth));
        walk(group.id, depth + 1);
      }
    }

    walk(null, 0);
    return ordered;
  }

  /// The name, indented by depth, with `· Set` on a combination group.
  static String labelFor(GroupDefinition group, int depth) {
    final indent = depth == 0 ? '' : '${'    ' * (depth - 1)}└ ';
    final kind = group.isCombination ? '  · Set' : '';
    return '$indent${group.name}$kind';
  }

  /// The whole lineage, so typing a parent's name finds its children. Without
  /// this the indentation shows the tree but the search cannot use it.
  static String searchTextFor(GroupsProvider provider, GroupDefinition group) {
    final crumbs = <String>[];
    final seen = <int>{};
    int? current = group.id;
    while (current != null && seen.add(current)) {
      final row = provider.findById(current);
      if (row == null) break;
      crumbs.insert(0, row.name);
      current = row.parentGroupId;
    }
    if (group.isCombination) crumbs.add('set combination');
    return crumbs.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupsProvider>();
    final entries = optionsFor(
      provider,
      scope: scope,
      groupType: groupType,
      keepSelected: value,
      excludeGroupId: excludeGroupId,
      excludeDescendants: excludeDescendantsOfSelf,
    );

    final options = <SearchableSelectOption<int?>>[
      if (nullOptionLabel != null)
        SearchableSelectOption<int?>(value: null, label: nullOptionLabel!),
      for (final (group, depth) in entries)
        SearchableSelectOption<int?>(
          value: group.id,
          label: labelFor(group, depth),
          searchText: searchTextFor(provider, group),
          highlightColor: GroupTypeStyle.of(group).folder,
        ),
    ];

    return SearchableSelectField<int?>(
      tapTargetKey: tapTargetKey,
      // A value with no matching option would render blank. Falling back to
      // null is at least honest about that, rather than showing a stale name.
      value: options.any((option) => option.value == value) ? value : null,
      decoration: decoration,
      dialogTitle: dialogTitle,
      searchHintText: searchHintText,
      fieldEnabled: fieldEnabled,
      options: options,
      onChanged: onChanged,
      validator: validator,
      onCreateOption: onCreateOption,
      createOptionLabelBuilder: createOptionLabelBuilder,
    );
  }
}
