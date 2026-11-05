import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/data/export.dart';
import 'package:floos/domain/period_summary.dart';

/// The statistics CSV is grouped by salary cycle, like every other history in
/// the app. It used to be grouped by calendar month, which split one salary
/// across two rows: with a payday on the 25th, the month the salary landed in
/// showed the income and almost none of the spending it paid for.

RecurrenceRule _salary() => RecurrenceRule(
      id: 1,
      title: 'راتب',
      amount: 10000,
      categoryId: 9,
      type: TxnType.income,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: DateTime(2026, 1, 25),
      active: true,
    );

Category _cat(TxnType t) => Category(
      id: t == TxnType.income ? 9 : 1,
      name: 'c',
      iconKey: 'k',
      colorValue: 0,
      type: t,
      kind: CategoryKind.essential,
      archived: false,
      sortOrder: 0,
    );

TxnRow _txn(TxnType t, double amount, DateTime date) => TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: t == TxnType.income ? 9 : 1,
        type: t,
        date: date,
        createdAt: date,
      ),
      category: _cat(t),
    );

void main() {
  test('one row per salary cycle, oldest first, straddling two months', () {
    final rows = [
      // Cycle 25 Jun – 24 Jul.
      _txn(TxnType.income, 10000, DateTime(2026, 6, 25)),
      _txn(TxnType.expense, 300, DateTime(2026, 6, 28)),
      _txn(TxnType.expense, 2000, DateTime(2026, 7, 10)),
      // Cycle 25 Jul – 24 Aug.
      _txn(TxnType.income, 10000, DateTime(2026, 7, 25)),
      _txn(TxnType.expense, 500, DateTime(2026, 8, 2)),
    ];
    final contributions = [
      SavingsContribution(
          id: 1,
          goalId: 1,
          amount: 1000,
          date: DateTime(2026, 7, 1),
          external: false,
          planned: false),
    ];

    final csv = statsCsvFor(
        cycleSummaries(rows, contributions, [_salary()], DateTime(2026, 8, 5)));
    final lines = csv.replaceFirst('\uFEFF', '').trim().split('\n');

    expect(csv.startsWith('\uFEFF'), isTrue, reason: 'Excel needs the BOM');
    expect(lines.first,
        'cycle_start,cycle_end,income,spent,saved,remaining,savings_rate');
    expect(lines.sublist(1), [
      // The whole June-paid salary and everything it paid for, in one row.
      '2026-06-25,2026-07-24,10000.00,2300.00,1000.00,6700.00,10.0',
      '2026-07-25,2026-08-24,10000.00,500.00,0.00,9500.00,0.0',
    ]);
  });

  test('a cycle with no income leaves the savings rate blank', () {
    final rows = [_txn(TxnType.expense, 50, DateTime(2026, 7, 26))];
    final csv = statsCsvFor(
        cycleSummaries(rows, const [], [_salary()], DateTime(2026, 8, 5)));
    final row = csv.trim().split('\n').last;
    expect(row, '2026-07-25,2026-08-24,0.00,50.00,0.00,-50.00,');
  });
}
