import 'package:flutter/material.dart';

/// The icon for a linkable master, by its type key.
///
/// Public and shared because more than one surface draws a `LinkRef` now: the
/// Miller columns inside the creation window, and the ecosystem ribbon on a
/// record's own panel. It was private to the columns, which is why the ribbon
/// would otherwise have started a second, drifting copy.
///
/// The keys are the links catalogue's (`backend/modules/links/catalog.js`), and
/// an unknown one falls back to a plain link rather than throwing — a master
/// added on the server should appear with a generic icon, not crash the strip
/// that lists it.
IconData linkTypeIcon(String type) => switch (type) {
  'item' => Icons.inventory_2_outlined,
  'die' => Icons.build_circle_outlined,
  'machine' => Icons.precision_manufacturing_outlined,
  'group' => Icons.account_tree_outlined,
  'pipeline' => Icons.timeline_outlined,
  'material' => Icons.layers_outlined,
  'unit' => Icons.straighten_outlined,
  'client' => Icons.groups_outlined,
  'vendor' => Icons.storefront_outlined,
  'employee' => Icons.badge_outlined,
  'department' => Icons.apartment_outlined,
  'set' => Icons.category_outlined,
  _ => Icons.link_outlined,
};
