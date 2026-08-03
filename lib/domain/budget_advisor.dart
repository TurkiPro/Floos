import '../data/database.dart';
import '../data/enums.dart';
import 'budget_envelope.dart';
import 'financial_period.dart';
import 'recurrence_math.dart';

/// Where a suggested budget came from — drives the label on the budgets screen.
enum BudgetSuggestionBasis { fromIncome, fromHistory }

/// A proposed monthly budget for one top-level expense category, ready to apply
/// with a single tap. The "spent" side is never involved — this is only the
/// target the advisor recommends.
class BudgetSuggestion {
  final int categoryId;
  final double amount;
  final BudgetSuggestionBasis basis;

  /// How many completed cycles the history median was taken over; 0 for the
  /// income seed.
  final int cyclesUsed;

  const BudgetSuggestion({
    required this.categoryId,
    required this.amount,
    required this.basis,
    required this.cyclesUsed,
  });
}

// --- tuning constants -------------------------------------------------------

// The classic 50/30/20 split for the day-one seed: half of income covers needs
// (essentials), ~30% covers wants (luxuries); the remaining ~20% is left for
// savings and is never budgeted here.
const double _needsShare = 0.50;
const double _wantsShare = 0.30;

// Round every suggestion to a friendly step so it reads as a deliberate target
// (1,720) rather than a raw average (1,713.44).
const double _roundStep = 10;

double _roundFriendly(double v) => (v / _roundStep).round() * _roundStep;

/// Median of a list (average of the two middle values for even length). Robust
/// to a single spike in a way a mean isn't — one 3,000 ⃁ flight shouldn't
/// permanently inflate the "travel" budget.
double _median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// The "salary": the largest active recurring income, same anchor
/// [financialPeriod] uses to define the cycle.
RecurrenceRule? _salaryRule(List<RecurrenceRule> incomeRules) {
  RecurrenceRule? salary;
  for (final r in incomeRules) {
    if (r.type != TxnType.income || !r.active) continue;
    if (salary == null || r.amount > salary.amount) salary = r;
  }
  return salary;
}

/// Best estimate of monthly recurring income for the day-one seed: the sum of
/// active monthly income rules, or — if none are monthly — the largest active
/// recurring income as a proxy. Zero when there's no recurring income at all.
double _monthlyIncome(List<RecurrenceRule> incomeRules) {
  var monthlySum = 0.0;
  RecurrenceRule? largest;
  for (final r in incomeRules) {
    if (r.type != TxnType.income || !r.active) continue;
    if (largest == null || r.amount > largest.amount) largest = r;
    if (r.frequency == Frequency.monthly && r.interval == 1) {
      monthlySum += r.amount;
    }
  }
  if (monthlySum > 0) return monthlySum;
  return largest?.amount ?? 0;
}

/// The last [maxCycles] *completed* financial cycles, ending at the current
/// period's start and stepping back one salary cadence at a time — most recent
/// first. Anchoring on the CURRENT cycle start (not the salary's scheduled grid)
/// means an early or late payday shifts every boundary together, so the last
/// completed cycle is never dropped just because this payday came a couple of
/// days off schedule. Falls back to whole calendar months when there is no
/// recurring income.
List<FinancialPeriod> previousCycles(
    List<RecurrenceRule> incomeRules, DateTime now, int maxCycles) {
  final current = financialPeriod(incomeRules, now);
  final salary = _salaryRule(incomeRules);
  final freq = salary?.frequency ?? Frequency.monthly;
  final interval = salary == null || salary.interval < 1 ? 1 : salary.interval;
  final anchor = dateOnly(current.start);
  return [
    for (var i = 1; i <= maxCycles; i++)
      FinancialPeriod(
        _minusPeriods(anchor, freq, interval, i),
        _minusPeriods(anchor, freq, interval, i - 1),
      ),
  ];
}

/// Every salary cycle from the one containing [earliest] up to and including the
/// current cycle — newest first — so history can be browsed by cycle instead of
/// by calendar month. Boundaries step back one salary cadence at a time from the
/// current cycle's start (an early/late payday shifts them all together); falls
/// back to whole calendar months when there's no recurring income.
List<FinancialPeriod> cyclesCovering(
    List<RecurrenceRule> incomeRules, DateTime earliest, DateTime now) {
  final current = financialPeriod(incomeRules, now);
  final salary = _salaryRule(incomeRules);
  final freq = salary?.frequency ?? Frequency.monthly;
  final interval = salary == null || salary.interval < 1 ? 1 : salary.interval;
  final earliestDay = dateOnly(earliest);
  final out = <FinancialPeriod>[current];
  var anchor = dateOnly(current.start);
  var guard = 0;
  while (anchor.isAfter(earliestDay) && guard++ < 1200) {
    final start = _minusPeriods(anchor, freq, interval, 1);
    out.add(FinancialPeriod(start, anchor));
    anchor = start;
  }
  return out;
}

/// [d] shifted back by [k] whole periods of [freq]×[interval]. DateTime's
/// constructor normalises any month/day overflow.
DateTime _minusPeriods(DateTime d, Frequency freq, int interval, int k) {
  final step = interval * k;
  switch (freq) {
    case Frequency.daily:
      return DateTime(d.year, d.month, d.day - step);
    case Frequency.weekly:
      return DateTime(d.year, d.month, d.day - 7 * step);
    case Frequency.monthly:
      return DateTime(d.year, d.month - step, d.day);
    case Frequency.yearly:
      return DateTime(d.year - step, d.month, d.day);
  }
}

/// Suggests a monthly budget per top-level expense category.
///
/// Budgets describe **discretionary** money only — the spending you decide on in
/// the moment. Committed obligations (rows generated by a recurring rule: rent,
/// subscriptions, family transfers) are excluded here and shown on their own
/// line, so a category's budget can't be blown by an obligation you never chose.
///
/// - **Once there's spending history** (at least one completed cycle contains
///   discretionary spend), each category's suggestion starts from the median of
///   its own discretionary spend across those cycles — sub-categories roll up to
///   their parent, exactly like `budgetProgress`. A category never spent on gets
///   no suggestion. The in-progress current cycle is excluded so a half-month
///   can't lowball it. The medians are then fitted inside the disposable
///   envelope (`salary − commitments − savings`, the same figure the weekly
///   budget uses): when they overshoot it, luxuries are trimmed before
///   essentials, and essentials only scale down once they alone exceed it.
/// - **Day one** (no history yet), every category is seeded from known recurring
///   income via a 50/30/20 split — essentials share the needs pool, luxuries the
///   wants pool — scaled by [lifestyleFactor]. With no recurring income there is
///   nothing to seed from, so the result is empty.
List<BudgetSuggestion> suggestBudgets({
  required List<TxnRow> rows,
  required List<Category> topExpenseCats,
  required List<RecurrenceRule> incomeRules,
  required List<RecurrenceRule> expenseRules,
  required List<SavingsContribution> contributions,
  required DateTime now,
  required double lifestyleFactor,
  int maxCycles = 6,
}) {
  final cycles = previousCycles(incomeRules, now, maxCycles);

  // cycleIndex -> topCategoryId -> summed DISCRETIONARY expense. Committed
  // (recurring) rows are skipped; sub-category spend rolls up to its parent,
  // matching budget_progress.
  final spentPerCycle = <int, Map<int, double>>{
    for (var ci = 0; ci < cycles.length; ci++) ci: {},
  };
  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
    if (r.txn.recurrenceId != null) continue; // committed -> not budgeted
    for (var ci = 0; ci < cycles.length; ci++) {
      if (cycles[ci].contains(r.txn.date)) {
        final topId = r.category.parentId ?? r.category.id;
        spentPerCycle[ci]![topId] =
            (spentPerCycle[ci]![topId] ?? 0) + r.txn.amount;
        break;
      }
    }
  }
  // A cycle only counts if it actually contains spending — a cycle predating the
  // user's first transaction must not drag a median down to zero.
  final activeCycles = [
    for (var ci = 0; ci < cycles.length; ci++)
      if (spentPerCycle[ci]!.isNotEmpty) ci,
  ];

  // Day one: no history at all -> seed every category from income.
  if (activeCycles.isEmpty) {
    return _incomeSeed(topExpenseCats, incomeRules, lifestyleFactor);
  }

  // Established: each category's own median discretionary spend across the active
  // cycles, before fitting them to what the salary allows.
  final want = <int, double>{};
  for (final cat in topExpenseCats) {
    final perCycle = [
      for (final ci in activeCycles) spentPerCycle[ci]![cat.id] ?? 0.0,
    ];
    final m = _median(perCycle);
    if (m > 0) want[cat.id] = m; // never spent on -> no suggestion
  }
  if (want.isEmpty) return const [];

  // Fit the medians inside the disposable envelope (salary − commitments −
  // savings), trimming luxuries before essentials when they overshoot.
  final disposable = monthlyEnvelope(
    incomeRules: incomeRules,
    expenseRules: expenseRules,
    contributions: contributions,
    period: financialPeriod(incomeRules, now),
  ).disposable;
  final kindOf = {for (final c in topExpenseCats) c.id: c.kind};
  final scaled = _fitToEnvelope(want, kindOf, disposable);

  final out = <BudgetSuggestion>[];
  for (final cat in topExpenseCats) {
    final raw = scaled[cat.id];
    if (raw == null) continue;
    final amount = _roundFriendly(raw);
    if (amount <= 0) continue; // trimmed to nothing -> no suggestion
    out.add(BudgetSuggestion(
      categoryId: cat.id,
      amount: amount,
      basis: BudgetSuggestionBasis.fromHistory,
      cyclesUsed: activeCycles.length,
    ));
  }
  return out;
}

/// Scales the per-category [want] amounts so their total fits [disposable],
/// trimming luxuries before essentials. Essentials are kept whole until they
/// alone exceed the envelope, at which point luxuries fall to zero and the
/// essentials scale down to fit. When the wants already fit — or there's no
/// positive envelope to fit them to — they pass through unchanged.
Map<int, double> _fitToEnvelope(
    Map<int, double> want, Map<int, CategoryKind> kindOf, double disposable) {
  final total = want.values.fold(0.0, (a, b) => a + b);
  if (disposable <= 0 || total <= disposable) return want;

  var needs = 0.0, wants = 0.0;
  want.forEach((id, v) {
    if (kindOf[id] == CategoryKind.luxury) {
      wants += v;
    } else {
      needs += v;
    }
  });

  final out = <int, double>{};
  if (needs >= disposable) {
    // Essentials alone don't fit: luxuries get nothing, essentials scale to fit.
    final f = needs > 0 ? disposable / needs : 0.0;
    want.forEach((id, v) {
      out[id] = kindOf[id] == CategoryKind.luxury ? 0.0 : v * f;
    });
  } else {
    // Essentials kept whole; luxuries share whatever's left.
    final leftForWants = disposable - needs;
    final f = wants > 0 ? leftForWants / wants : 0.0;
    want.forEach((id, v) {
      out[id] = kindOf[id] == CategoryKind.luxury ? v * f : v;
    });
  }
  return out;
}

List<BudgetSuggestion> _incomeSeed(
  List<Category> cats,
  List<RecurrenceRule> incomeRules,
  double lifestyleFactor,
) {
  final monthlyIncome = _monthlyIncome(incomeRules);
  if (monthlyIncome <= 0) return const [];

  final essentials = cats.where((c) => c.kind == CategoryKind.essential).length;
  final luxuries = cats.where((c) => c.kind == CategoryKind.luxury).length;
  final needsEach =
      essentials == 0 ? 0.0 : monthlyIncome * _needsShare / essentials;
  final wantsEach =
      luxuries == 0 ? 0.0 : monthlyIncome * _wantsShare / luxuries;

  final out = <BudgetSuggestion>[];
  for (final c in cats) {
    final pool = c.kind == CategoryKind.essential ? needsEach : wantsEach;
    final amount = _roundFriendly(pool * lifestyleFactor);
    if (amount <= 0) continue;
    out.add(BudgetSuggestion(
      categoryId: c.id,
      amount: amount,
      basis: BudgetSuggestionBasis.fromIncome,
      cyclesUsed: 0,
    ));
  }
  return out;
}
