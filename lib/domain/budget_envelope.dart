import '../data/database.dart';
import '../data/enums.dart';
import 'financial_period.dart';
import 'spending_window.dart';

/// The month's disposable income, broken into its parts: the [salary] (largest
/// active recurring income, monthly-equivalent), the [obligations] (every active
/// recurring expense, monthly-equivalent), and what's been [saved] this cycle.
///
/// [disposable] — salary minus obligations minus savings — is the single
/// spendable figure both the weekly budget and the budget advisor size
/// themselves against, so they can never disagree about how much money is
/// actually free to spend.
class MonthlyEnvelope {
  final double salary;
  final double obligations;
  final double saved;
  const MonthlyEnvelope({
    required this.salary,
    required this.obligations,
    required this.saved,
  });

  double get disposable => salary - obligations - saved;
}

/// Computes the [MonthlyEnvelope] from the live rules and contributions. Savings
/// count only what was set aside *this cycle* (external deposits already existed,
/// so they aren't fresh savings). Same salary anchor and monthly normalisation
/// [financialPeriod] and the weekly budget use.
MonthlyEnvelope monthlyEnvelope({
  required List<RecurrenceRule> incomeRules,
  required List<RecurrenceRule> expenseRules,
  required List<SavingsContribution> contributions,
  required FinancialPeriod period,
}) {
  // Salary = the largest active recurring income, as a monthly figure.
  RecurrenceRule? salary;
  for (final r in incomeRules) {
    if (r.type != TxnType.income || !r.active) continue;
    if (salary == null || r.amount > salary.amount) salary = r;
  }
  final salaryMonthly = salary == null
      ? 0.0
      : monthlyEquivalent(salary.frequency, salary.amount, salary.interval);

  // Obligations = every active recurring expense, as a monthly figure.
  var obligationsMonthly = 0.0;
  for (final r in expenseRules) {
    if (r.type != TxnType.expense || !r.active) continue;
    obligationsMonthly += monthlyEquivalent(r.frequency, r.amount, r.interval);
  }

  // Money actually set aside this cycle (internal contributions only).
  var saved = 0.0;
  for (final c in contributions) {
    if (!c.external && period.contains(c.date)) saved += c.amount;
  }

  return MonthlyEnvelope(
    salary: salaryMonthly,
    obligations: obligationsMonthly,
    saved: saved,
  );
}
