import '../data/database.dart';
import '../data/enums.dart';

/// One top-level category's slice of a set of expenses: its total, how many
/// transactions rolled into it (sub-categories included), the per-transaction
/// average, and the rows themselves for a drill-down.
class CategoryStat {
  final int categoryId; // top-level category id
  final double total;
  final List<TxnRow> transactions;
  const CategoryStat({
    required this.categoryId,
    required this.total,
    required this.transactions,
  });

  int get count => transactions.length;
  double get average => count == 0 ? 0 : total / count;
}

/// Groups [rows]' expenses by their top-level category (sub-categories roll up
/// to the parent, exactly like budgetProgress), summing totals and collecting
/// the transactions. Sorted by total, biggest first; income rows are ignored.
List<CategoryStat> categoryBreakdown(List<TxnRow> rows) {
  final totals = <int, double>{};
  final txns = <int, List<TxnRow>>{};
  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
    final topId = r.category.parentId ?? r.category.id;
    totals[topId] = (totals[topId] ?? 0) + r.txn.amount;
    (txns[topId] ??= <TxnRow>[]).add(r);
  }
  return [
    for (final e in totals.entries)
      CategoryStat(
        categoryId: e.key,
        total: e.value,
        transactions: txns[e.key]!,
      ),
  ]..sort((a, b) => b.total.compareTo(a.total));
}
