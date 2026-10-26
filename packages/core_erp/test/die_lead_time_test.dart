import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:flutter_test/flutter_test.dart';

// The two instants on a die are not interchangeable timestamps.
//
// `poAt` is when the die was ORDERED from whoever makes it; `dateInAt` is when
// the made die ARRIVED. The gap between them is the tooling lead time, which is
// the one number the die sheet exists to answer — design philosophy §5 lists
// "PO-to-date-in lead time" as the die sheet's metric.
//
// Nothing recorded that. Migration 048 documents the encoding (UTC, render via
// partStamp) and never says what either one means, so the pair read as two
// generic stamps and the column was labelled "Date In".

ItemDieLink _die({DateTime? ordered, DateTime? arrived}) => ItemDieLink(
      id: '1',
      toolCode: 'SADP48A',
      poAt: ordered,
      dateInAt: arrived,
    );

void main() {
  group('tooling lead time', () {
    test('is the gap between ordering and arrival', () {
      final die = _die(
        ordered: DateTime.utc(2026, 5, 1, 10),
        arrived: DateTime.utc(2026, 5, 22, 10),
      );
      expect(die.leadTime, const Duration(days: 21));
    });

    test('is unknown until both ends are', () {
      expect(_die(ordered: DateTime.utc(2026, 5, 1)).leadTime, isNull);
      expect(_die(arrived: DateTime.utc(2026, 5, 22)).leadTime, isNull);
      expect(_die().leadTime, isNull);
    });

    test('a die that arrived before it was ordered is left visible', () {
      // Not clamped to zero: a negative lead time is a data problem somebody
      // should see, not one the model should quietly tidy away.
      final die = _die(
        ordered: DateTime.utc(2026, 5, 22),
        arrived: DateTime.utc(2026, 5, 1),
      );
      expect(die.leadTime!.isNegative, isTrue);
      expect(die.leadTime!.inDays, -21);
    });

    test('the order of the two is not symmetric', () {
      // Guards the pair being swapped: ordered-then-arrived is positive, and
      // the reverse is not the same fact.
      final forward = _die(
        ordered: DateTime.utc(2026, 5, 1),
        arrived: DateTime.utc(2026, 5, 10),
      );
      final backward = _die(
        ordered: DateTime.utc(2026, 5, 10),
        arrived: DateTime.utc(2026, 5, 1),
      );
      expect(forward.leadTime, isNot(backward.leadTime));
      expect(forward.leadTime!.isNegative, isFalse);
      expect(backward.leadTime!.isNegative, isTrue);
    });
  });
}
