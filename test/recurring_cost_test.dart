import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/recurrence_math.dart';
import 'package:floos/domain/recurring_cost.dart';

RecurrenceRule _rule({
  double amount = 100,
  Frequency frequency = Frequency.monthly,
  int interval = 1,
  required DateTime start,
  DateTime? end,
  DateTime? lastMaterialized,
  bool active = true,
  TxnType type = TxnType.expense,
  DateTime? overrideScheduled,
  DateTime? overrideDate,
}) =>
    RecurrenceRule(
      id: 1,
      title: 'x',
      amount: amount,
      categoryId: 1,
      type: type,
      frequency: frequency,
      interval: interval,
      startDate: start,
      endDate: end,
      lastMaterialized: lastMaterialized,
      active: active,
      nextOverrideScheduled: overrideScheduled,
      nextOverrideDate: overrideDate,
    );

final _now = DateTime(2026, 11, 5, 14, 30);

void main() {
  test('monthly: twelve charges', () {
    final r = _rule(start: DateTime(2026, 1, 10));
    expect(costNext12Months(r, _now), 1200);
  });

  test('every two months: six charges', () {
    final r = _rule(start: DateTime(2026, 1, 10), interval: 2);
    expect(costNext12Months(r, _now), 600);
  });

  test('weekly: counted from the real dates, not 52 by assumption', () {
    final r = _rule(
        amount: 10, frequency: Frequency.weekly, start: DateTime(2026, 1, 1));
    final expected = occurrencesBetween(
      startDate: r.startDate,
      frequency: Frequency.weekly,
      lastMaterialized: DateTime(2026, 11, 4),
      until: DateTime(2027, 11, 4),
    ).length;
    expect(costNext12Months(r, _now), expected * 10);
    expect(expected, anyOf(52, 53));
  });

  test('yearly due in three months: one charge', () {
    final r = _rule(
        amount: 1200,
        frequency: Frequency.yearly,
        start: DateTime(2025, 2, 1));
    expect(costNext12Months(r, _now), 1200);
  });

  test('an end date in five months caps it at five charges', () {
    final r = _rule(start: DateTime(2026, 1, 10), end: DateTime(2027, 3, 31));
    // 10 Nov, 10 Dec, 10 Jan, 10 Feb, 10 Mar.
    expect(costNext12Months(r, _now), 500);
  });

  test('a rule starting next month counts from then', () {
    final r = _rule(start: DateTime(2027, 1, 1));
    // 1 Jan … 1 Nov 2027 = 11 charges before 5 Nov 2027.
    expect(costNext12Months(r, _now), 1100);
  });

  test('a charge already booked today is not counted again', () {
    final r = _rule(
        start: DateTime(2026, 1, 5), lastMaterialized: DateTime(2026, 11, 5));
    expect(occurrencesInNext12Months(r, _now).first, DateTime(2026, 12, 5));
    // 5 Dec 2026 … 5 Oct 2027: today's charge is already paid, and
    // 5 Nov 2027 is outside the exclusive window.
    expect(costNext12Months(r, _now), 1100);
  });

  test('a paused rule costs nothing', () {
    expect(
        costNext12Months(
            _rule(start: DateTime(2026, 1, 10), active: false), _now),
        0);
  });

  test('an income rule is not a cost', () {
    expect(
        costNext12Months(
            _rule(start: DateTime(2026, 1, 10), type: TxnType.income), _now),
        0);
  });

  test('an override moves the next charge but does not add one', () {
    final r = _rule(
      start: DateTime(2026, 1, 10),
      overrideScheduled: DateTime(2026, 11, 10),
      overrideDate: DateTime(2026, 11, 8),
    );
    final dates = occurrencesInNext12Months(r, _now);
    expect(dates.first, DateTime(2026, 11, 8));
    expect(dates, isNot(contains(DateTime(2026, 11, 10))));
    expect(costNext12Months(r, _now), 1200);
  });

  test('the total sums active expense rules only', () {
    final rules = [
      _rule(start: DateTime(2026, 1, 10)), // 1200
      _rule(amount: 50, start: DateTime(2026, 1, 10), active: false),
      _rule(amount: 999, start: DateTime(2026, 1, 10), type: TxnType.income),
      _rule(
          amount: 300,
          frequency: Frequency.yearly,
          start: DateTime(2026, 3, 1)), // 300
    ];
    expect(totalNext12Months(rules, _now), 1500);
  });
}
