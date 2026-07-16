import '../data/database.dart';
import '../data/enums.dart';

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

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// For each budgeted top-level category, projects this month's spend to month
/// end from the pace so far (spent × daysInMonth / dayOfMonth) and returns the
/// ones on track to blow the budget — biggest overshoot first. Already-over
/// categories are included (their projection only grows). Sub-category spend
/// rolls up to the parent, exactly like budgetProgress.
List<BudgetRisk> budgetRisks(
  List<CategoryBudget> budgets,
  List<TxnRow> rows,
  DateTime now,
) {
  final spentByTop = <int, double>{};
  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
    final d = r.txn.date;
    if (d.year != now.year || d.month != now.month) continue;
    final topId = r.category.parentId ?? r.category.id;
    spentByTop[topId] = (spentByTop[topId] ?? 0) + r.txn.amount;
  }

  final dim = _daysInMonth(now.year, now.month);
  final elapsed = now.day.clamp(1, dim);

  final out = <BudgetRisk>[];
  for (final b in budgets) {
    final spent = spentByTop[b.categoryId] ?? 0;
    if (spent <= 0) continue;
    final projected = spent * dim / elapsed;
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
