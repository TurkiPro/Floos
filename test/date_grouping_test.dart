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

  group('distinctMonthsDesc', () {
    test('empty list returns no months', () {
      expect(distinctMonthsDesc(const []), isEmpty);
    });

    test('dedupes multiple dates within the same month', () {
      final months = distinctMonthsDesc([
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 15),
        DateTime(2026, 6, 30),
      ]);
      expect(months, [const MonthKey(year: 2026, month: 6)]);
    });

    test('sorts newest month first, including across a year boundary', () {
      final months = distinctMonthsDesc([
        DateTime(2025, 12, 10),
        DateTime(2026, 2, 1),
        DateTime(2026, 1, 5),
      ]);
      expect(months, [
        const MonthKey(year: 2026, month: 2),
        const MonthKey(year: 2026, month: 1),
        const MonthKey(year: 2025, month: 12),
      ]);
    });
  });

  group('dayName / dayFullLabel', () {
    test('names the weekday in Arabic', () {
      // 2026-07-03 is a Friday.
      expect(dayName(DateTime(2026, 7, 3)), 'الجمعة');
      // 2026-07-05 is a Sunday.
      expect(dayName(DateTime(2026, 7, 5)), 'الأحد');
    });

    test('prefixes today/yesterday and includes weekday + Arabic date', () {
      final today = DateTime(2026, 7, 3);
      expect(dayFullLabel(DateTime(2026, 7, 3), today: today),
          'اليوم • الجمعة، 3 يوليو');
      expect(dayFullLabel(DateTime(2026, 7, 2), today: today),
          'أمس • الخميس، 2 يوليو');
      expect(dayFullLabel(DateTime(2026, 7, 1), today: today),
          'الأربعاء، 1 يوليو');
    });
  });

  group('monthLabel', () {
    test('formats an Arabic month name with the year', () {
      expect(monthLabel(const MonthKey(year: 2026, month: 7)), 'يوليو 2026');
    });

    test('handles the first and last month of the year', () {
      expect(monthLabel(const MonthKey(year: 2026, month: 1)), 'يناير 2026');
      expect(monthLabel(const MonthKey(year: 2026, month: 12)), 'ديسمبر 2026');
    });
  });
}
