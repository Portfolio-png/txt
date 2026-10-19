import 'item_definition.dart';

/// How a variation value turns into a short code.
///
/// These three were top-level functions inside `item_detail_panel.dart`, a
/// presentation file, with byte-identical PRIVATE copies in `inventory_screen
/// .dart` and `orders_screen.dart`. Three copies of one rule had not drifted
/// yet, which is the only reason this move is mechanical rather than a
/// reconciliation — and the reason to make it before a fourth caller arrives.
///
/// The value a user typed into the editor's `Code` field always wins. The
/// derivation is a fallback for values nobody has coded, which is why
/// "Brass" reads BRAS here and B on a part that was given one: B is a
/// decision, BRAS is a guess.

String itemTitle(ItemDefinition item) {
  return item.displayName.trim().isEmpty ? item.name : item.displayName;
}

/// A node's own code, or one derived from its name.
String nodeCodeOrGenerated(ItemVariationNodeDefinition node) {
  final code = node.code.trim();
  if (code.isNotEmpty) {
    return code;
  }
  final source = node.name.trim().isEmpty ? node.displayName : node.name;
  return generatedCodeForText(source);
}

/// One word becomes its first four letters; several become their initials,
/// except all-digit words, which are kept whole — "22" has to stay 22, a
/// gauge is not the letter 2.
String generatedCodeForText(String value) {
  final words = RegExp(
    r'[A-Za-z0-9]+',
  ).allMatches(value).map((match) => match.group(0)!).toList();
  if (words.isEmpty) {
    return value.trim();
  }
  if (words.length == 1) {
    final word = words.single.toUpperCase();
    return word.length <= 4 ? word : word.substring(0, 4);
  }
  return words
      .map((word) => RegExp(r'^\d+$').hasMatch(word) ? word : word[0])
      .join()
      .toUpperCase();
}
