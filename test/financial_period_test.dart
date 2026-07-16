import 'package:flutter_test/flutter_test.dart';

import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/financial_period.dart';

RecurrenceRule _income({
  int id = 1,
  required double amount,
  required DateTime start,
  bool active = true,
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
}
