import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/calendar_format.dart';
import 'package:floos/domain/financial_period.dart';
import 'package:floos/domain/period_summary.dart';
import 'package:floos/domain/year_review.dart';

/// The twelve-cycle "years" of the behaviour view. They replace calendar
/// years, which cut a salary cycle in two at January.

Category _cat(TxnType type) => Category(
      id: type == TxnType.income ? 9 : 1,
      name: 'c',
      iconKey: 'k',
      colorValue: 0,
      type: type,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
    );

TxnRow _txn(TxnType type, double amount, DateTime date) => TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: type == TxnType.income ? 9 : 1,
        type: type,
        date: date,
        createdAt: date,
      ),
      category: _cat(type),
    );

TxnRow _income(double amount, DateTime date) =>
    _txn(TxnType.income, amount, date);
TxnRow _expense(double amount, DateTime date) =>
    _txn(TxnType.expense, amount, date);

SavingsContribution _contrib(double amount, DateTime date,
        {bool external = false}) =>
    SavingsContribution(
        id: 1,
        goalId: 1,
        amount: amount,
        date: date,
        external: external,
        planned: false);

final _salary = [
  RecurrenceRule(
    id: 1,
    title: 'راتب',
    amount: 10000,
    categoryId: 9,
    type: TxnType.income,
    frequency: Frequency.monthly,
    interval: 1,
    startDate: DateTime(2024, 1, 25),
    active: true,
  ),
];

// Payday on the 25th. The current cycle is 25 Oct – 24 Nov 2026, so the newest
// block of twelve runs 25 Nov 2025 – 24 Nov 2026, and the one before it ends
// on 24 Nov 2025.
final _now = DateTime(2026, 11, 5);

void main() {
  group('cycleYearSummaries', () {
    test('blocks of twelve cycles, newest first, cut at a payday', () {
      final rows = [
        _income(10000, DateTime(2026, 10, 25)), // newest block
        _expense(300, DateTime(2025, 11, 25)), // newest block's first day
        _expense(700, DateTime(2025, 11, 24)), // the block before
        _income(10000, DateTime(2025, 1, 25)), // the block before
      ];
      final out = cycleYearSummaries(rows, const [], _salary, _now);

      expect(out, hasLength(2));
      expect(out[0].period.start, DateTime(2025, 11, 25));
      expect(out[0].period.end, DateTime(2026, 11, 25));
      expect(out[0].inProgress, isTrue);
      expect(out[0].income, 10000);
      expect(out[0].spent, 300);

      // The older block begins where the history does (the first salary on
      // 25 Jan 2025), not a full twelve cycles back.
      expect(out[1].period.start, DateTime(2025, 1, 25));
      expect(out[1].period.end, DateTime(2025, 11, 25));
      expect(out[1].cycleCount, 10);
      expect(out[1].inProgress, isFalse);
      expect(out[1].income, 10000);
      expect(out[1].spent, 700,
          reason: 'a calendar year would have split these across 2025/2026');
    });

    test('the oldest block stops where the history does', () {
      final rows = [
        _income(10000, DateTime(2026, 10, 25)),
        _expense(50, DateTime(2025, 9, 1)), // two cycles into the older block
      ];
      final out = cycleYearSummaries(rows, const [], _salary, _now);
      expect(out.last.cycleCount, lessThan(cyclesPerYear));
      expect(out.first.cycleCount, cyclesPerYear);
    });

    test('external savings are left out, internal ones counted', () {
      final out = cycleYearSummaries(
        [_income(10000, DateTime(2026, 10, 25))],
        [
          _contrib(1000, DateTime(2026, 10, 26)),
          _contrib(5000, DateTime(2026, 10, 27), external: true),
        ],
        _salary,
        _now,
      );
      expect(out.single.saved, 1000);
      expect(out.single.savingsRate, 0.1);
      expect(out.single.remaining, 9000);
    });

    test('an empty block is skipped, and no history means none', () {
      final out = cycleYearSummaries([
        _income(10000, DateTime(2026, 10, 25)),
        _expense(10, DateTime(2023, 12, 1)), // three blocks back
      ], const [], _salary, _now);
      expect(out, hasLength(2), reason: 'the empty block between is skipped');
      expect(cycleYearSummaries(const [], const [], _salary, _now), isEmpty);
    });

    test('the newest block states exactly what the year review does', () {
      final rows = [
        _income(10000, DateTime(2026, 9, 25)),
        _expense(2500, DateTime(2026, 10, 1)),
        _income(10000, DateTime(2026, 10, 25)),
        _expense(400, DateTime(2026, 11, 2)),
        _expense(999, DateTime(2025, 11, 1)), // outside both
      ];
      final contributions = [_contrib(800, DateTime(2026, 10, 26))];
      final block =
          cycleYearSummaries(rows, contributions, _salary, _now).first;
      final review = yearReview(
          rows: rows,
          contributions: contributions,
          incomeRules: _salary,
          now: _now);
      expect(block.income, review.income);
      expect(block.spent, review.spent);
      expect(block.saved, review.saved);
    });
  });

  test('a span label names both years', () {
    final label = cycleSpanLabelFor(
        FinancialPeriod(DateTime(2025, 11, 25), DateTime(2026, 11, 25)),
        hijri: false);
    expect(label, contains('2025'));
    expect(label, contains('2026'));
    expect(label, startsWith('25 '));
    expect(label, contains('24 '));
  });
}
