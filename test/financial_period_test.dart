import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/financial_period.dart';

RecurrenceRule _income({
  int id = 1,
  required double amount,
  required DateTime start,
  bool active = true,
  DateTime? overrideDate,
}) =>
    RecurrenceRule(
      id: id,
      title: 'راتب',
      amount: amount,
      categoryId: 1,
      type: TxnType.income,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: start,
      active: active,
      nextOverrideDate: overrideDate,
    );

void main() {
  final now = DateTime(2026, 7, 16);

  test('a salary on the 25th makes the period run 25th → 25th', () {
    final p = financialPeriod(
        [_income(amount: 9000, start: DateTime(2026, 1, 25))], now);
    expect(p.start, DateTime(2026, 6, 25));
    expect(p.end, DateTime(2026, 7, 25));
    expect(p.contains(DateTime(2026, 6, 25)), isTrue,
        reason: 'start inclusive');
    expect(p.contains(DateTime(2026, 7, 24)), isTrue);
    expect(p.contains(DateTime(2026, 7, 25)), isFalse, reason: 'end exclusive');
    expect(p.contains(DateTime(2026, 6, 24)), isFalse);
  });

  test('no recurring income falls back to the calendar month', () {
    final p = financialPeriod(const [], now);
    expect(p.start, DateTime(2026, 7, 1));
    expect(p.end, DateTime(2026, 8, 1));
  });

  test('a salary that has not started yet falls back to the calendar month',
      () {
    final p = financialPeriod(
        [_income(amount: 9000, start: DateTime(2026, 9, 25))], now);
    expect(p.start, DateTime(2026, 7, 1));
    expect(p.end, DateTime(2026, 8, 1));
  });

  test('on payday, the new cycle begins that day', () {
    final p = financialPeriod(
        [_income(amount: 9000, start: DateTime(2026, 1, 25))],
        DateTime(2026, 7, 25));
    expect(p.start, DateTime(2026, 7, 25));
    expect(p.end, DateTime(2026, 8, 25));
  });

  test('the largest active income defines the cycle', () {
    final p = financialPeriod([
      _income(id: 1, amount: 2000, start: DateTime(2026, 1, 10)),
      _income(id: 2, amount: 9000, start: DateTime(2026, 1, 25)),
    ], now);
    expect(p.start, DateTime(2026, 6, 25), reason: 'the 9000 salary wins');
  });

  test('paused income is ignored', () {
    final p = financialPeriod(
        [_income(amount: 9000, start: DateTime(2026, 1, 25), active: false)],
        now);
    expect(p.start, DateTime(2026, 7, 1));
  });

  group('nextSalaryDate agrees with the cycle end', () {
    test('scheduled payday, no override', () {
      final rules = [_income(amount: 9000, start: DateTime(2026, 1, 25))];
      expect(nextSalaryDate(rules, now), DateTime(2026, 7, 25));
      expect(nextSalaryDate(rules, now), financialPeriod(rules, now).end,
          reason: 'the countdown date and the cycle end must be the same day');
    });

    test('null without any recurring income', () {
      expect(nextSalaryDate(const [], now), isNull);
    });

    // The bug behind "6 days left on home vs 8 in stats": an early/late override
    // moves the actual next payday, so both the countdown and the cycle end must
    // follow it rather than the fixed schedule.
    test('an upcoming override pulls the payday (and cycle end) in', () {
      final rules = [
        _income(
            amount: 9000,
            start: DateTime(2026, 1, 25),
            overrideDate: DateTime(2026, 7, 22)),
      ];
      expect(nextSalaryDate(rules, now), DateTime(2026, 7, 22));
      expect(financialPeriod(rules, now).end, DateTime(2026, 7, 22));
      expect(nextSalaryDate(rules, now), financialPeriod(rules, now).end);
    });

    test('a stale override before today is ignored', () {
      final rules = [
        _income(
            amount: 9000,
            start: DateTime(2026, 1, 25),
            overrideDate: DateTime(2026, 7, 10)),
      ];
      expect(nextSalaryDate(rules, now), DateTime(2026, 7, 25));
      expect(financialPeriod(rules, now).end, DateTime(2026, 7, 25));
    });
  });
}
