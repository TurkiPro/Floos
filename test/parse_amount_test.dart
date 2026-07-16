import 'package:flutter_test/flutter_test.dart';
import 'package:floos/domain/parse_amount.dart';

void main() {
  group('parseAmount', () {
    test('Western digits, with historic comma-as-decimal', () {
      expect(parseAmount('12.50'), 12.5);
      expect(parseAmount('12,50'), 12.5);
      expect(parseAmount('1000'), 1000);
    });

    test('Eastern Arabic-Indic digits and separators', () {
      expect(parseAmount('١٢٣'), 123);
      expect(parseAmount('١٢٫٥'), 12.5); // Arabic decimal separator ٫
      expect(
          parseAmount('١٬٢٣٤'), 1234); // Arabic thousands separator ٬ dropped
    });

    test('Persian-variant digits', () {
      expect(parseAmount('۴۵'), 45);
    });

    test('mixed Eastern digits with a Western dot', () {
      expect(parseAmount('١٢.٥'), 12.5);
    });

    test('garbage and empty input is null', () {
      expect(parseAmount('abc'), isNull);
      expect(parseAmount(''), isNull);
      expect(parseAmount('   '), isNull);
    });
  });

  group('parseCount', () {
    test('parses whole numbers in either script', () {
      expect(parseCount('٢'), 2);
      expect(parseCount('3'), 3);
    });

    test('rejects a decimal', () {
      expect(parseCount('٢٫٥'), isNull);
    });
  });
}
