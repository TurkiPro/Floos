import '../data/database.dart';
import '../data/enums.dart';
import 'budget_advisor.dart' show previousCycles;
import 'financial_period.dart';

/// One salary cycle's savings, for the per-cycle trend chart.
class SavingsCyclePoint {
  final DateTime cycleStart;

  /// Net internal saving that cycle — deposits minus withdrawals. Can be
  /// negative (a cycle you pulled more out than you put in).
  final double saved;

  /// Income that landed that cycle, for the savings rate.
  final double income;

  /// The in-progress current cycle (drawn distinctly in the chart).
  final bool current;

  const SavingsCyclePoint({
    required this.cycleStart,
    required this.saved,
    required this.income,
    this.current = false,
  });
}

/// A read of the user's saving habits, all salary-cycle aligned (same cycles as
/// the rest of the app). "Saving" means *internal* contributions only — external
/// deposits are money that already existed (an import), not a habit — and a
/// negative contribution is a withdrawal. Pure and testable.
class SavingsBehavior {
  final double savedThisCycle;

  /// Fraction of this cycle's income set aside (null with no income yet).
  final double? rateThisCycle;

  /// The median of that fraction across past active cycles — your norm.
  final double? usualRate;

  /// Median net saved per past active cycle.
  final double medianPerCycle;

  /// Consecutive cycles (most recent, current included when positive) you saved.
  final int streak;

  /// Of the [consistencyTotal] past active cycles, how many you saved in.
  final int consistencySaved;
  final int consistencyTotal;

  /// Your best net-positive cycle (0 / null when you've never ended a cycle up).
  final double bestCycleAmount;
  final DateTime? bestCycleStart;

  /// Gross money pulled from savings over the window, and how many cycles ended
  /// net-negative.
  final double withdrawnRecently;
  final int withdrawalCycles;

  /// Oldest → newest, for the bar chart.
  final List<SavingsCyclePoint> trend;

  const SavingsBehavior({
    required this.savedThisCycle,
    required this.rateThisCycle,
    required this.usualRate,
    required this.medianPerCycle,
    required this.streak,
    required this.consistencySaved,
    required this.consistencyTotal,
    required this.bestCycleAmount,
    required this.bestCycleStart,
    required this.withdrawnRecently,
    required this.withdrawalCycles,
    required this.trend,
  });

  /// Enough past cycles to talk about norms/streaks; false for a brand-new user.
  bool get hasHistory => consistencyTotal > 0;
}

double _median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

SavingsBehavior savingsBehavior({
  required List<SavingsContribution> contributions,
  required List<TxnRow> rows,
  required List<RecurrenceRule> incomeRules,
  required DateTime now,
  int maxCycles = 6,
}) {
  final current = financialPeriod(incomeRules, now);
  final past = previousCycles(incomeRules, now, maxCycles); // most recent first

  double savedIn(FinancialPeriod p) {
    var s = 0.0;
    for (final c in contributions) {
      if (!c.external && p.contains(c.date)) s += c.amount;
    }
    return s;
  }

  double withdrawnIn(FinancialPeriod p) {
    var s = 0.0;
    for (final c in contributions) {
      if (!c.external && p.contains(c.date) && c.amount < 0) s += -c.amount;
    }
    return s;
  }

  double incomeIn(FinancialPeriod p) {
    var s = 0.0;
    for (final r in rows) {
      if (r.txn.type == TxnType.income && p.contains(r.txn.date)) {
        s += r.txn.amount;
      }
    }
    return s;
  }

  // A cycle "counts" once the user was actually using the app in it — otherwise
  // cycles predating their first entry would read as missed savings.
  bool active(FinancialPeriod p) {
    for (final r in rows) {
      if (p.contains(r.txn.date)) return true;
    }
    for (final c in contributions) {
      if (p.contains(c.date)) return true;
    }
    return false;
  }

  final savedThisCycle = savedIn(current);
  final incomeThisCycle = incomeIn(current);
  final rateThisCycle =
      incomeThisCycle > 0 ? savedThisCycle / incomeThisCycle : null;

  final activePast = [
    for (final p in past)
      if (active(p)) p
  ];

  final perCycleSaved = [for (final p in activePast) savedIn(p)];
  final medianPerCycle = _median(perCycleSaved);

  final rates = <double>[];
  for (final p in activePast) {
    final inc = incomeIn(p);
    if (inc > 0) rates.add(savedIn(p) / inc);
  }
  final usualRate = rates.isEmpty ? null : _median(rates);

  // Streak: the current cycle counts only when already positive (an empty
  // in-progress cycle mustn't reset it), then walk back through completed cycles
  // until one wasn't saved — or we hit pre-history.
  var streak = savedThisCycle > 0 ? 1 : 0;
  for (final p in past) {
    if (!active(p)) break;
    if (savedIn(p) > 0) {
      streak++;
    } else {
      break;
    }
  }

  final consistencyTotal = activePast.length;
  final consistencySaved = perCycleSaved.where((v) => v > 0).length;

  var bestAmount = 0.0;
  DateTime? bestStart;
  for (final p in activePast) {
    final v = savedIn(p);
    if (v > bestAmount) {
      bestAmount = v;
      bestStart = p.start;
    }
  }

  var withdrawn = withdrawnIn(current);
  var withdrawalCycles = savedThisCycle < 0 ? 1 : 0;
  for (final p in activePast) {
    withdrawn += withdrawnIn(p);
    if (savedIn(p) < 0) withdrawalCycles++;
  }

  final trend = <SavingsCyclePoint>[
    for (final p in activePast.reversed)
      SavingsCyclePoint(
          cycleStart: p.start, saved: savedIn(p), income: incomeIn(p)),
    SavingsCyclePoint(
        cycleStart: current.start,
        saved: savedThisCycle,
        income: incomeThisCycle,
        current: true),
  ];

  return SavingsBehavior(
    savedThisCycle: savedThisCycle,
    rateThisCycle: rateThisCycle,
    usualRate: usualRate,
    medianPerCycle: medianPerCycle,
    streak: streak,
    consistencySaved: consistencySaved,
    consistencyTotal: consistencyTotal,
    bestCycleAmount: bestAmount,
    bestCycleStart: bestStart,
    withdrawnRecently: withdrawn,
    withdrawalCycles: withdrawalCycles,
    trend: trend,
  );
}
