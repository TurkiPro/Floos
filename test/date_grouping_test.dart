import 'package:flutter_test/flutter_test.dart';
import 'package:floos/domain/date_grouping.dart';

void main() {
  group('dayLabel', () {
    test('same day returns today label', () {
      final today = DateTime(2026, 6, 30, 14, 30);
      expect(dayLabel(DateTime(2026, 6, 30, 9, 0), today: today), 'اليوم');
    });

    test('exactly one day back returns yesterday label', () {
      final today = DateTime(2026, 6, 30);
      expect(dayLabel(DateTime(2026, 6, 29), today: today), 'أمس');
    });

    test('two days back returns a formatted date, not yesterday', () {
      final today = DateTime(2026, 6, 30);
      final label = dayLabel(DateTime(2026, 6, 28), today: today);
      expect(label, isNot('أمس'));
      expect(label, isNot('اليوم'));
    });

    test('ignores time-of-day when computing the boundary', () {
      // 23:59 yesterday vs 00:01 today must still read as exactly one day
      // apart, not zero -- a naive Duration diff without truncating to
      // whole dates would see ~2 minutes and misreport "today".
      final today = DateTime(2026, 6, 30, 0, 1);
      final yesterday = DateTime(2026, 6, 29, 23, 59);
      expect(dayLabel(yesterday, today: today), 'أمس');
    });

    test('handles a year boundary correctly', () {
      final today = DateTime(2026, 1, 1);
      expect(dayLabel(DateTime(2025, 12, 31), today: today), 'أمس');
    });
  });

  group('groupByDay', () {
    test('empty list returns no groups', () {
      expect(groupByDay<int>(const [], (_) => DateTime(2026, 1, 1)), isEmpty);
    });

    test('single item returns a single group', () {
      final groups = groupByDay<String>(
        const ['a'],
        (_) => DateTime(2026, 6, 30, 10),
      );
      expect(groups, hasLength(1));
      expect(groups.single.key, DateTime(2026, 6, 30));
      expect(groups.single.value, ['a']);
    });

    test('groups items on the same day together regardless of time', () {
      final items = [
        (DateTime(2026, 6, 30, 18), 'evening'),
        (DateTime(2026, 6, 30, 8), 'morning'),
      ];
      final groups = groupByDay(items, (e) => e.$1);
      expect(groups, hasLength(1));
      expect(groups.single.value.map((e) => e.$2), ['evening', 'morning']);
    });

    test('preserves descending day order across groups', () {
      final items = [
        DateTime(2026, 6, 30),
        DateTime(2026, 6, 29),
        DateTime(2026, 6, 29),
        DateTime(2026, 6, 27),
      ];
      final groups = groupByDay<DateTime>(items, (d) => d);
      expect(groups.map((g) => g.key), [
        DateTime(2026, 6, 30),
        DateTime(2026, 6, 29),
        DateTime(2026, 6, 27),
      ]);
      expect(groups[1].value, hasLength(2));
    });

    test('groups correctly across a year boundary', () {
      final items = [DateTime(2026, 1, 1), DateTime(2025, 12, 31)];
      final groups = groupByDay<DateTime>(items, (d) => d);
      expect(groups.map((g) => g.key), [
        DateTime(2026, 1, 1),
        DateTime(2025, 12, 31),
      ]);
    });
  });
}
