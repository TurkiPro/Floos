import '../data/database.dart'; // TxnRow, SavingsContribution
import '../data/enums.dart'; // TxnType
import 'financial_period.dart';
import 'ledger_balance.dart';

/// Everything the home dashboard shows, computed once from the two streams.
/// [balance] is money neither spent nor set aside: all income − all expenses
/// − all savings. The monthly figures split this month's income into what's
/// left, what was spent, and what was saved.
class DashboardSummary {
  final double balance;
  final double savingsTotal;

  /// Everything put into investments (a manual portfolio) — the counterpart to
  /// [savingsTotal]. Non-external investments are subtracted from [balance] too.
  final double investedTotal;
  final double monthRemaining;
  final double monthSpent;
  final double monthSaved;
  final List<TxnRow> monthExpenses;
  // Whether any income landed this month -- the trigger for the savings prompt.
  final bool incomeReceivedThisMonth;

  const DashboardSummary({
    required this.balance,
    required this.savingsTotal,
    required this.investedTotal,
    required this.monthRemaining,
    required this.monthSpent,
    required this.monthSaved,
    required this.monthExpenses,
    required this.incomeReceivedThisMonth,
  });

  factory DashboardSummary.from(
    List<TxnRow> rows,
    List<SavingsContribution> contributions,
    List<Investment> investments,
    FinancialPeriod period,
  ) {
    // "This month" here means the current salary cycle (see FinancialPeriod),
    // so the salary you were just paid counts toward the period you're in.
    bool inMonth(DateTime d) => period.contains(d);

    double monthIncome = 0, monthSpent = 0;
    var incomeThisMonth = false;
    final monthExpenses = <TxnRow>[];
    for (final r in rows) {
      final amount = r.txn.amount;
      if (r.txn.type == TxnType.income) {
        if (inMonth(r.txn.date)) {
          monthIncome += amount;
          incomeThisMonth = true;
        }
      } else {
        if (inMonth(r.txn.date)) {
          monthSpent += amount;
          monthExpenses.add(r);
        }
      }
    }

    // External deposits (money that already existed) count toward the total
    // saved but never reduce the balance or this period's income split.
    double allSaved = 0, monthSaved = 0;
    for (final c in contributions) {
      allSaved += c.amount;
      if (c.external) continue;
      if (inMonth(c.date)) monthSaved += c.amount;
    }

    // Investments mirror savings: money moved into a portfolio, not spent. A
    // non-external entry comes out of the balance; a standalone (external) one
    // is pre-existing money that doesn't.
    double investedTotal = 0;
    for (final inv in investments) {
      investedTotal += inv.amount;
    }

    final balance = ledgerTotals(LedgerInputs(
      rows: rows,
      contributions: contributions,
      investments: investments,
    )).balance;

    // What this cycle's own income has left, before any reckoning with the
    // past.
    final cycleRemaining = monthIncome - monthSpent - monthSaved;

    // Capped at the real balance, exactly as the weekly budget is (see
    // weekly_budget_status.dart). A deficit carried in from last cycle is paid
    // off by the new salary the moment it lands, so that much of the salary is
    // already spoken for and was never "remaining". Uncapped, the card insists
    // the full salary is untouched while the balance below it says otherwise —
    // and it errs by claiming more money exists than does, which is the
    // dangerous direction for a budgeting app.
    //
    // Only caps once income has landed: before payday "remaining" is just this
    // cycle's spending so far, and the balance is a different quantity (it
    // still holds last cycle's leftovers) that would drag the figure somewhere
    // meaningless. Same guard the weekly budget uses.
    //
    // A carried-in SURPLUS is deliberately not added. This card splits the
    // cycle's income into left/spent/saved; money from previous cycles is real
    // but it is not this cycle's income, and «الرصيد» above already shows it.
    final monthRemaining =
        monthIncome > 0 && balance < cycleRemaining ? balance : cycleRemaining;

    return DashboardSummary(
      balance: balance,
      savingsTotal: allSaved,
      investedTotal: investedTotal,
      monthRemaining: monthRemaining,
      monthSpent: monthSpent,
      monthSaved: monthSaved,
      monthExpenses: monthExpenses,
      incomeReceivedThisMonth: incomeThisMonth,
    );
  }
}
