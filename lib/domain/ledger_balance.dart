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
  final List<DebtMovementRow> debts;

  const LedgerInputs({
    required this.rows,
    required this.contributions,
    required this.investments,
    required this.debts,
  });
}

/// Money into and out of the tracked balance.
class LedgerTotals {
  /// Income, plus money that came in without being income: a repayment of
  /// money you lent, or money you borrowed (when the totals include it).
  final double inflows;

  /// Spending; money moved into savings or investments from the balance (a
  /// savings withdrawal back to the balance counts here as a negative); money
  /// lent; and repayments of money you borrowed (when included). External
  /// entries — money that never passed through the tracked balance — are not
  /// counted anywhere.
  final double outflows;

  const LedgerTotals({required this.inflows, required this.outflows});

  double get balance => inflows - outflows;
}

/// [LedgerTotals] over everything, or only entries dated strictly before
/// [before] when it is given. [includeBorrowed] false leaves borrowed money
/// out entirely — see [spendableTotals].
LedgerTotals ledgerTotals(
  LedgerInputs l, {
  DateTime? before,
  bool includeBorrowed = true,
}) {
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
  for (final d in l.debts) {
    final m = d.movement;
    if (m.external || !counts(m.date)) continue;
    final borrowed = d.debt.direction == DebtDirection.borrowed;
    if (borrowed && !includeBorrowed) continue;
    // What the movement did to the balance: lending takes money out (and a
    // repayment of it, being negative, brings money back); borrowing brings
    // money in (and repaying it takes money out).
    final effect = borrowed ? m.amount : -m.amount;
    // Filed by direction of travel, not by debt: money leaving is an outflow
    // and money arriving an inflow. That is what lets the weekly freeze below
    // treat a repayment you make like any other money leaving.
    if (effect < 0) {
      outflows -= effect;
    } else {
      inflows += effect;
    }
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
double balanceAtWeekStart(
  LedgerInputs l,
  DateTime weekStart, {
  bool includeBorrowed = true,
}) =>
    ledgerTotals(l, includeBorrowed: includeBorrowed).inflows -
    ledgerTotals(l, before: weekStart, includeBorrowed: includeBorrowed)
        .outflows;

/// What is yours to spend: the balance as if you had never borrowed.
///
/// Borrowed money really is in the account, so «الرصيد» shows it. But it is
/// owed, and the figures that tell you how much you can spend — «المتبقي» and
/// the weekly budget — must not hand it out as spending money (the
/// maintainer's decision, plan 029). Leaving borrowed movements out entirely
/// is the same as "balance − what you still owe", and it also keeps the weekly
/// budget still for the whole week: borrowing raises nothing, and repaying
/// lowers nothing, because neither is spending.
LedgerTotals spendableTotals(LedgerInputs l, {DateTime? before}) =>
    ledgerTotals(l, before: before, includeBorrowed: false);

/// [balanceAtWeekStart] for [spendableTotals].
double spendableAtWeekStart(LedgerInputs l, DateTime weekStart) =>
    balanceAtWeekStart(l, weekStart, includeBorrowed: false);

/// What each debt still stands at, by debt id: positive means still owed
/// (to you for money lent, by you for money borrowed). External movements
/// count here — a loan from before you used the app is still owed.
Map<int, double> debtOutstanding(List<DebtMovementRow> debts) {
  final out = <int, double>{};
  for (final d in debts) {
    out[d.debt.id] = (out[d.debt.id] ?? 0) + d.movement.amount;
  }
  return out;
}
