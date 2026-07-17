import '../data/database.dart';
import '../data/enums.dart';
import 'financial_period.dart';

/// A category whose spending pace, projected to the end of the month, is on
/// track to exceed its budget.
class BudgetRisk {
  final int categoryId;
  final double spent; // this month so far
  final double projected; // pace projected to month end
  final double budget;
  const BudgetRisk({
    required this.categoryId,
    required this.spent,
    required this.projected,
    required this.budget,
  });

  double get overBy => projected - budget;
  double get overByPct => budget > 0 ? overBy / budget * 100 : 0;

  /// Already past the budget with actual spend (not just projected).
  bool get alreadyOver => spent >= budget;

  /// How far actual spend is over the budget, as a percent (0 when not yet over).
  double get spentOverPct =>
      budget > 0 && spent > budget ? (spent - budget) / budget * 100 : 0;
}

/// For each budgeted top-level category, projects this cycle's spend to the
/// cycle end from the pace so far (spent × cycleDays / daysElapsed) and returns
/// the ones on track to blow the budget — biggest overshoot first. Already-over
/// categories are included (their projection only grows). Spend and pace follow
/// the salary cycle [period] — the same window the rest of the statistics screen
/// uses — not the calendar month, so a category already over for the cycle reads
/// as over (not merely "projected"). Sub-category spend rolls up to the parent,
/// exactly like budgetProgress.
List<BudgetRisk> budgetRisks(
  List<CategoryBudget> budgets,
  List<TxnRow> rows,
  DateTime now,
  FinancialPeriod period,
) {
  final spentByTop = <int, double>{};
  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
    if (!period.contains(r.txn.date)) continue;
    final topId = r.category.parentId ?? r.category.id;
    spentByTop[topId] = (spentByTop[topId] ?? 0) + r.txn.amount;
  }

  final today = DateTime(now.year, now.month, now.day);
  final periodDays = period.end.difference(period.start).inDays;
  final totalDays = periodDays < 1 ? 1 : periodDays;
  final elapsed =
      (today.difference(period.start).inDays + 1).clamp(1, totalDays);

  final out = <BudgetRisk>[];
  for (final b in budgets) {
    final spent = spentByTop[b.categoryId] ?? 0;
    if (spent <= 0) continue;
    final projected = spent * totalDays / elapsed;
    if (projected <= b.amount) continue;
    out.add(BudgetRisk(
      categoryId: b.categoryId,
      spent: spent,
      projected: projected,
      budget: b.amount,
    ));
  }
  out.sort((a, b) => b.overBy.compareTo(a.overBy));
  return out;
}
