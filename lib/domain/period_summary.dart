import '../data/database.dart';
import '../data/enums.dart';
import 'budget_advisor.dart' show cyclesCovering;
import 'date_grouping.dart';
import 'financial_period.dart';

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

/// How one salary cycle behaved: its window plus income/spent/saved. The
/// cycle-based counterpart of [PeriodSummary], carrying the [FinancialPeriod] so
/// callers can label it (a month name, or a date range when it straddles two).
class CycleSummary {
  final FinancialPeriod period;
  final double income;
  final double spent;
  final double saved;
  const CycleSummary({
    required this.period,
    required this.income,
    required this.spent,
    required this.saved,
  });

  double get remaining => income - spent - saved;
  double? get savingsRate => income > 0 ? saved / income : null;
}

/// One summary per salary cycle that has any activity, newest first — the
/// cycle-based history the whole app browses by (never the calendar month).
List<CycleSummary> cycleSummaries(
  List<TxnRow> rows,
  List<SavingsContribution> contributions,
  List<RecurrenceRule> incomeRules,
  DateTime now,
) {
  DateTime? earliest;
  void see(DateTime d) {
    if (earliest == null || d.isBefore(earliest!)) earliest = d;
  }

  for (final r in rows) {
    see(r.txn.date);
  }
  for (final c in contributions) {
    if (!c.external) see(c.date);
  }
  if (earliest == null) return const [];

  final cycles = cyclesCovering(incomeRules, earliest!, now); // newest first
  final out = <CycleSummary>[];
  for (final p in cycles) {
    var income = 0.0, spent = 0.0, saved = 0.0;
    var active = false;
    for (final r in rows) {
      if (!p.contains(r.txn.date)) continue;
      active = true;
      if (r.txn.type == TxnType.income) {
        income += r.txn.amount;
      } else {
        spent += r.txn.amount;
      }
    }
    for (final c in contributions) {
      if (c.external || !p.contains(c.date)) continue;
      active = true;
      saved += c.amount;
    }
    // Skip cycles with no activity at all (a gap between the user's active
    // cycles must not appear as an empty row).
    if (active) {
      out.add(
          CycleSummary(period: p, income: income, spent: spent, saved: saved));
    }
  }
  return out;
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
    // External deposits (pre-existing money) aren't income saved in a period.
    if (c.external) continue;
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
    if (c.external) continue;
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
