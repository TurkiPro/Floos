import 'package:flutter_test/flutter_test.dart';
import 'package:floos/data/database.dart';
import 'package:floos/data/enums.dart';
import 'package:floos/domain/financial_period.dart';
import 'package:floos/domain/weekly_budget_status.dart';
import 'package:floos/domain/weekly_performance.dart';

/// Past weeks are judged against the budget that was actually in force.
///
/// The case that exposed it (v1.4.0, reported 2026-11-08): a deficit carried
/// in from the previous cycle, so the balance cap set the weekly budget all
/// cycle long. The weekly-performance screen judged last week against the
/// UNCAPPED figure (1,523), said «أحسنت — under by 18», and this week's budget
/// (1,306) then dropped for no visible reason. Against the budget the home
/// card had actually shown that week (~1,360), the week was over.

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

final _salary = [
  RecurrenceRule(
    id: 1,
    title: 'راتب',
    amount: 10000,
    categoryId: 9,
    type: TxnType.income,
    frequency: Frequency.monthly,
    interval: 1,
    startDate: DateTime(2026, 1, 25),
    active: true,
  ),
];

// Payday on the 25th; today is the first day of week 3 (8 Nov).
final _now = DateTime(2026, 11, 8, 7, 19);

final _rows = [
  // Overspent last cycle: 4,000 out with no income behind it — a deficit.
  _txn(TxnType.expense, 4000, DateTime(2026, 10, 20)),
  _txn(TxnType.income, 10000, DateTime(2026, 10, 25)),
  _txn(TxnType.expense, 1700, DateTime(2026, 10, 28)), // week 1
  _txn(TxnType.expense, 1500, DateTime(2026, 11, 3)), // week 2
];

double _inForce(List<TxnRow> rows, DateTime weekEnd) => weeklyBudgetInForce(
      rows: rows,
      incomeRules: _salary,
      expenseRules: const [],
      contributions: const [],
      investments: const [],
      debts: const [],
      weekEnd: weekEnd,
    );

List<WeekPerformance> _weeks(List<TxnRow> rows) {
  final period = financialPeriod(_salary, _now);
  final home = weeklyBudgetStatus(
    rows: rows,
    incomeRules: _salary,
    expenseRules: const [],
    contributions: const [],
    investments: const [],
    debts: const [],
    now: _now,
  );
  return weeklyPerformance(
    rows: rows,
    byId: const {},
    now: _now,
    periodStart: period.start,
    periodEnd: period.end,
    currentWeekBudget: home.budget,
    pastWeekBudget: (ws, we) => _inForce(rows, we),
  );
}

void main() {
  test('last week is judged against the budget the home card showed for it',
      () {
    final weeks = _weeks(_rows);
    final week2 = weeks.firstWhere((w) => w.index == 2);

    // What the home card said on the last day of week 2 (7 Nov), from the
    // data as it stood then.
    final shownThen = weeklyBudgetStatus(
      rows: [
        for (final r in _rows)
          if (r.txn.date.isBefore(DateTime(2026, 11, 8))) r
      ],
      incomeRules: _salary,
      expenseRules: const [],
      contributions: const [],
      investments: const [],
      debts: const [],
      now: DateTime(2026, 11, 7),
    ).budget;
    expect(week2.budget, closeTo(shownThen, 1e-9));

    // The cap set it: 4,300 left at the week's start, 24 days to payday.
    expect(week2.budget, closeTo(4300 / 24 * 7, 1e-6));
    expect(week2.over, isTrue,
        reason: 'spent 1,500 against ~1,254: over, not «أحسنت»');
  });

  test('this week drops because last week went over the real budget', () {
    final weeks = _weeks(_rows);
    final week2 = weeks.firstWhere((w) => w.index == 2);
    final week3 = weeks.firstWhere((w) => w.current);
    // 2,800 left, 17 days to payday.
    expect(week3.budget, closeTo(2800 / 17 * 7, 1e-6));
    expect(week3.budget, lessThan(week2.budget),
        reason: 'and the screen now says why: week 2 was over');
  });

  test("a finished week's budget is frozen", () {
    final before = _weeks(_rows).firstWhere((w) => w.index == 2).budget;
    final after = _weeks([
      ..._rows,
      _txn(TxnType.expense, 2000, DateTime(2026, 11, 8)), // spent this week
      _txn(TxnType.income, 3000, DateTime(2026, 11, 8)), // a bonus today
    ]).firstWhere((w) => w.index == 2).budget;
    expect(after, closeTo(before, 1e-9),
        reason: 'nothing after the week ended may rewrite it');
  });

  test('the current week shows all seven days, not just today', () {
    final week3 = _weeks(_rows).firstWhere((w) => w.current);
    expect(week3.weekStart, DateTime(2026, 11, 8));
    expect(week3.days, hasLength(7));
    expect(week3.days.last.date, DateTime(2026, 11, 14));
  });
}
