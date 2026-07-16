import '../data/database.dart';
import '../data/enums.dart';
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

/// The last [maxCycles] *completed* financial cycles ending on or before the
/// current period's start — most recent first. Anchored on the salary rule the
/// same way [financialPeriod] is; falls back to whole calendar months when
/// there is no recurring income (or it hasn't started yet).
List<FinancialPeriod> previousCycles(
    List<RecurrenceRule> incomeRules, DateTime now, int maxCycles) {
  final current = financialPeriod(incomeRules, now);
  final salary = _salaryRule(incomeRules);

  if (salary == null || dateOnly(salary.startDate).isAfter(current.start)) {
    // Calendar-month fallback: the [maxCycles] whole months before this one.
    return [
      for (var i = 1; i <= maxCycles; i++)
        FinancialPeriod(
          DateTime(current.start.year, current.start.month - i, 1),
          DateTime(current.start.year, current.start.month - i + 1, 1),
        ),
    ];
  }

  // Salary-anchored: collect occurrence dates up to and including the current
  // period start (which is itself an occurrence), then pair consecutive ones
  // into [start, end) windows, newest first.
  final base = dateOnly(salary.startDate);
  final occ = <DateTime>[];
  const safety = 100000;
  for (var n = 0; n < safety; n++) {
    final o = occurrence(
        freq: salary.frequency, interval: salary.interval, base: base, n: n);
    if (o.isAfter(current.start)) break;
    occ.add(o);
  }
  return [
    for (var i = occ.length - 1; i >= 1 && (occ.length - i) <= maxCycles; i--)
      FinancialPeriod(occ[i - 1], occ[i]),
  ];
}

/// Suggests a monthly budget per top-level expense category.
///
/// - **Once there's spending history** (at least one completed cycle contains
///   expenses), each category's suggestion is the median of its own spend across
///   those cycles — sub-categories roll up to their parent, exactly like
///   `budgetProgress`. A category never spent on gets no suggestion. The
///   in-progress current cycle is excluded so a half-month can't lowball it.
/// - **Day one** (no history yet), every category is seeded from known recurring
///   income via a 50/30/20 split — essentials share the needs pool, luxuries the
///   wants pool — scaled by [lifestyleFactor]. With no recurring income there is
///   nothing to seed from, so the result is empty.
List<BudgetSuggestion> suggestBudgets({
  required List<TxnRow> rows,
  required List<Category> topExpenseCats,
  required List<RecurrenceRule> incomeRules,
  required DateTime now,
  required double lifestyleFactor,
  int maxCycles = 6,
}) {
  final cycles = previousCycles(incomeRules, now, maxCycles);

  // cycleIndex -> topCategoryId -> summed expense. Sub-category spend rolls up
  // to its parent, matching budget_progress.
  final spentPerCycle = <int, Map<int, double>>{
    for (var ci = 0; ci < cycles.length; ci++) ci: {},
  };
  for (final r in rows) {
    if (r.txn.type != TxnType.expense) continue;
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

  // Established: median of each category's own spend across the active cycles.
  final out = <BudgetSuggestion>[];
  for (final cat in topExpenseCats) {
    final perCycle = [
      for (final ci in activeCycles) spentPerCycle[ci]![cat.id] ?? 0.0,
    ];
    final amount = _roundFriendly(_median(perCycle));
    if (amount <= 0) continue; // never spent on -> no suggestion
    out.add(BudgetSuggestion(
      categoryId: cat.id,
      amount: amount,
      basis: BudgetSuggestionBasis.fromHistory,
      cyclesUsed: activeCycles.length,
    ));
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
