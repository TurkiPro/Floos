import '../data/database.dart';
import '../data/enums.dart';
import 'date_grouping.dart';

/// How one period (a month or a year) behaved: what came in, what went out,
/// what was set aside, and what was left over at the end of it.
class PeriodSummary {
  final int year;

  /// Null for a yearly summary.
  final int? month;
  final double income;
  final double spent;
  final double saved;

  const PeriodSummary({
    required this.year,
    required this.month,
    required this.income,
    required this.spent,
    required this.saved,
  });

  /// What was left of the income once spending and saving are taken out.
  double get remaining => income - spent - saved;

  /// Share of income that was saved, or null when nothing came in.
  double? get savingsRate => income > 0 ? saved / income : null;

  MonthKey? get monthKey =>
      month == null ? null : MonthKey(year: year, month: month!);
}

/// One summary per month that has any activity, newest first.
List<PeriodSummary> monthlySummaries(
  List<TxnRow> rows,
  List<SavingsContribution> contributions,
) {
  final income = <MonthKey, double>{};
  final spent = <MonthKey, double>{};
  final saved = <MonthKey, double>{};

  for (final r in rows) {
    final k = MonthKey(year: r.txn.date.year, month: r.txn.date.month);
    if (r.txn.type == TxnType.income) {
      income[k] = (income[k] ?? 0) + r.txn.amount;
    } else {
      spent[k] = (spent[k] ?? 0) + r.txn.amount;
    }
  }
  for (final c in contributions) {
    final k = MonthKey(year: c.date.year, month: c.date.month);
    saved[k] = (saved[k] ?? 0) + c.amount;
  }

  final keys = <MonthKey>{...income.keys, ...spent.keys, ...saved.keys}.toList()
    ..sort((a, b) => a.year != b.year ? b.year - a.year : b.month - a.month);

  return [
    for (final k in keys)
      PeriodSummary(
        year: k.year,
        month: k.month,
        income: income[k] ?? 0,
        spent: spent[k] ?? 0,
        saved: saved[k] ?? 0,
      ),
  ];
}

/// One summary per year that has any activity, newest first.
List<PeriodSummary> yearlySummaries(
  List<TxnRow> rows,
  List<SavingsContribution> contributions,
) {
  final income = <int, double>{};
  final spent = <int, double>{};
  final saved = <int, double>{};

  for (final r in rows) {
    final y = r.txn.date.year;
    if (r.txn.type == TxnType.income) {
      income[y] = (income[y] ?? 0) + r.txn.amount;
    } else {
      spent[y] = (spent[y] ?? 0) + r.txn.amount;
    }
  }
  for (final c in contributions) {
    saved[c.date.year] = (saved[c.date.year] ?? 0) + c.amount;
  }

  final years = <int>{...income.keys, ...spent.keys, ...saved.keys}.toList()
    ..sort((a, b) => b - a);

  return [
    for (final y in years)
      PeriodSummary(
        year: y,
        month: null,
        income: income[y] ?? 0,
        spent: spent[y] ?? 0,
        saved: saved[y] ?? 0,
      ),
  ];
}
