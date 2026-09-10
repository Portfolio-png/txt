import 'package:core_erp/features/items/domain/item_expression.dart';
import 'package:flutter_test/flutter_test.dart';

const _bulbProperties = [
  ExpressionProperty(id: 11, name: 'Colour'),
  ExpressionProperty(id: 12, name: 'Wattage', inputType: 'Numeric'),
];

void main() {
  group('head', () {
    test('a bare name creates an item and nothing else', () {
      final plan = ItemExpression.parse('Cone');
      expect(plan.headText, 'Cone');
      expect(plan.createsItem, isTrue);
      expect(plan.valueSegments, isEmpty);
    });

    test('a matched head adds to that item instead of creating one', () {
      final plan = ItemExpression.parse(
        'Bulb + Red',
        itemId: 5,
        existingProperties: _bulbProperties,
      );
      expect(plan.createsItem, isFalse);
      expect(plan.itemId, 5);
    });

    test('a trailing + is pending, not an empty value', () {
      final plan = ItemExpression.parse('Cone + ');
      expect(plan.segments.last.kind, SegmentKind.pending);
      expect(plan.newPropertyCount, 0);
    });
  });

  group('values bind positionally to existing properties', () {
    test('first value lands on the first property', () {
      final plan = ItemExpression.parse(
        'Bulb + Red + 60',
        itemId: 5,
        existingProperties: _bulbProperties,
      );
      final values = plan.valueSegments.toList();

      expect(values[0].kind, SegmentKind.boundValue);
      expect(values[0].propertyName, 'Colour');
      expect(values[0].propertyId, 11);
      expect(values[0].value, 'Red');

      expect(values[1].propertyName, 'Wattage');
      expect(values[1].propertyId, 12);
      // The property's own type wins over anything inferred from the value.
      expect(values[1].inputType, 'Numeric');
      expect(plan.newPropertyCount, 0);
    });

    test('overflow past the last property invents one — the light-bulb case', () {
      final plan = ItemExpression.parse(
        'Bulb + Red + 60 + Brass',
        itemId: 5,
        existingProperties: _bulbProperties,
      );
      final values = plan.valueSegments.toList();

      expect(values[0].kind, SegmentKind.boundValue);
      expect(values[1].kind, SegmentKind.boundValue);
      expect(values[2].kind, SegmentKind.newProperty);
      expect(values[2].value, 'Brass');
      expect(values[2].propertyId, isNull);
      expect(plan.boundValueCount, 2);
      expect(plan.newPropertyCount, 1);
      expect(plan.warnings.single, contains('1 new property'));
    });

    test('a new item has no properties, so every value invents one', () {
      final plan = ItemExpression.parse('Ferrule + Brass + 12');
      expect(plan.createsItem, isTrue);
      expect(plan.boundValueCount, 0);
      expect(plan.newPropertyCount, 2);
    });
  });

  group('type words', () {
    test('each of the four resolves, by everyday name too', () {
      expect(ItemExpression.inputTypeFor('text'), 'Text');
      expect(ItemExpression.inputTypeFor('number'), 'Numeric');
      expect(ItemExpression.inputTypeFor('Numeric'), 'Numeric');
      expect(ItemExpression.inputTypeFor('GAUGE'), 'Gauge');
      expect(ItemExpression.inputTypeFor('material'), 'Material');
      expect(ItemExpression.inputTypeFor('Brass'), isNull);
    });

    test('a type word declares an empty property, carrying no value', () {
      final plan = ItemExpression.parse('Sheet + number + material');
      final values = plan.valueSegments.toList();

      expect(values[0].kind, SegmentKind.typeOnly);
      expect(values[0].inputType, 'Numeric');
      expect(values[0].value, isEmpty);
      expect(values[1].inputType, 'Material');
      expect(plan.newPropertyCount, 2);
    });

    test('the spec line parses end to end', () {
      final plan = ItemExpression.parse('a + b + c + d + number + material');
      expect(plan.headText, 'a');
      expect(plan.valueSegments.length, 5);
      // b, c, d are values; number and material declare typed properties.
      expect(plan.valueSegments.take(3).every((s) => s.value.isNotEmpty), isTrue);
      expect(plan.valueSegments.last.kind, SegmentKind.typeOnly);
      expect(plan.valueSegments.last.inputType, 'Material');
    });
  });

  _catalogTests();

  group('invented property names are recallable and never collide', () {
    test('named from the input type, not numbered', () {
      expect(ItemExpression.autoPropertyName('Material', {}), 'Material');
      expect(ItemExpression.autoPropertyName('Numeric', {}), 'Measurement');
      expect(ItemExpression.autoPropertyName('Gauge', {}), 'Gauge');
      expect(ItemExpression.autoPropertyName('Text', {}), 'Detail');
    });

    test('a taken name gets a suffix rather than merging into it', () {
      expect(
        ItemExpression.autoPropertyName('Material', {'Material'}),
        'Material 2',
      );
      expect(
        ItemExpression.autoPropertyName('Material', {'Material', 'Material 2'}),
        'Material 3',
      );
    });

    test('collides with neither the item nor an earlier segment', () {
      final plan = ItemExpression.parse(
        'Sheet + material + material',
        itemId: 9,
        existingProperties: const [ExpressionProperty(id: 1, name: 'Material')],
      );
      final names = plan.valueSegments.map((s) => s.propertyName).toList();
      expect(names, ['Material 2', 'Material 3']);
    });

    test('a bare number infers Measurement, text infers Detail', () {
      final plan = ItemExpression.parse('Ferrule + 12 + Brass');
      final values = plan.valueSegments.toList();
      expect(values[0].inputType, 'Numeric');
      expect(values[0].propertyName, 'Measurement');
      expect(values[1].inputType, 'Text');
      expect(values[1].propertyName, 'Detail');
    });
  });
}

// --- matching against a catalogue -------------------------------------------

const _catalog = [
  ExpressionItem(
    id: 5,
    name: 'Bulb',
    properties: [
      ExpressionProperty(
        id: 11,
        name: 'Colour',
        values: [
          ExpressionValue(id: 101, name: 'Red'),
          ExpressionValue(id: 102, name: 'Warm White'),
        ],
      ),
      ExpressionProperty(id: 12, name: 'Wattage', inputType: 'Numeric'),
    ],
  ),
  ExpressionItem(id: 7, name: 'Ferrule'),
];

void _catalogTests() {
  group('catalogue matching', () {
    test('a head that names an item resolves to it, case-insensitively', () {
      expect(ItemExpression.matchItem('bulb', _catalog)?.id, 5);
      expect(ItemExpression.matchItem('Nope', _catalog), isNull);
      expect(ItemExpression.parseWithCatalog('Bulb + Red', _catalog).itemId, 5);
      expect(ItemExpression.parseWithCatalog('Nope + Red', _catalog).itemId, isNull);
    });

    test('a value the property already holds is reused, not re-created', () {
      final plan = ItemExpression.parseWithCatalog('Bulb + Red', _catalog);
      final segment = plan.valueSegments.single;

      expect(segment.kind, SegmentKind.existingValue);
      expect(segment.valueId, 101);
      expect(plan.existingValueCount, 1);
      expect(plan.boundValueCount, 0);
      // The whole point: this line writes nothing at all.
      expect(plan.writeCount, 0);
    });

    test('an unfamiliar value on a known property is a new value', () {
      final plan = ItemExpression.parseWithCatalog('Bulb + Teal', _catalog);
      final segment = plan.valueSegments.single;

      expect(segment.kind, SegmentKind.boundValue);
      expect(segment.propertyId, 11);
      expect(segment.valueId, isNull);
      expect(plan.writeCount, 1);
    });
  });

  group('what to offer at the caret', () {
    test('before the first + it offers items, filtered as you type', () {
      final all = ItemExpression.suggest('', _catalog);
      expect(all.map((s) => s.label), ['Bulb', 'Ferrule']);
      expect(all.first.kind, SuggestionKind.item);

      final filtered = ItemExpression.suggest('fer', _catalog);
      expect(filtered.map((s) => s.label), ['Ferrule']);
    });

    test('after a + it offers that property\'s existing values', () {
      final suggestions = ItemExpression.suggest('Bulb + ', _catalog);
      expect(
        suggestions.map((s) => s.label),
        ['Red', 'Warm White'],
        reason: 'the first property is Colour',
      );
      expect(suggestions.every((s) => s.kind == SuggestionKind.existingValue), isTrue);
    });

    test('typing narrows, and offers to mint one only when nothing matches', () {
      final partial = ItemExpression.suggest('Bulb + R', _catalog);
      expect(partial.first.label, 'Red');
      // "R" is not a value yet, so minting is still on the table.
      expect(partial.last.kind, SuggestionKind.newValue);

      // An exact match means there is nothing to mint.
      final exact = ItemExpression.suggest('Bulb + Red', _catalog);
      expect(exact.map((s) => s.kind), everyElement(SuggestionKind.existingValue));
    });

    test('past the item\'s properties it offers the four types instead', () {
      final suggestions = ItemExpression.suggest('Bulb + Red + 9 + ', _catalog);
      expect(
        suggestions.map((s) => s.label),
        ['text', 'number', 'gauge', 'material'],
      );
    });

    test('tells you which property you are on, and how many there are', () {
      expect(ItemExpression.propertyProgress('Bulb + ', _catalog), (1, 2));
      expect(ItemExpression.propertyProgress('Bulb + Red + ', _catalog), (2, 2));
      expect(ItemExpression.propertyForNextSegment('Bulb + Red + ', _catalog)?.name, 'Wattage');
      // Run past them and there is no property to name.
      expect(ItemExpression.propertyProgress('Bulb + Red + 9 + ', _catalog), isNull);
    });

    test('matching a value ignores case, so "raw" finds "Red"-style values', () {
      final plan = ItemExpression.parseWithCatalog('bulb + RED', _catalog);
      final segment = plan.valueSegments.single;

      // Both the item and the value matched despite the casing.
      expect(plan.itemId, 5);
      expect(segment.kind, SegmentKind.existingValue);
      expect(segment.valueId, 101);
      // The stored spelling wins over what was typed.
      expect(segment.value, 'Red');
      expect(plan.writeCount, 0);
    });

    test('a completed segment advances to the next property', () {
      // The reported glitch: after "Bulb + Red +" the caret is on property 2,
      // not still on property 1.
      expect(ItemExpression.propertyProgress('Bulb + Red +', _catalog), (2, 2));
      expect(
        ItemExpression.propertyForNextSegment('Bulb + Red +', _catalog)?.name,
        'Wattage',
      );
      // Trailing whitespace must not change the reading either.
      expect(
        ItemExpression.propertyProgress('Bulb + Red +   ', _catalog),
        (2, 2),
      );
    });

    test('accepting a suggestion replaces only the segment being typed', () {
      expect(ItemExpression.applySuggestion('Bulb + R', 'Red'), 'Bulb + Red ');
      expect(ItemExpression.applySuggestion('Bu', 'Bulb'), 'Bulb ');
      expect(
        ItemExpression.applySuggestion('Bulb + Red + ', 'Warm White'),
        'Bulb + Red + Warm White ',
      );
    });
  });
}
