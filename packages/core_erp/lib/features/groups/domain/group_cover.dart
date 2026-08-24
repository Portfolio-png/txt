import 'package:flutter/foundation.dart';

/// One tile on a group's card: an item from inside the group.
///
/// A group has no photograph of its own — "Finished Goods" never will. What it
/// has is the things inside it, so the card is made of them, and recognising a
/// group becomes recognising what comes out of it.
@immutable
class GroupCoverItem {
  const GroupCoverItem({
    required this.itemId,
    required this.name,
    this.photoUrl = '',
    this.orderCount = 0,
    this.orderQuantity = 0,
  });

  factory GroupCoverItem.fromJson(Map<String, dynamic> json) {
    return GroupCoverItem(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString() ?? '',
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
      orderQuantity: (json['orderQuantity'] as num?)?.toInt() ?? 0,
    );
  }

  final int itemId;
  final String name;
  final String photoUrl;

  /// How many order lines this item appears on — the "most used" ranking.
  final int orderCount;
  final int orderQuantity;

  bool get hasPhoto => photoUrl.trim().isNotEmpty;

  /// Whether this item earned its place or is only here because it is recent.
  bool get isOrdered => orderCount > 0;

  /// Up to two initials, for the tile an item without a photo gets.
  String get initials {
    final parts = name
        .split(RegExp(r'[\s\-/]+'))
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1).toUpperCase())
        .toList();
    return parts.isEmpty ? '?' : parts.join();
  }
}

/// Why a card is showing the items it is showing.
///
/// Named rather than inferred from zeroes: a card showing recent items while
/// implying they are the most used would be lying quietly, which is worse than
/// showing nothing.
enum GroupCoverBasis {
  /// Ranked by how often the items are ordered.
  ordered,

  /// Nothing here has been ordered yet, so these are simply the newest.
  recent,

  /// The group holds no items at all.
  empty;

  static GroupCoverBasis parse(String? raw) {
    return switch (raw) {
      'ordered' => GroupCoverBasis.ordered,
      'recent' => GroupCoverBasis.recent,
      _ => GroupCoverBasis.empty,
    };
  }

  String get label => switch (this) {
    GroupCoverBasis.ordered => 'Most ordered',
    GroupCoverBasis.recent => 'Recently added',
    GroupCoverBasis.empty => 'No items yet',
  };
}
