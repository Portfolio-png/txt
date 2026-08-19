import 'package:core_erp/core/utils/quantity_shorthand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseQuantityShorthand', () {
    test('reads plain numbers', () {
      expect(parseQuantityShorthand('250'), 250);
      expect(parseQuantityShorthand(' 1000 '), 1000);
      expect(parseQuantityShorthand('12.5'), 12.5);
    });

    test('reads the k / L / cr shorthand in either case', () {
      expect(parseQuantityShorthand('1k'), 1000);
      expect(parseQuantityShorthand('1K'), 1000);
      expect(parseQuantityShorthand('1.5k'), 1500);
      expect(parseQuantityShorthand('1L'), 100000);
      expect(parseQuantityShorthand('10L'), 1000000);
      expect(parseQuantityShorthand('2.5L'), 250000);
      expect(parseQuantityShorthand('1cr'), 10000000);
      expect(parseQuantityShorthand('1 lakh'), 100000);
      expect(parseQuantityShorthand('1 crore'), 10000000);
    });

    test('treats commas as grouping, not decimals', () {
      expect(parseQuantityShorthand('1,00,000'), 100000);
      expect(parseQuantityShorthand('10,00,000'), 1000000);
      expect(parseQuantityShorthand('1,000'), 1000);
    });

    test('rejects what is not a quantity', () {
      expect(parseQuantityShorthand(null), isNull);
      expect(parseQuantityShorthand(''), isNull);
      expect(parseQuantityShorthand('   '), isNull);
      expect(parseQuantityShorthand('k'), isNull);
      expect(parseQuantityShorthand('abc'), isNull);
      expect(parseQuantityShorthand('1x'), isNull);
    });

    test('prefers the longer suffix so cr never reads as c', () {
      expect(parseQuantityShorthand('2cr'), 20000000);
      expect(parseQuantityShorthand('2lakh'), 200000);
    });
  });

  group('formatIndianNumber', () {
    test('groups by three then twos', () {
      expect(formatIndianNumber(100), '100');
      expect(formatIndianNumber(1000), '1,000');
      expect(formatIndianNumber(10000), '10,000');
      expect(formatIndianNumber(100000), '1,00,000');
      expect(formatIndianNumber(1000000), '10,00,000');
      expect(formatIndianNumber(10000000), '1,00,00,000');
      expect(formatIndianNumber(123456789), '12,34,56,789');
    });

    test('keeps a fraction and the sign', () {
      expect(formatIndianNumber(1234.5), '1,234.5');
      expect(formatIndianNumber(-100000), '-1,00,000');
    });
  });

  group('indianScaleLabel', () {
    test('names the scale, and stays quiet for small numbers', () {
      expect(indianScaleLabel(999), '');
      expect(indianScaleLabel(1000), '1 thousand');
      expect(indianScaleLabel(100000), '1 lakh');
      expect(indianScaleLabel(250000), '2.5 lakh');
      expect(indianScaleLabel(10000000), '1 crore');
    });
  });

  group('quantityFieldTooltip', () {
    test('teaches the shorthand while the field is empty', () {
      final tooltip = quantityFieldTooltip('');
      expect(tooltip, contains('1L = 1,00,000'));
      expect(tooltip, contains('10L = 10,00,000'));
    });

    test('reads the typed value back, grouped and named', () {
      expect(quantityFieldTooltip('10L'), '10,00,000  (10 lakh)');
      expect(quantityFieldTooltip('1,00,000'), '1,00,000  (1 lakh)');
      expect(quantityFieldTooltip('250'), '250');
    });
  });
}
