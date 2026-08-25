import 'package:flutter/material.dart';

import '../domain/group_definition.dart';

/// The colour a kind of group is drawn in, and the words for it.
///
/// One palette, used at every point a group is shown — the master list, the
/// group tree, the type picker in the editor. That is the whole point: choosing
/// "Component" in the picker and seeing a blue folder there is what teaches the
/// blue folders in the list, so the two must never drift apart.
///
/// Muted rather than saturated, in the manner of a desktop file manager: these
/// sit next to each other in a long list, and three bright colours would fight.
@immutable
class GroupTypeStyle {
  const GroupTypeStyle._({
    required this.folder,
    required this.background,
    required this.border,
    required this.label,
    required this.description,
    required this.icon,
    required this.openIcon,
  });

  /// The folder glyph's colour — the part the eye actually sorts on.
  final Color folder;

  /// A tint of [folder] for chips and selected rows.
  final Color background;
  final Color border;

  final String label;
  final String description;
  final IconData icon;
  final IconData openIcon;

  /// An item group: nestable, holds items, the ordinary case. Sand, because it
  /// is the one you see most and the one that should read as "plain folder".
  static const GroupTypeStyle hierarchical = GroupTypeStyle._(
    folder: Color(0xFFC98A1E),
    background: Color(0xFFFDF4E3),
    border: Color(0xFFF0DCB4),
    label: 'Item Group',
    description: 'Holds items and nests under another group.',
    icon: Icons.folder_rounded,
    openIcon: Icons.folder_open_rounded,
  );

  /// A component group: the same tree, different intent. Blue.
  static const GroupTypeStyle component = GroupTypeStyle._(
    folder: Color(0xFF3F7CB8),
    background: Color(0xFFEAF3FB),
    border: Color(0xFFC3DCF0),
    label: 'Component',
    description: 'Parts that go into something else.',
    icon: Icons.folder_copy_rounded,
    openIcon: Icons.folder_open_rounded,
  );

  /// A combination group: a curated set rather than a container. Rose, and a
  /// different glyph, because it is the one that behaves unlike the others.
  static const GroupTypeStyle combination = GroupTypeStyle._(
    folder: Color(0xFFC0567F),
    background: Color(0xFFFCEEF3),
    border: Color(0xFFF2CBDA),
    label: 'Combination Group',
    description: 'A variant set, gathered by hand across groups.',
    icon: Icons.folder_special_rounded,
    openIcon: Icons.folder_special_rounded,
  );

  /// The style for a stored `group_structure` string. Anything unrecognised is
  /// an item group, which is what the column defaults to.
  static GroupTypeStyle forStructure(String? structure) {
    return switch (structure) {
      'combination' => combination,
      'component' => component,
      _ => hierarchical,
    };
  }

  static GroupTypeStyle of(GroupDefinition group) =>
      forStructure(group.groupStructure);

  /// The glyph to draw, open or closed. A combination group has no open form —
  /// it is a set, not something you go inside.
  IconData iconFor({bool expanded = false}) => expanded ? openIcon : icon;
}
