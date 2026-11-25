import 'package:flutter_test/flutter_test.dart';
import 'package:core_erp/features/items/domain/part_name.dart';

void main() {
  group('partNameWithNo', () {
    test('formats part name with part number', () {
      expect(partNameWithNo('patti', 1), 'patti No. 1');
      expect(partNameWithNo('Patti Brass', 42), 'Patti Brass No. 42');
    });

    test('returns plain name when partNo is null or <= 0', () {
      expect(partNameWithNo('patti', null), 'patti');
      expect(partNameWithNo('patti', 0), 'patti');
      expect(partNameWithNo('patti', -1), 'patti');
    });

    test('does not duplicate suffix if already present', () {
      expect(partNameWithNo('patti No. 1', 1), 'patti No. 1');
      expect(partNameWithNo('patti no. 1', 1), 'patti no. 1');
    });

    test('handles empty name with partNo', () {
      expect(partNameWithNo('', 1), 'No. 1');
      expect(partNameWithNo('   ', 2), 'No. 2');
    });
  });
}
