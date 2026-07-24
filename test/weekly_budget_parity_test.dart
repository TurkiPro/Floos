import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/financial_period.dart';
import 'package:floos/domain/statistics_summary.dart';
import 'package:floos/domain/weekly_budget_status.dart';

/// The home status card and the statistics card must show the SAME weekly
/// budget. They used to be computed by two separate implementations, so this
/// locks them to one number for identical input.

Category _cat(TxnType type, CategoryKind kind) => Category(
      id: 1,
      name: 'c',
      iconKey: 'k',
      colorValue: 0,
      type: type,
      kind: kind,
      archived: false,
      sortOrder: 0,
    );

TxnRow _txn(TxnType type, double amount, DateTime date,
        {int? recurrenceId, CategoryKind kind = CategoryKind.essential}) =>
    TxnRow(
      txn: Txn(
        id: 1,
        amount: amount,
        categoryId: 1,
        type: type,
        date: date,
        recurrenceId: recurrenceId,
        createdAt: date,
      ),
      category: _cat(type, kind),
    );

RecurrenceRule _salary(DateTime start) => RecurrenceRule(
      id: 1,
      title: 'راتب',
      amount: 19000,
      categoryId: 1,
      type: TxnType.income,
      frequency: Frequency.monthly,
      interval: 1,
      startDate: start,
      active: true,
    );

void main() {
  test('home and stats derive the same weekly budget from the same data', () {
    final now = DateTime(2026, 7, 16);
    final rules = [_salary(DateTime(2026, 1, 25))];
    final rows = [
      _txn(TxnType.income, 19000, DateTime(2026, 6, 25)),
      _txn(TxnType.expense, 500, DateTime(2026, 6, 28)),
      _txn(TxnType.expense, 300, DateTime(2026, 7, 2),
          kind: CategoryKind.luxury),
      // A recurring obligation: excluded from the weekly budget, but it still
      // reduces the balance the budget is capped by.
      _txn(TxnType.expense, 1200, DateTime(2026, 7, 5), recurrenceId: 9),
      _txn(TxnType.expense, 250, DateTime(2026, 7, 14)),
      _txn(TxnType.expense, 120, DateTime(2026, 7, 16)),
    ];
    final contributions = [
      SavingsContribution(
          id: 1,
          goalId: 1,
          amount: 1000,
          date: DateTime(2026, 7, 1),
          external: false),
    ];

    final period = financialPeriod(rules, now);
    final stats = StatisticsSummary.from(rows, contributions, now, period);
    final home = weeklyBudgetStatus(
      rows: rows,
      incomeRules: rules,
      contributions: contributions,
      now: now,
    );

    expect(stats.recommendedWeekly, closeTo(home.budget, 1e-9),
        reason: 'the home card and the statistics card must agree');
  });
}
