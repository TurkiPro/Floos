import '../data/database.dart';
import '../data/enums.dart';

/// The one place the balance — «الرصيد», money neither spent nor set aside —
/// is computed. The home card, the weekly budget's cap and the statistics
/// screen all come through here.
///
/// It used to be written out separately in [DashboardSummary] and in
/// `weeklyBudgetStatus`, and keeping the copies in step is how investments
/// once reached the home card but not the statistics screen. A ledger that
/// moves the balance is added here, once.
///
/// Every field is required with no default, deliberately: a defaulted list is
/// exactly how a caller silently left investments out. Adding a ledger here
/// makes the compiler point at every call site.
class LedgerInputs {
  final List<TxnRow> rows;
  final List<SavingsContribution> contributions;
  final List<Investment> investments;

  const LedgerInputs({
    required this.rows,
    required this.contributions,
    required this.investments,
  });
}

/// Money into and out of the tracked balance.
class LedgerTotals {
  /// Income.
  final double inflows;

  /// Spending, plus money moved into savings or investments from the balance
  /// (a savings withdrawal back to the balance counts here as a negative).
  /// External entries — money that never passed through the tracked balance —
  /// are not counted.
  final double outflows;

  const LedgerTotals({required this.inflows, required this.outflows});

  double get balance => inflows - outflows;
}

/// [LedgerTotals] over everything, or only entries dated strictly before
/// [before] when it is given.
LedgerTotals ledgerTotals(LedgerInputs l, {DateTime? before}) {
  bool counts(DateTime d) => before == null || d.isBefore(before);

  var inflows = 0.0, outflows = 0.0;
  for (final r in l.rows) {
    if (!counts(r.txn.date)) continue;
    if (r.txn.type == TxnType.income) {
      inflows += r.txn.amount;
    } else {
      outflows += r.txn.amount;
    }
  }
  for (final c in l.contributions) {
    if (c.external || !counts(c.date)) continue;
    outflows += c.amount;
  }
  for (final inv in l.investments) {
    if (inv.external || !counts(inv.date)) continue;
    outflows += inv.amount;
  }
  return LedgerTotals(inflows: inflows, outflows: outflows);
}

/// The balance the weekly budget is capped by: everything that has come in so
/// far, less what had gone out by the start of the week.
///
/// Outflows are frozen to [weekStart] so spending during the week moves what
/// has been spent, never the budget it is measured against. Income is not
/// frozen: a salary or bonus landing mid-week is rare, only ever raises the
/// figure, and would be strange to withhold until the following week.
double balanceAtWeekStart(LedgerInputs l, DateTime weekStart) =>
    ledgerTotals(l).inflows - ledgerTotals(l, before: weekStart).outflows;
