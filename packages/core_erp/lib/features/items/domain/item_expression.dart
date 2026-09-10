/// The `+` expression language for on-the-fly item entry.
///
/// Someone typing a factory's books into the app spends most of their time
/// walking lists — item, then property, then value, then back. The expression
/// collapses that into one line:
///
///     Cone + Red + 90 + Brass
///
/// The first segment names the item; each segment after it is a value. Values
/// bind **positionally** to the item's existing top-level properties, so the
/// first value lands on the first property, the second on the second, and so
/// on. When the values outrun the properties, the overflow creates new ones —
/// that is the case that used to mean leaving the screen.
///
/// A segment that is only a type word (`text`, `number`, `gauge`, `material`)
/// does not carry a value. It declares a property of that type and leaves it
/// empty, which is how a new item gets its shape before anyone knows the
/// values.
///
/// Nothing here writes. Parsing is separated from execution so the reading can
/// be shown back to the user — a grammar you cannot see is a grammar you
/// cannot trust.
library;

/// A value that already exists under a property. Typing one reuses it rather
/// than adding a second value that means the same thing.
class ExpressionValue {
  const ExpressionValue({required this.id, required this.name});

  final int id;
  final String name;
}

/// A top-level property as the parser needs to see it.
class ExpressionProperty {
  const ExpressionProperty({
    required this.id,
    required this.name,
    this.inputType = 'Text',
    this.values = const <ExpressionValue>[],
  });

  final int id;
  final String name;
  final String inputType;
  final List<ExpressionValue> values;

  ExpressionValue? matchValue(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final value in values) {
      if (value.name.trim().toLowerCase() == needle) return value;
    }
    return null;
  }
}

/// An item the head can resolve to.
class ExpressionItem {
  const ExpressionItem({
    required this.id,
    required this.name,
    this.properties = const <ExpressionProperty>[],
  });

  final int id;
  final String name;
  final List<ExpressionProperty> properties;
}

enum SegmentKind {
  /// The head segment: the item itself.
  item,

  /// A value the property already holds. Selecting it writes nothing at all,
  /// which is the difference worth showing.
  existingValue,

  /// A new value landing on a property the item already has.
  boundValue,

  /// A value whose property does not exist yet, so one is named for it.
  newProperty,

  /// A type word with no value — declares an empty property of that type.
  typeOnly,

  /// Someone is mid-keystroke: `Cone + `.
  pending,
}

class ItemExpressionSegment {
  const ItemExpressionSegment({
    required this.raw,
    required this.kind,
    this.value = '',
    this.propertyName = '',
    this.inputType = 'Text',
    this.propertyId,
    this.valueId,
  });

  final String raw;
  final SegmentKind kind;

  /// What the user typed as the value, empty for [SegmentKind.typeOnly].
  final String value;

  /// The property this segment lands on — resolved for [SegmentKind.boundValue]
  /// and invented for the other two.
  final String propertyName;
  final String inputType;

  /// Set only when the property already exists on the item.
  final int? propertyId;

  /// Set only when the typed value matched one the property already holds.
  final int? valueId;

  bool get createsProperty =>
      kind == SegmentKind.newProperty || kind == SegmentKind.typeOnly;
}

class ItemExpressionPlan {
  const ItemExpressionPlan({
    required this.segments,
    required this.headText,
    required this.itemId,
    required this.warnings,
  });

  final List<ItemExpressionSegment> segments;

  /// The item name as typed.
  final String headText;

  /// Set when the head matched an item that already exists.
  final int? itemId;

  final List<String> warnings;

  bool get isEmpty => headText.isEmpty && segments.length <= 1;
  bool get createsItem => headText.isNotEmpty && itemId == null;

  Iterable<ItemExpressionSegment> get valueSegments =>
      segments.where((segment) => segment.kind != SegmentKind.item);

  int get newPropertyCount =>
      valueSegments.where((segment) => segment.createsProperty).length;

  /// New values landing on properties that already exist.
  int get boundValueCount => valueSegments
      .where((segment) => segment.kind == SegmentKind.boundValue)
      .length;

  /// Values reused as-is. These write nothing.
  int get existingValueCount => valueSegments
      .where((segment) => segment.kind == SegmentKind.existingValue)
      .length;

  /// Everything this line would actually create.
  int get writeCount => boundValueCount + newPropertyCount;
}

enum SuggestionKind { item, existingValue, newValue, inputType }

class ExpressionSuggestion {
  const ExpressionSuggestion({
    required this.kind,
    required this.label,
    required this.detail,
    required this.insertText,
  });

  final SuggestionKind kind;
  final String label;
  final String detail;

  /// Replaces the segment being typed, leaving the rest of the line alone.
  final String insertText;
}

class ItemExpression {
  const ItemExpression._();

  /// Swaps the trailing segment for [insertText], keeping the separator
  /// spacing the rest of the line uses.
  static String applySuggestion(String text, String insertText) {
    final parts = text.split(separator);
    parts[parts.length - 1] = ' ${insertText.trim()} ';
    return parts.join(separator).trimLeft();
  }

  static const String separator = '+';

  /// The four input types, in the order the A / 1 / G / M pills cycle.
  static const List<String> inputTypes = [
    'Text',
    'Numeric',
    'Gauge',
    'Material',
  ];

  /// What someone would actually type. `number` is the everyday word for the
  /// type the app calls Numeric, so both resolve.
  static String? inputTypeFor(String word) {
    switch (word.trim().toLowerCase()) {
      case 'text':
        return 'Text';
      case 'number':
      case 'numeric':
        return 'Numeric';
      case 'gauge':
      case 'swg':
        return 'Gauge';
      case 'material':
        return 'Material';
      default:
        return null;
    }
  }

  /// A property invented for an overflow value.
  ///
  /// Named from its input type rather than numbered, because "Material" is
  /// something the person who typed `+ Brass` will recognise a week later and
  /// `Property 4` is not. Collisions get a suffix rather than silently merging
  /// into an existing property.
  static String autoPropertyName(String inputType, Set<String> taken) {
    final base = switch (inputType) {
      'Numeric' => 'Measurement',
      'Gauge' => 'Gauge',
      'Material' => 'Material',
      _ => 'Detail',
    };
    final lowerTaken = taken.map((name) => name.toLowerCase()).toSet();
    if (!lowerTaken.contains(base.toLowerCase())) return base;
    for (var suffix = 2; suffix < 100; suffix++) {
      final candidate = '$base $suffix';
      if (!lowerTaken.contains(candidate.toLowerCase())) return candidate;
    }
    return base;
  }

  /// Parses [text] against the item the head resolved to.
  ///
  /// [existingProperties] are that item's top-level properties in their own
  /// order; pass an empty list for an item that does not exist yet.
  static ItemExpressionPlan parse(
    String text, {
    int? itemId,
    List<ExpressionProperty> existingProperties =
        const <ExpressionProperty>[],
  }) {
    final rawParts = text.split(separator);
    final headText = rawParts.isEmpty ? '' : rawParts.first.trim();
    final segments = <ItemExpressionSegment>[
      ItemExpressionSegment(
        raw: headText,
        kind: SegmentKind.item,
        value: headText,
      ),
    ];
    final warnings = <String>[];

    // Names already spoken for, so an invented property cannot collide with a
    // real one or with an earlier invention in the same line.
    final taken = <String>{
      for (final property in existingProperties) property.name,
    };

    var propertyCursor = 0;
    for (var i = 1; i < rawParts.length; i++) {
      final raw = rawParts[i];
      final trimmed = raw.trim();

      if (trimmed.isEmpty) {
        // `Cone + ` — the user is between segments, not making an empty value.
        segments.add(
          const ItemExpressionSegment(raw: '', kind: SegmentKind.pending),
        );
        continue;
      }

      final declaredType = inputTypeFor(trimmed);
      if (declaredType != null) {
        final name = autoPropertyName(declaredType, taken);
        taken.add(name);
        segments.add(
          ItemExpressionSegment(
            raw: trimmed,
            kind: SegmentKind.typeOnly,
            propertyName: name,
            inputType: declaredType,
          ),
        );
        continue;
      }

      if (propertyCursor < existingProperties.length) {
        final property = existingProperties[propertyCursor];
        propertyCursor++;
        final existing = property.matchValue(trimmed);
        segments.add(
          ItemExpressionSegment(
            raw: trimmed,
            // Matching a value the property already holds is a selection, not
            // an addition — nothing is written for it.
            kind: existing == null
                ? SegmentKind.boundValue
                : SegmentKind.existingValue,
            value: existing?.name ?? trimmed,
            propertyName: property.name,
            inputType: property.inputType,
            propertyId: property.id,
            valueId: existing?.id,
          ),
        );
        continue;
      }

      // Past the item's properties: the value has nowhere to land, so it gets
      // a property of its own. Typed from the value's shape, since that is the
      // only signal available.
      final inferred = _inferInputType(trimmed);
      final name = autoPropertyName(inferred, taken);
      taken.add(name);
      segments.add(
        ItemExpressionSegment(
          raw: trimmed,
          kind: SegmentKind.newProperty,
          value: trimmed,
          propertyName: name,
          inputType: inferred,
        ),
      );
    }

    if (headText.isEmpty && segments.length > 1) {
      warnings.add('Start with the item name, then add values with +.');
    }
    final invented = segments.where((s) => s.createsProperty).length;
    if (invented > 0 && itemId != null) {
      warnings.add(
        invented == 1
            ? '1 new property will be added to this item.'
            : '$invented new properties will be added to this item.',
      );
    }

    return ItemExpressionPlan(
      segments: segments,
      headText: headText,
      itemId: itemId,
      warnings: warnings,
    );
  }

  /// The item a head names, matched on the whole name, case-insensitively.
  static ExpressionItem? matchItem(
    String headText,
    List<ExpressionItem> catalog,
  ) {
    final needle = headText.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final item in catalog) {
      if (item.name.trim().toLowerCase() == needle) return item;
    }
    return null;
  }

  /// Parses against a catalogue, resolving the head itself.
  static ItemExpressionPlan parseWithCatalog(
    String text,
    List<ExpressionItem> catalog,
  ) {
    final headText = text.split(separator).first.trim();
    final matched = matchItem(headText, catalog);
    return parse(
      text,
      itemId: matched?.id,
      existingProperties: matched?.properties ?? const <ExpressionProperty>[],
    );
  }

  /// The property the segment now being typed will land on, or null when the
  /// line has run past the item's properties (or there is no item yet).
  static ExpressionProperty? propertyForNextSegment(
    String text,
    List<ExpressionItem> catalog,
  ) {
    final parts = text.split(separator);
    if (parts.length < 2) return null;
    final matched = matchItem(parts.first.trim(), catalog);
    if (matched == null) return null;
    // Segments already committed before the one being typed.
    var cursor = 0;
    for (var i = 1; i < parts.length - 1; i++) {
      final trimmed = parts[i].trim();
      if (trimmed.isEmpty) continue;
      if (inputTypeFor(trimmed) != null) continue;
      cursor++;
    }
    if (cursor >= matched.properties.length) return null;
    return matched.properties[cursor];
  }

  /// One-based position of the property being typed into, for "3rd of 4".
  static (int position, int total)? propertyProgress(
    String text,
    List<ExpressionItem> catalog,
  ) {
    final parts = text.split(separator);
    if (parts.length < 2) return null;
    final matched = matchItem(parts.first.trim(), catalog);
    if (matched == null || matched.properties.isEmpty) return null;
    var cursor = 0;
    for (var i = 1; i < parts.length - 1; i++) {
      final trimmed = parts[i].trim();
      if (trimmed.isEmpty) continue;
      if (inputTypeFor(trimmed) != null) continue;
      cursor++;
    }
    if (cursor >= matched.properties.length) return null;
    return (cursor + 1, matched.properties.length);
  }

  /// What to offer for the segment currently being typed.
  ///
  /// Before the first `+` it offers items. After one, it offers the values the
  /// property at that position already holds — so the common case is picking
  /// something that exists rather than quietly minting a near-duplicate. Past
  /// the item's properties there is nothing to reuse, so it offers the four
  /// input types instead.
  static List<ExpressionSuggestion> suggest(
    String text,
    List<ExpressionItem> catalog,
  ) {
    final parts = text.split(separator);
    final query = parts.last.trim().toLowerCase();

    if (parts.length == 1) {
      return [
        for (final item in catalog)
          if (query.isEmpty || item.name.toLowerCase().contains(query))
            ExpressionSuggestion(
              kind: SuggestionKind.item,
              label: item.name,
              detail: item.properties.isEmpty
                  ? 'no properties yet'
                  : item.properties.map((p) => p.name).join(' · '),
              insertText: item.name,
            ),
      ];
    }

    final property = propertyForNextSegment(text, catalog);
    if (property == null) {
      return [
        for (final word in const ['text', 'number', 'gauge', 'material'])
          if (query.isEmpty || word.startsWith(query))
            ExpressionSuggestion(
              kind: SuggestionKind.inputType,
              label: word,
              detail: 'declare a new ${inputTypeFor(word)} property',
              insertText: word,
            ),
      ];
    }

    final matches = [
      for (final value in property.values)
        if (query.isEmpty || value.name.toLowerCase().contains(query))
          ExpressionSuggestion(
            kind: SuggestionKind.existingValue,
            label: value.name,
            detail: 'already on ${property.name}',
            insertText: value.name,
          ),
    ];

    // Only offer to mint a value once it is clear none of the existing ones
    // are what was meant.
    final exact = property.matchValue(query);
    if (query.isNotEmpty && exact == null) {
      matches.add(
        ExpressionSuggestion(
          kind: SuggestionKind.newValue,
          label: parts.last.trim(),
          detail: 'new value on ${property.name}',
          insertText: parts.last.trim(),
        ),
      );
    }
    return matches;
  }

  /// Standard Wire Gauge, the range the gauge table covers.
  static List<String> get swgValues =>
      List<String>.generate(40, (index) => '${index + 1}');

  /// Folds the values collected after the item was confirmed back into the
  /// plan, turning each declared-but-empty property into one that carries a
  /// value. Keyed by the segment's index in [ItemExpressionPlan.segments].
  ///
  /// Execution consumes the result, so the collection step is inspectable
  /// rather than hidden inside a dialog's state.
  static ItemExpressionPlan applyCollectedValues(
    ItemExpressionPlan plan,
    Map<int, String> values,
  ) {
    final segments = <ItemExpressionSegment>[];
    for (var i = 0; i < plan.segments.length; i++) {
      final segment = plan.segments[i];
      final collected = values[i]?.trim() ?? '';
      if (segment.kind != SegmentKind.typeOnly || collected.isEmpty) {
        segments.add(segment);
        continue;
      }
      segments.add(
        ItemExpressionSegment(
          raw: segment.raw,
          kind: SegmentKind.newProperty,
          value: collected,
          propertyName: segment.propertyName,
          inputType: segment.inputType,
        ),
      );
    }
    return ItemExpressionPlan(
      segments: segments,
      headText: plan.headText,
      itemId: plan.itemId,
      warnings: plan.warnings,
    );
  }

  /// The segments still owing a value, with their index in the plan.
  static List<MapEntry<int, ItemExpressionSegment>> pendingValues(
    ItemExpressionPlan plan,
  ) {
    final pending = <MapEntry<int, ItemExpressionSegment>>[];
    for (var i = 0; i < plan.segments.length; i++) {
      if (plan.segments[i].kind == SegmentKind.typeOnly) {
        pending.add(MapEntry(i, plan.segments[i]));
      }
    }
    return pending;
  }

  /// A bare number is a measurement; everything else is text until someone
  /// says otherwise.
  static String _inferInputType(String value) {
    return double.tryParse(value) != null ? 'Numeric' : 'Text';
  }
}
