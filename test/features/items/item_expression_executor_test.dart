import 'package:core_erp/features/items/domain/item_expression.dart';
import 'package:core_erp/features/items/domain/item_expression_executor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what was asked of it, so ordering can be asserted rather than
/// inferred.
class _RecordingSink implements ItemExpressionSink {
  _RecordingSink({
    this.failProperty = false,
    this.failValue = false,
    Map<String, int>? existingProperties,
  }) : existing = {...?existingProperties};

  final bool failProperty;
  final bool failValue;

  /// Properties the item already has at write time, by lowercased name.
  final Map<String, int> existing;
  final List<String> calls = [];
  int _nextPropertyId = 900;

  @override
  String? get lastError => failProperty || failValue ? 'the sink said no' : null;

  @override
  Future<int?> findProperty({
    required int itemId,
    required String name,
  }) async {
    calls.add('find:$name');
    return existing[name.trim().toLowerCase()];
  }

  @override
  bool isDataEntry(String inputType) =>
      inputType == 'Numeric' || inputType == 'Gauge';

  @override
  Future<int?> appendPropertyWithValue({
    required int itemId,
    required String name,
    required String inputType,
    required String value,
  }) async {
    calls.add('property:$name:$inputType:$value');
    if (failProperty) return null;
    return _nextPropertyId++;
  }

  @override
  Future<bool> appendValue({
    required int itemId,
    required int propertyNodeId,
    required String value,
  }) async {
    calls.add('value:$value@$propertyNodeId');
    return !failValue;
  }
}

const _catalog = [
  ExpressionItem(
    id: 5,
    name: 'Bulb',
    properties: [
      ExpressionProperty(
        id: 11,
        name: 'Colour',
        values: [ExpressionValue(id: 101, name: 'Red')],
      ),
    ],
  ),
];

void main() {
  test('a value the item already holds writes nothing at all', () async {
    final sink = _RecordingSink();
    final outcome = await ItemExpressionExecutor.apply(
      ItemExpression.parseWithCatalog('Bulb + Red', _catalog),
      sink,
    );

    expect(sink.calls, isEmpty);
    expect(outcome.reused, 1);
    expect(outcome.wroteNothing, isTrue);
    expect(outcome.summary, '1 already on the item.');
  });

  test('a new value on an existing property is one write', () async {
    final sink = _RecordingSink();
    final outcome = await ItemExpressionExecutor.apply(
      ItemExpression.parseWithCatalog('Bulb + Teal', _catalog),
      sink,
    );

    // Resolved live first, then written to whatever the item actually has.
    expect(sink.calls, ['find:Colour', 'value:Teal@11']);
    expect(outcome.valuesAdded, 1);
    expect(outcome.propertiesAdded, 0);
    expect(outcome.isClean, isTrue);
  });

  test('an invented property is created before its value is hung on it', () async {
    final sink = _RecordingSink();
    final outcome = await ItemExpressionExecutor.apply(
      ItemExpression.parseWithCatalog('Bulb + Red + Brass', _catalog),
      sink,
    );

    // Order is the point: the property has to exist first.
    // One write, not two: the property and its value go in together.
    expect(sink.calls, ['find:Detail', 'property:Detail:Text:Brass']);
    expect(outcome.reused, 1);
    expect(outcome.propertiesAdded, 1);
    expect(outcome.valuesAdded, 1);
    expect(outcome.summary, 'Added 1 property and 1 value.');
  });

  test('a declared type reaches the property that gets created', () async {
    final sink = _RecordingSink();
    final plan = ItemExpression.applyCollectedValues(
      ItemExpression.parseWithCatalog('Bulb + Red + material', _catalog),
      {2: 'Brass'},
    );
    await ItemExpressionExecutor.apply(plan, sink);

    expect(sink.calls, contains('property:Material:Material:Brass'));
  });

  test('a declared property with no value is refused, not written empty', () async {
    final sink = _RecordingSink();
    final outcome = await ItemExpressionExecutor.apply(
      ItemExpression.parseWithCatalog('Bulb + Red + material', _catalog),
      sink,
    );

    expect(sink.calls, isEmpty);
    expect(outcome.failures.single, contains('no value yet'));
  });

  test('one failure does not sink the rest of the line', () async {
    final sink = _RecordingSink(failValue: true);
    final outcome = await ItemExpressionExecutor.apply(
      ItemExpression.parseWithCatalog('Bulb + Teal + Brass', _catalog),
      sink,
    );

    // Teal could not be written, but Brass's property still went in.
    expect(outcome.propertiesAdded, 1);
    expect(outcome.failures, hasLength(1));
    expect(outcome.isClean, isFalse);
  });

  test('a Numeric property is created without a value node', () async {
    // Numeric and Gauge are answered per use, so hanging a stored value under
    // one is meaningless — and used to fail with "Created variation value was
    // not found after saving".
    final sink = _RecordingSink();
    final plan = ItemExpression.applyCollectedValues(
      ItemExpression.parseWithCatalog('Bulb + Red + number', _catalog),
      {2: '60'},
    );
    final outcome = await ItemExpressionExecutor.apply(plan, sink);

    expect(sink.calls, ['find:Measurement', 'property:Measurement:Numeric:60']);
    expect(outcome.propertiesAdded, 1);
    expect(outcome.valuesAdded, 0, reason: 'nothing is stored for Numeric');
    expect(outcome.isClean, isTrue);
  });

  test('re-running a data-entry property adds nothing and does not fail', () async {
    final sink = _RecordingSink(existingProperties: {'measurement': 77});
    final plan = ItemExpression.applyCollectedValues(
      ItemExpression.parseWithCatalog('Bulb + Red + number', _catalog),
      {2: '60'},
    );
    final outcome = await ItemExpressionExecutor.apply(plan, sink);

    expect(sink.calls, ['find:Measurement']);
    expect(outcome.wroteNothing, isTrue);
    expect(outcome.isClean, isTrue);
  });

  test('a property the item already has is used, not created again', () async {
    // The exact failure from the field: the first click made "Detail", the
    // result was not visible, and clicking again hit the duplicate guard.
    final sink = _RecordingSink(existingProperties: {'detail': 55});
    final outcome = await ItemExpressionExecutor.apply(
      ItemExpression.parseWithCatalog('Bulb + Red + Brass', _catalog),
      sink,
    );

    expect(sink.calls, ['find:Detail', 'value:Brass@55']);
    expect(outcome.propertiesAdded, 0, reason: 'it was already there');
    expect(outcome.valuesAdded, 1);
    expect(outcome.isClean, isTrue);
  });

  test('a value goes to the property as it is now, not as the plan saw it', () async {
    // Node ids are reassigned when a used item's tree is rewritten, so the id
    // captured when the line was typed can point at nothing.
    final sink = _RecordingSink(existingProperties: {'colour': 4242});
    final outcome = await ItemExpressionExecutor.apply(
      ItemExpression.parseWithCatalog('Bulb + Teal', _catalog),
      sink,
    );

    expect(sink.calls, ['find:Colour', 'value:Teal@4242']);
    expect(outcome.valuesAdded, 1);
    expect(outcome.isClean, isTrue);
  });

  test('a refusal carries the reason, not just a failure', () async {
    final sink = _RecordingSink(failValue: true);
    final outcome = await ItemExpressionExecutor.apply(
      ItemExpression.parseWithCatalog('Bulb + Teal', _catalog),
      sink,
    );

    expect(outcome.failures.single, contains('the sink said no'));
  });

  test('an item that does not exist yet is the editor\'s job, not this', () async {
    final sink = _RecordingSink();
    final outcome = await ItemExpressionExecutor.apply(
      ItemExpression.parseWithCatalog('Ferrule + Brass', _catalog),
      sink,
    );

    expect(sink.calls, isEmpty);
    expect(outcome.failures.single, contains('does not exist yet'));
  });
}
