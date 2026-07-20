import '../data/database.dart'; // TxnRow, SavingsContribution
import '../data/enums.dart'; // TxnType
import 'financial_period.dart';

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

    double allIncome = 0, allExpense = 0, monthIncome = 0, monthSpent = 0;
    var incomeThisMonth = false;
    final monthExpenses = <TxnRow>[];
    for (final r in rows) {
      final amount = r.txn.amount;
      if (r.txn.type == TxnType.income) {
        allIncome += amount;
        if (inMonth(r.txn.date)) {
          monthIncome += amount;
          incomeThisMonth = true;
        }
      } else {
        allExpense += amount;
        if (inMonth(r.txn.date)) {
          monthSpent += amount;
          monthExpenses.add(r);
        }
      }
    }

    // External deposits (money that already existed) count toward the total
    // saved but never reduce the balance or this period's income split.
    double allSaved = 0, internalSaved = 0, monthSaved = 0;
    for (final c in contributions) {
      allSaved += c.amount;
      if (c.external) continue;
      internalSaved += c.amount;
      if (inMonth(c.date)) monthSaved += c.amount;
    }

    // Investments mirror savings: money moved into a portfolio, not spent. A
    // non-external entry comes out of the balance; a standalone (external) one
    // is pre-existing money that doesn't.
    double investedTotal = 0, internalInvested = 0;
    for (final inv in investments) {
      investedTotal += inv.amount;
      if (!inv.external) internalInvested += inv.amount;
    }

    return DashboardSummary(
      balance: allIncome - allExpense - internalSaved - internalInvested,
      savingsTotal: allSaved,
      investedTotal: investedTotal,
      monthRemaining: monthIncome - monthSpent - monthSaved,
      monthSpent: monthSpent,
      monthSaved: monthSaved,
      monthExpenses: monthExpenses,
      incomeReceivedThisMonth: incomeThisMonth,
    );
  }
}
