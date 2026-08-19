import 'package:core_erp/core/widgets/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';

SearchableSelectOption<int> _option(String label, {String? searchText}) {
  return SearchableSelectOption<int>(
    value: 1,
    label: label,
    searchText: searchText,
  );
}

void main() {
  group('SearchableSelectOption.matchesQuery', () {
    final socket = _option('Anchor Roma Classic Socket 10A • Base item');

    test('empty query matches everything', () {
      expect(socket.matchesQuery(''), isTrue);
      expect(socket.matchesQuery('   '), isTrue);
    });

    test('matches terms that are not adjacent in the label', () {
      expect(socket.matchesQuery('roma 10'), isTrue);
      expect(socket.matchesQuery('anchor 10a'), isTrue);
      expect(socket.matchesQuery('anchor socket base'), isTrue);
    });

    test('term order does not matter', () {
      expect(socket.matchesQuery('10 roma'), isTrue);
      expect(socket.matchesQuery('socket anchor'), isTrue);
    });

    test('still matches a contiguous query', () {
      expect(socket.matchesQuery('roma classic'), isTrue);
      expect(socket.matchesQuery('Anchor Roma Classic Socket 10A'), isTrue);
    });

    test('every term must be present', () {
      expect(socket.matchesQuery('roma 20'), isFalse);
      expect(socket.matchesQuery('anchor switch'), isFalse);
    });

    test('is case insensitive and tolerates extra whitespace', () {
      expect(socket.matchesQuery('  ROMA   10a '), isTrue);
    });

    test('searches searchText when provided, not the label', () {
      final option = _option('AR-SOCK-10', searchText: 'anchor roma socket 10a');
      expect(option.matchesQuery('roma 10'), isTrue);
      // 'ar-sock' appears in the label only, so it must not match.
      expect(option.matchesQuery('ar-sock'), isFalse);
    });
  });
}
