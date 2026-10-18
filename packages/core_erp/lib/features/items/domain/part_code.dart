/// The code a part is known by on a drawing: `SADP48` is the forty-eighth
/// Dolly patti in Switch Action — one letter per word of the group, then the
/// set, then the part name, then the number.
///
/// **The backend is authoritative.** `backend/modules/items/part-identity.js`
/// holds the same rule, and it is the one that runs for every other way a part
/// can be created. This copy exists so a field can fill in as someone types,
/// and the two are kept honest by one shared fixture table, asserted in
/// `part_code_test.dart` here and in `item-part-identity.test.js` there.
library;

/// Long enough to read a part off a drawing, short enough to print beside a
/// barcode.
const int kMaxPartCodeLetters = 12;

/// One letter per word, taken only where the word *starts* with an ASCII
/// letter. "2mm Washer" is a washer, not an M-something, so the leading number
/// loses its word; "M8 Bolt" keeps both, because M8 is how that part is named.
///
/// The character is tested before it is upper-cased, deliberately: Node's
/// `toUpperCase` is locale-sensitive where Dart's is not, and the two sides
/// have to agree on what counts as a letter.
String partCodeInitials(String? value) {
  final words = (value ?? '').split(RegExp(r'[^A-Za-z0-9]+'));
  final buffer = StringBuffer();
  for (final word in words) {
    if (word.isEmpty) continue;
    final first = word[0];
    if (!RegExp(r'[A-Za-z]').hasMatch(first)) continue;
    buffer.write(first.toUpperCase());
  }
  return buffer.toString();
}

/// The code for a part, or `''` when there is nothing to build one from.
///
/// A missing segment is simply absent — null and `''` mean the same thing, and
/// neither leaves a gap. With no letters anywhere the answer is `''`, never the
/// bare number: a code that is only digits cannot be told from the part number
/// and tells a reader nothing.
String buildPartCode({
  String? groupName,
  String? setName,
  String? itemName,
  int? partNo,
}) {
  final letters =
      partCodeInitials(groupName) +
      partCodeInitials(setName) +
      partCodeInitials(itemName);
  final capped = letters.length <= kMaxPartCodeLetters
      ? letters
      : letters.substring(0, kMaxPartCodeLetters);
  if (capped.isEmpty) return '';
  return '$capped${partNo ?? ''}';
}

/// What the server says the next part in a scope should be called.
class PartIdentitySuggestion {
  const PartIdentitySuggestion({
    required this.partNo,
    required this.partCode,
    this.scope = '',
  });

  final int partNo;
  final String partCode;

  /// Which scope the number came from — 'set', 'group-unfiled' or
  /// 'pending-set'. Reported so a caller can say what the number counts.
  final String scope;

  factory PartIdentitySuggestion.fromJson(Map<String, dynamic> json) {
    return PartIdentitySuggestion(
      partNo: (json['partNo'] as num?)?.toInt() ?? 1,
      partCode: json['partCode'] as String? ?? '',
      scope: json['scope'] as String? ?? '',
    );
  }
}

/// One line of one set that holds this part.
///
/// A row per LINE rather than per set, because a set can hold the same item at
/// two variations and each is its own line with its own quantity.
class ItemSetMembership {
  const ItemSetMembership({
    required this.lineId,
    required this.setId,
    required this.setName,
    required this.quantity,
    required this.variationLeafNodeId,
    required this.variationPathLabel,
    required this.setLineCount,
    this.photoUrl = '',
    this.groupId,
    this.groupName,
  });

  final int lineId;
  final int setId;
  final String setName;
  final int quantity;
  final int variationLeafNodeId;
  final String variationPathLabel;

  /// The SET's line count — what says whether removing this line would empty
  /// the set, which the server refuses.
  final int setLineCount;

  /// Carried so a write back to this set keeps its picture: the server writes
  /// photo_url on every update, so a merge that omits it clears the photo.
  final String photoUrl;

  /// The group the set itself is filed under, which need not be the part's.
  final int? groupId;
  final String? groupName;

  bool get isOnlyLine => setLineCount <= 1;

  factory ItemSetMembership.fromJson(Map<String, dynamic> json) {
    return ItemSetMembership(
      lineId: (json['lineId'] as num?)?.toInt() ?? 0,
      setId: (json['setId'] as num?)?.toInt() ?? 0,
      setName: json['setName'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      variationLeafNodeId: (json['variationLeafNodeId'] as num?)?.toInt() ?? 0,
      variationPathLabel: json['variationPathLabel'] as String? ?? '',
      setLineCount: (json['setLineCount'] as num?)?.toInt() ?? 0,
      photoUrl: json['photoUrl'] as String? ?? '',
      groupId: (json['groupId'] as num?)?.toInt(),
      groupName: json['groupName'] as String?,
    );
  }
}
