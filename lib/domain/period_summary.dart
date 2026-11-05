import '../data/database.dart';
import '../data/enums.dart';
import 'budget_advisor.dart' show cyclesCovering;
import 'financial_period.dart';

/// How one salary cycle behaved: its window plus income/spent/saved, carrying
/// the [FinancialPeriod] so callers can label it (a month name, or a date range
/// when it straddles two).
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

/// How many salary cycles make up one "year" in the behaviour view.
const cyclesPerYear = 12;

/// Twelve consecutive salary cycles taken together — the app's "year". Never a
/// calendar year: a calendar year cuts a cycle in two at January, so its first
/// and last months each carry half a salary's worth of spending.
class CycleYearSummary {
  /// From the start of the block's oldest cycle to the end of its newest.
  final FinancialPeriod period;

  /// How many cycles the block spans — twelve, except for the oldest block,
  /// which stops where the history does.
  final int cycleCount;

  /// The block holding the current cycle, so still under way.
  final bool inProgress;

  final double income;
  final double spent;
  final double saved;

  const CycleYearSummary({
    required this.period,
    required this.cycleCount,
    required this.inProgress,
    required this.income,
    required this.spent,
    required this.saved,
  });

  double get remaining => income - spent - saved;
  double? get savingsRate => income > 0 ? saved / income : null;
}

/// The history in blocks of [cyclesPerYear] salary cycles, newest first,
/// counted back from the current cycle — so the newest block is exactly the
/// twelve cycles the year review shows. Blocks with no activity are skipped.
///
/// Totals follow the same rules as [cycleSummaries]: every transaction in the
/// window, and savings contributions that came out of the balance.
List<CycleYearSummary> cycleYearSummaries(
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
  final out = <CycleYearSummary>[];
  for (var i = 0; i < cycles.length; i += cyclesPerYear) {
    final block = cycles.sublist(i,
        i + cyclesPerYear > cycles.length ? cycles.length : i + cyclesPerYear);
    final period = FinancialPeriod(block.last.start, block.first.end);
    var income = 0.0, spent = 0.0, saved = 0.0;
    var active = false;
    for (final r in rows) {
      if (!period.contains(r.txn.date)) continue;
      active = true;
      if (r.txn.type == TxnType.income) {
        income += r.txn.amount;
      } else {
        spent += r.txn.amount;
      }
    }
    for (final c in contributions) {
      if (c.external || !period.contains(c.date)) continue;
      active = true;
      saved += c.amount;
    }
    if (!active) continue;
    out.add(CycleYearSummary(
      period: period,
      cycleCount: block.length,
      inProgress: i == 0,
      income: income,
      spent: spent,
      saved: saved,
    ));
  }
  return out;
}
