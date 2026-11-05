import '../data/database.dart';
import '../data/enums.dart';
import 'budget_advisor.dart' show previousCycles;
import 'category_breakdown.dart';
import 'financial_period.dart';
import 'period_summary.dart';

/// The last twelve salary cycles side by side.
///
/// "A year" here is twelve cycles, the current one included and marked in
/// progress — never a calendar year; the cycle is the app's only period unit.
///
/// Built only from functions other screens already use: per-cycle figures
/// from [cycleSummaries] (the same totals the cycle-detail screen shows) and
/// category shares from [categoryBreakdown]. It restates numbers that appear
/// elsewhere, so it must not compute them its own way.
class YearReview {
  /// Cycles with any activity, oldest first.
  final List<CycleSummary> cycles;

  /// The cycle in progress; its figures are partial.
  final FinancialPeriod current;

  final double income;
  final double spent;
  final double saved;

  /// Among COMPLETED cycles with income, the best and worst savings rate. The
  /// cycle in progress is left out: it would win "best" the day after payday.
  final CycleSummary? best;
  final CycleSummary? worst;

  /// The five biggest top-level spending categories, biggest first.
  final List<CategoryStat> topCategories;

  /// Spending through recurring rules (rent, bills, subscriptions) versus
  /// everything chosen in the moment — the same split as the statistics
  /// screen.
  final double committed;
  final double discretionary;

  const YearReview({
    required this.cycles,
    required this.current,
    required this.income,
    required this.spent,
    required this.saved,
    required this.best,
    required this.worst,
    required this.topCategories,
    required this.committed,
    required this.discretionary,
  });

  double? get savingsRate => income > 0 ? saved / income : null;

  bool isCurrent(CycleSummary c) => c.period.start == current.start;
}

/// How many cycles a review covers, the current one included.
const reviewCycles = 12;

YearReview yearReview({
  required List<TxnRow> rows,
  required List<SavingsContribution> contributions,
  required List<RecurrenceRule> incomeRules,
  required DateTime now,
}) {
  final current = financialPeriod(incomeRules, now);
  final earlier = previousCycles(incomeRules, now, reviewCycles - 1);
  final windowStart = earlier.isEmpty ? current.start : earlier.last.start;
  bool inWindow(DateTime d) =>
      !d.isBefore(windowStart) && d.isBefore(current.end);

  final cycles = cycleSummaries(rows, contributions, incomeRules, now)
      .where((c) => !c.period.start.isBefore(windowStart))
      .toList()
      .reversed
      .toList();

  var income = 0.0, spent = 0.0, saved = 0.0;
  for (final c in cycles) {
    income += c.income;
    spent += c.spent;
    saved += c.saved;
  }

  CycleSummary? best, worst;
  for (final c in cycles) {
    final rate = c.savingsRate;
    if (rate == null || c.period.start == current.start) continue;
    if (best == null || rate > best.savingsRate!) best = c;
    if (worst == null || rate < worst.savingsRate!) worst = c;
  }

  final expenses = [
    for (final r in rows)
      if (r.txn.type == TxnType.expense && inWindow(r.txn.date)) r,
  ];
  var committed = 0.0, discretionary = 0.0;
  for (final r in expenses) {
    if (r.txn.recurrenceId != null) {
      committed += r.txn.amount;
    } else {
      discretionary += r.txn.amount;
    }
  }

  return YearReview(
    cycles: cycles,
    current: current,
    income: income,
    spent: spent,
    saved: saved,
    best: best,
    worst: worst,
    topCategories: categoryBreakdown(expenses).take(5).toList(),
    committed: committed,
    discretionary: discretionary,
  );
}
