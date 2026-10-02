import 'package:flutter/material.dart';

/// One record in the link graph, reduced to what a column shows: what it is,
/// which one it is, and the two lines of text that name it.
///
/// Deliberately not a typed Item / Die / Machine. A column holds whatever the
/// master it is listing holds, and the whole point of the graph is that a
/// column need not know which master that is.
@immutable
class LinkRef {
  const LinkRef({
    required this.type,
    required this.id,
    required this.label,
    this.subtitle = '',
    this.relation = 'linked',
  });

  /// A [LinkableType.type] key: 'item', 'die', 'machine', …
  final String type;
  final String id;
  final String label;
  final String subtitle;

  /// What the link to this record means. The type pair says it in every case
  /// so far, so this is usually the bare 'linked'.
  final String relation;

  static LinkRef? fromJson(Map<String, dynamic> json) {
    final type = (json['type'] as String?)?.trim();
    final id = json['id']?.toString().trim();
    if (type == null || type.isEmpty || id == null || id.isEmpty) return null;
    return LinkRef(
      type: type,
      id: id,
      label: (json['label'] as String?)?.trim() ?? '',
      subtitle: (json['subtitle'] as String?)?.trim() ?? '',
      relation: (json['relation'] as String?)?.trim().isNotEmpty == true
          ? (json['relation'] as String).trim()
          : 'linked',
    );
  }

  /// Identity in the graph: two refs to the same record are the same node, no
  /// matter which end of which link they arrived from.
  String get key => '$type:$id';

  @override
  bool operator ==(Object other) => other is LinkRef && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// A master that can be linked, as the server declares it.
///
/// The column headers and the "+ link" menu are built from this list rather
/// than from a hardcoded Item / Die / Machine, so a master added to the
/// server's catalog appears without an app release — and a master the user
/// cannot read never appears at all, because the server leaves it out.
@immutable
class LinkableType {
  const LinkableType({
    required this.type,
    required this.label,
    required this.plural,
    this.icon = '',
    this.canLink = false,
  });

  final String type;
  final String label;
  final String plural;
  final String icon;

  /// Whether this user may attach records of this master to something. False
  /// greys the master out of the + menu instead of letting a click 403.
  final bool canLink;

  static LinkableType? fromJson(Map<String, dynamic> json) {
    final type = (json['type'] as String?)?.trim();
    if (type == null || type.isEmpty) return null;
    final label = (json['label'] as String?)?.trim() ?? type;
    return LinkableType(
      type: type,
      label: label,
      plural: (json['plural'] as String?)?.trim().isNotEmpty == true
          ? (json['plural'] as String).trim()
          : '${label}s',
      icon: (json['icon'] as String?)?.trim() ?? '',
      canLink: json['canLink'] == true,
    );
  }
}

/// The links one record has to one master: the Dies heading in a column, and
/// the rows under it.
@immutable
class LinkGroup {
  const LinkGroup({
    required this.type,
    required this.label,
    required this.plural,
    required this.links,
  });

  final String type;
  final String label;
  final String plural;
  final List<LinkRef> links;

  static LinkGroup? fromJson(Map<String, dynamic> json) {
    final type = (json['type'] as String?)?.trim();
    if (type == null || type.isEmpty) return null;
    final label = (json['label'] as String?)?.trim() ?? type;
    return LinkGroup(
      type: type,
      label: label,
      plural: (json['plural'] as String?)?.trim().isNotEmpty == true
          ? (json['plural'] as String).trim()
          : '${label}s',
      links: [
        for (final raw in (json['links'] as List?) ?? const [])
          if (raw is Map<String, dynamic>) ?LinkRef.fromJson(raw),
      ],
    );
  }
}

/// One record and everything it is linked to, grouped by master.
@immutable
class EntityLinks {
  const EntityLinks({required this.entity, required this.groups});

  final LinkRef entity;
  final List<LinkGroup> groups;

  bool get isEmpty => groups.isEmpty;

  int get total => groups.fold(0, (sum, group) => sum + group.links.length);

  static EntityLinks? fromJson(Map<String, dynamic> json) {
    final raw = json['entity'];
    if (raw is! Map<String, dynamic>) return null;
    final entity = LinkRef.fromJson(raw);
    if (entity == null) return null;
    return EntityLinks(
      entity: entity,
      groups: [
        for (final group in (json['groups'] as List?) ?? const [])
          if (group is Map<String, dynamic>) ?LinkGroup.fromJson(group),
      ],
    );
  }
}
