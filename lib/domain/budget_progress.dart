import '../data/database.dart';
import '../data/enums.dart';
import 'financial_period.dart';

/// One category's monthly budget vs. what's actually been spent against it this
/// month. Spent is summed live from transactions (sub-categories roll up to
/// their top-level parent), never stored.
class BudgetLine {
  final int categoryId;
  final double budgeted;
  final double spent;

  const BudgetLine({
    required this.categoryId,
    required this.budgeted,
    required this.spent,
  });

  double get remaining => budgeted - spent;

  /// 0..1+ — how much of the budget is used. Can exceed 1 when over budget;
  /// callers clamp for a progress bar but read the raw value for [isOver].
  double get ratio => budgeted > 0 ? spent / budgeted : 0;

  bool get isOver => spent > budgeted;
}

/// Builds a [BudgetLine] per budget, summing this salary cycle's expenses by
/// top-level category. Spend follows the financial [period] (the same window the
/// home dashboard and statistics use), not the calendar month, so the budgets
/// screen and the stats "over budget" flags can't disagree. Rows outside the
/// cycle and income are ignored. Sorted most-consumed first, so the tightest
/// budgets surface at the top.
List<BudgetLine> budgetProgress(
  List<CategoryBudget> budgets,
  List<TxnRow> rows,
  FinancialPeriod period,
) {
  final spentByTop = <int, double>{};
  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
    if (!period.contains(r.txn.date)) continue;
    final topId = r.category.parentId ?? r.category.id;
    spentByTop[topId] = (spentByTop[topId] ?? 0) + r.txn.amount;
  }

  final lines = [
    for (final b in budgets)
      BudgetLine(
        categoryId: b.categoryId,
        budgeted: b.amount,
        spent: spentByTop[b.categoryId] ?? 0,
      ),
  ]..sort((a, b) => b.ratio.compareTo(a.ratio));

  return lines;
}
